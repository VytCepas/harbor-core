#!/usr/bin/env sh
# gate-approve.sh deploy (harbor#1018, ship contract §4, §5a.4): the default branch must still be the clicked sha, then
# the runner deploys it as `deploy-fleet.sh deploy <repo> --sha <sha> --approved`, under a one-shot token only the
# click writes. Stub gh, and a stub runner that refuses --approved without the token, as the contract asks of it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/gate/approval/fixture.sh"
TOKID="deploy-acme_widgets-cccccccccccc"
runner() { # [exit code] — logs its argv and whether the token was there, consumes it, and refuses --approved without it
  cat > "$GB/deploy-fleet.sh" <<EOF
#!/bin/sh
t="\$CLAUDE_CONFIG_DIR/.helm-approvals/approved/$TOKID"
if [ -f "\$t" ]; then rm -f "\$t"; echo "runner \$* token=yes" >> "\$GF/runner.log"; else echo "runner \$* token=no" >> "\$GF/runner.log"; exit 9; fi
exit ${1:-0}
EOF
}
world() { ag_world; printf 'repo %s\napply sh bin/deploy.sh --apply --live --unattended\n' "$AG_R" > "$GF/contents/.agents/ship.conf"; runner; }

t_section "main still at the clicked sha: the runner deploys it under a one-shot token; ledger and queue record it"
world; ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M" --reason "protected: bin/admission-bash.sh"
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "exit 0" 0 "$RC"
t_eq "the runner, with the contract's exact argv, saw the token" "runner deploy $AG_R --sha $SHA_M --approved token=yes" "$(cat "$GF/runner.log")"
t_eq "no token is left behind" "" "$(ls "$CFG/.helm-approvals/approved" 2>/dev/null)"
t_eq "ledger: deployed" "approve-deploy	$AG_R $SHA_M	deployed" "$(ag_ledger)"
t_eq "the queue row is closed" 0 "$(sh "$GB/gate-queue.sh" list --json 2>/dev/null | jq length)"
ag_mutant "M1 no token is written" gate-approve.sh 's|date -u +%Y-%m-%dT%H:%M:%SZ >"\$TOK"|true|'
rm -f "$GF/runner.log"; ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "M1: without the token the runner refuses --approved" "runner deploy $AG_R --sha $SHA_M --approved token=no" "$(cat "$GF/runner.log")"
t_eq "...and the approval is not recorded as a deploy" "approve-deploy	$AG_R $SHA_M	runner-failed rc=9" "$(ag_ledger | tail -1)"

t_section "an approval covers one commit: main moved, refused"
world; echo "$SHA_B" > "$GF/main.sha"
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "exit 1" 1 "$RC"
t_eq "the runner never ran" "" "$(cat "$GF/runner.log" 2>/dev/null)"
t_has "the new approve command names the new sha" "$OUT" "gate-approve.sh deploy $AG_R $SHA_B"
t_eq "ledger: refused-stale" "approve-deploy	$AG_R $SHA_M	refused-stale main=$SHA_B" "$(ag_ledger)"
ag_mutant "M2 main is not compared" gate-approve.sh 's/if \[ "\$M" != "\$S" \]; then/if false; then/'
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "M2: the mutant deploys a commit nobody clicked" 0 "$RC"

t_section "a failed runner is recorded, leaves the row open, and leaves no token"
world; runner 3; ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M" --reason "protected"
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "exit 1" 1 "$RC"
t_eq "ledger: runner-failed with its code" "approve-deploy	$AG_R $SHA_M	runner-failed rc=3" "$(ag_ledger)"
t_eq "the queue row stays open" 1 "$(sh "$GB/gate-queue.sh" list --json 2>/dev/null | jq length)"
t_eq "no token is left behind" "" "$(ls "$CFG/.helm-approvals/approved" 2>/dev/null)"

t_section "nothing to deploy, or no runner: refused before anything runs"
world; printf 'repo %s\n' "$AG_R" > "$GF/contents/.agents/ship.conf"
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "a manifest with no apply line: exit 1" 1 "$RC"
t_eq "...the runner never ran" "" "$(cat "$GF/runner.log" 2>/dev/null)"
world; rm "$GB/deploy-fleet.sh"
ag_run gate-approve.sh deploy "$AG_R" "$SHA_M"
t_eq "no installed runner: exit 1" 1 "$RC"
t_has "...saying so" "$OUT" "deploy-fleet.sh is not installed"
t_done
