#!/usr/bin/env sh
# bin/gate-required-generate.sh and what reads its sum (harbor#1149): core's CONTRACTS/required-checks.tsv holds harbor's own rows,
# the private layer's required-checks.tsv the rows whose repo cannot be named in core, and a reader sees one list. runtime-install installs the sum as
# bin/required-checks.tsv and install-drift holds it to the composition at the ref. Layers are throwaway directories; the repos
# and checks are made up and name no real entity.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
GEN="$T_ROOT/bin/gate-required-generate.sh"
CORE="$T/core.tsv"; printf '# core: harbor only\nacme/core\tgate\n' > "$CORE"
gen() { HARBOR_SCOPE_PRIVATE="$1" sh "$GEN" --core "${2:-$CORE}" 2>"$T/gen.err"; }   # stdout is the rows; stderr is $T/gen.err
layer() { mkdir -p "$T/pv-$1"; printf '%b' "$2" > "$T/pv-$1/required-checks.tsv"; printf '%s' "$T/pv-$1"; }

t_section "the sum: core's rows, then the layer's, verbatim"
t_exit "no layer at all: core, byte for byte" 0 sh -c "HARBOR_SCOPE_PRIVATE='$T/nowhere' sh '$GEN' --core '$CORE' | cmp -s - '$CORE'"
mkdir -p "$T/pv-empty"
t_exit "a layer with no required-checks.tsv: core, byte for byte" 0 sh -c "HARBOR_SCOPE_PRIVATE='$T/pv-empty' sh '$GEN' --core '$CORE' | cmp -s - '$CORE'"
PV="$(layer hdr '# only a header\n\n')"
t_exit "a file holding no row: core, byte for byte" 0 sh -c "HARBOR_SCOPE_PRIVATE='$PV' sh '$GEN' --core '$CORE' | cmp -s - '$CORE'"
PV="$(layer a '# other repos\nacme/other\tCI gate\nacme/other\tlint\n')"
printf '# core: harbor only\nacme/core\tgate\n# other repos\nacme/other\tCI gate\nacme/other\tlint\n' > "$T/want.a"
t_exit "a layer with rows: core, then the layer, verbatim" 0 sh -c "HARBOR_SCOPE_PRIVATE='$PV' sh '$GEN' --core '$CORE' | cmp -s - '$T/want.a'"
printf 'acme/core\tgate' > "$T/core.nonl"
printf 'acme/core\tgate\n# other repos\nacme/other\tCI gate\nacme/other\tlint\n' > "$T/want.nonl"
t_exit "a core with no final newline does not swallow the layer's first row" 0 sh -c "HARBOR_SCOPE_PRIVATE='$PV' sh '$GEN' --core '$T/core.nonl' | cmp -s - '$T/want.nonl'"
PV="$(layer add 'acme/core\textra\n')"
t_eq "the layer can add a check to a core repo" "gate extra" "$(gen "$PV" | awk -F'\t' '$1 == "acme/core" { printf "%s%s", sep, $2; sep = " " }')"
t_exit "...and every core row is still there, in order" 0 sh -c "HARBOR_SCOPE_PRIVATE='$PV' sh '$GEN' --core '$CORE' | head -n 2 | cmp -s - '$CORE'"
t_eq "the default core is this checkout's CONTRACTS/required-checks.tsv" "yes" "$(HARBOR_SCOPE_PRIVATE="$T/nowhere" sh "$GEN" | cmp -s - "$T_ROOT/CONTRACTS/required-checks.tsv" && echo yes)"

t_section "a layer that cannot be composed refuses the whole read, with nothing on stdout"
refuses() { # <label> <printf-format content> <expected message>
  PV="$(layer bad "$2")"; _o="$(gen "$PV")"; _rc=$?
  t_eq "$1: exit 2" 2 "$_rc"; t_eq "...nothing on stdout" "" "$_o"; t_has "...naming the line: $3" "$(cat "$T/gen.err")" "$3"
}
refuses "one field" 'acme/other CI gate\n' 'line 1: expected repo TAB check name, got 1 field(s)'
refuses "three fields" 'acme/other\tCI gate\textra\n' 'line 1: expected repo TAB check name, got 3 field(s)'
refuses "a repo that is not owner/name" '# fine\nother\tCI gate\n' 'line 2: the repo is not owner/name'
refuses "an empty check name" 'acme/other\t \n' 'line 1: the check name is empty'
refuses "a carriage return" 'acme/other\tCI gate\r\n' 'line 1: a carriage return'
refuses "a good row after a bad one is not a partial read" 'acme/other\tCI gate\nacme/other CI\n' 'line 2'
t_has "the fix names the layer's file" "$(cat "$T/gen.err")" "required-checks.tsv"
t_eq "an unreadable core is exit 2" 2 "$(HARBOR_SCOPE_PRIVATE="$T/nowhere" sh "$GEN" --core "$T/missing.tsv" >/dev/null 2>&1; echo $?)"
t_eq "an unknown argument is exit 2" 2 "$(sh "$GEN" --bogus >/dev/null 2>&1; echo $?)"

t_section "a layer file that exists and cannot be read refuses; it is never read as no rows"
PV="$(layer unr 'acme/other\tCI gate\n')"; chmod 000 "$PV/required-checks.tsv"
if [ -r "$PV/required-checks.tsv" ]; then t_pass; t_pass; t_pass   # root reads a 000 file: the three arms need a user who cannot
else
  _o="$(gen "$PV")"; _rc=$?
  t_eq "an unreadable file: exit 2" 2 "$_rc"; t_eq "...nothing on stdout, not core alone" "" "$_o"; t_has "...saying it is not readable" "$(cat "$T/gen.err")" "could not be read"
fi
chmod 644 "$PV/required-checks.tsv"
mkdir -p "$T/pv-dir/required-checks.tsv"
_o="$(gen "$T/pv-dir")"; _rc=$?
t_eq "a directory where the file belongs: exit 2" 2 "$_rc"; t_eq "...nothing on stdout" "" "$_o"
mkdir -p "$T/pv-dangling"; ln -sf "$T/gone.tsv" "$T/pv-dangling/required-checks.tsv"
_o="$(gen "$T/pv-dangling")"; _rc=$?
t_eq "a dangling link where the file belongs: exit 2" 2 "$_rc"; t_eq "...nothing on stdout" "" "$_o"

t_section "the layer's own history: --layer-revs lists the commits that touched the file, --private-rev composes one"
LG="$T/pv-git"; mkdir -p "$LG"; git init -q "$LG"
printf 'acme/other\tCI gate\n' > "$LG/required-checks.tsv"; git -C "$LG" add -A
git -C "$LG" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm one; L1="$(git -C "$LG" rev-parse HEAD)"
printf 'acme/other\tCI gate\nacme/other\tlint\n' > "$LG/required-checks.tsv"
git -C "$LG" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qam two; L2="$(git -C "$LG" rev-parse HEAD)"
t_eq "--layer-revs: newest first" "$L2 $L1" "$(sh "$GEN" --private "$LG" --layer-revs | paste -sd' ' -)"
t_eq "...nothing for a directory that is not a repo" "" "$(sh "$GEN" --private "$T/pv-empty" --layer-revs)"
printf '# core: harbor only\nacme/core\tgate\nacme/other\tCI gate\n' > "$T/want.rev1"
printf '# core: harbor only\nacme/core\tgate\nacme/other\tCI gate\nacme/other\tlint\n' > "$T/want.rev2"
t_exit "--private-rev: the first revision composes to core plus its one row" 0 sh -c "sh '$GEN' --core '$CORE' --private '$LG' --private-rev '$L1' | cmp -s - '$T/want.rev1'"
printf 'acme/other\tCI gate\nacme/other\tlint\nacme/zzz\tx\n' > "$LG/required-checks.tsv"   # an edit nobody committed
t_exit "...the second composes to both, and an uncommitted edit is not read" 0 sh -c "sh '$GEN' --core '$CORE' --private '$LG' --private-rev '$L2' | cmp -s - '$T/want.rev2'"
git -C "$LG" checkout -q -- required-checks.tsv
_o="$(sh "$GEN" --core "$CORE" --private "$LG" --private-rev 0123456789abcdef0123456789abcdef01234567 2>/dev/null)"; _rc=$?
t_eq "a commit the layer does not hold: exit 2" 2 "$_rc"; t_eq "...nothing on stdout" "" "$_o"
t_eq "a revision that is not hex is refused" 2 "$(sh "$GEN" --core "$CORE" --private "$LG" --private-rev '--output=x' >/dev/null 2>&1; echo $?)"

t_section "red-proof: the checks above can fail"
MB="$T/mut/bin"; mkdir -p "$MB"; cp "$T_ROOT/bin/log-lib.sh" "$MB/"
sed '/NF != 2 {/d' "$GEN" > "$MB/gate-required-generate.sh"
t_exit "M1 the field-count check is removed: the mutation applies" 1 cmp -s "$MB/gate-required-generate.sh" "$GEN"
PV="$(layer m1 'acme/other\tCI gate\textra\n')"
t_eq "M1: a three-field row is then composed, not refused" 0 "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$MB/gate-required-generate.sh" --core "$CORE" >/dev/null 2>&1; echo $?)"
sed 's#^cat "\$OVL"$#:#' "$GEN" > "$MB/gate-required-generate.sh"
t_exit "M2 the layer is never appended: the mutation applies" 1 cmp -s "$MB/gate-required-generate.sh" "$GEN"
PV="$(layer m2 'acme/other\tCI gate\n')"
t_eq "M2: the layer's row is then missing from the sum" "" "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$MB/gate-required-generate.sh" --core "$CORE" 2>/dev/null | grep 'acme/other' || :)"

# M3 the not-a-file refusal is removed, M4 a grep that failed to read is taken for "no rows": each must turn an arm above red
sed '/exists and is not a file/d' "$GEN" > "$MB/gate-required-generate.sh"
t_exit "M3 the not-a-file refusal is removed: the mutation applies" 1 cmp -s "$MB/gate-required-generate.sh" "$GEN"
PV="$(layer m3 'acme/other\tCI gate\n')"; mkdir -p "$T/m3dir/required-checks.tsv"
t_eq "M3: a directory where the file belongs is then read as no rows (exit 0)" 0 "$(HARBOR_SCOPE_PRIVATE="$T/m3dir" sh "$MB/gate-required-generate.sh" --core "$CORE" >/dev/null 2>&1; echo $?)"
sed 's#\*) _refuse "could not be read"[^;]*;;#*) cat "$CORE"; exit 0 ;;#' "$GEN" > "$MB/gate-required-generate.sh"
t_exit "M4 a grep that failed is taken for no rows: the mutation applies" 1 cmp -s "$MB/gate-required-generate.sh" "$GEN"
PV="$(layer m4 'acme/other\tCI gate\n')"; chmod 000 "$PV/required-checks.tsv"
if [ -r "$PV/required-checks.tsv" ]; then t_pass   # root
else t_eq "M4: an unreadable file is then read as no rows (exit 0)" 0 "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$MB/gate-required-generate.sh" --core "$CORE" >/dev/null 2>&1; echo $?)"; fi
chmod 644 "$PV/required-checks.tsv"

ri() { env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/runtime-install.sh" "$@"; }
t_section "runtime-install: the installed list is core when there is no layer, the sum when there is"
D="$T/cfg-none"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
HARBOR_SCOPE_PRIVATE="$T/nowhere" ri --apply --dir "$D" >/dev/null 2>&1
t_exit "no layer: bin/required-checks.tsv is CONTRACTS/required-checks.tsv, byte for byte" 0 cmp -s "$T_ROOT/CONTRACTS/required-checks.tsv" "$D/bin/required-checks.tsv"
PV="$(layer ri 'acme/other\tCI gate\n')"; D="$T/cfg-a"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
_plan="$(HARBOR_SCOPE_PRIVATE="$PV" ri --dir "$D" 2>&1)"
t_has "the dry run says the list is composed" "$_plan" "bin/required-checks.tsv is composed: core plus 1 row(s) from the private layer"
t_eq "...and wrote nothing" no "$([ -e "$D/bin/required-checks.tsv" ] && echo yes || echo no)"
HARBOR_SCOPE_PRIVATE="$PV" ri --apply --dir "$D" >/dev/null 2>&1
t_exit "a layer: the installed list holds the layer's row" 0 grep -q "^acme/other${TAB}CI gate\$" "$D/bin/required-checks.tsv"
t_exit "...and every one of core's rows" 0 sh -c "grep '^[^#]' '$T_ROOT/CONTRACTS/required-checks.tsv' | grep . | while IFS= read -r l; do grep -qxF \"\$l\" '$D/bin/required-checks.tsv' || exit 1; done"
t_eq "the installed file is the generator's output" "yes" "$(HARBOR_SCOPE_PRIVATE="$PV" sh "$GEN" | cmp -s - "$D/bin/required-checks.tsv" && echo yes)"
t_hasnt "an install whose list loses nothing says nothing of drops" "$(HARBOR_SCOPE_PRIVATE="$PV" ri --dir "$D" 2>&1)" "DROPS"
printf '# the layer lost its row\n' > "$PV/required-checks.tsv"
_plan="$(HARBOR_SCOPE_PRIVATE="$PV" ri --dir "$D" 2>&1)"
t_has "a layer edit that removes its row: the plan warns the gate gets smaller" "$_plan" "DROPS 1 required-check row(s)"
t_has "...and names the row" "$_plan" "acme/other CI gate"
t_has "...with the cause to look for" "$_plan" "or the layer is not found"
t_exit "...and the dry run left the installed list as it was" 0 grep -q "^acme/other${TAB}CI gate\$" "$D/bin/required-checks.tsv"
printf 'acme/other CI gate\n' > "$PV/required-checks.tsv"
D="$T/cfg-bad"; mkdir -p "$D"; printf '{}' > "$D/settings.json"
HARBOR_SCOPE_PRIVATE="$PV" ri --apply --dir "$D" > "$T/bad.out" 2>&1; _rc=$?
t_eq "a layer that does not compose refuses the install" 1 "$_rc"
t_has "...and says so" "$(cat "$T/bad.out")" "does not compose with core's"
t_eq "...writing no list" no "$([ -e "$D/bin/required-checks.tsv" ] && echo yes || echo no)"

t_section "install-drift: the installed list is held to the composition at the ref"
R="$T/repo"; CFG="$T/install"; mkdir -p "$R/bin" "$R/CONTRACTS" "$CFG/bin"
cp "$T_ROOT/bin/install-drift.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$GEN" "$R/bin/"
printf 'DATA="CONTRACTS/required-checks.tsv:bin/required-checks.tsv"\n' > "$R/bin/runtime-install.sh"
cp "$CORE" "$R/CONTRACTS/required-checks.tsv"
git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm v1
drift() { HARBOR_SCOPE_PRIVATE="$1" sh "$R/bin/install-drift.sh" --dir "$CFG" --ref main 2>&1; }
PV="$(layer dr 'acme/other\tCI gate\n')"
sh "$R/bin/gate-required-generate.sh" --core "$R/CONTRACTS/required-checks.tsv" --private "$PV" > "$CFG/bin/required-checks.tsv"
t_has "the composed list is current when its layer is there" "$(drift "$PV")" "current=1 stale=0 modified=0 unsourced=0"
t_has "...and reads modified when the layer is gone (it is no longer what would be installed)" "$(drift "$T/nowhere")" "FAIL: modified required-checks.tsv ("
cp "$R/CONTRACTS/required-checks.tsv" "$CFG/bin/required-checks.tsv"
t_has "the bare core list is current when there is no layer" "$(drift "$T/nowhere")" "current=1 stale=0 modified=0 unsourced=0"
t_has "...and reads stale, not edited in place, when a layer would add rows to it (a list installed before it was composed)" "$(drift "$PV")" "FAIL: stale required-checks.tsv ("

# An install is BEHIND when core moved on, or the layer did: the layer is a repo of its own and records the file's revisions.
PG="$T/pv-drift"; mkdir -p "$PG"; git init -q "$PG"
gc() { _gd="$1"; shift; git -C "$_gd" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q "$@"; }
printf 'acme/other\tCI gate\n' > "$PG/required-checks.tsv"; git -C "$PG" add -A; gc "$PG" -m l1
sh "$R/bin/gate-required-generate.sh" --core "$R/CONTRACTS/required-checks.tsv" --private "$PG" > "$CFG/bin/required-checks.tsv"
t_has "a list composed from this core and this layer revision is current" "$(drift "$PG")" "current=1 stale=0 modified=0 unsourced=0"
printf 'acme/other\tCI gate\nacme/other\tlint\n' > "$PG/required-checks.tsv"; gc "$PG" -am l2
t_has "the layer gained a row since the deploy: stale" "$(drift "$PG")" "FAIL: stale required-checks.tsv ("
printf '# core: harbor only\nacme/core\tgate\nacme/core\tlint\n' > "$R/CONTRACTS/required-checks.tsv"; git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qam v2
t_has "...and core gained one as well: still stale" "$(drift "$PG")" "FAIL: stale required-checks.tsv ("
t_has "...whose fix is a redeploy" "$(drift "$PG")" "fix: sh "
printf 'acme/other\tCI gate\nacme/other\tlint\nacme/other\tunreviewed\n' > "$PG/required-checks.tsv"
sh "$R/bin/gate-required-generate.sh" --core "$R/CONTRACTS/required-checks.tsv" --private "$PG" > "$CFG/bin/required-checks.tsv"
t_has "an uncommitted layer row, deployed, is what the layer says: current" "$(drift "$PG")" "current=1 stale=0 modified=0 unsourced=0"
git -C "$PG" checkout -q -- required-checks.tsv
t_has "...and once the layer drops it, no commit explains the installed row: modified" "$(drift "$PG")" "FAIL: modified required-checks.tsv ("
t_has "...and the fix names the generator, not a box-only capture" "$(drift "$PG")" "gate-required-generate.sh"
sh "$R/bin/gate-required-generate.sh" --core "$R/CONTRACTS/required-checks.tsv" --private "$PG" | grep -v "^acme/core${TAB}gate\$" > "$CFG/bin/required-checks.tsv"
t_has "a core row dropped from the installed list is not behind, it is edited: modified" "$(drift "$PG")" "FAIL: modified required-checks.tsv ("
t_done
