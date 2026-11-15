#!/usr/bin/env sh
# lint-conventions.sh rules policy.clause-anchored and policy.clause-traced (harbor#1026): each asked alone about a root holding
# only what it reads, silent on the real pair and red on a planted defect. The tool they call is judged in tests/policy/clauses/.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
t_section "lint-conventions asks the rules policy.clause-anchored and policy.clause-traced (harbor#1026)"
LR="$T_TMP/lintroot"; mkdir -p "$LR/bin" "$LR/policy" "$LR/standards/naming"
cp "$T_ROOT/bin/policy-check.sh" "$T_ROOT/bin/library-log.sh" "$LR/bin/"; cp "$T_ROOT/policy/constitution.md" "$T_ROOT/policy/clauses.tsv" "$LR/policy/"
cp "$T_ROOT/standards/naming/terms.tsv" "$T_ROOT/standards/naming/controls.tsv" "$LR/standards/naming/"
t_eq "policy.clause-anchored is silent on the real pair" "" "$(lint1 policy.clause-anchored "$LR" | grep -F 'ADVISORY [policy.clause-anchored]')"
t_has "...and really ran" "$(lint1 policy.clause-anchored "$LR")" "1 rules, 0 violations"
grep -v '^n1.2	' "$T_ROOT/policy/clauses.tsv" > "$LR/policy/clauses.tsv"
t_has "a clause with no row is an ADVISORY (the row is born warn)" "$(lint1 policy.clause-anchored "$LR")" "ADVISORY [policy.clause-anchored]"
cp "$T_ROOT/policy/clauses.tsv" "$LR/policy/clauses.tsv"
t_eq "policy.clause-traced is silent on the real register" "" "$(lint1 policy.clause-traced "$LR" | grep -F 'ADVISORY [policy.clause-traced]')"
sed 's/	admission.merge-raw	/	admission.gone	/' "$T_ROOT/policy/clauses.tsv" > "$LR/policy/clauses.tsv"
t_has "a clause naming a control that does not exist is an ADVISORY" "$(lint1 policy.clause-traced "$LR")" "ADVISORY [policy.clause-traced]"

t_section "policy.enforcement-covered and policy.enforcement-current (harbor#1028)"
mkdir -p "$LR/docs/policy"; cp "$T_ROOT/policy/clauses.tsv" "$LR/policy/clauses.tsv"; cp "$T_ROOT/policy/enforcement.tsv" "$LR/policy/"; cp "$T_ROOT/docs/policy/enforcement.md" "$LR/docs/policy/"
t_eq "policy.enforcement-covered is silent on the real matrix" "" "$(lint1 policy.enforcement-covered "$LR" | grep -F 'ADVISORY [policy.enforcement-covered]')"
t_eq "policy.enforcement-current is silent on the real matrix" "" "$(lint1 policy.enforcement-current "$LR" | grep -F 'ADVISORY [policy.enforcement-current]')"
grep -v '^n1.2/' "$T_ROOT/policy/enforcement.tsv" > "$LR/policy/enforcement.tsv"
t_has "a clause with no pair is an ADVISORY" "$(lint1 policy.enforcement-covered "$LR")" "ADVISORY [policy.enforcement-covered]"
cp "$T_ROOT/policy/enforcement.tsv" "$LR/policy/"; sed 's/| write | 0 | 2 | 2 |/| write | 7 | 7 | 7 |/' "$T_ROOT/docs/policy/enforcement.md" > "$LR/docs/policy/enforcement.md"
t_has "a hand-edited matrix is an ADVISORY" "$(lint1 policy.enforcement-current "$LR")" "ADVISORY [policy.enforcement-current]"

t_done
