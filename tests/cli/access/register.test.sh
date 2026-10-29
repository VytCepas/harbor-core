#!/usr/bin/env sh
# bin/access.sh: the access register and `harbor access add|list|has|refs|check` (harbor#1205).
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
# DEFERRED, needs a human at the keyboard: the terminal prompts of `add` (a missing field asked for) and bin/secret's own value prompt.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
SC() { sh "$T_ROOT/bin/secret" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
FAKEVAL="fake-value-$(printf 'q%.0s' 1 2 3 4 5 6)-0123"
FAKECRED="ghp_$(printf 'a%.0s' $(seq 1 36))"
ADD() { # <id> <ref|-> [extra args...] - every field given, so no prompt is needed
  _i="$1"; _r="$2"; shift 2
  case "$_r" in -) _sec=--no-secret ;; *) _sec="--secret $_r" ;; esac
  # shellcheck disable=SC2086
  AX add "$_i" --kind token --what "a test token" --use-when "only in tests" --reaches "nothing real" \
      --cannot "anything" --grant "the suite" $_sec "$@"
}
rc() { "$@" >/dev/null 2>&1; echo $?; }

t_section "a fresh register is header only and valid"
t_eq "scope install wrote register.md" present "$([ -f "$REG" ] && echo present || echo gone)"
t_eq "check on a header-only register is green" 0 "$(rc AX check)"
t_has "...and says there are no entries" "$(AX check 2>&1)" "0 entries"
t_eq "list prints nothing" "" "$(AX list 2>/dev/null)"
t_eq "refs prints nothing" "" "$(AX refs)"
t_eq "an unregistered ref is refused: has exits 1" 1 "$(rc AX has some-ref)"

t_section "no private layer: the register is empty and every ref is refused"
HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer"
t_eq "has exits 1" 1 "$(rc AX has some-ref)"
t_eq "check inspected nothing and exits 2" 2 "$(rc AX check)"
t_has "...and says it is not a pass" "$(AX check 2>&1)" "NOTHING was checked and this is not a pass"
t_eq "list prints nothing, exit 0" 0 "$(rc AX list)"
t_eq "add refuses: exit 1" 1 "$(rc ADD some-id some-ref)"
t_has "...and says there is no private layer" "$(ADD some-id some-ref 2>&1)" "no private layer to write one in"
t_eq "...nothing was created" gone "$([ -e "$T_TMP/no-layer" ] && echo present || echo gone)"
HARBOR_SCOPE_PRIVATE="$PV"

t_section "add records the entry and stores the value through the seam, once"
printf '%s' "$FAKEVAL" | ADD test-token test-token-ref --value-stdin >"$T_TMP/add.out" 2>&1; _rc=$?
t_eq "add exits 0" 0 "$_rc"
t_has "...and names the entry" "$(cat "$T_TMP/add.out")" "registered 'test-token' (token)"
t_hasnt "the register holds no value" "$(cat "$REG")" "$FAKEVAL"
t_hasnt "add printed no value" "$(cat "$T_TMP/add.out")" "$FAKEVAL"
t_hasnt "no store call carried the value in argv" "$(cat "$KC_STUB/argv.log")" "$FAKEVAL"
t_has "the entry carries its fields" "$(cat "$REG")" "    secret: test-token-ref"
t_has "...and the grant" "$(cat "$REG")" "    grant: the suite"
t_eq "has says registered: 0" 0 "$(rc AX has test-token-ref)"
t_eq "refs lists the ref" "test-token-ref" "$(AX refs)"
t_has "list shows id, kind and ref" "$(AX list)" "test-token	token	test-token-ref	a test token"
t_eq "the value is in the store, behind secret" "$FAKEVAL" "$(SC run test-token-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_eq "check is green with the entry" 0 "$(rc AX check)"
t_has "...and counts it" "$(AX check 2>&1)" "1 entry"

t_section "add refuses what it must"
BEFORE="$(cksum < "$REG")"
t_eq "a repeated id: exit 1" 1 "$(rc ADD test-token other-ref)"
t_eq "a ref another entry names: exit 1" 1 "$(rc ADD other-id test-token-ref)"
t_eq "an unknown kind: exit 2" 2 "$(rc AX add x --kind wizard --what w --use-when u --reaches r --cannot c --grant g --no-secret)"
t_eq "a missing field (no tty to ask): exit 2" 2 "$(rc AX add x --kind token --what w --use-when u --reaches r --grant g --no-secret </dev/null)"
t_has "...and names it" "$(AX add x --kind token --what w --use-when u --reaches r --grant g --no-secret </dev/null 2>&1)" "CANNOT"
t_eq "neither --secret nor --no-secret: exit 2" 2 "$(rc AX add x --kind token --what w --use-when u --reaches r --cannot c --grant g </dev/null)"
t_eq "a bad id: exit 2" 2 "$(rc ADD Bad_Id -)"
t_eq "a ref with a slash: exit 2" 2 "$(rc ADD x-id bad/ref)"
t_eq "--value-stdin without a ref: exit 2" 2 "$(rc AX add x --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --value-stdin </dev/null)"
t_eq "a field shaped like a credential: exit 2" 2 "$(rc AX add x --kind token --what "$FAKECRED" --use-when u --reaches r --cannot c --grant g --no-secret)"
t_hasnt "...and the value is not echoed" "$(AX add x --kind token --what "$FAKECRED" --use-when u --reaches r --cannot c --grant g --no-secret 2>&1)" "$FAKECRED"
t_eq "a newline in a field: exit 2" 2 "$(rc AX add x --kind token --what "$(printf 'a\nb')" --use-when u --reaches r --cannot c --grant g --no-secret)"
t_eq "none of those touched the register" "$BEFORE" "$(cksum < "$REG")"

t_section "an entry with no secret names no ref; a ref with no value is recorded and says so"
ADD mail-box - >/dev/null 2>&1
t_eq "--no-secret is recorded as none" 1 "$(grep -c '    secret: none' "$REG")"
t_eq "...and none is not a ref" 1 "$(rc AX has none)"
ADD later-ref later-ref </dev/null >"$T_TMP/later.out" 2>&1
t_has "no tty and no --value-stdin: the entry is kept and the missing value said" "$(cat "$T_TMP/later.out")" "no value was stored"
t_eq "...the ref is registered" 0 "$(rc AX has later-ref)"
t_eq "...and the store holds nothing for it" 1 "$(rc SC run later-ref V -- true)"

t_section "a failed store rolls the entry back"
mkdir -p "$T_TMP/badkc"; printf '#!/bin/sh\nexit 1\n' > "$T_TMP/badkc/security"; chmod +x "$T_TMP/badkc/security"
BEFORE="$(cksum < "$REG")"
printf '%s' "$FAKEVAL" | PATH="$T_TMP/badkc:$PATH" ADD rolled-back rolled-ref --value-stdin >"$T_TMP/rb.out" 2>&1; _rc=$?
t_eq "add exits 1" 1 "$_rc"
t_has "...and says it rolled back" "$(cat "$T_TMP/rb.out")" "rolled back"
t_eq "the register is byte-for-byte what it was" "$BEFORE" "$(cksum < "$REG")"
t_eq "the ref is not registered" 1 "$(rc AX has rolled-ref)"

t_section "--probe: a passing probe is reported, a failing one exits 1 and keeps the entry"
ADD probed-ok - --probe true >"$T_TMP/p1.out" 2>&1; _rc=$?
t_eq "a passing probe: exit 0" 0 "$_rc"
t_has "...and says so" "$(cat "$T_TMP/p1.out")" "probe passed"
ADD probed-bad - --probe false >"$T_TMP/p2.out" 2>&1; _rc=$?
t_eq "a failing probe: exit 1" 1 "$_rc"
t_has "...and says so" "$(cat "$T_TMP/p2.out")" "probe failed"
t_eq "...the entry is kept" 1 "$(grep -c '^## probed-bad$' "$REG")"

t_section "check finds a register that was edited by hand"
good="$T_TMP/good.md"; cp "$REG" "$good"
hand_edit() { # <label> <expected message> <lines appended to the register>
  cp "$good" "$REG"; printf '%s\n' "$3" >> "$REG"
  t_eq "$1: check is red" 1 "$(rc AX check)"
  t_has "$1: and names the problem" "$(AX check 2>&1)" "$2"
  cp "$good" "$REG"
}
hand_edit "a missing field" "hand-edit: no cannot field" '
## hand-edit

    kind: token
    what: w
    use-when: u
    reaches: r
    grant: g
    secret: none'
hand_edit "an unknown kind" "kind wizard is not one of" '
## hand-edit

    kind: wizard
    what: w
    use-when: u
    reaches: r
    cannot: c
    grant: g
    secret: none'
hand_edit "a typo'd field" "unknown field use_when" '
## hand-edit

    kind: token
    what: w
    use-when: u
    use_when: u
    reaches: r
    cannot: c
    grant: g
    secret: none'
hand_edit "a ref named twice" "secret test-token-ref is already named by test-token" '
## hand-edit

    kind: token
    what: w
    use-when: u
    reaches: r
    cannot: c
    grant: g
    secret: test-token-ref'
hand_edit "a repeated entry id" "repeats the one on line" '
## test-token

    kind: token'
printf '# Access register\n\n    stray: here\n' > "$REG"
t_eq "a field outside any entry: check is red" 1 "$(rc AX check)"
t_has "...and names the problem" "$(AX check 2>&1)" "a field line outside any entry"
cp "$good" "$REG"
hand_edit "a bad date" "verified yesterday is not an ISO date" '
## hand-edit

    kind: token
    what: w
    use-when: u
    reaches: r
    cannot: c
    grant: g
    secret: none
    verified: yesterday'
hand_edit "a credential value" "holds something shaped like a credential value" "
## hand-edit

    kind: token
    what: $FAKECRED
    use-when: u
    reaches: r
    cannot: c
    grant: g
    secret: none"
cp "$good" "$REG"; bad_out="$(printf '%s\n' "    what: $FAKECRED" > "$T_TMP/c.md"; cat "$T_TMP/c.md" >> "$REG"; AX check 2>&1)"; cp "$good" "$REG"
t_hasnt "check never prints the value it found" "$bad_out" "$FAKECRED"
t_eq "the restored register is green again" 0 "$(rc AX check)"

t_section "a legacy ref is served until registered, and check says when it can leave the list"
LEG="$T_TMP/legacy.txt"; printf '# a comment\nold-ref bin/old-consumer\n' > "$LEG"
t_eq "an unlisted, unregistered ref: 1" 1 "$(ACCESS_LEGACY_REFS="$LEG" rc AX has not-listed)"
t_eq "a listed ref: 3, grandfathered" 3 "$(ACCESS_LEGACY_REFS="$LEG" rc AX has old-ref)"
t_eq "a comment is not a ref" 1 "$(ACCESS_LEGACY_REFS="$LEG" rc AX has '#')"
printf 'test-token-ref bin/x\n' >> "$LEG"
t_has "a legacy ref that is now registered is flagged for removal" "$(ACCESS_LEGACY_REFS="$LEG" AX check 2>&1)" "test-token-ref is registered now"
t_eq "a registered ref wins over the list: 0" 0 "$(ACCESS_LEGACY_REFS="$LEG" rc AX has test-token-ref)"
t_done
