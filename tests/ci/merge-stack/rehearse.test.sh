#!/usr/bin/env sh
# harbor merge-stack rehearse (harbor#1060): the planned PRs' net changes built onto main in a scratch clone, in plan
# order, none of their code run (CI lints and tests it on --push); --push alone writes outside the scratch clone, and only a
# throwaway branch. A PR that cannot be built from origin stops the rehearsal.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
GMS="$T_ROOT/bin/gate-merge-stack.sh"; PL="$T_TMP/plan"; SU=CONTRACTS/suites.txt; T=ci/integration-test
HARBOR_GATE_REHEARSE_DIR="$T_TMP/scratch"; export HARBOR_GATE_REHEARSE_DIR; S="$HARBOR_GATE_REHEARSE_DIR/acme_widgets"
reh() { sh "$GMS" rehearse "$PL" "$@" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
pr_file() { # <n> <branch> <file> <line> — a PR that appends a line to a file
  ms_branch "$2"; ms_add "$3" "$4"; ms_push "$2"; ms_pr "$1" "$2"; }
tree() { git -C "$S" show "rehearse:$1" 2>/dev/null; }

t_section "the combined tree: net changes in plan order, lists unioned, nothing of the PRs run"
ms_world harbor; pr_file 11 b11 "$SU" tests/p/one.test.sh; pr_file 12 b12 "$SU" tests/p/two.test.sh; pr_file 13 b13 x.txt closed
echo CLOSED > "$MS_FIX/pr/13.state"; ms_plan "$PL" 11 12 13
t_eq "exit 0" 0 "$(reh)"
t_has "each PR is reported" "$(OUT)" "ok: #12 (b12) rebased onto the combined tree"
t_has "a PR that is not open is skipped, not failed" "$(OUT)" "skip: #13 (not open)"
t_has "lint and suites are left to CI on --push" "$(OUT)" "lint and suites of the combined tree run in CI, never here"
t_has "it ends clean" "$(OUT)" "ok: rehearsal clean"
t_eq "the scratch tree holds both PRs' suites" "1 1" "$(tree "$SU" | grep -cxF tests/p/one.test.sh) $(tree "$SU" | grep -cxF tests/p/two.test.sh)"
t_eq "...and the generated files are main's, not rebuilt" "status 0" "$(tree STATUS.md)"
t_eq "...with the closed PR's file absent" "" "$(tree x.txt)"
t_eq "nothing was pushed" "" "$(git --git-dir="$MS_BARE" for-each-ref "refs/heads/ci")"
t_eq "...and no PR was created or merged" 0 "$(ms_mutates)"
t_eq "the operator's checkout was not touched" "" "$(git -C "$H" status --porcelain)"

t_section "a conflict that is not a list stops, names the PR, and leaves the scratch clone clean"
ms_world harbor; echo 'x=1' > "$W/bin/code.sh"; wg add -A; wg commit -q -m c; wg push -q origin main 2>/dev/null
for n in 14 15; do ms_branch "b$n"; echo "x=$n" > "$W/bin/code.sh"; wg commit -qam "set $n"; ms_push "b$n"; ms_pr "$n" "b$n"; done
ms_plan "$PL" 14 15
t_eq "exit 1" 1 "$(reh)"
t_has "the STOP names #15 and the file" "$(OUT)" "STOP at #15 (b15): needs a person in: bin/code.sh"
t_has "...with the way on" "$(OUT)" "fix: resolve it on the PR branch with a new commit, then re-run: harbor merge-stack rehearse"
t_eq "no rebase is left in progress" "" "$(git -C "$S" status --porcelain | grep -v '^??')"

t_section "rehearse runs none of the PRs' code: no lint, suite, generator or hook of the combined tree (r5 #2) (red-proof)"
# every script rehearse ever ran from the combined tree, and the hooks a relative core.hooksPath would find in it, leave a mark
marked() { ms_world harbor; ms_branch b16; mkdir -p "$W/hooks"
  for f in bin/lint-conventions.sh tests/lib/check.sh hooks/post-checkout hooks/pre-commit hooks/post-rewrite hooks/pre-push hooks/reference-transaction \
    $(for g in docs status; do echo "bin/$g-gen.sh"; done); do
    printf '#!/bin/sh\necho "%s" >> "%s/ran"\necho "lint: 0 violations"\n' "$f" "$T_TMP" > "$W/$f"; chmod +x "$W/$f"; done
  wg add -A; wg commit -q -m 'PR: every script marks'; ms_push b16; ms_pr 16 b16; ms_plan "$PL" 16; git config --global core.hooksPath hooks; rm -f "$T_TMP/ran"; }
marked
t_eq "exit 0, even with --push" 0 "$(reh --push)"
t_eq "...and nothing of the PR ran" none "$(cat "$T_TMP/ran" 2>/dev/null || echo none)"
t_has "...it was pushed for CI to judge" "$(OUT)" "ok: pushed $T"
ms_mutant "M51 rehearse lints the combined tree again" 's#^  dedupe \. "rehearsal: list lines both sides added, kept once"$#&; sh bin/lint-conventions.sh >/dev/null#'
marked; sh "$M/bin/gate-merge-stack.sh" rehearse "$PL" >"$T_TMP/out" 2>&1
t_has "M51: the PR's lint ran" "$(cat "$T_TMP/ran" 2>/dev/null)" "bin/lint-conventions.sh"
ms_mutant "M52 the rehearsal's git runs hooks" 's#^git() { command git -c core.hooksPath=/dev/null "\$@"; }$#git() { command git "$@"; }#'
marked; sh "$M/bin/gate-merge-stack.sh" rehearse "$PL" --push >"$T_TMP/out" 2>&1
t_has "M52: the PR's own pre-push ran" "$(cat "$T_TMP/ran" 2>/dev/null)" "hooks/pre-push"
git config --global --unset core.hooksPath

t_section "--push: the tested branch and one DO-NOT-MERGE PR, once"
ms_world harbor; pr_file 11 b11 "$SU" tests/p/one.test.sh; pr_file 12 b12 a.txt two; ms_plan "$PL" 11 12
t_eq "exit 0" 0 "$(reh --push)"
t_has "pushed" "$(OUT)" "ok: pushed $T"
t_eq "the branch holds the combined tree" "1" "$(ms_file "$T" "$SU" | grep -cxF tests/p/one.test.sh)"
t_eq "one PR was created" 1 "$(grep -c '^pr create' "$MS_FIX/calls.log")"
t_has "...titled DO NOT MERGE and naming the stack" "$(grep '^pr create' "$MS_FIX/calls.log")" "DO NOT MERGE — integration check of #11 #12"
t_eq "a second rehearsal updates the branch and opens no second PR" 1 "$(reh --push >/dev/null; grep -c '^pr create' "$MS_FIX/calls.log")"

t_section "the tested branch is never main, a PR's own branch, or missing"
ms_plan "$PL" 11 12; printf 'tested main\n' >> "$PL"; sed -i.b '/^tested ci/d' "$PL"
t_eq "tested main: exit 1" 1 "$(reh --push)"; t_has "...refused before any push" "$(OUT)" "would overwrite main"
ms_plan "$PL" 11 12; sed -i.b 's#^tested .*#tested b11#' "$PL"
t_eq "tested = a PR's head branch: exit 1" 1 "$(reh --push)"; t_has "...naming the PR" "$(OUT)" "is the head branch of #11"
sed -i.b '/^tested/d' "$PL"
t_eq "--push with no tested branch: exit 2" 2 "$(reh --push)"

t_section "a list conflict resolved mid-rebase continues, though the net commit's message starts with # (red-proof)"
# `#12 net` is a comment line to git's editor step, so --continue saw an empty message and failed forever, every round
lists() { ms_world harbor; pr_file 11 b11 "$SU" tests/p/one.test.sh; pr_file 12 b12 "$SU" tests/p/two.test.sh; ms_plan "$PL" 11 12; }
lists
t_eq "two PRs appending to the suite list: exit 0" 0 "$(reh)"
t_eq "...both suites in the combined tree" "1 1" "$(tree "$SU" | grep -cxF tests/p/one.test.sh) $(tree "$SU" | grep -cxF tests/p/two.test.sh)"
ms_mutant "M41 git strips the # message on --continue" 's/ -c core.commentChar=auto//'
lists
t_eq "the mutant stops (once, not in a loop): exit 1" 1 "$(sh "$M/bin/gate-merge-stack.sh" rehearse "$PL" >"$T_TMP/out" 2>&1; echo $?)"
t_has "...saying the rebase would not continue" "$(OUT)" "the rebase would not continue once its conflicts were resolved"
t_section "a deletion against an edit stops the rehearsal too (r5 #1, probe n9r) (red-proof)"
legacy() { ms_world harbor; printf '#!/bin/sh\necho "legacy deploy"\n' > "$W/bin/legacy-deploy.sh"; wg add -A; wg commit -q -m seed-legacy
  wg push -q origin main 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null
  ms_branch b11; wg rm -q bin/legacy-deploy.sh; wg commit -qm 'retire legacy'; ms_push b11; ms_pr 11 b11
  ms_branch b12; printf 'echo "tweak"\n' >> "$W/bin/legacy-deploy.sh"; wg commit -qam 'tweak legacy'; ms_push b12; ms_pr 12 b12; ms_plan "$PL" 11 12; }
legacy
t_eq "#11 deletes bin/legacy-deploy.sh, #12 edits it: exit 1" 1 "$(reh)"
t_has "...the STOP names #12 and the file" "$(OUT)" "STOP at #12 (b12): needs a person in: bin/legacy-deploy.sh"
t_hasnt "...and it is not called clean" "$(OUT)" "rehearsal clean"
ms_mutant "M53 the r5 #1 fix reverted in rehearse" 's/^    elif ! three_stages "\$1" "\$_f"; then/    elif false; then/'
python3 - "$M/bin/gate-merge-stack-resolve.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
for a, b in (("if '<<<<<<<' not in s or not hash_syntax(p, s)", "if '<<<<<<<' in s and not hash_syntax(p, s)"), ("blocks == 0 or ", "")):
    assert a in s, a
    s = s.replace(a, b)
open(p, "w").write(s)
PY
legacy
t_eq "M53: the mutant calls it clean, with the deleted file in the combined tree (probe n9r)" "0 yes" \
  "$(sh "$M/bin/gate-merge-stack.sh" rehearse "$PL" >"$T_TMP/out" 2>&1; echo $?) $(git -C "$S" cat-file -e rehearse:bin/legacy-deploy.sh 2>/dev/null && echo yes || echo no)"

t_section "a PR whose head branch is not on origin (a fork PR) stops the rehearsal, never is left out of it (r5 #6, probe n12 iii) (red-proof)"
fork() { ms_world harbor; pr_file 11 b11 "$SU" tests/p/one.test.sh; pr_file 13 b13 x.txt three; ms_pr 12 fork-branch; ms_plan "$PL" 11 12 13; }
fork
t_eq "exit 1" 1 "$(reh)"
t_has "...naming #12 and why" "$(OUT)" "STOP at #12 (fork-branch): its head"
t_has "...its branch is not on origin" "$(OUT)" "is not origin/fork-branch"
t_hasnt "...never called clean" "$(OUT)" "rehearsal clean"
t_eq "...and no later PR is labelled with #12" "" "$(git -C "$S" log --format=%s origin/main..rehearse | grep '#12' || true)"
ms_mutant "M54 the r5 #6 fix reverted: a PR that is not on origin is skipped" 's/^      die "STOP at #\$p (\$b): its head .*$/      :/;s/^      die "STOP at #\$p (\$b): its net change could not be built" .*$/      :/;s/ || die "STOP at #\$p (\$b): the combined tree did not take its net change" .*$/ || :/'
fork
t_eq "M54: the mutant leaves #12 out and calls the rehearsal clean, exit 0" 0 "$(sh "$M/bin/gate-merge-stack.sh" rehearse "$PL" >"$T_TMP/out" 2>&1; echo $?)"
t_has "M54: ...rehearsal clean" "$(OUT)" "rehearsal clean"
t_done
