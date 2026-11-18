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

# _one <label> <want-exit> <input line> <canned rewrite> — one-line texts for the checks the long fixture cannot isolate.
_one() {
  printf '%s\n' "$3" > "$T_TMP/one"; printf '%s\n' "$4" > "$T_TMP/canned1"
  HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="cat '$T_TMP/canned1'" sh "$TOOL" "$T_TMP/one" > "$T_TMP/out" 2> "$T_TMP/err"; _rc=$?
  OUT="$(cat "$T_TMP/out")"; ERR="$(cat "$T_TMP/err")"
  t_eq "$1: exit" "$2" "$_rc"
}

t_section "each protected class holds on its own"
_one "quoted span changed" 3 "Ataskaitą „Pirkimų suvestinė“ atnaujinau šiandien." "Ataskaitą „Pirkimų ataskaita“ atnaujinau šiandien."
_one "ALL-CAPS term changed" 3 "Šią savaitę ROAS krito, todėl tikrinu kampanijas." "Šią savaitę CPA krito, todėl tikrinu kampanijas."
_one "English jargon translated" 3 "Consent baneris blokuoja checkout'o žingsnį ir trukdo pardavimams." "Sutikimų baneris blokuoja checkout'o žingsnį ir trukdo pardavimams."
t_has "English jargon translated: names it" "$ERR" "consent"
_one "jargon only changes case" 0 "Consent baneris blokuoja checkout'o žingsnį ir trukdo pardavimams." "consent baneris blokuoja checkout'o žingsnį ir trukdo pardavimams."
_one "typographic apostrophe" 0 "Perkeliu event'us į naują vietą šiandien." "Perkeliu event’us į naują vietą šiandien."

t_section "an answer that is not the text keeps the original"
_one "an error printed with exit 0" 3 "Labas rytas, šiandien darbas vyksta gerai ir be trukdžių." "Rate limit reached."
t_has "an error printed with exit 0: says why" "$ERR" "not Lithuanian"
_one "a stub of an answer" 3 "Labas rytas, šiandien darbas vyksta gerai ir be trukdžių." "Ačiū."
t_has "a stub of an answer: says why" "$ERR" "under 40%"

t_section "a model that hangs is cut off"
printf '%s\n' "Šiandien perkeliu duomenis į naują lentelę." > "$T_TMP/one"
_t0="$(date +%s)"
HARBOR_DOC_LITHUANIAN_REWRITE_TIMEOUT=1 HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="sleep 6; cat" sh "$TOOL" "$T_TMP/one" > "$T_TMP/out" 2> "$T_TMP/err"; _rc=$?
_t1="$(date +%s)"
t_eq "hung model: exit" 3 "$_rc"
t_has "hung model: says why" "$(cat "$T_TMP/err")" "did not answer within 1s"
t_eq "hung model: prints the original" "$(cat "$T_TMP/one")" "$(cat "$T_TMP/out")"
[ $((_t1 - _t0)) -lt 5 ] && t_pass || t_fail "hung model: took $((_t1 - _t0))s, the watchdog did not cut it"
t_exit "a bad timeout" 2 env HARBOR_DOC_LITHUANIAN_REWRITE_TIMEOUT=soon sh "$TOOL" "$T_TMP/one"

t_section "bad input is a usage error, never a model call"
t_exit "missing file" 2 sh "$TOOL" "$T_TMP/does-not-exist"
printf '   \n\n' > "$T_TMP/blank"
t_exit "whitespace only" 2 env HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="echo CALLED" sh "$TOOL" "$T_TMP/blank"

t_section "a check that cannot run keeps the original"
mkdir -p "$T_TMP/nojq"; printf '#!/bin/sh\nexit 1\n' > "$T_TMP/nojq/jq"; chmod +x "$T_TMP/nojq/jq"
printf '%s\n' "Perkeliu event'us į naują vietą šiandien." > "$T_TMP/one"
PATH="$T_TMP/nojq:$PATH" HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND="cat" sh "$TOOL" "$T_TMP/one" > "$T_TMP/out" 2> "$T_TMP/err"; _rc=$?
t_eq "jq fails: exit" 3 "$_rc"
t_has "jq fails: says so" "$(cat "$T_TMP/err")" "could not run"

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
t_eq "five Lithuanian letters: silent" "" "$(_p s3 "aą bč cę dė eį" | sh "$RULE")"
t_has "six Lithuanian letters: fires" "$(_p s3 "aą bč cę dė eį fš" | sh "$RULE")" "doc-lithuanian-rewrite.sh"
N5="$(jq -cn --arg c "$LT" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:"/x/a.md",content:$c}}' | sh "$RULE")"
t_has "no session id: one line" "$N5" "doc-lithuanian-rewrite.sh"
t_hasnt "no session id: not the rules" "$N5" "Write the draft to these rules"
LD="$CLAUDE_CONFIG_DIR/state/lithuanian-prose"; mkdir -p "$LD"; : > "$LD/old.seen"; touch -t 202001010000 "$LD/old.seen"
_p s4 "$LT" | sh "$RULE" > /dev/null
[ ! -f "$LD/old.seen" ] && t_pass || t_fail "a ledger older than 7 days was not pruned"
[ -f "$LD/s4.seen" ] && t_pass || t_fail "the new session's ledger was not written"

t_done
