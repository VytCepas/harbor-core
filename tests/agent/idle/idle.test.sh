#!/usr/bin/env sh
# bin/agent-idle-check.sh (harbor#1437, check agent.idle): a subagent that is running and has written nothing for an hour,
# while its session is alive, is a finding. Measured 2026-11-02: a background agent sat idle 7.5 hours waiting on a run that
# no longer existed. Fixture: a bus, session records and subagent transcripts with set ages; nothing real is read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/agent-idle-check.sh"
BUS="$T_TMP/bus"; STATE="$T_TMP/state"; PROJ="$CLAUDE_CONFIG_DIR/projects/-fixture"
mkdir -p "$BUS" "$STATE/sessions" "$PROJ"
HARBOR_EVENT_DIR="$BUS"; HARBOR_STATUS_DIR="$STATE"; export HARBOR_EVENT_DIR HARBOR_STATUS_DIR
NOW="$(date +%s)"
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
DAY="$BUS/$(date -u +%F).jsonl"; : > "$DAY"
EVN=0
ev() { # <age-s> <kind> <subject> <session-id> — one bus line
  EVN=$((EVN + 1))
  printf '{"id":"x%s","ts":"%s","src":"t","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":{"session_id":"%s"}}\n' "$EVN" "$(iso $((NOW - $1)))" "$2" "$3" "$4" >> "$DAY"
}
S1=11111111-aaaa-bbbb-cccc-000000000001; S2=22222222-aaaa-bbbb-cccc-000000000002; S3=33333333-aaaa-bbbb-cccc-000000000003
for s in $S1 $S2; do printf '{"state":"idle"}\n' > "$STATE/sessions/$s.json"; done    # S3 has no record: gone
transcript() { # <session> <agent> <age-s> — the agent's transcript, last written <age-s> ago
  mkdir -p "$PROJ/$1/subagents"; : > "$PROJ/$1/subagents/agent-$2.jsonl"
  touch -t "$(date -r $((NOW - $3)) +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$((NOW - $3))" +%Y%m%d%H%M.%S)" "$PROJ/$1/subagents/agent-$2.jsonl"
}
RC="$CLAUDE_CONFIG_DIR/cache/checks/agent.idle.json"
run() { sh "$TOOL" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }

t_section "an agent idle for hours in a live session is reported"
ev 27000 agent.spawn aidle00001 $S1; transcript $S1 aidle00001 26000     # the 7.5 h case
ev 27000 agent.spawn adone00001 $S1; ev 26000 agent.done adone00001 $S1; transcript $S1 adone00001 26000   # finished
ev 27000 agent.spawn astop00001 $S2; ev 20000 session.stop $S2 $S2; transcript $S2 astop00001 26000        # its session ended
ev 27000 agent.spawn agone00001 $S3; transcript $S3 agone00001 26000                                       # its session has no record
ev 600 agent.spawn afresh0001 $S1; transcript $S1 afresh0001 120                                            # started minutes ago
ev 27000 agent.spawn abusy00001 $S1; transcript $S1 abusy00001 120                                          # old spawn, written 2 minutes ago
ev 7200 agent.spawn anotr00001 $S1                                                                           # no transcript: spawn time decides
t_eq "one run, exit 1" "exit 1" "$(run)"
t_has "the idle agent is named with its session and minutes" "$(cat "$T_TMP/out")" "agent aidle00001 of session 11111111 is running and has written nothing for 433 minutes"
t_has "an agent with no transcript is judged by its spawn time" "$(cat "$T_TMP/out")" "agent anotr00001 of session 11111111"
for a in adone00001 astop00001 agone00001 afresh0001 abusy00001; do
  t_hasnt "$a is not reported" "$(cat "$T_TMP/out")" "agent $a "
done
t_has "the check id stamps the line" "$(cat "$T_TMP/out")" "[check:agent.idle]"
t_eq "the receipt is red" red "$(jq -r .status "$RC" 2>/dev/null)"
t_has "...its subjects name the session prefix and agent" "$(jq -r '.subjects | join(" ")' "$RC")" "11111111/aidle00001:433m"
t_eq "...two idle agents, not more" 2 "$(jq '.subjects | length' "$RC")"

t_section "it ends when the agent ends"
ev 100 agent.done aidle00001 $S1; ev 100 agent.done anotr00001 $S1
t_eq "no agent left running: exit 0" "exit 0" "$(run)"
t_eq "...and the receipt is green" green "$(jq -r .status "$RC" 2>/dev/null)"

t_section "the limit is the operator's, and --quiet prints no FAIL"
ev 3000 agent.spawn amid000001 $S1; transcript $S1 amid000001 3000     # 50 minutes
t_eq "50 minutes idle is under the default hour" "exit 0" "$(run)"
t_eq "HARBOR_AGENT_IDLE_SECS=1800 makes it idle" "exit 1" "$(HARBOR_AGENT_IDLE_SECS=1800 run)"
t_has "...naming 50 minutes" "$(cat "$T_TMP/out")" "nothing for 50 minutes"
t_eq "--quiet keeps the exit and the receipt" "exit 1" "$(HARBOR_AGENT_IDLE_SECS=1800 run --quiet)"
t_hasnt "...and prints no FAIL line" "$(cat "$T_TMP/out")" "FAIL"
t_eq "--quiet's receipt is red" red "$(jq -r .status "$RC")"
t_eq "a bad option is a usage error" "exit 2" "$(run --nope)"

t_section "read-only"
t_eq "nothing under the bus, the sessions or the projects changed" "" "$(find "$BUS" "$STATE" "$PROJ" -newer "$T_TMP/out" -type f 2>/dev/null | grep -v '\.beat$' | head -3)"
t_eq "an absent bus is green, not a failure" "exit 0" "$(HARBOR_EVENT_DIR="$T_TMP/nobus" run)"
t_done
