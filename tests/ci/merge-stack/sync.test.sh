#!/usr/bin/env sh
# harbor merge-stack merge, the sync step (harbor#1060): a PR an earlier merge made conflicting is rebased as ONE net
# commit, the declared line lists' pure additions kept from both sides, then pushed; list lines are deduped, no generated
# file rebuilt (no PR code runs), a real conflict stops for a person. Never git's union driver (r4 #2). Each rule has a mutant that must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
GMS="$T_ROOT/bin/gate-merge-stack.sh"; PL="$T_TMP/plan"; SU=contracts/suites.txt
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
lines() { ms_file "$1" "$2" | grep -cxF "$3" || true; }
# a PR that appends to the suite list, forked before main appended too: they conflict at the end of the file
race() { ms_world harbor; ms_branch feat; ms_add "$SU" tests/p/pr.test.sh; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  ms_main "$SU" tests/m/main.test.sh; ms_plan "$PL" 11; }

t_section "a conflicting PR is rebased onto main and pushed, then merged"
race
t_eq "GitHub calls it conflicting before" CONFLICTING "$(PATH="$PATH" gh pr view 11 -R acme/widgets --json mergeable --jq .mergeable)"
t_eq "exit 0" 0 "$(run)"
t_has "the rebase is announced" "$(cat "$T_TMP/out")" "rebase #11 (feat) onto main"
t_eq "the pushed branch moved" no "$([ "$(ms_tip feat)" = "$OLD" ] && echo yes || echo no)"
t_eq "...and now contains main's tip" yes "$(git --git-dir="$MS_BARE" merge-base --is-ancestor "$(git --git-dir="$MS_BARE" rev-parse 'main~1')" feat && echo yes || echo no)"
t_eq "main holds both suites once" "1 1" "$(lines main "$SU" tests/p/pr.test.sh) $(lines main "$SU" tests/m/main.test.sh)"
t_eq "the PR merged" "merge-check --squash --merge 11" "$(cat "$MS_FIX/merge.log")"
ms_mutant "M4 sync never pushes" 's/^  git -C "\$_w" push -q --force-with-lease origin "\$_b"$/  true/'
race
t_eq "the mutant stops: GitHub still sees a conflict" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...and the PR branch is where it was" "$OLD" "$(ms_tip feat)"
ms_mutant "M5 sync never rebases" 's/\[ "\$(st "\$1" mergeable)" = CONFLICTING \] || return 0/return 0/'
race
t_eq "the mutant stops: nothing was rebased" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...and the PR is still open, because GitHub would refuse it" OPEN "$(cat "$MS_FIX/pr/11.state")"

t_section "the net-commit rule: a PR that added a line and deleted it again merges without a person"
net() { ms_world harbor; ms_branch feat; ms_add "$SU" tests/n/x.test.sh; ms_add "$SU" tests/n/y.test.sh; ms_del "$SU" tests/n/x.test.sh
  ms_push feat; ms_pr 11 feat; ms_main "$SU" tests/m/main.test.sh; ms_plan "$PL" 11; }
net
t_eq "exit 0" 0 "$(run)"
t_eq "the deleted line is absent on main" 0 "$(lines main "$SU" tests/n/x.test.sh)"
t_eq "the kept one and main's are there" "1 1" "$(lines main "$SU" tests/n/y.test.sh) $(lines main "$SU" tests/m/main.test.sh)"
ms_mutant "M6 replay the history commit by commit" 's/^  git -C "\$_w" reset -q --soft .*$/  true/;s/^  git -C "\$_w" commit -q -m .*$/  true/'
net
t_eq "the mutant replays the deletion as its own commit, which conflicts: it stops for a person, exit 1" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...and never resurrects the line" 0 "$(lines feat "$SU" tests/n/x.test.sh)"

t_section "a line both sides added is kept once (a suite listed twice runs twice and its result is lost)"
dup() { ms_world harbor; ms_branch feat; ms_add "$SU" tests/d/shared.test.sh; ms_add "$SU" tests/d/pr.test.sh; ms_push feat; ms_pr 11 feat
  ms_main "$SU" tests/d/main.test.sh; ms_add "$SU" tests/d/shared.test.sh; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
dup
t_eq "exit 0" 0 "$(run)"
t_eq "the shared suite is on main once" 1 "$(lines main "$SU" tests/d/shared.test.sh)"
t_eq "the comment header survived" 1 "$(lines main "$SU" '# suites')"
# the same line added at two places git merges cleanly: only the regeneration step's dedupe catches it
dup2() { ms_world harbor; ms_branch feat; awk 'NR == 1 { print; print "tests/d/shared.test.sh"; next } 1' "$W/$SU" > "$W/$SU.t"; mv "$W/$SU.t" "$W/$SU"
  ms_add "$SU" tests/d/pr.test.sh; ms_push feat; ms_pr 11 feat
  ms_main "$SU" tests/d/main.test.sh; ms_add "$SU" tests/d/shared.test.sh; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
dup2
t_eq "a line added at the top by the PR and at the end by main: exit 0" 0 "$(run)"
t_eq "...on main once" 1 "$(lines main "$SU" tests/d/shared.test.sh)"
ms_mutant "M7 no dedupe" 's/!seen\[\$0\]++/1/'
dup2
run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant leaves it twice" 2 "$(lines feat "$SU" tests/d/shared.test.sh)"

t_section "a generated file is never rebuilt (no PR code runs, r5 #2): a conflict in one stops for a person; a real conflict too"
gen() { ms_world harbor; ms_branch feat; echo "hand edit" > "$W/docs/generated/status.md"; wg add -A; wg commit -q -m s; ms_add "$SU" tests/g/pr.test.sh; ms_push feat; ms_pr 11 feat
  OLD="$(ms_tip feat)"; ms_main "$SU" tests/g/main.test.sh; echo "other edit" > "$W/docs/generated/status.md"; wg add -A; wg commit -q -m s2; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
gen
t_eq "a docs/generated/status.md conflict stops for a person: exit 1" 1 "$(run)"
t_has "...saying it is generated and is rebuilt on the PR branch" "$(cat "$T_TMP/out")" "docs/generated/status.md is generated: rebuild it on the PR branch"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
race; run >/dev/null
t_eq "a list-only conflict merges, and the generated files are main's, not rebuilt" "status 0|site 0" "$(ms_file main docs/generated/status.md)|$(ms_file main docs/index.html)"
code() { ms_world harbor; echo 'x=1' > "$W/bin/code.sh"; wg add -A; wg commit -q -m c; wg push -q origin main 2>/dev/null
  ms_branch feat; echo 'x=2' > "$W/bin/code.sh"; wg commit -qam pr; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  wg checkout -q main; echo 'x=3' > "$W/bin/code.sh"; wg commit -qam other; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
code
t_eq "a conflict in code stops with exit 1" 1 "$(run)"
t_has "...naming the file for a person" "$(cat "$T_TMP/out")" "conflict needs a person"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
t_eq "...merging nothing" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
t_eq "...and leaving no rebase in progress" "" "$(git -C "$HOME/port/.worktrees/checkout/stack-11" status --porcelain)"

t_section "the resolver reads the base: git is pinned to diff3, whatever the operator configured (red-proof)"
words() { ms_world harbor; printf 'FILES="x y"\n' > "$W/bin/deploy-runtime-install.sh"; wg add -A; wg commit -q -m f; wg push -q origin main 2>/dev/null
  ms_branch feat; printf 'FILES="x y p"\n' > "$W/bin/deploy-runtime-install.sh"; wg commit -qam pr; ms_push feat; ms_pr 11 feat
  wg checkout -q main; printf 'FILES="x y m"\n' > "$W/bin/deploy-runtime-install.sh"; wg commit -qam other; wg push -q origin main 2>/dev/null
  ms_plan "$PL" 11; git config --global merge.conflictStyle merge; }
words
t_eq "with the operator's own style set to merge: exit 0" 0 "$(run)"
t_eq "both words are kept" 'FILES="x y m p"' "$(ms_file main bin/deploy-runtime-install.sh)"
ms_mutant "M8 the rebase uses the operator's conflict style" 's/ -c merge.conflictStyle=diff3//'
words
t_eq "the mutant gets no base section and stops" 1 "$(run "$M/bin/gate-merge-stack.sh")"
ms_mutant "M8b the rebase pins the old merge style" 's/merge.conflictStyle=diff3/merge.conflictStyle=merge/'
words
t_eq "...and so does a tool still pinned to the old style" 1 "$(run "$M/bin/gate-merge-stack.sh")"
gone() { ms_world harbor; printf 'FILES="a b c"\n' > "$W/bin/deploy-runtime-install.sh"; wg add -A; wg commit -q -m f; wg push -q origin main 2>/dev/null
  ms_branch feat; printf 'FILES="a c d"\n' > "$W/bin/deploy-runtime-install.sh"; wg commit -qam pr; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  wg checkout -q main; printf 'FILES="a b c e"\n' > "$W/bin/deploy-runtime-install.sh"; wg commit -qam other; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
gone
t_eq "a PR that deleted a word is not unioned back: stops for a person, exit 1" 1 "$(run)"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"

t_section "code never goes through a line union: main deleted a word, the PR edited the old line (r4 #2, probe n6) (red-proof)"
allow() { ms_world harbor
  printf '#!/bin/sh\nALLOW="status deploy"\ncase " $ALLOW " in *" $1 "*) echo "allowed $1" ;; *) echo "refused $1"; exit 1 ;; esac\n' > "$W/bin/harbor"
  wg add -A; wg commit -q -m seed-harbor; wg push -q origin main 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null
  ms_branch feat; sed 's/ALLOW="status deploy"/ALLOW="status deploy doctor"/' "$W/bin/harbor" > "$W/h.t"; mv "$W/h.t" "$W/bin/harbor"
  wg commit -qam 'PR: allow doctor'; ms_push feat; ms_pr 11 feat "allow doctor"; OLD="$(ms_tip feat)"
  wg checkout -q main; sed 's/ALLOW="status deploy"/ALLOW="status"/' "$W/bin/harbor" > "$W/h.t"; mv "$W/h.t" "$W/bin/harbor"
  wg commit -qam 'main: deploy no longer allowed'; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
allow
t_eq "GitHub calls the PR conflicting" CONFLICTING "$(PATH="$PATH" gh pr view 11 -R acme/widgets --json mergeable --jq .mergeable)"
t_eq "the conflict in bin/harbor stops for a person: exit 1" 1 "$(run)"
t_has "...saying so" "$(cat "$T_TMP/out")" "conflict needs a person"
t_eq "...the PR is still open and its branch untouched" "OPEN $OLD" "$(cat "$MS_FIX/pr/11.state") $(ms_tip feat)"
t_eq "...and main's bin/harbor has only main's ALLOW line" 'ALLOW="status"' "$(ms_file main bin/harbor | grep '^ALLOW=')"
t_eq "the shipped list declares only .txt and .tsv line lists, with no git attribute on any line" "" \
  "$(awk '/^[[:space:]]*(#|$)/ { next } NF != 1 || $1 !~ /[.](txt|tsv)$/' "$T_ROOT/contracts/merge-stack-union.txt")"
printf 'bin/harbor merge=union\n' > "$T_TMP/ua"
ms_mutant "M37 git's union driver is back for bin/harbor" "s#-c merge.conflictStyle=diff3 #-c core.attributesFile=$T_TMP/ua -c merge.conflictStyle=diff3 #"
allow
t_eq "the mutant merges the PR: exit 0" 0 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...main's bin/harbor now holds both ALLOW lines" 2 "$(ms_file main bin/harbor | grep -c '^ALLOW=')"
t_eq "...and allows the word main removed" "allowed deploy" "$(ms_file main bin/harbor > "$T_TMP/h"; sh "$T_TMP/h" deploy)"
ms_mutant "M39 the line-list lookup is skipped: suites.txt conflicts stop" 's/^  if awk -v f="\$2" .*\$UNION"; then$/  if false; then/'
race
t_eq "M39: a PR conflicting only in a declared list now stops for a person" 1 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "only an edit on both sides is resolved: a deletion, an add/add, a binary file or a mode change stops (r5 #1, probe n9) (red-proof)"
legacy() { # <who deletes: main|pr> — main and the PR forked from a seed holding bin/legacy-deploy.sh
  ms_world harbor; printf '#!/bin/sh\necho "legacy deploy"\n' > "$W/bin/legacy-deploy.sh"; wg add -A; wg commit -q -m seed-legacy
  wg push -q origin main 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null; ms_branch feat
  if [ "$1" = pr ]; then wg rm -q bin/legacy-deploy.sh; else printf 'echo "skip the approval"\n' >> "$W/bin/legacy-deploy.sh"; fi
  wg commit -qam "PR side"; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"; wg checkout -q main
  if [ "$1" = pr ]; then printf 'echo v2\n' >> "$W/bin/legacy-deploy.sh"; else wg rm -q bin/legacy-deploy.sh; fi
  wg commit -qam "main side"; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
legacy main
t_eq "main deleted the file the PR edits: GitHub calls it conflicting" CONFLICTING "$(PATH="$PATH" gh pr view 11 -R acme/widgets --json mergeable --jq .mergeable)"
t_eq "...stops for a person: exit 1 (probe n9 A)" 1 "$(run)"
t_has "...saying it is not an edit on both sides" "$(cat "$T_TMP/out")" "bin/legacy-deploy.sh: not an edit on both sides"
t_eq "...the file stays deleted on main, the PR open and its branch untouched" "absent OPEN $OLD" "$(ms_file main bin/legacy-deploy.sh >/dev/null && echo present || echo absent) $(cat "$MS_FIX/pr/11.state") $(ms_tip feat)"
legacy pr
t_eq "the PR deletes the file main edited: stops for a person, exit 1 (probe n9 B)" 1 "$(run)"
t_eq "...main keeps its edit and the PR is open" "echo v2 OPEN" "$(ms_file main bin/legacy-deploy.sh | tail -1) $(cat "$MS_FIX/pr/11.state")"
addadd() { ms_world harbor; ms_branch feat; ms_add contracts/idle-tools.txt pr-tool; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  ms_main contracts/idle-tools.txt main-tool; ms_plan "$PL" 11; }
addadd
t_eq "both sides created the same declared list (an add/add the resolver alone would union): exit 1" 1 "$(run)"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
blob() { ms_world harbor; printf 'v0\000\001' > "$W/logo.bin"; wg add -A; wg commit -q -m blob; wg push -q origin main 2>/dev/null
  ms_branch feat; printf 'pr\000\002' > "$W/logo.bin"; wg commit -qam pr; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  wg checkout -q main; printf 'main\000\003' > "$W/logo.bin"; wg commit -qam main; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
blob
t_eq "a binary file both sides changed (git leaves no marker): exit 1" 1 "$(run)"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
modes() { ms_world harbor; printf 'FILES="x y"\n' > "$W/bin/deploy-runtime-install.sh"; wg add -A; wg commit -q -m f; wg push -q origin main 2>/dev/null
  ms_branch feat; printf 'FILES="x y p"\n' > "$W/bin/deploy-runtime-install.sh"; wg commit -qam pr; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  wg checkout -q main; printf 'FILES="x y m"\n' > "$W/bin/deploy-runtime-install.sh"; chmod +x "$W/bin/deploy-runtime-install.sh"; wg commit -qam other; wg push -q origin main 2>/dev/null; ms_plan "$PL" 11; }
modes
t_eq "a FILES list both sides added to, while main also changed the mode: exit 1" 1 "$(run)"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
ms_mutant "M43 settle no longer asks for all three stages" 's/^    elif ! three_stages "\$1" "\$_f"; then/    elif false; then/'
addadd; t_eq "M43: the add/add merges (exit 0)" 0 "$(run "$M/bin/gate-merge-stack.sh")"
modes; t_eq "M43: so does the mode change" 0 "$(run "$M/bin/gate-merge-stack.sh")"
unblock() { python3 - "$M/bin/gate-merge-stack-resolve.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
for a, b in (("if '<<<<<<<' not in s or not hash_syntax(p, s)", "if '<<<<<<<' in s and not hash_syntax(p, s)"), ("blocks == 0 or ", "")):
    assert a in s, a
    s = s.replace(a, b)
open(p, "w").write(s)
PY
}
ms_mutant "M44 the resolver passes a file with no conflict block" 's/^# A conflicted file both sides only added to: keep both.*/# M44/'; unblock
blob; t_eq "M44: the binary file merges as main's copy, the PR's change dropped (exit 0)" "0 main" "$(run "$M/bin/gate-merge-stack.sh") $(ms_file main logo.bin | head -c 4)"
ms_mutant "M45 the r5 #1 fix reverted: any stages, a file with no block passes" 's/^    elif ! three_stages "\$1" "\$_f"; then/    elif false; then/'; unblock
legacy main; t_eq "M45: main's deletion is undone (probe n9 A)" "0 present" "$(run "$M/bin/gate-merge-stack.sh") $(ms_file main bin/legacy-deploy.sh >/dev/null && echo present || echo absent)"
legacy pr; t_eq "M45: the PR's approved deletion is dropped (probe n9 B)" "0 present" "$(run "$M/bin/gate-merge-stack.sh") $(ms_file main bin/legacy-deploy.sh >/dev/null && echo present || echo absent)"

t_section "sync runs none of the PR's code: not its generators, not the hooks in its tree (r5 #2, probe n14) (red-proof)"
# the PR's doc-index-generate.sh does its job, then writes a commit straight to main with whatever credentials run it (n14-gen.sh)
backdoor() { ms_world harbor; ms_branch feat; ms_add "$SU" tests/p/pr.test.sh
  cp "$T_ROOT/tests/ci/merge-stack/backdoor-generate.sh" "$W/bin/doc-index-generate.sh"; cp "$W/bin/doc-index-generate.sh" "$W/bin/status-generate.sh"
  wg commit -qam 'PR: tweak the generators'; ms_push feat; ms_pr 11 feat
  ms_main "$SU" tests/m/main.test.sh; ms_plan "$PL" 11
  # CI still running at preflight, then red: the PR must never merge, and nothing of it may reach main
  printf '[{"databaseId":901,"status":"in_progress","conclusion":"","workflowDatabaseId":1,"event":"pull_request"}]\n' > "$MS_FIX/runs/default.1"
  echo 1 > "$MS_FIX/watch/901"; echo failure > "$MS_FIX/view/901"; }
backdoor
t_eq "a red PR whose generators write to main: exit 1" 1 "$(run)"
t_has "...stopped on its red CI" "$(cat "$T_TMP/out")" "CI run 901 is red"
t_eq "...and nothing of it is on main: no backdoor.txt, main's tip is main's own (probe n14)" "absent|add tests/m/main.test.sh" \
  "$(ms_file main backdoor.txt || echo absent)|$(git --git-dir="$MS_BARE" log -1 --format=%s main)"
ms_mutant "M46 sync runs the PR's doc-index-generate.sh again" 's#^  \[ -z "\$(git -C "\$1" status --porcelain --untracked-files=no)" \] || git -C "\$1" commit -qam "\$2"$#  [ ! -f "$1/bin/doc-index-generate.sh" ] || sh "$1/bin/doc-index-generate.sh" --apply >/dev/null; &#'
backdoor; run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "M46: the red PR's commit is on main" unreviewed "$(ms_file main backdoor.txt)"
# the operator's checkout keeps its hooks in the repo (a relative core.hooksPath): in sync's worktree that is the PR's tree
hooked() { race; git -C "$H" config core.hooksPath hooks; wg checkout -q feat; mkdir -p "$W/hooks"
  for h in post-checkout pre-commit commit-msg post-commit post-rewrite pre-push reference-transaction; do
    printf '#!/bin/sh\npwd >> "%s/ran-%s"\n' "$T_TMP" "$h" > "$W/hooks/$h"; chmod +x "$W/hooks/$h"; done
  wg add -A; wg commit -q -m 'PR: hooks'; ms_push feat; rm -f "$T_TMP"/ran-*; }
hooked
t_eq "a PR carrying hooks the checkout's config points at: merges, exit 0" 0 "$(run)"
t_eq "...and not one of them ran" "none" "$(cat "$T_TMP"/ran-* 2>/dev/null || echo none)"
ms_mutant "M47 git runs with the operator's hooks" 's#^git() { command git -c core.hooksPath=/dev/null "\$@"; }$#git() { command git "$@"; }#'
hooked; run "$M/bin/gate-merge-stack.sh" >/dev/null
t_has "M47: the PR's own pre-push ran in sync's worktree" "$(cat "$T_TMP"/ran-pre-push 2>/dev/null)" "$HOME/port/.worktrees/checkout/stack-11"

t_section "no merge driver: the repo's attributes, the checkout's merge.default and info/attributes all stop for a person (r5 #5, probe n15) (red-proof)"
attr() { # <where the union driver is set: tree|default|info> — on top of n6's ALLOW conflict, a suites.txt one keeps it CONFLICTING
  allow; wg checkout -q feat; ms_add "$SU" tests/p/pr.test.sh; ms_push feat; OLD="$(ms_tip feat)"; ms_main "$SU" tests/m/main.test.sh
  case "$1" in
    tree) printf 'bin/harbor merge=union\n' > "$W/.gitattributes"; wg add -A; wg commit -q -m attr; wg push -q origin main 2>/dev/null ;;
    default) git -C "$H" config merge.default union ;;
    info) mkdir -p "$H/.git/info"; printf 'bin/harbor merge=union\n' > "$H/.git/info/attributes" ;;
  esac; }
attr tree
t_eq "main's .gitattributes sets bin/harbor merge=union: still stops for a person, exit 1" 1 "$(run)"
t_eq "...main's bin/harbor keeps one ALLOW line" 1 "$(ms_file main bin/harbor | grep -c '^ALLOW=')"
attr default
t_eq "merge.default=union in the checkout's config: stops, exit 1" 1 "$(run)"
attr info
t_eq "the checkout's .git/info/attributes sets it: stops, exit 1" 1 "$(run)"
t_has "...naming the driver" "$(cat "$T_TMP/out")" "a merge driver would resolve these unseen: bin/harbor (merge=union)"
t_eq "...pushing nothing" "$OLD" "$(ms_tip feat)"
ms_mutant "M48 the rebase reads the tree's attributes" 's# --attr-source="\$(empty_tree "\$_ad")"##'
attr tree; t_eq "M48: main's attribute unions bin/harbor and merges (probe n15)" "0 2" "$(run "$M/bin/gate-merge-stack.sh") $(ms_file main bin/harbor | grep -c '^ALLOW=')"
ms_mutant "M49 merge.default is the operator's" 's# -c merge.default=text##'
attr default; t_eq "M49: the checkout's default unions it and merges" 0 "$(run "$M/bin/gate-merge-stack.sh")"
ms_mutant "M50 no driver check" 's#^  \[ -z "\$_dv" \] ||#  true ||#'
attr info; t_eq "M50: info/attributes unions it and merges" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "the PR that is merged is the one on origin, not the local checkout's copy of the branch (red-proof)"
local_branch() { # <how> — a local branch $H holds, not checked out anywhere
  race; git -C "$H" fetch -q origin; git -C "$H" branch feat origin/feat; }
local_branch
git -C "$H" checkout -q feat; echo "local only" > "$H/local-secret.txt"; git -C "$H" add -A; git -C "$H" commit -q -m local; git -C "$H" checkout -q main
t_eq "an unpushed local commit: exit 1" 1 "$(run)"
t_has "it says the local branch is not origin's" "$(cat "$T_TMP/out")" "local branch feat is not origin/feat"
t_eq "the PR branch on origin was not touched" "$OLD" "$(ms_tip feat)"
t_eq "the local-only file is not on main" "" "$(ms_file main local-secret.txt)"
ms_mutant "M27 sync trusts the local branch" 's/^  \[ "\$(git -C "\$_w" rev-parse HEAD)" = .*$/  true/'
local_branch
git -C "$H" checkout -q feat; echo "local only" > "$H/local-secret.txt"; git -C "$H" add -A; git -C "$H" commit -q -m local; git -C "$H" checkout -q main
run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant merges the unpushed file onto main" "local only" "$(ms_file main local-secret.txt)"
local_branch
wg fetch -q origin; wg checkout -q -B feat origin/feat; echo "reviewed fix" > "$W/fix.txt"; wg add -A; wg commit -q -m fix; ms_push feat; NEW="$(ms_tip feat)"
t_eq "a local branch older than origin's: exit 1" 1 "$(run)"
t_eq "...origin's branch kept its reviewed commit" "$NEW" "$(ms_tip feat)"
local_branch
wg fetch -q origin; wg checkout -q -B feat origin/feat; echo "reviewed fix" > "$W/fix.txt"; wg add -A; wg commit -q -m fix; ms_push feat
run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant wipes the reviewed fix from the PR" "" "$(ms_file feat fix.txt)"

t_section "the INSTALLED layout: runtime-install ships merge-stack, and that copy rebases a line list and merges (5b.9) (red-proof)"
# The real installer into a sandbox config dir, then the INSTALLED gate-merge-stack.sh and real gate-merge-check.sh, no checkout above them.
CFG="$T_TMP/cfg"; rm -rf "$CFG"; mkdir -p "$CFG"; printf '{}' > "$CFG/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-runtime-install.sh" --apply --dir "$CFG" >"$T_TMP/install.out" 2>&1
t_eq "runtime-install --apply into a sandbox: exit 0" 0 "$?"
t_eq "...it installs the tool, merge-check, the resolver and the union list in bin/" "yes yes yes yes" \
  "$(for f in gate-merge-stack.sh gate-merge-check.sh gate-merge-stack-resolve.py merge-stack-union.txt; do [ -f "$CFG/bin/$f" ] && printf 'yes ' || printf 'no '; done | sed 's/ $//')"
t_eq "...and no contracts/ above bin/ for the union path to fall back on" no "$([ -e "$CFG/contracts" ] && echo yes || echo no)"
installed() { race; printf '{"required_status_checks":{"contexts":["suite"],"strict":false}}' > "$MS_FIX/protection.out"; echo 0 > "$MS_FIX/protection.rc"
  printf 'suite\tpass\t1m\thttps://example.invalid/1\n' > "$MS_FIX/checks.tsv"; }
installed
t_eq "the installed copy rebases a PR conflicting in a declared line list, and merges it: exit 0" 0 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_eq "...main holds both suites once" "1 1" "$(lines main "$SU" tests/p/pr.test.sh) $(lines main "$SU" tests/m/main.test.sh)"
t_has "...through the installed real merge-check" "$(cat "$T_TMP/out")" "gate: GitHub branch protection"
mv "$CFG/bin/merge-stack-union.txt" "$CFG/bin/union.away"; installed
t_eq "RED: with no union list beside the installed tool: exit 1" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_has "...saying the install is incomplete" "$(cat "$T_TMP/out")" "no merge-stack-union.txt beside $CFG/bin"
t_eq "...and nothing merged" OPEN "$(cat "$MS_FIX/pr/11.state")"
mv "$CFG/bin/union.away" "$CFG/bin/merge-stack-union.txt"
t_done
