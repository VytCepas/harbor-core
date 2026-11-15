#!/usr/bin/env sh
# harbor merge-stack verify (harbor#1060): after the merge, every PR merged, the checkout fast-forwarded, main's code
# equal to the tree CI tested, lint clean on a clean checkout, the deploy plan passing. An unexplained difference fails.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
GMS="$T_ROOT/bin/gate-merge-stack.sh"; PL="$T_TMP/plan"; T=ci/integration-test
HARBOR_GATE_REHEARSE_DIR="$T_TMP/scratch"; export HARBOR_GATE_REHEARSE_DIR
ver() { sh "${1:-$GMS}" verify "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
# two PRs on different files, rehearsed with --push (the tested branch), then merged
stacked() { ms_world harbor
  ms_branch fa; ms_add a.txt one; ms_push fa; ms_pr 11 fa "feat a"; ms_branch fb; ms_add b.txt two; ms_push fb; ms_pr 12 fb "feat b"
  ms_plan "$PL" 11 12
  sh "$GMS" rehearse "$PL" --push >/dev/null 2>&1; }
merge() { sh "$GMS" merge "$PL" >/dev/null 2>&1; }

t_section "merged, identical to the tested tree, lint and deploy plan clean: ALL CLEAR"
stacked; merge
t_eq "the checkout is behind origin/main before" no "$([ "$(git -C "$H" rev-parse HEAD)" = "$(git --git-dir="$MS_BARE" rev-parse main)" ] && echo yes || echo no)"
t_eq "exit 0" 0 "$(ver)"
t_has "every PR merged" "$(OUT)" "ok: #12"
t_has "the checkout was fast-forwarded to origin/main" "$(OUT)" "ok: at $(git --git-dir="$MS_BARE" rev-parse --short main)"
t_eq "...really" "$(git --git-dir="$MS_BARE" rev-parse main)" "$(git -C "$H" rev-parse HEAD)"
t_has "main is the tested tree" "$(OUT)" "ok: identical to $T"
t_has "lint on a clean checkout" "$(OUT)" "ok: lint: 0 violations"
t_has "the check suite" "$(OUT)" "ok: check: 0 violations"
t_has "the deploy plan" "$(OUT)" "ok: deploy: 3 ok, 0 failed, 0 warnings"
t_has "the verdict, with the deploy command for a real Terminal" "$(OUT)" "ALL CLEAR — deploy from a real Terminal: sh $H/bin/deploy.sh --apply --live"
t_eq "the throwaway lint worktree was removed" 1 "$(git -C "$H" worktree list | grep -c .)"

t_section "commits outside the plan explain a difference; they are named, not hidden"
ms_main other.txt late; ms_plan "$PL" 11 12
t_eq "exit 0" 0 "$(ver)"
t_has "the outside commit is named" "$(OUT)" "note: main also has commits outside the plan"
t_has "...and the files it explains" "$(OUT)" "differs only alongside those: other.txt"

t_section "lint, the deploy plan, a dirty checkout and a missing PR each fail, with a fix"
ms_main LINT_FAIL x; ms_main DEPLOY_FAIL x; echo dirty >> "$H/a.txt"; sed -i.b 's/^pr 12$/pr 12\npr 13/' "$PL"; ms_pr 13 fb; echo OPEN > "$MS_FIX/pr/13.state"
t_eq "exit 1" 1 "$(ver)"
t_has "an open PR" "$(OUT)" "FAIL: #13 is OPEN"
t_has "a dirty checkout" "$(OUT)" "FAIL: $H has uncommitted changes"
t_has "lint on main" "$(OUT)" "FAIL: lint: 1 violation"
t_has "...with its violation" "$(OUT)" "VIOLATION x"
t_has "the deploy plan" "$(OUT)" "FAIL: deploy: 2 ok, 1 failed, 0 warnings"
t_hasnt "no ALL CLEAR" "$(OUT)" "ALL CLEAR"

t_section "main differs from the tested tree with nothing to explain it: FAIL (red-proof)"
late() { stacked; ms_branch fa; ms_add a.txt late; ms_push fa; merge; }
late
t_eq "exit 1" 1 "$(ver)"
t_has "the FAIL names the file" "$(OUT)" "FAIL: differs from the tested tree with nothing else to explain it: a.txt"
t_has "...and the diff that shows it" "$(OUT)" "fix: git -C $H diff origin/$T origin/main"
ms_mutant "M15 an unexplained difference passes" 's/else bad "differs from the tested tree/else log_ok "differs from the tested tree/'
late
t_eq "the mutant passes it" 0 "$(ver "$M/bin/gate-merge-stack.sh")"

t_section "no tested branch: FAIL"
stacked; git --git-dir="$MS_BARE" update-ref -d "refs/heads/$T"; merge
t_eq "exit 1" 1 "$(ver)"
t_has "it says why" "$(OUT)" "FAIL: no tested branch origin/$T — keep it until this passes"
t_done
