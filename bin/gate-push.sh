#!/usr/bin/env sh
# gate-push.sh (harbor#1411) — run a repo's pre-push checks BEFORE git connects, then push in seconds.
#
#   sh bin/gate-push.sh [-u] [<remote>]   verify HEAD, record the pass, push the current branch to <remote>
#                                         (`gate-push` on PATH through contracts/shims.tsv, for any repo)
#   sh bin/gate-push.sh check <remote> <url>   the pre-push hook's first call; exit 0 = a recorded pass covers
#                                         this exact push and the hook may skip its checks, 1 = run them
#   sh bin/gate-push.sh fingerprint       print the check-set manifest the pass is bound to
#
# WHY. git takes the GitHub App token when `git push` connects, runs pre-push, then sends the pack with that token.
# The token can have as little as ~11 minutes left (hooks/access-confinement), so a long pre-push (a 29-minute
# `just fast-ci`, harbor's linter under load) ends in "RPC failed; HTTP 401" and a full re-run. Here the checks run
# under `git push --dry-run`, which runs the same hook with the same stdin and sends nothing after it, and the real
# push then finds the pass and skips.
#
# THE SKIP IS NARROW. The hook skips only when a record exists for the pushed sha, its tag authenticates over the
# remote, the exact stdin line, the fingerprint and its time, the fingerprint equals the current check set, and it
# is under HARBOR_GATE_PUSH_TTL seconds old (default 3600). Every other case runs the full checks, and says why.
#
# THE FINGERPRINT is the hook git resolves (core.hooksPath honoured, symlinks followed) plus what the hook declares
# in `# gate-push: file|env|cmd …` lines: files beside the hook, env vars that change the check set, and commands
# whose output is part of it (`just --show fast-ci`). In-tree inputs are pinned by the sha: verify refuses a tree
# with uncommitted tracked changes.
#
# WHY A HAND-WRITTEN RECORD DOES NOT SKIP. The tag is sha256(key, message) under a key at
# ${XDG_CACHE_HOME:-~/.cache}/harbor/secrets/gate-push/key, and the key path must resolve through a `secrets`
# directory. The session sandbox neither creates nor reads a `secrets` path (deploy-harden's **/secrets deny), so a
# sandboxed session cannot mint a tag; only a run outside the sandbox, which the permission gate sees, holds the key.
# The cost: the fast path runs outside the sandbox. A sandboxed push cannot read the key and runs the full checks.
# Beyond the boundary: a process outside the sandbox, or one that controls PATH (the hook's own `sh` comes from
# it), can bypass any hook, exactly as `--no-verify` can.
set -u

TTL="${HARBOR_GATE_PUSH_TTL:-3600}"
case "$TTL" in ''|*[!0-9]*) TTL=3600 ;; esac
ZERO=0000000000000000000000000000000000000000

say() { printf 'pre-push: %s\n' "$*"; }
# HERE is the real bin/: the ~/.local/bin/gate-push shim is a symlink, and library-log.sh sits beside the target.
_self="$0"
while [ -L "$_self" ]; do
  _sl="$(readlink "$_self")"
  case "$_sl" in /*) _self="$_sl" ;; *) _self="$(dirname "$_self")/$_sl" ;; esac
done
HERE="$(dirname "$_self")"
. "$HERE/library-log.sh"
log_init gate-push
# die <what failed> <fix> [exit] — every refusal of the run names its fix (contracts/logging.md)
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }

# Absolute paths first: a PATH-planted hasher would see the key on its stdin.
_sha() {
  for _h in /usr/bin/sha256sum /bin/sha256sum /usr/bin/shasum; do
    [ -x "$_h" ] || continue
    case "$_h" in *shasum) "$_h" -a 256 ;; *) "$_h" ;; esac | awk '{ print $1 }'; return
  done
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'
}
_filesha() { if [ -f "$1" ]; then _sha < "$1"; else printf 'absent'; fi; }

# The pre-push hook git runs here, as an absolute path with symlinks followed; empty when there is none.
hook_path() {
  _hp="$(git rev-parse --git-path hooks/pre-push 2>/dev/null)" || return 0
  case "$_hp" in /*) ;; *) _hp="$(pwd -P)/$_hp" ;; esac
  while [ -L "$_hp" ]; do
    _hl="$(readlink "$_hp")"
    case "$_hl" in /*) _hp="$_hl" ;; *) _hp="$(dirname "$_hp")/$_hl" ;; esac
  done
  [ -f "$_hp" ] && printf '%s' "$_hp"
}

# The check-set manifest: a change to any line is a new fingerprint.
manifest() {
  _mh="$(hook_path)"
  printf 'harbor gate-push fingerprint v1\n'
  [ -n "$_mh" ] || { printf 'hook absent\n'; return 0; }
  _md="$(dirname "$_mh")"
  printf 'hook %s %s\n' "$(_filesha "$_mh")" "$_mh"
  sed -n 's/^# gate-push: //p' "$_mh" | while IFS=' ' read -r _kind _rest; do
    case "$_kind" in
      file) for _f in $_rest; do
              case "$_f" in /*) _fp="$_f" ;; *) _fp="$_md/$_f" ;; esac
              printf 'file %s %s\n' "$(_filesha "$_fp")" "$_f"
            done ;;
      env)  for _v in $_rest; do
              case "$_v" in ''|[0-9]*|*[!A-Za-z0-9_]*) printf 'env-invalid %s\n' "$_v"; continue ;; esac
              if eval "[ -n \"\${$_v+x}\" ]"; then
                printf 'env %s %s\n' "$_v" "$(eval "printf '%s' \"\$$_v\"" | _sha)"
              else printf 'env %s unset\n' "$_v"; fi
            done ;;
      cmd)  _co="$(sh -c "$_rest" 2>&1; printf 'exit=%s' "$?")"
            printf 'cmd %s %s\n' "$(printf '%s' "$_co" | _sha)" "$_rest" ;;
      *)    printf 'unknown %s\n' "$_kind" ;;
    esac
  done
}
fingerprint() { manifest | _sha; }

# The key's path; refused unless it resolves through a `secrets` directory, which the session sandbox cannot create.
key_path() {
  _kd="${XDG_CACHE_HOME:-$HOME/.cache}/harbor/secrets/gate-push"
  if [ -d "$_kd" ]; then _kd="$(CDPATH= cd -P -- "$_kd" 2>/dev/null && pwd -P)" || return 1; fi
  case "$_kd/" in */secrets/*) printf '%s/key' "$_kd" ;; *) return 1 ;; esac
}
# read_key → the key on stdout via the shell's own redirect, never a PATH tool; 1 when it cannot be read.
read_key() {
  _kp="$(key_path)" || return 1
  { IFS= read -r _k < "$_kp"; } 2>/dev/null || return 1
  [ ${#_k} -ge 32 ] || return 1
  printf '%s' "$_k"
}
make_key() {
  _kp="$(key_path)" || return 1
  [ -f "$_kp" ] && return 0
  ( umask 077 && mkdir -p "$(dirname "$_kp")" && chmod 700 "$(dirname "$_kp")" \
    && od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$_kp.tmp.$$" && printf '\n' >> "$_kp.tmp.$$" \
    && mv "$_kp.tmp.$$" "$_kp" ) 2>/dev/null
}

store() { _gc="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$_gc" in /*) ;; *) _gc="$(pwd -P)/$_gc" ;; esac; printf '%s/gate-push' "$_gc"; }

# tag <key> <at> <remote> <push line> <fingerprint>
tag() { { printf '%s\n' "$1"; printf 'harbor gate-push v1\nat %s\nremote %s\npush %s\nfingerprint %s\n' "$2" "$3" "$4" "$5"; } | _sha; }

# ── check: the hook's question ────────────────────────────────────────────────────────────────────────────────
check() {
  _remote="${1:-}"
  if [ -n "${HARBOR_GATE_PUSH_CAPTURE:-}" ]; then
    { printf '%s\n' "$_remote"; cat; } > "$HARBOR_GATE_PUSH_CAPTURE" || exit 1
    say "gate-push verify run: the full checks run now; a pass is recorded for the push that follows."
    exit 1
  fi
  _lines="$(grep -v '^[[:space:]]*$' || :)"
  _n="$(printf '%s\n' "$_lines" | grep -c . || :)"
  if [ "$_n" -ne 1 ]; then say "$_n refs in this push; a recorded pass covers exactly one — running the full checks."; exit 1; fi
  set -f; set -- $_lines; set +f
  [ $# -eq 4 ] || exit 1
  _line="$1 $2 $3 $4"; _lsha="$2"
  case "$_lsha" in *[!0123456789abcdef]*|"$ZERO") exit 1 ;; esac
  _s8="$(printf '%s' "$_lsha" | cut -c1-12)"
  _rec="$(store)/$_lsha"
  if ! { IFS="$(printf '\t')" read -r _v _at _tag _fp _rr _rl < "$_rec"; } 2>/dev/null; then
    say "no recorded pass for $_s8 (sh bin/gate-push.sh records one) — running the full checks."; exit 1
  fi
  [ "$_v" = v1 ] || { say "the record for $_s8 is not v1 — running the full checks."; exit 1; }
  _fpn="$(fingerprint)"
  [ "$_fp" = "$_fpn" ] || { say "the check set changed since the pass recorded for $_s8 — running the full checks."; exit 1; }
  [ "$_rr $_rl" = "$_remote $_line" ] || { say "the pass for $_s8 was for another push (remote or remote sha moved) — running the full checks."; exit 1; }
  case "$_at" in ''|*[!0-9]*) exit 1 ;; esac
  _age=$(( $(date +%s) - _at ))
  if [ "$_age" -lt 0 ] || [ "$_age" -gt "$TTL" ]; then say "the pass for $_s8 is ${_age}s old, over ${TTL}s — running the full checks."; exit 1; fi
  _key="$(read_key)" || { say "the pass key is unreadable here (a sandboxed push cannot read secrets/) — running the full checks."; exit 1; }
  [ "$_tag" = "$(tag "$_key" "$_at" "$_remote" "$_line" "$_fpn")" ] \
    || { say "the record for $_s8 does not authenticate: no verify run wrote it — running the full checks."; exit 1; }
  say "0 check(s) run — gate-push verified $_s8 against this check set ${_age}s ago (fingerprint $(printf '%s' "$_fpn" | cut -c1-12))."
  exit 0
}

# ── verify, record, push ──────────────────────────────────────────────────────────────────────────────────────
run() {
  _u=''; [ "${1:-}" = -u ] && { _u=-u; shift; }
  case "${1:-}" in -*) die "unknown option: $1" "sh bin/gate-push.sh [-u] [<remote>]" 2 ;; esac
  _top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git work tree" "cd <repo> && sh bin/gate-push.sh" 2
  cd "$_top" || exit 2
  _br="$(git symbolic-ref --short -q HEAD)" || die "HEAD is detached: gate-push pushes the current branch" "git switch <branch>" 2
  _remote="${1:-$(git config "branch.$_br.remote" 2>/dev/null || echo origin)}"
  _ref="refs/heads/$_br:refs/heads/$_br"
  _sha="$(git rev-parse HEAD)"
  _s8="$(printf '%s' "$_sha" | cut -c1-12)"
  git diff --quiet HEAD -- 2>/dev/null \
    || die "uncommitted tracked changes: the checks would judge them, not $_s8" "commit them, or plain git push (its hook runs the full checks)"
  [ -n "$(hook_path)" ] || die "no pre-push hook here, so there is nothing to verify" "git push $_u $_remote $_br"
  make_key && read_key >/dev/null \
    || die "unchecked — the pass key under ${XDG_CACHE_HOME:-~/.cache}/harbor/secrets/ cannot be made or read here, so nothing was judged" \
           "run this outside the session sandbox: that boundary is what makes a recorded pass unforgeable" 3
  _fp1="$(fingerprint)"
  _cap="$(mktemp "${TMPDIR:-/tmp}/gate-push.XXXXXX")" || exit 2
  trap 'rm -f "$_cap"' EXIT
  log_head "verifying $_s8 ($_br) with this repo's pre-push, before any pack is sent"
  if ! HARBOR_GATE_PUSH_CAPTURE="$_cap" git push --dry-run "$_remote" "$_ref"; then
    die "the pre-push checks (or the dry run) failed on $_s8: nothing recorded, nothing pushed" "fix the red above, commit, run gate-push again"
  fi
  [ -s "$_cap" ] || die "the dry run passed but the hook never asked gate-push (not wired): nothing recorded, nothing pushed" \
                        "add the gate-push check call to the pre-push hook, or plain git push"
  _cr="$(sed -n 1p "$_cap")"; _cl="$(sed -n '2,$p' "$_cap" | grep -v '^[[:space:]]*$' || :)"
  set -f; set -- $_cl; set +f
  [ "$_cr" = "$_remote" ] && [ $# -eq 4 ] && [ "$2" = "$_sha" ] \
    || die "the hook saw a different push than gate-push asked for: nothing recorded" "sh bin/gate-push.sh again"
  _line="$1 $2 $3 $4"
  [ "$(git rev-parse HEAD)" = "$_sha" ] && git diff --quiet HEAD -- 2>/dev/null \
    || die "HEAD or the tree moved during the checks: nothing recorded" "sh bin/gate-push.sh again"
  [ "$(fingerprint)" = "$_fp1" ] || die "the check set changed during the run: nothing recorded" "sh bin/gate-push.sh again"
  _key="$(read_key)" || die "the pass key could not be read: nothing recorded" "run this outside the session sandbox" 3
  _st="$(store)" || exit 2
  mkdir -p "$_st" || exit 2
  _at="$(date +%s)"
  printf 'v1\t%s\t%s\t%s\t%s\t%s\n' "$_at" "$(tag "$_key" "$_at" "$_remote" "$_line" "$_fp1")" "$_fp1" "$_remote" "$_line" \
    > "$_st/$_sha.tmp.$$" && mv "$_st/$_sha.tmp.$$" "$_st/$_sha" || die "could not write the record under $_st" "ls -ld $_st"
  # Records past the TTL can never skip anything; keep the store to the live ones.
  find "$_st" -type f -mmin +$(( TTL / 60 + 1 )) -exec rm -f {} + 2>/dev/null || :
  log_ok "pass recorded for $_s8; pushing (the hook skips what just ran)"
  if git push $_u "$_remote" "$_ref"; then log_ok "pushed $_s8 to $_remote"
  else log_fail "the push of $_s8 failed after a recorded pass"; log_fix "sh bin/gate-push.sh $_u $_remote (the pass still covers this push for ${TTL}s)"; fi
  log_end
}

case "${1:-}" in
  check) shift; check "$@" ;;
  fingerprint) manifest; printf 'fingerprint %s\n' "$(fingerprint)" ;;
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0" ;;
  *) run "$@"; exit $? ;;
esac
