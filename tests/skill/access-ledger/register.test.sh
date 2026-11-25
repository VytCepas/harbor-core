#!/usr/bin/env sh
# check-routes.sh and the access register (harbor#1149): the cards are private data, so the gate resolves them
# through bin/scope-roots.sh --access and, with none, says nothing was checked rather than passing. Fixture cards only.
. "$(dirname "$0")/../../lib/core.sh"; t_init
ROUTES="$T_ROOT/skills/access-ledger/bin/check-routes.sh"
TODAY=$(date +%Y-%m-%d)
CARD="$T_TMP/card.md"
cat > "$CARD" <<CARDEOF
# thing - a fixture system

    identity: person@example.invalid via a named human profile
    account:  person@example.invalid | primary | reader on the fixture | a named human profile in the browser
    via:      api > browser
    ui-hosts: api.example.invalid
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

t_section "the generated files do not depend on the caller's locale"
LR="$T_TMP/locale"; mkdir -p "$LR"; cp "$CARD" "$LR/thing.md"
sed -e 's/person@example.invalid/Zed Bot/g; s/^# thing/# other/' -e '/^    ui-hosts:/d' -e 's/^    via:.*/    via:      api/' "$CARD" > "$LR/other.md"
sed -e 's/person@example.invalid/alpha@example.invalid/g; s/^# thing/# third/' -e '/^    ui-hosts:/d' -e 's/^    via:.*/    via:      api/' "$CARD" > "$LR/third.md"
LC_ALL=C sh "$ROUTES" --accounts "$LR" > "$LR/ACCOUNTS.md"; LC_ALL=C sh "$ROUTES" --dispatch "$LR" > "$LR/DISPATCH.md"
t_exit "written under C, it is current under en_US.UTF-8" 0 env LC_ALL=en_US.UTF-8 ACCESS_DIR="$LR" sh "$ROUTES"
t_exit "...and under C" 0 env LC_ALL=C ACCESS_DIR="$LR" sh "$ROUTES"

t_section "a layer whose access/ is empty is a failure, not a pass"
mkdir -p "$PV/access"
t_exit "no cards found is exit 1" 1 sh "$ROUTES"
t_has "...and says so" "$(GATE)" "no route cards found"
rmdir "$PV/access"
t_exit "a layer with no access/ at all is exit 2" 2 sh "$ROUTES"
t_section "the standard a card is held to, end to end (harbor#1617)"
mkreg "$T_TMP/std"
t_exit "CONTROL the fixture card passes the standard" 0 sh "$ROUTES" "$T_TMP/std"
sed 's#^    check:.*#    check:    open https://api.example.invalid/me#' "$CARD" > "$T_TMP/std/thing.md"
t_exit "check: open <url> is red" 1 sh "$ROUTES" "$T_TMP/std"
t_has "...and names harbor chrome goto as the form" "$(GATE "$T_TMP/std")" "harbor chrome goto"
sed 's#^    check:.*#    check:    GET https://api.example.invalid/me with the cookie jar#' "$CARD" > "$T_TMP/std/thing.md"
t_exit "a prose check line is red" 1 sh "$ROUTES" "$T_TMP/std"
sed '/^    ui-hosts:/d' "$CARD" > "$T_TMP/std/thing.md"
t_exit "api > browser with no ui-hosts is red" 1 sh "$ROUTES" "$T_TMP/std"
awk '/^    verified:/ { print "    session:  forever" } { print }' "$CARD" > "$T_TMP/std/thing.md"
t_exit "a session outside persistent|show-only is red" 1 sh "$ROUTES" "$T_TMP/std"
cp "$CARD" "$T_TMP/std/thing.md"

t_section "--run: an instrument failure is not an access failure (harbor#1617)"
mkdir -p "$T_TMP/run"
sed -e 's#^    check:.*#    check:    no-such-tool-xyz --me#' -e 's#^    expect:.*#    expect:   prints `account=nobody`#' "$CARD" > "$T_TMP/run/thing.md"
t_exit "a check whose command does not exist exits 0" 0 sh "$ROUTES" --run "$T_TMP/run"
_o="$(GATE --run "$T_TMP/run")"
t_has "...and says INSTRUMENT" "$_o" "INSTRUMENT"
t_has "...counted apart from access-FAIL" "$_o" "0 pass, 0 access-FAIL, 1 instrument"
sed -e 's#^    check:.*#    check:    printf "token=SECRETVALUE123\\n"#' -e 's#^    expect:.*#    expect:   prints `account=nobody`#' "$CARD" > "$T_TMP/run/thing.md"
t_exit "a check that prints the wrong thing is exit 1" 1 sh "$ROUTES" --run "$T_TMP/run"
t_has "...as an access-FAIL" "$(GATE --run "$T_TMP/run")" "1 access-FAIL"
t_hasnt "...and never echoes what the command printed" "$(GATE --run "$T_TMP/run" | grep -v '^   \$ ')" "SECRETVALUE123"
t_done
