#!/usr/bin/env sh
# `harbor scope install` creates the access register with a header only, and never overwrites it (harbor#1205).
# A temp HOME, a temp PORT_ROOT and a temp HARBOR_SCOPE_PRIVATE: nothing outside them is read or written.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SCOPE() { sh "$T_ROOT/bin/scope.sh" install "$@" 2>&1; }
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
rc() { "$@" >/dev/null 2>&1; echo $?; }
export PORT_ROOT="$T_TMP/port" HARBOR_SCOPE_PRIVATE="$T_TMP/pv"
REG="$HARBOR_SCOPE_PRIVATE/access/register.md"

t_section "--dry-run writes nothing"
OUT="$(SCOPE --private-only --dry-run)"
t_has "it says it would create the register" "$OUT" "would create $REG"
t_eq "...and the private layer does not exist" gone "$([ -e "$HARBOR_SCOPE_PRIVATE" ] && echo present || echo gone)"

t_section "a fresh install: the register exists, header only, empty by default"
OUT="$(SCOPE --private-only)"
t_has "install reports creating it" "$OUT" "created  $REG"
t_eq "the file is there" present "$([ -f "$REG" ] && echo present || echo gone)"
t_eq "it holds no entry" 0 "$(grep -c '^## ' "$REG")"
t_eq "it holds no field line" 0 "$(grep -c '^[[:space:]]\{1,\}[a-z-]*:' "$REG")"
t_has "the header points at the contract" "$(cat "$REG")" "contracts/access-register.md"
t_eq "check is green on it" 0 "$(rc AX check)"
t_has "...and counts no entry" "$(AX check 2>&1)" "0 entries"
t_eq "list is empty" "" "$(AX list 2>/dev/null)"
t_eq "refs is empty" "" "$(AX refs)"
t_eq "every ref is refused: a fresh box can read no credential" 1 "$(rc AX has any-ref-at-all)"
t_eq "...and so does bin/secret" 1 "$(rc sh "$T_ROOT/bin/secret" run any-ref-at-all V -- true)"

t_section "a second install never overwrites it"
printf '\n## kept\n\n    secret: kept-ref\n' >> "$REG"
SUM="$(cksum < "$REG")"
OUT="$(SCOPE --private-only)"
t_has "install says it kept it" "$OUT" "kept     $REG"
t_eq "the file is byte for byte what it was" "$SUM" "$(cksum < "$REG")"

t_section "an existing layer that lacks the register gets one, and its other files are untouched"
rm -f "$REG"; printf 'mine\n' > "$HARBOR_SCOPE_PRIVATE/CLAUDE.personal.md"
SCOPE --private-only >/dev/null
t_eq "the register is created" present "$([ -f "$REG" ] && echo present || echo gone)"
t_eq "the operator's file was not touched" "mine" "$(cat "$HARBOR_SCOPE_PRIVATE/CLAUDE.personal.md")"

t_section "the register is not a route card"
mkdir -p "$T_TMP/cards"; cp "$REG" "$T_TMP/cards/register.md"
OUT="$(sh "$T_ROOT/skills/access-ledger/bin/check-routes.sh" "$T_TMP/cards" 2>&1)"
t_hasnt "check-routes does not read it as a card" "$OUT" "register.md"
t_has "...and found no route cards, which is not a pass" "$OUT" "FAIL no route cards found"
t_done
