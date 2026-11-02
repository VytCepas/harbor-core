#!/usr/bin/env sh
# `harbor access stored`: every item bin/secret holds, against the register (harbor#1205).
# A stored item no entry names is refused to its consumer by the gate; this is the check that says so.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
VAL="fake-stored-value-0123456789"
plant() { printf 'v1:b64:%s' "$(printf '%s' "$VAL" | base64 | tr -d '\n')" > "$KC_STUB/items/secret.$1@${USER:-$(id -un)}"; }
entry() { printf '\n## %s\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: %s\n' "$1" "$2" >> "$REG"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
LEGREF="$(awk '/^[[:space:]]*(#|$)/ { next } { print $1; exit }' "$T_ROOT/contracts/secret-legacy-refs.txt")"

t_section "an empty store is a pass"
t_eq "exit 0" 0 "$(rc AX stored)"
t_has "...and says so" "$(AX stored 2>&1)" "0 stored items"

t_section "every stored item named: green, one state per item"
plant reg-ref; entry reg-entry reg-ref
plant "$LEGREF"
t_eq "exit 0" 0 "$(rc AX stored)"
t_eq "a registered item" "registered	reg-ref" "$(AX stored 2>/dev/null | grep reg-ref)"
t_eq "a legacy item" "grandfathered	$LEGREF" "$(AX stored 2>/dev/null | grep -F "$LEGREF")"

t_section "a stored item no entry names: red, named, with the fix"
plant orphan-ref
t_eq "exit 1" 1 "$(rc AX stored)"
t_eq "the item is UNREGISTERED" "UNREGISTERED	orphan-ref" "$(AX stored 2>/dev/null | grep orphan-ref)"
OUT="$(AX stored 2>&1)"
t_has "the FAIL names it" "$OUT" "secret.orphan-ref is stored but no entry names it"
t_has "the fix registers it" "$OUT" "harbor access add <id> --kind token ... --secret orphan-ref"
t_hasnt "no value leaves" "$OUT" "$VAL"
t_eq "...and the gate does refuse it, which is why this is red" 1 "$(rc sh "$T_ROOT/bin/secret" run orphan-ref V -- true)"
entry orphan-entry orphan-ref
t_eq "registered, it is green again" 0 "$(rc AX stored)"

t_section "an entry with no stored value is not this check's business"
entry unstored-entry unstored-ref
t_eq "still green" 0 "$(rc AX stored)"

t_section "a store that cannot be listed is not a pass"
D="$T_TMP/nolist"; mkdir -p "$D"; cp "$T_ROOT/bin/access.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$D/"
printf '#!/bin/sh\nexit 1\n' > "$D/secret"
t_eq "exit 2" 2 "$(HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$D/access.sh" stored)"
t_eq "stored takes no operand" 2 "$(rc AX stored extra)"

t_section "red-proof: a mutant that reads every item as registered passes the orphan"
plant orphan-two
t_eq "control: the real one is red" 1 "$(rc AX stored)"
mkdir -p "$T_TMP/mut"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/secret" "$T_TMP/mut/"
sed 's/__st=0; has_ref "\$__svc" || __st=\$?/__st=0/' "$T_ROOT/bin/access.sh" > "$T_TMP/mut/access.sh"
t_eq "the mutant was built: the register is no longer asked" 0 "$(grep -c 'has_ref "\$__svc"' "$T_TMP/mut/access.sh")"
t_eq "the mutant passes what the real one fails" 0 "$(HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$T_TMP/mut/access.sh" stored)"
t_done
