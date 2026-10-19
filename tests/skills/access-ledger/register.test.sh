#!/usr/bin/env sh
# check-routes.sh and the access register (harbor#1149): the cards are private data, so the gate resolves them
# through bin/roots.sh --access and, with none, says nothing was checked rather than passing. Fixture cards only.
. "$(dirname "$0")/../../lib/core.sh"; t_init
ROUTES="$T_ROOT/skills/access-ledger/bin/check-routes.sh"
TODAY=$(date +%Y-%m-%d)
CARD="$T_TMP/card.md"
cat > "$CARD" <<CARDEOF
# thing - a fixture system

    identity: person@example.invalid via a named human profile
    account:  person@example.invalid | primary | reader on the fixture | a named human profile in the browser
    via:      api > browser
    upgrade:  none - the grant is all-or-nothing
    use:      curl -sS https://api.example.invalid/me
    check:    curl -sS https://api.example.invalid/me
    expect:   a JSON object carrying an id
    role-check: none - no token exists to read a role with
    role-expect: none
    grant:    reader on the fixture
    owner:    vendor
    reaches:  reads
    cannot:   writes
    verified: $TODAY
CARDEOF
mkreg() { # <dir> → a register holding the card and both generated files
  mkdir -p "$1"; cp "$CARD" "$1/thing.md"
  sh "$ROUTES" --accounts "$1" > "$1/ACCOUNTS.md"; sh "$ROUTES" --dispatch "$1" > "$1/DISPATCH.md"
}
GATE() { sh "$ROUTES" "$@" 2>&1; }
NOPV="$T_TMP/no-layer"   # never created

t_section "with no register, every default mode says NOTHING was checked and exits 2"
export HARBOR_SCOPE_PRIVATE="$NOPV"
for _m in "" --report --dispatch --accounts --run; do
  t_exit "check-routes.sh ${_m:-(gate)} is exit 2, never 0" 2 sh "$ROUTES" $_m
done
t_exit "--coverage <corpus> with no register is exit 2" 2 sh "$ROUTES" --coverage "$T_TMP"
t_has "...and says the register is the reason, not a missing directory" "$(GATE --coverage "$T_TMP")" "no access register"
_o="$(GATE)"
t_has "the line says nothing was checked" "$_o" "NOTHING was checked and this is not a pass"
t_has "...and why: the resolver's reason" "$_o" "no private layer at $NOPV"
t_hasnt "...and prints no verdict a reader could mistake for a pass" "$_o" "route card(s) checked"

t_section "an explicit [dir] needs no register"
mkreg "$T_TMP/explicit"
t_exit "the gate over a given directory is green" 0 sh "$ROUTES" "$T_TMP/explicit"
t_exit "--report over a given directory runs" 0 sh "$ROUTES" --report "$T_TMP/explicit"
t_exit "a directory that does not exist is still exit 1" 1 sh "$ROUTES" "$T_TMP/absent"

t_section "with a private layer the default is its access/"
PV="$T_TMP/pv"; mkreg "$PV/access"; export HARBOR_SCOPE_PRIVATE="$PV"
t_exit "the default gate is green over <private>/access" 0 sh "$ROUTES"
t_has "...and checked the card there" "$(GATE)" "1 route card(s) checked"
t_has "--accounts defaults to it" "$(GATE --accounts)" "person@example.invalid"
printf 'x\n' >> "$PV/access/ACCOUNTS.md"
t_exit "a stale generated file in the register is red" 1 sh "$ROUTES"
export ACCESS_DIR="$T_TMP/explicit"; rm -rf "$PV"
t_exit "ACCESS_DIR wins over the layer" 0 sh "$ROUTES"
unset ACCESS_DIR

t_section "a layer whose access/ is empty is a failure, not a pass"
mkdir -p "$PV/access"
t_exit "no cards found is exit 1" 1 sh "$ROUTES"
t_has "...and says so" "$(GATE)" "no route cards found"
rmdir "$PV/access"
t_exit "a layer with no access/ at all is exit 2" 2 sh "$ROUTES"
t_done
