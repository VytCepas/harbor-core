#!/usr/bin/env sh
# harbor ship, the deploy gates (ship contract v1 §1, §3, §5): a protected change, a repo with no baseline, and a
# manifest with no verify or no restore are queued, never applied unattended. `ship deploy` and its refusals.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
Q="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/bin/gate-approve.sh"
prot_world() { fx_world; fx_base api; fx_main api secrets/key k2; }

t_section "a protected change on main is queued for one click, never applied unattended (red-proof)"
prot_world; S="$(fx_tip api)"
t_eq "exit 0" 0 "$(ship night)"
t_eq "nothing applied" 0 "$(fx_ops apply)"
t_has "the deploy is queued with its approve command" "$(fx_report)" "\`$Q deploy acme/api $S\`"
t_has "...and the protected path" "$(fx_report)" "secrets/key (secrets)"
t_eq "ship deploy without --approved queues too" "0 0" "$(ship deploy acme/api --sha "$S") $(fx_ops apply)"
t_eq "ship deploy --approved lets it through" 0 "$(ship deploy acme/api --sha "$S" --approved)"
t_eq "...applied and verified" "1 1" "$(fx_ops apply) $(fx_ops verify-smoke)"
t_eq "...and it is the new baseline" "$S" "$(fx_state api .sha)"
fx_mutant "MD1 the deploy change is not classified" 's/&& classify "\$ROOTD" "\$RUN\/deploy.paths" ||/\&\& true ||/'
prot_world; ship night >/dev/null
t_eq "the mutant applies the protected change unattended" 1 "$(fx_ops apply)"
SHIP=''

t_section "a repo with no recorded deploy is queued: the first deploy sets the baseline (red-proof)"
fx_world; fx_main api src/z.txt z; S="$(fx_tip api)"
t_eq "exit 0" 0 "$(ship night)"
t_has "queued, saying why" "$(fx_report)" "no deployed commit is recorded yet"
t_eq "nothing applied, no baseline written" "0 " "$(fx_ops apply) $(fx_state api .sha)"
fx_mutant "MD2 a missing baseline falls back to the root commit" \
  's/^  _base="\$(sget "\$DS" .sha)"; /  _base="$(sget "$DS" .sha)"; [ -n "$_base" ] || _base="$(git -C "$_h" rev-list --max-parents=0 HEAD)"; /'
fx_world; fx_main api src/z.txt z; git --git-dir="$T_TMP/remotes/api.git" rev-list --max-parents=0 trunk > "$LIVE/sha"; ship night >/dev/null
t_eq "the mutant applies a repo it has never deployed" 1 "$(fx_ops apply)"
SHIP=''

t_section "a manifest with no restore, or no verify, is never deployed unattended (red-proof)"
cut_world() { fx_world; fx_git api "drop $1" sh -c 'grep -v "^$0 " .agents/ship.conf > m; mv m .agents/ship.conf' "$1"
  fx_base api; fx_main api src/x.txt x; }
cut_world restore
t_eq "no restore: exit 0" 0 "$(ship night)"
t_has "queued: every deploy waits for a click" "$(fx_report)" "the manifest has no verify or no restore"
t_eq "nothing applied" 0 "$(fx_ops apply)"
cut_world verify; ship night >/dev/null
t_eq "no verify: nothing applied either" 0 "$(fx_ops apply)"
fx_mutant "MD3 the manifest's verify and restore are not required" 's/|| _gate="the manifest has no verify/|| _ungated="the manifest has no verify/'
cut_world restore; ship night >/dev/null
t_eq "the mutant deploys a repo it could not undo" 1 "$(fx_ops apply)"
SHIP=''

t_section "a failed plan applies nothing and is a problem; the night goes on to the next repo"
fx_world; fx_base api; fx_main api PLAN_FAILS 1; fx_pr web 21 page.html hi
t_eq "exit 1" 1 "$(ship night)"
t_eq "planned, not applied" "1 0" "$(fx_ops plan) $(fx_ops apply)"
t_has "the problem names the plan's log" "$(fx_report)" "the deploy plan failed (exit 1), nothing applied (log: "
t_eq "the receipt is red over the repo's plan" "red acme/api:plan" "$(jq -r '"\(.status) \(.subjects | join(" "))"' "$CLAUDE_CONFIG_DIR/cache/checks/deploy.fleet.json")"
t_eq "web still merged" "merge web #21 " "$(fx_merged)"
t_eq "the baseline did not move" "$(git --git-dir="$T_TMP/remotes/api.git" rev-parse trunk~1)" "$(fx_state api .sha)"

t_section "ship deploy refuses what it cannot judge"
fx_world; fx_base api; fx_main api src/y.txt y; S="$(fx_tip api)"
t_eq "a sha main is not at: exit 1" 1 "$(ship deploy acme/api --sha 0123456789abcdef --approved)"
t_has "...saying where main is" "$(cat "$T_TMP/out")" "trunk is at $(echo "$S" | cut -c1-12), not 0123456789abcdef"
t_eq "...and nothing applied" 0 "$(fx_ops apply)"
t_eq "a repo outside the fleet: exit 1" 1 "$(ship deploy acme/nope --sha "$S")"
t_eq "a merge-only repo: exit 0, no deploy stage" 0 "$(ship deploy acme/web --sha "$(fx_tip web main)")"
t_has "...said in the report" "$(fx_report)" "acme/web: merge-only"
echo dirty >> "$T_TMP/port/api/health.txt"
t_eq "a dirty main checkout: exit 1" 1 "$(ship deploy acme/api --sha "$S" --approved)"
t_has "...not deployed" "$(fx_report)" "is not a clean trunk checkout; not deployed"
git -C "$T_TMP/port/api" checkout -q health.txt
t_eq "an unprotected change deploys unattended through ship deploy too" "0 1" "$(ship deploy acme/api --sha "$S") $(fx_ops apply)"
t_eq "the deployed sha is recorded" "$S" "$(fx_state api .sha)"
t_eq "deploying it again is a no-op" "0 1" "$(ship deploy acme/api --sha "$S") $(fx_ops apply)"

t_section "the kill switch read between plan and apply (red-proof)"
fx_world; fx_base api; fx_main api src/k.txt k; touch "$SF/kill-in-plan"
t_eq "the switch turned on during plan: exit 0" "0 1 0" "$(ship night) $(fx_ops plan) $(fx_ops apply)"
fx_mutant "MK no kill-switch read before apply" 's/^  \[ "\$_ap" = 1 \] || ! kill_stop || return 0$/  :/'
fx_world; fx_base api; fx_main api src/k.txt k; touch "$SF/kill-in-plan"; ship night >/dev/null
t_eq "the mutant applies under the switch" 1 "$(fx_ops apply)"
SHIP=''

t_section "a recorded commit that is not an ancestor of the default branch is queued (red-proof)"
side_world() { fx_world; W="$T_TMP/seed/api"; git -C "$W" checkout -q -B side2 origin/trunk; echo s > "$W/src/side.txt"
  git -C "$W" add -A; git -C "$W" commit -q -m side; git -C "$W" push -q origin side2 2>/dev/null
  git -C "$T_TMP/port/api" fetch -q origin side2; fx_base api "$(fx_tip api side2)"; fx_main api src/q.txt q; }
side_world
t_eq "exit 0, nothing applied" "0 0" "$(ship night) $(fx_ops apply)"
t_has "queued, saying why" "$(fx_report)" "is not an ancestor of trunk"
fx_mutant "MA no ancestor check" 's/if \[ -z "\$_gate" \] && ! git -C "\$_h" merge-base --is-ancestor "\$_base" "\$_sha" 2>\/dev\/null; then/if false; then/'
side_world; ship night >/dev/null
t_eq "the mutant applies over a history it never deployed" 1 "$(fx_ops apply)"
SHIP=''

t_section "--approved is refused when SHIP_UNATTENDED=1 (§5a.4) (red-proof)"
fx_world; fx_base api; fx_main api secrets/key k; S="$(fx_tip api)"
t_eq "exit 2, nothing applied" "2 0" "$(SHIP_UNATTENDED=1 ship deploy acme/api --sha "$S" --approved) $(fx_ops apply)"
t_has "...saying who may pass it" "$(cat "$T_TMP/out")" "only gate-approve.sh passes it"
fx_mutant "MU --approved accepted unattended" 's/^\[ "\$APPROVED" = 0 \] || \[ "\${SHIP_UNATTENDED:-}" != 1 \] || usage_err/: || usage_err/'
fx_world; fx_base api; fx_main api secrets/key k; ( SHIP_UNATTENDED=1; export SHIP_UNATTENDED; ship deploy acme/api --sha "$(fx_tip api)" --approved >/dev/null )
t_eq "the mutant applies a protected change in an unattended run" 1 "$(fx_ops apply)"
SHIP=''

t_section "the default branch is read from origin, never assumed to be main (red-proof)"
fx_world; fx_base api; fx_main api src/d.txt d
t_eq "api's default branch is trunk, and it deploys" "0 1" "$(ship night) $(fx_ops apply)"
fx_mutant "MDB the default branch is hard-coded" 's/^  git -C "\$1" ls-remote --symref origin HEAD .*$/  echo main/'
fx_world; fx_base api; fx_main api src/d.txt d; ship night >/dev/null
t_eq "the mutant cannot deploy a trunk repo" 0 "$(fx_ops apply)"
SHIP=''
t_section "--approved needs gate-approve.sh's one-shot token, and consumes it (red-proof)"
fx_world; fx_base api; fx_main api secrets/key k; S="$(fx_tip api)"; TOK="$(fx_sdir)/../.helm-approvals/approved/deploy-acme_api-$(echo "$S" | cut -c1-12)"
t_eq "no token: exit 2, nothing applied" "2 0" "$(FX_NO_TOKEN=1 ship deploy acme/api --sha "$S" --approved) $(fx_ops apply)"
t_has "...naming the token" "$(cat "$T_TMP/out")" "--approved without the approval token"
t_eq "with the token: deployed" "0 1" "$(ship deploy acme/api --sha "$S" --approved) $(fx_ops apply)"
t_eq "...and the token is spent" gone "$([ -e "$TOK" ] && echo left || echo gone)"
fx_mutant "MTK --approved without a token" 's/^  \[ -f "\$TOKEN" \] || {/  true || {/'
fx_world; fx_base api; fx_main api secrets/key k; ( FX_NO_TOKEN=1 ship deploy acme/api --sha "$(fx_tip api)" --approved >/dev/null )
t_eq "the mutant applies a protected change no click approved" 1 "$(fx_ops apply)"
SHIP=''

t_section "the deployed-sha state lives in the guarded config dir and carries a checksum (red-proof)"
tamper_world() { fx_world; fx_base api; fx_main api secrets/key k; T1="$(fx_tip api)"; F="$(fx_sdir)/acme_api.json"
  jq --arg s "$T1" '.sha = $s' "$F" > "$F.t" && mv "$F.t" "$F"; printf '%s\n' "$T1" > "$LIVE/sha"; }
tamper_world
t_eq "a hand-moved baseline (live agreeing): exit 1" 1 "$(ship night)"
t_has "the protected change is queued, not taken as deployed" "$(fx_report)" "the deployed-sha state fails its checksum"
t_eq "...one queue row" 1 "$(fx_queue | grep -c .)"
t_eq "nothing applied" 0 "$(fx_ops apply)"
fx_mutant "MSUM the checksum is not verified" 's/^  \[ "\$(jq -r .\.sum \/\/ empty. "\$_sf" 2>\/dev\/null)" = "\$(ssum "\$_sf")" \]$/  true/'
tamper_world; ship night >/dev/null
t_eq "the mutant takes the protected change as deployed: nothing queued" 0 "$(fx_queue | grep -c .)"
SHIP=''

t_section "a restore outside the runner: the live install disagrees, so the baseline is not trusted (red-proof)"
manual_world() { fx_world; fx_base api; fx_main api secrets/key k; ship deploy acme/api --sha "$(fx_tip api)" --approved >/dev/null
  ( cd "$T_TMP/port/api" && SHIP_SNAPSHOT_ID=snap-1 sh ops/deploy-restore.sh ); fx_main api src/u.txt u; }
manual_world
t_eq "the approved protected deploy, then a manual restore" "snap-1 $(git --git-dir="$T_TMP/remotes/api.git" rev-parse trunk~1)" "$(fx_state api .snapshot) $(fx_state api .sha)"
t_eq "the next night: exit 0, nothing applied" "0 1" "$(ship night) $(fx_ops apply)"
t_has "queued: the live install is not the recorded sha" "$(fx_report)" "not the recorded $(git --git-dir="$T_TMP/remotes/api.git" rev-parse trunk~1 | cut -c1-12): changed outside the runner"
fx_mutant "MLIVE the live install is not read" 's/^  if \[ -n "\$_base" \] && \[ -n "\$_dcmd" \]; then$/  if false; then/'
manual_world; ship night >/dev/null
t_eq "the mutant re-applies the undone protected change unattended" 2 "$(fx_ops apply)"
SHIP=''
t_done
