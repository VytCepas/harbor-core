#!/usr/bin/env sh
# L0-5-interim (harbor#21) — write the fleet snapshot cache the statusline glyph reads.
# The glyph NEVER invokes the orchestrator; only this refresher does, on an interval
# (launchd/cron). Atomic write; on failure the previous cache is kept and the glyph
# degrades to "fleet: unknown" via staleness. POSIX, jq only.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the first executable line, because a script that treats the flag as work makes a --help sweep run for minutes. The text is the header, read at runtime.
# Removed notes: docs/explanation/code-cases/bin-status-fleet-snapshot-refresh.md
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# One log format (contracts/logging.md): a scheduled job is silent while it works, and its one failure says what failed and how to see why.
. "$(dirname -- "$0")/library-log.sh"
log_init fleet-snapshot-refresh
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$HOME/.claude/cache}"
CACHE="$CACHE_DIR/fleet-snapshot.json"
FLEET="${HARBOR_SCOPE_FLEET_FILE:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)}"
ORCH="${HARBOR_SCOPE_FLEET_CONTROLLER_BIN:-${HARBOR_ORCH_BIN:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN 2>/dev/null || :)}}"

mkdir -p "$CACHE_DIR"
TMP="$CACHE.tmp.$$"
OBS="$CACHE_DIR/guard-decisions.json"
OTMP="$OBS.tmp.$$"
trap 'rm -f "$TMP" "$OTMP"' EXIT

# Guard-decision counts (L1/OBSERVE-1, harbor#41, harbor#59), reduced here because reading the ledger scales with its size. Remove the cache on failure, never keep the last good value: an absent ledger must stay absent.
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

# What is BUILT here and NOT RUNNING there (harbor#44): piggybacked on this refresher, since a check for a schedule never installed cannot depend on a schedule the operator must install first; BEFORE the orchestrator block, whose exit 1 must not skip it.
# --live versus --dir is session-verdicts.sh's idiom: renew-check refuses --apply on the live dir unless it is NAMED --live, so passing the path would be a no-op that looks like a clean box.
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

# The sweep, counted twice a day (operator, 2026-09-22): housekeeping-clean.sh --if-due makes every other tick a no-op; it COUNTS AND NEVER DELETES and writes .helm-sweep for the statusline. BEFORE the orchestrator block, for the same reason.
# INLINE, not backgrounded: a record takes ~60s over fifteen repos, and launchd kills the job's process group on exit (AbandonProcessGroup), so `&` would die with this script.
if [ -f "$SRC_DIR/housekeeping-clean.sh" ]; then
  _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  _p() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
  LIVE_DIR="$HOME/.claude"
  if [ "$(_p "$_cfg")" = "$(_p "$LIVE_DIR")" ]; then
    sh "$SRC_DIR/housekeeping-clean.sh" --record --if-due --live >/dev/null 2>&1 || true
  else
    CLAUDE_CONFIG_DIR="$_cfg" sh "$SRC_DIR/housekeeping-clean.sh" --record --if-due >/dev/null 2>&1 || true
  fi
fi

# The CI queue (harbor#657), every tick because a queue changes by the minute; the cache holds epochs only and status-fleet-glyph.sh does the countdown. BEFORE the orchestrator block.
if [ -f "$SRC_DIR/ci-queue.sh" ]; then
  HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-queue.sh" >/dev/null 2>&1 || true
fi

# Main's tip (harbor#586): inside this run because a new launchd job needs the operator's yes. Writes cache/main-tip-verdict.json (the statusline's MAIN RED) and one checks.log line per change.
if [ -f "$SRC_DIR/ci-main-tip-verdict.sh" ]; then
  HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-main-tip-verdict.sh" >/dev/null 2>&1 || true
fi

# The obligations ledger (harbor#1050): reads are bounded (10s each, 40s together, HARBOR_STATUS_OBLIGATION_BUDGET) and a source that does not answer flips nothing. BEFORE the orchestrator block.
if [ -f "$SRC_DIR/status-obligations.sh" ]; then
  sh "$SRC_DIR/status-obligations.sh" reconcile >/dev/null 2>&1 || true
fi

# The account plan and main's protection (harbor#1060): two reads a tick, one checks.log line per change, and the statusline's PLAN/GATE alarm until `ci-github-plan.sh ack`.
if [ -f "$SRC_DIR/ci-github-plan.sh" ]; then
  HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-github-plan.sh" >/dev/null 2>&1 || true
fi

# The CI runner (harbor#865): one bounded read of the month's bill a tick; sets HARBOR_CI_RUNNER only when the value would change, and a failed read flips nothing (bin/ci-runner-switch.sh).
if [ -f "$SRC_DIR/ci-runner-switch.sh" ]; then
  HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runner-switch.sh" >/dev/null 2>&1 || true
  # each `org ORG` in .harbor-ci-runners gets its own verdict, against its own cap (harbor#1060)
  for _org in $(awk '$1 == "org" && $2 ~ /^[A-Za-z0-9][A-Za-z0-9-]*$/ { print $2 }' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.harbor-ci-runners" 2>/dev/null); do
    HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runner-switch.sh" --org "$_org" >/dev/null 2>&1 || true
  done
fi

# The fleet's runners (harbor#1060): after runner-switch, whose verdict each repo's CI_RUNS_ON follows; also raises the ci-runner-alarm. Creates no container and touches no billing (bin/ci-runners.sh).
if [ -f "$SRC_DIR/ci-runners.sh" ]; then
  HARBOR_SCOPE_CACHE_DIR="$CACHE_DIR" sh "$SRC_DIR/ci-runners.sh" tick >/dev/null 2>&1 || true
fi

# The watch: are the schedulers this board depends on actually loaded? The statusline numbers are only as true as the launchd jobs that write them; if one stops, its tokens freeze and keep rendering as current.
# INSTALLED is the denominator, LOADED the numerator (drift-renew-check.sh answers built-here-installed-nowhere, not installed-and-not-loaded). `launchctl list` is matched on the LABEL, not parsed for status:
# `-` in the pid column is the NORMAL state of a periodic job, and reading it as dead would alarm every healthy one. Written only when launchctl or systemctl exists and something is installed;
# otherwise the file stays absent (never `watch 0 0`, which reads as no jobs needed rather than nobody looked).
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
    # Anchored on both sides: a bare substring would count com.harbor.status.usage as loaded because com.harbor.status.usage-sessions is. The listing is wrapped in newlines because $(...) strips the last one.
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

# `-s` is load-bearing: `jq -e 'type == "array"'` runs once per JSON document, so two concatenated arrays pass it (measured 2026-08-14: three statusline rows, two fleet counts); the consumer (bin/status-fleet-glyph.sh) degrades on this too.
# Every element must be an OBJECT (fleet#218): `[..., null]` passed the array check and moved the statusline from 15 to 16 berths (a phantom project). Fields inside an object stay unchecked on purpose: the seam is additive-only (pinned in tests/status/statusline/fleet.test.sh).
if "$ORCH" snapshot --fleet "$FLEET" --json >"$TMP" 2>/dev/null \
   && jq -e -s 'length == 1 and (.[0] | type == "array" and all(.[]; type == "object"))' "$TMP" >/dev/null 2>&1; then
  mv "$TMP" "$CACHE"
else
  log_fail "the fleet snapshot failed, or failed the shape gate, so $CACHE keeps its previous value: $ORCH snapshot --fleet $FLEET"
  log_nofix "fleet — run $ORCH snapshot --fleet $FLEET --json to see why"
  log_end || :
  exit 1
fi

# harbor#1181: one counts-only line per refresh makes fleet state a stream (never project names, which can be client names). A missing library skips the history line, never the refresh.
HERE="$(dirname -- "$0")"
[ -f "$HERE/audit-stream-lib.sh" ] && . "$HERE/audit-stream-lib.sh" && \
harbor_emit fleet.snapshots "$(jq -c '{repos: length, dirty: (map(select(.status.dirty == true)) | length),
  ahead: (map(select((.status.ahead // 0) > 0)) | length), behind: (map(select((.status.behind // 0) > 0)) | length)}' \
  "$CACHE" 2>/dev/null)" || :

# harbor#1181 lane 5: the second-uid collector's findings land here, on this schedule (docs/reference/checks.md collector.health).
# It stands down when no collector is installed, and its red is its own receipt and checks.log line, not this job's.
[ ! -f "$HERE/audit-collector-check.sh" ] || sh "$HERE/audit-collector-check.sh" >/dev/null 2>&1 || :

# harbor#1437: the fleet controller's watch pass, once an hour, on this schedule (docs/reference/checks.md status.fleet-watch).
# --if-due makes every other tick a no-op; the pass is bounded, and its red is its own receipt and checks.log line, not this job's.
[ ! -f "$HERE/status-fleet-watch.sh" ] || sh "$HERE/status-fleet-watch.sh" --if-due >/dev/null 2>&1 || :
