#!/usr/bin/env sh
# finished.test.sh (harbor#1050) — work that ends with no <task-notification> carrying a tool-use id and a status: a Monitor's
# expiry notice (task id only), a Monitor that died with its subagent, an agent stopped after a resume, and the age the statusline shows.
# Each case runs against the real script (must print ok) and against the script as it was before this fix (must not): the
# old copy is `git show` of the merge base, so a case that cannot fail on the old code fails the suite.
. "$(dirname "$0")/../../lib/core.sh"; t_init

BIN="$T_ROOT/bin/status-obligations.sh"; KINDS="$T_ROOT/contracts/obligation-kinds.tsv"
W="$T_TMP/w"; EV="$W/ev"; OB="$W/ob"; FIX="$W/fix"; OLD="$T_TMP/old"; MUTD="$T_TMP/mut"
NOW=2026-10-06T02:00:00Z; N=0; D=2026-10-06.jsonl; BAD=""; EMPTY='{}'; P="$FIX/tr/p"
mkdir -p "$OLD" "$MUTD"
for _d in "$OLD" "$MUTD"; do for _l in library-log.sh library-fs.sh event-bus.sh; do ln -sf "$T_ROOT/bin/$_l" "$_d/$_l"; done; done
_base="$(git -C "$T_ROOT" merge-base HEAD origin/main 2>/dev/null)" || _base=""
# A branch that leaves the script alone has the fix at its merge base too: the old copy is then the one before the script's last change.
if [ -n "$_base" ] && git -C "$T_ROOT" diff --quiet "$_base" HEAD -- bin/status-obligations.sh 2>/dev/null; then
  _last="$(git -C "$T_ROOT" log -1 --format=%H HEAD -- bin/status-obligations.sh 2>/dev/null)"; _base="${_last:+$_last^}"
fi
[ -n "$_base" ] && git -C "$T_ROOT" show "$_base:bin/status-obligations.sh" > "$OLD/status-obligations.sh" 2>/dev/null
[ -s "$OLD/status-obligations.sh" ] || t_fail "no merge base to show the old script from"
cat > "$T_TMP/sessions" <<'STUB'
#!/bin/sh
printf '[{"sessionId":"S6","pid":1}]'
STUB
cat > "$T_TMP/claude" <<'STUB'
#!/bin/sh
printf '[]'
STUB
cat > "$T_TMP/gh" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$T_TMP/sessions" "$T_TMP/claude" "$T_TMP/gh"

fresh() { rm -rf "$W"; mkdir -p "$EV" "$OB" "$FIX/sweep" "$P/S6/subagents"; N=0; }
ev() { N=$((N + 1)); printf '{"id":"e%s","ts":"%s","src":"cli","kind":"%s","subject":"%s","repo":"harbor","cause":"","data":%s}\n' "$N" "$1" "$2" "$3" "${4:-$EMPTY}" >> "$EV/$D"; }
rec() { env HARBOR_EVENT_DIR="$EV" HARBOR_OBLIGATION_DIR="$OB" HARBOR_STATUS_OBLIGATION_NOW="$NOW" HARBOR_STATUS_OBLIGATION_KINDS="$KINDS" \
    HARBOR_STATUS_OBLIGATION_GH="$T_TMP/gh" HARBOR_STATUS_OBLIGATION_CLAUDE="$T_TMP/claude" HARBOR_STATUS_OBLIGATION_SESSIONS="$T_TMP/sessions" \
    HARBOR_STATUS_OBLIGATION_HOUSEKEEPING="$FIX/sweep/.helm-sweep.jsonl" HARBOR_STATUS_OBLIGATION_TRANSCRIPTS="$FIX/tr" sh "$1" reconcile >/dev/null 2>&1; }
cur() { jq -r --arg id "$1" '.obligations[] | select(.id == $id) | .state' "$OB/current.json"; }
chk() { [ "$3" = "$2" ] || BAD="$BAD [$1: want '$2', got '$3']"; }
verdict() { printf '%s' "${BAD:-ok}"; BAD=""; }

# A Monitor's own tool_result, as the transcript carries it (<file> <ts> <toolu> <task> <expiry>).
started() { printf '%s\n' "{\"type\":\"user\",\"timestamp\":\"$2.000Z\",\"message\":{\"role\":\"user\",\"content\":[{\"tool_use_id\":\"$3\",\"type\":\"tool_result\",\"content\":\"Monitor started (task $4, expires in $5 unless the source ends first; you get one notice at expiry)\"}]}}" >> "$1"; }
# The expiry notice: a task id, a summary and an event; no tool-use id, no status.
expired() { printf '%s\n' "{\"type\":\"queue-operation\",\"operation\":\"enqueue\",\"timestamp\":\"$2.000Z\",\"content\":\"<task-notification>\\n<task-id>$3</task-id>\\n<summary>Monitor event: \\\"w\\\"</summary>\\n<event>[Monitor expired after 10m with no events delivered. Re-arm it.]</event>\\n</task-notification>\"}" >> "$1"; }
# An agent's own notification: its task id is the agent id, and it carries a tool-use id (the Agent call's) and a status.
agent_note() { printf '%s\n' "{\"type\":\"queue-operation\",\"operation\":\"enqueue\",\"timestamp\":\"$2.000Z\",\"content\":\"<task-notification>\\n<task-id>$3</task-id>\\n<tool-use-id>toolu_call_$3</tool-use-id>\\n<output-file>/o/$3.output</output-file>\\n<status>$4</status>\\n<summary>Agent finished</summary>\\n</task-notification>\"}" >> "$1"; }
mon() { ev 2026-10-05T00:00:00Z tool.background.start "S6:$1" '{"tool":"Monitor"}'; } # an overdue Monitor row (opened 26h ago, 4h deadline)
# Real script: ok. Old script: not ok, or the case proves nothing.
both() { # <section> <case function>
  t_section "$1"; t_eq "the real script" ok "$("$2" "$BIN")"; _o="$("$2" "$OLD/status-obligations.sh")"
  [ "$_o" != ok ] && t_pass || t_fail "$1: the old script passes too, so the case cannot fail"; }
sub() { : > "$P/S6/subagents/agent-$1.jsonl"; } # <agent id>: a subagent transcript
SA="$P/S6/subagents"

case_expiry() { X="$1"; fresh; M="$P/S6.jsonl"; : > "$M"
  mon toolu_E1; mon toolu_E2; mon toolu_E3
  started "$M" 2026-10-05T00:01:00 toolu_E1 tkE1 10m; started "$M" 2026-10-05T00:02:00 toolu_E2 tkE2 30m; started "$M" 2026-10-05T00:03:00 toolu_E3 tkE3 30m
  expired "$M" 2026-10-05T00:11:00 tkE1; expired "$M" 2026-10-05T00:12:00 tkOTHER
  printf '%s\n' '{"type":"user","timestamp":"2026-10-05T00:20:00.000Z","message":{"content":"quoted: \"tool_use_id\":\"toolu_E3\",\"type\":\"tool_result\",\"content\":\"Monitor started (task tkE3, expires in 30m unless"}}' >> "$M"
  rec "$X"
  chk "a Monitor with an expiry notice for its task id closes" closed "$(cur tool.background:S6:toolu_E1)"
  chk "a Monitor with no notice stays overdue" overdue "$(cur tool.background:S6:toolu_E2)"
  chk "a notice for another task id closes nothing" overdue "$(cur tool.background:S6:toolu_E3)"
  chk "the ledger names the transcript" transcript "$(jq -r 'select(.obligation == "tool.background:S6:toolu_E1" and .to == "closed") | .source' "$OB/ledger.jsonl")"; verdict; }
both "a Monitor's expiry notice (task id only) closes its row" case_expiry

case_subagent() { X="$1"; fresh; M="$P/S6.jsonl"; : > "$M"
  for _a in agE agN agR; do sub "$_a"; done
  mon toolu_S1; mon toolu_S2; mon toolu_S3
  started "$SA/agent-agE.jsonl" 2026-10-05T20:00:00 toolu_S1 tks1 9h; started "$SA/agent-agN.jsonl" 2026-10-05T20:00:00 toolu_S2 tks2 9h; started "$SA/agent-agR.jsonl" 2026-10-05T20:00:00 toolu_S3 tks3 9h
  printf '%s\n' '{"type":"assistant","timestamp":"2026-10-05T20:05:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","content":[]}}' >> "$SA/agent-agE.jsonl"
  agent_note "$M" 2026-10-05T20:30:00 agN killed
  printf '%s\n' '{"type":"user","timestamp":"2026-10-05T20:05:00.000Z","message":{"role":"user","content":"tool result"}}' >> "$SA/agent-agR.jsonl"
  agent_note "$M" 2026-10-05T19:00:00 agR completed
  rec "$X"
  chk "a Monitor whose subagent's last record is a finished turn closes" closed "$(cur tool.background:S6:toolu_S1)"
  chk "one whose subagent has a killed notice after the start closes" closed "$(cur tool.background:S6:toolu_S2)"
  chk "a subagent still running, its only notice older than the start: stays" overdue "$(cur tool.background:S6:toolu_S3)"; verdict; }
both "a Monitor started in a subagent closes when the subagent has ended" case_subagent

case_window() { X="$1"; fresh; : > "$P/S6.jsonl"; sub agW
  mon toolu_W1; mon toolu_W2; mon toolu_W3
  started "$SA/agent-agW.jsonl" 2026-10-06T01:00:00 toolu_W1 tkw1 "6m 40s"; started "$SA/agent-agW.jsonl" 2026-10-06T01:30:00 toolu_W2 tkw2 1h; started "$SA/agent-agW.jsonl" 2026-10-06T01:00:00 toolu_W3 tkw3 30m
  rec "$X"
  chk "a Monitor of 6m 40s started an hour ago closes" closed "$(cur tool.background:S6:toolu_W1)"
  chk "a 1h one started 30m ago stays" overdue "$(cur tool.background:S6:toolu_W2)"
  chk "a 30m one started 60m ago closes" closed "$(cur tool.background:S6:toolu_W3)"; verdict; }
both "a subagent's Monitor closes once its stated expiry has passed" case_window

case_agent_killed() { X="$1"; fresh; M="$P/S6.jsonl"; : > "$M"
  ev 2026-10-05T00:00:00Z agent.spawn agK '{"session_id":"S6"}'; ev 2026-10-05T00:00:00Z agent.spawn agL '{"session_id":"S6"}'
  agent_note "$M" 2026-10-05T05:00:00 agK killed; agent_note "$M" 2026-10-05T05:00:00 agOther killed
  rec "$X"
  chk "an agent with a killed notice for its id closes" closed "$(cur agent:agK)"
  chk "an agent with no notice stays" overdue "$(cur agent:agL)"
  chk "the ledger names the transcript" transcript "$(jq -r 'select(.obligation == "agent:agK" and .to == "closed") | .source' "$OB/ledger.jsonl")"; verdict; }
both "an agent stopped with TaskStop closes on a notice for its id" case_agent_killed

# A resumed agent: spawned, done, spawned again. The completed notice before the resume must not close the second life.
case_resumed() { X="$1"; fresh; M="$P/S6.jsonl"; : > "$M"
  ev 2026-10-05T00:00:00Z agent.spawn agR '{"session_id":"S6"}'; ev 2026-10-05T02:00:00Z agent.done agR; ev 2026-10-05T06:00:00Z agent.spawn agR '{"session_id":"S6"}'
  ev 2026-10-05T00:00:00Z agent.spawn agS '{"session_id":"S6"}'; ev 2026-10-05T02:00:00Z agent.done agS; ev 2026-10-05T06:00:00Z agent.spawn agS '{"session_id":"S6"}'
  agent_note "$M" 2026-10-05T02:00:00 agR completed; agent_note "$M" 2026-10-05T02:00:00 agS completed; agent_note "$M" 2026-10-05T06:30:00 agS killed
  rec "$X"
  chk "the resumed row opened at the second spawn" 2026-10-05T06:00:00Z "$(jq -r '.obligations[] | select(.id == "agent:agR") | .opened_ts' "$OB/current.json")"
  chk "an older completed notice never closes the resumed, live agent" overdue "$(cur agent:agR)"
  chk "a later killed notice closes it" closed "$(cur agent:agS)"; verdict; }
t_section "a resumed agent with an older completed notice stays open"
t_eq "the real script" ok "$(case_resumed "$BIN")"
mutate() { awk -v from="$1" -v to="$2" 'BEGIN { RS = "\001" } { i = index($0, from); if (i == 0) exit 3; printf "%s%s%s", substr($0, 1, i - 1), to, substr($0, i + length(from)) }' "$BIN" > "$MUTD/status-obligations.sh" || { t_fail "mutation target not found: $1"; return 1; }; }
if mutate '(.[4][0:19]) > ($r[3][0:19])' '(.[4][0:19]) > ""'; then _o="$(case_resumed "$MUTD/status-obligations.sh")"; [ "$_o" != ok ] && t_pass || t_fail "dropping the opened_ts comparison still passes"; fi

case_rearmed() { X="$1"; fresh; M="$P/S6.jsonl"; : > "$M"
  mon toolu_R1; ev 2026-10-05T00:30:00Z tool.background.start S6:toolu_R2 '{"tool":"Monitor"}'
  started "$M" 2026-10-05T00:01:00 toolu_R1 tkr1 10m; expired "$M" 2026-10-05T00:11:00 tkr1
  started "$M" 2026-10-05T00:31:00 toolu_R2 tkr2 30m
  NOW=2026-10-05T00:40:00Z; rec "$X"; NOW=2026-10-06T02:00:00Z
  chk "the Monitor that expired closes" closed "$(cur tool.background:S6:toolu_R1)"
  chk "the one re-armed under a new task id stays open" open "$(cur tool.background:S6:toolu_R2)"; verdict; }
both "a Monitor re-armed under a new task id: the old row closes, the new one stays" case_rearmed

t_done
