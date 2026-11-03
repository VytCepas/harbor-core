#!/usr/bin/env sh
# name.repo-verb (harbor#1428): bin/lint-name.sh --check repo-kind holds a justfile's recipe names against verbs.tsv. Split from
# tests/lint/name/name.test.sh at the 500-line budget (tests/README.md T2); the fixtures come from tests/lint/name/fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; export HARBOR_SCOPE_PRIVATE; unset PORT_ROOT
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
. "$T_ROOT/tests/lint/name/fixture.sh"   # mini <dir>, mkrk, rk
RB="$TMP/rkblock"; mini "$RB"
t_section "repo-verb: the justfile's recipe names are held against verbs.tsv (harbor#1428)"
rv() { sh "$LN" --check repo-kind "$1" --format findings 2>&1; }
mkjf() { # <dir> <kind> <recipe-names...> : a whole repo of <kind> whose justfile has exactly these recipes
  _jd="$(mkrk "$1" "$2" README.md AGENTS.md CLAUDE.md docs/)"; shift 2; : > "$_jd/justfile"
  for _r in "$@"; do printf '%s:\n    true\n' "$_r" >> "$_jd/justfile"; done; printf '%s' "$_jd"
}
ALLW="$(vrecipes workload | tr -d ':' | tr '\n' ' ')"
t_has "a workload justfile with every required verb is clean" "$(rk "$(mkjf vok workload $ALLW)")" "no finding"
VN="$(rv "$(mkjf vno workload $(printf '%s\n' $ALLW | grep -vx 'test'))")"
t_has "a missing verb is a name.repo-verb finding naming it" "$VN" "[name.repo-verb] repo-verb:test"
t_has "…and its record carries no path, so a repo exempts it by verb" "$VN" "A	name.repo-verb	repo-verb:test"
t_hasnt "…while a verb that is there is not named" "$VN" "repo-verb:lint "
t_hasnt "a test-quick recipe is not the verb test" "$(rv "$(mkjf vtq workload $ALLW)")" "repo-verb:test-quick"
t_has "a variable assignment is not a recipe" "$(rv "$(mkjf vvar workload $(printf '%s\n' $ALLW | grep -vx 'ci'); printf 'ci := 1\n' >> "$RKD/vvar/justfile")")" "repo-verb:ci"
t_has "an indented line is a recipe body, not a recipe" "$(rv "$(mkjf vind workload $(printf '%s\n' $ALLW | grep -vx 'ci'); printf '    ci: x\n' >> "$RKD/vind/justfile")")" "repo-verb:ci"
t_has "a recipe with parameters is a recipe" "$(rv "$(mkjf vpar workload $(printf '%s\n' $ALLW | grep -vx 'docs'); printf 'docs *args:\n    true\n' >> "$RKD/vpar/justfile")")" "no finding"
t_hasnt "an optional verb is not required (test-mutation, code-map)" "$VN" "repo-verb:test-mutation"
t_hasnt "a control-plane needs only lint and test: no verb is missing" "$(rv "$(mkjf vcp control-plane lint test)")" "name.repo-verb"
t_has "…and lacking test is a finding for it too" "$(rv "$(mkjf vcp2 control-plane lint)")" "repo-verb:test"
t_hasnt "no justfile is name.repo-kind's finding, not one per verb" "$(rv "$(mkrk vnone workload README.md AGENTS.md CLAUDE.md docs/)")" "name.repo-verb"
t_exit "born warn: a missing verb exits 0" 0 sh "$LN" --check repo-kind "$RKD/vno"
awk -F'\t' 'BEGIN { OFS = "\t" } $1 == "name.repo-verb" { $2 = "block" } { print }' "$REG/controls.tsv" > "$RB/standards/naming/controls.tsv"
t_exit "…and at block it exits 1" 1 sh "$RB/bin/lint-name.sh" --root "$RB" --check repo-kind "$RKD/vno"
VX="$TMP/vexempt"; rm -rf "$VX"; mkdir -p "$VX"; cp -R "$REG" "$VX/naming"
printf 'tool-9001\tname.repo-verb\trepo-verb:test\ttool-required\tnever\ta fixture exemption\n' >> "$VX/naming/exemptions.tsv"
t_hasnt "a repo's exemption row (rule name.repo-verb, subject repo-verb:<id>) silences that verb" "$(sh "$LN" --registry "$VX/naming" --check repo-kind "$RKD/vno" 2>&1)" "repo-verb:test"
t_has "…and only that verb" "$(sh "$LN" --registry "$VX/naming" --check repo-kind "$(mkjf vno2 workload $(printf '%s\n' $ALLW | grep -vx 'test' | grep -vx 'ci'))" 2>&1)" "repo-verb:ci"
t_eq "the label list is generated from label-axes.tsv and terms.tsv: type:bug is in it" "type:bug" "$(sh "$LN" --gen labels --root "$TMP/vexempt" --registry "$REG" > /dev/null 2>&1; cut -f1 "$TMP/vexempt/build/naming/labels.tsv" | grep -x 'type:bug')"
t_eq "…and an axis row (epic) is not a label" "" "$(cut -f1 "$TMP/vexempt/build/naming/labels.tsv" | grep -x 'epic')"
t_done
