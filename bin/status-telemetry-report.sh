#!/usr/bin/env sh
# status-telemetry-report.sh (harbor#1181 lane 7) — the signals Harbor captures, turned into answers. TSV on stdout.
#   status-telemetry-report.sh approvals  [--bus DIR]                 each approval: opened, closed, latency in seconds
#   status-telemetry-report.sh pr-tokens  [--bus DIR] [--usage FILE]  each opened PR: its session's tokens, shared across
#                                                              that session's PRs (TOKENS, not dollars: the
#                                                              session rows carry no model to price them by)
#   status-telemetry-report.sh pr-cost    [--bus DIR] [--summary FILE] each opened PR: its session's USD, as the client priced
#                                                              it (otlp-receiver's cc-summary.json), shared across PRs
#   status-telemetry-report.sh skills     [--bus DIR]                 skill calls by skill
#   status-telemetry-report.sh memory     [--bus DIR]                 memory-note reads by note
# The bus keeps 14 days; for older history point --bus at the collector's copy. Read-only.
set -eu
case "${1:-}" in -h|--help|'') awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/library-log.sh"
LOG_FD=2   # stdout is the report
log_init telemetry-report
CMD="$1"; shift
BUS="${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}"; USAGE=""; SUMMARY=""
while [ $# -gt 0 ]; do case "$1" in
  --bus) BUS="${2:?--bus needs a dir}"; shift 2 ;;
  --usage) USAGE="${2:?--usage needs a file}"; shift 2 ;;
  --summary) SUMMARY="${2:?--summary needs a file}"; shift 2 ;;
  *) log_fail "unknown argument $1"; log_nofix "sh bin/status-telemetry-report.sh --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; exit 1; }
[ -d "$BUS" ] || { log_fail "no bus at $BUS"; log_nofix "HARBOR_EVENT_DIR or --bus"; exit 1; }
events() { find "$BUS" -type f -name '*.jsonl' -exec cat {} + 2>/dev/null | jq -c 'select(type == "object")' 2>/dev/null || :; }

case "$CMD" in
  approvals)
    printf 'id\topened\tclosed\tlatency_s\n'
    events | jq -rs '
      (map(select(.kind == "approval.open"))  | map({key: .subject, value: .ts}) | from_entries) as $o
      | (map(select(.kind == "approval.close")) | map({key: .subject, value: .ts}) | from_entries) as $c
      | $o | to_entries[] | [.key, .value, ($c[.key] // "open"),
          (if $c[.key] then (($c[.key] | fromdateiso8601) - (.value | fromdateiso8601)) else "" end)] | @tsv' ;;
  pr-tokens)
    [ -n "$USAGE" ] || USAGE="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/MEMORY/USAGE" -name sessions.jsonl 2>/dev/null | head -n 1)"
    [ -f "$USAGE" ] || { log_fail "no sessions.jsonl to join against"; log_nofix "--usage FILE, or run status-usage-aggregate.sh --sessions --apply"; exit 1; }
    printf 'pr\tsession\tprs_in_session\tinput\toutput\tcache_create\tcache_read\n'
    events | jq -c 'select(.kind == "pr.opened")' | jq -rs --slurpfile u "$USAGE" '
      ($u | map({key: .session, value: .}) | from_entries) as $s
      | (group_by(.data.session_id) | map({key: (.[0].data.session_id // ""), value: length}) | from_entries) as $n
      | .[] | (.data.session_id // "") as $sid | ($s[$sid] // null) as $r | ($n[$sid] // 1) as $k
      | [.subject, $sid, $k,
         (if $r then ($r.inp / $k | floor) else "unknown" end), (if $r then ($r.out / $k | floor) else "unknown" end),
         (if $r then ($r.cc / $k | floor) else "unknown" end), (if $r then ($r.cr / $k | floor) else "unknown" end)] | @tsv' ;;
  pr-cost)
    if [ -z "$SUMMARY" ]; then case "$(uname -s)" in
      Darwin) SUMMARY='/Library/Application Support/Harbor/collector/cc-summary.json' ;; *) SUMMARY=/var/lib/harbor/collector/cc-summary.json ;;
    esac; fi
    [ -f "$SUMMARY" ] || { log_fail "no $SUMMARY: the OTLP receiver is not installed or has seen nothing"; log_nofix "sudo sh bin/audit-collector-install.sh; or pr-tokens"; exit 1; }
    printf 'pr\tsession\tprs_in_session\tusd\n'
    events | jq -c 'select(.kind == "pr.opened")' | jq -rs --slurpfile c "$SUMMARY" '
      ($c[0].cost_usd_by_session // {}) as $u
      | (group_by(.data.session_id) | map({key: (.[0].data.session_id // ""), value: length}) | from_entries) as $n
      | .[] | (.data.session_id // "") as $sid | ($n[$sid] // 1) as $k
      | [.subject, $sid, $k, (if $u[$sid] then (($u[$sid] / $k * 100 | round) / 100) else "unknown" end)] | @tsv' ;;
  skills|memory)
    _k=skill.call; [ "$CMD" = skills ] || _k=memory.read
    printf 'subject\tcount\n'
    events | jq -r --arg k "$_k" 'select(.kind == $k) | .subject' | LC_ALL=C sort | uniq -c \
      | sort -rn | awk '{ printf "%s\t%s\n", $2, $1 }' ;;
  *) log_fail "unknown report $CMD"; log_nofix "sh bin/status-telemetry-report.sh --help"; exit 2 ;;
esac
log_end
