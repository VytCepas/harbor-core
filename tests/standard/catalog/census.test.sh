#!/usr/bin/env sh
# standard-catalog --census, --find, --tree and the harbor verbs (harbor#996 D1, D2): the fixture repo fixes the exact output.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture-repo.sh"
R="$T_TMP/repo"; cat_repo "$R"
EXP="$CAT_FX/expected"
run() { sh "$CAT_TOOL" "$@" --root "$R"; }

t_section "census: one row per tracked file, eleven columns, the exact rows"
t_exit "census exits 0" 0 run --census
t_eq "rows equal git ls-files" "$(git -C "$R" ls-files | wc -l | tr -d ' ')" "$(wc -l < "$R/build/catalog.tsv" | tr -d ' ')"
t_eq "the rows are the expected rows" "$(cat "$EXP/catalog.txt")" "$(cat "$R/build/catalog.tsv")"
t_eq "the findings are the expected findings" "$(cat "$EXP/findings.txt")" "$(cat "$R/build/catalog-findings.tsv")"
t_eq "no level column is blank or '-' without a finding" "" "$(cat_blank_without_finding "$R/build/catalog.tsv" "$R/build/catalog-findings.tsv")"
sh "$CAT_TOOL" --census --root "$R" --out "$T_TMP/again.tsv" >/dev/null 2>&1
t_eq "same input, same bytes" "$(cat "$R/build/catalog.tsv")" "$(cat "$T_TMP/again.tsv")"

t_section "census: how each family was found"
row() { awk -F'\t' -v p="$1" '$2 == p { print $6 }' "$R/build/catalog.tsv"; }
t_eq "the first word of a script" "drift" "$(row bin/drift-install.sh)"
t_eq "the directory of a test" "drift" "$(row tests/drift/install/basic.sh)"
t_eq "a test elsewhere takes its suite's subject" "drift" "$(row tests/misc/legacy.sh)"
t_eq "an unrenamed script takes the family of its new name" "drift" "$(row bin/old-sync.sh)"
t_eq "a dated report skips the date" "drift" "$(row docs/reports/2026-10-01-drift-audit.md)"
t_eq "a standards file belongs to the standard" "standard" "$(row standards/naming/terms.tsv)"
t_eq "a name with no family stays '-'" "-" "$(row bin/legacy-thing.sh)"
t_has "...and the finding says why" "$(cat "$R/build/catalog-findings.tsv")" "'legacy' of legacy-thing.sh is not a registered family"
t_eq "a subsystem is the first non-family ancestor" "control-plane" "$(awk -F'\t' '$2 == "bin/drift-install.sh" { print $5 }' "$R/build/catalog.tsv")"
t_eq "a purpose runs over comment lines and stops at its first sentence" "runs the conventions across the tree and reports each finding once." "$(awk -F'\t' '$2 == "bin/lint-all.sh" { print $11 }' "$R/build/catalog.tsv")"
t_eq "a heading is the purpose of a document" "Drift model" "$(awk -F'\t' '$2 == "docs/design/drift-model.md" { print $11 }' "$R/build/catalog.tsv")"
t_eq "front matter description is the purpose of a skill" "Check whether the installed skills match the tracked ones." "$(awk -F'\t' '$2 == "skills/drift-check/SKILL.md" { print $11 }' "$R/build/catalog.tsv")"
t_eq "a header that says generated sets the layer" "generated" "$(awk -F'\t' '$2 == "generated-counts.md" { print $8 }' "$R/build/catalog.tsv")"

t_section "find: a family's scripts, tests, checks, docs and controls, in that order"
t_eq "find drift is the expected output" "$(cat "$EXP/find-drift.txt")" "$(run --find drift 2>/dev/null)"
t_eq "find by subsystem takes every family under it" "yes" "$(run --find control-plane 2>/dev/null | grep -c 'bin/lint-all.sh' | sed 's/^1$/yes/')"
t_exit "an unknown term exits 1" 1 run --find nosuchthing
t_has "...and names what it tried" "$(run --find nosuchthing 2>&1 || :)" "no such family, subsystem, domain or system: nosuchthing"
t_exit "a registered system catalogued elsewhere is found, exit 0" 0 run --find fleet
t_eq "...with nothing of this checkout listed" "find fleet (system): 0 entries" "$(run --find fleet 2>/dev/null)"
t_exit "find without a term is a usage error" 2 sh "$CAT_TOOL" --find --root "$R"

t_section "tree: the seven levels from the registry"
t_eq "tree is the expected output" "$(cat "$EXP/tree.txt")" "$(run --tree 2>/dev/null)"
t_eq "tree --files drift lists the paths under the components" "$(cat "$EXP/tree-drift-files.txt")" "$(run --tree --files drift 2>/dev/null)"
t_has "the first line names all seven levels" "$(run --tree 2>/dev/null | sed -n 1p)" "metasystem › domain › system › subsystem › family › component › element"
t_exit "an unknown term exits 1" 1 run --tree nosuchthing
t_exit "a registered system catalogued elsewhere narrows to its own node, exit 0" 0 run --tree fleet
t_has "...which says it is not in this tree" "$(run --tree fleet 2>/dev/null)" "system  fleet  (not in this tree)"
t_eq "the root line is the level alone, not a workload system's name" "metasystem" "$(run --tree 2>/dev/null | sed -n 2p)"
t_exit "--files without --tree is a usage error" 2 sh "$CAT_TOOL" --census --files --root "$R"

t_section "harbor find and harbor tree are the same answers"
t_eq "harbor find drift" "$(cat "$EXP/find-drift.txt")" "$(sh "$T_ROOT/bin/harbor" find drift --root "$R" 2>/dev/null)"
t_eq "harbor tree" "$(cat "$EXP/tree.txt")" "$(sh "$T_ROOT/bin/harbor" tree --root "$R" 2>/dev/null)"
t_has "CONTRACTS/cli.md lists find" "$(cat "$T_ROOT/CONTRACTS/cli.md")" '| `harbor find` | `standard-catalog.sh --find` |'
t_has "CONTRACTS/cli.md lists tree" "$(cat "$T_ROOT/CONTRACTS/cli.md")" '| `harbor tree` | `standard-catalog.sh --tree` |'

t_section "census on this checkout: the registry fills what it can, and a finding names the rest"
sh "$CAT_TOOL" --census --root "$T_ROOT" --out "$T_TMP/real/catalog.tsv" >/dev/null 2>&1
t_exit "the map is tracked, so the rows can equal git ls-files" 0 git -C "$T_ROOT" ls-files --error-unmatch docs/context-map.md
t_eq "rows equal git ls-files" "$(git -C "$T_ROOT" ls-files | wc -l | tr -d ' ')" "$(wc -l < "$T_TMP/real/catalog.tsv" | tr -d ' ')"
t_eq "no level column is blank or '-' without a finding" "" "$(cat_blank_without_finding "$T_TMP/real/catalog.tsv" "$T_TMP/real/catalog-findings.tsv")"
t_done
