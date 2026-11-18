#!/usr/bin/env sh
# fleet-snapshot-refresh under the event dispatcher (2026-11-16): it returns at once and refreshes detached, so the
# serial dispatcher is not held for the minutes a tick takes; and one refresh runs at a time, a dead holder's lock taken
# over. The refresher runs alone in a temp bin/ with a stub orchestrator that takes 3 s, so no sibling job runs.
. "$(dirname "$0")/../../lib/core.sh"; t_init
W="$T_TMP/w"; mkdir -p "$W/bin" "$W/cfg" "$W/cache"
cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/status-fleet-snapshot-refresh.sh" "$W/bin/"
printf '#!/bin/sh\necho call >> "%s/calls"\nsleep 3\nprintf "[{\\"id\\":1}]"\n' "$W" > "$W/orch"; chmod +x "$W/orch"
run() { # [env assignments...]: one refresh as its callers start it
  env CLAUDE_CONFIG_DIR="$W/cfg" HARBOR_SCOPE_CACHE_DIR="$W/cache" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/orch" \
    HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" "$@" sh "$W/bin/status-fleet-snapshot-refresh.sh" >/dev/null 2>&1
}
calls() { grep -c . "$W/calls" 2>/dev/null || echo 0; }
settle() { n=0; while [ -e "$W/cache/fleet-snapshot-refresh.lock" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done; }

t_section "the dispatcher's handler returns at once; the refresh runs detached"
rm -f "$W/calls" "$W/cache/fleet-snapshot.json"
_t0=$(date +%s); run HARBOR_EVENT_JSON='{"kind":"ci.job.done"}'; _dt=$(( $(date +%s) - _t0 ))
t_eq "the handler is back well inside the stub's 3 s" yes "$([ "$_dt" -lt 2 ] && echo yes || echo "no (${_dt}s)")"
sleep 0.5; settle
t_eq "...and the refresh still ran, once" 1 "$(calls)"
t_eq "...and wrote the snapshot" '[{"id":1}]' "$(cat "$W/cache/fleet-snapshot.json" 2>/dev/null)"
t_eq "...and let go of its lock" no "$([ -e "$W/cache/fleet-snapshot-refresh.lock" ] && echo yes || echo no)"

t_section "one refresh at a time: a second trigger while one runs is answered by it"
rm -f "$W/calls"
run & _p=$!
n=0; while [ ! -e "$W/cache/fleet-snapshot-refresh.lock" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
_t0=$(date +%s); run; _dt=$(( $(date +%s) - _t0 ))
wait "$_p"
t_eq "the second returns at once" yes "$([ "$_dt" -lt 2 ] && echo yes || echo "no (${_dt}s)")"
t_eq "...and the orchestrator ran once for both" 1 "$(calls)"

t_section "a lock whose holder is gone is taken over"
rm -f "$W/calls"; mkdir -p "$W/cache/fleet-snapshot-refresh.lock"; echo 999999 > "$W/cache/fleet-snapshot-refresh.lock/pid"
run
t_eq "a dead holder's lock does not stop the refresh" 1 "$(calls)"
t_eq "...and is gone after it" no "$([ -e "$W/cache/fleet-snapshot-refresh.lock" ] && echo yes || echo no)"
t_done
