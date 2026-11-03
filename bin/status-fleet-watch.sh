#!/usr/bin/env sh
# status-fleet-watch.sh (harbor#1437) — the hourly fleet watch pass, scheduled by harbor: check id status.fleet-watch.
#
#   sh status-fleet-watch.sh [--if-due] [--timeout SECS] [--config-dir DIR]
#
# RIDES the status.fleet-snapshot job (every 300s) with --if-due, which makes every tick but the first of each hour a no-op: no
# plist of its own, so nothing here is a unit file an agent cannot install. The pass is bounded (--timeout, default 900): a hung
# probe is killed and reads as stood-down, and cannot stall the snapshot refresh that called it.
#
# Runs the fleet controller's `watch` over the fleet file: the remote probes (CI, cloud, supervised processes) refresh, the
# history is appended, and the threshold alerts come back as JSON. `watch` has no webhook (it emits and exits), so this is the
# only notifier a scheduled pass has: the alerts become one receipt, <config>/cache/checks/status.fleet-watch.json, which the
# daily `lint.findings` reconcile files as the issue `check/status.fleet-watch` and closes when a fresh receipt is green. Only
# the lint gate runs locally (`--task lint`): the tests of every repo each hour would queue behind the CI governor.
#
# THE REPORT IS THE DELTA. A subject is `<project> <category>`; the previous run's subjects are kept in
# <config>/cache/status-fleet-watch.tsv, and the run prints what is new and what is fixed, never the census. One
# [check:status.fleet-watch] line goes to checks.log for a run that changed something.
#
# Exit 0 nothing new · 1 a new alert · 2 usage · 3 unchecked: no controller or fleet file, or `watch` judged nothing (the
# receipt then says stood-down, never green). Writes only under <config>/cache.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
_SRC="$(CDPATH='' cd -- "$_SRC" && pwd)"
LOG_FD=2
. "$_SRC/library-log.sh"
log_init status-fleet-watch
ID="status.fleet-watch"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; DUE=0; LIMIT=900
usage_err() { log_fail "$1"; log_fix "sh bin/status-fleet-watch.sh --help"; log_end || :; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) [ $# -ge 2 ] || usage_err "--config-dir takes a directory"; CFG="$2"; shift 2 ;;
    --if-due) DUE=1; shift ;;
    --timeout) [ $# -ge 2 ] || usage_err "--timeout takes seconds"; LIMIT="$2"; shift 2 ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done
case "$LIMIT" in ''|*[!0-9]*) usage_err "--timeout takes whole seconds, not: $LIMIT" ;; esac
CACHE="$CFG/cache"; STATE="$CACHE/status-fleet-watch.tsv"; STAMP="$CACHE/status-fleet-watch.stamp"; CHECKS_LOG="$CACHE/checks.log"
# --if-due: an hourly pass. A stamp younger than 55 minutes means a pass already ran this hour; it is touched BEFORE the
# pass, so a pass that fails or hangs is retried next hour, not on every 5-minute tick.
if [ "$DUE" = 1 ] && [ -f "$STAMP" ] && [ -z "$(find "$STAMP" -mmin +55 2>/dev/null)" ]; then exit 0; fi
T="$(mktemp -d "${TMPDIR:-/tmp}/status-fleet-watch.XXXXXX")" || usage_err "cannot make a temp dir"
trap 'rm -rf "$T"' EXIT INT TERM HUP

# the fleet file and the controller binary, through the registry-aware reader, as status-fleet-snapshot-refresh.sh does (harbor#966)
FLEET="${HARBOR_SCOPE_FLEET_FILE:-$(sh "$_SRC/scope-roots.sh" --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)}"
ORCH="${HARBOR_SCOPE_FLEET_CONTROLLER_BIN:-${HARBOR_ORCH_BIN:-$(sh "$_SRC/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN 2>/dev/null || :)}}"

stood_down() { # <why>
  log_receipt "$(receipt_dir "$CFG")" "$ID" stood-down >/dev/null 2>&1 || :
  log_fail "$1"; log_fix "$2"; log_end || :; exit 3
}
[ -n "$ORCH" ] && [ -x "$ORCH" ] || stood_down "no fleet controller binary (HARBOR_SCOPE_FLEET_CONTROLLER_BIN is '${ORCH:-unset}')" "sh bin/scope-roots.sh --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN"
[ -n "$FLEET" ] && [ -r "$FLEET" ] || stood_down "no fleet file (HARBOR_SCOPE_FLEET_FILE is '${FLEET:-unset}')" "sh bin/scope-roots.sh --get HARBOR_SCOPE_FLEET_FILE"

mkdir -p "$CACHE" 2>/dev/null || :
: > "$STAMP" 2>/dev/null || :
_rc=0
"$ORCH" watch --fleet "$FLEET" --json --changed-only --interval 3600 --task lint > "$T/out" 2> "$T/err" &
_pid=$!
# the bound: a 1s poll, not one long sleep, and stdio off, so no orphan holds the caller's pipe open past the pass
( _i=0; while [ "$_i" -lt "$LIMIT" ] && kill -0 "$_pid" 2>/dev/null; do sleep 1; _i=$((_i + 1)); done
  kill "$_pid" 2>/dev/null ) >/dev/null 2>&1 &
_wd=$!
wait "$_pid" || _rc=$?
kill "$_wd" 2>/dev/null; wait "$_wd" 2>/dev/null
# 0 quiet and 1 eventful are both a judged pass; anything else (2: no fleet found) judged nothing
case "$_rc" in 0|1) ;; *) stood_down "watch judged nothing (exit $_rc): $(head -n 1 "$T/err" | cut -c1-160)" "$ORCH watch --fleet $FLEET --json" ;; esac
jq -r '.alerts[]? | "\(.project) \(.category)\t\(.level): \(.message)"' "$T/out" > "$T/alerts" 2>/dev/null \
  && jq -e '.alerts | type == "array"' "$T/out" >/dev/null 2>&1 \
  || stood_down "watch printed no alert list (not the --json report)" "$ORCH watch --fleet $FLEET --json"
LC_ALL=C sort -u "$T/alerts" -o "$T/alerts"
cut -f1 "$T/alerts" | LC_ALL=C sort -u > "$T/cur"
[ -f "$STATE" ] || : > "$STATE"
LC_ALL=C sort -u "$STATE" -o "$T/old"
comm -13 "$T/old" "$T/cur" > "$T/new"
comm -23 "$T/old" "$T/cur" > "$T/fixed"
NNEW="$(grep -c . "$T/new" | tr -d ' ')"; NFIX="$(grep -c . "$T/fixed" | tr -d ' ')"; NCUR="$(grep -c . "$T/cur" | tr -d ' ')"
NSTAND=$((NCUR - NNEW))

mkdir -p "$CACHE" 2>/dev/null || :
_tmp="$(mktemp "$CACHE/.status-fleet-watch.XXXXXX" 2>/dev/null)" || _tmp=""
if [ -n "$_tmp" ] && cp "$T/cur" "$_tmp" && mv -f "$_tmp" "$STATE"; then :; else
  [ -z "$_tmp" ] || rm -f "$_tmp"; log_warn "the state could not be written at $STATE, so the next run will report this one's alerts as new again"
fi
if [ "$NCUR" -eq 0 ]; then _st=green; else _st=red; fi
set --; while IFS= read -r _s; do set -- "$@" "$_s"; done < "$T/cur"
log_receipt "$(receipt_dir "$CFG")" "$ID" "$_st" "$@" \
  || log_warn "no receipt could be written under $(receipt_dir "$CFG"), so the findings channel does not see this run"

printf '[check:%s] %s alert(s): %s new, %s fixed, %s standing\n' "$ID" "$NCUR" "$NNEW" "$NFIX" "$NSTAND"
[ "$NNEW" -gt 0 ] || [ "$NFIX" -gt 0 ] || printf '  nothing new\n'
while IFS= read -r _n; do printf '  new      %s\n' "$(grep -F "$_n	" "$T/alerts" | head -n 1 | tr '\t' ' ' | cut -c1-160)"; done < "$T/new"
while IFS= read -r _n; do printf '  fixed    %s\n' "$_n"; done < "$T/fixed"
if [ "$NNEW" -gt 0 ] || [ "$NFIX" -gt 0 ]; then
  if [ ! -e "$CHECKS_LOG" ] || { [ -f "$CHECKS_LOG" ] && [ ! -L "$CHECKS_LOG" ] && [ "$(ls -ln "$CHECKS_LOG" | awk '{ print $2 }')" = 1 ]; }; then
    printf '[check:%s] %s %s new, %s fixed, %s standing\n' "$ID" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$NNEW" "$NFIX" "$NSTAND" >> "$CHECKS_LOG" 2>/dev/null || :
  fi
fi
log_end || :
[ "$NNEW" -eq 0 ] || exit 1
exit 0
