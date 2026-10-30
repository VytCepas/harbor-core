#!/usr/bin/env sh
# overlay.test.sh (harbor#967) — the repo overlay: naming-words.tsv and naming-families.tsv at a judged root.
# A planted family turns a family finding green, a shadowing or malformed row is red, harbor's own tree is never
# changed by one, no view carries a repo family, and the vendored judge reads it with no harbor checkout.
. "$(dirname "$0")/../../lib/core.sh"; t_init
# the suite never reads the box's private or pack overlays (D-85, harbor#950)
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; CLAUDE_CONFIG_DIR="$TMP/no-config"; export HARBOR_SCOPE_PRIVATE CLAUDE_CONFIG_DIR; unset PORT_ROOT
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
. "$T_ROOT/tests/lint/name/fixture.sh"   # mini <dir>
TAB="$(printf '\t')"
THDR="$(grep -v '^#' "$REG/terms.tsv" | head -n 1)"
family() { printf '%s\tfamily\t%s\t-\t-\texperimental\t-\ttest\t-\t-\t%s\n' "$1" "$1" "${2:-A family of this repo}"; }   # <id> [definition]
families() { { printf '%s\n' "$THDR"; for _f in "$@"; do family "$_f"; done; } > "$R/naming-families.tsv"; }
words() { { printf 'id\tnote\n'; for _w in "$@"; do printf '%s\t-\n' "$_w"; done; } > "$R/naming-words.tsv"; }
judge() { sh "$LN" --root "$1" --registry "${2:-$REG}" --format findings 2>/dev/null; }   # <root> [registry] -> findings
jrc() { sh "$LN" --root "$1" --registry "${2:-$REG}" > /dev/null 2>&1; echo $?; }
plain() { printf '%s\n' "$1" | cut -f2- | LC_ALL=C sort; }   # findings without the A/V column
# the findings about the repo's names, as gates/naming-check.sh keeps them: registry rules judge harbor's tree, not this one
names() { printf '%s\n' "$1" | awk -F'\t' 'NF >= 3 && $2 !~ /^name\.(registry-|exemption-|alias-expired|control-|surface-)/'; }

# A repo outside harbor: no standards/naming/ of its own, judged with harbor's registry, as gates/naming-check.sh does.
R="$TMP/repo"; mkdir -p "$R/bin" "$R/tests/corpus/build" "$R/docs"
: > "$R/bin/corpus-build.sh"; : > "$R/tests/corpus/build/run.test.sh"; : > "$R/docs/qzxv-notes.md"

t_section "a repo family turns its family findings green; a repo word, its word finding"
_b="$(judge "$R")"
t_has "with no overlay, bin/ under an unregistered family is name.family" "$_b" "name.family${TAB}bin/corpus-build.sh"
t_has "…and its tests directory is name.test-path" "$_b" "name.test-path${TAB}tests/corpus"
t_has "…and an unregistered word is name.word-unregistered" "$_b" "name.word-unregistered${TAB}docs/qzxv-notes.md"
t_has "--check bin judges the same name red" "$(sh "$LN" --root "$R" --registry "$REG" --check bin corpus-build.sh --format findings 2>/dev/null)" "name.family"
families corpus; words qzxv
_a="$(judge "$R")"
t_hasnt "with corpus in naming-families.tsv, bin/corpus-build.sh is no name.family finding" "$_a ." "name.family${TAB}bin/corpus-build.sh"
t_hasnt "…nor tests/corpus a name.test-path finding" "$_a ." "name.test-path${TAB}tests/corpus"
t_hasnt "…and with qzxv in naming-words.tsv, docs/qzxv-notes.md is no word finding" "$_a ." "docs/qzxv-notes.md"
t_eq "the repo now has no finding on its names at all" "" "$(names "$_a")"
t_eq "--check bin judges it green from the same root" "" "$(sh "$LN" --root "$R" --registry "$REG" --check bin corpus-build.sh --format findings 2>/dev/null)"
t_exit "…and a commit scoped to the repo family" 0 sh "$LN" --root "$R" --registry "$REG" --check commit "feat(corpus): add the intake"

t_section "a row that shadows harbor is red, and no exemption row hides it"
families audit
t_exit "a repo family that is a harbor family fails the run" 1 sh "$LN" --root "$R" --registry "$REG"
t_has "…as a block name.overlay-shadow finding" "$(judge "$R")" "V${TAB}name.overlay-shadow${TAB}overlay:naming-families.tsv:audit"
families install
t_has "a repo family that is a harbor verb is name.overlay-shadow" "$(judge "$R")" "name.overlay-shadow${TAB}overlay:naming-families.tsv:install"
families corpus; words cfg
t_has "a repo word that is a harbor alias is name.overlay-shadow" "$(judge "$R")" "name.overlay-shadow${TAB}overlay:naming-words.tsv:cfg"
X="$TMP/reg-exempt"; cp -R "$REG" "$X"
printf 'tool-9999\tname.overlay-shadow\toverlay:naming-words.tsv:cfg\ttool-required\tnever\ta row trying to hide a shadow\n' >> "$X/exemptions.tsv"
t_has "an exemptions.tsv row naming the finding does not hide it" "$(judge "$R" "$X")" "name.overlay-shadow${TAB}overlay:naming-words.tsv:cfg"
words drift
t_has "a repo word harbor already holds as a term is name.overlay-shadow" "$(judge "$R")" "name.overlay-shadow${TAB}overlay:naming-words.tsv:drift"
words qzxv

t_section "a malformed overlay is red"
{ printf 'word\tnote\nqzxv\t-\n'; } > "$R/naming-words.tsv"
t_has "a header row that is not words.tsv's is name.overlay-shape" "$(judge "$R")" "name.overlay-shape${TAB}overlay:naming-words.tsv:header"
t_has "…and its rows are not read, so the word is unregistered again" "$(judge "$R")" "name.word-unregistered${TAB}docs/qzxv-notes.md"
{ printf 'id\tnote\nqzxv\t-\textra\n'; } > "$R/naming-words.tsv"
t_has "a row with the wrong column count is name.overlay-shape" "$(judge "$R")" "name.overlay-shape${TAB}overlay:naming-words.tsv:line2"
{ printf '%s\n' "$THDR"; printf 'corpus\tverb\tcorpus\t-\t-\texperimental\t-\ttest\t-\t-\tA verb\n'; } > "$R/naming-families.tsv"; words qzxv
t_has "a family row whose class is not family is name.overlay-shape" "$(judge "$R")" "name.overlay-shape${TAB}overlay:naming-families.tsv:corpus"
t_has "…and the family is not registered" "$(judge "$R")" "name.family${TAB}bin/corpus-build.sh"
{ printf '%s\n' "$THDR"; family corpus -; } > "$R/naming-families.tsv"
t_has "a family row with no definition is name.overlay-shape" "$(judge "$R")" "name.overlay-shape${TAB}overlay:naming-families.tsv:corpus"
families corpus
chmod 000 "$R/naming-families.tsv"
t_exit "an overlay that cannot be read is UNCHECKED (exit 3), never clean" 3 sh "$LN" --root "$R" --registry "$REG"
chmod 644 "$R/naming-families.tsv"
t_exit "--check overlay on a directory that does not exist is a usage error" 2 sh "$LN" --check overlay "$TMP/nowhere"
t_exit "--check overlay judges a directory's overlay: green here" 0 sh "$LN" --check overlay "$R"

t_section "no view carries a repo family (D-13 CLI tree, labels, validators)"
for _v in cli-tree labels validators; do sh "$LN" --root "$R" --registry "$REG" --gen "$_v" > /dev/null 2>&1; done
t_eq "--gen cli-tree wrote the tree" "yes" "$([ -s "$R/build/naming/cli-tree.txt" ] && echo yes)"
t_hasnt "…and corpus is not one of its families" "$(cat "$R/build/naming/cli-tree.txt")" "corpus"
t_hasnt "--gen labels has no family:corpus" "$(cat "$R/build/naming/labels.tsv")" "corpus"
t_hasnt "--gen validators has no corpus in any slot" "$(cat "$R/build/validators.txt")" "corpus"

t_section "harbor's own tree: an overlay there is refused and changes no other finding"
t_eq "the harbor checkout carries no overlay" "" "$(find "$T_ROOT" -maxdepth 1 -name 'naming-*.tsv')"
M="$TMP/harbor-copy"; mini "$M"
: > "$M/bin/corpus-build.sh"
_h0="$(judge "$M" "$M/standards/naming")"
t_has "a harbor tree with bin/corpus-build.sh has its name.family finding" "$_h0" "name.family${TAB}bin/corpus-build.sh"
cp "$R/naming-families.tsv" "$R/naming-words.tsv" "$M/"
_h1="$(judge "$M" "$M/standards/naming")"
t_has "an overlay planted at its root is name.overlay-shape" "$_h1" "name.overlay-shape${TAB}overlay:naming-families.tsv"
t_eq "…and every other finding is the one it had without it" "$(plain "$_h0")" "$(plain "$(printf '%s\n' "$_h1" | awk -F'\t' '$2 != "name.overlay-shape"')")"
t_exit "…and the run fails" 1 sh "$LN" --root "$M" --registry "$M/standards/naming"

t_section "the vendored judge reads the overlay with no harbor checkout"
V="$TMP/vendored"; mkdir -p "$V/bin"; : > "$V/bin/corpus-build.sh"
sh "$T_ROOT/bin/standard-vendor.sh" "$V" > /dev/null 2>&1
t_eq "bin/standard-vendor.sh wrote vendor/naming/lint-name.sh" "yes" "$([ -f "$V/vendor/naming/lint-name.sh" ] && echo yes)"
t_eq "…the same lint as harbor's" "same" "$(cmp -s "$LN" "$V/vendor/naming/lint-name.sh" && echo same)"
# gates/naming-check.sh's pattern: the vendored lint, a copy of its registry, the repo as --root
cp -R "$V/vendor/naming/registry" "$TMP/vreg"
_v0="$(sh "$V/vendor/naming/lint-name.sh" --root "$V" --registry "$TMP/vreg" --format findings 2>/dev/null)"
t_has "with no overlay the vendored judge has the family finding" "$_v0" "name.family${TAB}bin/corpus-build.sh"
cp "$R/naming-families.tsv" "$V/"
_v1="$(sh "$V/vendor/naming/lint-name.sh" --root "$V" --registry "$TMP/vreg" --format findings 2>/dev/null)"
t_hasnt "…and with naming-families.tsv at the repo root it is gone" "$_v1 ." "name.family${TAB}bin/corpus-build.sh"
families audit; cp "$R/naming-families.tsv" "$V/"
t_has "…and a shadowing row is red there too" "$(sh "$V/vendor/naming/lint-name.sh" --root "$V" --registry "$TMP/vreg" --format findings 2>/dev/null)" "name.overlay-shadow${TAB}overlay:naming-families.tsv:audit"
t_done
