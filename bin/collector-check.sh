#!/usr/bin/env sh
# collector-check.sh (harbor#1181 lane 5) — the destination for the collector's findings: reads its world-readable
# status.json as the operator and files the collector.health receipt. Red when the heartbeat is older than 15 min,
# a source is unreadable (the read ACL removed?), or a new tamper event (truncated, edited, unreadable) appeared
# since the last run; red also appends one [check:collector.health] line to checks.log. Stood down when no
# collector is installed. Runs on fleet-snapshot-refresh's schedule (CHECKS.md).
set -eu
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/log-lib.sh"; . "$HERE/fs-lib.sh"
log_init collector-check
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STORE="${HARBOR_COLLECTOR_STORE:-/Library/Application Support/Harbor/collector}"
ST="$STORE/status.json"; SEEN="$CFG/cache/collector-check.seen"; RD="$(receipt_dir)"
STALE="${HARBOR_COLLECTOR_STALE:-900}"
if [ ! -f "$ST" ]; then
  log_skip "no collector at $STORE: not installed, nothing to judge"
  log_receipt "$RD" collector.health stood-down not-installed || log_warn "could not write the receipt in $RD"
  log_end; exit 0
fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is required to read $ST"; log_fix "$(pkg_hint jq)"; exit 1; }
# The heartbeat is the newer of a pass's end (status.json) and its start (pass.started): alive means a pass began
# within STALE, so a slow pass under load is not a dead collector, and a hung one still goes stale.
_hb="$(fs_mtime "$ST")"
[ ! -f "$STORE/pass.started" ] || { _ps="$(fs_mtime "$STORE/pass.started")"; [ "${_ps:-0}" -le "$_hb" ] 2>/dev/null || _hb="$_ps"; }
age=$(( $(date +%s) - _hb ))
unread="$(jq -r '.unreadable // 0' "$ST" 2>/dev/null || echo x)"; total="$(jq -r '.events_total // 0' "$ST" 2>/dev/null || echo x)"
seen=0; { [ -f "$SEEN" ] && IFS= read -r seen < "$SEEN"; } 2>/dev/null || :
case "$seen" in ''|*[!0-9]*) seen=0 ;; esac
why=""
[ "$age" -le "$STALE" ] || why="$why heartbeat-stale"
case "$unread" in 0) ;; *) why="$why unreadable-source" ;; esac
case "$total" in *[!0-9]*|'') why="$why status-unparseable" ;; *) [ "$total" -le "$seen" ] || why="$why new-events" ;; esac
# Lane 5b, the cross-check: the client counts its own tool decisions (cc-summary.json, written by otlp-receiver.py),
# the floor writes one guard row per call. Decisions today with NO guard row is a floor that stopped recording: hooks
# disarmed, the ledger made unwritable, or rows suppressed. Silent when the receiver has no count for today.
_day="$(date -u +%Y-%m-%d)"; _min="${HARBOR_COLLECTOR_SILENT_MIN:-20}"
_dec="$(jq -r --arg d "$_day" "[(.[\$d] // {}) | to_entries[] | select(.key | test(\"tool_decision$\")) | .value] | add // 0" "$STORE/cc-summary.json" 2>/dev/null || echo 0)"
case "$_dec" in ""|*[!0-9]*) _dec=0 ;; esac
if [ "$_dec" -ge "$_min" ]; then
  _rows="$(find "$CFG/MEMORY/OBSERVABILITY" -type f -name "guard-decisions.jsonl*" ! -path "*/archive/*" -exec cat {} + 2>/dev/null | grep "\"ts\":\"$_day" | grep -vc -E "\"d\":\"(armed|shadow|override)\"" || true)"   # session rows are not tool calls
  [ "${_rows:-0}" -gt 0 ] || why="$why guard-silent"
fi
mkdir -p "$CFG/cache"
# The off-host anchor (tier 3): every signed checkpoint the collector publishes is copied, once and never
# overwritten, into MEMORY/CHECKPOINTS/<host>/, which worklog-push.sh pushes to the private MEMORY remote. A
# published checkpoint that no longer matches its anchored copy is a signed day rewritten: checkpoint-changed.
_hh=""; { [ -f "$CFG/.helm-obs-host" ] && IFS= read -r _hh < "$CFG/.helm-obs-host"; } 2>/dev/null || :
case "$_hh" in ''|*[!A-Za-z0-9-]*) _hh=unknown-host ;; esac
_anc="$CFG/MEMORY/CHECKPOINTS/$_hh"
for _cf in "$STORE"/checkpoints/*.tsv "$STORE"/checkpoints/*.tsv.sig "$STORE"/checkpoints/collector.pub; do
  [ -f "$_cf" ] || continue
  _dst="$_anc/${_cf##*/}"
  if [ -f "$_dst" ]; then cmp -s "$_cf" "$_dst" || why="$why checkpoint-changed"
  else mkdir -p "$_anc" && cp "$_cf" "$_dst" 2>/dev/null || why="$why anchor-unwritable"; fi
done
case "$total" in *[!0-9]*|'') ;; *) printf '%s\n' "$total" > "$SEEN" ;; esac
if [ -n "$why" ]; then
  log_fail "collector.health:$why (heartbeat ${age}s ago, $unread unreadable, events $seen -> $total)"
  log_nofix "read $STORE/events.jsonl as the operator: sudo cat it, then decide; nothing here repairs a tampered ledger"
  # one checks.log line per CHANGE of reasons: a standing outage is the red receipt, not a line every tick
  _last=""; { [ -f "$SEEN.why" ] && IFS= read -r _last < "$SEEN.why"; } 2>/dev/null || :
  if [ "$_last" != "$why" ]; then
    printf '[check:collector.health] %s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$why" >> "$CFG/cache/checks.log" 2>/dev/null || :
  fi
  printf "%s\n" "$why" > "$SEEN.why" 2>/dev/null || :
  # shellcheck disable=SC2086 # the reasons are one word each, by construction above
  log_receipt "$RD" collector.health red $why || log_warn "could not write the receipt in $RD"
  log_end || :; exit 1
fi
rm -f "$SEEN.why" 2>/dev/null || :
log_ok "collector heartbeat ${age}s ago, no unreadable source, no new event"
log_receipt "$RD" collector.health green || log_warn "could not write the receipt in $RD"
log_end
