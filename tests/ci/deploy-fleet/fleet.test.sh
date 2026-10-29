#!/usr/bin/env sh
# harbor ship (harbor#1060, #1018), ship contract v1: two different fake repos, one deploy-capable and one merge-only,
# run end to end over two nights and one approved deploy. The runner names no repo of its own (a grep, red-proofed).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
Q="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/bin/gate-approve.sh"

t_section "night 1: green PRs merge, a red one is skipped, a protected one is queued, the first deploy waits"
fx_world
fx_pr api 11 src/a.txt alpha; fx_pr api 12 secrets/key hunter2
fx_pr web 21 page.html hi; fx_pr web 22 broken.html no; fx_red web 22; fx_pr web 23 draft.html wip none
H12="$(fx_tip api pr-12)"
t_eq "exit 0: nothing failed" 0 "$(ship night)"
t_eq "api #11 and web #21 merged, nothing else" "merge api #11 merge web #21 " "$(fx_merged)"
t_has "api trunk holds #11" "$(git --git-dir="$T_TMP/remotes/api.git" log --format=%s -1 trunk)" "(#11)"
R="$(fx_report)"
t_has "the report lists the merges" "$R" "acme/api #11 PR 11 on api"
t_has "...and web's" "$R" "acme/web #21"
t_has "the red PR is under skipped red, with merge-stack's reason" "$R" "acme/web #22 — #22 last CI run red"
t_hasnt "the unlabelled PR is not touched" "$R" "#23"
t_has "the protected PR is queued with its exact approve command" "$R" "\`$Q merge acme/api 12 $H12\`"
t_has "...and why: the classifier's verdict" "$R" "secrets/key (secrets)"
M1="$(fx_tip api)"
t_has "api's first deploy is queued: no baseline" "$R" "\`$Q deploy acme/api $M1\`"
t_has "web is merge-only: no deploy stage" "$R" "acme/web: merge-only"
t_eq "nothing was applied" 0 "$(fx_ops apply)"
t_eq "two rows in the approvals queue" 2 "$(fx_queue | grep -c .)"
t_eq "the merge row carries the contract's fields" "merge acme/api 12 $H12" "$(fx_queue | jq -r 'select(.kind == "merge") | "\(.kind) \(.repo) \(.pr) \(.sha)"')"
t_eq "the deploy row has no pr" "null" "$(fx_queue | jq -r 'select(.kind == "deploy") | .pr')"
t_eq "the queue ids are the contract's (§5a.2)" "deploy-acme_api-$(echo "$M1" | cut -c1-12) merge-acme_api-12-$(echo "$H12" | cut -c1-12)" "$(fx_queue | jq -r .id | sort | tr '\n' ' ' | sed 's/ $//')"
t_has "...and the report names each one" "$R" "(queue id merge-acme_api-12-$(echo "$H12" | cut -c1-12))"
t_has "one [check:ship] line, green" "$(cat "$T_TMP/cache/checks.log")" "[check:ship] 2026-10-06T23:00:00Z green night: merged 2, deployed 0"
t_eq "the receipt is green" green "$(jq -r .status "$CLAUDE_CONFIG_DIR/cache/checks/ship.json")"
t_has "api ran from its main checkout, on its default branch" "$(cat "$T_TMP/out")" "acme/api ($T_TMP/port/api, trunk)"
t_hasnt "...never the linked worktree" "$(cat "$T_TMP/out")" ".wt-api"

t_section "ship deploy: unapproved it queues again; approved it plans, applies, verifies and sets the baseline"
t_eq "unapproved: exit 0" 0 "$(ship deploy acme/api --sha "$M1")"
t_eq "...queued once, not applied" 2 "$(fx_queue | grep -c .)"
t_eq "...no apply" 0 "$(fx_ops apply)"
t_eq "approved: exit 0" 0 "$(ship deploy acme/api --sha "$M1" --approved)"
t_eq "plan ran unattended, with the repo" 1 "$(grep -c "unattended=1 repo=acme/api" "$SF/ops.log")"
t_eq "applied once, then both verify lines" "1 1 1" "$(fx_ops apply) $(fx_ops verify-health) $(fx_ops verify-smoke)"
t_eq "the baseline is main" "$M1" "$(fx_state api .sha)"
t_eq "...with this run's snapshot" snap-1 "$(fx_state api .snapshot)"
t_has "the report's deployed line says approved" "$(fx_report)" "acme/api $(echo "$M1" | cut -c1-12) (snapshot snap-1) — approved"

t_section "night 2: a new PR merges and deploys unattended, base..head"
fx_later 86400
fx_pr api 13 src/b.txt beta
t_eq "exit 0" 0 "$(ship night)"
M2="$(fx_tip api)"
t_has "#13 merged" "$(fx_merged)" "merge api #13"
t_eq "applied once more" 2 "$(fx_ops apply)"
t_eq "the baseline moved to the new main" "$M2" "$(fx_state api .sha)"
t_has "the report shows the range" "$(fx_report)" "acme/api $(echo "$M1" | cut -c1-12)..$(echo "$M2" | cut -c1-12) (snapshot snap-2)"
t_hasnt "the protected #12 stays queued, not merged" "$(fx_merged)" "#12"
t_eq "the queue did not grow: #12 was already queued" 2 "$(fx_queue | grep -c .)"
t_eq "a third night with nothing new applies nothing" "0 2" "$(ship night) $(fx_ops apply)"

t_section "named repos and plans narrow the run"
fx_pr web 24 more.html m
t_eq "ship night acme/api leaves web alone" 0 "$(ship night acme/api)"
t_hasnt "web #24 not merged" "$(fx_merged)" "#24"
printf 'repo acme/web\ncheckout %s\npr 24\nafter 24 echo run-me-once\n' "$T_TMP/port/web" > "$T_TMP/plan"
t_eq "--plan merges the plan's PR" 0 "$(ship night --plan "$T_TMP/plan")"
t_has "...#24" "$(fx_merged)" "merge web #24"
t_has "...and merge-stack printed the after line" "$(cat "$T_TMP/out" "$HOME"/.local/state/harbor/ship/backups/deploy-fleet/*/acme_web-24.plan.merge)" "run once now: echo run-me-once"
t_eq "an unknown repo is a problem, exit 1" 1 "$(ship night acme/nope)"

t_section "a linked worktree is never the checkout, even when it carries the repo's name (red-proof)"
wt_world() { fx_world; P="$T_TMP/port"; git clone -q https://github.com/acme/api.git "$P/api-main" 2>/dev/null
  mkdir -p "$T_TMP/wt"; git -C "$P/api-main" worktree add -q "$T_TMP/wt/api" -b wt-side 2>/dev/null
  fx_snap "$T_TMP/wt/api" "$P/api-main" "$P/web"; fx_base api; fx_main api src/w.txt w; }
wt_world
t_eq "exit 0, applied once" "0 1" "$(ship night) $(fx_ops apply)"
t_has "from the main checkout" "$(cat "$SF/ops.log")" "dir=$T_TMP/port/api-main"
fx_mutant "ME linked worktrees counted" 's/^    \[ "\$_gd" = "\$(git -C "\$_p" rev-parse --git-common-dir 2>\/dev\/null)" \] || continue$/    :/'
wt_world; ship night >/dev/null
t_has "the mutant picks the worktree named api" "$(cat "$T_TMP/out")" "acme/api ($T_TMP/wt/api, trunk)"
SHIP=''

t_section "universal: the runner names no repo, tool or register of its own (red-proof)"
names() { sed '/^[[:space:]]*#/d' "$1" | sed -E 's/HARBOR_[A-Z_]+//g; s#\.local/state/harbor#STATE#g; s#\.harbor-autoship\.off#KILL#g; s/harbor ship/VERB/g' \
  | grep -inE 'harbor|vytcepas|deploy\.sh|deploy-restore\.sh|floor-verify|live-verify|reference-check|contracts/' || true; }
t_eq "no harbor-specific name in a code line" "" "$(names "$T_ROOT/bin/deploy-fleet.sh")"
sed 's|^usage() {|usage() { : sh bin/deploy.sh --apply --live|' "$T_ROOT/bin/deploy-fleet.sh" > "$T_TMP/named"
t_has "the grep sees a harbor deploy line slipped in" "$(names "$T_TMP/named")" "deploy.sh"

t_section "harbor ship reaches it"
t_has "the dispatcher prints the usage" "$(sh "$T_ROOT/bin/harbor" ship --help 2>&1)" "usage: harbor ship night"
t_exit "a usage error is exit 2 through the verb" 2 sh "$T_ROOT/bin/harbor" ship deploy acme/api
t_exit "--approved belongs to deploy" 2 sh "$T_ROOT/bin/deploy-fleet.sh" night --approved
t_exit "a sha that is not hex" 2 sh "$T_ROOT/bin/deploy-fleet.sh" deploy acme/api --sha 'abc;rm'
t_done
