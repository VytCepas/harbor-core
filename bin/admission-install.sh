#!/usr/bin/env sh
# INSTALL (harbor#3) — wrapped, additive install of the Helm POSIX floor into a config dir (harbor#765).
#   sh admission-install.sh (--live | --dir PATH)           DRY RUN (the default): the plan, nothing written
#   sh admission-install.sh --apply (--live | --dir PATH)   write, backing up first beside the run's log
#   --with-b6         also install B6 (admission-integrity.sh), LAST, once a session with the floor on is verified
#   --with-stop-gate  also install the Stop gate (admission-stop.sh), which CAN refuse to let a turn end
#   --accept-loss     install even though this source lacks floor commits already installed (install-stamp)
#
# Copies the guard scripts into <dir>/bin, applies the B1 deny extension (admission-deny.sh), and additively merges the floor hooks into <dir>/settings.json. Additive + idempotent: never removes a foreign hook, never re-adds a floor hook already present (keyed by command string). Assumes the SEC-0 read-deny base is applied. B6 is NOT installed by default: it lands LAST, after this install is verified (docs/explanation/admission-baseline.md order).
# --help, the target and every standard flag come from bin/deploy-install-lib.sh (lint D7): physical paths, intent is a flag never a position (harbor#52), CLAUDE_CONFIG_DIR never picks the dir. Every printed command is spelled by il_spell/il_cmd, so it passes this script's own gate (harbor#95, #142).
# Removed notes: docs/explanation/code-cases/bin-admission-install.md
set -eu
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init floor-install
WITH_B6=0
# SG (harbor#291): the Stop gate is OPT-IN, as B6 is: a gate that can refuse to let a TURN end must be a deliberate act per box. The wiring lives here because deploy-runtime-install.sh installs no guard and wires no hook.
WITH_STOP=0
il_opt() {
  # shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
  case "$1" in
    --with-b6) WITH_B6=1; IL_TAKE=1 ;;
    --with-stop-gate) WITH_STOP=1; IL_TAKE=1 ;;
    *) IL_TAKE=0 ;;
  esac
}
il_parse "$@"
il_target
DIR="$IL_TARGET"
# The commit column of this run's .harbor-manifest rows (install standard §3): the checkout it runs from,
# or - for the installed copy sandbox-make runs.
il_source "$SRC/.."
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq is required, and is not on PATH"
  log_fix "$(pkg_hint jq)"
  log_end; exit 1
fi
S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S"
  log_nofix "docs/how-to/harden-the-host.md — a config dir Claude Code has started in once, hardened by deploy-harden.sh"
  log_end; exit 1
fi

GUARDS='admission-hook.sh library-admission.sh admission-normalize.awk admission-self-edit.sh admission-bash.sh admission-egress.sh admission-decide.sh annotate-web.sh pin-instructions.sh context-resolve.sh admission-observe.sh admission-cloud.sh admission-destroy.sh admission-deliverables.sh admission-api-route.sh govern-hook.sh'
# RECOVERY PATH, separate from $GUARDS (harbor#275): not guards (nothing wires them), but B6's own block message is `sh $CFG/bin/deploy-restore.sh ...`, so the floor must ship them. Held apart because $GUARDS is read by X13's payload derivation, admission-integrity.sh's floor MINIMUM and admission-remove.sh's removal list.
# library-log.sh and deploy-install-lib.sh are what deploy-restore.sh, deploy-harden.sh and pin-instructions.sh source (harbor#771, #765), so they are copied and content-pinned with it.
RECOVERY='deploy-restore.sh deploy-harden.sh library-log.sh deploy-install-lib.sh'
# EVENT PRODUCERS (harbor#1043): the hook and the bus it calls. Not guards (nothing can veto, the floor never depends on them): copied and recorded in the manifest but NOT content-pinned and not in $GUARDS. floor-uninstall reads this line too.
EVENTS='event-bus.sh event-hook.sh'
# APPROVAL GATE (harbor#1018): the tools the ask and allow rules name, their shared library, and merge-stack with its merge backstop (ship contract §5b.10). Copied and recorded, NOT pinned and NOT in $GUARDS: no hook runs them, and B6 blocks every session over a pinned file with no kill-switch line. The rules name these installed copies because a session cannot write <cfg>/bin (B1, guard-bash, guard-selfedit). floor-uninstall reads this line too.
GATES='library-fs.sh library-gate.sh gate-classify.sh gate-merge.sh gate-approve.sh gate-queue.sh gate-merge-check.sh gate-merge-stack.sh gate-merge-stack-resolve.py deploy-fleet.sh'

# The floor hook wiring: event, matcher, guard. <onfail> is `block` for a veto (P13E-2: padding a payload until the guard is slow was a way past every rule); il_merge_hook sets it on a hook already wired too.

# onFailure needs Claude Code 2.1.295 or later: il_onfailure decides, HARBOR_ADMISSION_ONFAILURE=1|0 overriding it.
ONFAIL="$(il_onfailure)"

# WIRING TABLE (harbor#766), one row per hook: <event>;<matcher>;<argv after /bin/sh>;<opt-in>;<also wired by>. A bare name in the argv is a file in <dir>/bin. The dry run and the apply both wire from it and admission-remove.sh reads it to decide what to strip, so the three cannot drift.
floor_hooks() { cat <<'ROWS'
PreToolUse;Bash;admission-hook.sh admission-bash.sh
PreToolUse;Bash|Write|Edit|MultiEdit;admission-hook.sh admission-egress.sh
# THE OTHER HALF OF guard-egress. It carries dedicated payload branches for
# mcp__* (FO-10), Task/Agent (FO-11), WebFetch/WebSearch (CRED-09/FO-17) and
# NotebookEdit (FO-09) — and NONE of them could ever run, because the installer
# only ever routed Bash|Write|Edit|MultiEdit to it. Months of coverage was dead
# code in the deployed configuration; the suite never noticed because its wiring
# assertions only checked the pairs the installer already wired (pass 11,
# P11-W1, critical). The matcher is a regex, so `mcp__.*` covers every server.
PreToolUse;mcp__.*|Task|Agent|WebFetch|WebSearch|NotebookEdit;admission-hook.sh admission-egress.sh
PreToolUse;Write|Edit|MultiEdit;admission-hook.sh admission-self-edit.sh
# guard-cloud (harbor#194) and guard-destroy (harbor#201) — ASK/DENY gates for
# destructive cloud ops and local work destruction. Wired WITHOUT admission-hook.sh,
# like context-resolve/floor-observe: they are the WARNING layer, fail-OPEN by
# design, and emit a PreToolUse JSON decision on stdout (exit 0). Routing them
# through the fail-CLOSED wrapper would deny ALL Bash if one ever crashed — the
# §2.11 disaster for a guard whose whole point is to be tolerable. Deliberately
# NOT added to guard-integrity's required set, so a missing copy cannot brick a
# session; they stay write-protected by guard-selfedit either way.
PreToolUse;Bash;admission-cloud.sh
PreToolUse;Bash;admission-destroy.sh
# guard-deliverables — the FILING gate. Same standalone, fail-OPEN wiring and
# the same reason: it denies a NEW loose .html/.md/.pdf in $HOME, Desktop,
# Documents or Downloads and names ~/Deliverables/<date>-<slug>/ instead. A
# tidiness rule must never be able to fail CLOSED and stop a session writing
# code, so it stays out of admission-hook.sh and out of B6's minimum set.
# ONE matcher covering BOTH ways a document gets written — the file tools, which
# carry a path, and Bash, where the path is inside a redirect. Wiring it as two
# entries under two matchers is what a first cut did and WIRE-1 rejected it: the
# same command twice under PreToolUse is a duplicate, tolerated only for
# guard-egress, which genuinely needs disjoint matcher sets. One entry, one
# alternation, no exception to maintain.
PreToolUse;Bash|Write|Edit|MultiEdit;admission-deliverables.sh
# govern-hook --box (harbor#516) — the merge backstop, box-level. Standalone and
# fail-OPEN like guard-cloud: a refusal is a JSON deny on stdout and every fault
# exits 0 in silence. Box-level because the repo pack reaches only sessions
# launched in the repo, and none of 19 merges in 30 days was.
PreToolUse;Bash;govern-hook.sh --box
# guard-apiroute — Claude Code's own API route. Standalone and fail-OPEN like
# guard-deliverables, for the opposite reason: it never vetoes a call, it REPAIRS a
# settings file afterwards and says so. PostToolUse because the write it exists for
# is invisible in the command text (on 2026-09-17 the command was a Python probe and
# the writer was a router its setup script installed); SessionStart because a daemon
# or an earlier session can write the route between calls.
PostToolUse;Bash|Write|Edit|MultiEdit;admission-api-route.sh
SessionStart;;admission-api-route.sh
# Pass 14 E-4: Monitor runs tool_input.command in the Bash shell and no guard saw it. Its own
# matcher rather than `Bash|Monitor`, so a box already wired under `Bash` does not run each guard twice.
PreToolUse;Monitor;admission-hook.sh admission-bash.sh
PreToolUse;Monitor;admission-hook.sh admission-egress.sh
PreToolUse;Monitor;admission-cloud.sh
PreToolUse;Monitor;admission-destroy.sh
PreToolUse;Monitor;admission-deliverables.sh
PreToolUse;Monitor;govern-hook.sh --box
# harbor#1313 L6: Grep returns file contents, and Read deny binds only the directory it searches. Its own
# matcher, as Monitor's, so a box already wired keeps one entry per selector.
PreToolUse;Grep;admission-hook.sh admission-egress.sh
PostToolUse;WebFetch|WebSearch|ToolSearch|mcp__.*;admission-hook.sh --advisory annotate-web.sh
# H2 (harbor#4) — record this session's detect-and-defer context so a later
# PostToolUse/Stop hook can read it. Claude Code spawns each hook fresh, so a
# SessionStart hook cannot export it; a per-session file is the only channel.
# Wired WITHOUT admission-hook.sh: it is a recorder, never a veto, and every path
# in it already exits 0. deploy-runtime-install.sh wires this same hook (RESOLVER_HOOK),
# so admission-remove.sh leaves it wired while that installer is on the box.
SessionStart;;context-resolve.sh;;runtime-install
# L0-11 (harbor#75) — the SAME recorder at PostToolUse, where it learns which
# working tree this session actually WRITES to. The registry's cwd is the launch
# directory and `lsof` returns the identical value (both measured 2026-08-02), so
# a peer report keyed on either is silent exactly when two sessions collide. One
# more wiring line rather than a new floor file: a new script would mean a B6 pin,
# a frozen-contract row, an F1 rule and wiring assertions in thirteen files to
# carry forty lines this already-installed recorder can hold.
PostToolUse;Write|Edit|MultiEdit|NotebookEdit;context-resolve.sh
# OBSERVE-1 (harbor#41). Also wired WITHOUT admission-hook.sh, and for a second
# reason on top of context-resolve's: admission-hook.sh exits at its own line-2
# kill-switch, so routing this through the wrapper would make an overridden
# session — the one thing it exists to record — invisible again.
SessionStart;;admission-observe.sh
# harbor#1043 PR 2 — the event producers: one script, one row per harness event it turns into a
# bus event (docs/design/events.md). Standalone and fail-OPEN like guard-apiroute: a recorder,
# never a veto, exit 0 on every path. SessionEnd, not Stop, is the session's end: Stop fires at
# the end of every TURN (measured 2.1.291). harbor#1051 PR 1 adds SubagentStart (agent.spawn) and
# one PostToolUse row, matcher limited to the tools that can open background work or a PR, so the
# hook does not run on a Read, an Edit or a Grep. Bash is in it for run_in_background and
# `gh pr create`; Claude Code's `if` filter cannot express the first, so the script tests both.
SessionStart;;event-hook.sh
SessionEnd;;event-hook.sh
SubagentStart;;event-hook.sh
SubagentStop;;event-hook.sh
PostToolUse;Monitor|ScheduleWakeup|CronCreate|Workflow|Bash|Skill|Read;event-hook.sh
# The two opt-ins, last so a default install wires exactly what it did before.
# B6 (--with-b6) is fail-CLOSED and lands after the floor is verified (docs/explanation/admission-baseline.md
# order). SG (harbor#291, --with-stop-gate) can refuse to let a TURN end, so it
# is a deliberate act per box; STANDALONE because admission-hook.sh speaks the
# PreToolUse protocol and this verdict is `decision:"block"`.
SessionStart;;admission-integrity.sh;b6
Stop;;admission-stop.sh;stop
ROWS
}
_hook_cmd() { # <argv> → the command string wired for it
  _hc="/bin/sh"
  for _ht in $1; do
    case "$_ht" in -*) _hc="$_hc $_ht" ;; *) _hc="$_hc $DIR/bin/$_ht" ;; esac
  done
  printf '%s' "$_hc"
}
# Merge every row this run installs into $NEW. Opt-in rows are in the DRY RUN too, so its hooks diff shows the Stop gate and B6 (harbor#275). A `case`, never `[ ... ] && ...`: under set -eu that leaves $? = 1.
wire_floor() {
  while IFS=';' read -r _ev _m _argv _opt _co; do
    case "$_ev" in ''|'#'*) continue ;; esac
    case "$_opt" in
      '') ;;
      b6)   if [ "$WITH_B6" -eq 0 ]; then continue; fi ;;
      stop) if [ "$WITH_STOP" -eq 0 ]; then continue; fi ;;
      *)    log_fail "unknown opt-in '$_opt' in admission-install.sh's wiring table"
            log_nofix "bin/admission-install.sh floor_hooks — every opt-in column is empty, b6 or stop"
            log_end; exit 1 ;;
    esac
    _of=''; [ "$_ev" != PreToolUse ] || _of="$ONFAIL"   # every PreToolUse row is a veto
    NEW="$(printf '%s' "$NEW" | il_merge_hook /dev/stdin "$_ev" "$_m" "$(_hook_cmd "$_argv")" "$_of")"
  done <<EOF
$(floor_hooks)
EOF
}
# The opt-ins this run installs, by their names: a rename's hook commands, old copies and pins follow them too.
_OPTN=""; [ "$WITH_B6" -eq 0 ] || _OPTN="admission-integrity.sh"; [ "$WITH_STOP" -eq 0 ] || _OPTN="$_OPTN admission-stop.sh"
# A box wired before a rename names the old files: rewire those commands first, so the merge finds them (harbor#961 W6).
_rewire() {
  NEW="$(printf '%s' "$NEW" | il_renamed_rewire /dev/stdin "$SRC/.." "$DIR" $GUARDS $_OPTN)" \
    || { log_fail "the hook commands of renamed files could not be rewired in $S"; log_nofix "the jq error above"; log_end; exit 1; }
}
NEW="$(cat "$S")"
_rewire
wire_floor

if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $DIR"; else log_head "plan for $DIR (dry run: nothing is written)"; fi
# THE VERDICT, AT THE MOMENT OF DECISION: eval-pass-score.sh is NOT a gate on this installer and never was; the fix is DISCLOSURE. Advisory by construction: a failure to compute it is reported as that, never as approval.
# Lint X7 reports this call and that advisory is correct: the script is repo-scoped (it reads the adversarial pass register, which is not shipped to a config dir), so shipping it alone would make it RUN AND FAIL on every install. The call stays repo-only and the ABSENCE is announced (constitution No.2 clause 7).
if [ -x "$SRC/eval-pass-score.sh" ] || [ -f "$SRC/eval-pass-score.sh" ]; then
  # The scorer's own status, never tail's: an unavailable verifier reported as exit 0 is the defect.
  _pstmp=$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX"); _psrc=0
  sh "$SRC/eval-pass-score.sh" > "$_pstmp" 2>&1 || _psrc=$?
  _ps="$(tail -3 "$_pstmp")"; rm -f "$_pstmp"
  if [ -n "$_ps" ]; then
    while IFS= read -r _l; do log_note "pass-score (ADVISORY — nothing here is gated on it): $_l"; done <<EOF
$_ps
EOF
  else log_note "eval-pass-score.sh produced no output (exit $_psrc) — that is not an approval"; fi
else
  log_note "pass-score verdict: UNAVAILABLE — no eval-pass-score.sh beside $SRC (this is the installed copy; the register it scores lives in the repo, so run this installer from a harbor checkout for the number). Absence of a verdict is not an approval."
fi
for g in $GUARDS; do log_note "guard to copy into $DIR/bin: $g"; done
for g in $EVENTS; do log_note "event producer to copy into $DIR/bin: $g (not a guard: no content pin)"; done
for g in $GATES; do log_note "approval gate tool to copy into $DIR/bin: $g (not a guard: no content pin)"; done
if [ "$WITH_STOP" -eq 1 ]; then log_note "guard to copy into $DIR/bin: admission-stop.sh (opt-in Stop gate — CAN refuse to let a TURN end)"; fi
# Listed in the dry run too: these are content-pinned, and a pin the dry run never mentioned is a file the operator did not know this installer owns (harbor#275).
for g in $RECOVERY; do log_note "recovery tooling to copy and pin alongside them: $g"; done
log_note "the B1 deny extension (admission-deny.sh) will be applied"
# The hooks this run would add, one line each, from the same table the apply wires.
_hadd="$(jq -rn --argjson old "$(jq -S '.hooks // {}' "$S")" --argjson new "$(printf '%s' "$NEW" | jq -S '.hooks // {}')" '
  [$new | to_entries[] | .key as $ev | .value[] | .matcher as $m | .hooks[] | {ev: $ev, m: ($m // ""), c: .command}] as $n
  | [$old | to_entries[] | .key as $ev | .value[] | .matcher as $m | .hooks[] | {ev: $ev, m: ($m // ""), c: .command}] as $o
  | $n - $o | .[] | "\(.ev) \(if .m == "" then "(any)" else .m end): \(.c)"' 2>/dev/null || :)"
if [ -n "$_hadd" ]; then
  while IFS= read -r _l; do log_note "hook to wire: $_l"; done <<EOF
$_hadd
EOF
else
  log_ok "every floor hook in the table is already wired"
fi

# ── would this deploy REMOVE work that is already installed? (harbor#115) ────
# A deploy from a `main` checkout that predated an unmerged branch once wrote older guards over newer ones and silently removed four live security fixes, while `git pull` said "Already up to date" and floor-verify said FLOOR IS ON. Refused in BOTH modes (the install standard's dry-run rule): deploy's plan phase reads this exit code to predict the apply.
# "The check said no" and "the check could not run" are different answers (harbor#313): a missing deploy-install-stamp.sh was once announced as a regression that did not exist. Still FAIL-CLOSED; only the diagnosis differs, decided by existence, not exit code.
_stamp_tool="$SRC/deploy-install-stamp.sh"
if [ ! -f "$_stamp_tool" ]; then
  il_loss "the regression check could not run: deploy-install-stamp.sh is not next to this script ($_stamp_tool), so nothing says this deploy is safe (run it from a checkout, or re-run the runtime installer so the installed copy has it — harbor#313)" \
    "$(il_cmd --apply --accept-loss)"
elif _st="$(sh "$_stamp_tool" --check "$DIR" floor-install 2>&1)"; then
  log_ok "no regression against what is installed (install-stamp)"
else
  il_loss "this source is missing work that is already installed in $DIR ($(printf '%s\n' "$_st" | sed -n 's/^  FAIL: //p' | head -1)); deploy from a checkout that contains it" \
    "$(il_cmd --apply --accept-loss)"
  while IFS= read -r _l; do [ -z "$_l" ] || log_note "$_l"; done <<EOF
$(printf '%s\n' "$_st" | sed -n 's/^  note: //p')
EOF
fi
il_stop

if [ "$IL_APPLY" -eq 0 ]; then
  # The Stop gate in the DRY RUN as well: a gate that can hold a session open must not be discoverable only in hindsight.
  if [ "$WITH_STOP" -eq 1 ]; then
    log_note "stop gate: WOULD install admission-stop.sh and wire it at Stop. It CAN refuse a turn end — once per defect, not once per turn. Fails open."
  else
    log_skip "stop gate: not included; to install it: $(il_apply_cmd floor) --with-stop-gate"
  fi
  il_renamed_retire "$SRC/.." 1 $GUARDS $RECOVERY $EVENTS $GATES $_OPTN
  [ "$IL_REFUSED" -eq 1 ] || il_apply_next floor
  log_end; exit $?
fi

mkdir -p "$DIR/bin"
il_backup "$S" || { log_end; exit 1; }
il_backup "$DIR/.helm-pins" || { log_end; exit 1; }
# The pre-run bytes of every script this run REPLACES with different content.
for g in $GUARDS $RECOVERY $EVENTS $GATES admission-integrity.sh admission-stop.sh; do
  if [ -f "$DIR/bin/$g" ] && [ -f "$SRC/$g" ] && ! cmp -s "$SRC/$g" "$DIR/bin/$g"; then
    il_backup "$DIR/bin/$g" || { log_end; exit 1; }
  fi
done
for g in $GUARDS; do il_install_exec "$SRC/$g" "$DIR/bin/$g"; il_manifest "bin/$g"; done
log_ok "guards copied into $DIR/bin: $(echo $GUARDS | tr ' ' ',')"
for g in $EVENTS; do il_install_exec "$SRC/$g" "$DIR/bin/$g"; il_manifest "bin/$g"; done
log_ok "event producers copied into $DIR/bin: $(echo $EVENTS | tr ' ' ',') (harbor#1043)"
# An installed floor-install (runtime-install ships one) has no gate beside it: what is absent is said, not faked.
_gmiss=''
for g in $GATES; do
  if [ -f "$SRC/$g" ]; then il_install_exec "$SRC/$g" "$DIR/bin/$g"; il_manifest "bin/$g"; else _gmiss="$_gmiss $g"; fi
done
if [ -n "$_gmiss" ]; then log_warn "approval gate NOT installed:$_gmiss not beside $SRC; deploy the floor from a checkout"
else log_ok "approval gate copied into $DIR/bin: $(echo $GATES | tr ' ' ',') (harbor#1018)"; fi
# ── NEVER ROLL BACK A FILE THE OTHER INSTALLER OWNS (PR #276 review, P1) ─────
# Two of $RECOVERY are in deploy-runtime-install.sh's $FILES, so copying them unconditionally would, after a runtime deploy from a newer checkout and a floor deploy from an older one, revert them to older bytes and pin them while the runtime stamp still claims the newer version. The regression gate above cannot see it (it asks install-stamp about floor-install).
# Decided by the STAMP TIMESTAMP, not git ancestry: who wrote these shared bytes most recently. Lexical compare is right for same-offset ISO-8601 on one box; a DST change fails SAFE, toward copying. The shared set is DERIVED, never listed here (harbor#275's T2 defect).
_rt_files="$(sed -n 's/^FILES="\(.*\)"/\1/p' "$SRC/deploy-runtime-install.sh" 2>/dev/null || true)"
_stamp_f="$DIR/.helm-install-stamp"
_rt_ts="$(sed -n 's/^runtime-install [0-9a-f]* \([^ ]*\).*/\1/p' "$_stamp_f" 2>/dev/null | tail -1)"
_fl_ts="$(sed -n 's/^floor-install [0-9a-f]* \([^ ]*\).*/\1/p'   "$_stamp_f" 2>/dev/null | tail -1)"
# `test '>'` is not POSIX (SC3012), so the order is asked of `sort`, bytewise (LC_ALL=C).
_rt_newer() { # <a> <b> — 0 iff a sorts strictly after b, bytewise
  [ "$1" != "$2" ] || return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort | tail -1)" = "$1" ]
}
_rt_owns=0
if [ -n "$_rt_ts" ] && { [ -z "$_fl_ts" ] || _rt_newer "$_rt_ts" "$_fl_ts"; }; then _rt_owns=1; fi
KEPT=""
for g in $RECOVERY; do
  case " $_rt_files " in
    *" $g "*)
      if [ "$_rt_owns" -eq 1 ] && [ -f "$DIR/bin/$g" ] && ! cmp -s "$SRC/$g" "$DIR/bin/$g"; then
        KEPT="${KEPT:+$KEPT }$g"; continue
      fi ;;
  esac
  il_install_exec "$SRC/$g" "$DIR/bin/$g"; il_manifest "bin/$g"
done
log_ok "recovery tooling copied into $DIR/bin: $(echo $RECOVERY | tr ' ' ',')$([ -z "$KEPT" ] || printf ' (except the kept: %s)' "$KEPT")"
# Per-guard content pins: B6 once checked only that files existed, so a guard gutted to its kill-switch line plus `exit 0` read as intact (red-team pass 6). COPY THEN PIN, one list used twice (harbor#275): a pin over a file this run did not write captures bytes of unknown provenance and B6 blocked every session; copying first makes the pin describe bytes this installer wrote and makes install order irrelevant.
mkdir -p "$DIR/.helm-pins"
for g in $GUARDS $RECOVERY; do
  [ -f "$DIR/bin/$g" ] && il_sha < "$DIR/bin/$g" > "$DIR/.helm-pins/$g.sha256"
done
log_ok "content-pinned in $DIR/.helm-pins: every guard and the recovery tooling (harbor#275)"
# A rename leaves the old name's copy and pin behind; B6 would check it for a kill-switch (harbor#949).
il_renamed_retire "$SRC/.." 1 $GUARDS $RECOVERY $EVENTS $GATES || { log_end; exit 1; }
# B8 (harbor#38): pin the persistent INSTRUCTION surfaces. Not a lock: they stay writable, but a change to CLAUDE.md / agents / skills / commands is reported at the next SessionStart. The pinner's gate is not ours to pass (harbor#135, #142): re-pinning blesses whatever they currently say, so on the live dir it is the operator's act; the live path DISCLOSES the command, a sandbox is pinned here.
B8_OPERATOR=0
if [ "$IL_LIVE" -eq 0 ]; then
  if il_run sh "$DIR/bin/pin-instructions.sh" --apply >/dev/null 2>&1; then
    log_ok "B8: instruction surfaces pinned"
  else
    log_warn "B8: could not pin the instruction surfaces, so the B8 advisory will say so at every SessionStart"
    log_fix "sh $DIR/bin/pin-instructions.sh --apply $(il_spell)"
  fi
else
  B8_OPERATOR=1
fi
# B1 deny extension + re-pin (floor-deny handles its own teeth and baseline; on install-lib, harbor#800).
_fd_rc=0
_fd="$(il_run sh "$SRC/admission-deny.sh" --apply 2>&1)" || _fd_rc=$?
if [ "$_fd_rc" -eq 0 ]; then
  log_ok "B1: deny extension applied; teeth and sec0 baseline re-pinned (floor-deny)"
else
  log_fail "B1: floor-deny exited $_fd_rc, so the deny extension and its pins are NOT in place: $(printf '%s\n' "$_fd" | tail -1)"
  log_fix "sh $SRC/admission-deny.sh --apply $(il_spell)"
  log_end; exit 1
fi
if [ "$WITH_B6" -eq 1 ]; then
  il_install_exec "$SRC/admission-integrity.sh" "$DIR/bin/admission-integrity.sh"; il_manifest bin/admission-integrity.sh
  il_sha < "$DIR/bin/admission-integrity.sh" > "$DIR/.helm-pins/admission-integrity.sh.sha256"
fi
# SG (harbor#291): the Stop gate, CONTENT-PINNED in the same breath as the copy (a guard written and not pinned is invisible to B6's content loop). Pinned here rather than listed in $GUARDS, which is also the presence list: a box that never opted in must not fail a check for a file it deliberately lacks.
if [ "$WITH_STOP" -eq 1 ]; then
  il_install_exec "$SRC/admission-stop.sh" "$DIR/bin/admission-stop.sh"; il_manifest bin/admission-stop.sh
  il_sha < "$DIR/bin/admission-stop.sh" > "$DIR/.helm-pins/admission-stop.sh.sha256"
fi
# Re-read settings (floor-deny just rewrote deny) and wire the SAME table the dry run showed (harbor#766).
NEW="$(cat "$S")"
_rewire
wire_floor
# The opt-ins are in bin/ now, so their old names can go the way the guards' did (harbor#961 W6).
[ -z "$_OPTN" ] || il_renamed_retire "$SRC/.." 1 $_OPTN || { log_end; exit 1; }
il_write_json "$NEW" "$S" || { log_end; exit 1; }
log_ok "hooks merged into $S; its pre-run bytes are in $IL_BK"

# OBSERVE-1 bootstrap: the hot path creates NOTHING (guard-lib property 3), so without this the ledger does not exist until the next SessionStart and decisions until then go unrecorded. Run once here, where a fork costs nothing.
CLAUDE_CONFIG_DIR="$DIR" sh "$DIR/bin/admission-observe.sh" </dev/null >/dev/null 2>&1 || true

# NOT SILENT: a kept file is pinned to the bytes on disk, so the gate stays quiet exactly when a reader needs telling that this deploy did not write what its line above says.
if [ -n "$KEPT" ]; then
  log_warn "KEPT the installed copy of: $KEPT — runtime-install stamped this dir AFTER the last floor deploy, and those files are in its payload too, so overwriting them would roll it back; they are pinned to the bytes now on disk, so B6 stays quiet. To make this floor source the author, deploy the runtime from it first"
  log_fix "sh $(dirname "$0")/deploy-runtime-install.sh --apply $(il_spell)"
fi
# RECORD WHAT WAS DEPLOYED (harbor#115) only after the apply ran, so a refused install never claims to be installed; --live is install-stamp's own gate.
_stw_rc=0
if [ "$IL_LIVE" -eq 1 ]; then _stw="$(sh "$SRC/deploy-install-stamp.sh" --write "$DIR" floor-install --live 2>&1)" || _stw_rc=$?
else _stw="$(sh "$SRC/deploy-install-stamp.sh" --write "$DIR" floor-install 2>&1)" || _stw_rc=$?; fi
if [ "$_stw_rc" -eq 0 ]; then
  log_ok "install-stamp: recorded floor-install in $DIR/.helm-install-stamp"
else
  log_warn "install-stamp could not record this deploy, so the next run cannot detect a rollback: $(printf '%s\n' "$_stw" | tail -1)"
  log_fix "sh $SRC/deploy-install-stamp.sh --write '$DIR' floor-install$( [ "$IL_LIVE" -eq 1 ] && echo ' --live' )"
fi
# What this run installed, one row per file (install standard §3). B6's .helm-pins is a separate store: the tamper gate never reads a record written by the thing it checks.
il_manifest_write || { log_end; exit 1; }
if [ "$B8_OPERATOR" -eq 1 ]; then
  # The target is spelled out, never left to the environment (Codex review, #148); --live stays because it is the AUTHORISATION.
  log_note "B8: the instruction surfaces were NOT re-pinned, deliberately (harbor#135): blessing what CLAUDE.md / agents / skills / commands say is your act, not an installer's; until you do, B6 reports the drift every session. Review with: sh $DIR/bin/pin-instructions.sh --check $(il_spell)"
  il_next --deploy-does "sh $DIR/bin/pin-instructions.sh --apply $(il_spell)"
fi
# A printed NEXT whose work is already done is an advisory that cries wolf (No.2.11): `--apply --with-b6` once told the operator to run `--apply --with-b6`. Deploy prints its own B6 advice, so it is skipped there.
if [ "$WITH_B6" -eq 0 ]; then
  log_note "B6 installs LAST, after you have verified a session with the floor on"
  il_next --deploy-does "$(il_apply_cmd floor) --with-b6"
else
  log_ok "b6: admission-integrity.sh installed, wired at SessionStart, content pinned"
fi
# Named in BOTH directions, saying what it can do rather than what it is called.
if [ "$WITH_STOP" -eq 0 ]; then
  log_skip "stop gate: NOT installed. It can REFUSE TO LET A TURN END when the transcript shows a floor edit with no suite run, or a suite left red. Opt in deliberately, per box: $(il_apply_cmd floor) --with-stop-gate"
else
  log_ok "stop gate: admission-stop.sh installed, wired at Stop, content pinned; it CAN refuse to let a TURN end — once per defect, not once per turn (Stop fires every turn). Fails open on any error."
fi
log_end; exit $?
