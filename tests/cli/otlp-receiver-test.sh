#!/usr/bin/env sh
# otlp-receiver.py (harbor#1181 lane 5b): keeps an allowlist of attributes and never prompt text or tool input,
# counts events per day for the cross-check, and as a server answers OTLP/HTTP JSON on 127.0.0.1 only.
. "$(dirname "$0")/../lib/core.sh"; t_init
X="$(cd "$(dirname "$0")/../.." && pwd)/bin/otlp-receiver.py"; ST="$T_TMP/store"
body() { # <event> <unix-ns> — one OTLP/JSON logs body, with fields that must NOT be kept
  printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","attributes":[' "$2"
  printf '{"key":"event.name","value":{"stringValue":"%s"}},{"key":"session.id","value":{"stringValue":"s-1"}},' "$1"
  printf '{"key":"tool_name","value":{"stringValue":"Bash"}},{"key":"decision","value":{"stringValue":"accept"}},'
  printf '{"key":"prompt","value":{"stringValue":"SECRET PROMPT TEXT"}},{"key":"tool_parameters","value":{"stringValue":"rm -rf SECRET"}}]}]}]}]}\n'
}
NS=1791500000000000000   # 2026-10-09T...Z
DAY="$(python3 -I -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1])/1e9,datetime.timezone.utc).strftime("%Y-%m-%d"))' "$NS" 2>/dev/null || date -u -r 1791500000 +%Y-%m-%d)"
body claude_code.tool_decision "$NS" > "$T_TMP/b.json"

t_section "ingest keeps the allowlist only"
t_eq "one record is kept" 1 "$(python3 -I "$X" --ingest "$T_TMP/b.json" --store "$ST" 2>/dev/null)"
L="$(cat "$ST/cc/$DAY.jsonl" 2>/dev/null)"
t_eq "event name and allowlisted attributes survive" "claude_code.tool_decision accept Bash s-1" \
  "$(printf '%s' "$L" | jq -r '"\(.event) \(.attrs.decision) \(.attrs.tool_name) \(.attrs["session.id"])"')"
t_eq "prompt text and tool input are dropped" 0 "$(printf '%s' "$L" | grep -c SECRET)"
t_eq "the summary counts it by day and name" 1 "$(jq -r --arg d "$DAY" '.[$d]["claude_code.tool_decision"]' "$ST/cc-summary.json")"
t_eq "the summary is world-readable, cc/ is not" "-rw-r--r-- drwx------" "$(ls -l "$ST/cc-summary.json" | cut -c1-10) $(ls -ld "$ST/cc" | cut -c1-10)"
python3 -I "$X" --ingest "$T_TMP/b.json" --store "$ST" >/dev/null 2>&1
t_eq "a second body adds to the count" 2 "$(jq -r --arg d "$DAY" '.[$d]["claude_code.tool_decision"]' "$ST/cc-summary.json")"

printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s","attributes":[{"key":"event.name","value":{"stringValue":"api_request"}},{"key":"session.id","value":{"stringValue":"s-9"}},{"key":"cost_usd","value":{"doubleValue":0.25}}]}]}]}]}\n' "$NS" > "$T_TMP/c.json"
python3 -I "$X" --ingest "$T_TMP/c.json" --store "$ST" >/dev/null 2>&1; python3 -I "$X" --ingest "$T_TMP/c.json" --store "$ST" >/dev/null 2>&1
t_eq "the client's own price is summed per session" 0.5 "$(jq -r '.cost_usd_by_session["s-9"]' "$ST/cc-summary.json")"

t_section "as a server"
P=$(( 40000 + $$ % 20000 )); python3 -I "$X" --port "$P" --store "$T_TMP/srv" >/dev/null 2>&1 & PID=$!
i=0; until curl -s -o /dev/null "http://127.0.0.1:$P/" 2>/dev/null || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
post() { curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: $1" --data-binary @"$T_TMP/b.json" "http://127.0.0.1:$P$2"; }
t_eq "POST /v1/logs as JSON is accepted" 200 "$(post application/json /v1/logs)"
t_eq "and stored" 1 "$(cat "$T_TMP/srv/cc/"*.jsonl 2>/dev/null | grep -c tool_decision)"
t_eq "protobuf is refused with a reason" 415 "$(post application/x-protobuf /v1/logs)"
t_eq "a path that is not OTLP is 404" 404 "$(post application/json /other)"
t_eq "metrics are accepted and dropped" 200 "$(post application/json /v1/metrics)"
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
t_done
