#!/usr/bin/env sh
# harbor merge-stack merge (harbor#1060): the order, the squash, `after` lines, a rerun, and the three CI-wait traps:
# the --required hang, a cancelled run re-waited, a stale head after a sync push. Each has a mutant that must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
GMS="$T_ROOT/bin/gate-merge-stack.sh"; PL="$T_TMP/plan"
two_prs() { ms_world
  ms_branch feat-a; ms_add a.txt one; ms_push feat-a; ms_pr 11 feat-a "feat a"
  ms_branch feat-b; ms_add b.txt two; ms_push feat-b; ms_pr 12 feat-b "feat b"
}
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
calls() { grep -c "$1" "$MS_FIX/calls.log" || true; }

t_section "two PRs merge in plan order, squashed, each on its own run; after-lines print once"
two_prs; MS_PLAN_EXTRA='after 11 secret import stape-api stape-api' ms_plan "$PL" 11 12
t_eq "exit 0" 0 "$(run)"
t_eq "merge-check was asked for #11 then #12, squash and merge" "merge-check --squash --merge 11
merge-check --squash --merge 12" "$(cat "$MS_FIX/merge.log")"
t_eq "main holds two squash commits, in order" "feat b (#12)
feat a (#11)" "$(git --git-dir="$MS_BARE" log --format=%s -2 main)"
t_has "the after line is printed" "$(cat "$T_TMP/out")" "run once now: secret import stape-api stape-api"
t_has "the summary says nothing failed" "$(cat "$T_TMP/out")" "0 failed"
t_eq "the CI gate never asked gh for required checks (the hang)" 0 "$(calls '^pr checks')"
t_eq "a rerun finds both merged and merges nothing" 0 "$(run)"
t_eq "...no second merge-check call" 2 "$(grep -c . "$MS_FIX/merge.log")"
t_has "...and says so" "$(cat "$T_TMP/out")" "#11 already merged"

t_section "a red run stops the stack before merge-check"
two_prs; ms_plan "$PL" 11 12
printf '[{"databaseId":777,"status":"completed","conclusion":"failure"}]\n' > "$MS_FIX/runs/$(ms_tip feat-a).1"
t_eq "exit 1 at the preflight" 1 "$(run)"
t_has "the FAIL names the run and its fix" "$(cat "$T_TMP/out")" "fix: gh run view 777 -R acme/widgets --log-failed"
t_eq "nothing was merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
two_prs; ms_plan "$PL" 11 12; echo 1 > "$MS_FIX/watch/900"
t_eq "a run that goes red while watched stops it (exit 1)" 1 "$(run)"
t_has "...naming the run" "$(cat "$T_TMP/out")" "CI run 900 is red"
t_eq "...with nothing merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"

t_section "the --required hang trap: green waits on the head's own run (red-proof)"
ms_mutant "M1 gate on gh pr checks --required" 's|gh run watch "\$_run" -R "\$R" --exit-status --interval 30|gh pr checks "$1" -R "$R" --required --watch|'
two_prs; ms_plan "$PL" 11 12
t_eq "the mutant fails the stack" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...because it asked for required checks, which a repo without protection never reports" 1 "$(calls '^pr checks')"

t_section "a cancelled run is re-waited, never passed (red-proof)"
cancel() { two_prs; ms_plan "$PL" 11
  printf '[{"databaseId":100,"status":"in_progress","conclusion":""}]\n' > "$MS_FIX/runs/default.1"; cp "$MS_FIX/runs/default.1" "$MS_FIX/runs/default.2"
  printf '[{"databaseId":101,"status":"in_progress","conclusion":""},{"databaseId":100,"status":"completed","conclusion":"cancelled"}]\n' > "$MS_FIX/runs/default.3"
  echo 1 > "$MS_FIX/watch/100"; echo cancelled > "$MS_FIX/view/100"; }
cancel
t_eq "exit 0: the superseding run passed" 0 "$(run)"
t_eq "the cancelled run 100 was watched, then 101" "run watch 100 -R acme/widgets --exit-status --interval 30
run watch 101 -R acme/widgets --exit-status --interval 30" "$(grep '^run watch' "$MS_FIX/calls.log")"
t_has "...and the green one is reported" "$(cat "$T_TMP/out")" "CI run 101 green"
ms_mutant "M2 a cancelled run counts as red" 's/\[ "\$_c" = cancelled \]/[ "$_c" = nothing ]/'
cancel
t_eq "the mutant stops on the cancelled run" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...and merges nothing" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"

t_section "after a sync push, green waits for GitHub to show the pushed head (harbor#1115) (red-proof)"
stale() { ms_world harbor
  ms_branch feat-a; ms_add contracts/suites.txt tests/p/pr.test.sh; ms_push feat-a; ms_pr 11 feat-a
  OLD="$(ms_tip feat-a)"; ms_main contracts/suites.txt tests/m/main.test.sh
  ms_plan "$PL" 11
  printf '[{"databaseId":555,"status":"completed","conclusion":"success"}]\n' > "$MS_FIX/runs/$OLD.1"
  echo "$OLD" > "$MS_FIX/stale/11.old"; echo 3 > "$MS_FIX/stale/11.count"; }
looked_at_old() { grep -c -- "^run list .*--commit $OLD " "$MS_FIX/calls.log" || true; }
stale
t_eq "exit 0" 0 "$(run)"
t_eq "the branch was rebased: its tip is no longer the old head" no "$([ "$(ms_tip feat-a)" = "$OLD" ] && echo yes || echo no)"
t_eq "green polled three times for the new head" 3 "$(grep -c '^sleep 5' "$MS_FIX/sleep.log")"
t_eq "the old head's run was looked up once only: the preflight, before the push" 1 "$(looked_at_old)"
t_eq "the new head's run 900 was the one watched" 1 "$(calls '^run watch 900')"
t_eq "...and 555, the old head's, was not" 0 "$(calls '^run watch 555')"
ms_mutant "M3 no wait for the pushed head" 's/if \[ -n "\${PUSHED:-}" \]; then/if false; then/'
stale
run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant judged the old head's run too" yes "$([ "$(looked_at_old)" -ge 2 ] && echo yes || echo no)"
t_eq "...and watched 555" 1 "$(calls '^run watch 555')"
t_done
