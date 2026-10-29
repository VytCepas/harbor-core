#!/usr/bin/env sh
# ci-governor.sh against PATH shims for ioreg, sysctl, pgrep, docker and gh, and a fake runners dir whose
# svc.sh only records. Nothing real is read or touched: not the runners, not launchd, not Colima.
# Each policy has a planted case that must move and a control that must not. The emergency ladder, the
# events and the wiring are in ci-governor-ladder-test.sh; the shims and helpers in ci-governor-fixture.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/ci-governor-fixture.sh"

t_section "active vs idle: the budget follows the user"
reset; : > "$FX/lbusy"; gov tick >/dev/null
t_eq "30s since the last keypress is active: the budget is 4" 4 "$(st budget)"
t_eq "...and a busy harbor-linux is capped to it, live" 4 "$(cpus)"
reset; : > "$FX/lbusy"; echo 700 > "$FX/idle"; gov tick >/dev/null
t_eq "700s idle (over 600) is idle: the budget is 8" 8 "$(st budget)"
t_eq "...and the cap follows" 8 "$(cpus)"
reset; echo 599 > "$FX/idle"; gov tick >/dev/null
t_eq "control: 599s is still active" 4 "$(st budget)"
reset; printf 'active_budget=3\nidle_budget = 6\nload_ceiling=junk\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; gov tick >/dev/null
t_eq "the config file overrides a default" 3 "$(st budget)"
echo 700 > "$FX/idle"; tick 30; tick 120
t_eq "...and the idle one (spaces around = are allowed)" 5 "$(st budget)"
reset; printf 'active_budget=; rm -rf /\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; gov tick >/dev/null
t_eq "a value that is not a number is the default, never evaluated" 4 "$(st budget)"

t_section "normal_min: a busy normal container never gets fewer than 2 cpus, however many are busy (harbor#1060)"
reset; for c in a-linux b-linux c-linux d-linux; do ctr "$c" busy; done; gov tick >/dev/null
t_eq "budget 4, four busy normal jobs (even share 1): each gets 2" "2 2 2 2" "$(ccpus a-linux) $(ccpus b-linux) $(ccpus c-linux) $(ccpus d-linux)"
reset; for c in a-linux b-linux c-linux; do ctr "$c" busy; done; : > "$FX/lbusy"; gov tick >/dev/null
t_eq "three busy normal beside a busy low one: each normal gets 2" "2 2 2" "$(ccpus a-linux) $(ccpus b-linux) $(ccpus c-linux)"
t_eq "...and the low one is still never below linux_min" 1 "$(cpus)"
reset; for c in a-linux b-linux c-linux; do ctr "$c"; done; : > "$FX/a-linux.lbusy"; gov tick >/dev/null
t_eq "control: idle containers stay at linux_min" "1 1 1" "$(ccpus b-linux) $(ccpus c-linux) $(cpus)"
reset; ctr a-linux busy; ctr b-linux busy; gov tick >/dev/null
t_eq "control: two busy normal on budget 4 split evenly, as before" "2 2" "$(ccpus a-linux) $(ccpus b-linux)"
reset; printf 'normal_min=3\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; for c in a-linux b-linux c-linux; do ctr "$c" busy; done; gov tick >/dev/null
t_eq "normal_min=3 is honoured: three busy normal jobs get 3 each" "3 3 3" "$(ccpus a-linux) $(ccpus b-linux) $(ccpus c-linux)"
reset; printf 'normal_min=1\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; for c in a-linux b-linux c-linux d-linux; do ctr "$c" busy; done; gov tick >/dev/null
t_eq "normal_min=1 is the old even share: four busy normal jobs get 1 each" "1 1 1 1" "$(ccpus a-linux) $(ccpus b-linux) $(ccpus c-linux) $(ccpus d-linux)"
reset; printf 'normal_min=3\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; echo 2 > "$FX/vmcpus"; ctr a-linux busy; gov tick >/dev/null
t_eq "normal_min is still capped at the Colima VM's cpus" 2 "$(ccpus a-linux)"

t_section "the cap never exceeds the Colima VM"
reset; : > "$FX/lbusy"; echo 2 > "$FX/vmcpus"; echo 700 > "$FX/idle"; gov tick >/dev/null
t_eq "budget 8 on a 2-CPU VM caps harbor-linux at 2" 2 "$(cpus)"
t_eq "...with no update, since it was already 2" 0 "$(nupd)"
t_has "status names the resize the budget needs" "$(gov status)" "colima start --cpu 8"

t_section "an overload cuts at once, then waits for the load average to catch up"
reset; : > "$FX/lbusy"; echo 700 > "$FX/idle"; gov tick >/dev/null
echo 9.50 > "$FX/load"; tick 30
t_eq "load 9.5 over the ceiling of 8 halves the budget at once" 4 "$(st budget)"
t_eq "...and the cap with it" 4 "$(cpus)"
t_has "the cut is one stamped checks.log line naming the load" "$(tail -1 "$CACHE/checks.log")" "budget 8 -> 4 (load 9.50 over 8)"
tick 30
t_eq "30s later, still loaded: no second cut yet (cut_interval 60)" 4 "$(st budget)"
tick 30
t_eq "60s after the first cut, still loaded: halved again" 2 "$(st budget)"
tick 60
t_eq "never below min_budget 2" 2 "$(st budget)"
reset; echo 700 > "$FX/idle"; gov tick >/dev/null; echo 8.00 > "$FX/load"; tick 30
t_eq "control: load exactly at the ceiling is not over it" 8 "$(st budget)"

t_section "min_budget is a floor, not only a limit on cuts (a raised min_budget lifts a budget sitting under it)"
reset; echo 700 > "$FX/idle"; gov tick >/dev/null; echo 12.00 > "$FX/load"; tick 30; tick 60
t_eq "(setup) a sustained load has the budget at the default floor of 2" 2 "$(st budget)"
printf 'min_budget=3\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; tick 60
t_eq "min_budget raised to 3, load still over the ceiling: the budget is lifted to 3" 3 "$(st budget)"
t_has "...as one stamped line naming why" "$(tail -1 "$CACHE/checks.log")" "budget 2 -> 3 (raised to min_budget 3)"
tick 60
t_eq "control: at the floor the budget holds, no flapping" 3 "$(st budget)"
reset; echo 700 > "$FX/idle"; gov tick >/dev/null; echo 12.00 > "$FX/load"; tick 30; tick 60; tick 60
t_eq "control: min_budget unchanged (2): a budget at 2 stays 2" 2 "$(st budget)"

t_section "hysteresis: a raise waits, and climbs in steps"
reset; gov tick >/dev/null; echo 700 > "$FX/idle"
tick 60
t_eq "idle 60s after the last change: no raise yet (raise_interval 120)" 4 "$(st budget)"
tick 60
t_eq "120s after it: raised one step of 2" 6 "$(st budget)"
tick 60
t_eq "60s after that raise: held" 6 "$(st budget)"
tick 60
t_eq "120s after it: at the idle target" 8 "$(st budget)"
reset; gov tick >/dev/null; echo 700 > "$FX/idle"; echo 7.00 > "$FX/load"; tick 300
t_eq "a load of 7 (under the ceiling, over raise_below 6) holds the budget" 4 "$(st budget)"
echo 5.00 > "$FX/load"; tick 30
t_eq "...and a load of 5 lets it climb" 6 "$(st budget)"
reset; echo 700 > "$FX/idle"; gov tick >/dev/null; echo 30 > "$FX/idle"; tick 30
t_eq "the user coming back cuts at once, no waiting" 4 "$(st budget)"

t_section "one line per change, never one per tick"
reset; : > "$FX/lbusy"; gov tick >/dev/null; tick; tick; tick
t_eq "four ticks with nothing changing: one line (the first tick's)" 1 "$(nlog)"
t_has "...stamped with the register id" "$(cat "$CACHE/checks.log")" "[check:ci-governor]"
echo 9.00 > "$FX/load"; tick
t_eq "a cut adds one" 2 "$(nlog)"
t_has "...that carries the cap change" "$(tail -1 "$CACHE/checks.log")" "harbor-linux --cpus 4 -> 2"
tick 5; tick 5
t_eq "control: the held ticks after it add none" 2 "$(nlog)"
t_eq "the cap is applied once, not re-applied every tick" 2 "$(nupd)"
reset; : > "$FX/lbusy"; : > "$FX/update.fail"; gov tick >/dev/null; tick; tick
t_eq "a failing docker update is said once" 1 "$(grep -c 'WARN harbor-linux --cpus 2 -> 4 failed' "$CACHE/checks.log")"

t_section "a busy runner is never stopped"
reset; printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$MACW" > "$FX/procs"
gov tick >/dev/null; echo 9.00 > "$FX/load"; tick; tick 60
t_eq "budget 2 leaves no room, but harbor-mac has a Worker: not stopped" 0 "$(nsvc stop)"
t_eq "...and GitHub was not even asked" no "$([ -f "$FX/gh.calls" ] && echo yes || echo no)"
reset; gov tick >/dev/null; echo 9.00 > "$FX/load"; echo true > "$FX/ghbusy"; tick; tick 60
t_eq "no Worker here but GitHub says busy (a job being handed over): not stopped" 0 "$(nsvc stop)"
reset; gov tick >/dev/null; echo 9.00 > "$FX/load"; : > "$FX/gh.fail"; tick; tick 60
t_eq "GitHub not answering: not stopped" 0 "$(nsvc stop)"
reset; gov tick >/dev/null; tick
t_eq "control: at budget 4 there is still room, so an idle runner stays up" 0 "$(nsvc stop)"
echo 9.00 > "$FX/load"; tick
t_eq "at budget 2, idle here and on GitHub: stopped" 1 "$(nsvc stop)"
t_eq "...and recorded as parked by the governor" harbor-mac "$(st parked)"
t_has "...in one line" "$(tail -1 "$CACHE/checks.log")" "harbor-mac stopped"
t_eq "other-mac is never managed" 0 "$(nsvc other)"
echo 2.00 > "$FX/load"; tick 120
t_eq "load gone and a raise to 4 has room again: the parked runner is started" 1 "$(nsvc start)"
t_eq "...and is no longer parked" "" "$(st parked)"

t_section "a runner the operator stopped stays stopped"
reset; printf '%s\n' "$GTML" > "$FX/procs"; gov tick >/dev/null; tick 300
t_eq "harbor-mac down, not parked by the governor: never started" 0 "$(nsvc start)"

t_section "other runners' jobs count against the budget, and so does harbor-linux's"
reset; printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$GTMW" > "$FX/procs"; gov tick >/dev/null
t_eq "harbor-linux idle sits at its floor of 1" 1 "$(cpus)"
t_eq "...and a other-mac job (2 cores) leaves 2 local slots of 4" 2 "$(st slots)"
: > "$FX/lbusy"; tick
t_eq "harbor-linux busy: the other-mac job leaves it 2 of 4" 2 "$(cpus)"
t_eq "...so CI holds 4" 4 "$(st ci_cores)"
t_eq "...so local slots fall to the minimum of 1" 1 "$(st slots)"
reset; gov tick >/dev/null
t_eq "control: nothing busy, 4 local slots" 4 "$(st slots)"

t_section "--dry-run decides and does nothing"
reset; : > "$FX/lbusy"; echo 700 > "$FX/idle"
O="$(gov tick --dry-run)"
t_has "it says what it would do" "$O" "would: harbor-linux --cpus 2 -> 8"
t_eq "...and does not do it" 2 "$(cpus)"
t_eq "...writes no state" no "$([ -e "$CACHE/ci-governor" ] && echo yes || echo no)"
t_eq "...and no log line" 0 "$(nlog)"

t_section "the statusline cache"
reset; echo 700 > "$FX/idle"; gov tick >/dev/null; echo 9.00 > "$FX/load"; tick
t_eq "the cache carries the budget" 4 "$(jq -r .budget "$CACHE/ci-governor.json")"
t_eq "...and says it is held under the target" true "$(jq -r .held "$CACHE/ci-governor.json")"

# ── run ─────────────────────────────────────────────────────────────────────────────────────────
runc() { HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_GOV_POLL=0.2 sh "$GOV" run "$@"; }
nslots() { find "$SD/slots" -type f 2>/dev/null | wc -l | tr -d ' '; }

t_section "run: no state dir, so it just runs (a CI container)"
reset
O="$(runc -- sh -c 'echo hello; exit 3' 2>&1)"; RC=$?
t_eq "the command ran" hello "$O"
t_eq "...its exit code came back" 3 "$RC"
t_eq "...and no state dir was made" no "$([ -e "$SD" ] && echo yes || echo no)"

t_section "run: a slot is taken while the command runs and given back after"
reset; gov tick >/dev/null
O="$(runc -- sh -c 'ls "$1" | wc -l | tr -d " "' _ "$SD/slots")"
t_eq "one slot was held while the command ran" 1 "$O"
t_eq "...and none after" 0 "$(nslots)"
runc --out "$T_TMP/out.txt" -- sh -c 'echo to-file; exit 4'; RC=$?
t_eq "--out sends the command's output to the file" to-file "$(cat "$T_TMP/out.txt")"
t_eq "...keeping its exit code" 4 "$RC"
O="$(GITHUB_ACTIONS=true runc -- sh -c 'ls "$1" | wc -l | tr -d " "' _ "$SD/slots")"
t_eq "under GitHub Actions it takes no slot (the runner is governed by tick)" 0 "$O"
O="$(runc -- sh -c 'HARBOR_NOW="$2" HARBOR_CACHE_DIR="$3" sh "$4" run -- sh -c "ls \"\$1\" | wc -l | tr -d \" \"" _ "$1"' _ "$SD/slots" "$AT" "$CACHE" "$GOV")"
t_eq "a run nested in a run takes no second slot (no self-deadlock)" 1 "$O"

t_section "run: a state dir it cannot write runs at once, never waits forever (harbor#555)"
# The confinement denies ~/.claude, so the lock is never made and the deadline, read only under it, never came.
reset; gov tick >/dev/null; printf 'run_deadline=30\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
chmod 555 "$SD" "$SD/slots"
if { printf "" > "$SD/.root-probe"; } 2>/dev/null; then
  rm -f "$SD/.root-probe"; printf '  note: this user writes through mode 555 (root), so the unwritable dir cannot be planted here\n'
else
  S0="$(date +%s)"; O="$(runc -- sh -c 'echo ran; exit 5' 2>&1)"; RC=$?; S1="$(date +%s)"
  t_has "the command ran" "$O" "ran"
  t_eq "...at once, not at the 30 s deadline" yes "$([ $((S1 - S0)) -lt 10 ] && echo yes || echo no)"
  t_eq "...keeping its exit code" 5 "$RC"
  t_has "...and said it ran without a slot" "$O" "is not writable here, so this runs without a slot"
fi
chmod 755 "$SD" "$SD/slots"

t_section "run: a full box waits, says so, and runs at the deadline"
reset; gov tick >/dev/null
printf 'slots=1\n' >> "$SD/state"   # the last line wins
sleep 30 & HOLDER=$!
printf '%s\n%s\nholder\n' "$HOLDER" "$(ps -o lstart= -p "$HOLDER" | tr -s ' ')" > "$SD/slots/$HOLDER"
printf 'run_deadline=1\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
O="$(runc -- echo ran 2>&1)"
t_has "a live holder of the only slot makes it wait, visibly" "$O" "waiting for a CPU slot: 1 of 1 in use"
t_has "...and at the deadline it runs anyway, and says so" "$O" "running over budget"
t_has "...the command did run" "$O" "ran"
t_eq "the live holder's slot was not taken from it" yes "$([ -f "$SD/slots/$HOLDER" ] && echo yes || echo no)"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

t_section "run: a dead holder's slot is reclaimed"
reset; gov tick >/dev/null; printf 'slots=1\n' >> "$SD/state"
sh -c 'exit 0' & DEAD=$!; wait "$DEAD"
printf '%s\nWed Jan  1 00:00:00 2025\ndead\n' "$DEAD" > "$SD/slots/$DEAD"
printf 'run_deadline=30\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
O="$(runc -- echo ran 2>&1)"
t_eq "a slot whose pid is gone does not hold the box: it runs at once" ran "$O"
t_eq "...and the dead slot is gone" no "$([ -f "$SD/slots/$DEAD" ] && echo yes || echo no)"
printf '%s\nWed Jan  1 00:00:00 2025\nrecycled\n' "$$" > "$SD/slots/$$"
O="$(runc -- echo ran 2>&1)"
t_eq "a live pid with another start time (a recycled pid) is reclaimed too" ran "$O"

t_section "run: a stale state is decided at acquire, never trusted (no timer keeps it fresh)"
reset; gov tick >/dev/null; printf 'slots=1\n' >> "$SD/state"
sleep 30 & H1=$!
printf '%s\n%s\nh\n' "$H1" "$(ps -o lstart= -p "$H1" | tr -s ' ')" > "$SD/slots/$H1"
printf 'run_deadline=1\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
O="$(runc -- echo ran 2>&1)"
t_has "control: a fresh state's 1 slot, held, makes it wait" "$O" "waiting for a CPU slot: 1 of 1 in use"
O="$(AT=$((AT + 600)) runc -- echo ran 2>&1)"
t_eq "the same state 600s old is decided again (4 slots, no CI): straight through" ran "$O"
t_eq "...and that decision was written" $((AT + 600)) "$(st at)"
kill "$H1" 2>/dev/null; wait 2>/dev/null
reset; gov tick >/dev/null; runc -- true
t_eq "run posts the governor's event on acquire and on release" 2 "$(grep -c 'com.harbor.ci-governor.event' "$FX/posts")"

t_section "a tick lock re-taken after its dead holder's pid was read is not taken over"
# Forced: as the waiter learns the old holder is dead, a live process takes the lock (the race event-bus.sh hit on CI).
verdict="$( STATE_DIR="$T_TMP/lockrace"; mkdir -p "$STATE_DIR"; L="$STATE_DIR/tick.lock"
  eval "$(sed -n '/^tick_lock() {/,/^}/p' "$GOV")"
  sleep 30 > /dev/null & LIVE=$!
  ( exit 0 ) & DEAD=$!; wait "$DEAD"
  mkdir "$L"; echo "$DEAD" > "$L/pid"
  kill() {
    if [ "$1" = -0 ] && [ "$2" = "$DEAD" ] && [ ! -e "$L.swapped" ]; then
      : > "$L.swapped"; rm -rf "$L"; mkdir "$L"; echo "$LIVE" > "$L/pid"; return 1
    fi
    command kill "$@"
  }
  ( sleep 1; [ "$(cat "$L/pid" 2>/dev/null)" = "$LIVE" ] && echo intact > "$L.verdict"; rm -rf "$L" ) &
  REL=$!
  tick_lock || echo timeout > "$L.verdict"
  wait "$REL"; command kill "$LIVE" 2>/dev/null
  cat "$L.verdict" 2>/dev/null || echo stolen )"
t_eq "the live holder keeps its lock; the waiter takes it once released" intact "$verdict"

t_done
