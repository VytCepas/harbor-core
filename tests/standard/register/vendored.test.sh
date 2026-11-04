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
t_section "a register column may reference the standard's own register: a workload reads it as the vendored copy"
# a workload has no standards/naming/; its kinds.tsv is vendor/naming/registry/kinds.tsv
rm -f "$R/stray.tsv"
printf 'id\theader\tcolumns\tkey\trefs\towner\tread_by\tnote\nfolders.tsv\trow\tfolder kind\tfolder\tkind>standards/naming/kinds.tsv:id\tstandard\t-\tmine\n' > "$R/naming-schemas.tsv"
printf 'folder\tkind\ndocs/a/\tmemory-store\n' > "$R/folders.tsv"
t_eq "no standards/naming/ in the workload" "no" "$([ -e "$R/standards/naming" ] && echo yes || echo no)"
out="$(tree)"
t_hasnt "a reference to standards/naming/kinds.tsv resolves in the vendored copy" "$out" "[standard.reference-resolves]"
printf 'docs/b/\tno-such-kind\n' >> "$R/folders.tsv"
out="$(tree)"
t_has "a value the vendored kinds.tsv does not hold is still red (it is read, not skipped)" "$out" "no-such-kind"
t_has "...under the target's name, not the vendored path" "$out" "not in standards/naming/kinds.tsv column id"
printf 'id\theader\tcolumns\tkey\trefs\towner\tread_by\tnote\nfolders.tsv\trow\tfolder kind\tfolder\tkind>standards/naming/nosuch.tsv:id\tstandard\t-\tmine\n' > "$R/naming-schemas.tsv"
t_has "a target that is in neither place is red (negative control)" "$(tree)" "the target register standards/naming/nosuch.tsv is not in the tree"
t_section "a repo that vendors under a subdirectory resolves against the copy it declares (harbor#966)"
# yard's shape: the package sits in templates/base/vendor/naming and naming-schemas.tsv declares that copy as a register glob
R2="$T_TMP/repo2"; mkdir -p "$R2/templates/base"; sh "$SV" --source "$H" "$R2/templates/base" >/dev/null 2>&1
printf 'id\theader\tcolumns\tkey\trefs\towner\tread_by\tnote\ntemplates/base/vendor/naming/registry/*.tsv\t=\t=standards/naming/*.tsv\t=\t\tstandard\t-\ta vendored copy\ntemplates/base/vendor/naming/MANIFEST.tsv\tnone\tpath sha256 source\tpath\t\tstandard\t-\tthe manifest\nfolders.tsv\trow\tfolder kind\tfolder\tkind>standards/naming/kinds.tsv:id\tmine\t-\tmine\n' > "$R2/naming-schemas.tsv"
printf 'folder\tkind\ndocs/a/\tmemory-store\n' > "$R2/folders.tsv"
sub() { sh "$T_ROOT/bin/standard-register.sh" --root "$R2" --schemas "$R2/templates/base/vendor/naming/registry/schemas.tsv" --extra "$R2/naming-schemas.tsv" check 2>&1; }
t_eq "no standards/naming/ and no root vendor/naming/ in the repo" "no" "$([ -e "$R2/standards/naming" ] || [ -e "$R2/vendor/naming" ] && echo yes || echo no)"
out="$(sub)"
t_hasnt "a reference to standards/naming/kinds.tsv resolves in the declared subdirectory copy" "$out" "[standard.reference-resolves]"
t_has "...and the repo is green" "$out" "every register is declared and every reference resolves"
printf 'docs/b/\tno-such-kind\n' >> "$R2/folders.tsv"
t_has "a value the declared copy does not hold is still red (it is read, not skipped)" "$(sub)" "not in standards/naming/kinds.tsv column id"
rm -f "$R2/templates/base/vendor/naming/registry/kinds.tsv"
t_has "a declared copy that lacks the register is red (negative control)" "$(sub)" "the target register standards/naming/kinds.tsv is not in the tree"
t_done
