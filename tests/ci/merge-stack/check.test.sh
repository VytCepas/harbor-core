#!/usr/bin/env sh
# harbor merge-stack check and the front door (harbor#1060): every PR's state, CI and mergeability reported, and
# NOTHING written; usage errors and bad plans exit 2 before any run; the dispatcher reaches the script.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
GMS="$T_ROOT/bin/gate-merge-stack.sh"; PL="$T_TMP/plan"
chk() { sh "${1:-$GMS}" check "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }

t_section "the report: merged, green, red, unfinished, closed"
ms_world
for n in 11 12 13 14 15; do ms_branch "b$n"; ms_add "f$n.txt" "$n"; ms_push "b$n"; ms_pr "$n" "b$n"; done
echo MERGED > "$MS_FIX/pr/11.state"; echo CLOSED > "$MS_FIX/pr/15.state"
printf '[{"databaseId":701,"status":"completed","conclusion":"failure"}]\n' > "$MS_FIX/runs/$(ms_tip b13).1"
printf '[{"databaseId":702,"status":"in_progress","conclusion":""}]\n' > "$MS_FIX/runs/$(ms_tip b14).1"
ms_plan "$PL" 11 12 13 14 15
t_eq "a red and a closed PR make it exit 1" 1 "$(chk)"
t_has "merged" "$(OUT)" "ok: #11 merged"
t_has "green, with GitHub's mergeability" "$(OUT)" "ok: #12 green, MERGEABLE"
t_has "red names the run" "$(OUT)" "FAIL: #13 last CI run red: 701 completed failure"
t_has "...and the fix that reads its log" "$(OUT)" "fix: gh run view 701 -R acme/widgets --log-failed"
t_has "an unfinished run is a wait, not a failure" "$(OUT)" "note: wait #14 CI not finished: 702 in_progress"
t_has "closed" "$(OUT)" "FAIL: #15 is CLOSED"
t_has "the summary counts the two failures" "$(OUT)" "2 failed"
ms_plan "$PL" 11 12 14
t_eq "merged + green + unfinished only: exit 0" 0 "$(chk)"
touch "$MS_FIX/noauth"; t_eq "gh not logged in: exit 1" 1 "$(chk)"; t_has "...with the login as the fix" "$(OUT)" "fix: gh auth login"; rm "$MS_FIX/noauth"
rm "$MS_INST/bin/merge-check.sh"; t_eq "an install without merge-check.sh: exit 1" 1 "$(chk)"; t_has "...naming it" "$(OUT)" "no $MS_INST/bin/merge-check.sh"

t_section "check writes nothing (red-proof)"
ro() { ms_world; ms_branch feat-a; ms_add a.txt one; ms_push feat-a; ms_pr 11 feat-a; ms_plan "$PL" 11; : > "$MS_FIX/calls.log"; }
ro; ms_footprint > "$T_TMP/before"; t_eq "exit 0" 0 "$(chk)"
ms_footprint > "$T_TMP/after"
t_eq "refs, the checkout, worktrees, HOME and every PR state are unchanged" "" "$(diff "$T_TMP/before" "$T_TMP/after")"
t_eq "gh was asked to merge, create or rerun nothing" 0 "$(ms_mutates)"
t_eq "merge-check never ran" no "$([ -f "$MS_FIX/merge.log" ] && echo yes || echo no)"
ms_mutant "M9 check carries on into the merge" 's/^if \[ "\$SUB" = check \]; then .*$/DEF=main/'
ro; chk "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant merged the PR" yes "$([ -f "$MS_FIX/merge.log" ] && echo yes || echo no)"

t_section "usage errors and bad plans exit 2 before any run"
ro
t_exit "no arguments" 2 sh "$GMS"
t_exit "an unknown sub-verb" 2 sh "$GMS" frobnicate "$PL"
t_exit "no plan" 2 sh "$GMS" check
t_exit "a plan that does not exist" 2 sh "$GMS" check "$T_TMP/none"
t_exit "--push outside rehearse" 2 sh "$GMS" merge "$PL" --push
t_exit "an unknown option" 2 sh "$GMS" check "$PL" --force
t_exit "two plans" 2 sh "$GMS" check "$PL" "$PL"
badplan() { printf '%s\n' "$2" > "$T_TMP/bad"; t_exit "$1" 2 sh "$GMS" check "$T_TMP/bad"; }
badplan "a plan with no pr" "repo acme/widgets
checkout $H"
badplan "a repo that is not owner/name" "repo acme
checkout $H
pr 1"
badplan "a repo with a shell word in it" 'repo acme/$(x)
checkout /tmp
pr 1'
badplan "a pr that is not a number" "repo acme/widgets
checkout $H
pr 11x"
badplan "a checkout that is not a directory" "repo acme/widgets
checkout $T_TMP/nowhere
pr 1"
t_eq "not one of them called gh" 0 "$(grep -c . "$MS_FIX/calls.log")"
t_has "--help prints the usage and points to the doc" "$(sh "$GMS" --help)" "docs/design/merge-stack.md"
t_exit "--help exits 0" 0 sh "$GMS" --help

t_section "harbor merge-stack reaches it, and the exit code is the script's"
t_has "the dispatcher runs --help" "$(sh "$T_ROOT/bin/harbor" merge-stack --help 2>&1)" "usage: harbor merge-stack <check|rehearse|merge|verify>"
t_exit "a usage error is exit 2 through the verb" 2 sh "$T_ROOT/bin/harbor" merge-stack check
t_eq "a clean check is exit 0 through the verb" 0 "$(sh "$T_ROOT/bin/harbor" merge-stack check "$PL" >/dev/null 2>&1; echo $?)"
t_done
