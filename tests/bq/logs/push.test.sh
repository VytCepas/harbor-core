#!/usr/bin/env sh
# push.test.sh (harbor#1278) — `harbor logs push` (bin/bq-logs.sh): the Mac's coded projection only. No digest (h, sk), no failure
# subject (k), no host folder, no bus subject, repo or data leaves; a dry run sends nothing; --apply needs the notice marker and goes
# as the impersonated loader; the scrub gate stops a projection that names the machine; the Mac's id is random, made once, read only.
. "$(dirname "$0")/../../lib/core.sh"; t_init
P="$T_ROOT/bin/bq-logs.sh"
HOSTDIR=fixture-host-77
OBS="$CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY/$HOSTDIR"; mkdir -p "$OBS/archive" "$CLAUDE_CONFIG_DIR/MEMORY/USAGE/$HOSTDIR"
EVD="$T_TMP/events"; mkdir -p "$EVD"; HARBOR_EVENT_DIR="$EVD"; export HARBOR_EVENT_DIR
XDG_CONFIG_HOME="$T_TMP/xdg"; XDG_STATE_HOME="$T_TMP/state"; export XDG_CONFIG_HOME XDG_STATE_HOME
D=2026-11-07
cat > "$OBS/guard-decisions.jsonl" <<EOF
{"v":1,"ts":"${D}T10:13:22Z","g":"egress","d":"block","r":"key-material-egress","s":"argv","t":"Bash","h":"d1d1d1d1d1d1d1d1","sk":"5e55105e55105e55","c":"confined","x":"-"}
{"v":1,"ts":"${D}T10:14:00Z","g":"egress","d":"block","r":"key-material-egress","s":"argv","t":"Bash","h":"d1d1d1d1d1d1d1d1","sk":"5e55105e55105e55","c":"confined","x":"-"}
{"v":1,"ts":"${D}T10:15:00Z","g":"egress","d":"block","r":"key-material-egress","s":"argv","t":"Bash","h":"d2d2d2d2d2d2d2d2","sk":"5e55105e55105e55","c":"unconfined","x":"cloud"}
{"v":1,"ts":"${D}T10:15:00Z","g":"bash","d":"allow","r":"bash-clean","s":"meta","t":"Bash","h":"-","sk":"5e55105e55105e55","c":"unconfined","x":"cloud"}
{"v":1,"ts":"${D}T10:16:00Z","g":"egress","d":"allow","r":"egress-clean","s":"meta","t":"mcp","h":"-","sk":"5e55105e55105e55","c":"-","x":"-"}
EOF
printf '%s\n' "{\"v\":1,\"ts\":\"2026-10-01T10:00:00Z\",\"g\":\"egress\",\"d\":\"deny\",\"r\":\"egress-clean\",\"s\":\"meta\",\"t\":\"Bash\",\"h\":\"-\",\"sk\":\"-\",\"c\":\"-\",\"x\":\"-\"}" > "$OBS/archive/guard-decisions.20261001T000000Z.jsonl"
cat > "$OBS/tool-failures.jsonl" <<EOF
{"v":1,"ts":"${D}T11:00:00Z","t":"Bash","e":"not-found","k":"~/clients/acme/plan.xlsx","h":"f00df00df00df00d","s":"5e55105e55105e55","ms":12}
{"v":1,"ts":"${D}T11:01:00Z","t":"mcp__claude_ai_Acme_Flow","e":"timeout","k":"acme","h":"f00df00df00df00e","s":"5e55105e55105e55","ms":30000}
EOF
cat > "$EVD/$D.jsonl" <<EOF
{"id":"x1","ts":"${D}T09:00:00Z","src":"hook","kind":"session.start","subject":"acme-session","repo":"acme-repo","cause":"","data":{"title":"Acme renewal"}}
{"id":"x2","ts":"${D}T09:05:00Z","src":"hook","kind":"agent.spawn","subject":"acme","repo":"acme-repo","cause":"","data":{}}
{"id":"x3","ts":"${D}T09:06:00Z","src":"hook","kind":"pr.opened","subject":"acme-org/acme-repo#4","repo":"acme-repo","cause":"","data":{}}
EOF
printf '{"day":"%s","model":"claude-opus-5-5","entry":"cli","msgs":3,"inp":1,"out":2,"cc":3,"cr":4}\n{"day":"%s","model":"<synthetic>","entry":"cli","msgs":1,"inp":0,"out":0,"cc":0,"cr":0}\n' "$D" "$D" > "$CLAUDE_CONFIG_DIR/MEMORY/USAGE/$HOSTDIR/usage.jsonl"
push() { _rc=0; sh "$P" push --since "$D" --until "$D" "$@" > "$T_TMP/rows.jsonl" 2> "$T_TMP/err" || _rc=$?; }

t_section "1 - a dry run prints the coded rows and sends nothing"
mkdir -p "$T_TMP/bqbin"; printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT" "$*" >> "%s/bq.log"; [ "$1" = query ] && cat > "%s/query.sql"; exit 0\n' "$T_TMP" "$T_TMP" > "$T_TMP/bqbin/bq"; chmod +x "$T_TMP/bqbin/bq"
PATH="$T_TMP/bqbin:$PATH" push
t_eq "exit 0" 0 "$_rc"
t_eq "nothing reached bq" no "$([ -s "$T_TMP/bq.log" ] && echo yes || echo no)"
t_has "it says nothing was sent" "$(cat "$T_TMP/err")" "Nothing was sent"
t_eq "every row is a table and a row" 0 "$(jq -c 'select((has("table") and has("row")) | not)' "$T_TMP/rows.jsonl" | grep -c . || true)"
ROWS="$(cat "$T_TMP/rows.jsonl")"
t_eq "the window holds: the October archive row is out" 0 "$(jq -c 'select(.row.day < "2026-11-07")' "$T_TMP/rows.jsonl" | grep -c . || true)"
t_eq "guard rows: the three blocks folded into two rows by confinement" "3" "$(jq -s '[.[] | select(.table == "decision") | .row.count] | add' "$T_TMP/rows.jsonl")"
t_eq "distinct subjects and repeats counted on the Mac: one command twice, then another once" "1:2 1:1" "$(jq -r -s '[.[] | select(.table == "decision") | .row] | sort_by(.confinement) | map("\(.distinct_subjects):\(.max_repeat)") | join(" ")' "$T_TMP/rows.jsonl")"
t_eq "the mcp tool failure is mcp" 1 "$(jq -s '[.[] | select(.table == "activity" and .row.tool == "mcp" and .row.error_class == "timeout")] | length' "$T_TMP/rows.jsonl")"
t_eq "<synthetic> is synthetic" 1 "$(jq -s '[.[] | select(.table == "usage_daily" and .row.model == "synthetic")] | length' "$T_TMP/rows.jsonl")"
t_eq "a session and an agent from the bus kinds" "1 0 1" "$(jq -r -s '[.[] | select(.table == "session")][0].row | "\(.started) \(.ended) \(.agents)"' "$T_TMP/rows.jsonl")"

t_section "2 - nothing but codes and counts leaves (D10)"
for v in d1d1d1d1d1d1d1d1 d2d2d2d2d2d2d2d2 5e55105e55105e55 f00df00df00df00d acme Acme clients plan.xlsx "$HOSTDIR" x1 x3; do
  t_hasnt "no '$v'" "$ROWS" "$v"
done
t_eq "no field named h, sk, k, subject, repo or data" 0 "$(jq -c '.row | keys[] | select(. == "h" or . == "sk" or . == "k" or . == "subject" or . == "repo" or . == "data" or . == "s")' "$T_TMP/rows.jsonl" | grep -c . || true)"
t_eq "every row is a day, never an hour" 0 "$(jq -c '.row | to_entries[] | select(.value | type == "string" and test("T[0-9]{2}:"))' "$T_TMP/rows.jsonl" | grep -c . || true)"

t_section "3 - the Mac's id: random, made once, read only"
ID="$(cat "$XDG_CONFIG_HOME/harbor/logs.id")"
t_eq "32 hex" 1 "$(printf '%s\n' "$ID" | grep -cE '^[0-9a-f]{32}$')"
t_eq "every row carries it" "$ID" "$(jq -r -s 'map(.row.person_id) | unique | join(",")' "$T_TMP/rows.jsonl")"
push; t_eq "a second push keeps it" "$ID" "$(cat "$XDG_CONFIG_HOME/harbor/logs.id")"
t_eq "harbor logs id prints it" "$ID" "$(sh "$P" id 2>/dev/null)"
t_eq "...and makes none when it is missing" "1 no" "$(mv "$XDG_CONFIG_HOME/harbor/logs.id" "$T_TMP/id.keep"; sh "$P" id >/dev/null 2>&1; echo "$? $([ -e "$XDG_CONFIG_HOME/harbor/logs.id" ] && echo yes || echo no)")"
mv "$T_TMP/id.keep" "$XDG_CONFIG_HOME/harbor/logs.id"

t_section "4 - --apply needs the marker, then goes as the impersonated loader"
PATH="$T_TMP/bqbin:$PATH" push --apply --project harbor-logs-eu --dataset harbor_logs
t_eq "no marker: refused" 1 "$_rc"
t_eq "...and nothing reached bq" no "$([ -s "$T_TMP/bq.log" ] && echo yes || echo no)"
: > "$XDG_CONFIG_HOME/harbor/notice-received"
PATH="$T_TMP/bqbin:$PATH" push --apply --project harbor-logs-eu --dataset harbor_logs
t_eq "with it: exit 0" 0 "$_rc"
t_eq "every bq call impersonates the loader, no key file" 0 "$(grep -v '^harbor-bq-loader@harbor-logs-eu.iam.gserviceaccount.com|' "$T_TMP/bq.log" | grep -c . || true)"
t_has "the staging tables are loaded" "$(cat "$T_TMP/bq.log")" "load --source_format=NEWLINE_DELIMITED_JSON harbor-logs-eu:harbor_logs.stg_decision"
t_has "and the merge replaces the Mac's days" "$(cat "$T_TMP/query.sql")" "DELETE FROM \`harbor-logs-eu.harbor_logs.decision\` t WHERE EXISTS"
t_eq "the cursor holds the last day pushed" "$D" "$(cat "$XDG_STATE_HOME/harbor/logs/last-push")"

t_section "5 - the scrub gate stops a projection that names this machine"
# the user name is a word the rows carry (a rule token): the gate must see it, refuse, and send nothing
: > "$T_TMP/bq.log"
USER=egress LOGNAME=egress PATH="$T_TMP/bqbin:$PATH" push --apply --project harbor-logs-eu --dataset harbor_logs
t_eq "refused" 1 "$_rc"
t_has "by the scrub gate, by class" "$(cat "$T_TMP/err")" "user name"
t_eq "nothing reached bq" no "$([ -s "$T_TMP/bq.log" ] && echo yes || echo no)"
t_done
