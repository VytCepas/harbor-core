#!/usr/bin/env sh
# The core skills' own checkers inside CI (R5, contracts/gates.md): each checker's --self-test. The measurement skills'
# checkers (topology, casefile, tracking-standards) left core with them (harbor#1149): their --self-tests, the R5
# falsifier and the maps contract run from the measurement pack's tests/skills/, which reads this checkout for the
# core half of each cross-check (check-routes.sh's write-verb deny-list, doc-report-verify.sh).
. "$(dirname "$0")/../../lib/core.sh"; t_init
ROUTES="$T_ROOT/skills/access-ledger/bin/check-routes.sh"

t_section "calibration: exit codes are read exactly"
t_exit "exit 0 is read as 0" 0 sh -c 'exit 0'
t_exit "exit 1 is read as 1" 1 sh -c 'exit 1'
t_exit "exit 2 is read as 2" 2 sh -c 'exit 2'
t_exit "exit 127 is read as 127" 127 sh -c 'exit 127'

t_section "each checker still discriminates"
# Exit 0 alone passed a checker emptied to `exit 0` (harbor#667 mutation pass): the count line is the witness.
counted() { printf '%s\n' "$1" | awk -v re="$2" '$0 ~ re { f = 1 } END { print f ? "yes" : "no" }'; }
_st="$(sh "$ROUTES" --self-test 2>&1)"; _rc=$?
t_eq "check-routes.sh --self-test exits 0" 0 "$_rc"
t_eq "...and counts its passes, none failed" yes "$(counted "$_st" '^self-test: [1-9][0-9]* passed, 0 failed$')"
t_has "...and its mutations went red" "$_st" "caught: "
_st="$(sh "$T_ROOT/bin/doc-report-verify.sh" --self-test 2>&1)"; _rc=$?
t_eq "doc-report-verify.sh --self-test exits 0 (harbor#411)" 0 "$_rc"
t_eq "...and counts its ok lines, none failed" yes "$(counted "$_st" '^report-contract: [1-9][0-9]* ok, 0 failed')"

# The access cards are private data since harbor#1149: tests/skill/access-ledger/register.test.sh
# runs the route gate over a fixture register and over none.

t_section "the renderer half (harbor#392): vendor/archify is tracked, node is a capability"
t_exit "vendor/archify is present" 0 test -f "$T_ROOT/vendor/archify/bin/archify.mjs"
t_done
