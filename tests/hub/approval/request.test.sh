#!/usr/bin/env sh
# request.test.sh (harbor#1278) — hub-approval.sh file and note: closed fields only, one open request per id, a mention for the
# admin, and the signal that tells a member an approval arrived.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
be_up
A="$BE_BIN/hub-approval.sh"; ID="$BE_ID"
LABEL='Touches the production bucket'
file() { be_rc sh "$A" file "$ID" prod-bucket very-high cloud "$LABEL"; }
posts() { be_log_count '.method == "POST" and (.path | endswith("/issues"))'; }

t_section "1 - the issue is the closed lines and nothing else"
be_reset
t_eq "filing is exit 0" 0 "$(file)"
want="$(printf 'harbor-request: 1\nid: %s\nmember: alice\nrule: prod-bucket\nlabel: %s\ntier: very-high\ntarget: cloud\ncore: 0123456789ab\ncc: @fixture-admin\n' "$ID" "$LABEL")"
t_eq "the exact body" "$want" "$(jq -r .body "$BE_ST/issues/1.json")"
t_eq "the exact title" "request $ID" "$(jq -r .title "$BE_ST/issues/1.json")"
t_eq "the create call sends only title and body" 'body,title' "$(jq -rs '[.[] | select(.method == "POST")][0].body | fromjson | keys | join(",")' "$BE_ST/log.jsonl")"
t_eq "the opened event is recorded" opened "$(jq -r 'select(.kind == "request") | .outcome' "$BE_HS/outbox.jsonl")"
be_reset; be_policy '.approval.approvers = ["fixture-admin","alice","second-admin"]'
file >/dev/null
t_eq "every other approver is mentioned, never the member" 'cc: @fixture-admin @second-admin' "$(jq -r .body "$BE_ST/issues/1.json" | sed -n 9p)"
be_policy '.approval.ttl_hours = 24'

t_section "2 - a core rule's label comes from the tier lookup"
be_reset
t_eq "the core label is accepted" 0 "$(be_rc sh "$A" file "$ID" admission.key-material-egress very-high credential 'Credentials leaving the machine')"
t_has "and filed" "$(jq -r .body "$BE_ST/issues/1.json")" 'rule: admission.key-material-egress'

t_section "3 - content can't ride a field"
be_reset
refused() { # <label> <rule> <tier> <target> <text>
  t_eq "$1" 2 "$(be_rc sh "$A" file "$ID" "$2" "$3" "$4" "$5")"
}
refused "a prose rule" 'delete the client bucket' very-high cloud "$LABEL"
refused "a rule with a newline" 'prod-bucket
cc: @someone' very-high cloud "$LABEL"
refused "a tier off the list" prod-bucket urgent cloud "$LABEL"
refused "a target off the list" prod-bucket very-high client-list "$LABEL"
refused "a label that isn't the rule's" prod-bucket very-high cloud 'the command was rm -rf gs://prod-acme'
refused "a label on a rule nobody knows" unknown-rule very-high cloud "$LABEL"
refused "a label with a line break" prod-bucket very-high cloud "$LABEL
extra line"
refused "a label over 60 characters" prod-bucket very-high cloud "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61)"
t_eq "a bad id" 2 "$(be_rc sh "$A" file 'r-short' prod-bucket very-high cloud "$LABEL")"
t_eq "nothing reached the board" 0 "$(posts)"

t_section "4 - one open request per id"
be_reset
file >/dev/null
t_eq "a second call is a no-op" 0 "$(file)"
t_eq "one issue" 1 "$(posts)"
printf 500 > "$BE_ST/force"; sh "$A" consume "$ID"; rm -f "$BE_ST/force"; printf '7\n' > "$BE_HS/used/$ID"
file >/dev/null
t_eq "a used request whose close failed is still the one open issue" 1 "$(posts)"
rm -rf "$BE_HS/requests" "$BE_HS/used"
file >/dev/null
t_eq "the board stops a duplicate when the local record is gone" 1 "$(posts)"
be_reset
sh "$A" file "$ID" prod-bucket very-high cloud "$LABEL" & p1=$!
sh "$A" file "$ID" prod-bucket very-high cloud "$LABEL" & p2=$!
wait "$p1"; wait "$p2"
t_eq "two hooks racing still open one" 1 "$(posts)"
t_eq "and no lock is left" 0 "$(find "$BE_HS/requests" -name '*.lock' | wc -l | tr -d ' ')"
mkdir -p "$BE_HS/requests/r-1111111111111111.lock"
touch -t 202001010000 "$BE_HS/requests/r-1111111111111111.lock"
t_eq "a crashed filer's old lock doesn't block" 0 "$(be_rc sh "$A" file r-1111111111111111 prod-bucket very-high cloud "$LABEL")"
t_eq "the request was filed" 2 "$(posts)"

t_section "5 - a closed request: declined stays quiet, used can be asked again"
be_reset
file >/dev/null
jq '.state = "closed"' "$BE_ST/issues/1.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/1.json"
file >/dev/null
t_eq "closed by the admin, a retry mails nobody" 1 "$(posts)"
be_comment 1 fixture-admin "approve $ID"
jq '.state = "open"' "$BE_ST/issues/1.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/1.json"
t_eq "an admin reopening it is enough" 0 "$(be_rc sh "$A" status "$ID")"
sh "$A" consume "$ID"
file >/dev/null
t_eq "the same call run again after use is a new request" 2 "$(posts)"
t_eq "with its own number in the record" 2 "$(jq -r .issue "$BE_HS/requests/$ID.json")"
t_eq "the old approval doesn't carry over" 1 "$(be_rc sh "$A" status "$ID")"
be_comment 2 fixture-admin "approve $ID"
t_eq "a new one does" 0 "$(be_rc sh "$A" status "$ID")"

t_section "6 - GitHub down or no policy"
be_reset
printf 500 > "$BE_ST/force"
t_eq "the board down is exit 3" 3 "$(file)"
rm -f "$BE_ST/force"
printf 500 > "$BE_ST/force-post"
t_eq "a create that fails is exit 3" 3 "$(file)"
rm -f "$BE_ST/force-post"
t_eq "and it files once GitHub is back" 0 "$(file)"
t_eq "one issue" 1 "$(jq -s 'map(select(.title)) | length' "$BE_ST"/issues/*.json)"
be_reset
mv "$T_TMP/state-policy.json.sig" "$T_TMP/sig.keep"
t_eq "no signed policy is exit 3" 3 "$(file)"
t_eq "and nothing filed" 0 "$(posts)"
mv "$T_TMP/sig.keep" "$T_TMP/state-policy.json.sig"

t_section "7 - the member hears an approval arrived (F23)"
be_reset
file >/dev/null
t_eq "nothing to say before an approval" "" "$(sh "$A" note)"
rm -f "$BE_HS/requests/.last-note"
be_comment 1 fixture-admin "approve $ID"
out="$(sh "$A" note)"
t_has "the note names the action" "$out" "An admin approved: $LABEL"
t_has "and the id" "$out" "$ID"
rm -f "$BE_HS/requests/.last-note"
t_eq "said once" "" "$(sh "$A" note)"
be_reset
file >/dev/null
sh "$A" note >/dev/null
be_comment 1 fixture-admin "approve $ID"
t_eq "at most one look a minute" "" "$(sh "$A" note)"
rm -f "$BE_HS/requests/.last-note"
json="$(sh "$A" note UserPromptSubmit)"
t_eq "hook form names the event" UserPromptSubmit "$(printf '%s' "$json" | jq -r .hookSpecificOutput.hookEventName)"
t_has "for the agent" "$(printf '%s' "$json" | jq -r .hookSpecificOutput.additionalContext)" 'An admin approved'
t_has "and the person" "$(printf '%s' "$json" | jq -r .systemMessage)" 'An admin approved'
be_reset
: > "$BE_ST/log.jsonl"
sh "$A" note >/dev/null
t_eq "no open request, no network" 0 "$(jq -s length "$BE_ST/log.jsonl")"
be_reset
file >/dev/null
sh "$A" consume "$ID"
rm -f "$BE_HS/requests/.last-note"
be_comment 1 fixture-admin "approve $ID"
t_eq "a used request says nothing" "" "$(sh "$A" note)"
be_reset
mkdir -p "$BE_HS"; printf 'token-expired\n' > "$BE_HS/board-state"
t_has "a dead token is told" "$(sh "$A" note)" 'token has ended'
t_eq "once a day, not on every prompt" "" "$(sh "$A" note)"
rm -f "$BE_HS/board-state" "$BE_HS/.token-note"; printf '6\n' > "$BE_HS/token-days-left"
t_has "a dying token is told" "$(sh "$A" note)" 'ends in 6 days'
be_reset
for i in 1 2 3 4; do
  old="r-000000000000000$i"
  sh "$A" file "$old" prod-bucket very-high cloud "$LABEL"
done
file >/dev/null
touch -t 202601010000 "$BE_HS"/requests/r-000000000000000?.json
be_comment 5 fixture-admin "approve $ID"
t_has "old requests can't use up the three looks" "$(sh "$A" note)" "$ID"
be_reset
file >/dev/null
be_comment 1 fixture-admin "approve $ID"
printf 500 > "$BE_ST/force"
t_eq "GitHub down, the note stays silent and exits 0" 0 "$(be_rc sh "$A" note)"
rm -f "$BE_ST/force"

be_down
t_done
