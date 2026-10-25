#!/usr/bin/env sh
# ci-wait.sh (harbor#1367): a PR's CI verdict, woken by ci.job.done on a real bus, with `gh` stubbed. It returns the
# verdict on the event rather than on its backstop, never waits on a status that is not CI, and has a deadline.
. "$(dirname "$0")/../../lib/core.sh"; t_init
W="$T_ROOT/bin/ci-wait.sh"; BUS="$T_ROOT/bin/event-bus.sh"
export HARBOR_EVENT_DIR="$T_TMP/bus" GH_OUT="$T_TMP/gh.json"; mkdir -p "$HARBOR_EVENT_DIR"
cat > "$T_BIN/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_OUT.calls"
[ -s "$GH_OUT" ] || exit 1
cat "$GH_OUT"
STUB
chmod +x "$T_BIN/gh"
checks() { printf '%s' "$1" > "$GH_OUT"; }  # <json>
GREEN='[{"name":"test","bucket":"pass"},{"name":"lint","bucket":"skipping"}]'
REVIEW='[{"name":"test","bucket":"pass"},{"name":"review/decision","bucket":"pending"}]'
run() { O="$(sh "$W" "$@" 2>&1)"; RC=$?; }

t_section "a settled PR: one read, the verdict, its exit code"
checks "$GREEN"; run acme/widgets#9
t_eq "all passing: exit 0" 0 "$RC"; t_eq "...one line naming the counts" "acme/widgets#9: green (1 pass, 1 skipping)" "$O"
t_has "...read with the PR number and repo" "$(cat "$GH_OUT.calls")" "pr checks 9 -R acme/widgets --json name,bucket"
checks '[{"name":"test","bucket":"pass"},{"name":"lint","bucket":"fail"}]'; run acme/widgets#9
t_eq "a failing check: exit 1" 1 "$RC"; t_has "...and says red" "$O" ": red (1 fail, 1 pass)"
checks '[{"name":"test","bucket":"cancel"}]'; run https://github.com/acme/widgets/pull/9
t_eq "a cancelled check is red, and a pull URL is read the same" 1 "$RC"

t_section "review/decision is not CI: named, never waited on"
checks "$REVIEW"; run acme/widgets#9 --timeout 5
t_eq "CI passed and review/decision pending: green at once" 0 "$RC"
t_has "...the verdict names it apart from CI" "$O" "not CI: review/decision pending"
checks "$REVIEW"; O="$(HARBOR_CI_NOT_CHECKS='' HARBOR_CI_WAIT_BACKSTOP=1 HARBOR_CI_WAIT_SETTLE=1 sh "$W" acme/widgets#9 --timeout 3 2>&1)"; RC=$?
t_eq "control: counted as CI, the same PR runs out its deadline (exit 3)" 3 "$RC"
t_has "...and says it is still running" "$O" "still running after 3s"

t_section "pending: woken by ci.job.done, not by the backstop"
checks '[{"name":"test","bucket":"pending"}]'; : > "$GH_OUT.calls"
T0="$(date +%s)"
HARBOR_CI_WAIT_BACKSTOP=60 HARBOR_CI_WAIT_SETTLE=1 sh "$W" acme/widgets#9 --timeout 90 > "$T_TMP/bg.out" 2>&1 & WP=$!
sleep 2
t_eq "while pending it has read GitHub once, then sleeps" 1 "$(grep -c . "$GH_OUT.calls")"
checks "$GREEN"; sh "$BUS" emit ci.job.done acme/widgets:1:test --src test >/dev/null
wait "$WP"; RC=$?; DT=$(( $(date +%s) - T0 ))
t_eq "the job's event ends the wait: exit 0" 0 "$RC"; t_has "...with the green verdict" "$(cat "$T_TMP/bg.out")" ": green"
t_eq "...in seconds, far inside the 60 s backstop" yes "$([ "$DT" -lt 20 ] && echo yes || echo "no (${DT}s)")"

t_section "deadline, GitHub down, and usage"
checks '[{"name":"test","bucket":"pending"}]'
O="$(HARBOR_CI_WAIT_BACKSTOP=1 HARBOR_CI_WAIT_SETTLE=1 sh "$W" acme/widgets#9 --timeout 2 2>&1)"; RC=$?
t_eq "never settles: exit 3 at the deadline" 3 "$RC"
: > "$GH_OUT"
O="$(HARBOR_CI_WAIT_BACKSTOP=1 HARBOR_CI_WAIT_SETTLE=1 sh "$W" acme/widgets#9 --timeout 30 2>&1)"; RC=$?
t_eq "GitHub unreadable three reads running: exit 4" 4 "$RC"; t_has "...and says so" "$O" "GitHub did not answer"
for bad in acme acme/widgets acme/widgets#x 'a;b/c#1' a/b/c#1; do
  run "$bad"; t_eq "'$bad' is refused before any command: exit 2" 2 "$RC"
done
run acme/widgets#9 --timeout 0; t_eq "a zero deadline is refused: exit 2" 2 "$RC"

t_section "harbor event ci reaches it"
checks "$GREEN"; O="$(sh "$BUS" ci acme/widgets#9 2>&1)"; RC=$?
t_eq "event-bus.sh hands the ci sub-verb to ci-wait" "0:acme/widgets#9: green (1 pass, 1 skipping)" "$RC:$O"
t_done
