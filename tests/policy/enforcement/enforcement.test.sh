#!/usr/bin/env sh
# bin/policy-check.sh --enforcement, --promotion, --gen enforcement and --report (harbor#1028): clause x moment -> mode, the promotion rule, the matrix.
. "$(dirname "$0")/../../lib/core.sh"; t_init
PC="$T_ROOT/bin/policy-check.sh"; FX="$T_ROOT/fixtures/policy"
pc() { sh "$PC" "$@" 2>&1; }
prc() { sh "$PC" "$@" >/dev/null 2>&1; echo $?; }
fxrun() { _d="$FX/$1"; shift; (cd "$_d" && sh "$PC" --root "$_d" "$@" 2>&1); }

t_section "the real matrix covers the real constitution"
t_eq "--enforcement is green: every clause has a pair" 0 "$(prc --enforcement)"
t_has "...and counts them" "$(pc --enforcement)" "pair(s) over"
t_eq "--promotion is green: no block pair is promoted without a proof and 28 days" 0 "$(prc --promotion)"
t_eq "every clause id in the matrix is a clause, and every clause is in it" "$(awk -F'\t' '!/^#/ && $1 != "id" { print $1 }' "$T_ROOT/policy/clauses.tsv" | sort)" "$(awk -F'\t' '!/^#/ && $1 != "id" { print $2 }' "$T_ROOT/policy/enforcement.tsv" | sort -u)"
t_eq "every moment in the matrix is in the closed set" "" "$(awk -F'\t' '!/^#/ && $1 != "id" { print $3 }' "$T_ROOT/policy/enforcement.tsv" | sort -u | grep -vxE 'write|session|commit|pr|merge|schedule|deploy|judgment' || :)"
t_eq "every moment is a term of class moment" "" "$(for m in write session commit pr merge schedule deploy judgment; do awk -F'\t' -v m="$m" '$1 == m && $2 ~ /moment/ { f = 1 } END { if (!f) print m }' "$T_ROOT/standards/naming/terms.tsv"; done)"

t_section "each rule goes red on its fixture, and its twin stays green"
t_has "a clause with no pair" "$(fxrun red-enforcement-missing --enforcement)" "[policy.enforcement-missing]"
t_has "a pair that binds later than it is checkable, with no reason" "$(fxrun red-enforcement-late --enforcement)" "[policy.enforcement-late]"
t_has "a mode that differs from the control's" "$(fxrun red-enforcement-drift --enforcement)" "[policy.enforcement-mode-drift]"
t_has "a promotion inside 28 days" "$(fxrun red-promotion-early --promotion)" "[policy.promotion-too-early]"
t_has "a promotion with no red proof" "$(fxrun red-promotion-no-proof --promotion)" "[policy.promotion-no-red-proof]"
t_eq "the pass twin of the enforcement rules" 0 "$(cd "$FX/pass-enforcement" && sh "$PC" --root . --enforcement >/dev/null 2>&1; echo $?)"
t_eq "the pass twin of the promotion rule" 0 "$(cd "$FX/pass-promotion" && sh "$PC" --root . --promotion >/dev/null 2>&1; echo $?)"
t_eq "a promotion is judged on the day the run is asked about (HARBOR_POLICY_TODAY)" 0 "$(cd "$FX/red-promotion-early" && HARBOR_POLICY_TODAY=2100-06-01 sh "$PC" --root . --promotion >/dev/null 2>&1; echo $?)"

t_section "the matrix is generated, and a hand edit is red (item 5)"
t_has "a current matrix passes its --check" "$(fxrun pass-matrix --gen enforcement --check)" "is current"
t_has "a hand-edited matrix fails it" "$(fxrun red-matrix-stale --gen enforcement --check)" "[policy.gen-stale]"
t_eq "the real matrix is current" 0 "$(prc --gen enforcement --check)"
t_has "the matrix counts judgment per strength" "$(cat "$T_ROOT/docs/policy/enforcement.md")" "Judgment share per strength"
t_has "...and names the pairs never seen red" "$(cat "$T_ROOT/docs/policy/enforcement.md")" "Pairs never seen red"

t_section "the batch report proposes and never edits (item 6)"
t_has "a pair whose control was never red is proposed" "$(fxrun red-promotion-no-proof --report)" "PROPOSE: [policy.enforcement-report] t.1/fx.two"
t_eq "the pair that was seen red is not" "0" "$(fxrun pass-promotion --report | grep -c 'PROPOSE' || :)"
before="$(cksum < "$FX/red-promotion-no-proof/policy/enforcement.tsv")"; fxrun red-promotion-no-proof --report >/dev/null
t_eq "the report edited no mode" "$before" "$(cksum < "$FX/red-promotion-no-proof/policy/enforcement.tsv")"
t_has "its register row names its destination" "$(cat "$T_ROOT/docs/reference/checks.md")" "policy.enforcement-report"
t_has "...and its control row is a check of that register" "$(grep '^check.policy.enforcement-report' "$T_ROOT/standards/naming/controls.tsv")" "docs/reference/checks.md"
t_done
