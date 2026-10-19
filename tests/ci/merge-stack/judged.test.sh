#!/usr/bin/env sh
# harbor merge-stack, which runs are judged (harbor#1060, ship contract 5b.12): with no `workflow` key the latest run of EVERY
# workflow on the head must be success; a red, skipped or pending one blocks. A mutant that judges one run must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
PL="$T_TMP/plan"
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
R_LINT_RED='{"databaseId":299,"status":"completed","conclusion":"failure","workflowDatabaseId":11,"workflowName":"lint"}'
R_LINT_OK='{"databaseId":298,"status":"completed","conclusion":"success","workflowDatabaseId":11,"workflowName":"lint"}'
R_TEST_OK='{"databaseId":300,"status":"completed","conclusion":"success","workflowDatabaseId":12,"workflowName":"test"}'
R_LINT_PEND='{"databaseId":295,"status":"in_progress","conclusion":"","workflowDatabaseId":11,"workflowName":"lint"}'
world() { MS_NOWF=1; ms_world; ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat; ms_plan "$PL" 11; unset MS_NOWF; }
runs() { printf '[%s]\n' "$1" > "$MS_FIX/runs/default.1"; }
one_run() { printf '{"databaseId":%s,"status":"%s","conclusion":"%s","workflowDatabaseId":11,"workflowName":"lint"}' "$1" "$2" "$3"; }

t_section "a red lint run beside a newer green test run does not merge (red-proof)"
world; runs "$R_TEST_OK,$R_LINT_RED"
t_eq "exit 1" 1 "$(run)"
t_has "the red run is named, with no workflow key in the plan" "$(OUT)" "FAIL: #11 last CI run red: 299 completed failure"
t_eq "nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
ms_mutant "M21 judge only the newest run" 's/group_by(\[.workflowDatabaseId, .event\]) | map(max_by(.databaseId))/[max_by(.databaseId)]/'
world; runs "$R_TEST_OK,$R_LINT_RED"
t_eq "the mutant merges it" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "every workflow green merges; a skipped or neutral conclusion, or a failing pending run, does not"
world; runs "$R_TEST_OK,$R_LINT_OK"
t_eq "two green workflows: exit 0" 0 "$(run)"
t_eq "...and both runs were watched, in workflow order" "run watch 298 -R acme/widgets --exit-status --interval 30
run watch 300 -R acme/widgets --exit-status --interval 30" "$(grep '^run watch' "$MS_FIX/calls.log")"
world; runs "$R_TEST_OK,$(one_run 297 completed skipped)"
t_eq "a skipped workflow blocks: exit 1" 1 "$(run)"
world; runs "$R_TEST_OK,$(one_run 296 completed neutral)"
t_eq "a neutral one blocks too" 1 "$(run)"
world; runs "$R_TEST_OK,$R_LINT_PEND"
t_eq "a pending one is waited for, then merges: exit 0" 0 "$(run)"
t_has "...both runs reported green" "$(OUT)" "ok: #11: CI run 295 300 green"
world; runs "$R_TEST_OK,$R_LINT_PEND"; echo 1 > "$MS_FIX/watch/295"
t_eq "a pending one that then fails stops the merge" 1 "$(run)"

t_section "a workflow whose latest run was cancelled is not green, before the watch or during it (5b.12) (red-proof)"
cancelled_first() { world; runs "$R_TEST_OK,$(one_run 294 completed cancelled)"; }
cancelled_first
t_eq "a workflow whose only run was cancelled blocks the merge: exit 1" 1 "$(run)"
t_has "...it is named" "$(OUT)" "FAIL: #11 last CI run red: 294 completed cancelled"
t_eq "...nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
cancelled_mid() { world; runs "$R_TEST_OK,$R_LINT_PEND"; cp "$MS_FIX/runs/default.1" "$MS_FIX/runs/default.2"
  printf '[%s,%s]\n' "$R_TEST_OK" "$(one_run 295 completed cancelled)" > "$MS_FIX/runs/default.3"; echo 1 > "$MS_FIX/watch/295"; echo cancelled > "$MS_FIX/view/295"; }
cancelled_mid
t_eq "a run cancelled while it is watched, with nothing newer, stops the merge: exit 1" 1 "$(run)"
t_has "...saying so" "$(OUT)" "CI run 295 was cancelled and no newer run replaced it"
t_eq "...nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
t_eq "...after a bounded wait for a replacement" 6 "$(grep -c '^sleep 10' "$MS_FIX/sleep.log")"
ms_mutant "M33 a cancelled run drops out of the judged set" 's/else (group_by(/else ([.[] | select(.conclusion != \\"cancelled\\")] | group_by(/'
cancelled_first
t_eq "the mutant merges past the cancelled run" 0 "$(run "$M/bin/gate-merge-stack.sh")"
cancelled_mid
t_eq "...and past the one cancelled mid-watch" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "two workflows that share a name: grouped by workflow id, so a red run cannot hide behind a green one (red-proof)"
SAME_RED='{"databaseId":299,"status":"completed","conclusion":"failure","workflowDatabaseId":21,"workflowName":"CI"}'
SAME_OK='{"databaseId":300,"status":"completed","conclusion":"success","workflowDatabaseId":22,"workflowName":"CI"}'
world; runs "$SAME_OK,$SAME_RED"
t_eq "a red CI run and a newer green CI run from another workflow file: exit 1" 1 "$(run)"
t_has "...the red one is named" "$(OUT)" "FAIL: #11 last CI run red: 299 completed failure"
ms_mutant "M25 group runs by workflow name" 's/group_by(\[.workflowDatabaseId, .event\])/group_by(.workflowName)/'
world; runs "$SAME_OK,$SAME_RED"
t_eq "the mutant merges it behind the green one" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "one workflow, two events: a newer green workflow_dispatch run cannot hide a red pull_request run (red-proof)"
EV_PR_RED='{"databaseId":299,"status":"completed","conclusion":"failure","workflowDatabaseId":11,"workflowName":"CI","event":"pull_request"}'
EV_PR_OK='{"databaseId":299,"status":"completed","conclusion":"success","workflowDatabaseId":11,"workflowName":"CI","event":"pull_request"}'
EV_WD_OK='{"databaseId":300,"status":"completed","conclusion":"success","workflowDatabaseId":11,"workflowName":"CI","event":"workflow_dispatch"}'
world; runs "$EV_WD_OK,$EV_PR_RED"
t_eq "a red pull_request run and a newer green workflow_dispatch run of the same workflow: exit 1" 1 "$(run)"
t_has "...the red one is named" "$(OUT)" "FAIL: #11 last CI run red: 299 completed failure"
t_eq "...nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
t_has "gh was asked for each run's event" "$(grep '^run list' "$MS_FIX/calls.log" | head -1)" "workflowDatabaseId,event"
world; runs "$EV_WD_OK,$EV_PR_OK"
t_eq "both events green: exit 0" 0 "$(run)"
t_has "...and both runs were judged" "$(OUT)" "ok: #11: CI run 299 300 green"
ms_mutant "M32 group runs by workflow id only, ignoring the event" 's/group_by(\[.workflowDatabaseId, .event\])/group_by(.workflowDatabaseId)/'
world; runs "$EV_WD_OK,$EV_PR_RED"
t_eq "the mutant merges behind the dispatch run" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "a workflow that starts while the others are watched is judged too (red-proof)"
late_wf() { world; printf '[%s]\n' "$R_TEST_OK" > "$MS_FIX/runs/default.1"; cp "$MS_FIX/runs/default.1" "$MS_FIX/runs/default.2"
  printf '[%s,%s]\n' "$R_TEST_OK" "$R_LINT_RED" > "$MS_FIX/runs/default.3"; cp "$MS_FIX/runs/default.3" "$MS_FIX/runs/default.4"
  echo 1 > "$MS_FIX/watch/299"; echo failure > "$MS_FIX/view/299"; }
late_wf
t_eq "a red lint run that appears after the first look blocks the merge: exit 1" 1 "$(run)"
t_has "...and it is the one named" "$(OUT)" "CI run 299 is red"
ms_mutant "MB no second look at the runs" 's/^  \[ "\$(latest_runs "\$_sha")" = "\$_runs" \] || .*$/  true/'
late_wf
t_eq "the mutant merges on the runs it saw first" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "an empty head commit stops the run, and the pin is never dropped (red-proof)"
world; touch "$MS_FIX/empty-head"
t_eq "exit 1" 1 "$(run)"
t_has "it names the empty head" "$(OUT)" "GitHub gave no head commit for it"
t_eq "nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
ms_mutant "M26 an empty head is judged" 's/^  case "\$_sha" in \*\[!0-9abcdef\]\*|.*) die .*$/  true/;s/^  \[ "\${#_sha}" = 40 \] || die .*$/  true/'
world; touch "$MS_FIX/empty-head"
t_eq "the mutant merges with no pin at all" 0 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...merge-check was given an empty --match-head-commit" "--squash --merge 11 --match-head-commit " "$(cat "$MS_FIX/args.log")"

t_section "a full page of runs is refused, never judged: gh returns only the newest (r4 #4, probe n7) (red-proof)"
# one workflow: a red pull_request run, then 100 newer green workflow_dispatch runs on the same commit. The stub, like gh,
# returns the newest --limit runs, so the red one is not in the page.
RED_PR='{"databaseId":299,"status":"completed","conclusion":"failure","workflowDatabaseId":11,"workflowName":"CI","event":"pull_request"}'
disp() { i=$1; while [ "$i" -le "$2" ]; do printf ',{"databaseId":%s,"status":"completed","conclusion":"success","workflowDatabaseId":11,"workflowName":"CI","event":"workflow_dispatch"}' "$i"; i=$((i + 1)); done; }
world; printf '[%s%s]\n' "$RED_PR" "$(disp 301 400)" > "$MS_FIX/runs/default.1"
t_eq "101 runs, the red one the oldest: exit 1" 1 "$(run)"
t_has "...named as a page that may hide a red run" "$(OUT)" "FAIL: #11 has 100 or more CI runs on its head: an older red run may be hidden"
t_eq "...nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
t_has "gh was asked for 100" "$(grep '^run list' "$MS_FIX/calls.log" | head -1)" "--limit 100"
world; printf '[%s]\n' "$(disp 301 400 | sed 's/^,//')" > "$MS_FIX/runs/default.1"
t_eq "exactly 100 runs, all green: still refused (a 101st may exist)" 1 "$(run)"
world; printf '[%s]\n' "$(disp 302 400 | sed 's/^,//')" > "$MS_FIX/runs/default.1"
t_eq "99 green runs: merges" 0 "$(run)"
world; printf '[%s]\n' "$(disp 302 400 | sed 's/^,//')" > "$MS_FIX/runs/default.1"; printf '[%s%s]\n' "$RED_PR" "$(disp 301 400)" > "$MS_FIX/runs/default.2"
t_eq "a full page that appears after the check, while merge judges the head: exit 1" 1 "$(run)"
t_has "...merge stops on it" "$(OUT)" "100 or more CI runs on"
t_eq "...nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
ms_mutant "M40 a full page is judged as if complete" 's/if length >= \$RUN_LIMIT then/if false then/'
world; printf '[%s%s]\n' "$RED_PR" "$(disp 301 400)" > "$MS_FIX/runs/default.1"
t_eq "the mutant merges past the hidden red run" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "a plan workflow key still narrows the runs asked for"
ms_world; ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat; ms_plan "$PL" 11
run >/dev/null
t_has "gh was asked for that workflow's runs only" "$(grep '^run list' "$MS_FIX/calls.log")" "--workflow governance.yml"
t_done
