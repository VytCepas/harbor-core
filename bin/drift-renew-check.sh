#!/usr/bin/env sh
# renew-check (harbor#44 follow-through, harbor#800) — what is BUILT here and NOT RUNNING there.
#   sh drift-renew-check.sh [--apply] (--live | --dir PATH)   the token line, then one WARN + fix per finding
#   --apply   also refresh the statusline cache in that dir (.helm-renew, .helm-props); no run log
#   Exit 0 always, a usage error (2) aside: a reporter, and a non-zero exit would make its scheduled
#   caller look broken every time the box is behind.
# platform: macOS-only — the `launchctl bootstrap` fix line is the macOS arm of a uname switch; Linux prints the `systemctl --user` form instead (harbor#618).

# Why: every other surface answers "is the installed thing healthy"; nothing answered "is the installed thing the thing we built" (2026-08-13: the floor stamp sat 11 bin/hooks commits behind, so admission-cloud.sh and admission-destroy.sh gated nothing here). A deploy that never happened reads like a feature that works.
# Installs nothing: each remedy writes to a surface admission-self-edit.sh protects or calls launchctl, which the floor refuses; it prints the command for the operator's terminal. The checkout is found, never assumed: installed at $CFG/bin there is no repo above this file, so it needs $HARBOR_SCOPE_REPO (default ~/port/harbor); without a git checkout the git-dependent checks STAND DOWN and say so, never "0 behind".
# Removed notes: docs/explanation/code-cases/bin-drift-renew-check.md
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init renew-check
REPO="${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}"
AGENTS="$HOME/Library/LaunchAgents"
case "$(uname -s 2>/dev/null)" in
  Darwin) JOBSRC="$REPO/launchd"; JOBGLOB='*.plist'; JOBDEST="$AGENTS"; JOBSYS="${HARBOR_DRIFT_RENEW_DAEMONS:-/Library/LaunchDaemons}" ;;
  *) JOBSRC="$REPO/systemd"; JOBGLOB='*.timer'; JOBDEST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; JOBSYS="" ;;
esac
# The target, --apply and --live are install-lib's (lint D7). --apply refreshes a statusline cache every fleet-snapshot-refresh tick, so it keeps no run log.
il_parse "$@"
# shellcheck disable=SC2034 # IL_LOG: read by deploy-install-lib.sh
IL_LOG=0
il_target
TGT="$IL_TARGET"; APPLY="$IL_APPLY"
[ -d "$TGT" ] || il_usage_error "not a directory: $TGT"

# Every fix names THIS box (harbor#800): a live install is deploy's (install standard §4), a sandbox its installer with --dir spelled.
_fix() { # <component> <installer>
  if [ "$IL_LIVE" -eq 1 ]; then printf "sh '%s/bin/deploy.sh' --only %s --apply --live" "$REPO" "$1"
  else case "$2" in runtime-install) _fi=deploy-runtime-install ;; floor-install) _fi=admission-install ;; *) _fi="$2" ;; esac
       printf 'sh %s/bin/%s.sh --apply %s' "$REPO" "$_fi" "$(il_spell)"; fi
}

N=0; TOKENS=""; FOUND=""
note() { # <token> <detail> <fix command | none:<where>>
  N=$((N+1))
  TOKENS="${TOKENS:+${TOKENS}·}$1"
  FOUND="${FOUND}$2	$3
"
}

# ── 1 · the installed floor against the checkout ─────────────────────────────
# Counts commits touching the files THAT INSTALLER ACTUALLY INSTALLS. The old pathspec `bin/ hooks/` was wider than either installer in both directions (live box 2026-08-24: `STALE floor5` while all sixteen floor payload files matched origin/main; the five commits were runtime-install's and already delivered, and `hooks/` holds git hooks no installer ships). §2.11: a token that fires on every statusline commit is one the operator learns to skip.
STAMP="$TGT/.helm-install-stamp"

# The payload is read from the installer, never restated (T2, harbor#275; admission-install.sh does the same for runtime-install's $FILES). The installer's own file is part of its pathspec: a commit changing only admission-install.sh still means the box is behind.
# Deliberately not counted: floor-install's CONDITIONAL payload (admission-integrity.sh under --with-b6, admission-stop.sh under --with-stop) and admission-deny.sh, which it RUNS rather than lists. All three are named in prose, and grepping prose is a heuristic this file will not carry. The first two are in runtime-install's $FILES, so a commit to either still raises a `runtime` token; only the settings.json deny entries are uncovered, which needs floor-install to declare them.
# Empty means stand down, never "0 behind" (renew-check-test.sh case 4).
_payload_pathspec() { # <installer-basename> — prints one `bin/<file>` per line
  # the stamp key is the installer's pre-#961 name; W3 moved runtime-install.sh (harbor#961), W7 floor-install.sh (harbor#949)
  case "$1" in runtime-install) _pi="$REPO/bin/deploy-runtime-install.sh" ;; floor-install) _pi="$REPO/bin/admission-install.sh" ;; *) _pi="$REPO/bin/$1.sh" ;; esac
  [ -f "$_pi" ] || return 1
  _pl="$(sed -n -e 's/^GUARDS=.\(.*\).$/\1/p' \
                -e 's/^RECOVERY=.\(.*\).$/\1/p' \
                -e 's/^FILES=.\(.*\).$/\1/p' \
                -e 's/^REFRESH_ONLY=.\(.*\).$/\1/p' "$_pi" 2>/dev/null \
          | tr ' ' '\n' \
          | sed -n 's|^\([A-Za-z0-9][A-Za-z0-9._-]*\)$|bin/\1|p')"
  [ -n "$_pl" ] || return 1
  # SUITE pairs are <checkout path>:<config-dir path>; the checkout side is the pathspec (harbor#727).
  _ps="$(sed -n 's/^SUITE=.\(.*\).$/\1/p' "$_pi" 2>/dev/null | tr ' ' '\n' \
          | sed -n 's|^\([A-Za-z0-9][A-Za-z0-9._/-]*\):[A-Za-z0-9._/-]*$|\1|p')"
  _pe="$(printf '%s\n' "$_pl" | sed -n 's|^bin/||p' | while IFS= read -r _pn; do il_engine_path "$_pn"; echo; done)"
  printf 'bin/%s.sh\n%s\n%s\n%s\n' "$1" "$_pl" "$_ps" "$_pe" | sed '/^$/d' | sort -u
}
# `git rev-parse --git-dir`, not `[ -d "$REPO/.git" ]`: in a worktree `.git` is a FILE, so every worktree reported `repo?`. Hoisted because section 1b asks the same question.
_repo_ok=0
command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && _repo_ok=1
if [ "$_repo_ok" = 1 ]; then
  # Runtime first, and the order is the fix: admission-install.sh is the PIN WRITER and deploy-runtime-install.sh REPLACES four of the files it pins, so whichever runs last decides whether the pins match the bytes. Measured on a copy of the live dir: floor then runtime gives "the next SessionStart will be BLOCKED", runtime then floor is green. A remedy pasted in the order given must not end in a lockout.
  for inst in runtime-install floor-install; do
    _sha="$(sed -n "s/^$inst \([0-9a-f]*\) .*/\1/p" "$STAMP" 2>/dev/null | tail -1)"
    if [ -z "$_sha" ]; then
      note "${inst%%-*}!" "$inst has NEVER stamped this config dir — the box may be running nothing this repo built" "$(_fix "${inst%%-*}" "$inst")"
    elif ! _paths="$(_payload_pathspec "$inst")" || [ -z "$_paths" ]; then
      note "${inst%%-*}?" "$inst declares no payload this can read at $REPO/bin/$inst.sh — the installed-vs-built comparison stood down rather than reporting 0 behind" "none:bin/drift-renew-check.sh (_payload_pathspec reads GUARDS=, RECOVERY=, FILES=, REFRESH_ONLY= and SUITE=)"
    else
      # Unquoted on purpose: one git argument per line, word-split under sh.
      # shellcheck disable=SC2086
      _behind="$(git -C "$REPO" rev-list --count "$_sha..origin/main" -- $_paths 2>/dev/null || printf '')"
      if [ -n "$_behind" ] && [ "$_behind" -gt 0 ] 2>/dev/null; then
        note "${inst%%-*}$_behind" "$inst is $_behind payload commit(s) behind origin/main (installed $(printf %.7s "$_sha")) — merged guards are not gating anything here" "$(_fix "${inst%%-*}" "$inst")"
      fi
    fi
  done
else
  note "repo?" "no git checkout at $REPO — the installed-vs-built comparison stood down rather than reporting 0 behind" "none:contracts/roots.tsv (set HARBOR_SCOPE_REPO to the harbor checkout)"
fi

# ── 1b · the running constitution against origin/main ────────────────────────
# Same subject as section 1, different mechanism: policy-constitution-install.sh writes no stamp, so there is no installed-at commit to count from. Its byte-exact footprint is a stronger oracle than a commit count (as drift-install.sh chose content over a lag counter).
# Why (harbor#557): the live CLAUDE.md sat 413 B behind main for two days with every instrument green. floor-verify's install-drift never looks at CLAUDE.md, and B8 holds the file against its own pin, which says "unchanged" for a file already stale when pinned.
# Held against origin/main, not the working tree: the live constitution should carry MERGED text, and a dry run would report identical on any branch whose text matches the box, including text nobody reviewed (DE-30).
CONST_LIVE="$TGT/CLAUDE.md"
CONST_WALK_MAX="${HARBOR_DRIFT_CONSTITUTION_WALK_MAX:-60}"
if [ ! -f "$CONST_LIVE" ]; then
  note "const!" "no CLAUDE.md in ${TGT#"$HOME"/} — the constitution has never been deployed to this config dir" "$(_fix constitution constitution-install)"
elif [ "$_repo_ok" = 1 ]; then
  _cref="$(git -C "$REPO" rev-parse --verify --quiet origin/main:policy/constitution.md 2>/dev/null || printf '')"
  _clive="$(git -C "$REPO" hash-object -- "$CONST_LIVE" 2>/dev/null || printf '')"
  if [ -z "$_cref" ] || [ -z "$_clive" ]; then
    note "const?" "origin/main carries no readable policy/constitution.md at $REPO — the live-vs-merged comparison stood down rather than reporting identical" "none:harbor#557"
  elif [ "$_cref" != "$_clive" ]; then
    # The distance is walked, not guessed: the commit whose blob the box runs anchors "how far behind", and it is cheap (only once the hashes differ). The shape is drift-install.sh's history walk, over the one governed file outside `bin/`, which its loop cannot reach.
    _cb=0; _cfound=0
    for _cc in $(git -C "$REPO" rev-list --max-count="$CONST_WALK_MAX" origin/main -- policy/constitution.md 2>/dev/null); do
      [ "$(git -C "$REPO" rev-parse --verify --quiet "$_cc:policy/constitution.md" 2>/dev/null)" = "$_clive" ] && { _cfound=1; break; }
      _cb=$((_cb+1))
    done
    if [ "$_cfound" = 1 ]; then
      note "const$_cb" "the running constitution is $_cb merged commit(s) behind origin/main — every session started since has loaded rules this repo has changed" "$(_fix constitution constitution-install)"
    elif [ "$_cb" -ge "$CONST_WALK_MAX" ]; then
      # Stopped looking is not found nothing: the branches around this one print OPPOSITE remedies, so a truncated walk falling through to const+ would tell an operator to back-port a box that needs deploying. A history of exactly $CONST_WALK_MAX revisions with no match lands here too; standing down over-reports uncertainty, which costs a second look, where a wrong verdict costs a destructive edit or a stale constitution.
      note "const?" "the running constitution matches none of the last $_cb revisions of policy/constitution.md and the walk stopped there — the distance was NOT determined, which is not the same as the box being current" "HARBOR_DRIFT_CONSTITUTION_WALK_MAX=$((CONST_WALK_MAX * 4)) sh $HERE/drift-renew-check.sh $(il_spell)"
    else
      # A separate token because it is a separate remedy, and the wrong one is destructive (harbor#462): the live file was 1,933 B larger than the repo's, all appends, doctrine written into the box and committed nowhere; deploying over it destroys it with cmp reporting success. So this never prints --apply. It does not re-decide the question: policy-constitution-install.sh owns the live-only-lines comparison, and a second implementation could disagree with the gate it warns about.
      note "const+" "the running constitution matches NO commit on origin/main — it may carry text version control has never held (harbor#462), so deploying over it could destroy that text" "none:harbor#462 — back-port it through a PR; read the direction first, it writes nothing: sh $REPO/bin/policy-constitution-install.sh $(il_spell)"
    fi
  fi
fi

# ── 2 · scheduled jobs that exist in the repo and on no schedule ─────────────
# The plist is the built artifact, LaunchAgents the footprint. `launchctl list` is deliberately not the oracle: a job can be loaded from a deleted plist, and the file is what an operator can act on.
# A private layer's jobs/ is a second source of the same plists (harbor#1149, contracts/private-layer.md); the footprint they owe is the same. Darwin only; a Linux box's units are systemd/.
PJOBS=""; [ "$JOBGLOB" != '*.plist' ] || PJOBS="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}/jobs"
# Two footprints are not a miss, and one file is not always a job (false alarm: `STALE jobs4`, all four wrong). A plist can be installed as a SYSTEM daemon (audit-collector-install.sh, under sudo, as another uid), and one can ship INERT on purpose, declared by the marker `harbor:shipped-inert` anywhere in the file, so a new inert job needs no edit here. §2.11: an always-on token is one the operator skips.
_job_ok() { # <plist> — installed as an agent or as a system daemon, or declared inert
  _jb="$(basename "$1")"
  [ -f "$JOBDEST/$_jb" ] && return 0
  [ -z "$JOBSYS" ] || [ ! -f "$JOBSYS/$_jb" ] || return 0
  grep -q 'harbor:shipped-inert' "$1" 2>/dev/null
}
_missing=0
for p in "$JOBSRC"/$JOBGLOB ${PJOBS:+"$PJOBS"/*.plist}; do
  [ -f "$p" ] || continue
  _job_ok "$p" || _missing=$((_missing+1))
done
[ "$_missing" -gt 0 ] && note "jobs$_missing" "$_missing scheduled job(s) built here and installed on no schedule. List: for p in $JOBSRC/$JOBGLOB${PJOBS:+ $PJOBS/*.plist}; do [ -f \"$JOBDEST/\$(basename \$p)\" ]${JOBSYS:+ || [ -f \"$JOBSYS/\$(basename \$p)\" ]} || grep -q harbor:shipped-inert \$p || echo \$p; done" "none:${JOBSRC##*/}/ — a schedule is the operator's to install, from a terminal"

# ── 3 · the judge's own cache ────────────────────────────────────────────────
# Absent means the daily judge was never wired; stale means it stopped.
JV="$TGT/.helm-judge"
if [ ! -f "$JV" ]; then
  if [ "$JOBGLOB" = '*.plist' ]; then
    # The plist is a template (harbor#630): rendering fills this box's roots in, a cp would install the placeholders.
    _jfix="sh $REPO/bin/deploy-launchd-render.sh $REPO/launchd/com.harbor.audit.triage.plist > ~/Library/LaunchAgents/com.harbor.audit.triage.plist && launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.harbor.audit.triage.plist"
  else
    _jfix="cp $REPO/systemd/harbor-audit-triage.service $REPO/systemd/harbor-audit-triage.timer $JOBDEST/ && systemctl --user daemon-reload && systemctl --user enable --now harbor-audit-triage.timer"
  fi
  note "judge!" "no ledger verdict has ever been written — the daily judge is not installed" "$_jfix"
elif [ -n "$(find "$JV" -mtime +2 -print 2>/dev/null)" ]; then
  if [ "$JOBGLOB" = '*.plist' ]; then _jwhy="none:launchd/com.harbor.audit.triage.plist (its StandardErrorPath names the job's own error file)"
  else _jwhy="none:systemd/harbor-audit-triage.timer (journalctl --user -u harbor-audit-triage.service shows its runs)"; fi
  note "judge?" "the ledger verdict has not been rewritten in over 2 days — the job is not reporting clean, it is not reporting" "$_jwhy"
fi

# ── 4 · the instruction pin ──────────────────────────────────────────────────
# Not recomputed here: admission-integrity.sh hashes the manifest at SessionStart, and a second hash is a copy that can disagree. This reads the gate's own artifact, a pin file that does not exist.
[ -f "$TGT/.helm-instructions.sha256" ] || \
  note "pin!" "instruction surfaces are UNPINNED — nothing detects a change to what loads into every session" "sh $REPO/bin/pin-instructions.sh --apply $(il_spell)"

# ── 5 · proposal packets waiting for a human ─────────────────────────────────
# A separate cache and statusline token: "the box is behind" and "somebody must read a patch" are different jobs. Written only when proposal.sh exists (checkout only, in no installer payload).
PROPS="$TGT/.helm-props"
if [ -f "$REPO/bin/proposal.sh" ]; then
  _np="$(sh "$REPO/bin/proposal.sh" count 2>/dev/null || printf '')"
  case "$_np" in
    ''|*[!0-9]*) : ;;
    *) [ "$APPLY" = 1 ] && { ( umask 077; printf 'props %s\n' "$_np" > "$PROPS.tmp" ) && mv -f "$PROPS.tmp" "$PROPS"; }
       printf 'props %s\n' "$_np" ;;
  esac
fi

OUT="$TGT/.helm-renew"
LINE="renew $N${TOKENS:+ $TOKENS}"
_cache_ok=1
if [ "$APPLY" = 1 ]; then
  { ( umask 077; printf '%s\n' "$LINE" > "$OUT.tmp" ) && mv -f "$OUT.tmp" "$OUT"; } 2>/dev/null || _cache_ok=0
fi
# The data line first, always: the statusline refresher and `head -1` read it.
printf '%s\n' "$LINE"
# Then the log (contracts/logging.md): one WARN per finding, never FAIL, so the exit stays 0.
log_head "$TGT vs $REPO"
[ "$N" -gt 0 ] || log_ok "everything this checkout built is running in $TGT"
while IFS='	' read -r _fd _fx; do
  [ -n "$_fd" ] || continue
  log_warn "$_fd"
  case "$_fx" in none:*) log_nofix "${_fx#none:}" ;; *) log_fix "$_fx" ;; esac
done <<EOF
$FOUND
EOF
if [ "$_cache_ok" -eq 0 ]; then
  log_warn "could not write the statusline cache $OUT, so the statusline shows the last value it had"
  log_nofix "the permissions of $TGT"
fi
log_end
exit 0
