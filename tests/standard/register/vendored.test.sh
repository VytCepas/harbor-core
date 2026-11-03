#!/usr/bin/env sh
# The naming package a repo vendors carries the reader (harbor#1424): a scaffolded repo is red on a .tsv no schema row
# declares, and green once it declares it in naming-schemas.tsv. The red proof is the first, on a repo built from the package.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SV="$T_ROOT/bin/standard-vendor.sh"
H="$T_TMP/harbor"; R="$T_TMP/repo"
mkdir -p "$H/bin" "$H/standards/naming"
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/lint-renderer.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-vendor.sh" "$T_ROOT/bin/standard-register.sh" "$T_ROOT/bin/doc-shape.sh" "$T_ROOT/bin/doc-fresh-verify.sh" "$T_ROOT/bin/standard-kit.sh" "$H/bin/"
cp "$T_ROOT"/standards/naming/*.tsv "$H/standards/naming/"
mkdir -p "$R"; sh "$SV" --source "$H" "$R" >/dev/null 2>&1
L="vendor/naming/lint-name.sh"
tree() { (cd "$R" && sh "$L" --root . --registry vendor/naming/registry 2>&1); }

t_section "the package ships the reader"
t_eq "standard-register.sh is vendored and executable" "yes" "$([ -x "$R/vendor/naming/standard-register.sh" ] && echo yes || echo no)"
t_has "its manifest row" "$(cat "$R/vendor/naming/MANIFEST.tsv")" "standard-register.sh	"
t_has "the schema table travels with the registry" "$(ls "$R/vendor/naming/registry")" "schemas.tsv"
out="$(cd "$R" && sh vendor/naming/standard-register.sh get vendor/naming/registry/kinds.tsv id folder 2>&1 | head -n 1)"
t_has "the vendored reader reads a vendored register by name" "$out" "memory-store"

t_section "a repo with only vendored registers is green; an undeclared .tsv is red"
t_hasnt "no register finding on the bare package" "$(tree)" "[standard.register-declared]"
printf 'id\tn\nx\t1\n' > "$R/stray.tsv"
t_has "an undeclared .tsv is red" "$(tree)" "[standard.register-declared]"
t_has "...and named" "$(tree)" "stray.tsv is a .tsv with no row in schemas.tsv"
printf 'id\theader\tcolumns\tkey\trefs\towner\tread_by\tnote\nstray.tsv\trow\tid n\tid\t\tstandard\t-\tmine\n' > "$R/naming-schemas.tsv"
out="$(tree)"; t_hasnt "declared in naming-schemas.tsv it is green" "$out" "stray.tsv is a .tsv with no row"
t_hasnt "...and so is naming-schemas.tsv itself, which the table declares" "$out" "naming-schemas.tsv is a .tsv with no row"
t_done
