#!/usr/bin/env sh
# deploy.sh (harbor#457) — install every Harbor payload onto THIS box, in the one order that works.
#   sh bin/deploy.sh --live                  DRY RUN: preflight, then every installer's own dry run
#   sh bin/deploy.sh --apply --live          preflight, one [y/N], snapshot, install, verify, re-pin [y/N]
#   --only C[,C…]   just these components: constitution shim sec0 runtime floor prod-guard skills inject packs
#                   project-init projects-orchestrator (the harbor verbs route here; one snapshot, same gates).
#                   A component this run cannot install FAILS preflight; its fix is --only without it
#   no --only      core (constitution shim sec0 runtime floor skills inject packs) plus the optional components harbor.toml
#                   `components` names: yard fleet prod-guard collector; key unset = every component (harbor#1149)
#   --with-b6, --with-stop-gate   opt the floor into B6 or the Stop gate; a box already wired keeps them
#   --prune         the cleanup: leftovers moved into backups/pruned-<TS>/ (a dry run unless --apply),
#                   then pruned-* dirs older than 30 days deleted
#   --only floor --uninstall   remove the floor (harbor uninstall): the same gates and snapshot, and a
#                   verify that expects the floor GONE; the snapshot is offered back. Every installed pack goes
#                   with it (bin/pack.sh remove), and the skill book is regenerated without their skills
#   --accept-loss   passed to constitution-, runtime-, floor- and skills-install and to restore.sh;
#                   deploy's own regression check then warns instead of refusing
#   --unattended    the ship runner's apply (deploy-fleet.sh, ship contract §6), never a person's: needs --apply,
#                   SHIP_UNATTENDED=1 and SHIP_SNAPSHOT naming an empty file. Installs without the [y/N], writes
#                   the snapshot id to SHIP_SNAPSHOT, and answers No to the restore and the B8 re-pin
#   -h, --help      this text. The live box only: each installer takes --dir for a sandbox.
#
# Owns ORDER, PREFLIGHT, SNAPSHOT and VERIFY. Every write is delegated to the
# installer that owns it. Deliberately one file: the sequence is the product.
#
# Kept separate on purpose:
#   - the B8 re-pin: asked last, from /dev/tty, default No. A session has no tty
#     so it gets No; script(1) can fake one, so this is an accident gate, not a wall.
#   - inject-install --projects: it writes other repos.
# Opt-ins are read from the box (harbor#762): a wired Stop gate and an installed B6 are refreshed.
# One log format (CONTRACTS/logging.md): deploy's own lines are log-lib's; its children's lines are
# relayed verbatim, and on --apply both go to backups/deploy/<TS>/log. Children run with HARBOR_DEPLOY=1.
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/log-lib.sh"
. "$ROOT/bin/install-lib.sh"
log_init deploy
# A native Windows shell is refused before anything, even arguments: no floor on an unproved platform (harbor#833).
case "$(uname -s 2>/dev/null || :)" in MINGW*|MSYS*|CYGWIN*)
  log_fail "native Windows shell ($(uname -s)): Harbor runs on macOS and Linux, and on Windows only inside WSL2 (CONTRACTS/platforms.md)"
  log_fix "install WSL2 (wsl --install), clone Harbor inside the WSL filesystem (~/port/harbor), and run deploy there"
  log_end || :; exit 1 ;;
esac
COMPONENTS='constitution shim sec0 runtime floor prod-guard skills inject packs project-init projects-orchestrator'
ONLY=''; PRUNE=0; WITH_B6=0; WITH_STOP=0; UNINSTALL=0; UNATTENDED=0
il_opt() {
  case "$1" in
    --unattended) UNATTENDED=1; IL_TAKE=-1 ;;  # -1: kept out of IL_ARGV, so no fix line hands a person the runner's flag
    --only) il_value --only "${2-}"; [ -z "$ONLY" ] || il_usage_error '--only given twice'; ONLY="$2"; IL_TAKE=2 ;;
    --prune) PRUNE=1; IL_TAKE=1 ;;
    --uninstall) UNINSTALL=1; IL_TAKE=1 ;;
    --with-b6) WITH_B6=1; IL_TAKE=1 ;;
    --with-stop-gate) WITH_STOP=1; IL_TAKE=1 ;;
    *) IL_TAKE=0 ;;
  esac
}
il_parse "$@"
[ "$IL_DIR_SET" -eq 0 ] || il_usage_error '--dir: deploy targets the live box only (each installer takes --dir for a sandbox)'
for _c in $(printf '%s' "$ONLY" | tr ',' ' '); do
  case " $COMPONENTS " in *" $_c "*) ;; *) il_usage_error "--only $_c: not a component ($COMPONENTS)" ;; esac
done
[ -z "$ONLY" ] || [ -n "$(printf '%s' "$ONLY" | tr -d ', ')" ] || il_usage_error '--only needs a component'
# The default set is core plus the optional components harbor.toml `components` names (harbor#1149).
# roots.sh --conf exits 0 with the list, 1 when the key is unset (the legacy full set), anything else a usage error.
# stderr is not captured: roots.sh's own notes (a BOM or CRLF file) reach the operator, and never the list.
CORE_SET='constitution shim sec0 runtime floor skills inject packs'
DEFSET="$COMPONENTS"; COMP_NOTE=''
if [ -z "$ONLY" ] && [ "$PRUNE" -eq 0 ]; then
  _cv="$(sh "$ROOT/bin/roots.sh" --conf components)" && _crc=0 || _crc=$?
  case "$_crc" in
    0)
      DEFSET="$CORE_SET"
      for _c in $_cv; do
        case "$_c" in
          core) ;;
          collector) _ccoll=1 ;;  # installed by root, never by deploy
          yard) DEFSET="$DEFSET project-init" ;;
          fleet) DEFSET="$DEFSET projects-orchestrator" ;;
          prod-guard) DEFSET="$DEFSET prod-guard" ;;
          *) il_usage_error "harbor.toml components: '$_c' is not a component (core, yard, fleet, prod-guard, collector)" ;;
        esac
      done
      COMP_NOTE="components: core + $(printf '%s' "$_cv" | tr '\n' ' ')(harbor.toml)"
      [ -z "${_ccoll:-}" ] || COMP_NOTE="$COMP_NOTE; collector is installed by root: sudo sh $ROOT/bin/collector-setup.sh"
      ;;
    1) COMP_NOTE='components unset, so it installs the legacy default (every component); set components in harbor.toml' ;;
    *) il_usage_error "harbor.toml components: roots.sh could not read it (exit $_crc); its message is above" ;;
  esac
fi
if [ "$UNINSTALL" -eq 1 ]; then  # the floor is the one component with an uninstaller (harbor#808)
  [ "$ONLY" = floor ] || il_usage_error '--uninstall takes --only floor, the one component with an uninstaller'
  [ "$PRUNE" -eq 0 ] && [ "$WITH_B6" -eq 0 ] && [ "$WITH_STOP" -eq 0 ] || il_usage_error '--uninstall takes no --prune, --with-b6 or --with-stop-gate'
fi
if [ "$PRUNE" -eq 1 ] && { [ -n "$ONLY" ] || [ "$WITH_B6" -eq 1 ] || [ "$WITH_STOP" -eq 1 ]; }; then
  il_usage_error '--prune is its own run: it takes no --only, --with-b6 or --with-stop-gate'
fi
# --unattended (harbor#1018, ship contract §6): only the runner's env passes it. The guard (deploy-raw) keeps a
# session from typing it; the restore stays the runner's (manifest `restore`), the re-pin stays the operator's.
if [ "$UNATTENDED" -eq 1 ]; then
  [ "$IL_APPLY" -eq 1 ] || il_usage_error '--unattended takes --apply: a dry run asks nothing'
  [ "${SHIP_UNATTENDED:-}" = 1 ] || il_usage_error '--unattended is the ship runner alone, which sets SHIP_UNATTENDED=1'
  [ -n "${SHIP_SNAPSHOT:-}" ] && [ -f "$SHIP_SNAPSHOT" ] && [ ! -L "$SHIP_SNAPSHOT" ] && [ ! -s "$SHIP_SNAPSHOT" ] \
    || il_usage_error '--unattended needs SHIP_SNAPSHOT naming an empty file, where the runner reads the snapshot id'
  [ "$UNINSTALL" -eq 0 ] && [ "$PRUNE" -eq 0 ] && [ "$IL_ACCEPT_LOSS" -eq 0 ] \
    || il_usage_error '--unattended takes no --uninstall, --prune or --accept-loss: those stay at a terminal'
fi
# The live config dir, physically; a CLAUDE_CONFIG_DIR naming another dir exits 2 here, before any work.
# On --apply the log opens now, so a refused preflight is kept too.
il_target
# It named the target itself if it passed il_target; children get the target from --live alone.
unset CLAUDE_CONFIG_DIR
CFG="$IL_TARGET"
LOCAL_BIN="${HARBOR_LOCAL_BIN:-$HOME/.local/bin}"
BASE="${HARBOR_BASE_BRANCH:-main}"
# Installers under deploy skip the next steps deploy itself performs (harbor#285).
HARBOR_DEPLOY=1; export HARBOR_DEPLOY
AL=''; [ "$IL_ACCEPT_LOSS" -eq 0 ] || AL=' --accept-loss'
# deploy's own command line, for the fix lines that send the operator back here: its --only and opt-ins kept.
_deploy_cmd() { # [<checkout>] [--accept-loss] — the apply, spelled for its gate
  _dc_r="$ROOT"; case "${1-}" in /*) _dc_r="$1"; shift ;; esac
  _dc_l="$AL"; [ "${1-}" != --accept-loss ] || _dc_l=' --accept-loss'
  printf "sh '%s/bin/deploy.sh' --apply%s --live%s" "$_dc_r" "${IL_ARGV:+ $IL_ARGV}" "$_dc_l"
}
DEPLOY_CMD="$(_deploy_cmd)"
_jq_fix() { pkg_hint jq; }  # harbor#1149, harbor#618: the package manager this OS has, from log-lib
# A component this run installs; with no --only, the default set (harbor#1149).
_want() {
  if [ -z "$ONLY" ]; then case " $DEFSET " in *" $1 "*) return 0 ;; esac; return 1; fi
  case ",$ONLY," in *",$1,"*) return 0 ;; esac; return 1
}
_want_any() { for _wa in "$@"; do _want "$_wa" && return 0; done; return 1; }

# Physical paths, never strings (lint D2, harbor#52).
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/harbor-deploy.XXXXXX")"
SNAP=''
# Everything the installers write in the config dir, derived from their writes (harbor#765):
# runtime-install's lib/ and prod-guard-install's settings.json.bak.* were missing. A glob is allowed.
# The install manifest joined it with Wave C (§3): a restore that put the files back and not their rows
# would leave install-drift and skills-collide reading a record of an install that was undone.
SNAP_SET='settings.json CLAUDE.md bin lib hooks inject.d skills skill-packs commands checks.d shims.d .harbor-packs .helm-pins .helm-floor-teeth .sec0-baseline.sha256 .helm-instructions.sha256 .helm-install-stamp .harbor-manifest settings.json.bak.*'
B8PIN="$CFG/.helm-instructions.sha256"
trap 'rm -rf "$WORK"' EXIT
# A trapped INT returns to the script, so it must exit explicitly or the install carries on.
trap '_interrupted' INT TERM
FAILS=0

_interrupted() {
  printf '\n'
  log_fail 'INTERRUPTED: the config dir may be half-installed'
  if [ -n "$SNAP" ]; then log_fix "sh '$ROOT/bin/restore.sh' --live --from '$SNAP'   # the restore plan for the pre-run copy"
  else log_nofix 'nothing was snapshotted yet, so nothing was installed'; fi
  log_end || :
  exit 130
}

# A FAIL is always followed by its fix: a command, or `none automatic — see <where>`.
_bad() { # <what failed> <fix command | "none: <where>">
  FAILS=$((FAILS + 1))
  log_fail "$1"
  case "${2-}" in 'none: '*) log_nofix "${2#none: }" ;; '') log_nofix 'harbor#457 — bin/deploy.sh' ;; *) log_fix "$2" ;; esac
}
_notes() { while IFS= read -r _nl; do [ -n "$_nl" ] && log_note "$_nl"; done; }  # stdin lines → notes

# A child's lines, verbatim: all of them on screen (or only its verdicts, with --brief) and all in the log.
_relay() { # [--brief] <file>
  _rb=0; [ "$1" = --brief ] && { _rb=1; shift; }
  if [ "$_rb" -eq 1 ]; then
    grep -E '^  (FAIL|WARN|fix): |^[A-Za-z0-9_.-]+: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$' "$1" || :
  else cat "$1"; fi
  [ -z "$LOG_PATH" ] || sed "s|^|$(date -u +%Y-%m-%dT%H:%M:%SZ) |" "$1" >>"$LOG_PATH" 2>/dev/null || :
}
# Run a child with its lines relayed; returns its rc.
_run() {
  _r_rc=0
  "$@" >"$WORK/out" 2>&1 </dev/null || _r_rc=$?
  _relay "$WORK/out"
  return "$_r_rc"
}

# Yes only from a person at a terminal. No tty, EOF or a Claude session all mean No.
_ask() {
  printf '%s [y/N] ' "$1"
  if [ "$UNATTENDED" -eq 1 ]; then
    printf '\n'; log_note "$1 — answering No: --unattended asks nobody"; return 1
  fi
  if [ -n "${CLAUDECODE:-}" ]; then
    printf '\n'; log_note "$1 — answering No: running inside a Claude session"; return 1
  fi
  _a_ans=""
  if ! { read -r _a_ans </dev/tty; } 2>/dev/null; then
    printf '\n'; log_note "$1 — answering No: no answer, no terminal or end of input (run this from a terminal window, not via \`!\`)"
    return 1
  fi
  case "$_a_ans" in y|Y|yes|YES|Yes) log_note "$1 — answered yes"; return 0 ;; *) log_note "$1 — answered no"; return 1 ;; esac
}

# B6 as the next SessionStart would see it: prints clean | advisory:<msg> | BLOCKED:<msg>.
_b6_verdict() {
  _g="$CFG/bin/guard-integrity.sh"
  [ -f "$_g" ] || _g="$ROOT/bin/guard-integrity.sh"
  _g_out="$(env -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW CLAUDE_CONFIG_DIR="$CFG" sh "$_g" </dev/null 2>/dev/null || true)"
  if [ -z "$_g_out" ]; then printf 'clean'; return; fi
  # `.continue == false`, never `//`: jq's alternative operator treats false as missing.
  if printf '%s' "$_g_out" | jq -e '.continue == false' >/dev/null 2>&1; then
    printf 'BLOCKED:%s' "$(printf '%s' "$_g_out" | jq -r '.stopReason // "no reason given"' 2>/dev/null | cut -c1-400)"
  else
    printf 'advisory:%s' "$(printf '%s' "$_g_out" | jq -r '.systemMessage // .hookSpecificOutput.additionalContext // "?"' 2>/dev/null | cut -c1-400)"
  fi
}

# B8 manifest lines are `<sha|link:target|absent>  <path>`. Fails when it cannot be built.
_b8_manifest() { # <out>
  sh "$ROOT/bin/pin-instructions.sh" --print --live >"$1" 2>/dev/null && [ -s "$1" ]
}
_b8_paths() { # <manifest-a> <manifest-b> — paths whose line differs, one per line
  diff "$1" "$2" | awk '/^[<>] /{ sub(/^[<>] [^ ]*  /, ""); print }' | sort -u
}

# No optional locks: `git status` must not refresh the index, or a dry run writes (harbor#865).
_git() { git -C "$ROOT" --no-optional-locks "$@"; }

# True when a box file's bytes are ones an install put there: the manifest records them for its path, or
# they were committed at <repo-path> at some point, current or withdrawn (install-lib's il_known, §3).
_in_history() { # <repo-path> <file under $CFG>
  il_known "$CFG" "${2#"$CFG"/}" "$2" "$ROOT" "$1"
}
# The same question of the private layer's own history (harbor#1149): the box packs and the project registry it carries are
# installed into <config>/inject.d, so a past version of one is as much "an install put it there" as a core pack is.
_in_private_history() { # <repo-path in the private layer> <file under $CFG>
  _pv="$(sh "$ROOT/bin/roots.sh" --private 2>/dev/null)" && [ -d "$_pv" ] || return 1
  il_known "$CFG" "${2#"$CFG"/}" "$2" "$_pv" "$1"
}

# ── UP FRONT: refused before any check or plan (install standard §4) ─────────
# A linked worktree installs text nobody reviewed, and a session answers every [y/N] with No. Both
# used to surface only after the whole preflight and plan (review 2026-09-27 §4), so the operator
# read a full plan for a run that could never happen. The fix is the exact command, from a terminal.
_dry_cmd() { # <checkout> — this run's dry run, from there
  printf "sh '%s/bin/deploy.sh'%s --live%s" "$1" "${IL_ARGV:+ $IL_ARGV}" "$AL"
}
_upfront() {
  if _git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # runtime-install copies `harbor` from the MAIN worktree, whatever checkout runs it.
    _main_wt="$(_git worktree list --porcelain | awk 'NR==1{ sub(/^worktree /, ""); print }')"
    if [ -n "$_main_wt" ] && [ "$(_phys "$_main_wt")" != "$(_phys "$ROOT")" ]; then
      if [ "$IL_APPLY" -eq 1 ]; then _fx="$(_deploy_cmd "$_main_wt")   # from a terminal window"; else _fx="$(_dry_cmd "$_main_wt")"; fi
      _bad "running from a linked worktree ($ROOT); deploy from the main checkout" "$_fx"
    fi
  fi
  # The runner under gate-approve.sh inherits the session's env; --unattended is that exception, nothing wider.
  if [ "$IL_APPLY" -eq 1 ] && [ -n "${CLAUDECODE:-}" ] && [ "$UNATTENDED" -eq 0 ]; then
    _bad 'refused up front: running inside a Claude session, and --apply runs only from a terminal window (not via `!`, which has no terminal to answer the prompt)' \
      "$DEPLOY_CMD"
  fi
  [ "$FAILS" -gt 0 ] || return 0
  log_note "PREFLIGHT FAILED ($FAILS) — refused up front: nothing was checked, planned or installed"
  log_end || :
  exit 1
}

# ── PREFLIGHT: read-only; any FAIL stops the deploy before its first write ────
# The checkout: what deploy installs, and what --prune judges "the repo no longer ships" against.
_checkout() {
  if ! _git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _bad "$ROOT is not a git checkout" 'none: harbor#457 — deploy runs from a harbor checkout on main'
  else
    log_ok 'running from the main checkout'

    _br="$(_git symbolic-ref --short -q HEAD || true)"
    if [ "$_br" = "$BASE" ]; then log_ok "on $BASE"
    else _bad "on '${_br:-detached HEAD}', not $BASE — a branch is text nobody has reviewed" "git -C '$ROOT' switch $BASE"; fi

    _dirty="$(_git status --porcelain)"
    if [ -z "$_dirty" ]; then log_ok 'working tree clean'
    else
      _bad "uncommitted changes in $ROOT — they would be installed unreviewed" \
        'none: harbor#457 — commit them through a PR, or remove them, then re-run'
      printf '%s\n' "$_dirty" | head -10 | _notes
    fi

    if _git fetch --quiet origin "$BASE" 2>"$WORK/fetch.err"; then
      _head="$(_git rev-parse HEAD)"; _up="$(_git rev-parse "origin/$BASE" 2>/dev/null || true)"
      if [ "$_head" = "$_up" ]; then log_ok "in sync with origin/$BASE ($(_git rev-parse --short HEAD))"
      else
        _ab="$(_git rev-list --left-right --count "HEAD...origin/$BASE" 2>/dev/null || printf '? ?')"
        _ahead="${_ab%%[[:space:]]*}"; _behind="${_ab##*[[:space:]]}"
        if [ "$_ahead" = 0 ]; then _fx="git -C '$ROOT' pull --ff-only origin $BASE"
        else _fx="none: harbor#457 — push those commits through a PR, then pull"; fi
        _bad "not in sync with origin/$BASE (ahead $_ahead, behind $_behind)" "$_fx"
      fi
    else
      _bad "cannot fetch origin/$BASE, so what is merged cannot be confirmed: $(head -1 "$WORK/fetch.err")" \
        "git -C '$ROOT' fetch origin $BASE"
    fi
  fi
}

_preflight() {
  log_head 'preflight · nothing is written unless every check here passes'
  _checkout
  # --with-b6 onto a box with no floor is refused here, with the reason (FLOOR.md order).
  _optins

  # Shims and CLAUDE.md's path root point at HARBOR_REPO, not at whichever checkout runs this.
  _hr="$(sh "$ROOT/bin/roots.sh" --get HARBOR_REPO 2>/dev/null || true)"
  if [ "$(_phys "${_hr:-?}")" = "$(_phys "$ROOT")" ]; then log_ok 'HARBOR_REPO resolves to this checkout'
  elif [ -n "$_hr" ] && [ -f "$_hr/bin/deploy.sh" ]; then
    _bad "shims and CLAUDE.md would point at $_hr, not this checkout" "sh '$_hr/bin/deploy.sh' --live$AL"
  else _bad "shims and CLAUDE.md would point at ${_hr:-<unresolved>}, not this checkout" 'none: CONTRACTS/roots.tsv — HARBOR_REPO'; fi

  if command -v jq >/dev/null 2>&1; then log_ok 'jq present'; else _bad 'jq is missing; every installer needs it' "$(_jq_fix)"; fi
  if [ -f "$CFG/settings.json" ]; then log_ok 'config dir has settings.json'
  else _bad "no settings.json in $CFG" "$(il_first_run_cmd "$ROOT")"; fi

  # Refused here rather than midway: floor-install refusing AFTER runtime-install wrote = lockout.
  for _i in runtime-install floor-install; do
    _want "${_i%-install}" || continue
    if sh "$ROOT/bin/install-stamp.sh" --check "$CFG" "$_i" >"$WORK/stamp" 2>&1; then
      log_ok "$_i: no regression against what is installed"
    elif [ "$IL_ACCEPT_LOSS" -eq 1 ]; then
      log_warn "--accept-loss: $_i would REMOVE installed work (harbor#115); the lines below name it"
      _relay "$WORK/stamp"
    else
      _bad "$_i would REMOVE installed work (harbor#115); deploy from a checkout that contains it, or accept the loss" \
        "$(_deploy_cmd --accept-loss)"
      _relay "$WORK/stamp"
    fi
  done

  # Runtime without floor (harbor#916): runtime-install replaces B6-pinned files (log-lib.sh) and
  # only floor-install re-pins them, so the next session is BLOCKED. Measured 2026-10-02: preflight
  # passed, verify failed after the write, and the operator restored. Refused here, before any write.
  if _want runtime && ! _want floor && [ -d "$CFG/.helm-pins" ]; then
    _rf="$(sed -n 's/^FILES="\(.*\)"$/\1/p' "$ROOT/bin/runtime-install.sh" 2>/dev/null)"; _pd=''
    if [ -z "$_rf" ]; then
      _bad "cannot read runtime-install's FILES, so whether it replaces a B6-pinned file is unknown" 'none: harbor#916 — bin/runtime-install.sh FILES='
    else
      for _f in $_rf; do
        [ -f "$CFG/.helm-pins/$_f.sha256" ] && [ -f "$ROOT/bin/$_f" ] || continue
        [ "$(cat "$CFG/.helm-pins/$_f.sha256" 2>/dev/null)" = "$(_sha256 < "$ROOT/bin/$_f")" ] || _pd="$_pd${_pd:+ }$_f"
      done
      if [ -n "$_pd" ]; then
        _bad "runtime without floor would replace B6-pinned $_pd, and only floor-install re-pins it: the next session would be BLOCKED" \
          "$(_only_cmd "$ONLY,floor")"
      else log_ok 'runtime replaces no B6-pinned file, so it can install without floor'; fi
    fi
  fi

  # runtime-, sec0-, floor- and prod-guard-install re-pin the deny baseline unconditionally,
  # so installing over existing drift would bless it.
  if ! _want_any runtime floor sec0 prod-guard; then :
  elif [ -d "$CFG/.helm-pins" ]; then
    _v="$(_b6_verdict)"
    case "$_v" in
      clean)      log_ok 'B6: the box is intact right now' ;;
      advisory:*"settings.json changed outside the floor"*)
                  _bad "B6: settings.json drifted since its baseline; runtime- and prod-guard-install would re-pin it unseen" \
                    "sh '$ROOT/bin/floor-deny.sh' --live --repin   # after you have reviewed the drift" ;;
      advisory:*) log_note "B6 advisory (does not block): ${_v#advisory:}" ;;
      *)          _bad "B6: the box is ALREADY drifted; installing would re-pin over it. ${_v#BLOCKED:}" \
                    'none: the B6 reason above, which names its own recovery' ;;
    esac
  else
    log_note 'no .helm-pins: the floor has never been installed here (first install)'
  fi

  # Shims: shim-install's own dry run refuses a regular file where a shim belongs (exit 1).
  if ! _want shim; then :
  elif sh "$ROOT/bin/shim-install.sh" --live >"$WORK/shim" 2>&1; then
    log_ok "shims: $(grep -c ': would ' "$WORK/shim" || :) to write, none blocked"
    [ -z "$LOG_PATH" ] || _relay "$WORK/shim" >/dev/null
  else
    _relay --brief "$WORK/shim"
    _bad 'shims: a regular file sits where a shim belongs; shim-install --apply would refuse it (its FAIL lines above)' \
      'none: the shim-install fix lines above — remove the file, or drop its row from CONTRACTS/shims.tsv'
    if grep -q '^  FAIL: harbor: ' "$WORK/shim"; then
      log_note "harbor: that is the copy older runtime-installs made; it is safe to remove: rm '$LOCAL_BIN/harbor'"
    fi
  fi

  # Skills: skills-install's own dry run refuses what would make its --apply fail after writing
  # (a NESTED copy, a live copy newer than the repo, files only the installed copy has).
  if ! _want skills; then :
  elif [ ! -d "$CFG/skills" ]; then
    log_note 'no skills dir yet: every tracked skill will be installed new'
  elif sh "$ROOT/bin/skills-install.sh" --all --live$AL >"$WORK/skills" 2>&1; then
    log_ok "skills: $(grep -c ': would update ' "$WORK/skills" || :) to update, $(grep -c ': would install ' "$WORK/skills" || :) new, none blocked"
    [ -z "$LOG_PATH" ] || _relay "$WORK/skills" >/dev/null
  else
    _relay --brief "$WORK/skills"
    _bad 'skills: skills-install --all --apply would refuse (its FAIL lines above)' 'none: the skills-install fix lines above'
  fi

  # Commands are overwritten with no collide check; a box copy in no commit is someone's edit.
  : >"$WORK/cmds"
  _want skills && { sh "$ROOT/bin/skills-install.sh" commands --all --live >"$WORK/cmds" 2>&1 || true; }
  _cm_bad=0
  for _n in $(sed -n 's/^  note: \([^:]*\): would update .*/\1/p' "$WORK/cmds"); do
    if [ -f "$CFG/commands/$_n.md" ] && ! _in_history "commands/$_n.md" "$CFG/commands/$_n.md"; then
      _bad "command $_n: the installed copy matches no commit; installing would overwrite that edit" \
        "none: harbor#457 — copy $CFG/commands/$_n.md into commands/$_n.md through a PR, or remove it"
      _cm_bad=1
    fi
  done
  if _want skills && [ "$_cm_bad" -eq 0 ]; then log_ok 'commands: no box-only edits would be overwritten'; fi

  # inject-install rebuilds inject.d from scratch. A pack the repo once held (current or withdrawn)
  # is its to replace; bytes in no commit are someone's work and would be deleted.
  if _want inject && [ -d "$CFG/inject.d" ]; then
    ( cd "$CFG/inject.d" && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort ) >"$WORK/inj.live"
    : >"$WORK/inj.unsrc"
    # A note a pack installed (its manifest in .harbor-packs) is bytes from that pack's repo, not from a commit here; the
    # packs step puts it back after inject-install rebuilds the directory.
    _pack_owned inject.d >"$WORK/inj.pack"
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      grep -qxF -e "$_f" "$WORK/inj.pack" && continue
      _in_history "inject.d/box/$_f" "$CFG/inject.d/$_f" || _in_private_history "inject.d/box/$_f" "$CFG/inject.d/$_f" \
        || printf '%s\n' "$_f" >>"$WORK/inj.unsrc"
    done <"$WORK/inj.live"
    if [ -s "$WORK/inj.unsrc" ]; then
      _bad 'inject.d holds packs whose bytes are in no commit; inject-install would replace them' \
        "none: harbor#457 — copy each one into inject.d/box/ (or the private layer's) through a PR, or move it out of $CFG/inject.d"
      _notes <"$WORK/inj.unsrc"
    else
      log_ok 'inject.d: every installed pack is one the repo holds or once held'
    fi
  fi

  : >"$WORK/b8.drift.pre"
  if [ ! -f "$B8PIN" ]; then
    log_note 'B8: instruction surfaces are not pinned yet'
  elif ! _b8_manifest "$WORK/b8.pre"; then
    _bad 'B8: the instruction manifest could not be built, so drift cannot be judged' \
      "none: the error of sh '$ROOT/bin/pin-instructions.sh' --print --live"
  else
    _b8_paths "$B8PIN" "$WORK/b8.pre" >"$WORK/b8.drift.pre"
    if [ -s "$WORK/b8.drift.pre" ]; then
      log_note "B8: $(wc -l <"$WORK/b8.drift.pre" | tr -d ' ') instruction-surface path(s) ALREADY changed before this deploy; the re-pin prompt lists them separately"
    else
      log_ok 'B8: instruction surfaces match their pin'
    fi
  fi
}

# ── OPT-INS, READ FROM THE BOX (harbor#762) ───────────────────────────────────
# A flag the operator passed once is not a record: a box whose settings.json wires the Stop gate, or
# that runs B6, is refreshed by every deploy, or VERIFY calls the unrefreshed copy stale (2026-09-27).
FLOOR_OPTS=''
_stop_wired() { jq -e '[.hooks.Stop[]?.hooks[]?.command // empty | select(test("(^|/)guard-stop\\.sh( |$)"))] | length > 0' "$CFG/settings.json" >/dev/null 2>&1; }
_b6_installed() {
  [ -f "$CFG/bin/guard-integrity.sh" ] \
    && jq -e '[.hooks.SessionStart[]?.hooks[]?.command // empty | select(test("guard-integrity"))] | length > 0' "$CFG/settings.json" >/dev/null 2>&1
}
_optins() {
  _want floor || return 0
  if [ "$WITH_STOP" -eq 1 ]; then FLOOR_OPTS="$FLOOR_OPTS --with-stop-gate"; log_note 'Stop gate: opted in by --with-stop-gate'
  elif _stop_wired; then FLOOR_OPTS="$FLOOR_OPTS --with-stop-gate"; log_note 'Stop gate: wired on this box, so floor-install refreshes it (--with-stop-gate, harbor#762)'; fi
  if [ "$WITH_B6" -eq 1 ]; then
    FLOOR_OPTS="$FLOOR_OPTS --with-b6"
    # B6 installs LAST (FLOOR.md): onto a floor that exists and a session that ran on it, never with it.
    if [ -d "$CFG/.helm-pins" ]; then log_note 'B6: opted in by --with-b6'
    else _bad 'B6 installs last: this box has no floor yet (no .helm-pins), so --with-b6 would install the gate with the floor it checks' \
      "sh '$ROOT/bin/deploy.sh' --apply --live   # then restart a session, then add --with-b6"; fi
  elif _b6_installed; then FLOOR_OPTS="$FLOOR_OPTS --with-b6"; log_note 'B6: installed and wired on this box, so floor-install refreshes it and its pin (--with-b6)'; fi
}

# ── PACKS (harbor#1149): harbor.toml `packs` lists the workload repos whose harbor-pack/ installs box-wide ──
# bin/pack.sh is the only reader and writer of a pack. No `packs` key means no packs, said once. A pack that refuses
# is skipped by pack.sh, by name, and the run exits 1: here that fails the preflight (dry run) or the install (apply).
PACKS_LIST=''
_packs_conf() { # sets PACKS_LIST; returns 0 when packs are listed, 1 when none (a note is already logged), 2 when harbor.toml is unreadable
  PACKS_LIST=''; _pc_rc=0
  PACKS_LIST="$(sh "$ROOT/bin/roots.sh" --conf packs)" || _pc_rc=$?
  case "$_pc_rc" in
    0) [ -n "$PACKS_LIST" ] || _pc_rc=1 ;;
  esac
  case "$_pc_rc" in
    0) ;;
    1) log_note 'packs: harbor.toml lists no packs (no packs key, or an empty one), so none are installed; set packs = ["<repo-id>"] to install a workload repo'"'"'s harbor-pack/'; return 1 ;;
    *) return 2 ;;
  esac
  return 0
}
_pack_owned() { # <dir under the config dir> -> the files a pack installed there, relative to that dir
  cat "$CFG"/.harbor-packs/*.tsv 2>/dev/null | awk -F'\t' -v p="$1/" '$1 == "F" && index($2, p) == 1 { print substr($2, length(p) + 1) }'
}
_pack_ids() { # the packs installed on this box, from their manifests
  for _pm in "$CFG"/.harbor-packs/*.tsv; do [ -f "$_pm" ] || continue; _pm="${_pm##*/}"; printf '%s\n' "${_pm%.tsv}"; done
}
_packs_refusals() { sed -n 's/^  FAIL: //p' "$1" | head -3 | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
_packs_plan() {
  _packs_conf && _pk_rc=0 || _pk_rc=$?
  case "$_pk_rc" in
    1) return 0 ;;
    2) _bad "harbor.toml packs: roots.sh could not read it (exit 2); its message is above" 'none: CONTRACTS/private-layer.md — harbor.toml'; return 0 ;;
  esac
  _r_rc=0
  sh "$ROOT/bin/pack.sh" install --live >"$WORK/out" 2>&1 </dev/null || _r_rc=$?
  { printf '\n=== pack.sh install (rc=%s)\n' "$_r_rc"; cat "$WORK/out"; } >>"$PLAN"
  if [ "$_r_rc" -ne 0 ]; then
    _bad "pack.sh: its own dry run FAILED (rc=$_r_rc), so its install would too: $(_packs_refusals "$WORK/out")" 'none: its FAIL and fix lines below'
    _relay --brief "$WORK/out"
    return 0
  fi
  log_ok "pack.sh: its dry run passes ($(printf '%s\n' "$PACKS_LIST" | wc -l | tr -d ' ') pack(s) in harbor.toml)"
  _relay --brief "$WORK/out"
}
_packs_install() { # run after inject-install, which rebuilds inject.d and so drops a pack's notes
  _packs_conf && _pk_rc=0 || _pk_rc=$?
  case "$_pk_rc" in 1) return 0 ;; 2) _INSTALL_FAILED='harbor.toml packs: roots.sh could not read it'; return 1 ;; esac
  log_note 'running: pack.sh install --apply --live'
  if ! _run sh "$ROOT/bin/pack.sh" install --apply --live; then
    _INSTALL_FAILED="pack.sh install --apply --live: $(_packs_refusals "$WORK/out")"
    return 1
  fi
}
# Uninstall takes every installed pack with the floor (their rows are the register's and the skill book's), then
# regenerates the skill book from what is left, so no pack row survives in either index.
_packs_uninstall_plan() {
  _pids="$(_pack_ids | tr '\n' ' ')"
  [ -n "$_pids" ] || return 0
  log_note "packs installed here, removed with the floor: $_pids"
  _r_rc=0
  # shellcheck disable=SC2086
  sh "$ROOT/bin/pack.sh" remove $_pids --live >"$WORK/pout" 2>&1 </dev/null || _r_rc=$?
  cat "$WORK/pout" >>"$PLAN"
  [ "$_r_rc" -eq 0 ] || { _bad "pack.sh remove: its own dry run FAILED (rc=$_r_rc), so its removal would too" 'none: its FAIL and fix lines below'; _relay --brief "$WORK/pout"; }
}
_packs_uninstall() {
  _pids="$(_pack_ids | tr '\n' ' ')"
  [ -n "$_pids" ] || return 0
  log_note 'running: pack.sh remove --apply --live'
  # shellcheck disable=SC2086
  _run sh "$ROOT/bin/pack.sh" remove $_pids --apply --live || { _bad 'stopped at: pack.sh remove --apply --live' 'none: its FAIL and fix lines above'; return 1; }
  log_note 'skill-book.sh: write the installed index from the box without the packs'
  _run sh "$ROOT/bin/skill-book.sh" install --apply --live || { _bad 'stopped at: skill-book.sh install' 'none: its FAIL and fix lines above'; return 1; }
  return 0
}

# ── CROSS-REPO (harbor#736): each repo's own `just install [--apply|--check]`, after Harbor's ──────
# The documented interface (project-init#1047, projects-orchestrator#318): a dry run by default that
# exits 1 when --apply would refuse, and --check non-zero on drift. A repo it cannot run fails preflight (UNREACHABLE).
XR_PI=''; XR_PO=''
_xr_dir() { case "$1" in project-init) sh "$ROOT/bin/roots.sh" --get HARBOR_PROJECT_INIT 2>/dev/null ;; *) sh "$ROOT/bin/roots.sh" --get HARBOR_ORCHESTRATOR 2>/dev/null ;; esac; }
_xr_set() { if [ "$1" = project-init ]; then XR_PI="$2"; else XR_PO="$2"; fi; }
_xr_get() { if [ "$1" = project-init ]; then printf '%s' "$XR_PI"; else printf '%s' "$XR_PO"; fi; }
_just() { _jd="$1"; shift; just --justfile "$_jd/justfile" --working-directory "$_jd" "$@"; }
# Is the clone at <dir> current with a FRESHLY fetched origin/main? A child's dry run judges sync by the last
# fetch (project-init and projects-orchestrator both did, until their dry runs learned to fetch), so a clone
# behind passed the dry run and was refused at apply, after the box had been written (harbor#736). Judged
# here as well, against a fetch made now: a behind clone, or a fetch that fails, fails the preflight.
# --no-write-fetch-head: a dry run leaves an up-to-date clone byte-for-byte as it was (bootstrap-test).
XR_BASE=main
_xr_sync() { # <name> <dir>
  if ! git -C "$2" rev-parse --git-dir >/dev/null 2>&1; then
    log_note "$1: $2 is not a git checkout, so its sync with origin/$XR_BASE was not checked"; return 0
  fi
  if ! GIT_TERMINAL_PROMPT=0 git -C "$2" fetch --quiet --no-write-fetch-head origin "$XR_BASE" 2>"$WORK/xfetch.err" </dev/null; then
    _bad "$1: cannot fetch origin/$XR_BASE in $2, so whether the clone is current cannot be confirmed: $(head -1 "$WORK/xfetch.err")" \
      "git -C '$2' fetch origin $XR_BASE"
    return 0
  fi
  _xab="$(git -C "$2" rev-list --left-right --count "HEAD...origin/$XR_BASE" 2>/dev/null || printf '? ?')"
  _xa="${_xab%%[[:space:]]*}"; _xb="${_xab##*[[:space:]]}"
  if [ "$_xa" = 0 ] && [ "$_xb" = 0 ]; then log_ok "$1: $2 is in sync with origin/$XR_BASE (fetched just now)"; return 0; fi
  if [ "$_xa" = 0 ]; then _fx="git -C '$2' pull --ff-only origin $XR_BASE"
  else _fx="none: unpushed commits in $2 (git -C '$2' log origin/$XR_BASE..HEAD); push them through a PR, then pull"; fi
  _bad "$1: $2 is not in sync with origin/$XR_BASE (ahead $_xa, behind $_xb), so its --apply would refuse after Harbor's installers had written" "$_fx"
}
_xr_plan() { # <name>
  _xd="$(_xr_dir "$1" || :)"
  if [ -z "$_xd" ] || [ ! -f "$_xd/justfile" ]; then _xr_set "$1" skip; _unreach "$1" "no justfile at ${_xd:-<unresolved>}, so there is no \`just install\` to run (harbor#736)"; return 0; fi
  if ! command -v just >/dev/null 2>&1; then _xr_set "$1" skip; _unreach "$1" "just is not on PATH, so its \`just install\` cannot run (harbor#736)"; return 0; fi
  if ! _just "$_xd" --summary 2>/dev/null | tr ' ' '\n' | grep -qx install; then
    _xr_set "$1" skip; _unreach "$1" "$_xd has no \`install\` recipe, so deploy cannot install it (harbor#736)"; return 0
  fi
  _xr_set "$1" "$_xd"
  _xr_sync "$1" "$_xd"
  _r_rc=0; _just "$_xd" install >"$WORK/out" 2>&1 </dev/null || _r_rc=$?
  { printf '\n=== %s: just install (rc=%s)\n' "$1" "$_r_rc"; cat "$WORK/out"; } >>"$PLAN"
  [ -z "$LOG_PATH" ] || _relay "$WORK/out" >/dev/null
  if [ "$_r_rc" -eq 0 ]; then
    log_ok "$1: its dry run (just install) passes"
    # Which build, from where, into where: the recipe's own plan lines (harbor#736).
    grep -v '^[[:space:]]*$' "$WORK/out" | head -8 | sed "s|^|$1: |" | _notes
  else
    _bad "$1: its own dry run (just install, in $_xd) refuses (rc=$_r_rc), so its --apply would too" "none: its last lines below; all of them in the plan file"
    tail -5 "$WORK/out" | _notes
  fi
}

# A failed `just install --apply` said "see its FAIL and fix lines above" when the child printed none
# (harbor#736). Its reasons are read back from its output and become deploy's own FAIL and fix lines:
# the child's `  FAIL:` / `  fix:` pairs (the log shape), else the `    - <reason>` rows of the older
# `refusing --apply:` report, else a plain statement that it printed neither.
_xr_reasons() { # <file> → one "<reason><TAB><fix>" per reason, fix empty when the child gave none
  awk 'BEGIN { t = sprintf("\t") }
    /^  FAIL: / { if (r != "") print r t; r = substr($0, 9); next }
    /^  fix: /  { if (r != "") { print r t substr($0, 8); r = "" } next }
    /^    - /   { if (r != "") { print r t; r = "" } print substr($0, 7) t }
    END { if (r != "") print r t }' "$1"
}
_xr_report() { # the failed child's output is $WORK/xr.out; its name and dir are _XR_NAME and _XR_DIR
  _xr_reasons "$WORK/xr.out" >"$WORK/xr.pairs"
  if [ ! -s "$WORK/xr.pairs" ]; then
    _bad "stopped at: $_INSTALL_FAILED — later steps did not run, and it printed no FAIL or fix line" \
      "none: its whole output above; \`just install\` in $_XR_DIR is its dry run"
    return 0
  fi
  _xrfirst=1; _xrtab="$(printf '\t')"
  while IFS="$_xrtab" read -r _xrr _xrf; do
    case "$_xrf" in
      '') _xrf="none: the output above, where $_XR_NAME gave no fix; \`just install\` in $_XR_DIR is its dry run" ;;
      'none automatic — '*) _xrf="none: ${_xrf#none automatic — }" ;;
    esac
    if [ "$_xrfirst" -eq 1 ]; then _bad "stopped at: $_INSTALL_FAILED — $_xrr (later steps did not run)" "$_xrf"
    else _bad "$_XR_NAME: $_xrr" "$_xrf"; fi
    _xrfirst=0
  done <"$WORK/xr.pairs"
}

# ── THE PLAN: every installer's own dry run. A dry run that fails predicts an apply that fails. ──
# (The install standard: a dry run exits 1 whenever its --apply would refuse, constitution's loss
# check included, so no rehearsal on a copy is needed.)
PROD_GUARD=1
_plan() {
  log_head "plan · each installer's own dry run (its verdicts here; the full text in the plan file)"
  # The installers print `(replace)` for identical files too; install-drift says what really differs.
  if [ -d "$CFG/bin" ] && _want_any runtime floor; then
    sh "$ROOT/bin/install-drift.sh" --dir "$CFG" --ref HEAD >"$WORK/drift.pre" 2>&1 || true
    cat "$WORK/drift.pre" >>"$PLAN"
    [ -z "$LOG_PATH" ] || _relay "$WORK/drift.pre" >/dev/null
    log_note "installed bin/ vs this commit: $(sed -n 's/.*\(current=[0-9]* stale=[0-9]* modified=[0-9]* unsourced=[0-9]*\).*/\1/p' "$WORK/drift.pre" | tail -1)"
    awk '$1=="FAIL:" && $2=="stale" { sub(/^  FAIL: /, ""); print }' "$WORK/drift.pre" | head -8 | _notes
    if awk '$1=="FAIL:" && $2=="modified"' "$WORK/drift.pre" | grep -q .; then
      log_note 'hand-edited on the box (bytes match no commit); the install overwrites them, the snapshot keeps them:'
      awk '$1=="FAIL:" && $2=="modified" { sub(/^  FAIL: /, ""); print }' "$WORK/drift.pre" | _notes
    fi
  fi
  for _p in "runtime:runtime-install.sh --live$AL" "floor:floor-install.sh --live$AL$FLOOR_OPTS" 'prod-guard:prod-guard-install.sh --live' \
            "constitution:constitution-install.sh --live$AL" 'inject:inject-install.sh --live' 'sec0:sec0-harden.sh --live'; do
    _want "${_p%%:*}" || continue
    _p="${_p#*:}"
    _r_rc=0
    # shellcheck disable=SC2086
    sh "$ROOT/bin/"$_p >"$WORK/out" 2>&1 </dev/null || _r_rc=$?
    { printf '\n=== %s (rc=%s)\n' "$_p" "$_r_rc"; cat "$WORK/out"; } >>"$PLAN"
    # prod-guard copies project-init's prod_guard.py; a box without project-init cannot install it.
    if [ "${_p%% *}" = prod-guard-install.sh ] && grep -q '^  FAIL: no prod_guard.py at' "$WORK/out"; then
      [ -z "$LOG_PATH" ] || _relay "$WORK/out" >/dev/null
      PROD_GUARD=0; _unreach prod-guard "$(sed -n 's/^  FAIL: //p' "$WORK/out" | head -1); it is copied from a project-init checkout (PROJECT_INIT_SRC)"; continue
    fi
    if [ "$_r_rc" -ne 0 ]; then
      _bad "${_p%% *}: its own dry run FAILED (rc=$_r_rc), so its install would too" "none: its FAIL and fix lines below"
      _relay --brief "$WORK/out"
      continue
    fi
    # prod_guard.py becomes a hook in every session, so its source must be reviewed text too.
    if [ "${_p%% *}" = prod-guard-install.sh ]; then
      _pg="$(sed -n 's|^  note: source: \(/.*\) (upstream source repo)$|\1|p' "$WORK/out" | head -1)"
      if [ -n "$_pg" ]; then
        _pgb="$(git -C "$(dirname "$_pg")" symbolic-ref --short -q HEAD 2>/dev/null || true)"
        _pgd="$(git -C "$(dirname "$_pg")" --no-optional-locks status --porcelain -- "$_pg" 2>/dev/null || true)"
        if [ "$_pgb" != "$BASE" ] || [ -n "$_pgd" ]; then
          if [ -n "$_pgd" ]; then _fx="none: harbor#457 — commit or discard the edits to $_pg in its own repo"
          else _fx="git -C '$(dirname "$_pg")' switch $BASE"; fi
          _bad "prod-guard-install: $_pg is on '${_pgb:-detached}'${_pgd:+ with uncommitted edits}, not a clean $BASE" "$_fx"
          continue
        fi
      fi
    fi
    log_ok "${_p%% *}: its dry run passes"
    _relay --brief "$WORK/out"
  done
  _want_any packs inject && _packs_plan
  for _x in project-init projects-orchestrator; do _want "$_x" && _xr_plan "$_x"; done
  [ -z "$UNREACH" ] || _unreachable
  return 0
}

# ── UNREACHABLE: asked for, and cannot be installed here (operator decision, 2026-09-30) ──────────
# These were skip: lines, so a new box reported "installed and verified" having installed only Harbor.
# Now they fail preflight; the fix is this run with --only every selected component but them.
UNREACH=''
_unreach() { # <component> <why>
  UNREACH="${UNREACH:+$UNREACH }$1"; printf '%s: %s\n' "$1" "$2" >>"$WORK/unreach"
}
_only_cmd() { # <c1,c2…> — this run's command, its --only replaced by those; opt-ins and mode kept
  _oc_args=''; _oc_drop=0
  for _oc in $IL_ARGV; do  # deploy's own words: flags and a comma list, never a quoted value
    if [ "$_oc_drop" -eq 1 ]; then _oc_drop=0; continue; fi
    if [ "$_oc" = --only ]; then _oc_drop=1; continue; fi
    _oc_args="$_oc_args $_oc"
  done
  _oc_a=''; [ "$IL_APPLY" -eq 0 ] || _oc_a=' --apply'
  printf "sh '%s/bin/deploy.sh'%s --only %s%s --live%s" "$ROOT" "$_oc_a" "$1" "$_oc_args" "$AL"
}
_unreachable() {
  _ur_keep=''
  for _uc in $COMPONENTS; do
    _want "$_uc" || continue
    case " $UNREACH " in *" $_uc "*) continue ;; esac
    _ur_keep="${_ur_keep:+$_ur_keep,}$_uc"
  done
  if [ -n "$_ur_keep" ]; then _fx="$(_only_cmd "$_ur_keep")"
  else _fx='none: the reasons below — make each one reachable, then re-run'; fi
  _bad "cannot install here: $(printf '%s' "$UNREACH" | sed 's/ /, /g'). Asked for, so this run fails rather than report success without them: leave them out with --only, or make them reachable (the reasons below)" "$_fx"
  _notes <"$WORK/unreach"
}

# ── INSTALL: order is load-bearing ────────────────────────────────────────────
# constitution first: its loss check refuses on apply, so it must refuse before anything else wrote.
# shim before runtime: shim-install owns the ~/.local/bin links, `harbor` included (shims.tsv).
# sec0 before runtime: it writes the SEC-0 deny base the floor assumes, and re-pins what it wrote.
# runtime before floor: floor-install writes the B6 content pins, so it runs after the files it pins.
# inject before packs: inject-install rebuilds inject.d from scratch, which drops a pack's notes; packs before the skill
# book, which is generated from the skills the box then holds, packs' included (harbor#1149).
# shim again after packs: a pack's commands are linked from the shims.d fragment its install wrote (harbor#1149), which the
# first shim run, before the packs, could not have read on a box that never had them.
# The two other repos last (harbor#736): Harbor's floor is in place before any other tool is replaced.
_install() {
  log_head 'install'
  for _p in "constitution:constitution-install.sh --apply --live$AL" \
            'shim:shim-install.sh --live --apply' \
            'sec0:sec0-harden.sh --apply --live' \
            "runtime:runtime-install.sh --live --apply$AL" \
            "floor:floor-install.sh --live --apply$AL$FLOOR_OPTS" \
            'prod-guard:prod-guard-install.sh --live --apply' \
            "skills:skills-install.sh --all --apply --live$AL" \
            "skills:skills-install.sh commands --all --apply --live$AL" \
            'inject:inject-install.sh --live --apply' \
            'packs:PACKS' \
            'packs:shim-install.sh --live --apply' \
            'skills:skill-book.sh install --apply --live' \
            'project-init:XREPO' 'projects-orchestrator:XREPO'; do
    _c="${_p%%:*}"; _p="${_p#*:}"
    if [ "$_c" = packs ]; then _want_any packs inject || continue; else _want "$_c" || continue; fi
    if [ "$_p" = PACKS ]; then _packs_install || return 1; continue; fi
    if [ "$_p" = XREPO ]; then
      _xd="$(_xr_get "$_c")"
      case "$_xd" in ''|skip) continue ;; esac
      log_note "running: just install --apply, in $_xd"
      _xrc=0; _run _just "$_xd" install --apply || _xrc=$?
      [ "$_xrc" -eq 0 ] || { _INSTALL_FAILED="$_c: just install --apply (rc=$_xrc)"; cp "$WORK/out" "$WORK/xr.out"; _XR_NAME="$_c"; _XR_DIR="$_xd"; return 1; }
      continue
    fi
    case "$_p" in
      prod-guard-install*) [ "$PROD_GUARD" -eq 1 ] || continue ;;
      # skills-install treats a missing skills dir as a precondition, and no installer creates it.
      'skills-install.sh --all'*) mkdir -p "$CFG/skills" ;;
    esac
    log_note "running: $_p"
    # shellcheck disable=SC2086
    _run sh "$ROOT/bin/"$_p || { _INSTALL_FAILED="$_p"; return 1; }
  done
}

_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
# The row restore.sh demands (harbor#769): the snapshot's hash, its path, when, and the hashes of its set
# and of its ~/.local/bin record (harbor#770), which restore.sh reads only through this row.
_ledger_row() {
  _lh="$(_sha256 <"$SNAP/config.tgz")" && _ls="$(_sha256 <"$SNAP/set.txt")" && _lb="$(_sha256 <"$SNAP/local-bin.tsv")" || return 1
  [ "${#_lh}" -eq 64 ] && [ "${#_ls}" -eq 64 ] && [ "${#_lb}" -eq 64 ] || return 1
  printf '%s %s %s set=%s bin=%s\n' "$_lh" "${SNAP#"$CFG"/}/config.tgz" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_ls" "$_lb"
}

# The shims.tsv target a name is linked to, or nothing: a regular file with those bytes is a copy.
_shim_want() { # <name>
  _sw="$(awk -F'\t' -v n="$1" '$1 == n && NF >= 3 { print $2 "\t" $3; exit }' "$ROOT/CONTRACTS/shims.tsv" 2>/dev/null || :)"
  [ -n "$_sw" ] || return 0
  printf '%s/%s' "$(sh "$ROOT/bin/roots.sh" --get "${_sw%%	*}" 2>/dev/null || :)" "${_sw#*	}"
}
# ~/.local/bin as a restore can use it (harbor#770): the listing it replaces could not put a link back.
_local_bin_record() { # <out>
  {
    printf '# local-bin.tsv (harbor#770): <name> TAB <link|copy|file> TAB <link target | git blob of a copy or file>\n'
    printf '# dir: %s\n' "$(_phys "$LOCAL_BIN")"
    if [ -d "$LOCAL_BIN" ]; then
      for _e in "$LOCAL_BIN"/* "$LOCAL_BIN"/.[!.]*; do
        [ -e "$_e" ] || [ -L "$_e" ] || continue
        _n="${_e##*/}"
        case "$_n" in *'	'*) continue ;; esac
        if [ -L "$_e" ]; then printf '%s\tlink\t%s\n' "$_n" "$(readlink "$_e")"
        elif [ -f "$_e" ]; then
          _k='file'; _w="$(_shim_want "$_n")"
          if [ -n "$_w" ] && [ -f "$_w" ] && cmp -s "$_e" "$_w"; then _k=copy; fi
          printf '%s\t%s\t%s\n' "$_n" "$_k" "$(il_blob "$_e")"
        fi
      done
    fi
  } >"$1"
}

_snapshot() {
  log_head 'snapshot · everything the installers write, before they write it'
  SNAP="$CFG/backups/deploy-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$SNAP"
  # set.txt is what restore.sh moves aside, absent entries included, so files a run ADDS go too.
  set -f
  # shellcheck disable=SC2086
  printf '%s\n' $SNAP_SET >"$SNAP/set.txt"
  set +f
  _paths=""
  while IFS= read -r _s; do
    # shellcheck disable=SC2086,SC2231
    for _p in "$CFG"/$_s; do [ -e "$_p" ] && _paths="$_paths ${_p##*/}"; done
  done <"$SNAP/set.txt"
  # shellcheck disable=SC2086
  if tar -czf "$SNAP/config.tgz" -C "$CFG" $_paths && tar -tzf "$SNAP/config.tgz" >/dev/null \
     && _local_bin_record "$SNAP/local-bin.tsv" \
     && _row="$(_ledger_row)" && printf '%s\n' "$_row" >>"$CFG/.helm-snapshots"; then
    ls -A "$CFG" >"$SNAP/top-level.txt"
    cp "$PLAN" "$SNAP/plan.txt" 2>/dev/null || true
    log_ok "snapshot: $SNAP/config.tgz ($(du -h "$SNAP/config.tgz" | awk '{print $1}')), recorded in .helm-snapshots"
    log_ok "snapshot: $SNAP/local-bin.tsv, every entry of $LOCAL_BIN as restore.sh can put a link back (harbor#770)"
  else
    _bad 'snapshot failed; nothing has been installed' "none: the tar error above; $SNAP"; return 1
  fi
}

# One restore code path (harbor#765): restore.sh's own plan, then the operator's yes. --accept-loss,
# because removing floor surfaces this run ADDED is exactly what undoing the run means.
_restore_offer() {
  log_note 'restore puts the config dir back as it was before this run, through bin/restore.sh:'
  if ! _run sh "$ROOT/bin/restore.sh" --live --from "$SNAP" --accept-loss; then
    _bad "restore.sh cannot restore this run's snapshot (above); the pre-run state is $SNAP/config.tgz" \
      'none: the restore.sh FAIL and fix lines above'
    return 0
  fi
  if ! _ask 'Restore the snapshot now?'; then
    log_note 'not restored. To restore later, from a terminal:'
    il_next "sh '$ROOT/bin/restore.sh' --apply --live --from '$SNAP' --accept-loss"
    return 0
  fi
  if _run sh "$ROOT/bin/restore.sh" --apply --live --from "$SNAP" --accept-loss; then
    _v="$(_b6_verdict)"
    case "$_v" in
      BLOCKED:*) _bad "restored, but the next session would be BLOCKED: ${_v#BLOCKED:}" 'none: the B6 reason above, which names its own recovery' ;;
      *)         log_ok "restored; the next session's B6 verdict: ${_v%%:*}" ;;
    esac
    _recheck
  else
    _bad "restore FAILED (above): the pre-run state is $SNAP/config.tgz" 'none: the restore.sh FAIL and fix lines above'
  fi
}

# Every check again, on the box the restore left (install standard §4): what to do next is decided from
# what IS there, not from the run that was undone, and the log keeps both.
_recheck() {
  log_head 're-check · every check again, on the restored box'
  _rk="$FAILS"; REPIN_DECLINED=1
  _verify
  _floor_verify
  if [ "$FAILS" -eq "$_rk" ]; then log_ok 're-check: the restored box passes every check'
  else log_note "re-check: $((FAILS - _rk)) check(s) fail on the restored box; each FAIL line above names it"; fi
}

# ── VERIFY: ask the box, never infer from exit codes alone ────────────────────
_verify() {
  log_head 'verify'
  _v="$(_b6_verdict)"
  case "$_v" in
    clean)      log_ok 'B6: the next session will start' ;;
    advisory:*) log_note "B6 advisory: ${_v#advisory:}" ;;
    *)          _bad "B6: the next session would be BLOCKED. ${_v#BLOCKED:}" 'none: the B6 reason above, which names its own recovery' ;;
  esac

  # stale/modified = an install did not land; unsourced is the box's own extra file (advisory).
  if _want_any runtime floor; then
    sh "$ROOT/bin/install-drift.sh" --dir "$CFG" --ref HEAD >"$WORK/drift" 2>&1 || true
    [ -z "$LOG_PATH" ] || _relay "$WORK/drift" >/dev/null
    _sum="$(sed -n 's/.*\(current=[0-9]* stale=[0-9]* modified=[0-9]* unsourced=[0-9]*\).*/\1/p' "$WORK/drift" | tail -1)"
    case " $_sum " in
      *' stale=0 modified=0 '*) log_ok "installed bin/ matches this commit: $_sum" ;;
      '  ') _bad 'install-drift printed no summary' 'none: its output below'; tail -5 "$WORK/drift" | _notes ;;
      *)  _bad "installed bin/ differs from this commit: $_sum" 'none: the install-drift rows below, one per file'
          awk '$1=="FAIL:" && ($2=="stale" || $2=="modified") { sub(/^  FAIL: /, ""); print }' "$WORK/drift" | head -10 | _notes ;;
    esac
  fi

  if ! _want shim; then :
  elif [ -e "$LOCAL_BIN/harbor" ] && cmp -s "$ROOT/bin/harbor" "$LOCAL_BIN/harbor"; then
    if ( cd / && "$LOCAL_BIN/harbor" browser route >/dev/null 2>&1 ); then log_ok 'harbor dispatcher current and runs from a foreign cwd'
    else _bad 'harbor dispatcher is current but does not run from outside the repo' "cd / && '$LOCAL_BIN/harbor' browser route"; fi
  else
    _bad "$LOCAL_BIN/harbor is missing or differs from bin/harbor" "sh '$ROOT/bin/deploy.sh' --apply --only shim --live"
  fi

  _refcheck

  # The other repos' installed builds against their trees (harbor#736): their --check exits non-zero on drift.
  for _x in project-init projects-orchestrator; do
    _want "$_x" || continue
    _xd="$(_xr_get "$_x")"
    case "$_xd" in ''|skip) continue ;; esac
    _xrc=0; _just "$_xd" install --check >"$WORK/xcheck" 2>&1 </dev/null || _xrc=$?
    [ -z "$LOG_PATH" ] || _relay "$WORK/xcheck" >/dev/null
    if [ "$_xrc" -eq 0 ]; then log_ok "$_x: the installed build matches its tree (just install --check)"
    else _bad "$_x: the installed build differs from its tree (just install --check, rc=$_xrc)" "sh '$ROOT/bin/deploy.sh' --apply --only $_x --live"
         tail -5 "$WORK/xcheck" | _notes; fi
  done

  sh "$ROOT/bin/install-stamp.sh" --show "$CFG" 2>/dev/null | sed 's/^/install stamp: /' | _notes || true
}

_refcheck() { # advisory: does the installed surface hold together (every hook, pin and citation)?
  if sh "$ROOT/bin/reference-check.sh" --live >"$WORK/ref" 2>&1; then log_ok 'reference-check: the installed surface holds together'
  else log_note "reference-check --live reports findings (advisory): sh '$ROOT/bin/reference-check.sh' --live"; fi
  [ -z "$LOG_PATH" ] || _relay "$WORK/ref" >/dev/null
}

# Last, so its B8 check sees the re-pin decision rather than the state before it.
_floor_verify() {
  _want_any runtime floor sec0 prod-guard || return 0
  log_head 'floor-verify · fires known-blocked shapes at the installed floor'
  _fv_rc=0
  env -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW CLAUDE_CONFIG_DIR="$CFG" sh "$ROOT/bin/floor-verify.sh" --live >"$WORK/fv" 2>&1 || _fv_rc=$?
  _fvv="$(sed -n 's/^  note: \(FLOOR IS .*\)$/\1/p' "$WORK/fv" | tail -1)"; [ -n "$_fvv" ] || _fvv="$(tail -1 "$WORK/fv")"
  if [ "$_fv_rc" -eq 0 ]; then
    log_ok "floor-verify: $_fvv"
  elif [ "$REPIN_DECLINED" -eq 1 ] && grep -q '^  FAIL: ' "$WORK/fv" && ! awk '/^  FAIL: / && !/B8/' "$WORK/fv" | grep -q .; then
    log_note 'floor-verify: only B8 fails, because no re-pin was made; the rest of the floor is on'
  else
    _bad "floor-verify: $_fvv" 'none: the floor-verify FAIL and fix lines below'
    _relay --brief "$WORK/fv"
  fi
  [ -z "$LOG_PATH" ] || _relay "$WORK/fv" >/dev/null
}

# ── RE-PIN: the operator's decision, shown before it is asked ─────────────────
_repin() {
  log_head 'B8 re-pin · yours to decide'
  if ! _b8_manifest "$WORK/b8.post"; then
    _bad 'the instruction manifest could not be built; no re-pin offered' \
      "none: the error of sh '$ROOT/bin/pin-instructions.sh' --print --live"
    return 0
  fi
  if [ ! -f "$B8PIN" ]; then
    log_note 'the instruction surfaces have never been pinned on this box'
    if _ask 'Pin them now, as installed?'; then
      if _run sh "$ROOT/bin/pin-instructions.sh" --apply --live; then log_ok 'pinned'
      else _bad 'pin FAILED' 'none: the pin-instructions lines above'; fi
    else
      REPIN_DECLINED=1
      log_note 'not pinned. When ready, from a terminal:'
      il_next "sh '$ROOT/bin/pin-instructions.sh' --apply --live"
    fi
    return 0
  fi
  _b8_paths "$B8PIN" "$WORK/b8.post" >"$WORK/b8.drift"
  if [ ! -s "$WORK/b8.drift" ]; then
    log_ok 'instruction surfaces match their pin; nothing to re-pin'; return 0
  fi
  # By this deploy = differs between the pre- and post-install manifests; the rest predates it.
  if [ -f "$WORK/b8.pre" ]; then _b8_paths "$WORK/b8.pre" "$WORK/b8.post" >"$WORK/b8.byme"
  else cp "$WORK/b8.drift" "$WORK/b8.byme"; fi
  comm -12 "$WORK/b8.drift" "$WORK/b8.byme" >"$WORK/b8.mine"
  comm -23 "$WORK/b8.drift" "$WORK/b8.byme" >"$WORK/b8.prior"
  log_note "Changed by THIS deploy ($(wc -l <"$WORK/b8.mine" | tr -d ' ')); * = also had unpinned changes before it:"
  awk 'NR == FNR { p[$0] = 1; next } { print (($0 in p) ? $0 "  *" : $0) }' "$WORK/b8.drift.pre" "$WORK/b8.mine" | head -25 | sed 's/^/  /' | _notes
  if [ -s "$WORK/b8.prior" ]; then
    log_note "Changed BEFORE this deploy, NOT by it — review these ($(wc -l <"$WORK/b8.prior" | tr -d ' ')):"
    head -25 "$WORK/b8.prior" | sed 's/^/  /' | _notes
  fi
  log_note 'a re-pin approves ALL of the above as intended'
  if _ask 'Re-pin the instruction surfaces?'; then
    if _run sh "$ROOT/bin/pin-instructions.sh" --apply --live; then log_ok 're-pinned'
    else _bad 're-pin FAILED' 'none: the pin-instructions lines above'; fi
  else
    REPIN_DECLINED=1
    log_note 'not re-pinned. When you have reviewed it, from a terminal:'
    il_next "sh '$ROOT/bin/pin-instructions.sh' --apply --live"
  fi
}

_b6_state() {
  _want floor || return 0
  if _b6_installed; then
    log_ok 'B6 is enabled; floor-install refreshed it and its pin (--with-b6), nothing more to do'
  else
    log_note 'B6 is not enabled. After you restart a session and it works:'
    il_next "sh '$ROOT/bin/deploy.sh' --apply --only floor --with-b6 --live"
  fi
}

# ── PRUNE: the leftovers, found by code and moved, never deleted by hand (install standard §5) ──────
# Everything moves into backups/pruned-<TS>/, at its path under the config dir (or HOME/<path> for one
# outside it), so a prune is undone by moving it back. The one deletion is the second pass: pruned-*
# dirs older than 30 days. Nothing here judges by a name alone where bytes can be asked instead.
PRUNE_KEEP=10; PRUNE_DAYS=7; PRUNE_AFTER=30
PDIR=''
_pr_add() { printf '%s\t%s\n' "$1" "$2" >>"$WORK/prune"; }  # <path> <why>
_pr_has() { awk -F'\t' -v p="$1" '$1 == p { f = 1 } END { exit !f }' "$WORK/prune" 2>/dev/null; }
_pr_find() {
  : >"$WORK/prune"; : >"$WORK/prune.kept"
  # 1 · the retired baseline (harbor#765): its archives and pointer, and baseline-pin.sh WITH its B6 pin.
  # A pin whose file is gone blocks every session (B6: "guard missing"), so the two move together.
  [ ! -e "$CFG/.helm-baseline" ] || _pr_add "$CFG/.helm-baseline" 'the retired baseline pointer (harbor#765: deploy snapshots replaced it)'
  for _f in "$CFG"/backups/config-baseline-*.tgz "$CFG"/config-baseline-*.tgz; do
    [ -f "$_f" ] && _pr_add "$_f" 'a retired baseline archive (harbor#765)'
  done
  if [ -e "$CFG/bin/baseline-pin.sh" ] || [ -e "$CFG/.helm-pins/baseline-pin.sh.sha256" ]; then
    [ ! -e "$CFG/bin/baseline-pin.sh" ] || _pr_add "$CFG/bin/baseline-pin.sh" 'retired (harbor#765); moves with its B6 pin'
    [ ! -e "$CFG/.helm-pins/baseline-pin.sh.sha256" ] || _pr_add "$CFG/.helm-pins/baseline-pin.sh.sha256" 'the B6 pin of the retired baseline-pin.sh; moves with it'
  fi
  # 2 · files the repo shipped and no longer ships: install-drift's "deleted from the repo" rows, and only
  # when the bytes are a commit's (il_known), so box-only work is never taken for a leftover.
  sh "$ROOT/bin/install-drift.sh" --dir "$CFG" --ref HEAD >"$WORK/drift.prune" 2>&1 || :
  awk '$1 == "FAIL:" && $2 == "unsourced" && /deleted from the repo/ { print $3 }' "$WORK/drift.prune" | while IFS= read -r _b; do
    case "$_b" in */*) _r="$_b" ;; *) _r="bin/$_b" ;; esac
    _pr_has "$CFG/$_r" && continue
    if il_known "$CFG" "$_r" "$CFG/$_r" "$ROOT" "$_r"; then
      _pr_add "$CFG/$_r" "the repo shipped it and no longer does (last in $(_git log -1 --format=%h -- "$_r"))"
      [ ! -e "$CFG/.helm-pins/${_r##*/}.sha256" ] || _pr_add "$CFG/.helm-pins/${_r##*/}.sha256" "the B6 pin of $_r; moves with it"
    else
      printf '%s\t%s\n' "$CFG/$_r" 'the repo once had this path, but these bytes are in no commit: box-only work, kept' >>"$WORK/prune.kept"
    fi
  done
  # Skills and commands the repo no longer ships: every file's bytes a commit's, and no current skill of
  # the same name in any letter case (a case-insensitive volume shows one dir under both spellings).
  _heads="$(_git ls-tree --name-only HEAD skills/ vendor/skills/ 2>/dev/null | sed 's|.*/||' | tr 'A-Z' 'a-z')"
  for _d in "$CFG"/skills/*/; do
    [ -d "$_d" ] && [ ! -L "${_d%/}" ] || continue
    _n="$(basename "$_d")"
    printf '%s\n' "$_heads" | grep -qxF "$(printf '%s' "$_n" | tr 'A-Z' 'a-z')" && continue
    [ -n "$(_git log -1 --format=%h -- "skills/$_n" "vendor/skills/$_n" 2>/dev/null)" ] || continue
    _all=1
    ( cd "$_d" && find . -name __pycache__ -prune -o -type f ! -name .DS_Store ! -name '*.pyc' -print | sed 's|^\./||' ) >"$WORK/prune.files"
    while IFS= read -r _f; do
      il_known "$CFG" "skills/$_n/$_f" "$_d$_f" "$ROOT" "skills/$_n/$_f" "vendor/skills/$_n/$_f" || { _all=0; break; }
    done <"$WORK/prune.files"
    if [ "$_all" -eq 1 ]; then _pr_add "$CFG/skills/$_n" 'a skill the repo shipped and no longer does; every file is a commit'"'"'s'
    else printf '%s\t%s\n' "$CFG/skills/$_n" 'a skill the repo once shipped, holding bytes in no commit: kept' >>"$WORK/prune.kept"; fi
  done
  _cheads="$(_git ls-tree --name-only HEAD commands/ 2>/dev/null | sed 's|.*/||' | tr 'A-Z' 'a-z')"
  for _f in "$CFG"/commands/*.md; do
    [ -f "$_f" ] || continue
    _n="${_f##*/}"
    printf '%s\n' "$_cheads" | grep -qxF "$(printf '%s' "$_n" | tr 'A-Z' 'a-z')" && continue
    [ -n "$(_git log -1 --format=%h -- "commands/$_n" 2>/dev/null)" ] || continue
    if il_known "$CFG" "commands/$_n" "$_f" "$ROOT" "commands/$_n"; then _pr_add "$_f" 'a command the repo shipped and no longer does'
    else printf '%s\t%s\n' "$_f" 'a command the repo once shipped, holding bytes in no commit: kept' >>"$WORK/prune.kept"; fi
  done
  # 3 · prod-guard-install's old backups in the config root (install-lib backs up beside the log now).
  for _f in "$CFG"/settings.json.bak.*; do [ -e "$_f" ] && _pr_add "$_f" "prod-guard-install's old backup in the config root"; done
  # 4 · backups beyond retention: per installer, the newest $PRUNE_KEEP and anything younger than
  # $PRUNE_DAYS days stay. A tool dir holds <TS> runs; a legacy entry groups by its name before the date.
  for _e in "$CFG"/backups/*; do
    [ -e "$_e" ] || continue
    _n="${_e##*/}"
    case "$_n" in pruned-*|config-baseline-*) continue ;; esac
    if [ -d "$_e" ] && ! printf '%s' "$_n" | grep -qE '[0-9]{8}'; then
      for _r in "$_e"/*; do [ -e "$_r" ] && printf '%s\t%s\n' "$_n" "$_r"; done
    elif printf '%s' "$_n" | grep -qE '[0-9]{8}'; then
      printf '%s\t%s\n' "legacy:$(printf '%s' "$_n" | sed -E 's/[0-9]{8}.*$//')" "$_e"
    fi
  done | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2r >"$WORK/prune.bk"
  awk -F'\t' '{ n[$1]++; if (n[$1] > K) print $2 }' K="$PRUNE_KEEP" "$WORK/prune.bk" | while IFS= read -r _r; do
    [ -n "$(find "$_r" -prune -mtime -"$PRUNE_DAYS" 2>/dev/null)" ] && continue
    _pr_add "$_r" "beyond retention: the newest $PRUNE_KEEP of its installer and anything younger than $PRUNE_DAYS days stay"
  done
  # 5 · a stale project-init bootstrap clone: install.sh's second copy, which nothing on PATH runs.
  _pic="$HOME/.local/share/project-init"
  if [ -d "$_pic/.git" ]; then
    _used=''
    for _l in "$LOCAL_BIN"/*; do
      [ -L "$_l" ] || continue
      case "$(readlink "$_l")" in "$_pic"/*|"$_pic") _used="${_l##*/}" ;; esac
    done
    if [ -z "$_used" ]; then _pr_add "$_pic" "project-init's bootstrap clone: nothing in $LOCAL_BIN runs it (the uv tool is its own copy)"
    else printf '%s\t%s\n' "$_pic" "project-init's bootstrap clone: $LOCAL_BIN/$_used still runs it, kept" >>"$WORK/prune.kept"; fi
  fi
  # 6 · ~/.local/bin: a dangling link, and a shim some other owner linked (harbor#708: shims.tsv owns
  # them; runtime-install used to link idea/memory/gcx/gcloud into the config dir).
  for _l in "$LOCAL_BIN"/* "$LOCAL_BIN"/.[!.]*; do
    [ -L "$_l" ] || continue
    _t="$(readlink "$_l")"
    if [ ! -e "$_l" ]; then _pr_add "$_l" "a dangling link: $_t does not exist"; continue; fi
    _w="$(_shim_want "${_l##*/}")"
    if [ -n "$_w" ] && [ "$_t" != "$_w" ]; then
      case "$_t" in "$CFG"/*) _pr_add "$_l" "double-owned: CONTRACTS/shims.tsv owns it (-> $_w), this link -> $_t is the retired runtime-install one (harbor#708)"; SHIM_AFTER=1 ;; esac
    fi
  done
  return 0
}
SHIM_AFTER=0
_pr_move() { # <path>
  case "$1" in "$CFG"/*) _pr="${1#"$CFG"/}" ;; "$HOME"/*) _pr="HOME/${1#"$HOME"/}" ;; *) _pr="ROOT$1" ;; esac
  if [ -e "$PDIR/$_pr" ] || [ -L "$PDIR/$_pr" ]; then _bad "$PDIR/$_pr already exists; $1 is left where it is" 'none: pick the older of the two by hand'; return 1; fi
  if mkdir -p "$(dirname -- "$PDIR/$_pr")" && mv "$1" "$PDIR/$_pr"; then
    case "$1" in "$CFG"/*) il_manifest_drop "$_pr" ;; esac
    log_ok "moved $1 -> $PDIR/$_pr"; return 0
  fi
  _bad "could not move $1 into $PDIR" 'none: the mv error above'; return 1
}
_prune() {
  log_head "prune · what the box holds that nothing installs any more"
  _pr_find
  _np="$(grep -c . "$WORK/prune" || :)"
  PDIR="$CFG/backups/pruned-$(date +%Y%m%d-%H%M%S)"
  while IFS='	' read -r _p _why; do
    [ -n "$_p" ] || continue
    if [ "$IL_APPLY" -eq 0 ]; then log_note "would move $_p ($_why)"; continue; fi
    # A bin/ file and its B6 pin move as one: the second failing puts the first back.
    case "$_p" in
      "$CFG"/.helm-pins/*) continue ;;  # moved with its file below, or alone when it has none
    esac
    _pr_move "$_p" || continue
    case "$_p" in "$CFG"/bin/*)
      _pin="$CFG/.helm-pins/${_p##*/}.sha256"
      if _pr_has "$_pin" && [ -e "$_pin" ] && ! _pr_move "$_pin"; then
        mv "$PDIR/${_p#"$CFG"/}" "$_p" && log_warn "put $_p back: its B6 pin could not move with it" && log_nofix 'the mv error above'
      fi ;;
    esac
  done <"$WORK/prune"
  # A pin whose file is already gone moves alone.
  if [ "$IL_APPLY" -eq 1 ]; then
    awk -F'\t' -v d="$CFG/.helm-pins/" 'index($1, d) == 1' "$WORK/prune" >"$WORK/prune.pins"
    while IFS='	' read -r _p _why; do [ ! -e "$_p" ] || _pr_move "$_p" || :; done <"$WORK/prune.pins"
  fi
  while IFS='	' read -r _p _why; do [ -z "$_p" ] || log_skip "$_p: $_why"; done <"$WORK/prune.kept"
  [ "$_np" -gt 0 ] || log_ok 'nothing to prune'
  [ "$SHIM_AFTER" -eq 0 ] || il_next "sh '$ROOT/bin/deploy.sh' --apply --only shim --live   # links the shims.tsv owner back"
  # The second pass: what an earlier prune moved, once it has been kept $PRUNE_AFTER days.
  log_head "prune · pruned-* dirs older than $PRUNE_AFTER days"
  _old="$(find "$CFG/backups" -maxdepth 1 -type d -name 'pruned-*' -mtime +"$PRUNE_AFTER" 2>/dev/null | LC_ALL=C sort)"
  if [ -z "$_old" ]; then log_ok "no pruned-* dir is older than $PRUNE_AFTER days"; fi
  printf '%s\n' "$_old" | while IFS= read -r _o; do
    [ -n "$_o" ] || continue
    if [ "$IL_APPLY" -eq 0 ]; then log_note "would delete $_o (moved there more than $PRUNE_AFTER days ago)"
    elif rm -rf "$_o"; then log_ok "deleted $_o (moved there more than $PRUNE_AFTER days ago)"
    else log_fail "could not delete $_o"; log_nofix 'the rm error above'; fi
  done
  il_manifest_write || :
  if [ "$IL_APPLY" -eq 0 ] && { [ "$_np" -gt 0 ] || [ -n "$_old" ]; }; then il_next "$DEPLOY_CMD   # from a terminal window"; fi
}

# ── UNINSTALL (harbor#808): the floor comes off through deploy, with an install's refusals, [y/N],
# snapshot, log and restore offer. Its verify expects the floor GONE: floor-verify, B6 and install-drift
# would call every uninstall a failure, so the check is floor-uninstall's own dry run finding nothing.
_UN_LEFT='^  note: (hook to remove|floor file to remove): '
_uninstall() {
  if [ "$IL_APPLY" -eq 1 ]; then log_head "uninstall the floor from $CFG"; else log_head "uninstall plan for $CFG (dry run: removes nothing)"; fi
  log_note "repo:       $ROOT"
  log_note "config dir: $CFG"
  _upfront
  [ "$IL_APPLY" -eq 1 ] || il_session "$DEPLOY_CMD   # from a terminal window: a session cannot run --apply"
  PLAN="$WORK/plan.txt"; : >"$PLAN"
  log_head 'preflight · nothing is removed unless every check here passes'
  _checkout
  if command -v jq >/dev/null 2>&1; then log_ok 'jq present'; else _bad 'jq is missing; floor-uninstall needs it' "$(_jq_fix)"; fi
  if [ -f "$CFG/settings.json" ]; then log_ok 'config dir has settings.json'
  else _bad "no settings.json in $CFG, so there is no floor wiring to remove" 'none: harbor#808 — there is nothing to uninstall'; fi
  if [ "$FAILS" -eq 0 ]; then
    log_head "plan · floor-uninstall's own dry run"
    _r_rc=0; sh "$ROOT/bin/floor-uninstall.sh" --live >"$WORK/out" 2>&1 </dev/null || _r_rc=$?
    cp "$WORK/out" "$PLAN"
    _relay "$WORK/out"
    [ "$_r_rc" -eq 0 ] || _bad "floor-uninstall.sh: its own dry run FAILED (rc=$_r_rc), so its removal would too" 'none: its FAIL and fix lines above'
    _packs_uninstall_plan
  fi
  if [ "$FAILS" -gt 0 ]; then log_note "PREFLIGHT FAILED ($FAILS) — nothing was removed"; log_end || :; exit 1; fi
  if [ "$IL_APPLY" -eq 0 ]; then
    log_head 'next'
    log_note 'Preflight passed; the plan is above'
    il_next "$DEPLOY_CMD   # from a terminal window"
    log_end; exit $?
  fi
  if ! _ask "Remove the floor from $CFG?"; then
    _bad 'declined at the prompt — nothing was removed' "$DEPLOY_CMD   # from a terminal window, answering y"
    log_end || :; exit 1
  fi
  _snapshot || { log_end || :; exit 1; }
  log_head 'uninstall'
  log_note 'running: floor-uninstall.sh --apply --live'
  if ! _run sh "$ROOT/bin/floor-uninstall.sh" --apply --live; then
    _bad 'stopped at: floor-uninstall.sh --apply --live' 'none: its FAIL and fix lines above'
    _restore_offer; log_end || :; exit 1
  fi
  if ! _packs_uninstall; then _restore_offer; log_end || :; exit 1; fi
  log_head 'verify · the floor is gone'
  _r_rc=0; sh "$ROOT/bin/floor-uninstall.sh" --live >"$WORK/unv" 2>&1 </dev/null || _r_rc=$?
  [ -z "$LOG_PATH" ] || _relay "$WORK/unv" >/dev/null
  if [ "$_r_rc" -ne 0 ]; then
    _bad "floor-uninstall's dry run FAILED after the removal (rc=$_r_rc), so the floor cannot be confirmed gone" 'none: its FAIL and fix lines below'
    _relay --brief "$WORK/unv"
  elif grep -qE "$_UN_LEFT" "$WORK/unv"; then
    _bad 'the floor is still present after floor-uninstall: its own dry run still lists what is below' 'none: harbor#808 — each line below is a hook or file left'
    grep -E "$_UN_LEFT" "$WORK/unv" | sed 's/^  note: //' | _notes
  else
    log_ok "the floor is gone: floor-uninstall's own dry run finds no hook and no file left to remove"
  fi
  if [ -n "$(_pack_ids)" ] || [ -n "$(ls "$CFG"/checks.d/* "$CFG"/shims.d/* 2>/dev/null)" ]; then
    _bad "a pack is still installed after the removal: $(_pack_ids | tr '\n' ' ')" 'none: harbor#1149 — pack.sh remove names what it could not take'
  else
    log_ok 'no pack is left: no manifest in .harbor-packs and no fragment in checks.d or shims.d'
  fi
  _refcheck
  log_head 'result'
  log_note "snapshot: $SNAP/config.tgz"
  if [ "$FAILS" -gt 0 ]; then
    log_note "removed, but $FAILS verification(s) failed — read the FAIL lines above"
    _restore_offer; log_end || :; exit 1
  fi
  log_note 'the floor is removed. Restart Claude Code sessions to unload it. To put it back, from a terminal:'
  il_next "sh '$ROOT/bin/restore.sh' --apply --live --from '$SNAP' --accept-loss"
  log_end; exit $?
}

# ── MAIN ──────────────────────────────────────────────────────────────────────
REPIN_DECLINED=0
[ "$UNINSTALL" -eq 0 ] || _uninstall
if [ "$PRUNE" -eq 1 ]; then
  if [ "$IL_APPLY" -eq 1 ]; then log_head "prune $CFG"; else log_head "prune plan for $CFG (dry run: nothing is moved)"; fi
  _upfront
  [ "$IL_APPLY" -eq 1 ] || il_session "$DEPLOY_CMD   # from a terminal window"
  log_head 'preflight · the checkout the leftovers are judged against'
  _checkout
  if [ "$FAILS" -gt 0 ]; then log_note "PREFLIGHT FAILED ($FAILS) — nothing was moved"; log_end || :; exit 1; fi
  _prune
  log_end; exit $?
fi
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $CFG"; else log_head "plan for $CFG (dry run: installs nothing)"; fi
log_note "repo:       $ROOT"
log_note "config dir: $CFG"
log_note "local bin:  $LOCAL_BIN"
[ -z "$COMP_NOTE" ] || log_note "$COMP_NOTE"
[ -z "$ONLY" ] || log_note "only:       $(printf '%s' "$ONLY" | tr ',' ' ') — every other component is left as it is"
_upfront
# A dry run inside a Claude session says what its --apply would do there (refused up front).
[ "$IL_APPLY" -eq 1 ] || il_session "$DEPLOY_CMD   # from a terminal window: a session cannot run --apply"

PLAN="$WORK/plan.txt"
: >"$PLAN"
_preflight
[ "$FAILS" -gt 0 ] || _plan
if [ "$IL_APPLY" -eq 0 ] && [ -s "$PLAN" ]; then
  cp "$PLAN" "${TMPDIR:-/tmp}/harbor-deploy-plan.txt" 2>/dev/null && log_note "full plan: ${TMPDIR:-/tmp}/harbor-deploy-plan.txt"
fi
if [ "$FAILS" -gt 0 ]; then
  log_note "PREFLIGHT FAILED ($FAILS) — nothing was installed"
  log_end || :
  exit 1
fi

if [ "$IL_APPLY" -eq 0 ]; then
  log_head 'next'
  log_note 'Preflight passed; the plan is above'
  il_next "$DEPLOY_CMD   # from a terminal window"
  log_end; exit $?
fi

if [ "$UNATTENDED" -eq 1 ]; then
  log_note "Install all of the above onto $CFG? — yes: --unattended, the ship runner's apply"
elif ! _ask "Install all of the above onto $CFG?"; then
  _bad 'declined at the prompt — nothing was installed' "$DEPLOY_CMD   # from a terminal window, answering y"
  log_end || :
  exit 1
fi

_snapshot || { log_end || :; exit 1; }
# Before the first install: an apply that fails midway must leave the runner an id to restore (deploy-fleet.md).
if [ "$UNATTENDED" -eq 1 ]; then
  case "$SNAP" in
    *[!A-Za-z0-9._:/@+-]*)
      _bad "the snapshot path $SNAP is not one plain token, so the runner could not restore it; nothing was installed" \
        "none: run from a config dir whose path has no spaces, or deploy from a terminal: $DEPLOY_CMD"
      log_end || :; exit 1 ;;
  esac
  printf '%s\n' "$SNAP" >"$SHIP_SNAPSHOT" || { _bad "could not write the snapshot id to $SHIP_SNAPSHOT; nothing was installed" "ls -l '$SHIP_SNAPSHOT'"; log_end || :; exit 1; }
  log_ok "snapshot id written for the runner: $SHIP_SNAPSHOT"
fi
_INSTALL_FAILED=''
if ! _install; then
  log_head 'install failed'
  if [ -s "$WORK/xr.out" ]; then _xr_report
  else _bad "stopped at: $_INSTALL_FAILED — later steps did not run" 'none: its FAIL and fix lines above'; fi
  _v="$(_b6_verdict)"
  case "$_v" in
    BLOCKED:*) _bad "the next session would be BLOCKED: ${_v#BLOCKED:}" 'none: the B6 reason above, which names its own recovery' ;;
    *)         log_note "the next session's B6 verdict: ${_v%%:*}" ;;
  esac
  _restore_offer
  log_end || :
  exit 1
fi

_verify
# Never ask to bless the surfaces of an install that already failed verification.
if [ "$FAILS" -eq 0 ]; then _repin
else REPIN_DECLINED=1; log_head 'B8 re-pin'; log_note 'not offered: verification failed above'; fi
_floor_verify
_b6_state

log_head 'result'
log_note "snapshot: $SNAP/config.tgz"
if [ "$FAILS" -gt 0 ]; then
  log_note "installed, but $FAILS verification(s) failed — read the FAIL lines above"
  _restore_offer
  log_end || :
  exit 1
fi
log_note 'installed and verified. Restart Claude Code sessions to load it.'
log_end; exit $?
