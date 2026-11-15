#!/usr/bin/env sh
# conditions.test.sh (harbor#1278) — hub-approval.sh status against each numbered condition of contracts/hub.md, "The board".
# Each case changes one fact of an approval that otherwise passes, so a red here names the condition that moved.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
be_up
A="$BE_BIN/hub-approval.sh"; ID="$BE_ID"
status() { be_rc sh "$A" status "${1:-$ID}"; }
# fresh [comment args]: a clean board, one valid open issue and an approve comment, as asked
fresh() {
  be_reset
  be_policy '.approval.ttl_hours = 24'
  N="$(be_seed_issue "$ID")"
  [ $# = 0 ] || be_comment "$N" "$@"
}
APPROVE="approve $ID"

t_section "0 - the baseline passes, or every refusal below proves nothing"
fresh fixture-admin "$APPROVE"
t_eq "a real admin's comment approves" 0 "$(status)"
fresh
t_eq "no comment at all is not approved" 1 "$(status)"
be_reset
t_eq "no issue is not approved" 1 "$(status)"

t_section "1 - the author: GitHub's record, signed approvers, not the member, a User"
fresh alice "$APPROVE"
t_eq "a member-authored approve is refused" 1 "$(status)"
fresh alice "$APPROVE"; be_policy '.approval.approvers += ["alice"]'
t_eq "even when the member is on the signed list" 1 "$(status)"
fresh ALICE "$APPROVE"; be_policy '.approval.approvers += ["alice"]'
t_eq "and logins compare without case" 1 "$(status)"
fresh someone-else "$APPROVE"
t_eq "an author off the list is refused" 1 "$(status)"
fresh Fixture-Admin "$APPROVE"
t_eq "GitHub's casing of an approver still counts" 0 "$(status)"
fresh fixture-admin "$APPROVE" 2026-11-07T10:00:00Z 2026-11-07T10:00:00Z Bot
t_eq "a bot is refused" 1 "$(status)"
fresh someone-else "$APPROVE"
jq '.approval.approvers += ["someone-else"]' "$T_TMP/state-policy.json" > "$T_TMP/p" && cp "$T_TMP/p" "$T_TMP/state-policy.json"
printf '404' > "$BE_ST/perm-default"
t_eq "an approver added after signing is refused, even with the endpoint silent" 1 "$(status)"
fresh fixture-admin "$APPROVE"; rm -f "$T_TMP/state-policy.json.sig"
t_eq "a policy with no signature approves nothing" 1 "$(status)"
fresh fixture-admin "$APPROVE"; cp "$BE_ROOT/hub-signers" "$T_TMP/signers.keep"
ssh-keygen -t ed25519 -q -N '' -C other -f "$T_TMP/signing/other"
printf 'hub %s\n' "$(cut -d' ' -f1,2 "$T_TMP/signing/other.pub")" > "$BE_ROOT/hub-signers"
t_eq "a policy signed by another key approves nothing" 1 "$(status)"
cp "$T_TMP/signers.keep" "$BE_ROOT/hub-signers"

t_section "2 - the permission endpoint and its fallback (both branches, a real token still has to say which it gets)"
perm() { fresh fixture-admin "$APPROVE"; printf '%s' "$1" > "$BE_ST/perm/fixture-admin"; status; }
t_eq "200 admin" 0 "$(perm '200 admin')"
t_eq "200 maintain" 0 "$(perm '200 maintain')"
t_eq "200 write" 0 "$(perm '200 write')"
t_eq "200 read denies, whatever the list says" 1 "$(perm '200 read')"
t_eq "200 none denies" 1 "$(perm '200 none')"
t_eq "200 with no permission field denies" 1 "$(perm '200 ')"
t_eq "403 for this token: the signed list decides" 0 "$(perm '403')"
t_eq "404 for this token: the signed list decides" 0 "$(perm '404')"
fresh someone-else "$APPROVE"; printf '403' > "$BE_ST/perm/someone-else"
t_eq "and the list still refuses a non-approver on that branch" 1 "$(status)"
t_eq "422 denies" 1 "$(perm '422')"
t_eq "500 denies" 3 "$(perm '500')"
t_eq "a rate-limited 403 isn't a refusal, so the list doesn't decide" 3 "$(perm '403 limited')"

t_section "3 - never edited"
fresh fixture-admin "$APPROVE" 2026-11-07T10:00:00Z 2026-11-07T10:00:01Z
t_eq "an edited comment is refused" 1 "$(status)"

t_section "4 - expiry against the response's Date header, never the laptop"
at() { printf '%s\n' "$1" > "$BE_ST/date"; status; }
fresh fixture-admin "$APPROVE"
t_eq "a second before ttl" 0 "$(at 'Sun, 08 Nov 2026 09:59:59 GMT')"
t_eq "at ttl exactly" 1 "$(at 'Sun, 08 Nov 2026 10:00:00 GMT')"
fresh fixture-admin "$APPROVE"
touch "$BE_ST/nodate"
t_eq "no Date header denies" 1 "$(status)"
rm -f "$BE_ST/nodate"
printf 'not a date\n' > "$BE_ST/date"
t_eq "a bad Date header denies" 1 "$(status)"
# The laptop says it's the comment's own minute, the server says a year on: the server wins, and the reverse. Its own PATH
# entry: the suite watchdog reads `date` too, and a fake one on $T_BIN trips the hard timeout.
mkdir -p "$T_TMP/clock"
printf '#!/bin/sh\nprintf "1794045600\\n"\n' > "$T_TMP/clock/date"; chmod +x "$T_TMP/clock/date"
fresh fixture-admin "$APPROVE"
t_eq "a laptop clock set back doesn't revive it" 1 "$(PATH="$T_TMP/clock:$PATH"; at 'Sun, 07 Nov 2027 10:00:00 GMT')"
printf '#!/bin/sh\nprintf "4102444800\\n"\n' > "$T_TMP/clock/date"
fresh fixture-admin "$APPROVE"
t_eq "a laptop clock set forward doesn't expire it" 0 "$(PATH="$T_TMP/clock:$PATH"; at 'Sat, 07 Nov 2026 12:00:00 GMT')"
fresh fixture-admin "$APPROVE"
printf '{"id":"%s","issue":%s,"rule":"prod-bucket","tier":"very-high","target":"cloud","label":"Touches the production bucket"}\n' "$ID" "$N" > "$T_TMP/rec"
mkdir -p "$BE_HS/requests"; cp "$T_TMP/rec" "$BE_HS/requests/$ID.json"
at 'Sun, 08 Nov 2026 10:00:00 GMT' >/dev/null
at 'Sun, 08 Nov 2026 10:00:00 GMT' >/dev/null
t_eq "a lapse is told to the board once" 1 "$(jq -s 'map(select(.outcome == "expired")) | length' "$BE_HS/outbox.jsonl")"

t_section "5 - the issue is open and its body's id matches"
fresh; jq '.state = "closed"' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
be_comment "$N" fixture-admin "$APPROVE"
t_eq "a closed issue approves nothing" 1 "$(status)"
OTHER=r-fedcba9876543210
fresh; jq --arg b "$(be_issue_body "$OTHER")" '.body = $b' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
be_comment "$N" fixture-admin "$APPROVE"
t_eq "a body naming another id" 1 "$(status)"
fresh; jq --arg b "$(be_issue_body "$ID")
and some prose" '.body = $b' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
be_comment "$N" fixture-admin "$APPROVE"
t_eq "a body with added prose" 1 "$(status)"
fresh; jq --arg b "$(be_issue_body "$ID" bob)" '.body = $b' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
be_comment "$N" fixture-admin "$APPROVE"
t_eq "a body naming another member" 1 "$(status)"
fresh; jq '.user.login = "bob"' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
be_comment "$N" fixture-admin "$APPROVE"
# The record reaches it directly: the creator filter on the list would hide it, and test nothing.
mkdir -p "$BE_HS/requests"; printf '{"id":"%s","issue":%s}\n' "$ID" "$N" > "$BE_HS/requests/$ID.json"
t_eq "an issue someone else opened" 1 "$(status)"

t_section "the comment's whole body, trimmed, is the approval (M8)"
body() { fresh fixture-admin "$1"; status; }
t_eq "padded with whitespace" 0 "$(body "
  $APPROVE

")"
t_eq "a quoted line" 1 "$(body "> $APPROVE")"
t_eq "a quote and a reply" 1 "$(body "> $APPROVE

not this one")"
t_eq "the line among others" 1 "$(body "$APPROVE
thanks")"
t_eq "in a sentence" 1 "$(body "please $APPROVE")"
t_eq "another case" 1 "$(body "Approve $ID")"
t_eq "another id" 1 "$(body "approve r-fedcba9876543210")"
t_eq "no id" 1 "$(body approve)"
fresh; jq '.labels = [{name: "approved"}]' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
t_eq "a label never counts" 1 "$(status)"

t_section "a changed call gets a new id, and the old approval doesn't reach it"
. "$T_ROOT/bin/library-hub.sh"
C1='{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"gsutil rm gs://prod-a/x"}}'
C2='{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"gsutil rm gs://prod-a/y"}}'
I1="$(hub_request_id "$(hub_canon "$C1" alice)" salt)"; I2="$(hub_request_id "$(hub_canon "$C2" alice)" salt)"
[ "$I1" != "$I2" ] && t_pass || t_fail "a changed command kept its id"
be_reset; N="$(be_seed_issue "$I1")"; be_comment "$N" fixture-admin "approve $I1"
t_eq "the approved call passes" 0 "$(status "$I1")"
t_eq "the changed call doesn't" 1 "$(status "$I2")"

t_section "tampered local state can't move an approval (F6)"
be_reset; N1="$(be_seed_issue "$I1")"; be_comment "$N1" fixture-admin "approve $I1"; N2="$(be_seed_issue "$I2")"
mkdir -p "$BE_HS/requests"
printf '{"id":"%s","issue":%s}\n' "$I2" "$N1" > "$BE_HS/requests/$I2.json"
t_eq "a record pointing the new id at an approved issue" 1 "$(status "$I2")"
mkdir -p "$BE_HS/requests/x"
t_eq "an id that isn't one is refused before any path is built" 1 "$(be_rc sh "$A" status '../../etc/passwd')"

t_section "GitHub down keeps the call denied"
fresh fixture-admin "$APPROVE"
printf 500 > "$BE_ST/force"
t_eq "a 500 is unreachable" 3 "$(status)"
rm -f "$BE_ST/force"
UP="$HARBOR_HUB_API_BASE"; HARBOR_HUB_API_BASE=http://127.0.0.1:9
t_eq "no connection is unreachable" 3 "$(status)"
HARBOR_HUB_API_BASE="$UP"
printf wrong > "$BE_ST/token"
t_eq "a dead token stays denied" 3 "$(status)"
printf '%s' "$BE_TOKEN" > "$BE_ST/token"
t_eq "and the same approval passes once GitHub answers" 0 "$(status)"
t_eq "no token at all is denied" 3 "$(BE_TOKEN_VALUE='' be_rc sh "$A" status "$ID")"

t_section "consumed once"
fresh fixture-admin "$APPROVE"
printf '{"id":"%s","issue":%s,"rule":"prod-bucket","tier":"very-high","target":"cloud","label":"Touches the production bucket"}\n' "$ID" "$N" > "$T_TMP/rec"
mkdir -p "$BE_HS/requests"; cp "$T_TMP/rec" "$BE_HS/requests/$ID.json"
t_eq "approved" 0 "$(status)"
t_eq "consume exits 0" 0 "$(be_rc sh "$A" consume "$ID")"
t_eq "the mark names the comment" "$(jq -r '.[0].id' "$BE_ST/comments/$N.json")" "$(cat "$BE_HS/used/$ID")"
t_eq "it comments used" "used $ID" "$(jq -r '.[-1].body' "$BE_ST/comments/$N.json")"
t_eq "it closes the issue" closed "$(jq -r .state "$BE_ST/issues/$N.json")"
t_eq "a second retry is denied" 1 "$(status)"
rm -rf "$BE_HS/used"
t_eq "and stays denied with the local mark gone, as the issue is closed" 1 "$(status)"
fresh fixture-admin "$APPROVE"; cp "$T_TMP/rec" "$BE_HS/requests/$ID.json" 2>/dev/null || { mkdir -p "$BE_HS/requests"; cp "$T_TMP/rec" "$BE_HS/requests/$ID.json"; }
status >/dev/null; sh "$A" consume "$ID"
jq '.state = "open"' "$BE_ST/issues/$N.json" > "$T_TMP/i" && cp "$T_TMP/i" "$BE_ST/issues/$N.json"
t_eq "a reopened issue doesn't revive a used comment" 1 "$(status)"
be_comment "$N" fixture-admin "$APPROVE" 2026-11-07T11:00:00Z
t_eq "a fresh comment on it does" 0 "$(status)"
t_eq "the events say approved and used" "approved used" "$(jq -r 'select(.kind == "request") | .outcome' "$BE_HS/outbox.jsonl" | sort -u | tr '\n' ' ' | sed 's/ $//')"
fresh fixture-admin "$APPROVE"; mkdir -p "$BE_HS/requests"; cp "$T_TMP/rec" "$BE_HS/requests/$ID.json"
status >/dev/null; printf 500 > "$BE_ST/force"
t_eq "consume never fails the hook, GitHub down" 0 "$(be_rc sh "$A" consume "$ID")"
t_eq "and the mark still holds it" 1 "$(rm -f "$BE_ST/force"; status)"
t_eq "consume of a bad id is still exit 0" 0 "$(be_rc sh "$A" consume nonsense)"

fresh fixture-admin "$APPROVE"
status >/dev/null; sh "$A" consume "$ID"
t_eq "a lost local record still closes the right issue" closed "$(jq -r .state "$BE_ST/issues/$N.json")"
fresh fixture-admin "$APPROVE"; N2="$(be_seed_issue r-fedcba9876543210)"
mkdir -p "$BE_HS/requests"; printf '{"id":"%s","issue":%s}\n' "$ID" "$N2" > "$BE_HS/requests/$ID.json"
status >/dev/null; sh "$A" consume "$ID"
t_eq "a moved local record closes the verified issue" closed "$(jq -r .state "$BE_ST/issues/$N.json")"
t_eq "and not the one it pointed at" open "$(jq -r .state "$BE_ST/issues/$N2.json")"

t_section "a 200 at the end of the hour's quota is still an answer"
fresh fixture-admin "$APPROVE"; touch "$BE_ST/remaining0"
t_eq "approved" 0 "$(status)"

t_section "standalone never reaches the board"
fresh fixture-admin "$APPROVE"
n0="$(jq -s length "$BE_ST/log.jsonl" 2>/dev/null || echo 0)"
t_eq "no member role, no approval" 1 "$(HARBOR_MEMBER_ROLE='' status)"
t_eq "and no call" "$n0" "$(jq -s length "$BE_ST/log.jsonl" 2>/dev/null || echo 0)"
t_eq "no member login, no approval" 1 "$(HARBOR_MEMBER_LOGIN='' status)"

be_down
t_done
