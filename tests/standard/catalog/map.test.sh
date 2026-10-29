#!/usr/bin/env sh
# standard-catalog --map and --check (harbor#996 D3): green on a fresh docs/context-map.md, red on planted drift.
# The last section runs --check on THIS checkout: that is the CI gate, a PR that adds a file regenerates the map.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture-repo.sh"
R="$T_TMP/repo"; cat_repo "$R"
chk() { sh "$CAT_TOOL" --check --root "$R"; }

t_section "map: written from the catalog, byte for byte the expected page"
rm -f "$R/docs/context-map.md"
t_exit "--check is red while the map is absent" 1 chk
t_exit "--map exits 0" 0 sh "$CAT_TOOL" --map --root "$R"
t_eq "the map is the expected page" "$(cat "$CAT_FX/expected/context-map.txt")" "$(cat "$R/docs/context-map.md")"
t_has "it opens with context-map front matter" "$(sed -n 1,2p "$R/docs/context-map.md")" "kind: context-map"

t_section "check: green when fresh"
git -C "$R" add -A
t_exit "--check exits 0 on a fresh map" 0 chk
t_has "...and says so" "$(chk 2>&1)" "docs/context-map.md equals a fresh map"

t_section "check: red on planted drift, green again once regenerated"
printf '\nA line a person added by hand.\n' >> "$R/docs/context-map.md"
t_exit "a hand edit to the map exits 1" 1 chk
t_has "...and names the fix" "$(chk 2>&1 || :)" "sh bin/standard-catalog.sh --map"
sh "$CAT_TOOL" --map --root "$R" >/dev/null 2>&1
t_exit "regenerated, exit 0" 0 chk
printf '#!/usr/bin/env sh\n# drift-new.sh — added after the map was written.\n' > "$R/bin/drift-new.sh"; git -C "$R" add bin/drift-new.sh
t_exit "a new tracked file without a regenerated map exits 1" 1 chk
git -C "$R" rm -q -f --cached bin/drift-new.sh
t_exit "the file untracked again, exit 0" 0 chk
git -C "$R" rm -q -f --cached bin/drift-skills.sh
t_exit "a tracked file removed without a regenerated map exits 1" 1 chk
git -C "$R" add bin/drift-skills.sh
t_exit "put back, exit 0" 0 chk
sed 's/^| drift | control-plane |/| drift | observability |/' "$R/docs/context-map.md" > "$T_TMP/m"; cp "$T_TMP/m" "$R/docs/context-map.md"
t_exit "a wrong cell in the table exits 1" 1 chk
# A bare backtick: GNU sed reads \` as buffer start, so the plant was a no-op on Linux CI.
sed 's/broader` chain/broader` chain (edited)/' "$CAT_FX/expected/context-map.txt" > "$R/docs/context-map.md"
t_exit "an edited sentence exits 1" 1 chk

t_section "check: the registry is what the map is read from"
sh "$CAT_TOOL" --map --root "$R" >/dev/null 2>&1
awk -F'\t' -v OFS='\t' '$1 == "drift" { $4 = "observability" } { print }' "$R/standards/naming/terms.tsv" > "$T_TMP/t" && cp "$T_TMP/t" "$R/standards/naming/terms.tsv"
t_exit "moving a family to another subsystem makes the map stale" 1 chk

if [ -d "$T_ROOT/evals" ]; then
  t_section "check: this checkout's docs/context-map.md is fresh (the CI gate)"
  t_exit "docs/context-map.md equals a fresh map" 0 sh "$CAT_TOOL" --check --root "$T_ROOT"
fi   # an exported core tree has no evals: the map of the full tree is not re-derivable there, so the section is not opened
t_done
