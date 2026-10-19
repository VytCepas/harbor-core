#!/usr/bin/env sh
# bin/event-hook.sh, the tool and agent producers (harbor#1051 PR 1): SubagentStart → agent.spawn,
# PostToolUse → tool.background.start and pr.opened. Payload shapes are the ones in Claude Code's hook
# reference (2.1.291): session_id, hook_event_name, tool_name, tool_input, tool_response, tool_use_id,
# the last after the response. What must hold: each producer emits its event with the contract's subject,
# nothing but a §3a key and an id leaves a payload (command text, prompts, tool output, a URL written in
# the command), a start's subject pairs with its terminal's, and a hung bus or a stdin that never closes
# cannot hold the hook past its bound.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EH="$T_ROOT/bin/event-hook.sh"
BUS="$T_TMP/bus"; export HARBOR_EVENT_DIR="$BUS"
SHELLS=sh; if command -v dash >/dev/null 2>&1; then SHELLS="sh dash"; else echo "  skip: dash is not on this host — sh only"; fi

SID="7a22d39c-5e3e-4ca5-ba58-d3557cef4b47"; AID="a05c2096b80f4f945"; TU="toolu_01ABCdefGHIjklMNOpqrSTU"
SECRET_CMD="COMMAND-SENTINEL"; SECRET_OUT="OUTPUT-SENTINEL"; SECRET_PROMPT="PROMPT-SENTINEL"
TPATH="/Users/someone/.claude/projects/-x/$SID.jsonl"
post() { # <tool> <tool_input json> <tool_response json> [tool_use_id] — a PostToolUse payload, real key order
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","permission_mode":"default","hook_event_name":"PostToolUse","tool_name":"%s","tool_input":%s,"tool_response":%s,"tool_use_id":"%s","duration_ms":12}' \
    "$SID" "$TPATH" "$T_TMP" "$1" "$2" "$3" "${4-$TU}"; }
sub_start() { # [agent_id]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SubagentStart","agent_id":"%s","agent_type":"Explore","prompt":"%s"}' \
    "$SID" "$TPATH" "$T_TMP" "${1-$AID}" "$SECRET_PROMPT"; }
sub_stop() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SubagentStop","agent_id":"%s","agent_type":"Explore","last_assistant_message":"%s"}' "$SID" "$T_TMP" "$AID" "$SECRET_OUT"; }
fire() { # <shell> <payload> → exit code
  printf '%s' "$2" | $1 "$EH" >"$T_TMP/o" 2>"$T_TMP/e"; echo $?; }
lines() { cat "$BUS"/*.jsonl 2>/dev/null; }
one() { lines | jq -r "select(.kind == \"$1\") | $2"; }  # <kind> <jq expr>
count() { lines | grep -c . || :; }

BG_IN="{\"command\":\"sleep 3; echo $SECRET_CMD\",\"description\":\"d\",\"run_in_background\":true}"
FG_IN="{\"command\":\"echo $SECRET_CMD\",\"run_in_background\":false}"
OUT="{\"stdout\":\"$SECRET_OUT\\n\",\"stderr\":\"\",\"interrupted\":false}"
PR_IN="{\"command\":\"gh pr create --title t --body \\\"$SECRET_CMD\\\"\",\"description\":\"open the PR\"}"
PR_OUT="{\"stdout\":\"Creating pull request for b into main in VytCepas/harbor\\n\\nhttps://github.com/VytCepas/harbor/pull/1234\\n\",\"stderr\":\"\",\"interrupted\":false}"

for SH in $SHELLS; do
  rm -rf "$BUS"
  t_section "$SH: SubagentStart puts agent.spawn on the bus, its subject the agent_id that agent.done will carry"
  t_eq "SubagentStart exits 0" 0 "$(fire $SH "$(sub_start)")"
  t_eq "...and prints nothing" "" "$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
  t_eq "agent.spawn: agent_id subject, from hook.subagent-start" "agent.spawn $AID hook.subagent-start" "$(one agent.spawn '"\(.kind) \(.subject) \(.src)"')"
  t_eq "...carrying its owning session, as §3a allows" "$SID" "$(one agent.spawn .data.session_id)"
  fire $SH "$(sub_stop)" >/dev/null
  t_eq "agent.spawn and agent.done name one subject" "$(one agent.spawn .subject)" "$(one agent.done .subject)"
  rm -rf "$BUS"
  fire $SH '{"session_id":"s-1","hook_event_name":"SubagentStart","tool_use_id":"tu-9"}' >/dev/null
  t_eq "no agent_id: the spawning call's <session_id>:<tool_use_id>" "s-1:tu-9" "$(one agent.spawn .subject)"
  rm -rf "$BUS"
  fire $SH '{"session_id":"s-1","hook_event_name":"SubagentStart"}' >/dev/null
  t_eq "no agent_id and no tool_use_id: nothing is emitted" 0 "$(count)"

  t_section "$SH: PostToolUse starts a background row for Monitor, ScheduleWakeup, CronCreate, Workflow and background Bash"
  for tool in Monitor ScheduleWakeup CronCreate Workflow; do
    rm -rf "$BUS"
    t_eq "$tool exits 0" 0 "$(fire $SH "$(post $tool "{\"command\":\"$SECRET_CMD\",\"prompt\":\"$SECRET_PROMPT\"}" "\"$SECRET_OUT\"")")"
    t_eq "$tool: one tool.background.start, subject <session_id>:<tool_use_id>, data.tool and data.session_id" \
      "1 $SID:$TU hook.post-tool-use $tool $SID" \
      "$(count) $(one tool.background.start '"\(.subject) \(.src) \(.data.tool) \(.data.session_id)"')"
  done
  rm -rf "$BUS"; fire $SH "$(post Bash "$BG_IN" "$OUT")" >/dev/null
  t_eq "Bash with run_in_background:true: one start, data.tool Bash" "1 $SID:$TU Bash" \
    "$(count) $(one tool.background.start '"\(.subject) \(.data.tool)"')"
  t_eq "...and that row's data is exactly the two keys" "session_id,tool" "$(one tool.background.start '.data | keys_unsorted | join(",")')"
  rm -rf "$BUS"; fire $SH "$(post ScheduleWakeup '{"stop":true}' '"cancelled"')" >/dev/null
  t_eq "ScheduleWakeup with stop:true cancels a wakeup, it opens nothing" 0 "$(count)"

  t_section "$SH: PostToolUse opens a PR row from the tool RESULT's URL"
  rm -rf "$BUS"; t_eq "gh pr create exits 0" 0 "$(fire $SH "$(post Bash "$PR_IN" "$PR_OUT")")"
  t_eq "pr.opened: owner/repo#n subject, hook.post-tool-use" "1 VytCepas/harbor#1234 hook.post-tool-use" \
    "$(count) $(one pr.opened '"\(.subject) \(.src)"')"
  t_eq "data.link is the https URL and data.session_id the owner" "https://github.com/VytCepas/harbor/pull/1234 $SID" \
    "$(one pr.opened '"\(.data.link) \(.data.session_id)"')"
  t_eq "the row's repo is the PR's repo" harbor "$(one pr.opened .repo)"
  t_eq "...and its data is exactly link and session_id" "session_id,link" "$(one pr.opened '.data | keys_unsorted | join(",")')"
  rm -rf "$BUS"
  fire $SH "$(post Bash '{"command":"cd x && gh -R o/r pr create --fill"}' '{"stdout":"https://github.com/o/r/pull/7\n"}')" >/dev/null
  t_eq "gh pr create behind a cd and with -R still counts" "o/r#7" "$(one pr.opened .subject)"
  rm -rf "$BUS"
  fire $SH "$(post Bash "$PR_IN" '{"stdout":"warning: https://github.com/a/b/pull/1 is old\nhttps://github.com/c/d/pull/2\n"}')" >/dev/null
  t_eq "several URLs in the result: the one on the last line, which is what gh prints" "c/d#2" "$(one pr.opened .subject)"
  rm -rf "$BUS"
  fire $SH "$(post Bash "$PR_IN" '{"stdout":"https://github.com/c/d/pull/2\nsee also https://github.com/a/b/pull/1 for context\n"}')" >/dev/null
  t_eq "a URL inside a sentence on the last line is not the PR (no event)" 0 "$(count)"

  t_section "$SH: skill calls and memory-note reads (harbor#1181 lane 7)"
  rm -rf "$BUS"; fire $SH "$(post Skill '{"skill":"artifact-design","args":"PROMPT-SENTINEL"}' '"ok"')" >/dev/null
  t_eq "a skill call is one skill.call, subject the skill name" "skill.call artifact-design $SID" "$(one skill.call '"\(.kind) \(.subject) \(.data.session_id)"')"
  t_eq "its arguments never reach the bus" 0 "$(lines | grep -c PROMPT-SENTINEL)"
  rm -rf "$BUS"; fire $SH "$(post Read '{"file_path":"/Users/someone/.claude/projects/-x/memory/never-poll-harness-tracked-work.md"}' '"OUTPUT-SENTINEL"')" >/dev/null
  t_eq "a Read of a memory note is one memory.read, subject its basename" never-poll-harness-tracked-work.md "$(one memory.read .subject)"
  t_eq "no path, no user and no content reach the bus" 0 "$(lines | grep -c -E 'someone|/memory/|OUTPUT-SENTINEL')"
  rm -rf "$BUS"; fire $SH "$(post Read '{"file_path":"/Users/someone/.claude/projects/-x/memory/MEMORY.md"}' '"c"')" >/dev/null
  t_eq "the memory index counts as a memory read" MEMORY.md "$(one memory.read .subject)"
  rm -rf "$BUS"; fire $SH "$(post Read '{"file_path":"/Users/someone/port/harbor/README.md"}' '"c"')" >/dev/null
  t_eq "any other Read writes nothing" 0 "$(count)"
  rm -rf "$BUS"; fire $SH "$(post Read '{"file_path":"/x/memory/bad name;rm.md"}' '"c"')" >/dev/null
  t_eq "a basename outside the id charset is dropped, never written" 0 "$(count)"

  t_section "$SH: a pr.opened cannot be forged, and a real one is not missed (harbor#1114 findings 1 and 2)"
  # Each forge is a payload where a PR URL sits in the result but gh pr create did not print it as its
  # last line. Every one must write NOTHING; every true positive below must write exactly one event.
  forge() { # <label> <tool_input json> <tool_response json>
    rm -rf "$BUS"; fire $SH "$(post Bash "$2" "$3")" >/dev/null
    t_eq "no pr.opened: $1" 0 "$(count)"; }
  OLD_URL='{"stdout":"docs/a.md:3: gh pr create\nhttps://github.com/other-org/other-repo/pull/42\n"}'
  forge "a grep that names gh pr create, an old URL in its output" \
    '{"command":"grep -rn \"gh pr create\" docs/"}' "$OLD_URL"
  forge "gh pr view -R, whose description says gh pr create" \
    '{"command":"gh pr view -R someone/else 7","description":"gh pr create"}' '{"stdout":"https://github.com/someone/else/pull/7\n"}'
  forge "gh pr create followed by cat of a file that ends in a URL" \
    '{"command":"gh pr create --fill && cat notes.txt"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create followed by a pipe" \
    '{"command":"gh pr create --fill | cat notes.txt"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create followed by a semicolon command" \
    '{"command":"gh pr create --fill; cat notes.txt"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create followed by a newline command" \
    '{"command":"gh pr create --fill\ncat notes.txt"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create inside an echoed string" \
    '{"command":"echo \"x; gh pr create\""}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create inside single quotes" \
    '{"command":"echo '"'"'a && gh pr create'"'"'"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh pr create only in the description key" \
    '{"command":"echo hi","description":"gh pr create"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "gh says the PR already exists (stdout)" \
    '{"command":"gh pr create --fill"}' '{"stdout":"a pull request for branch b into branch main already exists:\nhttps://github.com/VytCepas/harbor/pull/1000\n"}'
  forge "gh says the PR already exists (stderr), URL in stdout" \
    '{"command":"gh pr create --fill"}' '{"stdout":"https://github.com/VytCepas/harbor/pull/1000\n","stderr":"a pull request already exists"}'
  forge "a tool_input key whose name is not command" \
    '{"cmd":"gh pr create --fill"}' '{"stdout":"https://github.com/evil/x/pull/1\n"}'
  forge "a forged stdout key written inside the command" \
    '{"command":"echo \"stdout\":\"https://github.com/evil/x/pull/1\\n\" && gh pr create"}' '{"stdout":"nothing here\n"}'

  true_pr() { # <label> <expected subject> <tool_input json> <stdout json value>
    rm -rf "$BUS"; fire $SH "$(post Bash "$3" "{\"stdout\":\"$4\"}")" >/dev/null
    t_eq "pr.opened: $1" "1 $2" "$(count) $(one pr.opened .subject)"; }
  URL1="https://github.com/VytCepas/harbor/pull/1234"
  true_pr "a plain gh pr create" VytCepas/harbor#1234 '{"command":"gh pr create --fill"}' "Creating pull request\\n\\n$URL1\\n"
  true_pr "a multi-line command, gh pr create on its own line (the JSON newline escape)" VytCepas/harbor#1234 \
    '{"command":"git push -u origin b\ngh pr create --fill"}' "$URL1\\n"
  true_pr "gh pr create after &&" VytCepas/harbor#1234 '{"command":"git push -u origin b && gh pr create --fill"}' "$URL1\\n"
  true_pr "gh pr create after ; and with 2>&1" VytCepas/harbor#1234 '{"command":"cd x; gh pr create --fill 2>&1"}' "$URL1\\n"
  true_pr "a heredoc body with quotes, apostrophes, && and newlines inside the double quotes" VytCepas/harbor#1234 \
    '{"command":"gh pr create --title \"fix: it'"'"'s done\" --body \"$(cat <<'"'"'EOF'"'"'\n## Summary\n- a && b; c | d\nEOF\n)\""}' "$URL1\\n"
  true_pr "a CRLF-terminated last line" VytCepas/harbor#1234 '{"command":"gh pr create --fill"}' "$URL1\\r\\n"

  t_section "$SH: what is not a producer's tool or result emits nothing (and exits 0)"
  rm -rf "$BUS"
  for case in \
    "Bash fg|$(post Bash "$FG_IN" "$OUT")" \
    "Read|$(post Read '{"file_path":"/x"}' '"c"')" \
    "Edit|$(post Edit '{"file_path":"/x","old_string":"a","new_string":"b"}' '{}')" \
    "Task with a background-looking input|$(post Task '{"run_in_background":true}' '{}')" \
    "mcp tool|$(post mcp__x__y '{"run_in_background":true}' '"o"')" \
    "gh pr create, no URL in the result|$(post Bash "$PR_IN" '{"stdout":"nothing to see\n"}')" \
    "a PR URL in the result of a command that is not gh pr create|$(post Bash '{"command":"gh pr view 5"}' '{"stdout":"https://github.com/o/r/pull/5\n"}')" \
    "gh pr create with the URL only in the command|$(post Bash '{"command":"gh pr create --body https://github.com/e/e/pull/9"}' '{"stdout":"x"}')" \
    "a non-github host|$(post Bash "$PR_IN" '{"stdout":"https://evil.example/o/r/pull/3\n"}')" \
    "an http (not https) URL|$(post Bash "$PR_IN" '{"stdout":"http://github.com/o/r/pull/3\n"}')" \
    "no tool_use_id|$(printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Monitor","tool_input":{},"tool_response":"x"}' "$SID")" \
    "no session_id|$(printf '{"hook_event_name":"PostToolUse","tool_name":"Monitor","tool_input":{},"tool_response":"x","tool_use_id":"t"}')" \
    "run_in_background:true as a real key in the RESULT of a foreground call|$(post Bash "$FG_IN" '{"stdout":"x","meta":{"run_in_background":true}}')" \
    "gh pr create written in the OUTPUT of another command, beside a PR URL|$(post Bash '{"command":"cat notes.md"}' '{"stdout":"run gh pr create then see https://github.com/o/r/pull/5\n"}')" \
    "a forged run_in_background inside the command string|$(post Bash '{"command":"echo \"run_in_background\":true"}' "$OUT")" \
    "an unsafe tool_use_id|$(post Monitor '{}' '"x"' 'a;b')" \
    "an over-long tool_use_id|$(post Monitor '{}' '"x"' "$(awk 'BEGIN { while (n++ < 129) printf "x" }')")"; do
    rc="$(fire $SH "${case#*|}")"
    t_eq "exit 0 for: ${case%%|*}" 0 "$rc"
  done
  t_eq "...and not one of them wrote an event" 0 "$(count)"

  t_section "$SH: nothing but a session id, a call id and a link leaves the payload (DE-16, the constitution's privacy rule)"
  rm -rf "$BUS"
  fire $SH "$(post Bash "$PR_IN" "$PR_OUT")" >/dev/null; fire $SH "$(post Bash "$BG_IN" "$OUT")" >/dev/null
  fire $SH "$(post Monitor "{\"command\":\"$SECRET_CMD\"}" "\"$SECRET_OUT\"")" >/dev/null; fire $SH "$(sub_start)" >/dev/null
  all="$(lines)"
  t_eq "four events were written" 4 "$(count)"
  for needle in "$SECRET_CMD" "$SECRET_OUT" "$SECRET_PROMPT" "gh pr create" "open the PR" "$TPATH" ".claude" "/Users/" "$T_TMP" "transcript" "stdout" "description"; do
    t_hasnt "no event contains '$needle'" "$all" "$needle"
  done
  t_eq "every data key is in the §3a allowlist" "" \
    "$(printf '%s\n' "$all" | jq -r '.data | keys[]' | grep -vxE 'title|link|session_id|deadline_ts|tool|closes_on|evidence|exit' || true)"
  t_eq "every data.link is https" "" "$(printf '%s\n' "$all" | jq -r '.data.link // empty' | grep -v '^https://' || true)"
  t_eq "the keys of every line are the contract's, in order" "id,ts,src,kind,subject,repo,cause,data" \
    "$(printf '%s\n' "$all" | jq -r 'keys_unsorted | join(",")' | sort -u)"

  t_section "$SH: a field forged inside a string, or nested in the tool's own objects, is not the field"
  rm -rf "$BUS"
  fire $SH "$(post Monitor '{"command":"x \"tool_use_id\":\"forged-in-cmd\" \"session_id\":\"forged-sid\""}' \
    '{"nested":{"tool_use_id":"forged-nested","session_id":"forged-nested-sid"},"text":"\"tool_use_id\":\"forged-in-text\""}')" >/dev/null
  t_eq "the subject is the real <session_id>:<tool_use_id>" "$SID:$TU" "$(one tool.background.start .subject)"
  rm -rf "$BUS"
  fire $SH "$(post Bash '{"command":"gh pr create --title \"tool_response\": https://github.com/f/f/pull/8"}' "$PR_OUT")" >/dev/null
  t_eq "a pull URL in the command is not the PR, a key written in it is not the response" "VytCepas/harbor#1234" "$(one pr.opened .subject)"

  t_section "$SH: a start kind's terminal repeats its subject; tool.background has no terminal producer"
  # Claude Code has no hook for a background tool's completion (the hook reference lists none), so the
  # row's terminal is the reconciler's or the session's. What is asserted is the half that exists: no
  # producer here invents a tool.background.done or pr.merged out of a hook it does not get.
  rm -rf "$BUS"
  fire $SH "$(sub_start)" >/dev/null; fire $SH "$(post Monitor '{}' '"x"')" >/dev/null; fire $SH "$(post Bash "$PR_IN" "$PR_OUT")" >/dev/null
  fire $SH "$(sub_stop)" >/dev/null
  t_eq "agent.spawn and agent.done: one subject, non-empty" "$AID $AID" "$(one agent.spawn .subject) $(one agent.done .subject)"
  t_eq "no tool.background.done, pr.merged or pr.closed was produced" 0 "$(lines | jq -r .kind | grep -cE '^(tool\.background\.done|pr\.merged|pr\.closed)$' || :)"
  t_eq "the background start's subject has the <session_id>:<tool_use_id> shape a terminal would repeat" "yes" \
    "$(one tool.background.start .subject | grep -qE '^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$' && echo yes || echo no)"
done

t_section "producers.off silences the tool producers too"
rm -rf "$BUS"; mkdir -p "$BUS"; : > "$BUS/producers.off"
fire sh "$(post Monitor '{}' '"x"')" >/dev/null; fire sh "$(sub_start)" >/dev/null
t_eq "nothing written while off" 0 "$(find "$BUS" -name '*.jsonl' | wc -l | tr -d ' ')"
rm -rf "$BUS"   # a producers.off left here would make every hang case below pass without running the bus

# ── THE BOUND (§3a.9) ─────────────────────────────────────────────────────────
# A watchdog around every wait: killed at 15 s (RC 143) if the hook itself ever hangs; elapsed in ms.
now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000'; }
bounded() { # <stdin file | -> <cmd…> → RC and ELAPSED (ms); stdout and stderr in $T_TMP/o and $T_TMP/e
  _in="$1"; shift; _t0="$(now_ms)"
  if [ "$_in" = - ]; then "$@" <&- >"$T_TMP/o" 2>"$T_TMP/e" & _p=$!; else "$@" <"$_in" >"$T_TMP/o" 2>"$T_TMP/e" & _p=$!; fi
  # Polls, never signals: a TERM to this subshell is swallowed if it lands before the subshell has its own
  # trap, because core.sh traps TERM in the parent and the fork inherits that (flaked as a 15 s wait at P=24).
  ( _n=0; while [ "$_n" -lt 150 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.1; _n=$((_n + 1)); done; [ "$_n" -lt 150 ] || kill "$_p" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$_p"; RC=$?
  ELAPSED=$(( $(now_ms) - _t0 )); return 0
}
HANG="$T_TMP/hang"; mkdir -p "$HANG/bin"; cp "$EH" "$HANG/bin/"
UNIQ="7$$"
# a bus that never returns, with a child that outlives it; it leaves a marker so a case that never reached it is red
printf '#!/bin/sh\n: >> "%s/reached"\nsleep %s\n' "$T_TMP" "$UNIQ" > "$HANG/bin/event-bus.sh"
printf '%s' "$(post Monitor '{}' '"x"')" > "$T_TMP/in.mon"; printf '%s' "$(post Bash "$PR_IN" "$PR_OUT")" > "$T_TMP/in.pr"
printf '%s' "$(sub_start)" > "$T_TMP/in.sub"

t_section "a hung event-bus.sh cannot hold the hook past its bound"
for f in mon pr sub; do
  rm -f "$T_TMP/reached"
  bounded "$T_TMP/in.$f" env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$HANG/bin/event-hook.sh"
  t_eq "$f: exit 0, nothing printed" "0" "$RC$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
  t_eq "$f: the hung bus was actually reached" yes "$([ -e "$T_TMP/reached" ] && echo yes || echo no)"
  t_eq "$f: back within 1 s bound + 1.5 s of slack (took $ELAPSED ms)" yes "$([ "$ELAPSED" -lt 2500 ] && echo yes || echo no)"
done
t_eq "the stub bus's child was killed with it, none left sleeping" 0 "$(pgrep -f "sleep $UNIQ" 2>/dev/null | wc -l | tr -d ' ')"
bounded "$T_TMP/in.mon" env HARBOR_EVENT_BUS_TIMEOUT=bogus sh "$HANG/bin/event-hook.sh"
t_eq "a junk HARBOR_EVENT_BUS_TIMEOUT falls back to the default (2 s): exit 0, back in under 5 s (took $ELAPSED ms)" "0 yes" \
  "$RC $([ "$ELAPSED" -lt 5000 ] && echo yes || echo no)"
pkill -f "sleep $UNIQ" 2>/dev/null || :

t_section "a double-forked child of a hung bus is killed with it (harbor#1114 finding 5: the process group, not just direct children)"
# `(cmd &)` reparents cmd to init, so it is nobody's child: only a group kill reaches it. Needs perl, which
# the hook uses to make the bus a group leader; where perl is absent the limit is documented (events.md).
UNIQ2="8$$"
if command -v perl >/dev/null 2>&1; then
  printf '#!/bin/sh\n: >> "%s/reached"\n(sleep %s &)\nsleep %s\n' "$T_TMP" "$UNIQ2" "$UNIQ" > "$HANG/bin/event-bus.sh"
  rm -f "$T_TMP/reached"
  bounded "$T_TMP/in.mon" env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$HANG/bin/event-hook.sh"
  t_eq "the hook returned 0 and the hung bus was reached (took $ELAPSED ms)" "0 yes" "$RC $([ -e "$T_TMP/reached" ] && echo yes || echo no)"
  sleep 0.3
  t_eq "the double-forked child of the bus is gone" 0 "$(pgrep -f "sleep $UNIQ2" 2>/dev/null | wc -l | tr -d ' ')"
  t_eq "...and the bus's own child is gone" 0 "$(pgrep -f "sleep $UNIQ" 2>/dev/null | wc -l | tr -d ' ')"
  pkill -f "sleep $UNIQ2" 2>/dev/null || :; pkill -f "sleep $UNIQ" 2>/dev/null || :
else echo "  skip: no perl on this host, so the bus runs ungrouped (the documented limit)"; fi

t_section "a stdin that is closed or never closes cannot hold the hook"
bounded - env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$EH"
t_eq "closed stdin: exit 0, nothing printed (took $ELAPSED ms)" "0" "$RC$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
# 5 s, as for the junk-timeout case: 2.5 s read red twice on a loaded CI pool (P=24), never on a hang.
t_eq "...and back well before the 15 s kill (took $ELAPSED ms)" yes "$([ "$ELAPSED" -lt 5000 ] && echo yes || echo no)"
_t0="$(now_ms)"
# rc is written by the hook's side of the pipe: the pipeline itself only ends when its `sleep` does.
rm -f "$T_TMP/rc"
( sleep "11.$$" | { env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$EH" >"$T_TMP/o" 2>"$T_TMP/e"; echo $? > "$T_TMP/rc"; } ) &
_w=$!; while [ ! -s "$T_TMP/rc" ] && [ "$(( $(now_ms) - _t0 ))" -lt 9000 ]; do sleep 0.1; done
ELAPSED=$(( $(now_ms) - _t0 )); RC="$(cat "$T_TMP/rc" 2>/dev/null || echo running)"
t_eq "an open stdin nothing writes to: the hook exits 0 within 2 s bound + 1.5 s slack (took $ELAPSED ms)" "0 yes" \
  "$RC $([ "$ELAPSED" -lt 3500 ] && echo yes || echo no)"
t_eq "...and printed nothing" "" "$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
kill "$_w" 2>/dev/null; pkill -f "sleep 11.$$" 2>/dev/null || :   # pid-unique pattern: never another session's sleep

t_section "the git hooks are bounded the same way (hooks/lib.sh hook_event)"
R="$T_TMP/g/repo"; mkdir -p "$R" "$T_TMP/g/hooks" "$T_TMP/g/bin"; git -C "$R" init -q
printf x > "$R/f"; git -C "$R" add f; git -C "$R" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false commit -q -m m
cp "$T_ROOT/hooks/post-commit" "$T_ROOT/hooks/lib.sh" "$T_TMP/g/hooks/"; printf '#!/bin/sh\n: >> "%s/reached"\nsleep %s\n' "$T_TMP" "$UNIQ" > "$T_TMP/g/bin/event-bus.sh"
rm -f "$T_TMP/reached"
(cd "$R" && bounded /dev/null env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$T_TMP/g/hooks/post-commit"; echo "$RC $ELAPSED" > "$T_TMP/rc")
read -r RC ELAPSED < "$T_TMP/rc"
t_eq "post-commit with a hung bus: exit 0 (took $ELAPSED ms)" 0 "$RC"
t_eq "...and nothing printed" "" "$(cat "$T_TMP/o")$(cat "$T_TMP/e")"
t_eq "...and the hung bus was actually reached" yes "$([ -e "$T_TMP/reached" ] && echo yes || echo no)"
t_eq "...back within 1 s bound + 1.5 s of slack" yes "$([ "$ELAPSED" -lt 2500 ] && echo yes || echo no)"
pkill -f "sleep $UNIQ" 2>/dev/null || :

if command -v perl >/dev/null 2>&1; then
  printf '#!/bin/sh\n: >> "%s/reached"\n(sleep %s &)\nsleep %s\n' "$T_TMP" "$UNIQ2" "$UNIQ" > "$T_TMP/g/bin/event-bus.sh"
  (cd "$R" && bounded /dev/null env HARBOR_EVENT_BUS_TIMEOUT=1 sh "$T_TMP/g/hooks/post-commit"; echo "$RC $ELAPSED" > "$T_TMP/rc")
  read -r RC ELAPSED < "$T_TMP/rc"; sleep 0.3
  t_eq "post-commit: a hung bus with a double-forked child: exit 0 and the child is gone" "0 0" \
    "$RC $(pgrep -f "sleep $UNIQ2" 2>/dev/null | wc -l | tr -d ' ')"
  pkill -f "sleep $UNIQ2" 2>/dev/null || :; pkill -f "sleep $UNIQ" 2>/dev/null || :
fi

t_section "the added wall time per call, in ms (printed; bounded only against a hang)"
ms() { perl -MTime::HiRes=time -e '$n = shift; $c = shift; $t = time; system($c) for 1 .. $n; printf "%.0f", (time - $t) / $n * 1000' "$1" "$2"; }
BUS="$T_TMP/bus-t"; export HARBOR_EVENT_DIR="$BUS"
printf '%s' "$(post Bash "$FG_IN" "$OUT")" > "$T_TMP/p.fg"; printf '%s' "$(post Read '{"file_path":"/x"}' '"c"')" > "$T_TMP/p.read"
printf '%s' "$(post Bash "$BG_IN" "$OUT")" > "$T_TMP/p.bg"
EMPTY="$(ms 20 "sh -c : < '$T_TMP/p.fg'")"
FG="$(ms 20 "sh '$EH' < '$T_TMP/p.fg'")"; RD="$(ms 20 "sh '$EH' < '$T_TMP/p.read'")"; BGM="$(ms 20 "sh '$EH' < '$T_TMP/p.bg'")"
printf '  empty sh: %s ms · hook on a foreground Bash call (matched, no event): %s ms · on a non-memory Read (matched since harbor#1181; the hook'"'"'s own early-out): %s ms · on a background Bash (event written): %s ms (mean of 20)\n' "$EMPTY" "$FG" "$RD" "$BGM"
t_eq "the background-Bash events were written (20)" 20 "$(count)"
t_eq "a matched call with no event adds under 1000 ms" yes "$([ "$FG" -lt 1000 ] && echo yes || echo no)"
t_eq "a call that writes an event adds under 1000 ms" yes "$([ "$BGM" -lt 1000 ] && echo yes || echo no)"
t_done
