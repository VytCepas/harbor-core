#!/usr/bin/env sh
# The agent-brief inform pack through the real engine (harbor#953): a brief missing its outcome draws a
# note that names it, a complete brief draws none, the pack never denies, and a fired rule reaches the
# decision log. A throwaway config dir carries the pack, its model helper, the engine and the floor lib.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"
mkdir -p "$CFG/inject.d" "$CFG/bin" "$REPO"
cp "$T_ROOT/inject.d/box/96-agent-brief.md" "$T_ROOT/inject.d/box/agent-brief.sh" "$T_ROOT/inject.d/box/agent-model.sh" "$CFG/inject.d/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/guard-lib.sh" "$CFG/bin/"
# A decision log the floor writer will accept: a host token, a sink file, and a host dir that is not writable.
OBS="$CFG/MEMORY/OBSERVABILITY/testhost"; mkdir -p "$OBS"; printf 'testhost\n' > "$CFG/.helm-obs-host"
: > "$OBS/guard-decisions.jsonl"; chmod 500 "$OBS"
trap 'chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT

FULL='Goal: list the stale branches. Done when every branch older than 30 days is named. Constraint: read-only, never delete anything. Write the table to ~/Deliverables/branches.md.'
call() { # <prompt> [model] [subagent_type] [effort] → engine stdout in $OUT, rc in $RC
  jq -nc --arg p "$1" --arg m "${2-sonnet}" --arg t "${3-general-purpose}" --arg e "${4-}" \
    '{hook_event_name:"PreToolUse",tool_name:"Agent",session_id:"s",
      tool_input:({description:"d",prompt:$p,subagent_type:$t} + (if $m == "" then {} else {model:$m} end)
                  + (if $e == "" then {} else {effort:$e} end))}' > "$T/in.json"
  OUT="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>"$T/err")"; RC=$?
}
note() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

t_section "a brief missing a section draws a note that names it"
call 'Look at the branches and tell me about them.'
t_has "a thin brief draws the note" "$(note)" 'Agent brief check'
t_has "it names the missing outcome" "$(note)" 'done/outcome'
t_has "it names the missing constraints" "$(note)" 'constraints'
t_has "it names the missing output location" "$(note)" 'output location'
call 'Done when every branch older than 30 days is named. Constraint: read-only. Write it to ~/Deliverables/b.md.'
t_eq "a brief with all three: silent" "" "$(note)"
call 'Constraint: read-only, never delete. Write the table to ~/Deliverables/b.md. List the stale branches.'
t_has "outcome missing alone is named" "$(note)" 'done/outcome'
t_hasnt "and only it" "$(note)" 'constraints ('
call 'Done when every branch is named. List the stale branches. Write it to ~/Deliverables/b.md.'
t_has "constraints missing alone is named" "$(note)" 'constraints'
call 'Done when every branch is named. Stay within read-only.'
t_has "output location missing alone is named" "$(note)" 'output location'

t_section "the model field"
call "$FULL" ''
t_has "no model: the note names it" "$(note)" 'a model'
call "$FULL" 'haiku'
t_eq "a complete brief with a model: silent" "" "$(note)"
call 'look around' '' fork
t_eq "a fork is exempt, as it is for the tier rule" "" "$(note)"

t_section "haiku asked to change code names its effort (harbor#818)"
CODE='Goal: fix the failing parser test. Done when tests/x-test.sh passes. Constraint: only touch bin/x.sh. Report back the diff.'
call "$CODE" haiku
t_has "haiku, a code change, no effort: the note names it" "$(note)" 'an effort'
t_hasnt "and nothing else" "$(note)" 'constraints ('
call "$CODE" haiku general-purpose high
t_eq "the same brief with effort high: silent" "" "$(note)"
call "$FULL" haiku
t_eq "haiku on read-only work with no effort: silent" "" "$(note)"
call "$CODE" sonnet
t_eq "sonnet on the same code change: silent" "" "$(note)"
call 'Goal: add a regression test for the --days window. Done when the suite passes. Only touch the test. Report back.' haiku
t_has "writing a test counts as changing code" "$(note)" 'an effort'

t_section "it informs and never denies"
call 'Look at the branches.' ''
t_eq "a worst-case brief carries no permissionDecision" "" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""')"
t_eq "exit 0" 0 "$RC"
t_eq "the script never prints a deny sentinel" 0 "$(grep 'printf' "$T_ROOT/inject.d/box/agent-brief.sh" | grep -c 'HARBOR-DECISION')"
t_eq "garbage payload: silent exit 0" 0 "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" >/dev/null 2>&1; echo $?)"

t_section "the decision log"
chmod u+w "$OBS"; : > "$OBS/guard-decisions.jsonl"; chmod 500 "$OBS"
call "$FULL"
t_eq "a silent call writes no record" 0 "$(wc -l < "$OBS/guard-decisions.jsonl" | tr -d ' ')"
call 'Look at the branches and tell me about them.'
_rec="$(tail -n 1 "$OBS/guard-decisions.jsonl")"
t_eq "a fired note writes one record" 1 "$(wc -l < "$OBS/guard-decisions.jsonl" | tr -d ' ')"
t_eq "the record names the rule" agent-brief "$(printf '%s' "$_rec" | jq -r '.r')"
t_eq "the record is the inject guard's advise" "inject advise" "$(printf '%s' "$_rec" | jq -r '[.g,.d]|join(" ")')"
t_eq "the record carries the tool" Agent "$(printf '%s' "$_rec" | jq -r '.t')"
t_done
