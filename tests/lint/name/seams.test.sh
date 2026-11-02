#!/usr/bin/env sh
# standard.seam-registered (harbor#1425): a vendored copy or MANIFEST.tsv with no row in contracts/seams.tsv is red, and so is a row
# whose copy is gone or whose schema this tree owns and does not hold. Each arm is a repo built from the vendored package.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SV="$T_ROOT/bin/standard-vendor.sh"
H="$T_TMP/harbor"; R="$T_TMP/repo"
mkdir -p "$H/bin" "$H/standards/naming"
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/lint-renderer.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-vendor.sh" "$T_ROOT/bin/standard-register.sh" "$T_ROOT/bin/doc-shape.sh" "$T_ROOT/bin/doc-fresh-verify.sh" "$H/bin/"
cp "$T_ROOT"/standards/naming/*.tsv "$H/standards/naming/"
mkdir -p "$R/contracts"; sh "$SV" --source "$H" "$R" >/dev/null 2>&1
tree() { (cd "$R" && sh vendor/naming/lint-name.sh --root . --registry vendor/naming/registry 2>&1); }
TAB="$(printf '\t')"
HDR="id${TAB}kind${TAB}producer${TAB}consumer${TAB}copy_path${TAB}pin${TAB}schema${TAB}freshness${TAB}owner${TAB}allowed_lag${TAB}reason"
row() { printf '%s\n' "$1${TAB}$2${TAB}$3${TAB}$4${TAB}$5${TAB}$6${TAB}$7${TAB}$8${TAB}standard${TAB}0${TAB}-"; }
seams() { { printf '# seams (fixture)\n# standard_version: 2.0.0\n%s\n' "$HDR"; cat; } > "$R/contracts/seams.tsv"; }
R_=standard.seam-registered

t_section "a tree whose every copy has a row is green"
row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - - | seams
t_hasnt "no seam finding" "$(tree)" "[$R_]"

t_section "a MANIFEST.tsv with no row is red, and names the copy"
mkdir -p "$R/vendor/zz"; printf 'path\tsha256\tsource\n' > "$R/vendor/zz/MANIFEST.tsv"
OUT="$(tree)"
t_has "red" "$OUT" "[$R_]"
t_has "...naming vendor/zz/" "$OUT" "vendor/zz/ is a vendored copy with no row"

t_section "a row for it turns it green"
{ row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - -; row zz upstream x harbor vendor/zz/ - - -; } | seams
t_hasnt "green" "$(tree)" "[$R_]"

t_section "a vendor/<name>/ directory with no MANIFEST.tsv is a copy too"
mkdir -p "$R/vendor/loose"; printf 'x\n' > "$R/vendor/loose/file.txt"
t_has "red" "$(tree)" "vendor/loose/ is a vendored copy with no row"

t_section "a row whose copy is gone is red"
rm -rf "$R/vendor/loose"
{ row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - -; row zz upstream x harbor vendor/zz/ - - -; row ghost vendor x harbor vendor/ghost/ - - -; } | seams
OUT="$(tree)"
t_has "red" "$OUT" "[$R_]"
t_has "...naming the row" "$OUT" "row ghost names the copy vendor/ghost/"

t_section "a copy marked ? (dev layer, not exported) may be absent, and still covers the copy when present"
{ row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - -; row zz upstream x harbor vendor/zz/ - - -; row ghost upstream x harbor 'vendor/ghost/?' - - -; } | seams
t_hasnt "an absent optional copy is green" "$(tree)" "[$R_]"
{ row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - -; row zz upstream x harbor 'vendor/zz/?' - - -; } | seams
t_hasnt "a present optional copy is covered by its row" "$(tree)" "[$R_]"

t_section "a schema this tree owns and does not hold is red"
{ row self vendor harbor harbor vendor/naming/ MANIFEST.tsv#harbor_commit - -; row zz upstream x harbor vendor/zz/ - - -; row s format harbor yard - - contracts/schemas/none.schema.json -; } | seams
t_has "red" "$(tree)" "row s names the schema contracts/schemas/none.schema.json"

t_section "a tree with no register is silent (a workload carries none)"
rm -f "$R/contracts/seams.tsv"
t_hasnt "no seam finding" "$(tree)" "[$R_]"
t_done
