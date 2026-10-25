#!/usr/bin/env sh
# session-title.sh (harbor#1257): applies the model-written title via sessionTitle, keyed by session id,
# refuses over 50 characters, never overwrites the operator's /rename, fails open. Fixtures are written here.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/session-title.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$T/cfg"; mkdir -p "$CFG/session-titles"
title() { printf '%s\n' "$2" > "$CFG/session-titles/$1.txt"; }
# run <payload-json> — the hook the way the harness runs it; stdout in $OUT, stderr in $ERR, exit in $RC.
run() { printf '%s' "$1" | CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2> "$T/err"; RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"; }
ups() { printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","session_title":"%s"}' "$1" "${2-}"; }
ss()  { printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"%s","session_title":"%s"}' "$1" "$2" "${3-}"; }
want() { jq -nc --arg e "$1" --arg t "$2" '{hookSpecificOutput: {hookEventName: $e, sessionTitle: $t}}'; }

t_section "a title the model wrote is emitted on both events"
title s1 'harbor: session title hook'
run "$(ups s1)";                t_eq "UserPromptSubmit emits it" "$(want UserPromptSubmit 'harbor: session title hook')" "$OUT"; t_eq "...exit 0" 0 "$RC"
for src in startup resume fork; do
  run "$(ss s1 $src)";          t_eq "SessionStart $src emits it" "$(want SessionStart 'harbor: session title hook')" "$OUT"
done
run "$(ss s1 compact)";         t_eq "SessionStart compact stays silent" "" "$OUT"
run "$(ss s1 clear)";           t_eq "SessionStart clear stays silent" "" "$OUT"
run '{"session_id":"s1","hook_event_name":"Stop"}'; t_eq "Stop (no sessionTitle arm) stays silent" "" "$OUT"

t_section "the file is keyed by session id"
title s2 'other: second session'
run "$(ups s2)";                t_eq "s2 gets s2's title" "$(want UserPromptSubmit 'other: second session')" "$OUT"
run "$(ups s3)";                t_eq "s3 has no file: nothing" "" "$OUT"
run "$(ups ../s1)";             t_eq "a path-shaped session id reads no file" "" "$OUT"

t_section "an operator-set title is never overwritten"
run "$(ups s1 'my own name')";  t_eq "a different session_title: nothing" "" "$OUT"; t_eq "...exit 0" 0 "$RC"
run "$(ss s1 resume 'my own name')"; t_eq "...also on SessionStart" "" "$OUT"
run "$(ups s1 'harbor: session title hook')"; t_eq "an identical session_title may be re-emitted" "$(want UserPromptSubmit 'harbor: session title hook')" "$OUT"

t_section "length is enforced by the hook"
title s4 '12345678901234567890123456789012345678901234567890'
run "$(ups s4)";                t_eq "exactly 50 characters is accepted" "$(want UserPromptSubmit '12345678901234567890123456789012345678901234567890')" "$OUT"
title s5 '123456789012345678901234567890123456789012345678901'
run "$(ups s5)";                t_hasnt "51 characters: no sessionTitle" "$OUT" 'sessionTitle'; t_has "...a message naming the limit" "$OUT" 'limit is 50'; t_eq "...exit 0" 0 "$RC"
title s6 'ééééééééééééééééééééééééééééééééééééééééééééééééé'
run "$(ups s6)";                t_has "50 multibyte characters count as 50, not as bytes" "$OUT" 'sessionTitle'

t_section "empty, missing and malformed input fail open"
: > "$CFG/session-titles/s7.txt"; run "$(ups s7)"; t_eq "an empty file: nothing" "" "$OUT"; t_eq "...exit 0" 0 "$RC"
printf '   \n' > "$CFG/session-titles/s8.txt"; run "$(ups s8)"; t_eq "a blank file: nothing" "" "$OUT"
run 'not json';                 t_eq "garbage payload: nothing" "" "$OUT"; t_eq "...exit 0" 0 "$RC"
run '';                         t_eq "empty payload: nothing" "" "$OUT"; t_eq "...exit 0" 0 "$RC"
title s9 'a "quoted" title \ here'; run "$(ups s9)"; t_eq "quotes and backslashes survive as valid JSON" 'a "quoted" title \ here' "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.sessionTitle')"

t_section "the path is one the floor lets the model Write"
GS="$T_ROOT/bin/guard-selfedit.sh"
gp="$(jq -nc --arg p "$CFG/session-titles/s1.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
t_exit "guard-selfedit allows a Write to the title file" 0 sh -c "printf '%s' '$gp' | CLAUDE_CONFIG_DIR='$CFG' sh '$GS' >/dev/null 2>&1"
gb="$(jq -nc --arg p "$CFG/settings.json" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}')"
t_exit "...and still blocks settings.json (the probe can fail)" 2 sh -c "printf '%s' '$gb' | CLAUDE_CONFIG_DIR='$CFG' sh '$GS' >/dev/null 2>&1"
t_done
