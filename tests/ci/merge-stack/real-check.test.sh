#!/usr/bin/env sh
# harbor merge-stack with the REAL bin/gate-merge-check.sh beside it (harbor#1060): the stub gh answers branch protection (403, 404,
# 200) and the PR's check rows, so what a repo must do to opt in is pinned to merge-check's actual behaviour, not to a stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
PL="$T_TMP/plan"
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
GH403='gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
GH404='gh: Branch not protected (HTTP 404)'
GH200='{"required_status_checks":{"contexts":["suite"],"strict":false}}'
# world <protection answer> <exit> <check rows> <opt-in rows, committed to origin/main; '' for none>
world() { ms_world; ms_real_check; [ -z "$4" ] || optin "$4"
  ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat "feat a"; ms_plan "$PL" 11
  printf '%s' "$1" > "$MS_FIX/protection.out"; printf '%s' "$2" > "$MS_FIX/protection.rc"; printf "$3" > "$MS_FIX/checks.tsv"; }
optin() { mkdir -p "$W/.agents"; printf "$1" > "$W/.agents/required-checks.tsv"; wg add -A; wg commit -q -m optin
  wg push -q origin "$MS_DEF" 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null; }
ONE='acme/widgets\tsuite\n'; TWO='acme/widgets\tsuite\nacme/widgets\tsecurity\n'
PASS='suite\tpass\t1m\thttps://example.invalid/1\n'; FAIL='suite\tfail\t1m\thttps://example.invalid/1\n'

t_section "the opt-in file gates a repo whose branch protection answers 403 (a private repo on a free plan)"
world "$GH403" 1 "$PASS" "$ONE"
t_eq "a listed check that passes: the real merge-check merges, exit 0" 0 "$(run)"
t_has "it says which gate it used" "$(OUT)" "gate: local"
t_eq "the PR is merged" MERGED "$(cat "$MS_FIX/pr/11.state")"
t_has "gh was told to merge only that head" "$(cat "$MS_FIX/gh-merge.log")" "--squash --match-head-commit $(ms_tip feat)"
world "$GH403" 1 "$FAIL" "$ONE"
t_eq "a listed check that is red: refused" 1 "$(run)"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"

t_section "branch protection with required checks is the other opt-in"
world "$GH200" 0 "$PASS" ''
t_eq "protection requiring the check, which passes: exit 0" 0 "$(run)"
t_has "the gate is GitHub's" "$(OUT)" "gate: GitHub branch protection"
world "$GH200" 0 "$FAIL" ''
t_eq "...and red: refused" 1 "$(run)"

t_section "neither opt-in is a refusal; GitHub's exact 404 'Branch not protected' falls back to the file (#1139)"
world "$GH403" 1 "$PASS" ''
t_eq "403 and no file: refused, merge-check has no gate to judge by" 1 "$(run)"
world "$GH404" 1 "$PASS" ''
t_eq "404 and no file: refused too" 1 "$(run)"
t_eq "...and nothing was merged" OPEN "$(cat "$MS_FIX/pr/11.state")"
world "$GH404" 1 "$PASS" "$ONE"
t_eq "404 'Branch not protected' with the file, its check green: merges" 0 "$(run)"
t_has "...on the local gate" "$(OUT)" "gate: local"
world "$GH404" 1 "$FAIL" "$ONE"
t_eq "...and red: refused" 1 "$(run)"
world 'gh: Not Found (HTTP 404)' 1 "$PASS" "$ONE"
t_eq "any other 404 (no such repo or branch) with the file: refused" 1 "$(run)"

t_section "red-proof: the repo's file must reach merge-check"
ms_mutant "M30 the required-checks file is not passed" 's/^      HARBOR_GATE_REQUIRED_CHECKS="\$RCTMP"; export HARBOR_GATE_REQUIRED_CHECKS$/      :/'
world "$GH403" 1 "$PASS" "$ONE"
t_eq "the mutant: the same repo is refused, merge-check never saw its file" 1 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "the opt-in file is read from origin/<default branch>, never the checkout's working tree (5b.11) (red-proof)"
# origin/main lists suite and security; the PR makes its security job skip itself
SEC='suite\tpass\t1m\thttps://example.invalid/1\nsecurity\tskipping\t0\thttps://example.invalid/2\n'
world "$GH403" 1 "$SEC" "$TWO"
t_eq "control: the checkout equals origin/main, the skipped listed check is refused" 1 "$(run)"
t_has "...naming it" "$(OUT)" "security"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
uncommitted() { world "$GH403" 1 "$SEC" "$TWO"; printf "$ONE" > "$H/.agents/required-checks.tsv"; }
uncommitted
t_eq "an uncommitted edit in the checkout drops the security row: still refused" 1 "$(run)"
t_eq "...the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
prbranch() { world "$GH403" 1 "$SEC" "$TWO"; wg checkout -q feat; printf "$ONE" > "$W/.agents/required-checks.tsv"; wg commit -qam 'drop security'
  ms_push feat; git -C "$H" fetch -q origin; git -C "$H" checkout -q -B feat origin/feat; }
prbranch
t_eq "the checkout is on the PR's branch, whose own commit drops the row: still refused" 1 "$(run)"
t_eq "...the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
t_eq "...and main still lists both checks" "$(printf "$TWO")" "$(ms_file main .agents/required-checks.tsv)"
world "$GH403" 1 "$PASS" ''; mkdir -p "$H/.agents"; printf "$ONE" > "$H/.agents/required-checks.tsv"
t_eq "a file only in the working tree (origin/main has none) is no opt-in: refused" 1 "$(run)"
ms_mutant "M31 the opt-in file is read from the working tree" 's|git -C "\$H" show "refs/remotes/origin/\$DEF:\$_rp" >> "\$RCTMP.all"|cat "$H/$_rp" >> "$RCTMP.all"|'
uncommitted
t_eq "the mutant merges on the uncommitted edit" 0 "$(run "$M/bin/gate-merge-stack.sh")"
prbranch
t_eq "...and on the PR's own branch" 0 "$(run "$M/bin/gate-merge-stack.sh")"
t_eq "...whose merge deletes main's security row" "$(printf "$ONE")" "$(ms_file main .agents/required-checks.tsv)"

t_section "rows only in contracts/required-checks.tsv on origin (harbor's shape): read from origin in BOTH layouts (r4 #1) (red-proof)"
# merge-check's own fallback is the file beside it: from a checkout's bin/ (how `harbor merge-stack` runs) that is the working tree
BOTH='suite\tpass\t1m\thttps://example.invalid/1\nsecurity\tpass\t1m\thttps://example.invalid/2\n'
harborish() { # <check rows> [checkout] — origin lists suite + security in contracts/, no .agents file; [checkout] puts the tool in the repo
  ms_world; mkdir -p "$W/contracts"; printf "$TWO" > "$W/contracts/required-checks.tsv"
  if [ "${2:-}" = checkout ]; then mkdir -p "$W/bin"; cp "$T_ROOT/contracts/merge-stack-union.txt" "$W/contracts/"
    cp "$T_ROOT/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack-resolve.py" "$T_ROOT/bin/gate-merge-check.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/ci-lost-job.sh" "$W/bin/"; fi
  wg add -A; wg commit -q -m rows; wg push -q origin "$MS_DEF" 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null
  ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat "feat a"; ms_plan "$PL" 11
  printf '%s' "$GH403" > "$MS_FIX/protection.out"; echo 1 > "$MS_FIX/protection.rc"; printf "$1" > "$MS_FIX/checks.tsv"; }
dropped_on_pr() { wg checkout -q feat; printf "$ONE" > "$W/contracts/required-checks.tsv"; wg commit -qam 'drop security'
  ms_push feat; git -C "$H" fetch -q origin; git -C "$H" checkout -q -B feat origin/feat; }
CK="$H/bin/gate-merge-stack.sh"
harborish "$BOTH" checkout
t_eq "origin has no .agents file, only contracts/required-checks.tsv" "" "$(ms_file main .agents/required-checks.tsv)"
t_eq "checkout layout, every listed check green: merges, exit 0" 0 "$(run "$CK")"
t_eq "...the PR is merged" MERGED "$(cat "$MS_FIX/pr/11.state")"
t_has "...gated on origin's CONTRACTS file" "$(OUT)" "required checks: contracts/required-checks.tsv as origin/main holds it"
harborish "$SEC" checkout
t_eq "checkout layout, a listed check skips itself: refused" 1 "$(run "$CK")"
harborish "$SEC" checkout; printf "$ONE" > "$H/contracts/required-checks.tsv"
t_eq "checkout layout, an uncommitted edit drops the row: still refused (probe n5 A)" 1 "$(run "$CK")"
t_eq "...the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
harborish "$SEC" checkout; dropped_on_pr
t_eq "checkout layout, on the PR's branch whose commit drops the row: still refused (probe n5 B)" 1 "$(run "$CK")"
t_eq "...and main still lists both checks" "$(printf "$TWO")" "$(ms_file main contracts/required-checks.tsv)"
# the installed layout (5b.9): runtime-install's copy, with no contracts/ above its bin/
CFG="$T_TMP/cfg"; rm -rf "$CFG"; mkdir -p "$CFG"; printf '{}' > "$CFG/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-runtime-install.sh" --apply --dir "$CFG" >"$T_TMP/install.out" 2>&1
t_eq "runtime-install --apply into a sandbox: exit 0, no contracts/ above bin/" "0 no" "$? $([ -e "$CFG/contracts" ] && echo yes || echo no)"
harborish "$BOTH"
t_eq "installed layout, every listed check green: merges, exit 0 (probe n8)" 0 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_eq "...the PR is merged" MERGED "$(cat "$MS_FIX/pr/11.state")"
harborish "$SEC"
t_eq "installed layout, a listed check skips itself: refused" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
harborish "$SEC"; printf "$ONE" > "$H/contracts/required-checks.tsv"
t_eq "installed layout, an uncommitted edit drops the row: still refused" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
harborish "$SEC"; dropped_on_pr
t_eq "installed layout, on the PR's branch whose commit drops the row: still refused" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_eq "...the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
on_main() { wg checkout -q "$MS_DEF"; "$@"; wg commit -qam "$*"; wg push -q origin "$MS_DEF" 2>/dev/null; }
two_agents() { mkdir -p "$W/.agents"; printf "$TWO" > "$W/.agents/required-checks.tsv"; printf "$ONE" > "$W/contracts/required-checks.tsv"; wg add -A; }
harborish "$SEC"; on_main two_agents
t_eq "origin's .agents file counts beside its contracts/ one: its security row is required, so refused" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_has "...gated on the .agents file" "$(OUT)" "required checks: .agents/required-checks.tsv as origin/main holds it"
harborish "$BOTH"; on_main git -C "$W" rm -q contracts/required-checks.tsv
mkdir -p "$H/contracts"; printf "$TWO" > "$H/contracts/required-checks.tsv"
t_eq "origin declares nothing, a working-tree file does: refused, only protection could gate" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"
t_has "...saying origin declares none" "$(OUT)" "origin/main declares none"
ms_mutant "M30b merge-check is not handed the list, from the checkout" 's/^      HARBOR_GATE_REQUIRED_CHECKS="\$RCTMP"; export HARBOR_GATE_REQUIRED_CHECKS$/      :/'
harborish "$SEC" checkout; cp "$M/bin/gate-merge-stack.sh" "$H/bin/gate-merge-stack.sh"; printf "$ONE" > "$H/contracts/required-checks.tsv"
t_eq "the mutant, run from the checkout, merges on the uncommitted edit" 0 "$(run "$CK")"
harborish "$BOTH"; cp "$T_ROOT/bin/gate-merge-check.sh" "$T_ROOT/bin/ci-lost-job.sh" "$M/bin/"
t_eq "...and the installed mutant refuses harbor's green PR (merge-check has no file beside it)" 1 "$(run "$M/bin/gate-merge-stack.sh")"
t_section "a repo is judged by the UNION of its own declaration and harbor's rows for it (r5 #3, #1139, probe n11) (red-proof)"
# a Flow-shaped repo: GitHub answers 404 "Branch not protected"; harbor's file beside the tool lists its two checks
flow() { # <check rows> [the repo's own .agents rows on origin]
  ms_world; ms_real_check; printf 'acme/widgets\tunit-test\nacme/widgets\tgrammar-test\n' > "$MS_INST/contracts/required-checks.tsv"
  [ -z "${2:-}" ] || optin "$2"
  ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat "feat a"; ms_plan "$PL" 11
  printf '%s' "$GH404" > "$MS_FIX/protection.out"; echo 1 > "$MS_FIX/protection.rc"; printf "$1" > "$MS_FIX/checks.tsv"; }
DBT2='unit-test\tpass\t1m\thttps://example.invalid/1\ngrammar-test\tpass\t1m\thttps://example.invalid/2\n'
DBTRED='unit-test\tfail\t1m\thttps://example.invalid/1\ngrammar-test\tpass\t1m\thttps://example.invalid/2\n'
DBT1='unit-test\tpass\t1m\thttps://example.invalid/1\n'
flow "$DBT2"
t_eq "no declaration on the repo's origin, harbor's rows green: merges, exit 0 (probe n11 c)" 0 "$(run)"
t_has "...on the local gate" "$(OUT)" "gate: local"
t_has "...naming the checks it holds for the run" "$(OUT)" "required checks for acme/widgets, fixed for this run: unit-test | grammar-test"
flow "$DBTRED"
t_eq "a check harbor lists is red: refused (probe n11 d)" 1 "$(run)"
flow "$DBT1" 'acme/widgets\tunit-test\n'
t_eq "the repo's own file lists only unit-test and the PR dropped the grammar job: refused (probe n11 e)" 1 "$(run)"
t_has "...naming the check harbor requires" "$(OUT)" "grammar-test"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
flow "$DBT2" 'acme/widgets\tunit-test\nacme/widgets\tdocs-check\n'
t_eq "a check the repo's own file adds is required too: refused while it is missing" 1 "$(run)"
t_has "...naming it" "$(OUT)" "docs-check"
ms_mutant "M56 harbor's rows are left out of the union" 's/^  harbor_rows >> .*$/  :/'
flow "$DBT2"; t_eq "M56: the green Flow PR is refused again (n11 c)" 1 "$(run "$M/bin/gate-merge-stack.sh")"
flow "$DBT1" 'acme/widgets\tunit-test\n'; t_eq "M56: the weaker repo file merges the PR that dropped a job (n11 e)" 0 "$(run "$M/bin/gate-merge-stack.sh")"
# harbor's rows from a harbor CHECKOUT come from its origin's default branch, never its working tree (r4 #1's rule)
HB="$T_TMP/harbor.git"; HC="$T_TMP/hc"
harbor_checkout() { rm -rf "$HB" "$HC"; git init -q --bare "$HB"; git clone -q "$HB" "$HC" 2>/dev/null; mkdir -p "$HC/bin" "$HC/contracts"
  cp "$T_ROOT/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack-resolve.py" "$T_ROOT/bin/gate-merge-check.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/ci-lost-job.sh" "$HC/bin/"
  cp "$T_ROOT/contracts/merge-stack-union.txt" "$HC/contracts/"; printf 'acme/widgets\tunit-test\nacme/widgets\tgrammar-test\n' > "$HC/contracts/required-checks.tsv"
  git -C "$HC" add -A; git -C "$HC" commit -q -m harbor; git -C "$HC" push -q origin HEAD 2>/dev/null
  printf 'acme/widgets\tunit-test\n' > "$HC/contracts/required-checks.tsv"; }   # an uncommitted edit drops the grammar row
flow "$DBT1"; harbor_checkout
t_eq "from a harbor checkout whose working tree dropped the grammar row: still refused" 1 "$(run "$HC/bin/gate-merge-stack.sh")"
t_has "...on the row its origin holds" "$(OUT)" "grammar-test"
flow "$DBT2"; harbor_checkout
t_eq "...and the same PR with both jobs green merges from that checkout" 0 "$(run "$HC/bin/gate-merge-stack.sh")"
flow "$DBT1"; harbor_checkout; sed 's#^  _hc="\$(CDPATH= cd -- "\$HERE/\.\.".*$#  cat "$HROWS"; return#' "$HC/bin/gate-merge-stack.sh" > "$T_TMP/m58"
t_eq "M58: the mutation applies" 1 "$(cmp -s "$T_TMP/m58" "$HC/bin/gate-merge-stack.sh"; echo $?)"
cp "$T_TMP/m58" "$HC/bin/gate-merge-stack.sh"
t_eq "M58: harbor's rows read from the working tree: the dropped row lets the PR merge" 0 "$(run "$HC/bin/gate-merge-stack.sh")"
# the installed layout: harbor's rows are the copy runtime-install put beside the tool
printf 'acme/widgets\tunit-test\n' >> "$CFG/bin/required-checks.tsv"
flow "$DBT1"
t_eq "installed layout, the row in the installed copy, green: merges" 0 "$(run "$CFG/bin/gate-merge-stack.sh")"
flow 'unit-test\tfail\t1m\thttps://example.invalid/1\n'
t_eq "installed layout, that check red: refused" 1 "$(run "$CFG/bin/gate-merge-stack.sh")"

t_section "the required checks are read once, at preflight: an earlier PR cannot lower the gate for a later one (r5 #4, probe n13) (red-proof)"
lower() { # origin's .agents lists suite and security; #11 drops security from it; #12 then skips security
  ms_world; ms_real_check; optin "$TWO"
  ms_branch f11; printf "$ONE" > "$W/.agents/required-checks.tsv"; wg commit -qam 'drop security'; ms_push f11; ms_pr 11 f11 "chore: drop a required check"
  ms_branch f12; ms_add b.txt two; ms_push f12; ms_pr 12 f12 "feat b"; ms_plan "$PL" 11 12
  printf '%s' "$GH403" > "$MS_FIX/protection.out"; echo 1 > "$MS_FIX/protection.rc"; printf "$BOTH" > "$MS_FIX/checks.tsv"
  # the stub has one check set for every PR: once #11 has merged, security skips
  printf '[ "$MS_PR" != 11 ] || printf "suite\\tpass\\t1m\\thttps://x.invalid/1\\nsecurity\\tskipping\\t0\\thttps://x.invalid/2\\n" > "$MS_FIX/checks.tsv"\n' >> "$T_TMP/merge-into.sh"; }
lower
t_eq "#11 drops security from origin's list and merges, #12 skips security: exit 1" 1 "$(run)"
t_eq "...#11 merged, #12 still open" "MERGED OPEN" "$(cat "$MS_FIX/pr/11.state") $(cat "$MS_FIX/pr/12.state")"
t_has "...refused on the security row held from preflight" "$(OUT)" "security"
ms_mutant "M57 the required checks are re-read before each PR" 's/^    log_head "merge #\$p"; green "\$p"$/    log_head "merge #$p"; green "$p"; checks_snapshot/'
lower; t_eq "M57: #12 merges on the list #11 lowered (probe n13)" "0 MERGED" "$(run "$M/bin/gate-merge-stack.sh") $(cat "$MS_FIX/pr/12.state")"
t_done
