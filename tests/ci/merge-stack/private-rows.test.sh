#!/usr/bin/env sh
# harbor merge-stack reads harbor's required-checks rows composed with the private layer's required-checks.tsv (harbor#1149).
# Core lists nothing for the repo under merge; the repo's own .agents file lists one check; the layer adds the other. Only the
# layer's row can block the PR that dropped that job. Run from a tree whose contracts/ sits beside the tool, and from a git
# checkout whose origin holds core's file. The repo and its checks are made up and name no real entity.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
PL="$T_TMP/plan"; PV="$T_TMP/pv"; mkdir -p "$PV"
run() { HARBOR_SCOPE_PRIVATE="$PV" sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
GH404='gh: Branch not protected (HTTP 404)'
DBT2='unit-test\tpass\t1m\thttps://example.invalid/1\ngrammar-test\tpass\t1m\thttps://example.invalid/2\n'
DBT1='unit-test\tpass\t1m\thttps://example.invalid/1\n'
LAYER='acme/widgets\tunit-test\nacme/widgets\tgrammar-test\n'
# a repo that opts in with its own .agents file listing unit-test, GitHub answering "Branch not protected", core listing nothing for it
world() { # <check rows the PR shows>
  ms_world; ms_real_check; cp "$T_ROOT/bin/gate-required-generate.sh" "$MS_INST/bin/"
  printf '# core: harbor only\nacme/harbor\tgate\n' > "$MS_INST/contracts/required-checks.tsv"
  if [ "${OWN:-1}" = 1 ]; then # OWN=0: the repo declares nothing itself, so the layer's row is the whole local gate
    mkdir -p "$W/.agents"; printf 'acme/widgets\tunit-test\n' > "$W/.agents/required-checks.tsv"; wg add -A; wg commit -q -m optin
    wg push -q origin "$MS_DEF" 2>/dev/null; git -C "$H" pull -q --ff-only 2>/dev/null
  fi
  ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat "feat a"; ms_plan "$PL" 11
  printf '%s' "$GH404" > "$MS_FIX/protection.out"; echo 1 > "$MS_FIX/protection.rc"; printf "$1" > "$MS_FIX/checks.tsv"; }

t_section "a tree whose contracts/ sits beside the tool: the layer's rows are part of harbor's rows"
printf "$LAYER" > "$PV/required-checks.tsv"
world "$DBT2"
t_eq "both jobs green: merges" 0 "$(run)"
t_has "...holding the layer's check for the run" "$(OUT)" "required checks for acme/widgets, fixed for this run: unit-test | grammar-test"
world "$DBT1"
t_eq "the PR dropped the job only the layer requires: refused" 1 "$(run)"
t_has "...naming that check" "$(OUT)" "grammar-test"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
rm -f "$PV/required-checks.tsv"
world "$DBT1"
t_eq "without the layer the repo's own, weaker file merges the same PR" 0 "$(run)"
printf 'acme/widgets grammar-test\n' > "$PV/required-checks.tsv"
world "$DBT2"
t_eq "a layer that does not compose refuses, even for a green PR" 1 "$(run)"
t_has "...naming the layer's file" "$(OUT)" "required-checks.tsv"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
rm -f "$PV/required-checks.tsv"; mkdir -p "$PV/required-checks.tsv"
world "$DBT2"
t_eq "a layer file that exists and is not a file refuses too, never read as no rows" 1 "$(run)"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
rmdir "$PV/required-checks.tsv"

t_section "a repo only the layer names: its row is the whole local gate, and losing the row refuses, never lowers it"
OTHER='other\tpass\t1m\thttps://example.invalid/3\n'
printf 'acme/widgets\tunit-test\n' > "$PV/required-checks.tsv"; OWN=0
world "$DBT1"
t_eq "its one check green: merges" 0 "$(run)"
t_has "...holding the layer's check for the run" "$(OUT)" "required checks for acme/widgets, fixed for this run: unit-test"
world "$OTHER"
t_eq "the PR shows other checks green and not that one: refused" 1 "$(run)"
t_has "...naming the check it lacks" "$(OUT)" "unit-test"
rm -f "$PV/required-checks.tsv"
world "$DBT1"
t_eq "the layer's file gone, the same green PR: refused, the repo has no declared gate" 1 "$(run)"
t_eq "...and the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
printf '# a header and no row\n' > "$PV/required-checks.tsv"
world "$DBT1"
t_eq "the layer's file holding no row: refused too" 1 "$(run)"
M="$T_TMP/mut"; rm -rf "$M"; mkdir -p "$M/bin" "$M/contracts"; cp "$MS_INST"/bin/* "$M/bin/"
cp "$T_ROOT/contracts/merge-stack-union.txt" "$MS_INST/contracts/required-checks.tsv" "$M/contracts/"
sed 's/^elif \[ "\$GATE" != local \] \&\& \[ "\$REQROWS" -eq 0 \]; then$/elif false; then/' "$T_ROOT/bin/gate-merge-check.sh" > "$M/bin/gate-merge-check.sh"
t_exit "M2 merge-check no longer refuses a repo with no declared gate: the mutation applies" 1 cmp -s "$M/bin/gate-merge-check.sh" "$T_ROOT/bin/gate-merge-check.sh"
world "$DBT1"
t_eq "M2: the repo that lost its layer row merges on any green check (red-proof of the refusal above)" 0 "$(run "$M/bin/gate-merge-stack.sh")"
OWN=1

t_section "red-proof: the layer's rows must reach the union"
printf "$LAYER" > "$PV/required-checks.tsv"
ms_mutant "M1 the composer is bypassed" 's#^  if \[ -f "\$HERE/gate-required-generate.sh" \]; then sh .*#  cat "$1"#'
world "$DBT1"
t_eq "M1: the PR that dropped the layer's job merges" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "run from a git checkout: core's file as origin holds it, then the layer's"
HB="$T_TMP/harbor.git"; HC="$T_TMP/hc"
harbor_checkout() { rm -rf "$HB" "$HC"; git init -q --bare "$HB"; git clone -q "$HB" "$HC" 2>/dev/null; mkdir -p "$HC/bin" "$HC/contracts"
  cp "$T_ROOT/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack-resolve.py" "$T_ROOT/bin/gate-merge-check.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/ci-lost-job.sh" "$T_ROOT/bin/gate-required-generate.sh" "$HC/bin/"
  cp "$T_ROOT/contracts/merge-stack-union.txt" "$HC/contracts/"; printf '# core: harbor only\nacme/harbor\tgate\n' > "$HC/contracts/required-checks.tsv"
  git -C "$HC" add -A; git -C "$HC" commit -q -m harbor; git -C "$HC" push -q origin HEAD 2>/dev/null; }
world "$DBT1"; harbor_checkout
t_eq "core lists nothing for the repo, the layer lists grammar-test: the PR that dropped it is refused" 1 "$(run "$HC/bin/gate-merge-stack.sh")"
t_has "...naming that check" "$(OUT)" "grammar-test"
world "$DBT2"; harbor_checkout
t_eq "...and the same PR with both jobs green merges from that checkout" 0 "$(run "$HC/bin/gate-merge-stack.sh")"
printf 'acme/widgets grammar-test\n' > "$PV/required-checks.tsv"
world "$DBT2"; harbor_checkout
t_eq "a layer that does not compose refuses from the checkout too" 1 "$(run "$HC/bin/gate-merge-stack.sh")"
t_eq "...leaving the PR open" OPEN "$(cat "$MS_FIX/pr/11.state")"
t_done
