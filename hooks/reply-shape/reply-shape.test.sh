#!/usr/bin/env sh
# reply-shape.sh, the advisory Stop hook: a turn that wrote and shows no evidence draws the note, a
# turn with evidence or no writes draws none, a long reply draws the length note, the note says
# "leads with the answer" is review-only, and every path exits 0 (harbor#952). Transcripts are fixtures.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
TOOL="$T_ROOT/hooks/reply-shape/reply-shape.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$T/cfg"
PROMPT='{"type":"user","message":{"role":"user","content":"do the thing"}}'
RESULT='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}'
tool() { # <name> <input-json>
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"x","name":"%s","input":%s}]}}' "$1" "$2"; }
say() { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
# fixture <name> <prompt-record> <records…>
fixture() { n="$1"; shift; printf '%s\n' "$@" > "$T/$n.jsonl"; }
run() { # <fixture> [stop_hook_active]
  printf '{"session_id":"s","transcript_path":"%s/%s.jsonl","stop_hook_active":%s}' "$T" "$1" "${2:-false}" > "$T/p.json"
  CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2> "$T/err" < "$T/p.json"; RC=$?; }
msg() { cat "$T/out"; }
LONG="$(awk 'BEGIN{for(i=0;i<320;i++) printf "word "}')"

fixture edit_noev  "$PROMPT" "$(tool Edit '{"file_path":"/a/b.sh"}')" "$RESULT" "$(say 'Fixed the parser.')"
fixture edit_ev    "$PROMPT" "$(tool Edit '{"file_path":"/a/b.sh"}')" "$RESULT" "$(say 'Fixed the parser. reply-shape: 12 passed, 0 failed')"
fixture edit_fence "$PROMPT" "$(tool Write '{"file_path":"/a/b.sh"}')" "$RESULT" "$(say 'Done.
```
exit 0
```')"
fixture bash_write "$PROMPT" "$(tool Bash '{"command":"echo hi > out.txt"}')" "$RESULT" "$(say 'Wrote it.')"
fixture bash_read  "$PROMPT" "$(tool Bash '{"command":"git log --oneline 2>&1 | head"}')" "$RESULT" "$(say 'The last commit is abc.')"
fixture read_only  "$PROMPT" "$(tool Read '{"file_path":"/a/b.sh"}')" "$RESULT" "$(say 'It parses args.')"
fixture long_reply "$PROMPT" "$(say "$LONG")"
fixture old_write  "$PROMPT" "$(tool Edit '{"file_path":"/a/b.sh"}')" "$RESULT" "$(say 'Fixed. 3 passed, 0 failed')" "$PROMPT" "$(say 'Yes, that is right.')"

t_section "a turn that wrote and cites no evidence draws the note"
run edit_noev;   t_has "Edit, bare claim: note" "$(msg)" 'cites no command output'
t_has "the note names its id" "$(msg)" '[check:session.reply-shape]'
t_has "the note says answer-first is review-only" "$(msg)" 'review-only'
t_has "the note carries the disable command" "$(msg)" 'reply-shape.off'
run bash_write;  t_has "a writing Bash call counts as a write" "$(msg)" 'cites no command output'

t_section "evidence, or no write, draws none"
run edit_ev;     t_eq "Edit with a pass count: silent" "" "$(msg)"
run edit_fence;  t_eq "Write with a fenced output block: silent" "" "$(msg)"
run bash_read;   t_eq "a read-only Bash call is not a write" "" "$(msg)"
run read_only;   t_eq "Read only: silent" "" "$(msg)"
run old_write;   t_eq "a write in an EARLIER turn does not count" "" "$(msg)"

t_section "length"
run long_reply;  t_has "320 words with no write: the length note" "$(msg)" 'advisory threshold 300'
t_hasnt "length alone does not claim a missing-evidence defect" "$(msg)" 'cites no command output'
REPLY_SHAPE_MAX_WORDS=400 run long_reply; t_eq "the threshold is overridable" "" "$(msg)"

t_section "never blocks: exit 0 on every path, one systemMessage, nothing on stderr"
run edit_noev
t_eq "output is one systemMessage string" 0 "$(jq -e 'keys==["systemMessage"] and (.systemMessage|type=="string")' "$T/out" >/dev/null 2>&1; echo $?)"
t_eq "the note carries no block decision" "" "$(jq -r '.decision // empty' "$T/out")"
t_eq "nothing on stderr" "" "$(cat "$T/err")"
for _f in edit_noev edit_ev long_reply read_only; do run "$_f"; t_eq "exit 0: $_f" 0 "$RC"; done
run edit_noev true; t_eq "stop_hook_active stands it down" "" "$(msg)"; t_eq "stop_hook_active exit" 0 "$RC"
printf '{"transcript_path":"/nope.jsonl"}' > "$T/p2.json"
t_exit "a missing transcript" 0 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" < "$T/p2.json"
t_exit "malformed JSON" 0 sh -c "printf 'not json' | CLAUDE_CONFIG_DIR='$CFG' sh '$TOOL'"
t_exit "empty stdin" 0 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" < /dev/null
printf 'not json\n' > "$T/garbage.jsonl"; run garbage; t_eq "a garbage transcript exits 0" 0 "$RC"

t_section "the off switch"
REPLY_SHAPE=off run edit_noev; t_eq "REPLY_SHAPE=off silences it" "" "$(msg)"
_s="$T/cfg-off"; mkdir -p "$_s"; : > "$_s/reply-shape.off"
printf '{"transcript_path":"%s/edit_noev.jsonl"}' "$T" > "$T/p3.json"
CLAUDE_CONFIG_DIR="$_s" sh "$TOOL" > "$T/out" < "$T/p3.json"; t_eq "the sentinel silences it" "" "$(msg)"
t_done
