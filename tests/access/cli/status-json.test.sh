#!/usr/bin/env sh
# `harbor access status --json` (harbor#1480): the Harbor pane's access feed. The same facts as the text mode, as data: one
# object, every entry, text mode's exit codes, [id...] filtering. NEVER a value: a sentinel is stored in the file-backed
# keychain stub and printed by a failing check, and must not appear anywhere in the output or in the state file.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
SC() { sh "$T_ROOT/bin/secret" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port" ACCESS_STATE="$T_TMP/state.tsv"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
rc() { "$@" >/dev/null 2>&1; echo $?; }
TODAY="$(date -u +%Y-%m-%d)"
entry() { # <id> <ref> [extra field lines...]
  _i="$1"; _r="$2"; shift 2
  printf '\n## %s\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: %s\n' "$_i" "$_r" >> "$REG"
  for _l in "$@"; do printf '    %s\n' "$_l" >> "$REG"; done
}
put() { printf '%s' "$2" | SC put "$1" >/dev/null 2>&1; }  # <ref> <value>
alive() { printf 'check: sh %s run %s V -- sh -c '"'"'case "$V" in good-*) echo alive ;; esac'"'"'' "$T_ROOT/bin/secret" "$1"; }
EXPECT='expect: prints `alive`'
days_from_today() { awk -v n="$1" -v t="$TODAY" 'BEGIN { split(t, a, "-"); y = a[1]; m = a[2]; d = a[3] + n
  while (1) { ml = (m == 2) ? (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
    if (d > ml) { d -= ml; m++; if (m > 12) { m = 1; y++ } } else if (d < 1) { m--; if (m < 1) { m = 12; y-- }
      d += (m == 2) ? (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31) } else break }
  printf "%04d-%02d-%02d\n", y, m, d }'; }
SENT='SENTINEL-VALUE-0123456789abcdef'
E1="$(days_from_today -3)"; E2="$(days_from_today 5)"

t_section "an empty register: an object with no entries, exit 0"
t_eq "entries is []" '[]' "$(AX status --json | jq -c '.entries')"
t_eq "exit 0" 0 "$(rc AX status --json)"

entry ok-one ok-ref "$(alive ok-ref)" "$EXPECT"; put ok-ref good-1
entry dead-one dead-ref "$(alive dead-ref)" "$EXPECT"; put dead-ref bad-1
entry leak-one leak-ref "check: echo $SENT; exit 1" "$EXPECT"; put leak-ref "$SENT"
entry gone-one gone-ref
entry late-one late-ref "expires: $E1"; put late-ref good-3
entry soon-one soon-ref "expires: $E2" "$(alive soon-ref)" "$EXPECT"; put soon-ref good-4
entry quiet-one quiet-ref; put quiet-ref good-2
entry outside-one none
printf '\n## a-login\n\n    kind: account\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: none\n' >> "$REG"
entry bad-date bd-ref 'expires: 2026-13-45'; put bd-ref good-5
entry retired-one none 'revoked: 2026-01-01'

OUT="$(AX status --json 2>"$T_TMP/err")"; RC=$(rc AX status --json)
TXT="$(AX status -v 2>&1)"; TRC=$(rc AX status)
e() { printf '%s' "$OUT" | jq -c --arg i "$1" ".entries[] | select(.id == \$i) | $2"; }

t_section "shape"
t_eq "one object on stdout" 1 "$(printf '%s' "$OUT" | jq -s 'length')"
t_eq "ts is an ISO UTC stamp" true "$(printf '%s' "$OUT" | jq '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")')"
t_eq "an entry has exactly the contract's keys" '["alive","days_left","expires","id","kind","problem","since","state","stored"]' "$(printf '%s' "$OUT" | jq -c '[.entries[] | keys] | unique | .[0]')"
t_eq "every entry is there, in register order" '["ok-one","dead-one","leak-one","gone-one","late-one","soon-one","quiet-one","outside-one","a-login","bad-date","retired-one"]' "$(printf '%s' "$OUT" | jq -c '[.entries[].id]')"
t_eq "stderr is empty" "" "$(cat "$T_TMP/err")"

t_section "state, stored, alive, problem"
t_eq "a passing check: ok, stored, alive, no problem" '["ok",true,true,null]' "$(e ok-one '[.state, .stored, .alive, .problem]')"
t_eq "a failing check: dead, alive false" '["dead",true,false]' "$(e dead-one '[.state, .stored, .alive]')"
t_has "...and says why" "$(e dead-one .problem)" "lacks the expected literal"
t_eq "a ref not in the store: unstored, not stored" '["unstored",false,null]' "$(e gone-one '[.state, .stored, .alive]')"
t_has "...and says why" "$(e gone-one .problem)" "is not in the store"
t_eq "a past expiry: expired" expired "$(e late-one .state | tr -d '"')"
t_eq "...with its date and negative days_left" "[\"$E1\",-3]" "$(e late-one '[.expires, .days_left]')"
t_eq "an expiry within 14 days: expiring, check passed so alive" '["expiring",true,5]' "$(e soon-one '[.state, .alive, .days_left]')"
t_eq "stored, no check: unknown, alive null, no problem" '["unknown",true,null,null]' "$(e quiet-one '[.state, .stored, .alive, .problem]')"
t_eq "a sign-in with no secret: unknown, not stored" '["unknown",false,null]' "$(e a-login '[.state, .stored, .alive]')"
t_eq "an unmanaged token: unknown" unknown "$(e outside-one .state | tr -d '"')"
t_eq "a retired entry: unknown" unknown "$(e retired-one .state | tr -d '"')"
t_eq "an unreadable expiry date is null, not a guess" '[null,null]' "$(e bad-date '[.expires, .days_left]')"
t_eq "no expiry: both null" '[null,null]' "$(e ok-one '[.expires, .days_left]')"
t_eq "kind is the entry's" '"account"' "$(e a-login .kind)"
t_eq "since is today for a state seen first now" "\"$TODAY\"" "$(e dead-one .since)"
awk -F'\t' -v OFS='\t' '$1 == "dead-one" { $3 = "2026-01-01" } { print }' "$ACCESS_STATE" > "$T_TMP/s" && mv "$T_TMP/s" "$ACCESS_STATE"
t_eq "...and keeps the first day from the state file" '"2026-01-01"' "$(AX status --json | jq -c '.entries[] | select(.id == "dead-one") | .since')"

t_section "agreement with the text mode, and its exit codes"
t_eq "exit 1 when anything is red, as text mode" "$TRC" "$RC"
t_eq "...which is 1" 1 "$RC"
for _id in dead-one gone-one late-one; do
  t_has "text mode also marks $_id red" "$TXT" "$_id"
done
t_eq "the JSON's problem entries are the text mode's non-green lines" "dead-one gone-one late-one leak-one soon-one" "$(printf '%s' "$OUT" | jq -r '[.entries[] | select(.problem != null) | .id] | sort | join(" ")')"
t_eq "...the text mode's red and expiring lines" "dead-one gone-one late-one leak-one soon-one" "$(printf '%s\n' "$TXT" | awk '$1 ~ /^(FAIL|MISSING|EXPIRED|TIMEOUT|REFUSED|REVOKED-STORED|expiring)$/ { print $2 }' | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "ids filter" '["dead-one"]' "$(AX status --json dead-one | jq -c '[.entries[].id]')"
t_eq "...and in the order given" '["soon-one","ok-one"]' "$(AX status --json soon-one ok-one | jq -c '[.entries[].id]')"
t_eq "a green id exits 0 in JSON as in text" "$(rc AX status ok-one)" "$(rc AX status --json ok-one)"
t_eq "...which is 0" 0 "$(rc AX status --json ok-one)"
t_eq "an unknown id: exit 2, no JSON" "2 " "$(AX status --json no-such-id 2>/dev/null >"$T_TMP/o"; echo "$? $(cat "$T_TMP/o")")"
mkdir -p "$T_TMP/nolist"; printf '#!/bin/sh\ncase "$1" in dump-keychain) exit 1 ;; esac\nexec "%s/security" "$@"\n' "$T_BIN" > "$T_TMP/nolist/security"; chmod +x "$T_TMP/nolist/security"
t_eq "a store that cannot be listed: exit 2, as text" 2 "$(PATH="$T_TMP/nolist:$PATH" rc AX status --json)"

t_section "the verb: harbor access status --json passes through; no other access verb takes --json"
HX() { HARBOR_SCOPE_BIN="$T_ROOT/bin" sh "$T_ROOT/bin/harbor" "$@"; }
t_eq "the dispatcher passes --json to status" "$(printf '%s' "$OUT" | jq -c '[.entries[].id]')" "$(HX access status --json 2>/dev/null | jq -c '[.entries[].id]')"
t_eq "list --json is refused, exit 2" 2 "$(rc AX list --json)"
t_eq "check --json is refused, exit 2" 2 "$(rc AX check --json)"
t_eq "has --json is refused, exit 2" 2 "$(rc AX has some-ref --json)"
t_eq "list without the flag still works" 0 "$(rc AX list)"

t_section "never a value"
t_hasnt "the sentinel (stored, and printed by a failing check) is not in the JSON" "$OUT" "$SENT"
t_hasnt "...nor on stderr" "$(cat "$T_TMP/err")x" "$SENT"
t_hasnt "...nor in the state file" "$(cat "$ACCESS_STATE")" "$SENT"
t_hasnt "no stored value of any kind: good-1 bad-1" "$OUT" "good-1"
t_hasnt "...bad-1" "$OUT" "bad-1"
t_hasnt "the check text itself is not an output field" "$OUT" "echo "
t_eq "the leaking entry reports dead and nothing else" '["dead",false]' "$(e leak-one '[.state, .alive]')"

t_done
