#!/usr/bin/env sh
# digest.test.sh (harbor#1278) — bin/hub-digest.sh over fixture heartbeat issues, no network: per member last seen, version, floor hash,
# refusals and requests; silent members at silent_days; a digest on EVERY run, empty included (R19); and nothing outside the closed
# vocabulary ever reaches the output, whoever wrote the comment.
. "$(dirname "$0")/../../lib/core.sh"; t_init
D="$T_ROOT/bin/hub-digest.sh"; POL="$T_ROOT/tests/hub/fixtures/policy.json"; NOW="2026-11-12T09:00:00Z"
B='```'
# hb <login> <serial> <refusals> <requests> [extra jq edit]: an event array holding one heartbeat
hb() { jq -c -n --arg m "$1" --argjson s "$2" --argjson r "$3" --argjson q "$4" \
  '[{v:1,kind:"heartbeat",ts:"2026-11-07T08:00:00Z",member:$m,core:"0123456789ab",contract:1,floor:"0123456789abcdef",serial:$s,mode:"shadow",refusals:$r,asks:3,requests:$q,packs:["fixture-pack"]}] | '"${5:-.}"; }
# cm <author> <created_at> <events>: one comment
cm() { jq -n --arg a "$1" --arg t "$2" --arg e "$3" --arg b "$B" '{author:$a, created_at:$t, body:($b + "json\n" + $e + "\n" + $b)}'; }
# issue <title> <author> <comment>...
issue() { _t="$1"; _a="$2"; shift 2; printf '%s\n' "$@" | jq -s --arg t "$_t" --arg a "$_a" '{title:$t, author:$a, comments:.}'; }
digest() { _o="$(sh "$D" "$@" 2>/dev/null)" && _rc=0 || _rc=$?; OUT="$_o"; RC=$_rc; }

printf 'alice\nbob\ncarol\n' > "$T_TMP/members"
{
  issue "heartbeat alice" alice "$(cm alice 2026-11-12T08:30:00Z "$(hb alice 9 2 1)")" "$(cm alice 2026-11-11T08:30:00Z "$(hb alice 8 7 7)")"
  issue "heartbeat bob" bob "$(cm bob 2026-11-07T09:00:00Z "$(hb bob 4 0 0)")"
  issue "heartbeat dave" dave "$(cm dave 2026-11-12T08:00:00Z "$(hb dave 1 0 0)")" "$(cm mallory 2026-11-12T08:10:00Z "$(hb dave 99 99 99)")"
  issue "heartbeat erin" erin "$(cm erin 2026-11-12T08:00:00Z "$(hb erin 1 0 0 '.[0].note = "the client said no"')")"
  issue "heartbeat frank" frank "$(cm frank 2026-11-12T08:00:00Z "$(hb alice 1 0 0)")"
  issue "heartbeat gina" mallory "$(cm mallory 2026-11-12T08:00:00Z "$(hb gina 1 0 0)")"
} | jq -s '.' > "$T_TMP/issues.json"

t_section "1 - the table: who, when, which version, what they met"
digest --issues "$T_TMP/issues.json" --policy "$POL" --now "$NOW" --members "$T_TMP/members"
t_eq "exit 0" 0 "$RC"
t_has "the format line" "$OUT" "harbor-digest: 1"
t_has "the hub and the date" "$OUT" "hub: fixture-hub"
t_has "alice is ok, from her newest comment" "$OUT" "| alice | 2026-11-12T08:30:00Z | 0123456789ab | 1 | 0123456789abcdef | 9 | shadow | 2 | 3 | 1 | ok |"
t_has "the admins are mentioned for the mail" "$OUT" "cc: @fixture-admin"
t_has "dave's numbers come from his own comment, not the one mallory wrote" "$OUT" "| dave | 2026-11-12T08:00:00Z | 0123456789ab | 1 | 0123456789abcdef | 1 | shadow | 0 | 3 | 0 | ok |"
t_has "mallory's comment on dave's issue is counted" "$OUT" "foreign-comments: 1"

t_section "2 - silent members, at silent_days and not before"
t_has "bob last seen 5 days ago is silent" "$OUT" "| bob | 2026-11-07T09:00:00Z |"
t_has "bob's state" "$OUT" "| 4 | shadow | 0 | 3 | 0 | silent |"
t_has "carol never sent one" "$OUT" "| carol | - | - | - | - | - | - | - | - | - | never |"
digest --issues "$T_TMP/issues.json" --policy "$POL" --now "2026-11-12T08:59:59Z" --members "$T_TMP/members"
t_has "one second short of silent_days is still ok" "$OUT" "| bob | 2026-11-07T09:00:00Z | 0123456789ab | 1 | 0123456789abcdef | 4 | shadow | 0 | 3 | 0 | ok |"
digest --issues "$T_TMP/issues.json" --policy "$POL" --now "$NOW" --members "$T_TMP/members" --silent
t_eq "--silent names bob, carol, and erin and frank whose only comments were refused" "bob
carol
erin
frank" "$OUT"
jq '.revoked = ["bob"]' "$POL" > "$T_TMP/revoked.json"
digest --issues "$T_TMP/issues.json" --policy "$T_TMP/revoked.json" --now "$NOW" --members "$T_TMP/members" --silent
t_eq "a revoked member is not expected" "carol
erin
frank" "$OUT"

t_section "3 - nothing outside the vocabulary is printed"
digest --issues "$T_TMP/issues.json" --policy "$POL" --now "$NOW" --members "$T_TMP/members"
t_hasnt "free text in an event" "$OUT" "the client said"
t_hasnt "erin, whose event carried it, is not listed on the strength of it" "$OUT" "| erin | 2026"
t_hasnt "frank's comment names another member" "$OUT" "| frank | 2026"
t_hasnt "an issue whose author is not the titled login" "$OUT" "gina"
t_has "the invalid comments are counted" "$OUT" "invalid-comments: 2"
t_eq "every line is a header, the table or the sentence" "0" "$(printf '%s\n' "$OUT" | grep -v '^$' | grep -v -E '^(harbor-digest: 1|hub: [a-z0-9.-]+|date: [0-9-]+|silent_days: [0-9]+|members: [0-9]+|silent: [0-9]+|invalid-comments: [0-9]+|foreign-comments: [0-9]+|cc: (@[A-Za-z0-9-]+ ?)+)$' | grep -v -E '^\|( [A-Za-z0-9.: -]+ \|)+$' | grep -v -E '^\|(---\|)+$' | grep -c . || true)"

t_section "4 - a quiet day still has a digest (R19)"
printf '[]' > "$T_TMP/none.json"
digest --issues "$T_TMP/none.json" --policy "$POL" --now "$NOW"
t_eq "an empty board exits 0" 0 "$RC"
t_has "and prints the header" "$OUT" "harbor-digest: 1"
t_has "and says nothing came" "$OUT" "no member has sent a heartbeat"
digest --issues "$T_TMP/none.json" --policy "$POL" --now "$NOW" --silent
t_eq "--silent with nobody is empty and exit 0" "0:" "$RC:$OUT"

t_section "5 - bad input is refused and prints no digest"
t_exit "a policy that fails the format" 2 sh "$D" --issues "$T_TMP/none.json" --policy "$T_ROOT/tests/hub/fixtures/events.json" --now "$NOW"
t_exit "issues that are not an array" 2 sh "$D" --issues "$POL" --policy "$POL" --now "$NOW"
t_exit "a time in the wrong shape" 2 sh "$D" --issues "$T_TMP/none.json" --policy "$POL" --now "yesterday"
t_exit "no arguments" 2 sh "$D"
t_exit "--help" 0 sh "$D" --help
digest --issues "$T_TMP/none.json" --policy "$T_ROOT/tests/hub/fixtures/events.json" --now "$NOW"
t_eq "and nothing on stdout" "" "$OUT"
t_done
