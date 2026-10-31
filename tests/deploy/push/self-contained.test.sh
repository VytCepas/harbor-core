#!/usr/bin/env sh
# The core export is self-consistent (harbor#1149): staged as bin/deploy-push.sh stages it, no core document cites a
# dev-layer file, and the two rules whose subject IS a generated dev-layer file (docs/generated/status.md, docs/generated/plan.md) say they skipped.
# The subject is this checkout's HEAD, not the working tree: the list of files comes from `deploy-push.sh --dry-run`
# itself, so the classifier under test is the one that exports. The leak gate it also runs is another suite's subject
# (a red gate does not stop the list being printed), so the exit code of that dry run is not read here.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_TEST_IN_SUITE HARBOR_IN_SUITE

PV="$T_TMP/pv"; mkdir -p "$PV"; printf 'id\tkind\tpattern\tnote\n' > "$PV/leaks.tsv"
LIST="$T_TMP/core.files"; RAW="$T_TMP/raw"; S="$T_TMP/export"; mkdir -p "$RAW" "$S"
HARBOR_SCOPE_PRIVATE="$PV" HARBOR_SCOPE_ROOT="$T_ROOT" sh "$T_ROOT/bin/deploy-push.sh" --dry-run > "$LIST" 2>/dev/null || :
NCORE="$(wc -l < "$LIST" | tr -d ' ')"
git -C "$T_ROOT" archive HEAD | tar -xf - -C "$RAW"
tar -cf - -C "$RAW" -T "$LIST" | tar -xf - -C "$S"
( cd "$S" && git init -q . && git add -f -A ) >/dev/null 2>&1

# one rule, asked alone about the staged export, by the export's own copy of the linter
lint() { HARBOR_SCOPE_ROOT="$S" sh "$S/bin/lint-conventions.sh" --only "$1" 2>&1; }
GREEN='1 rules, 0 violations'; DEAD='cites a path that does not exist:'
# a plant: append a line to a staged file, run one rule, put the file back
plant() { # <file> <line> <rule> → the rule's output with the line in place
  cp "$S/$1" "$T_TMP/plant.orig"; printf '%s\n' "$2" >> "$S/$1"
  lint "$3"; cp "$T_TMP/plant.orig" "$S/$1"
}

t_section "the staged export is the core and only the core"
[ "$NCORE" -gt 100 ] && t_pass || t_fail "deploy-push --dry-run listed $NCORE files, so nothing was staged (a refusal prints none)"
t_eq "...and every listed file is staged" "$NCORE" "$(find "$S" -path "$S/.git" -prune -o \( -type f -o -type l \) -print | wc -l | tr -d ' ')"
t_eq "...no docs/generated/status.md" "" "$(find "$S" -name docs/generated/status.md -print)"
t_eq "...no EVALS-DATA/" "" "$(find "$S" -name EVALS-DATA -print)"
t_eq "...layers.tsv, which names the dev layer, is there" "yes" "$([ -f "$S/contracts/layers.tsv" ] && echo yes || echo no)"

t_section "no core document cites a dev-layer file"
for r in doc.paths-resolve policy.constitution-paths; do
  _o="$(lint "$r")"
  t_has "$r is green over the export" "$_o" "$GREEN"
  t_hasnt "...and names no dead citation" "$_o" "$DEAD"
done

t_section "the rules about docs/generated/status.md and docs/generated/plan.md skip, aloud, in the export"
_o="$(lint doc.status-generated)"
t_has "doc.status-generated is green" "$_o" "$GREEN"
t_has "...and says it skipped" "$_o" "(skipped: docs/generated/status.md is dev-layer"
_o="$(lint doc.plan-generated)"
t_has "doc.plan-generated is green" "$_o" "$GREEN"
t_has "...and says it skipped" "$_o" "(skipped: docs/generated/plan.md is generated from docs/reports/platform-build-tickets.md"

t_section "a planted dev link in a core document is red"
_o="$(plant README.md 'See [the ledger](./docs/reports/rejected-approaches.md).' doc.paths-resolve)"
t_has "README.md linking docs/reports/rejected-approaches.md" "$_o" "README.md $DEAD ./docs/reports/rejected-approaches.md"
_o="$(plant contracts/README.md 'See [the counts](../docs/generated/status.md).' doc.paths-resolve)"
t_has "contracts/README.md linking docs/generated/status.md" "$_o" "contracts/README.md $DEAD ../docs/generated/status.md"
_o="$(plant docs/explanation/doc-truth.md 'See [the notes](../docs/how-to/handover.md).' doc.paths-resolve)"
t_has "docs/explanation/doc-truth.md linking docs/how-to/handover.md" "$_o" "docs/explanation/doc-truth.md $DEAD ../docs/how-to/handover.md"
_o="$(plant docs/README.md 'See [the counts](../docs/generated/status.md).' doc.paths-resolve)"
t_has "docs/README.md linking docs/generated/status.md (docs/ is swept)" "$_o" "docs/README.md $DEAD ../docs/generated/status.md"
_o="$(plant standards/naming.md 'See [the plan](../docs/generated/plan.md).' doc.paths-resolve)"
t_has "standards/naming.md linking docs/generated/plan.md (standards/ is swept)" "$_o" "standards/naming.md $DEAD ../docs/generated/plan.md"
_o="$(plant policy/constitution.md 'Read `./docs/how-to/handover.md` first.' policy.constitution-paths)"
t_has "policy/constitution.md citing ./docs/how-to/handover.md" "$_o" "policy/constitution.md $DEAD docs/how-to/handover.md"
# the rest of the exported markdown: a dev link here resolves in the dev checkout and dangles in the export, so only the
# export can see it. One file per directory the sweep used to skip, picked from what is staged.
first_md() { find "$S/$1" -type f -name '*.md' | LC_ALL=C sort | sed -n 1p | sed "s#^$S/##"; }
for _d in skills commands context-rules patches vendor/archify fixtures; do
  _f="$(first_md "$_d")"
  [ -n "$_f" ] || { t_fail "$_d has no staged markdown to plant in, so its sweep went unproved"; continue; }
  _up="$(printf '%s' "${_f%/*}" | sed 's#[^/][^/]*#..#g')"; [ "$_f" != "${_f%/*}" ] || _up=.
  _o="$(plant "$_f" "See [the counts]($_up/docs/generated/status.md)." doc.paths-resolve)"
  t_has "$_f linking docs/generated/status.md" "$_o" "$_f $DEAD $_up/docs/generated/status.md"
done
# each rule alone, because one green line must not vouch for the other: a plant left behind in the files only
# doc.paths-resolve reads would leave policy.constitution-paths green, and the joined text would still hold the needle
t_has "...doc.paths-resolve is green again once the plants are put back" "$(lint doc.paths-resolve)" "$GREEN"
t_has "...policy.constitution-paths is green again too" "$(lint policy.constitution-paths)" "$GREEN"

t_section "files an adopter writes do not make the export a dev tree"
# core tells a session to write docs/how-to/handover.md (hooks/session-state/session-state.sh) and names docs/reports/rejected-approaches.md as the in-repo ledger
# (contracts/memory-format.md). Both are dev-layer rows, neither is a witness, and neither may turn the rules red with a
# fix the export cannot run (status-plan-generate.sh: "no plan at docs/reports/platform-build-tickets.md").
both() { printf '%s\n%s\n' "$(lint doc.status-generated)" "$(lint doc.plan-generated)"; }
printf 'a handoff note\n' > "$S/docs/how-to/handover.md"
_o="$(both)"
t_has "an untracked docs/how-to/handover.md: both rules still skip" "$_o" "(skipped: docs/generated/plan.md is generated"
t_has "...docs/generated/status.md's too" "$_o" "(skipped: docs/generated/status.md is dev-layer"
t_hasnt "...and neither is red" "$_o" "VIOLATION"
printf 'a ledger\n' > "$S/docs/reports/rejected-approaches.md"
_o="$(both)"
t_hasnt "an untracked docs/reports/rejected-approaches.md beside it: still not red" "$_o" "VIOLATION"
git -C "$S" add -f docs/how-to/handover.md docs/reports/rejected-approaches.md
_o="$(both)"
t_has "both COMMITTED to the index: both rules still skip" "$_o" "(skipped: docs/generated/plan.md is generated"
t_hasnt "...and neither is red" "$_o" "VIOLATION"
git -C "$S" rm -q --cached -f docs/how-to/handover.md docs/reports/rejected-approaches.md; rm -f "$S/docs/how-to/handover.md" "$S/docs/reports/rejected-approaches.md"
mkdir -p "$S/docs/generated"; printf 'a plan of my own\n' > "$S/docs/generated/plan.md"
_o="$(lint doc.plan-generated)"
t_has "an adopter's own docs/generated/plan.md has no source to be stale against: skipped" "$_o" "(skipped: docs/generated/plan.md is generated"
t_hasnt "...not red" "$_o" "VIOLATION"
rm -f "$S/docs/generated/plan.md"

t_section "the skip is for a tree without the dev layer: where the plan source is, the rules judge"
printf '# tickets\n' > "$S/docs/reports/platform-build-tickets.md"
_o="$(lint doc.status-generated)"
t_has "the plan source back on disk: a missing docs/generated/status.md is red" "$_o" "docs/generated/status.md is stale"
t_hasnt "...and not skipped" "$_o" "(skipped"
_o="$(lint doc.plan-generated)"
t_has "...a missing docs/generated/plan.md is red" "$_o" "docs/generated/plan.md is stale"
t_hasnt "...and not skipped" "$_o" "(skipped"
git -C "$S" add -f docs/reports/platform-build-tickets.md; rm -f "$S/docs/reports/platform-build-tickets.md"
_o="$(both)"
t_has "the plan source deleted from disk but still in the index: docs/generated/status.md is red" "$_o" "docs/generated/status.md is stale"
t_has "...and docs/generated/plan.md is red" "$_o" "docs/generated/plan.md is stale"
t_hasnt "...neither skipped" "$_o" "(skipped"
git -C "$S" rm -q --cached -f docs/reports/platform-build-tickets.md
t_has "...and the export is skipped again with it gone" "$(both)" "(skipped: docs/generated/plan.md is generated"
mkdir -p "$S/docs/generated"; printf 'not what status-gen prints\n' > "$S/docs/generated/status.md"
_o="$(lint doc.status-generated)"
t_has "a docs/generated/status.md in the export is checked, not skipped" "$_o" "docs/generated/status.md is stale"
rm -f "$S/docs/generated/status.md"
t_has "...and the export is skipped again with it gone" "$(lint doc.status-generated)" "(skipped: docs/generated/status.md is dev-layer"

t_done
