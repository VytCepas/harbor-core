#!/usr/bin/env sh
# harbor ship, bounded commands (ship contract v1.1 §5a.5): a hung verify times out as red and is restored, and a TERM
# during apply or verify kills the command's process group, restores this run's snapshot and reports, within seconds.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
hang_world() { fx_world; fx_base api; fx_main api src/h.txt h; touch "$SF/verify-hangs"; }
gone() { [ -s "$SF/verify.pid" ] && ! kill -0 "$(cat "$SF/verify.pid")" 2>/dev/null && echo gone || echo alive; }
reap() { [ ! -s "$SF/verify.pid" ] || kill -9 "$(cat "$SF/verify.pid")" 2>/dev/null || :; }
started() { _i=0; until [ -s "$SF/verify.pid" ] || [ "$_i" -ge 150 ]; do /bin/sleep 0.1; _i=$((_i + 1)); done; }

t_section "a hung verify times out (timeout.verify 3), counts as red, and is restored"
hang_world; T0="$(date +%s)"
t_eq "exit 1" 1 "$(ship night)"
t_eq "...within seconds, not the sleep's 600" yes "$([ $(($(date +%s) - T0)) -lt 40 ] && echo yes || echo no)"
t_eq "the sleep's process group was killed" gone "$(gone)"
t_has "the report says it timed out" "$(fx_report)" "\`sh ops/health.sh\` timed out after 3s"
t_eq "this run's snapshot was restored" "restore snap-1" "$(grep '^restore' "$SF/ops.log")"
t_has "...and verified again, green" "$(fx_report)" "verify after restore: green"
reap
fx_mutant "MT no timeout" 's/alarm \$t; waitpid/waitpid/'
hang_world; sh "$SHIP" night > "$T_TMP/out" 2>&1 & MP=$!
started; /bin/sleep 6
t_eq "the mutant is still hung after 6s" alive "$(kill -0 "$MP" 2>/dev/null && echo alive || echo done)"
kill -TERM "$MP" 2>/dev/null; wait "$MP" 2>/dev/null; reap
SHIP=''

t_section "TERM during a hung verify: the group is killed, this run's snapshot restored, the night reported"
term_world() { fx_world; fx_git api "verify may take 10 min" sh -c 'sed "s/^timeout.verify 3$/timeout.verify 600/" .agents/ship.conf > m && mv m .agents/ship.conf'
  fx_base api; fx_main api src/t.txt t; touch "$SF/verify-hangs"; }
term_world; T0="$(date +%s)"
sh "$T_TMP/inst/bin/deploy-fleet.sh" night > "$T_TMP/out" 2>&1 & RP=$!
started; kill -TERM "$RP"; RC=0; wait "$RP" || RC=$?
t_eq "the runner exits 143" 143 "$RC"
t_eq "...within seconds" yes "$([ $(($(date +%s) - T0)) -lt 30 ] && echo yes || echo no)"
t_eq "the hung verify's process is gone" gone "$(gone)"
t_eq "this run's snapshot was restored" "restore snap-1" "$(grep '^restore' "$SF/ops.log")"
t_has "the report names the signal" "$(fx_report)" "failing: the run was interrupted by a signal during apply or verify"
t_has "...and the restore" "$(fx_report)" "snapshot: snap-1 — restore: ok"
t_eq "the baseline did not move" "$(git --git-dir="$T_TMP/remotes/api.git" rev-parse trunk~1)" "$(fx_state api .sha)"
t_eq "the receipt is red" red "$(jq -r .status "$CLAUDE_CONFIG_DIR/cache/checks/ship.json")"
t_eq "the lock is released" no "$([ -d "$HOME/.local/state/harbor/ship/lock.d" ] && echo yes || echo no)"
reap
fx_mutant "MS no signal trap" 's/^trap on_signal INT TERM HUP$/:/'
term_world; sh "$SHIP" night > "$T_TMP/out" 2>&1 & RP=$!
started; kill -TERM "$RP"; wait "$RP" 2>/dev/null
t_eq "the mutant dies without restoring" 0 "$(fx_ops restore)"
t_eq "...and leaves no report" "" "$(fx_report)"
reap
t_done
