#!/usr/bin/env sh
# decision-question.test.sh (harbor#949) — the decision standard's two packs through the real engine.
# A thin question is denied with each gap named, a complete one passes, the answers draw the recording
# note, and the documents must name every label the script enforces.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"; U="$T_ROOT/context-rules/user"
mkdir -p "$CFG/inject.d" "$CFG/bin" "$REPO"
cp "$U/decision-question-shape.md" "$U/decision-question.sh" "$U/decision-answer-binds.md" "$CFG/inject.d/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"

REC='Ship it now. Why: smallest change. Pros: one commit. Cons: no migration window. Consequence: reversible by revert; touches the CI owner. Flips if: CI is red on main.'
ALT='Hold a week. Pros: no risk this week. Cons: the gap stays open. Consequence: blocks the release.'
# ask <questions-json> [event] → engine stdout in $OUT, rc in $RC
ask() {
  jq -nc --argjson q "$1" --arg ev "${2:-PreToolUse}" \
    '{hook_event_name:$ev,tool_name:"AskUserQuestion",session_id:"s",tool_input:{questions:$q}}' > "$T/in.json"
  OUT="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>"$T/err")"; RC=$?
}
q() { # <label1> <desc1> <label2> <desc2> [multiSelect] → one question
  jq -nc --arg l1 "$1" --arg d1 "$2" --arg l2 "$3" --arg d2 "$4" --argjson ms "${5:-false}" \
    '{question:"Ship the fix now?",header:"Ship",multiSelect:$ms,options:[{label:$l1,description:$d1},{label:$l2,description:$d2}]}'
}
decision() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
reason()   { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
note()     { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

t_section "a thin question is denied, and the reason names each gap"
ask "[$(q Ship 'ship it' Hold 'wait')]"
t_eq "bare options: deny" deny "$(decision)"
t_has "it names the missing recommendation" "$(reason)" 'Q1: no option is marked'
t_has "it names option 1's missing labels" "$(reason)" 'Q1 option 1 (Ship): lacks Pros: Cons: Consequence:'
t_has "it names option 2's missing labels" "$(reason)" 'Q1 option 2 (Hold): lacks Pros: Cons: Consequence:'
t_has "it states the standard" "$(reason)" 'Flips if:'
ask "[$(q Hold "$ALT" 'Ship (Recommended)' "$REC")]"
t_eq "every label, but the recommendation second: deny" deny "$(decision)"
t_has "it says the recommendation must be first" "$(reason)" 'must be the FIRST'
ask "[$(q 'Ship (Recommended)' "$REC" 'Hold (Recommended)' "$ALT Why: x. Flips if: y.")]"
t_has "two options marked on a single-select: deny" "$(reason)" 'the only one marked'
ask "[$(q 'Ship (Recommended)' 'Ship it now. Pros: a. Cons: b. Consequence: c.' Hold "$ALT")]"
t_has "the recommended option without Why: and Flips if: is named" "$(reason)" 'lacks Why: Flips if:'
ask "[$(q 'Ship (Recommended)' "$REC" Hold 'Hold a week. Pros: none. Cons: slower.')]"
t_has "an alternative with no consequence is named" "$(reason)" 'Q1 option 2 (Hold): lacks Consequence:'
ask "[$(q 'Ship (Recommended)' "$REC" Hold "$ALT"),$(q Ship 'x' Hold 'y')]"
t_has "the second question's gap is named as Q2" "$(reason)" 'Q2: no option is marked'
t_hasnt "the complete first question is not named" "$(reason)" 'Q1'

t_section "a complete question passes"
ask "[$(q 'Ship (Recommended)' "$REC" Hold "$ALT")]"
t_eq "anatomy on every option, recommendation first: no decision" "" "$(decision)"
t_eq "and no note" "" "$(note)"
t_eq "exit 0" 0 "$RC"
ask "[$(q 'Ship (Recommended)' "$(printf '%s' "$REC" | tr '[:upper:]' '[:lower:]')" Hold "$ALT")]"
t_eq "labels are matched without case" "" "$(decision)"
ask "$(jq -nc --arg p "$REC" --arg d "$ALT" '[{question:"q",header:"h",options:[{label:"Ship (Recommended)",description:"short",preview:$p},{label:"Hold",description:$d}]}]')"
t_eq "the parts may live in the option's preview" "" "$(decision)"
ask "[$(q Ship "$REC" 'Hold (Recommended)' "$ALT Why: x. Flips if: y." true)]"
t_eq "a multiSelect may mark a later option" "" "$(decision)"
ask "[$(q Ship "$REC" Hold "$ALT" true)]"
t_eq "a multiSelect with nothing marked is still denied" deny "$(decision)"
ask '[{"question":"What should the ticket be called?","kind":"text"}]'
t_eq "a question with no options is out of scope" "" "$(decision)"
t_eq "garbage payload: exit 0, nothing printed" "0:" \
  "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null; printf '%s:' $?)"

t_section "the answers coming back carry the recording duty"
ask "[$(q 'Ship (Recommended)' "$REC" Hold "$ALT")]" PostToolUse
t_has "PostToolUse on AskUserQuestion delivers the note" "$(note)" 'record each'
t_has "it names where an answer binds" "$(note)" 'docs/decisions/'
t_eq "and never a decision" "" "$(decision)"

t_section "the standard's documents name every label the script enforces"
_labels="$(sed -n "s/^LABELS_[A-Z]*='\(.*\)'$/\1/p" "$U/decision-question.sh" | tr '|' '\n')"
t_eq "the script declares five labels" 5 "$(printf '%s\n' "$_labels" | grep -c .)"
for _doc in docs/explanation/grilling.md commands/grillme.md; do
  printf '%s\n' "$_labels" | while IFS= read -r _l; do
    [ -n "$_l" ] || continue
    grep -qF "\`$_l\`" "$T_ROOT/$_doc" && printf 'ok\n' || printf 'MISSING %s in %s\n' "$_l" "$_doc"
  done > "$T/vocab"
  t_eq "$_doc names each label in backticks" "" "$(grep MISSING "$T/vocab" || true)"
done
t_done
