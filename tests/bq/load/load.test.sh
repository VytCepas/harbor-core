#!/usr/bin/env sh
# load.test.sh (harbor#1278) — bin/bq-load.sh build: the board into staged rows keyed by each laptop's random id, never a login.
# A comment counts only from its own member, with a seal; a hub rule reaches BigQuery as hub:<serial>:<index> (D6); an excluded id
# loads nothing and the merge deletes it (R12); and no login or e-mail can reach a staged file.
. "$(dirname "$0")/../../lib/core.sh"; t_init
L="$T_ROOT/bin/bq-load.sh"; X="$T_TMP/x"; OUT="$T_TMP/out"; mkdir -p "$X" "$T_TMP/agebin" "$T_TMP/pol"
# A stub age, as the sender's suite has: an age-shaped header, then the plaintext. The real cipher is age's to test.
printf '#!/bin/sh\ncase "$1" in -r) printf "age-encryption.org/v1\\n-> X25519 stub%%s\\n" "$2"; cat ;; -d) sed "1,2d" ;; esac\n' > "$T_TMP/agebin/age"
chmod +x "$T_TMP/agebin/age"; PATH="$T_TMP/agebin:$PATH"; export PATH
: > "$X/identity"
cp "$T_ROOT/tests/hub/fixtures/policy.json" "$T_TMP/pol/1.json"
A=0f1e2d3c4b5a69788796a5b4c3d2e1f0; C=aaaabbbbccccddddeeeeffff00001111
DAY=2026-11-07

# seal <id> <events json>: the heartbeat field a laptop sends
seal() { jq -cn --arg id "$1" --argjson e "$2" '{v: 1, id: $id, events: $e}' | age -r age1stub | base64 | tr -d '\n'; }
hb() { # <login> [sealed]
  jq -cn --arg m "$1" --arg s "${2:-}" '{v:1,kind:"heartbeat",ts:"2026-11-07T10:00:00Z",member:$m,core:"0123456789ab",contract:1,floor:"0123456789abcdef",serial:1,mode:"enforce",refusals:2,asks:0,requests:0,packs:["fixture-pack"]} + (if $s != "" then {sealed:$s} else {} end)'
}
ev() { jq -cn --arg m "$1" --arg r "$2" '{v:1,kind:"refusal",ts:"2026-11-07T10:00:00Z",member:$m,rule:$r,tier:"very-high",target:"cloud",count:1}'; }
act() { jq -cn --arg m "$1" --argjson n "$2" '[{v:1,kind:"activity",ts:"2026-11-07T00:00:00Z",member:$m,tool:"Bash",verb_class:"readonly",verdict:"allow",count:$n},{v:1,kind:"session",ts:"2026-11-07T00:00:00Z",member:$m,outcome:"started",count:2}]'; }
body() { jq -rn --argjson a "$1" '"```json\n" + ($a | tojson) + "\n```"'; }
comment() { jq -cn --arg a "$1" --arg t "$2" --arg b "$3" '{author: $a, created_at: $t, body: $b}'; }
board() { # the issues file as hub-fetch.sh prints it
  SA="$(seal "$A" "$(act alice 7)")"; SC="$(seal "$C" "$(act carol 3)")"
  jq -n \
    --argjson a1 "$(comment alice "${DAY}T10:13:22Z" "$(body "[$(hb alice "$SA"),$(ev alice prod-bucket),$(ev alice acme-prod-bucket)]")")" \
    --argjson a2 "$(comment alice "${DAY}T11:02:00Z" "$(body "[$(hb alice "$SA"),$(ev alice prod-bucket)]")")" \
    --argjson m1 "$(comment mallory "${DAY}T11:05:00Z" "$(body "[$(hb alice "$SA")]")")" \
    --argjson b1 "$(comment bob "${DAY}T10:30:00Z" "$(body "[$(hb bob),$(ev bob admission.key-material-egress)]")")" \
    --argjson c1 "$(comment carol "${DAY}T09:00:00Z" "$(body "[$(hb carol "$SC")]")")" \
    '[{title: "heartbeat alice", author: "alice", comments: [$a1, $a2, $m1]},
      {title: "heartbeat bob", author: "bob", comments: [$b1]},
      {title: "heartbeat carol", author: "carol", comments: [$c1]}]'
}
board > "$X/issues.json"
printf '%s\n' "$C" > "$X/excluded"
b64() { printf '%s' "$1" | xxd -r -p | base64; }
build() { _rc=0; sh "$L" build --issues "$X/issues.json" --policies "$T_TMP/pol" --identity "$X/identity" --out "$OUT" --excluded "$X/excluded" \
  --load-id 7 --now 2026-11-08T07:23:00Z > "$T_TMP/build.out" 2>&1 || _rc=$?; }

t_section "1 - only a sealed comment from its own member keys a row"
build
t_eq "build exits 0" 0 "$_rc"
t_eq "the board's comments are judged" 5 "$(jq .comments "$OUT/summary.json")"
t_eq "two are kept: alice's own, sealed" 2 "$(jq .comments_kept "$OUT/summary.json")"
t_eq "the foreign one is author-mismatch" 1 "$(jq '.refused["author-mismatch"]' "$OUT/summary.json")"
t_eq "bob, with no seal (no receipt on his laptop), is no-id" 1 "$(jq '.refused["no-id"]' "$OUT/summary.json")"
t_eq "carol, excluded, is excluded" 1 "$(jq '.refused.excluded' "$OUT/summary.json")"
t_eq "one person in the heartbeat table, by alice's id" "$(b64 "$A")" "$(jq -r -s 'map(.person_id) | unique | join(",")' "$OUT/staging/heartbeat.jsonl")"
t_eq "heartbeats at day grain: two comments, one row" "1 2 $DAY" "$(jq -r -s '"\(length) \(.[0].heartbeats) \(.[0].day)"' "$OUT/staging/heartbeat.jsonl")"
t_eq "no per-person time finer than a day is staged" 0 "$(cat "$OUT"/staging/*.jsonl | jq -s '[.[] | select(.person_id != null) | to_entries[] | select(.value | type == "string" and test("T[0-9]{2}:"))] | length')"

t_section "2 - the hub names stay on the board (D6)"
HUBCODE=1000001000
t_eq "prod-bucket, the policy's rule 0 at serial 1, as its hub code, counted per day" "$HUBCODE 2" "$(jq -r -s '[.[] | select(.rule == '"$HUBCODE"')][0] | "\(.rule) \(.count)"' "$OUT/staging/decision.jsonl")"
t_eq "a kebab client name not in the policy is refused, never coded" 1 "$(jq '.refused["not-in-set"]' "$OUT/summary.json")"
t_eq "the hub code is in the staged dim_enum" "hub:1:0" "$(jq -r -s --argjson c "$HUBCODE" '[.[] | select(.code == $c)][0].value' "$OUT/staging/dim_enum.jsonl")"
t_eq "the pack as hubpack:0" 3000000000 "$(jq -s '.[0].packs[0]' "$OUT/staging/heartbeat.jsonl")"

t_section "3 - the counts come from the seal only"
t_eq "alice's activity: 7 calls a seal, two seals" 14 "$(jq -s 'map(.calls) | add' "$OUT/staging/activity.jsonl")"
t_eq "and her session starts" 4 "$(jq -s '.[0].started' "$OUT/staging/session.jsonl")"

t_section "4 - an excluded id loads nothing and is deleted (R12)"
t_eq "no staged row carries carol's id" 0 "$(cat "$OUT"/staging/*.jsonl | grep -c "$(b64 "$C")" || true)"
_tables="$(awk -F'\t' '$2 == "person_id" { print $1 }' "$T_ROOT/contracts/bq-schema.tsv" | grep -c .)"
t_eq "the merge deletes her id from every per-person table" "$_tables" "$(grep -c "WHERE person_id IN (FROM_HEX('$C'))" "$OUT/merge.sql")"
t_has "it replaces each (source, person, day) whole" "$(cat "$OUT/merge.sql")" "s.source = t.source AND s.person_id = t.person_id AND s.day = t.day"
t_has "behind the no-STRING assertion" "$(cat "$OUT/merge.sql")" "a STRING column outside dim_"
t_has "and a code check per coded field" "$(cat "$OUT/merge.sql")" "decision.rule: a code dim_enum does not hold"

t_section "5 - no login or e-mail reaches staging"
for l in alice bob carol mallory; do
  t_eq "$l appears in no staged file" 0 "$(cat "$OUT"/staging/*.jsonl | grep -c -i "\"$l\"" || true)"
done
t_eq "no @ anywhere staged" 0 "$(cat "$OUT"/staging/*.jsonl | grep -c '@' || true)"
# the scan itself: a staged login, a staged e-mail, and base64 that merely contains a login's letters
. "$T_ROOT/bin/library-log.sh"; BQ_HERE="$T_ROOT/bin"; . "$T_ROOT/bin/library-bq.sh"
S="$T_TMP/scan"; mkdir -p "$S/staging"; printf 'alice\nbob\n' > "$S/logins"
printf '{"person_id":"ASNFZ+bob/mrze8BI0VniavN7w=="}\n' > "$S/staging/t.jsonl"
bq_identity_scan "$S" "$S/logins" && t_pass || t_fail "base64 with a login's letters inside is not a login"
printf '{"person_id":"alice"}\n' > "$S/staging/t.jsonl"
bq_identity_scan "$S" "$S/logins" && t_fail "a login as a value passed the scan" || t_pass
printf '{"count":1,"member":"x"}\n' > "$S/staging/t.jsonl"
bq_identity_scan "$S" "$S/logins" && t_fail "a member key passed the scan" || t_pass
printf '{"x":"alice@example.com"}\n' > "$S/staging/t.jsonl"
bq_identity_scan "$S" "$S/logins" && t_fail "an e-mail passed the scan" || t_pass
# end to end: a staging step that leaks the login, as a defect would, must stop the build with nothing staged
M="$T_TMP/mutant"; mkdir -p "$M"; cp "$T_ROOT/bin/"*.sh "$M/"; mkdir -p "$T_TMP/contracts"; cp "$T_ROOT/contracts/bq-schema.tsv" "$T_ROOT/contracts/bq-values.tsv" "$T_ROOT/contracts/hub-vocabulary.tsv" "$T_TMP/contracts/"
ln -s "$T_TMP/contracts" "$T_TMP/mutant/../contracts" 2>/dev/null || :
awk '{ print } /^    _bsk="\$\(grep -c \. "\$1\/\$2.kept.jsonl"/ { print "    printf '"'"'{\"member\":\"alice\"}\\n'"'"' >> \"$1/staging/$2.jsonl\"" }' "$T_ROOT/bin/library-bq.sh" > "$M/library-bq.sh"
t_eq "the mutant differs in that one line" 1 "$(diff "$T_ROOT/bin/library-bq.sh" "$M/library-bq.sh" | grep -c '^>')"
_rc=0; sh "$M/bq-load.sh" build --issues "$X/issues.json" --policies "$T_TMP/pol" --identity "$X/identity" --out "$T_TMP/mout" --excluded "$X/excluded" \
  --load-id 7 --now 2026-11-08T07:23:00Z > "$T_TMP/m.out" 2>&1 || _rc=$?
t_eq "a login in staging stops the build" 1 "$_rc"
t_eq "...with nothing staged" no "$([ -d "$T_TMP/mout/staging" ] && echo yes || echo no)"

t_section "6 - refusals before any judgement"
_rc=0; sh "$L" build --issues "$X/none.json" --policies "$T_TMP/pol" --identity "$X/identity" --out "$OUT" > /dev/null 2>&1 || _rc=$?
t_eq "an unreadable board is unchecked, 3" 3 "$_rc"
t_done
