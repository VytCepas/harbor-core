#!/usr/bin/env sh
# bin/standard-register.sh (harbor#1424): one reader finds a register's columns by NAME through schemas.tsv, and the tree is
# judged both ways. The red proofs: shift a header, repeat a key, drop a row, add an undeclared .tsv, dangle a reference —
# each is a finding on a throwaway tree, and the real tree reads clean.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SR="$T_ROOT/bin/standard-register.sh"
R="$T_TMP/repo"
mkrepo() { rm -rf "$R"; mkdir -p "$R/contracts" "$R/standards/naming"
  printf '# schemas.tsv\n# standard_version: 2.0.0\nid\theader\tcolumns\tkey\trefs\towner\tread_by\tnote\n' > "$R/standards/naming/schemas.tsv"
  printf '# terms\nid\tclass\nstandard\tfamily\nlint\tfamily\n' > "$R/standards/naming/terms.tsv"
  printf 'standards/naming/schemas.tsv\trow\tid header columns key refs owner read_by note\tid\t\tstandard\t-\tthe table\n' >> "$R/standards/naming/schemas.tsv"
  printf 'standards/naming/terms.tsv\trow\tid class\tid\t\tstandard\t-\tterms\n' >> "$R/standards/naming/schemas.tsv"
  printf 'contracts/pets.tsv\trow\tid kind owner\tid\towner>standards/naming/terms.tsv:id\tstandard\t-\tpets\n' >> "$R/standards/naming/schemas.tsv"
  printf '# pets\nid\tkind\towner\nrex\tdog\tstandard\ntom\tcat\tlint\n' > "$R/contracts/pets.tsv"; }
run() { sh "$SR" --root "$R" "$@" 2>&1; }
mkrepo

t_section "get reads columns by name, in the order asked, whatever the file's order"
t_eq "two columns, reversed" "dog	rex
cat	tom" "$(run get contracts/pets.tsv kind id)"
t_eq "--where narrows" "tom" "$(run get --where kind=cat contracts/pets.tsv id)"
t_has "--header names the columns" "$(run get --header contracts/pets.tsv id)" "id"
t_eq "cols prints the declared columns" "id kind owner" "$(run cols contracts/pets.tsv)"
t_exit "an unknown column is usage (2)" 2 sh "$SR" --root "$R" get contracts/pets.tsv nope
t_exit "a file with no schema row is unchecked (3)" 3 sh "$SR" --root "$R" get contracts/none.tsv id

t_section "a register that is not what its row says reads as NOTHING, never as shifted columns"
printf '# pets\nid\towner\tkind\nrex\tstandard\tdog\n' > "$R/contracts/pets.tsv"
out="$(run get contracts/pets.tsv owner)"; rc=0; sh "$SR" --root "$R" get contracts/pets.tsv owner >/dev/null 2>&1 || rc=$?
t_eq "a reordered header exits 1" 1 "$rc"; t_has "and names the header" "$out" "the header row is"
t_hasnt "and prints no row" "$out" "dog"
mkrepo; printf 'bad\tcat\n' >> "$R/contracts/pets.tsv"
rc=0; sh "$SR" --root "$R" get contracts/pets.tsv id >/dev/null 2>&1 || rc=$?; t_eq "a short row exits 1" 1 "$rc"
mkrepo; printf 'rex\tcat\tlint\n' >> "$R/contracts/pets.tsv"
out="$(run get contracts/pets.tsv id)"; t_has "a repeated key is named" "$out" "repeats the key id=rex"

t_section "facts: undeclared file, row with no file, dangling reference — each red, then green when put right"
mkrepo; t_eq "a clean tree has no finding" "" "$(run facts)"
printf 'id\tx\n' > "$R/contracts/stray.tsv"
t_has "an undeclared .tsv is red" "$(run facts)" "contracts/stray.tsv is a .tsv with no row in schemas.tsv"
rm "$R/contracts/stray.tsv"; t_eq "...and green once removed" "" "$(run facts)"
rm "$R/contracts/pets.tsv"; t_has "a row whose file is gone is red" "$(run facts)" "contracts/pets.tsv has a row in schemas.tsv and no file in the tree"
mkrepo; printf 'zed\tfish\tzz-ghost\n' >> "$R/contracts/pets.tsv"
t_has "a dangling reference is red" "$(run facts)" "owner is zz-ghost, which is not in standards/naming/terms.tsv column id"
t_has "...under its own rule" "$(run facts)" "G	standard.reference-resolves"
mkrepo; printf 'zed\tfish\t-\n' >> "$R/contracts/pets.tsv"; t_eq "a - cell is no reference" "" "$(run facts)"
mkrepo; printf 'contracts/maybe.tsv?\trow\tid owner\tid\t\tstandard\t-\ta register a repo may or may not carry\n' >> "$R/standards/naming/schemas.tsv"
t_eq "a row marked ? may have no file" "" "$(run facts)"
printf 'id\towner\nx\tstandard\n' > "$R/contracts/maybe.tsv"; t_eq "...and is read when it has" "" "$(run facts)"
mkdir -p "$R/contracts/fixtures" "$R/tests"; printf 'a\tb\n' > "$R/contracts/fixtures/x.tsv"; printf 'a\tb\n' > "$R/tests/y.tsv"
t_eq "fixtures/ and test* paths are outside the scope" "" "$(run facts)"

t_section "a copy row borrows the original's columns; a repo's own rows come from --extra"
mkrepo; mkdir -p "$R/vendor/naming/registry"; cp "$R/standards/naming/terms.tsv" "$R/vendor/naming/registry/terms.tsv"
printf 'vendor/naming/registry/*.tsv\t=\t=standards/naming/*.tsv\t=\t\tstandard\t-\tcopies\n' >> "$R/standards/naming/schemas.tsv"
t_eq "a vendored copy is read by the original's columns" "standard" "$(run get vendor/naming/registry/terms.tsv id | head -n 1)"
printf 'id\tZZ\nstandard\tfamily\n' > "$R/vendor/naming/registry/terms.tsv"
t_has "...and a copy whose header differs from the original's is red" "$(run facts)" "vendor/naming/registry/terms.tsv line"
HDR='id\theader\tcolumns\tkey\trefs\towner\tread_by\tnote'
mkrepo; { printf '%b\n' "$HDR"; printf 'own.tsv\tnone\tname\tname\t\tstandard\t-\tmine\n'; } > "$T_TMP/extra.tsv"; printf 'a\n' > "$R/own.tsv"
t_eq "--extra declares a repo's own register" "" "$(run --extra "$T_TMP/extra.tsv" facts)"
t_has "...without it the file is undeclared" "$(run facts)" "own.tsv is a .tsv with no row"
rm "$R/own.tsv"; t_has "an --extra row with no file is red" "$(run --extra "$T_TMP/extra.tsv" facts)" "own.tsv has a row in the repo schema rows and no file"
# a repo that vendors the table: harbor's rows describe files it does not carry, which is not a finding there
mkrepo; mkdir -p "$R/vendor/naming/registry"; mv "$R/standards/naming/schemas.tsv" "$T_TMP/vendored-table.tsv"; rm -rf "$R/standards"
t_eq "a row whose file is absent is no finding where the table is only vendored" "" "$(run --schemas "$T_TMP/vendored-table.tsv" facts | grep 'no file in the tree' || :)"

t_section "the real tree"
t_exit "every real register is declared and every reference resolves" 0 sh "$SR" check
t_exit "controls.tsv is read by name from the real tree" 0 sh "$SR" get --where type=lint standards/naming/controls.tsv id engine
# the core export ships no dev-layer file, so a row naming one must carry the ? that says the file may be absent (harbor#1424)
DEVROWS="$(awk -F'\t' '$1 !~ /^#/ && $1 != "id" && $1 !~ /[*?]/ { print $1 }' "$T_ROOT/standards/naming/schemas.tsv" |
  LAYERS_FILE="$T_ROOT/contracts/layers.tsv" sh "$T_ROOT/bin/scope-layers.sh" --classify | awk -F'\t' '$NF == "dev" { print $1 }')"
t_eq "a schema row for a dev-layer file is optional, so the core export stays clean" "" "$DEVROWS"
t_eq "the register index is produced" "| Register |" "$(sh "$SR" index | head -n 1 | cut -c1-12)"
t_done
