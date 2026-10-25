#!/usr/bin/env sh
# session-subagent-check.sh, the advisory SubagentStop hook: a final report whose hash equals this agent's
# previous stop draws the duplicate note; a background task still running that this agent started draws
# the orphan note; everything else is silent; every path exits 0 and never blocks (harbor#445 item E).
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/session-subagent-check.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$T/cfg"; ST="$T/state"
printf 'Command running in background with ID: bg-77\nmentions bg-88 in passing\n' > "$T/agent-a.jsonl"
printf '{"agentId":"ag10","x":1}\n{"agentId":"ag10","y":2}\n' > "$T/agent-self.jsonl"
: > "$T/agent-empty.jsonl"
run() { # <agent_id> <message> <background_tasks-json> [transcript] [stop_hook_active]
  jq -nc --arg id "$1" --arg m "$2" --argjson b "$3" --arg tp "$T/${4:-agent-a}.jsonl" --argjson a "${5:-false}" \
    '{session_id:"s",hook_event_name:"SubagentStop",stop_hook_active:$a,agent_id:$id,agent_type:"general-purpose",
      agent_transcript_path:$tp,last_assistant_message:$m,background_tasks:$b}' > "$T/p.json"
  CLAUDE_CONFIG_DIR="$CFG" HARBOR_SESSION_STATE_DIR="$ST" sh "$TOOL" > "$T/out" 2> "$T/err" < "$T/p.json"; RC=$?; }
msg() { cat "$T/out"; }
NONE='[]'
RUN77='[{"id":"bg-77","type":"shell","status":"running","command":"sleep 99"}]'
DONE77='[{"id":"bg-77","type":"shell","status":"completed"}]'
RUN88='[{"id":"bg-88","type":"shell","status":"running","command":"sleep 99"}]'

t_section "duplicate final report"
run ag1 'Report A' "$NONE";  t_eq "first stop: silent" "" "$(msg)"
run ag1 'Report A' "$NONE";  t_has "same hash as the previous stop: note" "$(msg)" 'duplicate'
t_has "the note names its id" "$(msg)" '[check:subagent-stop]'
t_has "the note carries the disable command" "$(msg)" 'subagent-stop.off'
run ag1 'Report B' "$NONE";  t_eq "a different report: silent" "" "$(msg)"
run ag2 'Report A' "$NONE";  t_eq "the same text from ANOTHER agent: silent" "" "$(msg)"

t_section "background tasks this agent started"
run ag3 'r1' "$RUN77";       t_has "running and started by this agent: note" "$(msg)" 'bg-77'
run ag4 'r2' "$DONE77";      t_eq "finished: silent" "" "$(msg)"
run ag5 'r3' "$RUN88";       t_eq "running but NOT in this agent's transcript: silent" "" "$(msg)"
run ag6 'r4' "$RUN77" agent-empty; t_eq "empty transcript, cannot attribute: silent" "" "$(msg)"

PEND77='[{"id":"bg-77","type":"shell","status":"pending","command":"sleep 99"}]'
SELF='[{"id":"ag10","type":"subagent","status":"running"}]'
run ag11 'p' "$PEND77";      t_has "pending counts like running" "$(msg)" 'bg-77'
run ag10 's' "$SELF" agent-self; t_eq "the agent's own task id, on every transcript line: silent" "" "$(msg)"
run ag12 's' "$RUN88";       t_eq "an id merely mentioned, no launch receipt: silent" "" "$(msg)"

t_section "state files are aged out"
mkdir -p "$ST/agent-stop"; : > "$ST/agent-stop/oldagent"; touch -t 202001010000 "$ST/agent-stop/oldagent"
run ag13 'fresh' "$NONE";    t_eq "a state file older than 7 days is removed" "" "$(find "$ST/agent-stop" -name oldagent)"
t_eq "a fresh one stays" 1 "$(find "$ST/agent-stop" -name ag13 | wc -l | tr -d ' ')"

t_section "never blocks: exit 0, one systemMessage, nothing on stderr"
run ag7 'x' "$RUN77"
t_eq "output is one systemMessage" 0 "$(jq -e 'keys==["systemMessage"]' "$T/out" >/dev/null 2>&1; echo $?)"
t_eq "no decision" "" "$(jq -r '.decision // empty' "$T/out")"
t_eq "nothing on stderr" "" "$(cat "$T/err")"
t_eq "exit 0" 0 "$RC"
run ag8 'x' "$RUN77" agent-a true; t_eq "stop_hook_active stands it down" "" "$(msg)"
printf 'not json' > "$T/p3.json"
t_exit "garbage payload" 0 env CLAUDE_CONFIG_DIR="$CFG" HARBOR_SESSION_STATE_DIR="$ST" sh "$TOOL" < "$T/p3.json"
printf '{"agent_id":"../../etc","last_assistant_message":"x"}' > "$T/p4.json"
t_exit "unsafe agent_id" 0 env CLAUDE_CONFIG_DIR="$CFG" HARBOR_SESSION_STATE_DIR="$ST" sh "$TOOL" < "$T/p4.json"
t_eq "unsafe agent_id writes nothing outside the state dir" "" "$(find "$T" -name 'etc*' 2>/dev/null)"

t_section "off switches"
run ag9 'D' "$NONE"; run ag9 'D' "$NONE"
t_eq "env off" "" "$( SUBAGENT_STOP_CHECK=off; export SUBAGENT_STOP_CHECK; run ag9 'D' "$NONE"; msg )"
mkdir -p "$CFG"; : > "$CFG/subagent-stop.off"
run ag9 'D' "$NONE"; t_eq "sentinel off" "" "$(msg)"
t_done
