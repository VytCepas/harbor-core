#!/usr/bin/env sh
# harbor ship, a red verify (ship contract v1 §5): restore THIS run's snapshot, verify again, file a finding, stop the
# night; one rollback per night; a rolled-back commit is never applied unattended again; the baseline moves only on green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
Q="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/bin/gate-approve.sh"
bad_world() { fx_world; fx_base api; B0="$(fx_tip api)"; fx_pr api 11 health.txt broken; fx_pr web 21 page.html hi; }

t_section "a red verify: restore this run's snapshot, verify again, report, file a finding, stop the night"
bad_world
t_eq "exit 1" 1 "$(ship night)"
BAD="$(fx_tip api)"
t_eq "#11 merged, then applied once" "merge api #11  1" "$(fx_merged) $(fx_ops apply)"
t_eq "restore got this run's snapshot" "restore snap-1" "$(grep '^restore' "$SF/ops.log")"
t_eq "every verify ran again after the restore" "2 2" "$(fx_ops verify-health) $(fx_ops verify-smoke)"
t_eq "the live box is healthy again" ok "$(cat "$LIVE/health.txt")"
R="$(fx_report)"
t_has "the report names the failing check" "$R" "failing: \`sh ops/health.sh\` exit 1 (log: "
t_has "...the snapshot and the restore" "$R" "snapshot: snap-1 — restore: ok"
t_has "...the verify after it" "$R" "verify after restore: green"
t_has "...the run log" "$R" "— log: $HOME/.local/state/harbor/ship/backups/deploy-fleet/"
t_has "the night stopped" "$R" "stopped: acme/api was rolled back"
t_has "web was not reached" "$R" "acme/web: not reached, the night stopped"
t_eq "...so #21 did not merge" "merge api #11 " "$(fx_merged)"
t_eq "the finding: the receipt is red over the repo" "red acme/api:rollback" "$(jq -r '"\(.status) \(.subjects | join(" "))"' "$CLAUDE_CONFIG_DIR/cache/checks/ship.json")"
t_has "checks.log carries one red line" "$(grep -c 'check:ship.* red night' "$T_TMP/cache/checks.log")" 1
t_eq "the baseline did not move" "$B0" "$(fx_state api .sha)"
t_eq "the bad commit is recorded as rolled back" "$BAD" "$(fx_state api '.rolled_back[0].sha')"
fx_mutant "MB1 the baseline moves before verify" \
  's/^  if verify_all "\$_h" "\$_l"; then$/  record_deployed "$DS" "$_sha" "$SID"; if verify_all "$_h" "$_l"; then/'
bad_world; ship night >/dev/null
t_eq "the mutant records the bad commit as deployed" "$(fx_tip api)" "$(fx_state api .sha)"
fx_mutant "MB2 the night does not stop" 's/if \[ -n "\$STOPPED" \]; then add notes/if false; then add notes/'
bad_world; ship night >/dev/null
t_has "the mutant goes on to merge web" "$(fx_merged)" "merge web #21"
SHIP=''

t_section "at most one rollback a night: a later run the same night does nothing unattended (red-proof)"
bad_world; ship night >/dev/null; BAD="$(fx_tip api)"
fx_later 3600
t_eq "an hour later: exit 0" 0 "$(ship night)"
t_eq "nothing more merged or applied" "merge api #11  1" "$(fx_merged) $(fx_ops apply)"
t_has "the report says why" "$(fx_report)" "stopped the night (acme/api $BAD)"
t_eq "the receipt stays red" red "$(jq -r .status "$CLAUDE_CONFIG_DIR/cache/checks/ship.json")"
t_eq "an unattended ship deploy is refused too" "0 1" "$(ship deploy acme/api --sha "$BAD") $(fx_ops apply)"
fx_mutant "MB3 a rollback stops only its own run" 's/\[ \$((NOW - _lr)) -lt "\$NIGHT" \] || return 1/return 1/'
bad_world; ship night >/dev/null; fx_later 3600; ship night >/dev/null
t_has "the mutant merges web the same night" "$(fx_merged)" "merge web #21"
SHIP=''

t_section "a rolled-back commit is never applied unattended again, even under a fix (red-proof)"
bad_world; ship night >/dev/null; BAD="$(fx_tip api)"
fx_later 72000
t_eq "the next night: exit 0" 0 "$(ship night)"
t_has "web merges now" "$(fx_merged)" "merge web #21"
t_eq "api is not applied again" 1 "$(fx_ops apply)"
t_has "it is queued, naming the rolled-back commit" "$(fx_report)" "it contains $(echo "$BAD" | cut -c1-12), which was rolled back"
fx_pr api 12 health.txt ok; ship night >/dev/null; FIX="$(fx_tip api)"
t_eq "a fix on top merges and is still not applied" "1" "$(fx_ops apply)"
t_has "...it waits for approve deploy" "$(fx_report)" "\`$Q deploy acme/api $FIX\`"
t_eq "approved, it deploys" "0 2" "$(ship deploy acme/api --sha "$FIX" --approved) $(fx_ops apply)"
fx_pr api 13 src/next.txt n; ship night >/dev/null
t_eq "past the approved baseline, deploys are unattended again" 3 "$(fx_ops apply)"
fx_mutant "MB4 a rolled-back commit is retried" 's/&& { _gate="it contains/\&\& { _retry="it contains/'
bad_world; ship night >/dev/null; fx_later 72000; ship night >/dev/null
t_eq "the mutant applies the rolled-back commit again" 2 "$(fx_ops apply)"
SHIP=''

t_section "restore only ever targets this run's snapshot: an apply that wrote none is not restored (red-proof)"
crash_world() { fx_world; fx_base api; fx_main api src/a.txt a
  ship deploy acme/api --sha "$(fx_tip api)" >/dev/null; fx_main api APPLY_CRASHES 1; }
crash_world
t_eq "the green deploy recorded its snapshot" snap-1 "$(fx_state api .snapshot)"
t_eq "the crashing apply: exit 1" 1 "$(ship night)"
t_eq "restore was never called" 0 "$(fx_ops restore)"
t_has "the report says NOT restored" "$(fx_report)" "snapshot: none from this run, NOT restored"
t_has "...and why" "$(fx_report)" "apply exited 3"
fx_mutant "MB5 restore falls back to the last recorded snapshot" \
  's/^  if \[ -z "\$SID" \]; then$/  [ -n "$SID" ] || SID="$(sget "$DS" .snapshot)"; if [ -z "$SID" ]; then/'
crash_world; ship night >/dev/null
t_eq "the mutant restores an older run's snapshot" "restore snap-1" "$(grep '^restore' "$SF/ops.log")"
SHIP=''
fx_world; fx_base api; fx_main api src/a.txt a; ship deploy acme/api --sha "$(fx_tip api)" >/dev/null
fx_main api health.txt broken; ship night >/dev/null
t_eq "with an older snapshot on disk, restore gets this run's" "restore snap-2" "$(grep '^restore' "$SF/ops.log")"

t_section "snapshot freshness (§5b.13): an id an earlier run recorded is refused, never restored (red-proof)"
stale_world() { fx_world; fx_base api; fx_main api src/a.txt a; ship deploy acme/api --sha "$(fx_tip api)" >/dev/null
  fx_main api health.txt broken; touch "$SF/apply-stale"; }
stale_world
t_eq "the recorded snapshot is snap-1" snap-1 "$(fx_state api .snapshot)"
t_eq "apply writes snap-1 again, verify goes red: exit 1" 1 "$(ship night)"
t_eq "restore was never called" 0 "$(fx_ops restore)"
t_has "the report says why" "$(fx_report)" "apply reported snap-1, the snapshot an earlier run recorded"
fx_mutant "MF a reused snapshot id is trusted" 's/^  \[ -n "\$SID" \] && \[ "\$SID" = "\$(sget "\$DS" .snapshot)" \] || return 0$/  return 0/'
stale_world; ship night >/dev/null
t_eq "the mutant restores an older run's snapshot" "restore snap-1" "$(grep '^restore' "$SF/ops.log")"
SHIP=''
t_done
