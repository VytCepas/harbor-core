#!/usr/bin/env sh
# The core skills' own checkers inside CI (R5, CONTRACTS/gates.md): each checker's --self-test. The measurement skills'
# checkers (topology, casefile, tracking-standards) left core with them (harbor#1149): their --self-tests, the R5
# falsifier and the maps contract run from the measurement pack's tests/skills/, which reads this checkout for the
# core half of each cross-check (check-routes.sh's write-verb deny-list, report-contract.sh).
. "$(dirname "$0")/../lib/core.sh"; t_init
ROUTES="$T_ROOT/skills/access-ledger/bin/check-routes.sh"

t_section "calibration: exit codes are read exactly"
t_exit "exit 0 is read as 0" 0 sh -c 'exit 0'
t_exit "exit 1 is read as 1" 1 sh -c 'exit 1'
t_exit "exit 2 is read as 2" 2 sh -c 'exit 2'
t_exit "exit 127 is read as 127" 127 sh -c 'exit 127'

t_section "each checker still discriminates"
t_exit "check-routes.sh --self-test" 0 sh "$ROUTES" --self-test
t_exit "report-contract.sh --self-test (harbor#411)" 0 sh "$T_ROOT/bin/report-contract.sh" --self-test

# The access cards are private data since harbor#1149: tests/skills/access-ledger/register.test.sh
# runs the route gate over a fixture register and over none.

t_section "the renderer half (harbor#392): vendor/archify is tracked, node is a capability"
t_exit "vendor/archify is present" 0 test -f "$T_ROOT/vendor/archify/bin/archify.mjs"
t_done
