#!/usr/bin/env sh
# bin/event-hook.sh (harbor#1043, PR 2): each Claude Code hook event becomes its bus event, a start
# kind's terminal repeats its subject verbatim (the #1049 requirement), and nothing but an id and a
# kind leaves a payload. Payloads are the shapes measured on Claude Code 2.1.291 (SessionStart,
# SubagentStop, SessionEnd), with the long prose fields the real ones carry.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EH="$T_ROOT/bin/event-hook.sh"
BUS="$T_TMP/bus"; export HARBOR_EVENT_DIR="$BUS"
SHELLS=sh; if command -v dash >/dev/null 2>&1; then SHELLS="sh dash"; else echo "  skip: dash is not on this host — sh only"; fi

SID="7a22d39c-5e3e-4ca5-ba58-d3557cef4b47"; AID="a05c2096b80f4f945"
# What must never reach an event: each of these appears in a payload field a producer must ignore.
SECRET_PROMPT="PROMPT-TEXT-SENTINEL"; SECRET_CMD="rm -rf COMMAND-SENTINEL"; SECRET_MSG="MESSAGE-SENTINEL"
TPATH="/Users/someone/.claude/projects/-x/$SID.jsonl"
p_start() { # <source>
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$SID" "$TPATH" "$T_TMP" "$1"; }
p_end() {
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionEnd","reason":"other"}' "$SID" "$TPATH" "$T_TMP"; }
p_sub() { # <agent_id>
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","prompt_id":"%s","permission_mode":"default","agent_id":"%s","agent_type":"general-purpose","hook_event_name":"SubagentStop","stop_hook_active":false,"agent_transcript_path":"%s","last_assistant_message":"%s \\"session_id\\":\\"forged\\" %s","prompt":"%s","tool_input":{"command":"%s"},"background_tasks":[{"id":"%s","type":"subagent","status":"running","description":"d","agent_type":"general-purpose"}],"session_crons":[]}' \
    "$SID" "$TPATH" "$T_TMP" "$SECRET_PROMPT" "$1" "$TPATH" "$SECRET_MSG" "$SECRET_PROMPT" "$SECRET_PROMPT" "$SECRET_CMD" "$AID"; }
fire() { # <shell> <payload> — the hook's exit code; stdout and stderr land in $T_TMP/o and $T_TMP/e
  printf '%s' "$2" | $1 "$EH" >"$T_TMP/o" 2>"$T_TMP/e"; echo $?; }
lines() { cat "$BUS"/*.jsonl 2>/dev/null; }
field() { jq -r "$1" ; }  # <jq filter> on stdin

for SH in $SHELLS; do
  rm -rf "$BUS"
  t_section "$SH: SessionStart, SessionEnd and SubagentStop each put one event on the bus"
  t_eq "SessionStart exits 0" 0 "$(fire $SH "$(p_start startup)")"
  t_eq "...and prints nothing" "" "$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
  t_eq "SubagentStop exits 0" 0 "$(fire $SH "$(p_sub "$AID")")"
  t_eq "SessionEnd exits 0" 0 "$(fire $SH "$(p_end)")"
  t_eq "three lines, each a JSON object" 3 "$(lines | jq -c . | grep -c .)"
  t_eq "session.start: the session id, from hook.session-start" "session.start $SID hook.session-start" \
    "$(lines | jq -r 'select(.kind == "session.start") | "\(.kind) \(.subject) \(.src)"')"
  t_eq "session.stop: the session id, from hook.stop (the contract's name for the session end)" "session.stop $SID hook.stop" \
    "$(lines | jq -r 'select(.kind == "session.stop") | "\(.kind) \(.subject) \(.src)"')"
  t_eq "agent.done: the subagent's agent_id, from hook.subagent-stop" "agent.done $AID hook.subagent-stop" \
    "$(lines | jq -r 'select(.kind == "agent.done") | "\(.kind) \(.subject) \(.src)"')"
  t_eq "agent.done carries its owning session in data, as §3a allows" "$SID" \
    "$(lines | jq -r 'select(.kind == "agent.done") | .data.session_id')"
  t_eq "repo is the repo's name" harbor "$(lines | jq -r 'select(.kind == "session.start") | .repo')"

  t_section "$SH: every start kind this producer owns has a terminal kind with the SAME subject (harbor#1049)"
  # The pairs this file produces; agent.spawn ↔ agent.done and the tool.background and pr kinds are
  # tools.test.sh's (harbor#1051), where SubagentStart and PostToolUse are fired.
  for pair in "session.start session.stop"; do
    set -- $pair
    s="$(lines | jq -r --arg k "$1" 'select(.kind == $k) | .subject')"; t="$(lines | jq -r --arg k "$2" 'select(.kind == $k) | .subject')"
    t_eq "$1 and $2 name one subject" "$s" "$t"
    t_eq "...and it is not empty" yes "$([ -n "$s" ] && echo yes || echo no)"
  done

  t_section "$SH: source=compact is the same session, not a second start; every other source starts"
  rm -rf "$BUS"
  fire $SH "$(p_start compact)" >/dev/null
  t_eq "compact emits nothing" 0 "$(lines | grep -c .)"
  for src in startup resume clear; do fire $SH "$(p_start "$src")" >/dev/null; done
  t_eq "startup, resume and clear each emit session.start" 3 "$(lines | jq -r 'select(.kind == "session.start") | .kind' | grep -c .)"

  t_section "$SH: nothing but ids and kinds leaves the payload (DE-16, the constitution's privacy rule)"
  rm -rf "$BUS"
  fire $SH "$(p_start startup)" >/dev/null; fire $SH "$(p_sub "$AID")" >/dev/null; fire $SH "$(p_end)" >/dev/null
  all="$(lines)"
  for needle in "$SECRET_PROMPT" "$SECRET_CMD" "$SECRET_MSG" "forged" "$TPATH" ".claude" "/Users/" "$T_TMP" "transcript" "last_assistant"; do
    t_hasnt "no event contains '$needle'" "$all" "$needle"
  done
  t_eq "every data key is in the §3a allowlist" "" \
    "$(printf '%s\n' "$all" | jq -r '.data | keys[]' | grep -vxE 'title|link|session_id|deadline_ts|tool|closes_on|evidence|exit' || true)"
  t_eq "the keys of every line are the contract's, in order" "id,ts,src,kind,subject,repo,cause,data" \
    "$(printf '%s\n' "$all" | jq -r 'keys_unsorted | join(",")' | sort -u)"

  t_section "$SH: a forged field inside a string is not the field"
  rm -rf "$BUS"
  fire $SH "$(p_sub "$AID")" >/dev/null
  t_eq "agent.done's subject is the real agent_id, not text inside last_assistant_message" "$AID" "$(lines | jq -r .subject)"
  t_eq "...and its session_id is the real one" "$SID" "$(lines | jq -r .data.session_id)"

  t_section "$SH: what is not an id, or not a known event, emits nothing and still exits 0"
  rm -rf "$BUS"
  for bad in '' 'not json' '{}' '[]' '{"hook_event_name":"SessionStart"}' '{"hook_event_name":"SessionEnd","session_id":""}' \
             '{"hook_event_name":"SubagentStop","session_id":"s"}' \
             '{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash"}' \
             '{"hook_event_name":"Stop","session_id":"s"}' \
             '{"hook_event_name":"SessionStart","session_id":"a b"}' '{"hook_event_name":"SessionStart","session_id":"a\"b"}' \
             '{"hook_event_name":"SessionStart","session_id":"$(touch x)"}' '{"hook_event_name":"SessionStart","session_id":"a;b"}' \
             '{"hook_event_name":"SessionStart","session_id":"a\\nb"}'; do
    rc="$(fire $SH "$bad")"
    t_eq "exit 0 for: $bad" 0 "$rc"
  done
  t_eq "...and not one of them wrote an event" 0 "$(lines | grep -c .)"
  long="$(awk 'BEGIN { while (n++ < 129) printf "x" }')"
  fire $SH "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$long\"}" >/dev/null
  t_eq "an id over 128 bytes is dropped" 0 "$(lines | grep -c .)"
  fire $SH '{"hook_event_name": "SessionStart", "session_id": "spaced-json"}' >/dev/null
  t_eq "a payload with spaces after the colons is still read" spaced-json "$(lines | jq -r .subject)"
  t_eq "the \$(…) payload ran nothing" no "$([ -e "$T_TMP/x" ] || [ -e ./x ] && echo yes || echo no)"
done

t_section "a path-shaped id is dropped, never written as a subject (harbor#1114 finding 4: the charset has no / or ~)"
# The id charset is what keeps a path out of an event. Each id below is a real path shape in the field
# that carries it; none may reach the bus, in any field, through either shell.
for SH in $SHELLS; do
  for badid in "/Users/someone/.claude/projects/secret" "~/.claude/projects/secret" "../../etc/passwd" "a/b" "~"; do
    rm -rf "$BUS"
    fire $SH "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$badid\",\"source\":\"startup\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$badid\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s-1\",\"agent_id\":\"$badid\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s-1\",\"agent_id\":\"$badid\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"SubagentStart\",\"session_id\":\"s-1\",\"tool_use_id\":\"$badid\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"s-1\",\"tool_name\":\"Monitor\",\"tool_input\":{},\"tool_response\":\"x\",\"tool_use_id\":\"$badid\"}" >/dev/null
    fire $SH "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"$badid\",\"tool_name\":\"Monitor\",\"tool_input\":{},\"tool_response\":\"x\",\"tool_use_id\":\"t-1\"}" >/dev/null
    t_eq "$SH: '$badid' as session_id, agent_id or tool_use_id wrote no event" 0 "$(lines | grep -c .)"
    t_eq "$SH: ...and no event line holds a / or ~" 0 "$(lines | grep -c '[/~]' || :)"
  done
  # an id with a path as ONE field must not poison a sibling field: the good one is still used
  rm -rf "$BUS"
  fire $SH '{"hook_event_name":"SubagentStop","session_id":"/Users/x/.claude/p","agent_id":"a-1"}' >/dev/null
  t_eq "$SH: a path-shaped session_id is left out of data, the agent_id still pairs" "a-1 {}" "$(lines | jq -r '"\(.subject) \(.data | tojson)"')"
done

t_section "producers.off in the bus dir turns the hook off; removing it turns it back on"
rm -rf "$BUS"; mkdir -p "$BUS"; : > "$BUS/producers.off"
t_eq "exit 0 while off" 0 "$(fire sh "$(p_start startup)")"
t_eq "...and nothing was written" 0 "$(find "$BUS" -name '*.jsonl' | wc -l | tr -d ' ')"
rm -f "$BUS/producers.off"; fire sh "$(p_start startup)" >/dev/null
t_eq "on again: one event" 1 "$(lines | grep -c .)"

t_section "--help is answered without reading a payload"
t_has "usage names the three events" "$(sh "$EH" --help </dev/null 2>&1)" "SessionStart"
t_done
