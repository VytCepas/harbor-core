#!/usr/bin/env sh
# harbor merge-stack for a repo that is not harbor (harbor#1060, ship contract 5a.6): gate-merge-check.sh comes from the tool's
# own install dir, with HARBOR_REPO and the required-checks list as origin/<default branch> holds it, empty when it has none
# (5b.11: never the working tree). A repo with NO bin/ merges.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
PL="$T_TMP/plan"
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
plain() { ms_world; ms_branch feat; ms_add plain.txt one; ms_push feat; ms_pr 11 feat "plain feat"; ms_plan "$PL" 11; }

t_section "a repo with no bin/ of its own merges through the tool"
plain
t_eq "the fake repo has no bin/ at all" no "$([ -e "$H/bin" ] && echo yes || echo no)"
t_eq "check passes: merge-check is the tool's own" 0 "$(sh "$GMS" check "$PL" >/dev/null 2>&1; echo $?)"
t_eq "merge: exit 0" 0 "$(run)"
t_eq "merge-check was the install's, asked for #11" "merge-check --squash --merge 11" "$(cat "$MS_FIX/merge.log")"
t_eq "...told the repo from the plan, and an empty required-checks list (origin declares none)" "repo=acme/widgets rc=/ br=main" "$(sed 's#rc=/[^ ]*#rc=/#' "$MS_FIX/env.log")"
t_eq "...the list is empty, so merge-check never falls back to a file of its own" "" "$(cat "$MS_FIX/rc.log")"
t_eq "the PR is on main" "plain feat (#11)" "$(git --git-dir="$MS_BARE" log --format=%s -1 main)"

t_section "the repo's own .agents/required-checks.tsv is passed when origin/<default branch> holds it"
ms_world; mkdir -p "$W/.agents"; printf 'acme/widgets\tsuite\n' > "$W/.agents/required-checks.tsv"; wg add -A; wg commit -q -m optin
wg push -q origin main 2>/dev/null; ms_branch feat; ms_add plain.txt one; ms_push feat; ms_pr 11 feat "plain feat"; ms_plan "$PL" 11
mkdir -p "$H/.agents"; printf 'acme/widgets\tedited\n' > "$H/.agents/required-checks.tsv"   # an edit in the checkout: never read
t_eq "exit 0" 0 "$(run)"
t_has "merge-check was given a file" "$(cat "$MS_FIX/env.log")" "repo=acme/widgets rc=/"
t_eq "...holding origin/main's rows" "$(printf 'acme/widgets\tsuite')" "$(cat "$MS_FIX/rc.log")"
t_eq "...a temp copy, gone after the run" no "$(f="$(sed -n 's/.* rc=\([^ ]*\) .*/\1/p' "$MS_FIX/env.log")"; [ -e "$f" ] && echo yes || echo no)"
plain; mkdir -p "$H/.agents"; printf 'acme/widgets\tsuite\n' > "$H/.agents/required-checks.tsv"
t_eq "a file only in the working tree: exit 0" 0 "$(run)"
t_eq "...is not read: merge-check's list is empty" "" "$(cat "$MS_FIX/rc.log")"

t_section "a repo's own bin/gate-merge-check.sh is never the one that runs"
ms_world; ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat; ms_plan "$PL" 11
mkdir -p "$H/bin"; printf '#!/bin/sh\necho decoy > "$MS_FIX/decoy"\nexit 1\n' > "$H/bin/gate-merge-check.sh"
t_eq "exit 0" 0 "$(run)"
t_eq "the decoy never ran" no "$([ -e "$MS_FIX/decoy" ] && echo yes || echo no)"

t_section "red-proof: merge-check resolved from the repo checkout (the bug) cannot merge a repo with no bin/"
ms_mutant "M16 resolve merge-check from the checkout" 's#^MC="\$HERE/gate-merge-check.sh"#MC="$H/bin/gate-merge-check.sh"#'
plain
t_eq "the mutant is refused at the preflight" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_has "...for the missing script in the repo" "$(cat "$T_TMP/out")" "no $H/bin/gate-merge-check.sh"
t_eq "...and merges nothing" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
ms_mutant "M17 the repo is not passed to merge-check" 's/HARBOR_REPO="\$R"; export HARBOR_REPO; //'
plain; run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant's merge-check got no HARBOR_REPO" "repo= rc=/ br=main" "$(sed 's#rc=/[^ ]*#rc=/#' "$MS_FIX/env.log")"

t_section "another repo's own docs/index.html is never taken from the base, nor regenerated (red-proof)"
site() { ms_world; mkdir -p "$W/docs"; echo "theirs v0" > "$W/docs/index.html"; wg add -A; wg commit -q -m site; wg push -q origin "HEAD:$MS_DEF" 2>/dev/null
  git -C "$H" pull -q --ff-only 2>/dev/null; ms_branch feat; echo "theirs pr" > "$W/docs/index.html"; wg commit -qam pr; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  wg checkout -q "$MS_DEF"; echo "theirs main" > "$W/docs/index.html"; wg commit -qam main; wg push -q origin "$MS_DEF" 2>/dev/null; ms_plan "$PL" 11; }
site
t_eq "a conflict in it stops for a person: exit 1" 1 "$(run)"
t_has "...naming the PR's conflict" "$(cat "$T_TMP/out")" "conflict needs a person"
t_eq "...and pushes nothing" "$OLD" "$(ms_tip feat)"
ms_mutant "M22 a conflicted file is taken from the base" 's/^    if generated_by "\$1" "\$_f"; then log_warn .*$/    if true; then git -C "$1" checkout -q --ours "$_f"; git -C "$1" add "$_f"/'
site; t_eq "the mutant takes the base's copy and merges" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "the default branch is the remote's, not main (red-proof)"
unset MS_DEF; MS_DEF=trunk
trunk() { ms_world harbor; ms_branch feat; ms_add contracts/suites.txt tests/p/pr.test.sh; ms_push feat; ms_pr 11 feat; OLD="$(ms_tip feat)"
  ms_main contracts/suites.txt tests/m/main.test.sh; ms_plan "$PL" 11; }
trunk
t_eq "the remote's default branch is trunk" trunk "$(git --git-dir="$MS_BARE" symbolic-ref --short HEAD)"
t_eq "a conflicting PR is rebased onto trunk and merged: exit 0" 0 "$(run)"
t_eq "trunk holds both suites" "1 1" "$(git --git-dir="$MS_BARE" show trunk:contracts/suites.txt | grep -cxF tests/p/pr.test.sh) $(git --git-dir="$MS_BARE" show trunk:contracts/suites.txt | grep -cxF tests/m/main.test.sh)"
t_has "merge-check is told the branch" "$(cat "$MS_FIX/env.log")" "br=trunk"
trunk; sh "$GMS" rehearse "$PL" --push >"$T_TMP/out" 2>&1; t_eq "rehearse --push builds on trunk: exit 0" 0 "$?"
t_has "...and opens the PR against trunk" "$(grep '^pr create' "$MS_FIX/calls.log")" "--base trunk"
run >/dev/null; sh "$GMS" verify "$PL" >"$T_TMP/out" 2>&1; t_eq "verify on trunk: exit 0" 0 "$?"
t_has "...ALL CLEAR" "$(cat "$T_TMP/out")" "ALL CLEAR"
ms_mutant "M23 the default branch is hard-coded to main" 's#DEF="\$(default_branch)"#DEF=main#'
trunk; t_eq "the mutant cannot read a main that does not exist (it fails)" yes "$([ "$(run "$M/bin/gate-merge-stack.sh")" != 0 ] && echo yes || echo no)"
t_eq "...and merges nothing" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
unset MS_DEF
t_done
