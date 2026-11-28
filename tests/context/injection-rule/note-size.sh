#!/usr/bin/env sh
# note-size.sh <repo root> — bytes the injection engine puts in the model's context for ONE fixed synthetic session (harbor P10, W2).
#   sh tests/context/injection-rule/note-size.sh .                      # this checkout
#   git archive origin/main | tar -x -C "$D" && sh tests/context/injection-rule/note-size.sh "$D"    # a baseline
# The session: a startup, 6 thin Agent briefs, 4 answered AskUserQuestions, 5 Lithuanian Bash calls, 3 subagent starts,
# 3 different unbounded loops, 8 calls a fixture skill owns, a compaction, then 2 briefs, 2 answers, 2 Lithuanian calls.
# It reads the engine and the shipped rules of <root> and writes only to a temporary config dir and HOME.
set -eu
ROOT="${1:?usage: note-size.sh <repo root>}"
ROOT="$(cd "$ROOT" && pwd -P)"
T="$(mktemp -d "${TMPDIR:-/tmp}/note-bytes.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CFG="$T/cfg"; HOME="$T/home"; export HOME; SK="$CFG/skills"; REPO="$T/repo"
mkdir -p "$CFG/context-rules/user" "$CFG/bin" "$REPO" "$SK/alpha" "$HOME/port/harbor" "$HOME/port/demo"
cp "$ROOT"/context-rules/user/* "$CFG/context-rules/user/"
cp "$ROOT/hooks/injection-rule/injection-rule.sh" "$ROOT"/bin/library-*.sh "$ROOT/bin/admission-normalize.awk" "$CFG/bin/"
printf 'harbor\t~/port/harbor\tthe fixture control plane\ndemo\t~/port/demo\ta fixture project\n' > "$CFG/context-rules/user/projects.tsv"
printf -- '---\nname: alpha\ndescription: "Alpha things. USE WHEN alpha work. NOT FOR beta."\nowns-commands: alphacli\n---\n# alpha\n' > "$SK/alpha/SKILL.md"
printf '{"type":"user","message":"nothing relevant"}\n' > "$T/empty.jsonl"
LOG="$T/log.tsv"; : > "$LOG"
S=m1
fire() { # <payload json> → appends "<id>\t<bytes>" per delivered note
  _o="$(printf '%s' "$1" | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" sh "$CFG/bin/injection-rule.sh" 2>/dev/null || true)"
  [ -n "$_o" ] || return 0
  printf '%s' "$_o" | jq -r '.hookSpecificOutput.additionalContext // empty' | sed 's/ \[context:/\
[context:/g' | awk -F'[][]' '/^\[context:/ { id = $2; sub(/^context:/, "", id); n[id]++ } END { for (i in n) print i }' > "$T/ids" || true
  _b="$(printf '%s' "$_o" | jq -r '.hookSpecificOutput.additionalContext // empty' | wc -c | tr -d ' ')"
  _n="$(wc -l < "$T/ids" | tr -d ' ')"
  [ "$_n" -gt 0 ] || return 0
  # one note per id; a payload with several shares its bytes evenly (they are rare)
  while IFS= read -r _i; do printf '%s\t%s\n' "$_i" "$((_b / _n))" >> "$LOG"; done < "$T/ids"
}
ev() { jq -cn --arg e "$1" --arg s "$S" --arg src "${2-}" '{hook_event_name:$e,session_id:$s,transcript_path:"'"$T"'/empty.jsonl"} + (if $src == "" then {} else {source:$src} end)'; }
bash_call() { jq -cn --arg c "$1" --arg s "$S" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:$s,transcript_path:"'"$T"'/empty.jsonl",tool_input:{command:$c,description:"run"}}'; }
agent_call() { jq -cn --arg p "$1" --arg s "$S" '{hook_event_name:"PreToolUse",tool_name:"Agent",session_id:$s,tool_input:{description:"d",subagent_type:"general-purpose",model:"sonnet",prompt:$p}}'; }
answer() { jq -cn --arg s "$S" '{hook_event_name:"PostToolUse",tool_name:"AskUserQuestion",session_id:$s,tool_input:{questions:[]},tool_response:{answers:{"Ship?":"Ship"}}}'; }

fire "$(ev SessionStart startup)"
i=0; while [ $i -lt 6 ]; do i=$((i + 1)); fire "$(agent_call "Look at branch $i and tell me about it.")"; done
i=0; while [ $i -lt 4 ]; do i=$((i + 1)); fire "$(answer)"; done
i=0; while [ $i -lt 5 ]; do i=$((i + 1)); fire "$(bash_call "gmail-write reply abc$i --body \"Ačiū, radau priežastį, pataisysiu šiandien žodžiu\"")"; done
i=0; while [ $i -lt 3 ]; do i=$((i + 1)); fire "$(ev SubagentStart)"; done
i=0; while [ $i -lt 3 ]; do i=$((i + 1)); fire "$(bash_call "while true; do sleep $i; done")"; done
i=0; while [ $i -lt 8 ]; do i=$((i + 1)); fire "$(bash_call "alphacli list $i")"; done
fire "$(ev SessionStart compact)"
i=0; while [ $i -lt 2 ]; do i=$((i + 1)); fire "$(agent_call "Look at tag $i and tell me about it.")"; done
i=0; while [ $i -lt 2 ]; do i=$((i + 1)); fire "$(answer)"; done
i=0; while [ $i -lt 2 ]; do i=$((i + 1)); fire "$(bash_call "gmail-write reply def$i --body \"Ačiū, radau priežastį, pataisysiu šiandien žodžiu\"")"; done

printf 'note\tcount\tbytes\n'
sort "$LOG" | awk -F'\t' '{ c[$1]++; b[$1] += $2; C++; B += $2 } END { for (i in c) printf "%s\t%d\t%d\n", i, c[i], b[i]; printf "TOTAL\t%d\t%d\n", C, B }' | sort
