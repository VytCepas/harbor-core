#!/usr/bin/env sh
# L0-5-interim (harbor#21) — write the fleet snapshot cache the statusline glyph reads.
# The glyph NEVER invokes the orchestrator; only this refresher does, on an interval
# (launchd/cron). Atomic write; on failure the previous cache is kept and the glyph
# degrades to "fleet: unknown" via staleness. POSIX, jq only.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# One log format (contracts/logging.md): a scheduled job is silent while it works, and its one failure
# says what failed and how to see why, on the stdout launchd keeps.
. "$(dirname -- "$0")/library-log.sh"
log_init fleet-snapshot-refresh
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
CACHE="$CACHE_DIR/fleet-snapshot.json"
# the fleet file through the registry-aware reader beside this script (harbor#966)
FLEET="${HARBOR_FLEET_FILE:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_FLEET_FILE 2>/dev/null || :)}"
# the fleet CLI, a roots.tsv row read through the same reader (harbor#966)
ORCH="${HARBOR_ORCH_BIN:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_ORCH_BIN 2>/dev/null || :)}"

mkdir -p "$CACHE_DIR"
TMP="$CACHE.tmp.$$"
OBS="$CACHE_DIR/guard-decisions.json"
OTMP="$OBS.tmp.$$"
trap 'rm -f "$TMP" "$OTMP"' EXIT

# ── guard-decision counts (L1/OBSERVE-1, harbor#41 → statusline, harbor#59) ──
# Reduced to the two numbers the statusline renders. Done HERE and not in the
# statusline because reading the ledger means reading every record in it, and a
# statusline tick must not scale with the size of a log.
#
# REMOVE THE CACHE ON FAILURE, never leave the last good value. observe-report
# exits 1 on an absent or empty ledger, which is the state on any box where the
# guards are not installed — and a persisted "blocks 3" from a ledger that no
# longer exists is a number the operator would act on. Absent must stay absent.
SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -x "$SRC_DIR/admission-observe-report.sh" ] || [ -f "$SRC_DIR/admission-observe-report.sh" ]; then
  if sh "$SRC_DIR/admission-observe-report.sh" --json 2>/dev/null \
       | jq -e '{blocks:(.verdicts.block // 0), overrides:(.verdicts.override // 0)}' >"$OTMP" 2>/dev/null; then
    mv "$OTMP" "$OBS"
  else
    rm -f "$OBS"
  fi
else
  rm -f "$OBS"
fi

# ── what is BUILT here and NOT RUNNING there (harbor#44 follow-through) ──────
# Piggybacked on this refresher rather than given a launchd job of its own, and
# that is the whole point: a check for "the schedule was never installed" cannot
# depend on a schedule the operator has to install first. This refresher is
# already loaded on this box, so the check runs today.
#
# BEFORE the orchestrator block below, which `exit 1`s when the snapshot fails.
# Ordered after it, a missing orchestrator would silently take this with it —
# and the state where nothing is installed is exactly when it must still speak.
#
# The --live/dir split is session-verdicts.sh's idiom: renew-check refuses
# --apply on the live dir unless it was NAMED --live, so passing the path would
# make the refresher a no-op that looks like a clean box.
if [ -f "$SRC_DIR/drift-renew-check.sh" ]; then
  _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  _p() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
  LIVE_DIR="$HOME/.claude"
  if [ "$(_p "$_cfg")" = "$(_p "$LIVE_DIR")" ]; then
    sh "$SRC_DIR/drift-renew-check.sh" --live --apply >/dev/null 2>&1 || true
  else
    sh "$SRC_DIR/drift-renew-check.sh" --dir "$_cfg" --apply >/dev/null 2>&1 || true
  fi
fi

# ── the sweep: what is left over and needs a person, counted twice a day ─────
# The operator's call (2026-09-22): this job, at 09:00 and 16:00 — not a launchd
# job of its own. housekeeping-clean.sh --if-due makes every other tick a no-op that
# reads one line, so the slot gate lives in one place and is tested there.
#
# It COUNTS AND NEVER DELETES: --record refuses --apply outright. It writes
# .helm-sweep, which the statusline renders as 🧹N and SWEEP.
#
# INLINE, NOT BACKGROUNDED, and the cost is accepted: a record takes about a
# minute (measured 2026-09-22 at 60s over fifteen repos), twice a day, during
# which this tick's snapshot waits. `&` would not save it — launchd kills every
# process left in the job's process group when the job exits (launchd.plist(5),
# AbandonProcessGroup), so a backgrounded sweep would die with this script.
# BEFORE the orchestrator block, for renew-check's reason: that block exits 1
# when the snapshot fails, and the sweep must still run then.
if [ -f "$SRC_DIR/housekeeping-clean.sh" ]; then
  # Restated, not inherited from the renew-check block: that block is skipped
  # when drift-renew-check.sh is absent, and set -u would then end this whole job.
  _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  _p() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
  LIVE_DIR="$HOME/.claude"
  if [ "$(_p "$_cfg")" = "$(_p "$LIVE_DIR")" ]; then
    sh "$SRC_DIR/housekeeping-clean.sh" --record --if-due --live >/dev/null 2>&1 || true
  else
    CLAUDE_CONFIG_DIR="$_cfg" sh "$SRC_DIR/housekeeping-clean.sh" --record --if-due >/dev/null 2>&1 || true
  fi
fi

# ── the CI queue: jobs left on this box's runners, and when they should end ────
# Operator request 2026-09-23 (harbor#657): ⏳ on the statusline. Every tick, not
# on a slot — a queue changes by the minute, and an idle box costs two GitHub
# reads per repo. The cache holds epochs only; status-fleet-glyph.sh does the countdown.
# BEFORE the orchestrator block, for the sweep's reason: that block can exit 1.
if [ -f "$SRC_DIR/ci-queue.sh" ]; then
  HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-queue.sh" >/dev/null 2>&1 || true
fi

# ── main's tip: does every recent commit on main carry a green CI verdict? ─────
# harbor#586. Inside this run and not on a schedule of its own: a new launchd job needs the
# operator's yes, and one bounded read of main's runs a tick is cheaper than the ⏳ tile's.
# Writes cache/main-tip-verdict.json (the statusline's MAIN RED) and one checks.log line per change.
if [ -f "$SRC_DIR/ci-main-tip-verdict.sh" ]; then
  HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-main-tip-verdict.sh" >/dev/null 2>&1 || true
fi

# ── the obligations ledger: fold the bus, then ask the real state about what is still open (harbor#1050) ──
# Inside this run and not on a schedule of its own, for main-tip-verdict's reason. Reads are bounded (10s each, 40s together,
# HARBOR_STATUS_OBLIGATION_BUDGET) and a source that does not answer flips nothing, so a failure or a timeout costs this tick
# at most the budget and never its exit status. BEFORE the orchestrator block, which can exit 1.
if [ -f "$SRC_DIR/status-obligations.sh" ]; then
  sh "$SRC_DIR/status-obligations.sh" reconcile >/dev/null 2>&1 || true
fi

# ── the account plan and main's protection: say the first time either moves (harbor#1060) ───
# Pro -> Free on 2026-10-05 turned protection off and cut the minutes, and surfaced only when a merge was refused.
# Two reads a tick; one checks.log line per change, and the statusline's PLAN/GATE alarm until `ci-github-plan.sh ack`.
if [ -f "$SRC_DIR/ci-github-plan.sh" ]; then
  HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-github-plan.sh" >/dev/null 2>&1 || true
fi

# ── the CI runner: GitHub-hosted until the month's Actions minutes run short ───
# harbor#865. Inside this run and not on a schedule of its own, for main-tip-verdict's reason. One bounded read of the
# month's bill a tick; sets the repo variable HARBOR_RUNNER only when the value would change, and logs
# one checks.log line per change. A read that fails flips nothing (bin/ci-runner-switch.sh).
if [ -f "$SRC_DIR/ci-runner-switch.sh" ]; then
  HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runner-switch.sh" >/dev/null 2>&1 || true
  # each `org ORG` in .harbor-ci-runners gets its own verdict, against its own cap (harbor#1060)
  for _org in $(awk '$1 == "org" && $2 ~ /^[A-Za-z0-9][A-Za-z0-9-]*$/ { print $2 }' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.harbor-ci-runners" 2>/dev/null); do
    HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runner-switch.sh" --org "$_org" >/dev/null 2>&1 || true
  done
fi

# ── the fleet's runners: each repo's CI_RUNS_ON follows that verdict (harbor#1060) ───
# After runner-switch, which writes the verdict this reads. Sets CI_RUNS_ON on the repos with a local runner, re-runs
# billing-refused runs once, logs drift on change, and raises the ci-runner-alarm (a runner offline, docker down, a job no
# runner can take). It creates no container and reads or writes no billing (bin/ci-runners.sh).
if [ -f "$SRC_DIR/ci-runners.sh" ]; then
  HARBOR_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runners.sh" tick >/dev/null 2>&1 || true
fi

# -- the watch . are the schedulers this board depends on actually loaded ------
# THE NUMBERS THE STATUSLINE RENDERS ARE ONLY AS TRUE AS THIS JOB. .helm-renew,
# .helm-judge, guard-decisions.json and the fleet snapshot are all files on disk
# refreshed by launchd. If a job stops, every token sourced from it freezes at its
# last value and keeps rendering as current -- a green board over a dead reporter.
# That failure has been measured on this operator's data pipelines (alerting fires
# on build FAILURE, so a green build over a dead feed is silent); there is no
# reason to assume the same shape is safe here.
#
# INSTALLED IS THE DENOMINATOR, LOADED IS THE NUMERATOR, and the distinction is
# the whole check. drift-renew-check.sh already answers "built here, installed nowhere"
# by comparing repo plists against ~/Library/LaunchAgents. It does NOT answer
# "installed and not loaded", and its own comment explains why it declines to: a
# job can be loaded from a plist since deleted, and a plist can sit on disk
# unloaded, so the FILE is what an operator can act on. True -- and the load state
# is the thing that decides whether that file does anything today.
#
# launchctl list IS MATCHED ON THE LABEL, NOT PARSED FOR STATUS. The third column
# is the label; the first is a pid or "-", and "-" means loaded-but-not-currently-
# running, which for a periodic job is the NORMAL state. Reading it as dead would
# put every healthy interval job in the alarm -- the false-positive shape
# CONSTITUTION 2.11 calls a defect rather than safety.
#
# WRITTEN ONLY WHEN launchctl (or systemctl) EXISTS AND SOMETHING IS INSTALLED. Otherwise the
# file stays absent and the statusline renders no watch tile, which is the honest
# answer: this check has never run here. Never "watch 0 0" -- that reads as "no
# jobs needed" rather than "nobody looked".
WATCHF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-watch"
_inst=0; _load=0; _watched=0
if command -v launchctl >/dev/null 2>&1; then
  _watched=1
  _agents="$HOME/Library/LaunchAgents"
  _listing="$(launchctl list 2>/dev/null || printf '')"
  for _pl in "$_agents"/com.harbor.*.plist; do
    [ -f "$_pl" ] || continue
    _inst=$((_inst + 1))
    _lbl="${_pl##*/}"; _lbl="${_lbl%.plist}"
    # Anchored on both sides: a bare substring match would count
    # com.harbor.usage as loaded because com.harbor.usage-sessions is. The listing is wrapped in
    # newlines because $(...) strips the last one: a harbor job listed last must still match.
    case "
$_listing
" in
      *"	$_lbl
"*) _load=$((_load + 1)) ;;
    esac
  done
elif command -v systemctl >/dev/null 2>&1; then
  # Linux (harbor#618): installed is a harbor-*.timer in the user unit dir; loaded is an active timer.
  _watched=1
  for _t in "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"/harbor-*.timer; do
    [ -f "$_t" ] || continue
    _inst=$((_inst + 1))
    systemctl --user is-active --quiet "${_t##*/}" 2>/dev/null && _load=$((_load + 1))
  done
fi
if [ "$_watched" -eq 1 ]; then
  if [ "$_inst" -gt 0 ]; then
    _wtmp="$WATCHF.tmp"
    ( umask 077; printf 'watch %s %s\n' "$_load" "$_inst" > "$_wtmp" ) \
      && mv -f "$_wtmp" "$WATCHF" || rm -f "$_wtmp"
  else
    rm -f "$WATCHF"
  fi
fi

# `-s` IS LOAD-BEARING, NOT STYLE. `jq -e 'type == "array"'` is evaluated ONCE PER
# JSON DOCUMENT, so a producer emitting two concatenated top-level arrays passes
# it — every document is an array, every check returns 0, and the file is
# published. Measured 2026-08-14: the consumer then rendered THREE statusline rows
# with TWO different fleet counts, because `jq -r PROGRAM file` also runs per
# document. Slurping collapses the whole file into ONE array of documents, so
# `length == 1` is the only spelling that can say "exactly one answer in here".
# The consumer degrades on this too now (bin/status-fleet-glyph.sh), because a cache with
# a private remote and a launchd writer needs the check at both ends.
#
# EVERY ELEMENT MUST BE AN OBJECT (fleet#218). The array check
# alone admitted `[…, null]`, and each consumer counts elements: measured
# 2026-09-19, a null-padded copy of the live cache moved the statusline from ⚓15
# to ⚓16, a phantom project with no fields and no error. The producer's schema
# (snapshot.v1, `items: object`) already refuses that shape, so this is the
# writer agreeing with the contract, not a stricter one. It stops at the ELEMENT:
# fields inside an object stay unchecked on purpose, because the seam is
# additive-only and a field-level gate here would blank the tile on a legitimate
# producer change (the trade tests/status/statusline/fleet.test.sh pins).
if "$ORCH" snapshot --fleet "$FLEET" --json >"$TMP" 2>/dev/null \
   && jq -e -s 'length == 1 and (.[0] | type == "array" and all(.[]; type == "object"))' "$TMP" >/dev/null 2>&1; then
  mv "$TMP" "$CACHE"
else
  log_fail "the fleet snapshot failed, or failed the shape gate, so $CACHE keeps its previous value: $ORCH snapshot --fleet $FLEET"
  log_nofix "fleet — run $ORCH snapshot --fleet $FLEET --json to see why"
  log_end || :
  exit 1
fi

# harbor#1181: the cache above is overwritten every refresh, so fleet state had no history. One counts-only line per
# refresh makes it a stream; never project names, which can be client names.
# A missing library skips the history line, never the refresh: telemetry spills, it does not fail its caller.
HERE="$(dirname -- "$0")"
[ -f "$HERE/audit-stream-lib.sh" ] && . "$HERE/audit-stream-lib.sh" && \
harbor_emit fleet.snapshots "$(jq -c '{repos: length, dirty: (map(select(.status.dirty == true)) | length),
  ahead: (map(select((.status.ahead // 0) > 0)) | length), behind: (map(select((.status.behind // 0) > 0)) | length)}' \
  "$CACHE" 2>/dev/null)" || :

# harbor#1181 lane 5: the second-uid collector's findings land here, on this schedule (docs/reference/checks.md collector.health).
# It stands down when no collector is installed, and its red is its own receipt and checks.log line, not this job's.
[ ! -f "$HERE/audit-collector-check.sh" ] || sh "$HERE/audit-collector-check.sh" >/dev/null 2>&1 || :
