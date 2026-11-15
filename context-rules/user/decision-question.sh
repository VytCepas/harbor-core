#!/usr/bin/env sh
# decision-question.sh (harbor#949) — deny an AskUserQuestion whose options lack the decision anatomy.
# A deny, not a note: a note rides back with the answer. It reads labels, not honesty (grilling.md).
# Fail-open on no jq or a malformed payload; a question with no options is out of scope.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0

# The vocabulary; decision-question.test.sh fails when the standard's documents stop naming one.
LABELS_EVERY='Pros:|Cons:|Consequence:'
LABELS_RECOMMENDED='Why:|Flips if:'

PROBLEMS="$(printf '%s' "$P" | jq -r --arg every "$LABELS_EVERY" --arg rec "$LABELS_RECOMMENDED" '
  def text: (((.description // "") | tostring) + " " + ((.preview // "") | tostring)) | ascii_downcase;
  def marked: ((.label // "") | tostring) | test("\\(recommended\\)\\s*$"; "i");
  def lacking($labels): . as $t | [$labels | split("|")[] | . as $l | select(($t | index($l | ascii_downcase)) == null)];
  (.tool_input.questions // []) as $qs
  | if ($qs | type) != "array" then empty else $qs end
  | to_entries[]
  | .key as $qi | .value as $q
  | select(($q | type) == "object" and ($q.options | type) == "array" and ($q.options | length) > 0)
  | "Q\($qi + 1)" as $n
  | [$q.options | to_entries[] | select(.value | type == "object") | select(.value | marked) | .key] as $recs
  | (if ($recs | length) == 0 then
       "\($n): no option is marked; put the recommended one first and end its label with (Recommended)"
     elif ($q.multiSelect // false) != true and $recs != [0] then
       "\($n): the recommended option must be the FIRST and the only one marked (Recommended)"
     else empty end),
    ($q.options | to_entries[] | select(.value | type == "object")
     | .key as $oi | .value as $o
     | ($o | text) as $t
     | (($t | lacking($every)) + (if ($o | marked) then ($t | lacking($rec)) else [] end)) as $miss
     | select(($miss | length) > 0)
     | "\($n) option \($oi + 1) (\(($o.label // "") | tostring | .[0:40])): lacks \($miss | join(" "))")
' 2>/dev/null)" || exit 0
[ -n "$PROBLEMS" ] || exit 0

LIST="$(printf '%s\n' "$PROBLEMS" | head -n 8 | awk 'NR > 1 { printf "; " } { printf "%s", $0 }')"
printf '%s\n' "HARBOR-DECISION deny: This question does not meet the decision standard (harbor docs/explanation/grilling.md): $LIST. Every option's description (or its preview) carries Pros:, Cons: and Consequence: (what changes, what breaks or must follow, cost, reversibility, who else it touches). The recommended option is first, its label ends (Recommended), and it also carries Why: (why it beats the others) and Flips if: (what would change the recommendation). Up to four real options: a genuine alternative, and Defer/Hold with its own consequence where honest; no strawmen. When options differ on several axes, put a comparison matrix in the preview. A question you could answer by reading or running something is not a question: go and find out. Re-ask with the parts filled in."
