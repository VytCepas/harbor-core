#!/usr/bin/env sh
# lithuanian-rewrite.test.sh (harbor#1572) — bin/doc-lithuanian-rewrite.sh keeps a rewrite only when every protected token survives,
# and the lithuanian-prose context rule names it: rules once per session, one line after, silent on the rewrite call.
# The model is a fake (HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND prints a canned rewrite), so no network and no spend.
. "$(dirname "$0")/../../lib/core.sh"
t_init

TOOL="$T_ROOT/bin/doc-lithuanian-rewrite.sh"
RULE="$T_ROOT/context-rules/user/lithuanian-prose.sh"
IN="$T_TMP/in.txt"
printf '%s\n' "Šiuo metu yra vykdomas Purchase event'ų perkėlimas į naują tag'ą, nes „event_id“ nebuvo perduodamas." \
  "Esant poreikiui atsiųsiu 1 200 pirkimų sąrašą, žr. https://example.com/a_b?x=1 ir \`purchase_v2\`." > "$IN"

# _run <label> <want-exit> <canned rewrite> — the fake model prints the canned text; stdout and stderr land in $OUT / $ERR.
_run() {
  printf '%s' "$3" > "$T_TMP/canned"
  HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="cat '$T_TMP/canned'" sh "$TOOL" "$IN" > "$T_TMP/out" 2> "$T_TMP/err"; _rc=$?
  OUT="$(cat "$T_TMP/out")"; ERR="$(cat "$T_TMP/err")"
  t_eq "$1: exit" "$2" "$_rc"
}
GOOD_L1="Purchase event'us perkeliu į naują tag'ą, nes „event_id“ nebuvo perduodamas."
L2="Jei reikės, atsiųsiu 1 200 pirkimų sąrašą, žr. https://example.com/a_b?x=1 ir \`purchase_v2\`."
ORIG="$(cat "$IN")"

t_section "a rewrite that keeps every protected token is used"
_run "good rewrite" 0 "$GOOD_L1
$L2
"
t_eq "good rewrite: prints the rewrite" "$GOOD_L1
$L2" "$OUT"
t_has "good rewrite: says so" "$ERR" "every protected token kept"

t_section "an apostrophe term may change its ending, never its stem"
_run "ending only" 0 "Purchase event'ai perkeliami į naują tag'o vietą, nes „event_id“ nebuvo perduodamas.
$L2
"
_run "translated term" 3 "Purchase įvykius perkeliu į naują žymę, nes „event_id“ nebuvo perduodamas.
$L2
"
t_eq "translated term: prints the original" "$ORIG" "$OUT"
t_has "translated term: names what was lost" "$ERR" "lost"

t_section "a changed number, URL, code span, quoted identifier or line count keeps the original"
_run "number dropped" 3 "$GOOD_L1
Jei reikės, atsiųsiu pirkimų sąrašą, žr. https://example.com/a_b?x=1 ir \`purchase_v2\`.
"
t_has "number dropped: names the number" "$ERR" "200"
_run "url changed" 3 "$GOOD_L1
Jei reikės, atsiųsiu 1 200 pirkimų sąrašą, žr. https://example.com/a-b?x=1 ir \`purchase_v2\`.
"
_run "code span changed" 3 "$GOOD_L1
Jei reikės, atsiųsiu 1 200 pirkimų sąrašą, žr. https://example.com/a_b?x=1 ir \`purchase_v3\`.
"
_run "identifier declined" 3 "Purchase event'us perkeliu į naują tag'ą, nes „event_id'as“ nebuvo perduodamas.
$L2
"
_run "lines merged" 3 "$GOOD_L1 $L2
"
t_has "lines merged: says why" "$ERR" "lines 2 became 1"
_run "a greeting added" 3 "Sveiki,
$GOOD_L1
$L2
"

t_section "a model that fails or says nothing keeps the original"
printf 'exit 1\n' > "$T_TMP/fail.sh"
HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="sh '$T_TMP/fail.sh'" sh "$TOOL" "$IN" > "$T_TMP/out" 2> "$T_TMP/err"; _rc=$?
t_eq "model failed: exit" 3 "$_rc"
t_eq "model failed: prints the original" "$ORIG" "$(cat "$T_TMP/out")"
_run "empty answer" 3 ""
t_exit "unknown model" 2 sh "$TOOL" --model opus "$IN"

t_section "the context rule: rules once, one line after, silent on the rewrite call"
_p() { jq -cn --arg s "$1" --arg c "$2" '{hook_event_name:"PreToolUse",session_id:$s,tool_name:"Write",tool_input:{file_path:"/x/a.md",content:$c}}'; }
LT="Šiuo metu duomenų perkėlimas vykdomas į naują lentelę, kurią užpildysiu iki penktadienio."
N1="$(_p s1 "$LT" | sh "$RULE")"
t_has "first note: carries the rules" "$N1" "Write the draft to these rules"
t_has "first note: names the tool" "$N1" "doc-lithuanian-rewrite.sh"
N2="$(_p s1 "$LT" | sh "$RULE")"
t_has "second note: names the tool" "$N2" "doc-lithuanian-rewrite.sh"
t_hasnt "second note: no rules again" "$N2" "Write the draft to these rules"
N3="$(_p s2 "$LT" | sh "$RULE")"
t_has "another session: the rules again" "$N3" "Write the draft to these rules"
N4="$(jq -cn --arg c "sh ~/port/harbor/bin/doc-lithuanian-rewrite.sh a.md # $LT" '{hook_event_name:"PreToolUse",session_id:"s1",tool_name:"Bash",tool_input:{command:$c}}' | sh "$RULE")"
t_eq "the rewrite call: silent" "" "$N4"

t_done
