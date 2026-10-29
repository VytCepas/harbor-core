#!/usr/bin/env sh
# bin/lint-name.sh --gen issue-taxonomy (harbor#978): the label list is generated from label-axes.tsv, never a second copy.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_SCOPE_PRIVATE="$T_TMP/no-private"; export HARBOR_SCOPE_PRIVATE
R="$T_TMP/r"; mkdir -p "$R/standards"; cp -R "$T_ROOT/standards/naming" "$R/standards/naming"
gen() { sh "$T_ROOT/bin/lint-name.sh" --root "$R" --gen issue-taxonomy >/dev/null 2>&1; }
t_section "the generated taxonomy and map"
t_exit "--gen issue-taxonomy exits 0" 0 sh "$T_ROOT/bin/lint-name.sh" --root "$R" --gen issue-taxonomy
TX="$R/build/naming/issue-taxonomy.tsv"; MP="$R/build/naming/label-map.tsv"
t_has "a type label is rendered as type:<value>" "$(cat "$TX")" "$(printf 'type\ttype:bug\t-')"
t_has "P0-critical maps to priority:p0" "$(cat "$MP")" "$(printf 'P0-critical\tpriority:p0\tok')"
t_has "an axis row becomes a #AXIS cardinality line" "$(cat "$TX")" "$(printf '#AXIS\ttype\t1\t1')"
for l in bug feature task chore spike documentation tech-debt P0-critical finding; do
  t_eq "bare label $l is mapped" 1 "$(cut -f1 "$MP" | grep -cx -- "$l")"
done
t_section "no second list: every connector label is the legacy of a registry row"
for l in $(awk -F'\t' '!/^#/ && NF >= 2 { print $2 }' "$T_ROOT/contracts/issue-taxonomy.tsv"); do
  t_eq "contracts/issue-taxonomy.tsv label $l is covered" 1 "$(cut -f1 "$MP" | grep -cx -- "$l")"
done
t_section "every family: row names a registered family"
for f in $(awk -F'\t' '$1 ~ /^family:/ { sub(/^family:/, "", $1); print $1 }' "$R/standards/naming/label-axes.tsv"); do
  t_has "family:$f is a terms.tsv family" "$(awk -F'\t' '$1 == "'"$f"'" { print $2 }' "$R/standards/naming/terms.tsv")" "family"
done
t_section "a registry edit changes the output with no other edit"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "type:bug" { $1 = "type:defect" } { print }' "$T_ROOT/standards/naming/label-axes.tsv" > "$R/standards/naming/label-axes.tsv"
gen
t_has "renaming the id in the registry renames the generated label" "$(cat "$TX")" "type:defect"
t_hasnt "…and the old id is gone" "$(cat "$TX")" "type:bug"
t_section "--gen vendors: a dialect checker's vendor list is the registry's (harbor#985)"
VR="$T_TMP/v"; mkdir -p "$VR/standards"; cp -R "$T_ROOT/standards/naming" "$VR/standards/naming"
vgen() { sh "$T_ROOT/bin/lint-name.sh" --root "$VR" --gen vendors >/dev/null 2>&1; }
t_exit "--gen vendors exits 0" 0 sh "$T_ROOT/bin/lint-name.sh" --root "$VR" --gen vendors
VT="$VR/build/naming/vendors.tsv"
t_has "fb maps to meta as a legacy token" "$(cat "$VT")" "$(printf 'fb\tmeta\tlegacy')"
t_has "the current vendor term is listed" "$(cat "$VT")" "$(printf 'meta\tmeta\tcurrent')"
sed 's/^fb\tmeta/fb\tmetaa/' "$T_ROOT/standards/naming/aliases.tsv" > "$VR/standards/naming/aliases.tsv"
vgen
t_has "mutation: changing the registry changes the result" "$(cat "$VT")" "$(printf 'fb\tmetaa\tlegacy')"
t_done
