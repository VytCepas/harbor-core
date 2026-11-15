#!/usr/bin/env sh
# send.test.sh (harbor#1278) — hub-events.sh send: one closed comment per send on the member's heartbeat issue, survives a noisy
# session (R20), and leaves a board on which silence, a dead token and a removed floor read differently (F30).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
be_up
E="$BE_BIN/hub-events.sh"; O="$BE_HS/outbox.jsonl"; P="$BE_HS/outbox.pending.jsonl"
comment_posts() { be_log_count '.method == "POST" and (.path | endswith("/comments"))'; }
last_batch() { # the array in the newest comment of issue <n>
  jq -r '.[-1].body' "$BE_ST/comments/${1:-1}.json" | sed -e '1d' -e '$d'
}
due() { rm -f "$BE_HS/last-send"; }

t_section "1 - one comment, one fenced json block, on the member's own issue"
be_reset
sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1
sh "$E" record ask rule=prod-bucket tier=high target=cloud outcome=proceeded count=1
t_eq "send is exit 0" 0 "$(be_rc sh "$E" send)"
t_eq "the issue title" 'heartbeat alice' "$(jq -r .title "$BE_ST/issues/1.json")"
t_eq "the comment is one fence" '```json' "$(jq -r '.[0].body' "$BE_ST/comments/1.json" | head -n 1)"
t_eq "closed by one fence" '```' "$(jq -r '.[0].body' "$BE_ST/comments/1.json" | tail -n 1)"
last_batch > "$T_TMP/batch.json"
t_eq "the batch passes the format" 0 "$(be_rc sh "$BE_BIN/hub-format.sh" event "$T_TMP/batch.json")"
t_eq "a heartbeat leads it" heartbeat "$(jq -r '.[0].kind' "$T_TMP/batch.json")"
t_eq "with the batch's counts" '1 1 0' "$(jq -r '.[0] | "\(.refusals) \(.asks) \(.requests)"' "$T_TMP/batch.json")"
t_eq "and the floor hash" 0123456789abcdef "$(jq -r '.[0].floor' "$T_TMP/batch.json")"
t_eq "and the policy's facts" '0123456789ab 1 shadow' "$(jq -r '.[0] | "\(.core) \(.serial) \(.mode)"' "$T_TMP/batch.json")"
t_eq "and hub pack ids from the policy, never a member's name" fixture-pack "$(jq -r '.[0].packs | join(",")' "$T_TMP/batch.json")"
t_eq "the outbox is empty after" no "$([ -s "$O" ] && echo yes || echo no)"
t_eq "and nothing is pending" no "$([ -s "$P" ] && echo yes || echo no)"
t_eq "no @ in anything sent, so no mail" 0 "$(jq -r '.[0].body' "$BE_ST/comments/1.json" | grep -c '@' || :)"
due
sh "$E" send
t_eq "the cached issue is reused" 1 "$(be_log_count '.method == "POST" and (.path | endswith("/issues"))')"
t_eq "an empty outbox still beats" 2 "$(comment_posts)"

be_reset
sh "$E" record heartbeat core=0123456789ab contract=1 floor=ffffffffffffffff serial=1 mode=shadow refusals=0 asks=0 requests=0 packs=
sh "$E" send
t_eq "one heartbeat per comment, the sender's own" '1 0123456789abcdef' "$(last_batch | jq -r '[.[] | select(.kind == "heartbeat")] | "\(length) \(.[0].floor)"')"

t_section "2 - the issue is found, not guessed"
be_reset
sh "$E" send
rm -f "$BE_HS/heartbeat-issue"; due
sh "$E" send
t_eq "a lost cache finds the issue on the board" 1 "$(be_log_count '.method == "POST" and (.path | endswith("/issues"))')"
due; printf '99\n' > "$BE_HS/heartbeat-issue"
sh "$E" send
t_eq "a stale cache finds it too" 1 "$(be_log_count '.method == "POST" and (.path | endswith("/issues"))')"
t_eq "and is repaired" 1 "$(cat "$BE_HS/heartbeat-issue")"
due; N="$(be_seed_issue r-0123456789abcdef)"; printf '%s\n' "$N" > "$BE_HS/heartbeat-issue"
sh "$E" send
t_eq "a cache pointing at another issue posts nothing there" 0 "$(jq length "$BE_ST/comments/$N.json")"

t_section "3 - a noisy session costs one comment (R20)"
be_reset
i=0
while [ "$i" -lt 40 ]; do sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1; i=$((i + 1)); done
awk 'BEGIN { for (i = 0; i < 3000; i++) print "{\"v\":1,\"kind\":\"ask\",\"ts\":\"2026-11-07T10:00:00Z\",\"member\":\"alice\",\"rule\":\"prod-bucket\",\"tier\":\"high\",\"target\":\"cloud\",\"outcome\":\"not-run\",\"count\":1}" }' >> "$O"
sh "$E" send
t_eq "one comment" 1 "$(comment_posts)"
last_batch > "$T_TMP/batch.json"
t_eq "the refusals folded" 40 "$(jq '[.[] | select(.kind == "refusal")][0].count' "$T_TMP/batch.json")"
t_eq "the asks folded" 3000 "$(jq '[.[] | select(.kind == "ask")][0].count' "$T_TMP/batch.json")"
t_eq "the heartbeat counts them" '40 3000' "$(jq -r '.[0] | "\(.refusals) \(.asks)"' "$T_TMP/batch.json")"
t_eq "three events in all" 3 "$(jq length "$T_TMP/batch.json")"
sh "$E" record check check=floor-integrity outcome=passed
sh "$E" send
t_eq "a second send inside the interval posts nothing" 1 "$(comment_posts)"
t_eq "and keeps the record" yes "$([ -s "$O" ] && echo yes || echo no)"
due; printf '9999999999\n' > "$BE_HS/last-send"
sh "$E" send
t_eq "a last-send in the future can't silence the sender" 2 "$(comment_posts)"

t_section "4 - a batch stays inside a comment"
be_reset
awk 'BEGIN { for (i = 0; i < 400; i++) printf "{\"v\":1,\"kind\":\"refusal\",\"ts\":\"2026-11-07T10:00:00Z\",\"member\":\"alice\",\"rule\":\"rule-%d-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"tier\":\"very-high\",\"target\":\"command\",\"count\":1}\n", i }' > "$T_TMP/many"
mkdir -p "$BE_HS"; cp "$T_TMP/many" "$O"
sh "$E" send
t_eq "one comment" 1 "$(comment_posts)"
size="$(jq -r '.[0].body' "$BE_ST/comments/1.json" | wc -c | tr -d ' ')"
[ "$size" -lt 65536 ] && t_pass || t_fail "a comment of $size characters"
t_eq "250 events went" 250 "$(last_batch | jq length)"
t_eq "the rest wait" 151 "$(wc -l < "$P" | tr -d ' ')"
due
sh "$E" send
t_eq "and go next" 152 "$(last_batch | jq length)"
t_eq "none left" no "$([ -s "$P" ] && echo yes || echo no)"

t_section "5 - a tampered outbox doesn't reach the board (F29)"
be_reset
sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1
printf 'not json at all: the client list\n' >> "$O"
printf '%s\n' '{"v":1,"kind":"refusal","ts":"2026-11-07T10:00:00Z","member":"alice","rule":"admission.rm-root","tier":"very-high","target":"command","count":1,"note":"the client said"}' >> "$O"
printf '%s\n' '{"v":1,"kind":"refusal","ts":"2026-11-07T10:13:22Z","member":"alice","rule":"exact-time","tier":"very-high","target":"command","count":1}' >> "$O"
printf '%s\n' '{"v":1,"kind":"check","ts":"2026-11-07T10:00:00Z","member":"bob","check":"forged","outcome":"passed"}' >> "$O"
sh "$E" send
body="$(jq -r '.[-1].body' "$BE_ST/comments/1.json")"
t_hasnt "prose stays out" "$body" 'client'
t_hasnt "an exact time stays out" "$body" 'exact-time'
t_hasnt "another member's event stays out" "$body" 'forged'
t_has "the good record went" "$body" 'admission.rm-root'
t_has "and the drops are reported by a count, not a value" "$body" 'hub-events-dropped'
due
sh "$E" send
t_hasnt "reported once" "$(jq -r '.[-1].body' "$BE_ST/comments/1.json")" 'hub-events-dropped'

t_section "6 - nothing is lost when GitHub is down"
be_reset
sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1
printf 500 > "$BE_ST/force"
t_eq "a 500 is exit 3" 3 "$(be_rc sh "$E" send)"
t_eq "and the outbox is untouched" 1 "$(wc -l < "$O" | tr -d ' ')"
rm -f "$BE_ST/force"
sh "$E" send
printf 500 > "$BE_ST/force-post"
sh "$E" record ask rule=prod-bucket tier=high target=cloud outcome=proceeded count=1
due
t_eq "a failed post is exit 3" 3 "$(be_rc sh "$E" send)"
t_eq "the batch waits" 1 "$(wc -l < "$P" | tr -d ' ')"
t_eq "no heartbeat kept in it" 0 "$(jq -s 'map(select(.kind == "heartbeat")) | length' "$P")"
t_eq "and the interval didn't start" no "$([ -e "$BE_HS/last-send" ] && echo yes || echo no)"
rm -f "$BE_ST/force-post"
t_eq "the next send delivers" 0 "$(be_rc sh "$E" send)"
t_has "it arrived" "$(jq -r '.[-1].body' "$BE_ST/comments/1.json")" 'prod-bucket'
be_reset
sh "$E" send
due
awk 'BEGIN { for (i = 0; i < 2100; i++) printf "{\"v\":1,\"kind\":\"refusal\",\"ts\":\"2026-11-07T10:00:00Z\",\"member\":\"alice\",\"rule\":\"rule-%d\",\"tier\":\"very-high\",\"target\":\"command\",\"count\":1}\n", i }' > "$O"
printf 500 > "$BE_ST/force-post"
sh "$E" send 2>/dev/null || :
rm -f "$BE_ST/force-post"
t_eq "a long outage is capped" 2000 "$(wc -l < "$P" | tr -d ' ')"
t_eq "and the overflow is counted" 100 "$(wc -c < "$BE_HS/dropped" | tr -d ' ')"

t_section "7 - token expiry is told apart from silence (F25, R20)"
be_reset
printf '2026-11-13 12:00:00 UTC' > "$BE_ST/expires"
sh "$E" send
sh "$E" send
last_batch > "$T_TMP/batch.json"
t_eq "days left from GitHub's headers" '6 expiring' "$(jq -r '.[] | select(.kind == "token") | "\(.days_left) \(.outcome)"' "$T_TMP/batch.json")"
t_eq "kept for the session note" 6 "$(cat "$BE_HS/token-days-left")"
be_reset
printf '2027-06-01 12:00:00 UTC' > "$BE_ST/expires"
sh "$E" send
t_eq "far off, no token event" 0 "$(last_batch | jq '[.[] | select(.kind == "token")] | length')"
t_eq "and no note" no "$([ -e "$BE_HS/token-days-left" ] && echo yes || echo no)"
be_reset
printf 'not a time' > "$BE_ST/expires"
sh "$E" send
t_eq "an expiry it can't read raises nothing" 0 "$(last_batch | jq '[.[] | select(.kind == "token")] | length')"
be_reset
sh "$E" send
due
printf wrong > "$BE_ST/token"
sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1
t_eq "a dead token is exit 3" 3 "$(be_rc sh "$E" send)"
t_eq "the laptop knows why" token-expired "$(cat "$BE_HS/board-state")"
t_eq "nothing reached the board" 1 "$(jq length "$BE_ST/comments/1.json")"
printf '%s' "$BE_TOKEN" > "$BE_ST/token"
sh "$E" send
t_has "the new token delivers the gap" "$(jq -r '.[-1].body' "$BE_ST/comments/1.json")" 'expired-token'
t_has "and what piled up" "$(jq -r '.[-1].body' "$BE_ST/comments/1.json")" 'admission.rm-root'
t_eq "and the state clears" ok "$(cat "$BE_HS/board-state")"

t_section "8 - a floor that isn't answering says so"
be_reset
mv "$BE_BIN/member-integrity.sh" "$T_TMP/integrity.keep"
sh "$E" send
t_eq "no integrity tool reads as a zero hash, never a pass" 0000000000000000 "$(last_batch | jq -r '.[0].floor')"
mv "$T_TMP/integrity.keep" "$BE_BIN/member-integrity.sh"
be_reset
be_stub_sibling hub-sync.sh 'exit 0'
sh "$E" send
t_eq "no policy reads as serial 0 on the core defaults" '0 enforce 000000000000' "$(last_batch | jq -r '.[0] | "\(.serial) \(.mode) \(.core)"')"
be_stub_sibling hub-sync.sh "[ \"\$1\" = path ] && printf '%s\\n' '$T_TMP/state-policy.json'; exit 0"

t_section "9 - a silent fixture member shows through what is recorded"
# silent_days 5, the fixture policy. The reader is what a digest does: last comment by GitHub's clock, then the last token event.
be_reset
member() { # <login> <rfc1123 date> [token expiry]
  rm -rf "$BE_HS"
  printf '%s\n' "$1" > "$BE_ST/login"
  printf '%s\n' "$2" > "$BE_ST/date"
  if [ -n "${3:-}" ]; then printf '%s' "$3" > "$BE_ST/expires"; else rm -f "$BE_ST/expires"; fi
  HARBOR_MEMBER_LOGIN="$1" sh "$E" send
}
member alice 'Sat, 07 Nov 2026 09:00:00 GMT'
member bob 'Tue, 27 Oct 2026 09:00:00 GMT'
member carol 'Tue, 27 Oct 2026 09:00:00 GMT' '2026-10-28 09:00:00 UTC'
printf 'Sat, 07 Nov 2026 12:00:00 GMT\n' > "$BE_ST/date"
now="$(jq -rn '"2026-11-07T12:00:00Z" | fromdateiso8601')"
for f in "$BE_ST"/issues/*.json; do
  n="$(jq -r .number "$f")"
  jq -r --argjson now "$now" --arg who "$(jq -r '.title | sub("heartbeat "; "")' "$f")" '
    .[-1] as $c | ($c.body | split("\n")[1:-1] | join("") | fromjson) as $b
    | (($now - ($c.created_at | fromdateiso8601)) / 86400) as $age
    | [$b[] | select(.kind == "token")][-1] as $t
    | $who + " " + (if $age < 5 then "seen"
        elif $t != null and $t.days_left < $age then "token-ended"
        else "silent" end)' "$BE_ST/comments/$n.json"
done | sort > "$T_TMP/seen"
t_eq "a live member reads as seen" 'alice seen' "$(sed -n 1p "$T_TMP/seen")"
t_eq "a silent member shows" 'bob silent' "$(sed -n 2p "$T_TMP/seen")"
t_eq "a member whose token ran out isn't called silent" 'carol token-ended' "$(sed -n 3p "$T_TMP/seen")"

t_section "10 - the id and the counts travel sealed, never in clear (Log scope level 2, legal/dpia.md R10, R11)"
# A stub age: an age-shaped header, then the plaintext. Enough to read back what was sealed; the real cipher is age's to test.
mkdir -p "$T_TMP/agebin"
printf '#!/bin/sh\ncase "$1" in -r) printf "age-encryption.org/v1\\n-> X25519 stub%%s\\n" "$2"; cat ;; -d) sed "1,2d" ;; esac\n' > "$T_TMP/agebin/age"
chmod +x "$T_TMP/agebin/age"
REC="age1$(printf '%058d' 0 | tr 0 q)"
LID="0f1e2d3c4b5a69788796a5b4c3d2e1f0"
mkdir -p "$T_TMP/harbor-ids"; printf '%s\n' "$LID" > "$T_TMP/harbor-ids/$(id -un).id"
be_policy ".approval.ttl_hours = 24 | .logs = {recipient: \"$REC\"}"
counts() { # record the fixture's counts
  i=0; while [ "$i" -lt 5 ]; do sh "$E" record activity tool=Bash verb_class=readonly verdict=allow count=1; i=$((i + 1)); done
  sh "$E" record activity tool=Read verb_class=na verdict=deny count=1
  sh "$E" record session outcome=started count=1
  sh "$E" record session outcome=started count=1
}
unseal() { jq -r '.[0].sealed' "$T_TMP/batch.json" | base64 -d | sed '1,2d'; }
be_reset; : > "$BE_ROOT/notice-received"
counts
PATH="$T_TMP/agebin:$PATH" sh "$E" send
last_batch > "$T_TMP/batch.json"
_body="$(jq -r '.[-1].body' "$BE_ST/comments/1.json")"
t_eq "no activity or session event in clear" 0 "$(jq '[.[] | select(.kind == "activity" or .kind == "session")] | length' "$T_TMP/batch.json")"
t_hasnt "the id is nowhere in the comment" "$_body" "$LID"
t_eq "the heartbeat is sealed" true "$(jq '.[0] | has("sealed")' "$T_TMP/batch.json")"
t_eq "the comment passes the board format" 0 "$(be_rc sh "$BE_BIN/hub-format.sh" board "$T_TMP/batch.json")"
t_eq "sealed: the id" "$LID" "$(unseal | jq -r .id)"
t_eq "sealed: the counts, folded per tool, class and verdict" "5 1 2" "$(unseal | jq -r '[(.events[] | select(.verb_class == "readonly") | .count), (.events[] | select(.tool == "Read") | .count), (.events[] | select(.kind == "session") | .count)] | map(tostring) | join(" ")')"
t_eq "the tally is emptied by the send" no "$([ -s "$BE_HS/tally.jsonl" ] && echo yes || echo no)"
t_eq "and nothing is left pending" 0 "$(jq -s '[.[] | select(.kind == "activity" or .kind == "session")] | length' "$P" 2>/dev/null || echo 0)"
# a clear count on the board is refused by the board format, so the sender's gate drops it
jq -c '. + [{v: 1, kind: "activity", ts: "2026-11-07T00:00:00Z", member: "alice", tool: "Bash", verb_class: "readonly", verdict: "allow", count: 3}]' "$T_TMP/batch.json" > "$T_TMP/clear.json"
t_eq "the board format refuses a count in clear" 1 "$(be_rc sh "$BE_BIN/hub-format.sh" board "$T_TMP/clear.json")"
jq -c --arg id "$LID" '.[0].sealed = $id | [.[0]]' "$T_TMP/batch.json" > "$T_TMP/clear.json"
t_eq "and an id in clear where the seal goes" 1 "$(be_rc sh "$BE_BIN/hub-format.sh" board "$T_TMP/clear.json")"

t_section "11 - no receipt marker: no counts kept, nothing sealed (R11)"
be_reset; rm -f "$BE_ROOT/notice-received"
counts
t_eq "no tally is kept" no "$([ -s "$BE_HS/tally.jsonl" ] && echo yes || echo no)"
t_eq "and that is not a drop" 0 "$(if [ -f "$BE_HS/dropped" ]; then wc -c < "$BE_HS/dropped" | tr -d ' '; else echo 0; fi)"
PATH="$T_TMP/agebin:$PATH" sh "$E" send
last_batch > "$T_TMP/batch.json"
t_eq "the heartbeat carries no seal" false "$(jq '.[0] | has("sealed")' "$T_TMP/batch.json")"
t_hasnt "and no id" "$(jq -r '.[-1].body' "$BE_ST/comments/1.json")" "$LID"
t_has "the release-1 events still go (D8)" "$(jq -r '.[0].kind' "$T_TMP/batch.json")" "heartbeat"

t_section "12 - a marker but no way to seal: said by a fixed word, the counts kept"
be_reset; : > "$BE_ROOT/notice-received"
counts
sh "$E" send   # no age on PATH
last_batch > "$T_TMP/batch.json"
t_eq "no seal" false "$(jq '.[0] | has("sealed")' "$T_TMP/batch.json")"
t_eq "a hub-logs-seal check says so" 1 "$(jq '[.[] | select(.kind == "check" and .check == "hub-logs-seal")] | length' "$T_TMP/batch.json")"
t_eq "the counts wait in pending" 3 "$(jq -s '[.[] | select(.kind == "activity" or .kind == "session")] | length' "$P")"
rm -f "$BE_ROOT/notice-received"

be_down
t_done
