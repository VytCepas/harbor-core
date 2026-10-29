#!/usr/bin/env sh
# renew-check (harbor#44 follow-through, harbor#800) — what is BUILT here and NOT RUNNING there.
#   sh drift-renew-check.sh [--apply] (--live | --dir PATH)   the token line, then one WARN + fix per finding
#   --apply   also refresh the statusline cache in that dir (.helm-renew, .helm-props); no run log
#   Exit 0 always, a usage error (2) aside: a reporter, and a non-zero exit would make its scheduled
#   caller look broken every time the box is behind.
# platform: macOS-only — the `launchctl bootstrap` fix line is the macOS arm of a uname switch; Linux prints the `systemctl --user` form instead (harbor#618).

# One number for the statusline (stdout's first line, data), the detail for a human who asks (the
# log lines under it, each finding a WARN whose fix is aimed at THIS box: --live, or --dir '<d>').
#
# WHY. Every other surface on this box answers "is the installed thing healthy".
# NOTHING answered "is the installed thing the thing we built" — and the gap is
# not hypothetical. Measured 2026-08-13: `.helm-install-stamp` pins the floor at
# 4f997de (2026-08-09) with **11 later commits touching bin/ and hooks/**, which
# is precisely why guard-cloud.sh and guard-destroy.sh — written, tested, merged
# — gate nothing on this machine. And `launchd/com.harbor.usage.plist` has a
# counterpart in no LaunchAgents directory, so the durable usage ledger M9 built
# has never been written by a schedule.
#
# A DEPLOY THAT NEVER HAPPENED READS EXACTLY LIKE A FEATURE THAT WORKS. That is
# the whole class: the repo is green, the tests pass, the contract describes the
# behaviour, and the box does not have it. Everything here compares an artifact
# in the CHECKOUT against the same artifact's footprint on the BOX.
#
# IT INSTALLS NOTHING, and that is not timidity. Each remedy it names is a write
# to a surface guard-selfedit.sh protects, or a `launchctl` call the floor
# refuses — both deliberately out of a session's reach. It prints the command;
# the operator runs it in their own terminal.
#
# THE CHECKOUT IS FOUND, NEVER ASSUMED. Installed at $CFG/bin there is no repo
# above this file, so the comparison needs $HARBOR_REPO (default ~/port/harbor). If
# that is not a git checkout the git-dependent checks STAND DOWN and say so —
# never "0 behind", which would read as up to date.
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init renew-check
REPO="${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}"
AGENTS="$HOME/Library/LaunchAgents"
# Where a schedule is built and installed: launchd on macOS, systemd user units elsewhere (harbor#618).
case "$(uname -s 2>/dev/null)" in
  Darwin) JOBSRC="$REPO/launchd"; JOBGLOB='*.plist'; JOBDEST="$AGENTS"; JOBSYS="${HARBOR_RENEW_DAEMONS:-/Library/LaunchDaemons}" ;;
  *) JOBSRC="$REPO/systemd"; JOBGLOB='*.timer'; JOBDEST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; JOBSYS="" ;;
esac
# The target, --apply and --live are install-lib's (lint D7): physical paths, the live dir only by
# --live, and a CLAUDE_CONFIG_DIR naming another dir exits 2. Its --apply refreshes a statusline cache
# every tick of fleet-snapshot-refresh, so it keeps no run log: one per tick would be the leftover.
il_parse "$@"
IL_LOG=0
il_target
TGT="$IL_TARGET"; APPLY="$IL_APPLY"
[ -d "$TGT" ] || il_usage_error "not a directory: $TGT"

# Every fix names THIS box (harbor#800): a live install is deploy's, the one live entry (the install
# standard §4); a sandbox is fixed by its installer, --dir spelled. The pin is the operator's act.
_fix() { # <component> <installer>
  if [ "$IL_LIVE" -eq 1 ]; then printf "sh '%s/bin/deploy.sh' --only %s --apply --live" "$REPO" "$1"
  else printf 'sh %s/bin/%s.sh --apply %s' "$REPO" "$2" "$(il_spell)"; fi
}

N=0; TOKENS=""; FOUND=""
note() { # <token> <detail> <fix command | none:<where>>
  N=$((N+1))
  TOKENS="${TOKENS:+${TOKENS}·}$1"
  FOUND="${FOUND}$2	$3
"
}

# ── 1 · the installed floor against the checkout ─────────────────────────────
# Counts commits touching the files THAT INSTALLER ACTUALLY INSTALLS. A docs
# commit does not make an installed floor stale, and a number that moves for
# reasons the operator cannot act on is one they learn to ignore.
#
# THE PATHSPEC WAS `bin/ hooks/`, AND IT IS WIDER THAN EITHER INSTALLER IN BOTH
# DIRECTIONS. Measured on the live box 2026-08-24: the row read `STALE floor5`
# while all sixteen floor payload files were byte-identical to origin/main. The
# five commits it counted touched status-fleet-glyph.sh, status-dashboard-generate.sh, cu.sh and
# audit-triage.sh — every one of them runtime-install's, and every one of them
# already delivered by a runtime-install run that same afternoon. The remedy
# printed (`floor-install --live --apply`) would have copied byte-identical files
# and moved a stamp. `hooks/` is wider still: it holds this repo's GIT hooks
# (commit-msg, pre-commit, pre-push) and appears in NO installer payload at all,
# so a commit to a git hook reported the security floor as stale.
#
# §2.11 — a false positive is a defect, not safety. A renewal token that fires on
# every statusline commit is one the operator learns to skip, and it is the same
# token that has to be believed the day guard-cloud.sh really is not installed.
STAMP="$TGT/.helm-install-stamp"

# THE PAYLOAD IS READ FROM THE INSTALLER, NEVER RESTATED HERE. floor-install.sh
# already does exactly this to read deploy-runtime-install.sh's $FILES (:301), and its
# own comment names the reason: "a second copy of runtime-install's payload is
# the T2 defect harbor#275 was made of". Same sed, same trust boundary — the
# declaration inside the installer is the one source of truth for what it owns.
#
# THE INSTALLER'S OWN FILE IS PART OF ITS PATHSPEC. A commit that changes only
# floor-install.sh — new hook wiring, a different deny extension, a changed
# install order — leaves every payload file identical and still means the box is
# behind what installing today would produce.
#
# WHAT THIS DELIBERATELY DOES NOT COUNT, so the next reader does not mistake the
# gap for an oversight: floor-install's CONDITIONAL payload (guard-integrity.sh
# under --with-b6, guard-stop.sh under --with-stop) and floor-deny.sh, which it
# RUNS rather than lists. All three are named in the installer's prose, not in a
# payload variable, and grepping prose is a heuristic this file will not carry.
# floor-deny.sh and guard-integrity.sh are both in runtime-install's $FILES, so a
# commit to either still raises a `runtime` token; only the settings.json deny
# entries floor-install regenerates are uncovered. Closing that properly means
# floor-install declaring those three the way it declares $GUARDS, which is a
# change to the floor installer and belongs in its own review.
#
# EMPTY MEANS STAND DOWN, NEVER "0 BEHIND". If an installer stops declaring its
# payload in a form this can read, the honest answer is that the comparison could
# not be made — the rule the absent-checkout arm below already follows, and the
# distinction renew-check-test.sh case 4 exists to hold.
_payload_pathspec() { # <installer-basename> — prints one `bin/<file>` per line
  # the stamp key is the installer's pre-#961 name; W3 moved runtime-install.sh (harbor#961)
  case "$1" in runtime-install) _pi="$REPO/bin/deploy-runtime-install.sh" ;; *) _pi="$REPO/bin/$1.sh" ;; esac
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
  # A hook engine moved to its folder (D-88): both spellings, so neither side of the move drops out of the count.
  _pe="$(printf '%s\n' "$_pl" | sed -n 's|^bin/||p' | while IFS= read -r _pn; do il_engine_path "$_pn"; echo; done)"
  printf 'bin/%s.sh\n%s\n%s\n%s\n' "$1" "$_pl" "$_ps" "$_pe" | sed '/^$/d' | sort -u
}
# `git rev-parse --git-dir`, NOT `[ -d "$REPO/.git" ]`. In a worktree `.git` is a
# FILE, so the directory test made every worktree report `repo?` — measured the
# first time this ran from ~/harbor-wt-*. contracts/hooks.md records the same
# trap for an install snippet that was documented and never run.
# HOISTED SO SECTION 1b CAN REUSE THE ANSWER. "Is $REPO a checkout" is asked by
# two arms now, and a second inline copy of the test is a second thing that can
# be changed in one place and not the other.
_repo_ok=0
command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 && _repo_ok=1
if [ "$_repo_ok" = 1 ]; then
  # RUNTIME FIRST, AND THE ORDER IS THE FIX, NOT A PREFERENCE. floor-install.sh is
  # the PIN WRITER (:223, over its payload plus deploy-restore.sh/baseline-pin.sh/
  # deploy-harden.sh), and deploy-runtime-install.sh REPLACES four of the files it pins. So
  # whichever runs last decides whether the pins match the bytes on disk.
  #
  # MEASURED 2026-08-14 on a copy of the live config dir, both orders:
  #   floor-install → runtime-install : "the next SessionStart will be BLOCKED"
  #                                     (deploy-restore.sh replaced after its pin was taken)
  #   runtime-install → floor-install : B6 silent, floor-verify green
  # This loop printed the blocking order because `floor` sorts before `runtime`,
  # and a remedy an operator pastes in the order given must not end in a lockout.
  for inst in runtime-install floor-install; do
    _sha="$(sed -n "s/^$inst \([0-9a-f]*\) .*/\1/p" "$STAMP" 2>/dev/null | tail -1)"
    if [ -z "$_sha" ]; then
      note "${inst%%-*}!" "$inst has NEVER stamped this config dir — the box may be running nothing this repo built" "$(_fix "${inst%%-*}" "$inst")"
    elif ! _paths="$(_payload_pathspec "$inst")" || [ -z "$_paths" ]; then
      note "${inst%%-*}?" "$inst declares no payload this can read at $REPO/bin/$inst.sh — the installed-vs-built comparison stood down rather than reporting 0 behind" "none:bin/drift-renew-check.sh (_payload_pathspec reads GUARDS=, RECOVERY=, FILES=, REFRESH_ONLY= and SUITE=)"
    else
      # UNQUOTED ON PURPOSE: the pathspec is one git argument per line and must
      # word-split. This file runs under `sh`, where it does; harbor's own
      # `for g in $GUARDS` loops rest on the same rule.
      # shellcheck disable=SC2086
      _behind="$(git -C "$REPO" rev-list --count "$_sha..origin/main" -- $_paths 2>/dev/null || printf '')"
      if [ -n "$_behind" ] && [ "$_behind" -gt 0 ] 2>/dev/null; then
        note "${inst%%-*}$_behind" "$inst is $_behind payload commit(s) behind origin/main (installed $(printf %.7s "$_sha")) — merged guards are not gating anything here" "$(_fix "${inst%%-*}" "$inst")"
      fi
    fi
  done
else
  note "repo?" "no git checkout at $REPO — the installed-vs-built comparison stood down rather than reporting 0 behind" "none:contracts/roots.tsv (set HARBOR_REPO to the harbor checkout)"
fi

# ── 1b · the running constitution against origin/main ────────────────────────
# SAME SUBJECT AS SECTION 1, DIFFERENT MECHANISM, AND THE DIFFERENCE IS FORCED.
# policy-constitution-install.sh writes NO stamp: it copies policy/constitution.md over
# $CFG/CLAUDE.md and verifies with cmp. There is no installed-at commit to count
# from, so the loop above could not have covered it by adding a name to its list.
# What the installer does leave is a byte-exact footprint, which is a STRONGER
# oracle than a commit count rather than a weaker one — the deployed file either
# is the merged file or it is not, and drift-install.sh's header already records
# why it chose content over a lag counter for the same reason.
#
# WHY THIS ARM EXISTS (harbor#557). Measured 2026-09-18: the live CLAUDE.md sat
# 413 B behind main for two days and every instrument on the box was green.
# floor-verify's install-drift enumerates $DIR/bin and never looks at CLAUDE.md;
# this file's own loop covered runtime-install and floor-install and nothing
# else; B8 holds the live file against ITS OWN PIN, which is a question about
# tampering and answers "unchanged since pinning" for a file that was already
# stale when it was pinned. The installer existed the whole time. Nothing ever
# said to run it, so it was run when a human happened to think of it.
#
# HELD AGAINST origin/main, NOT THE WORKING TREE. Shelling out to the installer's
# dry run would have been shorter and would have reported `identical` on any
# branch whose policy/constitution.md happens to match the box — including text nobody
# has reviewed, which is DE-30's failure and the thing constitution-install's own
# --from-branch gate exists to make deliberate rather than accidental. The live
# constitution is supposed to carry MERGED text, so merged text is what it is
# compared to.
CONST_LIVE="$TGT/CLAUDE.md"
# HOW FAR BACK THE BLOB WALK BELOW LOOKS. A knob because the cap decides between
# two OPPOSITE remedies and the suite has to be able to reach the branch where it
# binds; 60 against a path with 19 commits in its entire history (measured
# 2026-09-20) is slack, not a limit anyone will meet.
CONST_WALK_MAX="${HARBOR_CONST_WALK_MAX:-60}"
if [ ! -f "$CONST_LIVE" ]; then
  note "const!" "no CLAUDE.md in ${TGT#"$HOME"/} — the constitution has never been deployed to this config dir" "$(_fix constitution constitution-install)"
elif [ "$_repo_ok" = 1 ]; then
  _cref="$(git -C "$REPO" rev-parse --verify --quiet origin/main:policy/constitution.md 2>/dev/null || printf '')"
  _clive="$(git -C "$REPO" hash-object -- "$CONST_LIVE" 2>/dev/null || printf '')"
  if [ -z "$_cref" ] || [ -z "$_clive" ]; then
    # Case 4's rule, one artifact down: "I could not look" and "identical" are
    # the two states this file exists to keep apart, and silence spells the
    # second one.
    note "const?" "origin/main carries no readable policy/constitution.md at $REPO — the live-vs-merged comparison stood down rather than reporting identical" "none:harbor#557"
  elif [ "$_cref" != "$_clive" ]; then
    # THE DISTANCE IS WALKED, NOT GUESSED. The commit whose blob the box is
    # running is the only honest anchor for "how far behind", and it is cheap:
    # this runs ONLY once the hashes already differ, over a path with 19 commits
    # in its whole history (measured 2026-09-20, 0.02s).
    #
    # THE SHAPE IS drift-install.sh's, DELIBERATELY. It walks a path's history
    # for the live bytes at :137 and grades the result current/stale/modified/
    # unsourced. This is that walk over the one governed file living OUTSIDE
    # `bin/`, which is why install-drift cannot reach it: its loop is
    # `for live in "$DIR"/bin/*` and CLAUDE.md is not in it.
    _cb=0; _cfound=0
    for _cc in $(git -C "$REPO" rev-list --max-count="$CONST_WALK_MAX" origin/main -- policy/constitution.md 2>/dev/null); do
      [ "$(git -C "$REPO" rev-parse --verify --quiet "$_cc:policy/constitution.md" 2>/dev/null)" = "$_clive" ] && { _cfound=1; break; }
      _cb=$((_cb+1))
    done
    if [ "$_cfound" = 1 ]; then
      note "const$_cb" "the running constitution is $_cb merged commit(s) behind origin/main — every session started since has loaded rules this repo has changed" "$(_fix constitution constitution-install)"
    elif [ "$_cb" -ge "$CONST_WALK_MAX" ]; then
      # STOPPED LOOKING IS NOT FOUND NOTHING, and conflating them here would be
      # the expensive kind of wrong: the two branches around this one print
      # OPPOSITE remedies, so a truncated walk falling through to const+ would
      # tell an operator to back-port a box that merely needs deploying.
      #
      # A history of exactly $CONST_WALK_MAX revisions with no match lands here
      # too, when `const+` would have been right. That asymmetry is deliberate:
      # standing down over-reports uncertainty, which costs a second look, while
      # either of the other two verdicts being wrong costs the operator a
      # destructive edit or a constitution left stale.
      note "const?" "the running constitution matches none of the last $_cb revisions of policy/constitution.md and the walk stopped there — the distance was NOT determined, which is not the same as the box being current" "HARBOR_CONST_WALK_MAX=$((CONST_WALK_MAX * 4)) sh $HERE/drift-renew-check.sh $(il_spell)"
    else
      # A SEPARATE TOKEN BECAUSE IT IS A SEPARATE REMEDY, AND THE WRONG ONE IS
      # DESTRUCTIVE. harbor#462: the live file was 1,933 B LARGER than the repo's
      # and every hunk was an append — three blocks of doctrine written straight
      # into the box and committed nowhere, one of them the whole "every check is
      # registered" rule. Deploying over that state destroys it, byte-perfectly,
      # with cmp reporting success. So this never prints --apply.
      #
      # AND IT DOES NOT RE-DECIDE THE QUESTION. Whether the live-only lines are
      # unsourced text or a reordering is constitution-install's own comm(1) over
      # sorted unique lines, at :149; a second implementation here would be a
      # copy that can disagree with the gate it is warning about. This says the
      # distance is uncomputable and names the tool that owns the answer.
      note "const+" "the running constitution matches NO commit on origin/main — it may carry text version control has never held (harbor#462), so deploying over it could destroy that text" "none:harbor#462 — back-port it through a PR; read the direction first, it writes nothing: sh $REPO/bin/policy-constitution-install.sh $(il_spell)"
    fi
  fi
fi

# ── 2 · scheduled jobs that exist in the repo and on no schedule ─────────────
# The plist is the built artifact; LaunchAgents is the footprint. `launchctl
# list` is deliberately NOT the oracle: a job can be loaded from a plist that
# was since deleted, and a plist can sit on disk unloaded — the file is the
# thing an operator can act on, and the load state is one `launchctl` away.
# A private layer's jobs/ is a second source of the same plists (harbor#1149, contracts/private-layer.md): client monitors
# are built there, and the footprint they owe is the same file in the same LaunchAgents. Darwin only; a Linux box's units are systemd/.
PJOBS=""; [ "$JOBGLOB" != '*.plist' ] || PJOBS="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}/jobs"
#
# TWO FOOTPRINTS ARE NOT A MISS, AND ONE FILE IS NOT ALWAYS A JOB (false alarm measured 2026-10-11: `STALE jobs4`, all four wrong).
#   - A plist can be installed as a SYSTEM daemon: audit-collector-install.sh writes the collector, its checkpoint and the OTLP receiver
#     under sudo, because they run as another uid. Looking only in LaunchAgents reported three loaded daemons as never installed.
#   - A plist can be shipped INERT on purpose (event.dispatch: "no installer loads that plist"). It says so itself, with the marker
#     `harbor:shipped-inert` anywhere in the file; the marker is the declaration, so a new inert job needs no edit here, and a
#     plist that lacks it and is installed nowhere is still reported.
# §2.11: a token that is always on is one the operator learns to skip, and it is the token that has to be believed the day a real
# agent plist is missing.
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
# Absent means the daily judge was never wired; stale means it stopped. Both are
# "a self-process that is not running", which is this file's whole subject.
JV="$TGT/.helm-judge"
if [ ! -f "$JV" ]; then
  if [ "$JOBGLOB" = '*.plist' ]; then
    # The plist is a template (harbor#630): rendering fills this box's roots in, a cp would install the placeholders.
    _jfix="sh $REPO/bin/deploy-launchd-render.sh $REPO/launchd/com.harbor.judge.plist > ~/Library/LaunchAgents/com.harbor.judge.plist && launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.harbor.judge.plist"
  else
    _jfix="cp $REPO/systemd/harbor-judge.service $REPO/systemd/harbor-judge.timer $JOBDEST/ && systemctl --user daemon-reload && systemctl --user enable --now harbor-judge.timer"
  fi
  note "judge!" "no ledger verdict has ever been written — the daily judge is not installed" "$_jfix"
elif [ -n "$(find "$JV" -mtime +2 -print 2>/dev/null)" ]; then
  if [ "$JOBGLOB" = '*.plist' ]; then _jwhy="none:launchd/com.harbor.judge.plist (its StandardErrorPath names the job's own error file)"
  else _jwhy="none:systemd/harbor-judge.timer (journalctl --user -u harbor-judge.service shows its runs)"; fi
  note "judge?" "the ledger verdict has not been rewritten in over 2 days — the job is not reporting clean, it is not reporting" "$_jwhy"
fi

# ── 4 · the instruction pin ──────────────────────────────────────────────────
# Not recomputed here. guard-integrity.sh already hashes the manifest at
# SessionStart and session-verdicts.sh already speaks on teeth drift; a second
# implementation of the same hash is a copy that can disagree with the gate.
# What this reads is the gate's OWN artifact: a pin file that does not exist.
[ -f "$TGT/.helm-instructions.sha256" ] || \
  note "pin!" "instruction surfaces are UNPINNED — nothing detects a change to what loads into every session" "sh $REPO/bin/pin-instructions.sh --apply $(il_spell)"

# ── 5 · proposal packets waiting for a human ─────────────────────────────────
# A SEPARATE cache and a separate statusline token, deliberately. "The box is
# behind what we built" and "somebody must read a patch" are different jobs for
# the operator, and folding them into one number would make each one's remedy
# ambiguous. Written only when the tool exists — proposal.sh lives in the
# checkout and is in no installer payload, because it acts on the repo.
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
# Then the log (contracts/logging.md): one WARN per finding, its fix aimed at this box. Findings are
# WARNs, never FAILs, so the exit stays 0 as the header promises.
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
