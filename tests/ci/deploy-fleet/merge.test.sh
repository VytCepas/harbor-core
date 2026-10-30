#!/usr/bin/env sh
# harbor ship, the merge stage (ship contract v1 §3, §5): a red PR is never merged, a protected one is queued, the
# kill switch stops the run, and the classifier sees a rename's two paths and a deletion. Each rail has a mutant.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
KILL="$CLAUDE_CONFIG_DIR/.harbor-autoship.off"; KILLP="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/.harbor-autoship.off"
red_world() { fx_world; fx_base api; fx_pr web 21 page.html hi; fx_pr web 22 broken.html no; fx_red web 22; }

t_section "a red PR is skipped and reported, never handed to merge-stack (red-proof)"
red_world
t_eq "exit 0" 0 "$(ship night)"
t_eq "only the green PR merged" "merge web #21 " "$(fx_merged)"
t_has "#22 is under skipped red" "$(fx_report)" "acme/web #22 — #22 last CI run red: 777"
t_hasnt "the runner never started a merge of #22" "$(cat "$T_TMP/out")" "merge acme/web #22"
fx_mutant "MR1 the runner ignores merge-stack check" 's/\[ "\$_crc" = 0 \] || {/true || {/'
red_world
ship night >/dev/null
t_has "the mutant hands the red PR to merge-stack" "$(cat "$T_TMP/out")" "merge acme/web #22"
t_hasnt "...and no longer reports it as skipped red" "$(fx_report)" "Skipped red"
SHIP=''

t_section "the red gate itself is merge-stack's report, which the runner calls: removing it merges a red PR (red-proof)"
fx_mutant "runner intact" 's/^NIGHT=57600 /NIGHT=57600/'
sed -i.bak 's/^report() {$/report() { return 0/' "$M/bin/gate-merge-stack.sh"
t_exit "merge-stack's report is off" 1 cmp -s "$M/bin/gate-merge-stack.sh" "$T_ROOT/bin/gate-merge-stack.sh"
red_world; ship night >/dev/null
t_has "the red PR merges: the rail is end to end, through merge-stack" "$(fx_merged)" "merge web #22"
SHIP=''

t_section "a protected PR is queued through gate-queue.sh, never merged unattended (red-proof)"
fx_world; fx_base api; fx_pr api 12 secrets/key hunter2
t_eq "exit 0" 0 "$(ship night)"
t_eq "nothing merged" "" "$(fx_merged)"
t_eq "one queue row, kind merge" "merge" "$(fx_queue | jq -r .kind)"
t_eq "gate-queue.sh was the writer, with the contract's id" "merge-acme_api-12-$(fx_tip api pr-12 | cut -c1-12)" "$(fx_queue | jq -r .id)"
t_eq "...and the reason" "protected: secrets/key (secrets)" "$(fx_queue | jq -r .reason)"
t_eq "a second night does not queue it twice" "0 1" "$(ship night) $(fx_queue | grep -c .)"
fx_mutant "MR2 the runner ignores the classifier" 's/classify "\$ROOTD" "\$RUN\/\$_f-\$_n.paths" || {/true || {/'
fx_world; fx_base api; fx_pr api 12 secrets/key hunter2
ship night >/dev/null
t_eq "the mutant merges the protected PR" "merge api #12 " "$(fx_merged)"
SHIP=''

t_section "the classifier sees a rename's old and new paths and a deletion; a classifier that cannot answer protects"
fx_world; fx_main api secrets/old x; fx_main api secrets/gone y; fx_base api
W="$T_TMP/seed/api"; git -C "$W" checkout -q -B pr-14 origin/trunk; git -C "$W" mv secrets/old src/old; git -C "$W" commit -q -m mv
git -C "$W" push -q origin pr-14 2>/dev/null
git --git-dir="$T_TMP/remotes/api.git" update-ref refs/pull/14/head "$(fx_tip api pr-14)"
D="$SF/gh/acme_api/pr"; echo pr-14 > "$D/14.branch"; echo OPEN > "$D/14.state"; echo mv > "$D/14.title"; echo ship:auto > "$D/14.labels"
git -C "$W" checkout -q -B pr-15 origin/trunk; git -C "$W" rm -q secrets/gone; git -C "$W" commit -q -m rm; git -C "$W" push -q origin pr-15 2>/dev/null
git --git-dir="$T_TMP/remotes/api.git" update-ref refs/pull/15/head "$(fx_tip api pr-15)"
echo pr-15 > "$D/15.branch"; echo OPEN > "$D/15.state"; echo rm > "$D/15.title"; echo ship:auto > "$D/15.labels"
ship night >/dev/null
t_has "the rename's old path was classified" "$(cat "$SF/classify.seen")" "secrets/old"
t_has "...and its new one" "$(cat "$SF/classify.seen")" "src/old"
t_has "the deletion's path was classified" "$(cat "$SF/classify.seen")" "secrets/gone"
t_eq "both are queued, neither merged" "2 " "$(fx_queue | grep -c .) $(fx_merged)"
fx_world; fx_base api; fx_pr api 16 src/c.txt c; rm "$CLAUDE_CONFIG_DIR/bin/gate-classify.sh"
ship night >/dev/null
t_has "no classifier: queued, not merged" "$(fx_report)" "no classifier at $(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/bin/gate-classify.sh"
t_eq "...nothing merged" "" "$(fx_merged)"
fx_world; fx_base api; fx_pr api 17 'src/we"ird.txt' w
ship night >/dev/null
t_has "a path git has to quote is protected" "$(fx_report)" "a path git had to quote"

t_section "the head that merges is the head that was classified: a push after it waits a night (red-proof)"
fx_world; fx_pr web 21 page.html hi; H21="$(fx_tip web pr-21)"; echo "web pr-21 21" > "$SF/push-after-classify"
t_eq "exit 0" 0 "$(ship night)"
t_has "the plan pins the classified head" "$(cat "$HOME"/.local/state/harbor/ship/backups/deploy-fleet/*/acme_web-21.plan)" "pr 21 head $H21"
t_eq "every pin the runner wrote is a full 40-hex sha" "" "$(cat "$HOME"/.local/state/harbor/ship/backups/deploy-fleet/*/*.plan | awk '$1 == "pr" && $3 == "head" && (length($4) != 40 || $4 ~ /[^0-9a-f]/)')"
t_eq "the moved head is not merged" "" "$(fx_merged)"
t_eq "...main never got the secret" "" "$(git --git-dir="$T_TMP/remotes/web.git" show main:secrets/key 2>/dev/null)"
t_has "it waits for the next night, to be classified again" "$(fx_report)" "acme/web #21 needs a rebase onto main: left for the next night"
fx_mutant "MP2 an abbreviated pin" 's/pr %s head %s\\n'"'"' "\$_s" "\$_h" "\$_n" "\$_hd"/pr %s head %.12s\\n'"'"' "$_s" "$_h" "$_n" "$_hd"/'
fx_world; fx_pr web 21 page.html hi; ship night >/dev/null
t_has "the 40-hex assertion sees the mutant's short pin" "$(cat "$HOME"/.local/state/harbor/ship/backups/deploy-fleet/*/*.plan | awk '$1 == "pr" && $3 == "head" && (length($4) != 40 || $4 ~ /[^0-9a-f]/)')" "pr 21 head"
SHIP=''
fx_mutant "MP1 the plan carries no head pin" 's/pr %s head %s\\n'"'"' "\$_s" "\$_h" "\$_n" "\$_hd"/pr %s\\n'"'"' "$_s" "$_h" "$_n"/'
fx_world; fx_pr web 21 page.html hi; echo "web pr-21 21" > "$SF/push-after-classify"; ship night >/dev/null
t_eq "the mutant merges a head nobody classified" "merge web #21 " "$(fx_merged)"
SHIP=''

t_section "a fetched head that is not the head GitHub reports is not judged (red-proof)"
fx_world; fx_pr web 21 page.html hi; fx_pr web 25 other.html o
fx_tip web pr-25 > "$SF/gh/acme_web/pr/21.reported"
t_eq "exit 1: a problem" 1 "$(ship night)"
t_has "...named" "$(fx_report)" "acme/web #21: the fetched head is not the head GitHub reports"
t_eq "#21 not merged" "merge web #25 " "$(fx_merged)"
fx_mutant "MC the fetched head is not compared" 's/\[ -n "\$_hd" \] && \[ "\$(git -C "\$_h" rev-parse FETCH_HEAD)" = "\$_hd" \]/true/'
fx_world; fx_pr web 21 page.html hi; fx_pr web 25 other.html o; fx_tip web pr-25 > "$SF/gh/acme_web/pr/21.reported"; ship night >/dev/null
t_hasnt "the mutant goes on to judge #21" "$(cat "$T_TMP/out")" "is not the head GitHub reports"
SHIP=''

t_section "opt-in and the register are read from origin's default branch, never the working tree (red-proof, review P7 and P8)"
fx_world; fx_git web "opt out" git rm -q .agents/ship.conf; fx_pr web 21 page.html hi
t_eq "manifest deleted on origin main, still in the checkout: exit 0" 0 "$(ship night)"
t_eq "...and its ship:auto PR is not merged" "" "$(fx_merged)"
t_has "the checkout still carries the stale manifest" "$(cat "$T_TMP/port/web/.agents/ship.conf")" "repo acme/web"
fx_mutant "MO opt-in read from the working tree" 's|git -C "\$1" show "\$2:.agents/ship.conf" > "\$_rd/.agents/ship.conf"|cp "$1/.agents/ship.conf" "$_rd/.agents/ship.conf"|'
fx_world; fx_git web "opt out" git rm -q .agents/ship.conf; fx_pr web 21 page.html hi; ship night >/dev/null
t_eq "the mutant merges a repo that opted out" "merge web #21 " "$(fx_merged)"
SHIP=''
reg_world() { fx_world; fx_git web "protect docs" sh -c 'printf "docs/*\tdocs\treview\n" >> .agents/protected-paths.tsv'; fx_pr web 22 docs/x.md d; }
reg_world
t_eq "main's register gained docs/*: exit 0" 0 "$(ship night)"
t_eq "...a PR touching docs/x.md is queued, not merged" "" "$(fx_merged)"
t_has "...protected by main's register" "$(fx_report)" "docs/x.md (docs)"
fx_mutant "MR the register read from the working tree" 's|git -C "\$1" show "\$2:\$_rg" > "\$_rd/\$_rg"|cp "$1/$_rg" "$_rd/$_rg"|'
reg_world; ship night >/dev/null
t_eq "the mutant merges it on the checkout's stale register" "merge web #22 " "$(fx_merged)"
SHIP=''

t_section "the kill switch stops the run before and between steps (red-proof)"
fx_world; fx_base api; fx_pr web 21 page.html hi; touch "$KILL"
t_eq "exit 0: a switch is not a failure" 0 "$(ship night)"
t_eq "nothing merged" "" "$(fx_merged)"
t_has "the report says why" "$(fx_report)" "stopped: the kill switch $KILLP is on"
t_eq "the receipt stands down" stood-down "$(jq -r .status "$CLAUDE_CONFIG_DIR/cache/checks/deploy.fleet.json")"
t_has "checks.log says so" "$(cat "$T_TMP/cache/checks.log")" "[check:deploy.fleet] 2026-10-06T23:00:00Z stood-down night"
fx_world; fx_base api; fx_pr web 21 page.html hi; fx_pr web 22 more.html m; fx_pr api 11 src/a.txt a; touch "$SF/kill-after-merge"
ship night >/dev/null
t_eq "switched on after the first merge: the second PR and the next repo wait" "merge api #11 " "$(fx_merged)"
t_eq "...and nothing was applied" 0 "$(fx_ops apply)"
fx_mutant "MR3 the kill switch is not read" 's/^killed() { \[ -e "\$KILL" \]; }/killed() { false; }/'
fx_world; fx_base api; fx_pr web 21 page.html hi; touch "$KILL"
ship night >/dev/null
t_eq "the mutant merges under the switch" "merge web #21 " "$(fx_merged)"
t_done
