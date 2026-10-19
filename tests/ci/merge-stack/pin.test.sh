#!/usr/bin/env sh
# harbor merge-stack head pinning (harbor#1060, ship contract 5b.10): a pinned PR is merged only on the head that was
# classified, and never synced; every merge is pinned to the head whose CI was judged (--match-head-commit). Mutants must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/merge-stack/fixture.sh"
PL="$T_TMP/plan"
run() { sh "${1:-$GMS}" merge "$PL" >"$T_TMP/out" 2>&1; echo $?; }
OUT() { cat "$T_TMP/out"; }
one() { ms_world harbor; ms_branch feat; ms_add a.txt one; ms_push feat; ms_pr 11 feat "feat"; HEAD1="$(ms_tip feat)"; }
# a push that lands the moment the PR's run has been watched: after green, before the merge
late_push() {
  { printf 'git -C "%s" checkout -q feat\necho late > "%s/late.txt"\ngit -C "%s" add -A\n' "$W" "$W" "$W"
    printf 'git -C "%s" commit -q -m late\ngit -C "%s" push -q --force origin feat\n' "$W" "$W"; } > "$MS_FIX/after-watch"
}
on_main() { git --git-dir="$MS_BARE" show "main:$1" 2>/dev/null; }
pin() { sed -i.b "s/^pr 11\$/pr 11 $1/" "$PL"; }

t_section "every merge is pinned to the head whose CI was judged"
one; ms_plan "$PL" 11
t_eq "exit 0" 0 "$(run)"
t_eq "merge-check was told the judged head" "--squash --merge 11 --match-head-commit $HEAD1" "$(cat "$MS_FIX/args.log")"
t_eq "...and told the default branch, the repo and its (empty) required-checks list" "repo=acme/widgets rc=/ br=main" "$(sed 's#rc=/[^ ]*#rc=/#' "$MS_FIX/env.log")"

t_section "a push between judging and merging cannot land (red-proof)"
one; ms_plan "$PL" 11; late_push
t_eq "the merge is refused: exit 1" 1 "$(run)"
t_eq "the PR is still open" OPEN "$(cat "$MS_FIX/pr/11.state")"
t_eq "the late commit is not on the default branch" "" "$(on_main late.txt)"
t_eq "...and the first head was the one judged" "--squash --merge 11 --match-head-commit $HEAD1" "$(cat "$MS_FIX/args.log")"
ms_mutant "M18 merge without --match-head-commit" 's/ --match-head-commit "\$JUDGED" )/ )/'
one; ms_plan "$PL" 11; late_push
run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant merges the NEW head" late "$(on_main late.txt)"

t_section "a pinned PR on its pinned head merges; on any other head it is needs-rebase and nothing else"
one; ms_plan "$PL" 11; pin "head $HEAD1"
t_eq "the pin matches: exit 0" 0 "$(run)"
t_eq "...merged on exactly that head" "--squash --merge 11 --match-head-commit $HEAD1" "$(cat "$MS_FIX/args.log")"
one; ms_add b.txt two; ms_push feat; ms_plan "$PL" 11; pin "head $HEAD1"
t_eq "a head that moved since the pin: exit 3, not 1" 3 "$(run)"
t_has "it says needs-rebase and names both heads" "$(OUT)" "needs-rebase #11: its head is $(ms_tip feat), the plan pins $HEAD1"
t_eq "nothing was merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
t_eq "check reports it too, exit 3" 3 "$(sh "$GMS" check "$PL" >"$T_TMP/out" 2>&1; echo $?)"
ms_mutant "M19 a pin is not checked" 's/^    if \[ -n "\$_pin" \] \&\& ! head_is .*$/    true/;s/^    if \[ -n "\$_pin" \] \&\& \[ "\$JUDGED" != .*$/    true/'
t_eq "the mutant merges the moved head" 0 "$(run "$M/bin/gate-merge-stack.sh")"

t_section "a pinned PR is never synced, even when it conflicts (red-proof)"
conf() { ms_world harbor; ms_branch feat; ms_add CONTRACTS/suites.txt tests/p/pr.test.sh; ms_push feat; ms_pr 11 feat; HEAD1="$(ms_tip feat)"
  ms_main CONTRACTS/suites.txt tests/m/main.test.sh; ms_plan "$PL" 11; pin "head $HEAD1"; }
conf
t_eq "the merge fails on the conflict: exit 1" 1 "$(run)"
t_eq "the PR branch was not rebased or pushed" "$HEAD1" "$(ms_tip feat)"
t_eq "...and no rebase was announced" "" "$(OUT | grep 'rebase #11')"
ms_mutant "M20 a pinned PR is synced" 's/\[ -n "\$_pin" \] || sync "\$p"/sync "$p"/'
conf; run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant rebased and pushed it" no "$([ "$(ms_tip feat)" = "$HEAD1" ] && echo yes || echo no)"

t_section "a push between the pin check and the judge is caught by the judged head (red-proof)"
read_race() { one; ms_plan "$PL" 11; pin "head $HEAD1"
  { printf 'git -C "%s" checkout -q feat\necho late > "%s/late.txt"\ngit -C "%s" add -A\n' "$W" "$W" "$W"
    printf 'git -C "%s" commit -q -m late\ngit -C "%s" push -q --force origin feat\ntouch "%s/hook-ran"\n' "$W" "$W" "$MS_FIX"; } > "$MS_FIX/after-read"
  echo 3 > "$MS_FIX/after-read-n"; }
read_race
t_eq "exit 3: needs-rebase" 3 "$(run)"
t_eq "the push did land between the reads" yes "$([ -e "$MS_FIX/hook-ran" ] && echo yes || echo no)"
t_eq "nothing was merged" "" "$(cat "$MS_FIX/merge.log" 2>/dev/null)"
ms_mutant "MA the judged head is not compared with the pin" 's/^    if \[ -n "\$_pin" \] \&\& \[ "\$JUDGED" != "\$_pin" \]; then .*$/    true/'
read_race; run "$M/bin/gate-merge-stack.sh" >/dev/null
t_eq "the mutant merges the unclassified head" late "$(on_main late.txt)"

t_section "the plan format: pins are validated, an unpinned line is unchanged"
one; ms_plan "$PL" 11; pin "head zzzzzzz"; t_eq "a pin that is not hex: exit 2" 2 "$(run)"
ms_plan "$PL" 11; pin "head abc"; t_eq "a pin that is too short: exit 2" 2 "$(run)"
ms_plan "$PL" 11; pin "sha abc1234"; t_eq "an unknown field: exit 2" 2 "$(run)"
ms_plan "$PL" 11; pin "head $(printf '%s' "$HEAD1" | cut -c1-7)"; t_eq "a 7-hex pin is refused: a prefix can be forged into another commit" 2 "$(run)"
ms_plan "$PL" 11; pin "head $(printf '%s' "$HEAD1" | cut -c1-39)"; t_eq "a prefix of the real head is refused too" 2 "$(run)"
ms_plan "$PL" 11; pin "head $(printf '%s' "$HEAD1" | tr 'a-f0-9' 'A-F0-9')"; t_eq "an upper-case 40-hex pin is refused (gh reports lower case)" 2 "$(run)"
ms_plan "$PL" 11; pin "head ${HEAD1%?}$([ "${HEAD1#"${HEAD1%?}"}" = 0 ] && echo 1 || echo 0)"; t_eq "a full pin that is not the head is needs-rebase, compared with =" 3 "$(run)"
ms_mutant "M24 a short pin is accepted" 's/length(\$3) == 40/length($3) >= 7/'
ms_plan "$PL" 11; pin "head $(printf '%s' "$HEAD1" | cut -c1-7)"
t_eq "the mutant lets the short pin through (exit is no longer 2)" yes "$([ "$(run "$M/bin/gate-merge-stack.sh")" != 2 ] && echo yes || echo no)"
t_done
