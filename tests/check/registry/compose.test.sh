#!/usr/bin/env sh
# bin/check-registry-generate.sh: the one check registry, core CHECKS.md plus the private layer's checks.md (harbor#1149).
# Every layer here is a throwaway directory named by --private; the ids are made up and name no real entity.
. "$(dirname "$0")/../../lib/core.sh"; t_init
GEN="$T_ROOT/bin/check-registry-generate.sh"
CORE="$T_TMP/CHECKS.md"
cat > "$CORE" <<'EOF'
# CHECKS

## Register

| id | watches | schedule | notifies | red means |
|---|---|---|---|---|
| `core-one` | a core thing | hourly | desktop | broken |
| `core-two` | another | 09:00 daily | desktop | broken |
<!-- private:register -->

Prose after the register.

## Platforms

| id | platforms | why | disable |
|---|---|---|---|
| core-one | macOS only | w | `launchctl bootout x` |
| core-two | macOS only | w | `launchctl bootout y` |
<!-- private:platforms -->

## Adding a check
EOF
REG='| `acme-feed` | the Acme feed | hourly | desktop | the feed stopped |
| `acme-tags` | the Acme tags | 07:30 daily | desktop | a tag moved |'
PLAT='| acme-feed | macOS only | client watcher | `launchctl bootout a` |
| acme-tags | macOS only | client watcher | `launchctl bootout b` |'
frag() { # <name> [register rows] [platforms rows] [notes] -> a private layer dir holding checks.md
  _d="$T_TMP/pv-$1"; mkdir -p "$_d"
  { printf '<!-- fragment -->\n\n'
    [ -z "${2-}" ] || printf '## Register\n\n%s\n\n' "$2"
    [ -z "${3-}" ] || printf '## Platforms\n\n%s\n\n' "$3"
    [ -z "${4-}" ] || printf '## Notes\n\n%s\n' "$4"; } > "$_d/checks.md"
  printf '%s' "$_d"
}
gen() { sh "$GEN" --core "$CORE" --private "$1" 2>"$T_TMP/err"; }
ids() { awk -F'|' '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `/ { id = $2; gsub(/[` ]/, "", id); print id }'; }
pids() { awk -F'|' '/^## / { p = ($0 ~ /^## Platforms/) } p && /^\| [a-z]/ && $2 != " id " { id = $2; gsub(/ /, "", id); print id }'; }

t_section "no layer, no checks.md, an empty one: core comes out byte for byte"
t_exit "a layer directory that does not exist" 0 sh -c "sh '$GEN' --core '$CORE' --private '$T_TMP/nowhere' | cmp -s - '$CORE'"
mkdir -p "$T_TMP/pv-bare"
t_exit "a layer with no checks.md" 0 sh -c "sh '$GEN' --core '$CORE' --private '$T_TMP/pv-bare' | cmp -s - '$CORE'"
mkdir -p "$T_TMP/pv-empty"; : > "$T_TMP/pv-empty/checks.md"
t_exit "an empty checks.md, as 'scope install' writes it" 0 sh -c "sh '$GEN' --core '$CORE' --private '$T_TMP/pv-empty' | cmp -s - '$CORE'"
t_exit "HARBOR_SCOPE_PRIVATE names the layer when --private is not given" 0 sh -c "HARBOR_SCOPE_PRIVATE='$T_TMP/nowhere' sh '$GEN' --core '$CORE' | cmp -s - '$CORE'"

t_section "a layer with rows: one registry holding core and private, markers consumed"
PV="$(frag full "$REG" "$PLAT" 'Why acme-feed exists.')"; OUT="$(gen "$PV")"
t_eq "the register ids are core's then the layer's" "core-one core-two acme-feed acme-tags" "$(printf '%s\n' "$OUT" | ids | tr '\n' ' ' | sed 's/ $//')"
t_eq "the platforms ids are core's then the layer's" "core-one core-two acme-feed acme-tags" "$(printf '%s\n' "$OUT" | pids | tr '\n' ' ' | sed 's/ $//')"
t_eq "every register row has exactly one platforms row" "" "$(printf '%s\n' "$OUT" | ids | sort | comm -3 - "$(printf '%s\n' "$OUT" | pids | sort > "$T_TMP/p"; echo "$T_TMP/p")" | tr -d '\t')"
t_eq "no insertion point survives into the composed file" 0 "$(printf '%s\n' "$OUT" | grep -c '<!-- private:')"
t_has "the notes close the file under their own heading" "$(printf '%s\n' "$OUT" | tail -3)" "Why acme-feed exists."
t_has "...under ## Private notes" "$OUT" "## Private notes"
t_eq "the rows are the layer's, verbatim" "2" "$(printf '%s\n' "$OUT" | grep -cF -e "$(printf '%s' "$REG" | sed -n 1p)" -e "$(printf '%s' "$REG" | sed -n 2p)")"
t_eq "core loses nothing: every core line is still there" "" "$(grep -v '^<!-- private:' "$CORE" | sort | comm -23 - "$(printf '%s\n' "$OUT" | sort > "$T_TMP/o"; echo "$T_TMP/o")")"
t_eq "the layer adds exactly four rows, less two insertion points, plus a five-line notes block" 7 "$(( $(printf '%s\n' "$OUT" | wc -l) - $(wc -l < "$CORE") ))"
t_eq "composing is read-only: core is untouched" 0 "$(grep -c acme "$CORE")"
PV="$(frag onlyreg "$REG" "$PLAT")"; OUT="$(gen "$PV")"
t_hasnt "no notes, no notes heading" "$OUT" "## Private notes"
PV="$(frag comment "$REG" "$PLAT")"; printf '<!-- a comment -->\n' >> "$PV/checks.md"
t_eq "a one-line comment in the fragment is free" 0 "$(sh "$GEN" --core "$CORE" --private "$PV" >/dev/null 2>&1; echo $?)"
printf '\357\273\277' > "$T_TMP/bom"; cat "$T_TMP/bom" "$(frag bomsrc "$REG" "$PLAT")/checks.md" > "$T_TMP/bomfrag"
mkdir -p "$T_TMP/pv-bom"; cp "$T_TMP/bomfrag" "$T_TMP/pv-bom/checks.md"
t_eq "a byte-order mark and CRLF are stripped, not refused" 0 "$(sed 's/$/\r/' "$T_TMP/bomfrag" > "$T_TMP/pv-bom/checks.md"; sh "$GEN" --core "$CORE" --private "$T_TMP/pv-bom" >/dev/null 2>&1; echo $?)"

t_section "a fragment that cannot compose refuses the whole read: exit 2, nothing on stdout"
refuses() { # <label> <layer dir> <message needle>
  _o="$(sh "$GEN" --core "$CORE" --private "$2" 2>"$T_TMP/err")"; _r=$?
  t_eq "$1: exit 2" 2 "$_r"; t_eq "$1: nothing on stdout" "" "$_o"; t_has "$1: says why" "$(cat "$T_TMP/err")" "$3"
}
refuses "an id already in core" "$(frag dupcore '| `core-one` | x | hourly | desktop | y |' '| core-one | macOS only | w | d |')" "is in core CHECKS.md"
refuses "an id twice in the fragment" "$(frag duppriv "$(printf '%s\n%s' "$REG" "$(printf '%s' "$REG" | sed -n 1p)")" "$PLAT")" "repeats line"
refuses "a register row without cells" "$(frag short '| `acme-feed` | only | three |' '| acme-feed | macOS only | w | d |')" "not a register row"
refuses "a register row whose id is not in backticks" "$(frag bare '| acme-feed | a | hourly | desktop | r |' '| acme-feed | macOS only | w | d |')" "not a register row"
refuses "a platforms row with the wrong column count" "$(frag plat5 "$REG" '| acme-feed | macOS only | w |
| acme-tags | macOS only | w | d |')" "not a platforms row"
refuses "a register row with no platforms row" "$(frag noplat "$REG" '| acme-feed | macOS only | w | d |')" "not both"
refuses "a platforms row with no register row" "$(frag noreg '| `acme-feed` | a | hourly | desktop | r |' "$PLAT")" "not both"
PV="$(frag oddsec "$REG" "$PLAT")"; printf '## Registr\n| `x` |\n' >> "$PV/checks.md"
refuses "a section it does not know" "$PV" "is not Register, Platforms or Notes"
PV="$(frag stray "$REG" "$PLAT")"; { printf 'stray words\n'; cat "$PV/checks.md"; } > "$T_TMP/s"; mv "$T_TMP/s" "$PV/checks.md"
refuses "text before the first section" "$PV" "content before the first section"
sed '/private:register/d' "$CORE" > "$T_TMP/nomark.md"
_o="$(sh "$GEN" --core "$T_TMP/nomark.md" --private "$(frag full2 "$REG" "$PLAT")" 2>"$T_TMP/err")"; _r=$?
t_eq "rows with no insertion point in core: exit 2" 2 "$_r"; t_eq "...nothing on stdout" "" "$_o"
t_has "...says which line is missing" "$(cat "$T_TMP/err")" "<!-- private:register -->"
t_exit "an unknown argument is exit 2" 2 sh "$GEN" --nope
t_exit "a missing core is exit 2" 2 sh "$GEN" --core "$T_TMP/none.md" --private "$T_TMP/nowhere"

t_section "the real tree: the insertion points are there, and core alone is the registry"
t_eq "CHECKS.md has one register insertion point" 1 "$(grep -cx '<!-- private:register -->' "$T_ROOT/CHECKS.md")"
t_eq "CHECKS.md has one platforms insertion point" 1 "$(grep -cx '<!-- private:platforms -->' "$T_ROOT/CHECKS.md")"
t_exit "with no layer the generator prints CHECKS.md unchanged" 0 sh -c "sh '$GEN' --core '$T_ROOT/CHECKS.md' --private '$T_TMP/nowhere' | cmp -s - '$T_ROOT/CHECKS.md'"
OUT="$(sh "$GEN" --core "$T_ROOT/CHECKS.md" --private "$(frag real "$REG" "$PLAT")")"
t_eq "a layer joins the real register: two more ids" "$(( $(ids < "$T_ROOT/CHECKS.md" | wc -l) + 2 ))" "$(printf '%s\n' "$OUT" | ids | wc -l | tr -d ' ')"
t_eq "...and two more platforms rows" "$(( $(pids < "$T_ROOT/CHECKS.md" | wc -l) + 2 ))" "$(printf '%s\n' "$OUT" | pids | wc -l | tr -d ' ')"
t_done
