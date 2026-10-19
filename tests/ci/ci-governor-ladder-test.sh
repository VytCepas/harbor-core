#!/usr/bin/env sh
# ci-governor.sh's emergency ladder, its event-driven listener and the local suite entries that take a
# slot: the second half of ci-governor-test.sh, split out for tests/'s 500-line budget (harbor#817).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/ci-governor-fixture.sh"

# ── emergency: a spike seen in seconds, a ladder undone on recovery ─────────────────────────────
samp() { AT=$((AT + ${1:-3})); HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" sample >/dev/null 2>&1; }
ek() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print }' "$SD/emergency"; }
pstat() { ps -o stat= -p "$1" 2>/dev/null | cut -c1; }
child_of() { ps -A -o pid=,ppid=,comm= | awk -v p="$1" '$2 == p && $3 ~ /sleep$/ { print $1; exit }'; }   # the sleep, not a passing notifyutil
# slot_up — a real local run (sleep 60) holding a slot; sets SLOT (the run) and KID (the sleep under it).
slot_up() {
  HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" sh "$GOV" run -- sleep 60 >/dev/null 2>&1 & SLOT=$!
  KID=""; _i=0
  while [ -z "$KID" ] && [ "$_i" -lt 50 ]; do sleep 0.1; [ -f "$SD/slots/$SLOT" ] && KID="$(child_of "$SLOT")"; _i=$((_i + 1)); done
}
slot_down() { kill -CONT "$KID" 2>/dev/null; kill "$KID" "$SLOT" 2>/dev/null; wait "$SLOT" 2>/dev/null; }
stopped() { [ "$(pstat "$1")" = T ] && echo yes || echo no; }
clear_out() { echo 1 > "$FX/mem"; echo 10 > "$FX/cpu"; rm -f "$FX/therm"; samp 3; samp 60; }   # clear_secs 60 later: over

t_section "emergency: a CPU spike is two hot samples in a row, while the user is active"
reset; printf 'min_budget=1\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; gov tick >/dev/null
echo 9.00 > "$FX/load"; tick 30; echo 2.00 > "$FX/load"
t_eq "(setup) a load cut has just taken the budget to 2" 2 "$(st budget)"
echo 99 > "$FX/cpu"; samp 3
t_eq "one sample at 99% busy is not yet an emergency" 0 "$(ek on)"
samp 3
t_eq "the second in a row is" 1 "$(ek on)"
t_eq "rung (a): the budget is at min_budget at once, 6s after a cut (cut_interval skipped)" 1 "$(st budget)"
t_has "one stamped line says why" "$(tail -1 "$CACHE/checks.log")" "EMERGENCY: cpu 99% busy"
reset; echo 99 > "$FX/cpu"; echo 700 > "$FX/idle"; samp; samp; samp
t_eq "control: the user idle, CI is meant to fill the box: no emergency" 0 "$(ek on)"
reset; echo 94 > "$FX/cpu"; samp; samp; samp
t_eq "control: 94% is under cpu_emergency 95" 0 "$(ek on)"
reset; echo 99 > "$FX/cpu"; samp; echo 10 > "$FX/cpu"; samp; echo 99 > "$FX/cpu"; samp
t_eq "control: hot, clear, hot is not two in a row" 0 "$(ek on)"

t_section "emergency: memory pressure and thermal need one sample"
reset; gov tick >/dev/null; echo 4 > "$FX/mem"; samp
t_eq "critical memory pressure (4) is an emergency on one sample" 1 "$(ek on)"
t_has "...named" "$(ek why)" "memory pressure level 4"
reset; echo 2 > "$FX/mem"; samp
t_eq "control: warn (2) is under mem_emergency 4" 0 "$(ek on)"
reset; printf 'CPU Power notify\n\tCPU_Scheduler_Limit \t= 100\n\tCPU_Available_CPUs \t= 10\n\tCPU_Speed_Limit \t= 70\n' > "$FX/therm"; samp
t_eq "a CPU speed limit of 70% is an emergency" 1 "$(ek on)"
t_has "...named" "$(ek why)" "CPU speed limited to 70%"
reset; printf 'CPU Power notify\n\tCPU_Speed_Limit \t= 100\n' > "$FX/therm"; samp
t_eq "control: a limit of 100% is none" 0 "$(ek on)"
reset; printf 'Thermal warning level set to 2.\n' > "$FX/therm"; samp
t_eq "a recorded thermal warning level is an emergency" 1 "$(ek on)"
reset; samp
t_eq "control: 'No thermal warning level has been recorded' is none" 0 "$(ek on)"

t_section "rung (b): local slots are stopped, and continued after"
reset; gov tick >/dev/null; slot_up
t_eq "(setup) a real local run is holding a slot" yes "$([ -n "$KID" ] && echo yes || echo no)"
echo 4 > "$FX/mem"; samp
t_eq "the emergency SIGSTOPs the process under the slot" yes "$(stopped "$KID")"
t_has "...in the one line" "$(tail -1 "$CACHE/checks.log")" "1 local slot process(es) stopped"
clear_out
t_eq "60s clear later it is continued" no "$(stopped "$KID")"
t_has "...and says so" "$(tail -1 "$CACHE/checks.log")" "1 local slot process(es) continued (emergency over)"
slot_down

t_section "rung (b): a stopped process whose run died is still continued"
reset; gov tick >/dev/null; slot_up; echo 4 > "$FX/mem"; samp
kill -KILL "$SLOT"; wait "$SLOT" 2>/dev/null
t_eq "(setup) the run is gone and its sleep is orphaned, still stopped" yes "$(stopped "$KID")"
clear_out
t_eq "recovery continues it from the record, not from a slot that no longer exists" no "$(stopped "$KID")"
kill "$KID" 2>/dev/null

t_section "rung (b) is bounded: stop_max, resume, and the watcher's exit"
reset; printf 'stop_max=10\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; gov tick >/dev/null; slot_up
echo 4 > "$FX/mem"; samp
t_eq "(setup) stopped" yes "$(stopped "$KID")"
tick 11
t_eq "stop_max 10s on, the slot is continued though the emergency is not over" no "$(stopped "$KID")"
t_eq "...the emergency itself holds" 1 "$(st emerg_applied)"
slot_down
reset; gov tick >/dev/null; slot_up; echo 4 > "$FX/mem"; samp
O="$(gov resume)"
t_eq "resume continues a stopped slot by hand" no "$(stopped "$KID")"
t_has "...and says what it did" "$O" "continued (resumed by hand)"
slot_down
reset; gov tick >/dev/null; slot_up; echo 4 > "$FX/mem"
printf 'sample_interval=0.2\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" sampler >/dev/null 2>&1 & W=$!
_i=0; while [ "$(stopped "$KID")" = no ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
t_eq "the sampler stops the slot within its own loop" yes "$(stopped "$KID")"
kill -TERM "$W"; wait "$W" 2>/dev/null
t_eq "a sampler told to stop continues the slot first" no "$(stopped "$KID")"
slot_down

t_section "rung (c): harbor-linux to a fractional floor, then back"
reset; : > "$FX/lbusy"; gov tick >/dev/null
echo 4 > "$FX/mem"; samp
t_eq "harbor-linux is at linux_emergency_cpus 0.5" 500000000 "$(cat "$FX/nano")"
clear_out
t_eq "after recovery it is back on the budget (2)" 2 "$(cpus)"

t_section "rung (d): a busy Mac job to darwin background, never other-mac's, back after"
reset; printf '%s\n%s\n%s\n%s\n' "$MACL" "$GTML" "$MACW" "$GTMW" > "$FX/procs"; gov tick >/dev/null
echo 4 > "$FX/mem"; samp
t_has "harbor-mac's Runner.Worker is moved with taskpolicy -b" "$(cat "$FX/taskpolicy.log")" "-b -p 80001"
t_hasnt "other-mac's is never touched" "$(cat "$FX/taskpolicy.log")" "80002"
t_eq "nothing was stopped or started" 0 "$(nsvc s)"
clear_out
t_has "after recovery it is moved back with taskpolicy -B" "$(cat "$FX/taskpolicy.log")" "-B -p 80001"
reset; printf '%s\n%s\n' "$MACL" "$MACW" > "$FX/procs"; gov tick >/dev/null; samp
t_eq "control: no emergency, no taskpolicy" no "$([ -f "$FX/taskpolicy.log" ] && echo yes || echo no)"

t_section "recovery has hysteresis: clear_secs with no hot sample, then the slow raise"
reset; gov tick >/dev/null; echo 4 > "$FX/mem"; samp; echo 1 > "$FX/mem"
samp 3; samp 50
t_eq "50s clear: still on" 1 "$(ek on)"
echo 99 > "$FX/cpu"; samp 3; echo 10 > "$FX/cpu"
t_eq "a single hot CPU sample (short of spike_samples) keeps it on" 1 "$(ek on)"
samp 3; samp 57
t_eq "...and restarted the clock: 57s after it, still on" 1 "$(ek on)"
samp 3
t_eq "60s clear: over" 0 "$(ek on)"
t_eq "the budget stays at the floor on the way out" 2 "$(st budget)"
tick 60
t_eq "60s after: the raise still waits (raise_interval 120)" 2 "$(st budget)"
tick 60
t_eq "120s after: the slow raise resumes" 4 "$(st budget)"

t_section "emergency: one line in, one line out, nothing per sample"
reset; gov tick >/dev/null; N0="$(nlog)"; echo 4 > "$FX/mem"; samp
t_eq "entering is one line" $((N0 + 1)) "$(nlog)"
samp; samp; tick 30; tick 30
t_eq "samples and ticks during it add none" $((N0 + 1)) "$(nlog)"
clear_out
t_eq "leaving is one more" $((N0 + 2)) "$(nlog)"
t_has "...that says so" "$(tail -1 "$CACHE/checks.log")" "emergency over"

t_section "a dead sampler cannot hold an emergency"
reset; : > "$FX/lbusy"; gov tick >/dev/null; slot_up; echo 4 > "$FX/mem"; samp
tick 120
t_eq "a sample 120s old counts as clear: the slot is continued" no "$(stopped "$KID")"
t_eq "...and harbor-linux is off its emergency floor" 2 "$(cpus)"
slot_down

t_section "emergency --dry-run decides and does nothing"
reset; gov tick >/dev/null; slot_up; echo 4 > "$FX/mem"
O="$(HARBOR_NOW="$((AT + 3))" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" sample --dry-run 2>&1)"
t_has "it says it is an emergency" "$O" "emergency 1 (memory pressure level 4)"
t_has "...and what it would stop" "$O" "would: SIGSTOP local slot processes"
t_eq "...and stops nothing" no "$(stopped "$KID")"
t_eq "...nor writes the sampler's state" no "$([ -f "$SD/emergency" ] && echo yes || echo no)"
slot_down

t_section "the statusline cache says emergency"
reset; gov tick >/dev/null; echo 4 > "$FX/mem"; samp
t_eq "emergency is true in the cache" true "$(jq -r .emergency "$CACHE/ci-governor.json")"


# ── events: nothing runs on a timer ────────────────────────────────────────────────────────────
LST=""
listen_up() {
  printf 'sample_interval=0.2\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
  rm -f "$FX/notify.waiting"
  HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" listen >/dev/null 2>&1 & LST=$!
  _i=0; while [ ! -f "$SD/state" ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
  _i=0; while [ ! -f "$FX/notify.waiting" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done   # it is LISTENING
}
listen_down() { kill -TERM "$LST" 2>/dev/null; wait "$LST" 2>/dev/null; }   # the listener alone, as its own exit must clean up
sampler_down() { _sp="$(awk '{print $1}' "$SD/sampler" 2>/dev/null)"; [ -z "$_sp" ] || kill "$_sp" 2>/dev/null; }
until_eq() { # <want> <cmd…> — up to 5s for <cmd> to print <want>; prints what it last printed
  _w="$1"; shift; _i=0
  while [ "$("$@")" != "$_w" ] && [ "$_i" -lt 25 ]; do sleep 0.2; _i=$((_i + 1)); done; "$@"
}
sampler_alive() { _sp="$(awk '{print $1}' "$SD/sampler" 2>/dev/null)"; [ -n "$_sp" ] && kill -0 "$_sp" 2>/dev/null && echo yes || echo no; }
niostat() { if [ -f "$FX/iostat.calls" ]; then wc -l < "$FX/iostat.calls" | tr -d ' '; else echo 0; fi; }

t_section "events: the listener decides once at start, then waits"
reset; listen_up
t_eq "it made its first decision" 4 "$(st budget)"
N0="$(niostat)"; sleep 2
t_eq "an idle box: no sample in 2s (nothing is polled)" "$N0" "$(niostat)"
t_eq "...and no sampler" no "$(sampler_alive)"
listen_down; sampler_down

t_section "events: a container job hook's trigger line reaches a decision"
reset; listen_up
t_eq "(setup) harbor-linux idle at its floor of 1 before the event" 1 "$(cpus)"
printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$GTMW" > "$FX/procs"; : > "$FX/lbusy"
echo "1790000000 job-started" >> "$FX/trigger"
t_eq "the trigger line woke it: harbor-linux busy, a other-mac job holds 2, so 2 of 4" 2 "$(until_eq 2 cpus)"
t_eq "cores are held, so the sampler runs" yes "$(until_eq yes sampler_alive)"
printf '%s\n%s\n' "$MACL" "$GTML" > "$FX/procs"; rm -f "$FX/lbusy"; echo "1790000001 job-completed" >> "$FX/trigger"
t_eq "the completed line: nothing held, the sampler exits" no "$(until_eq no sampler_alive)"
t_eq "...and harbor-linux is back at its floor" 1 "$(until_eq 1 cpus)"
listen_down; sampler_down

t_section "events: a host job hook's notification reaches a decision"
reset; : > "$FX/lbusy"; listen_up
printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$MACW" > "$FX/procs"
notifyutil -p com.harbor.ci-governor.event
t_eq "a harbor-mac job (2 cores) is counted: harbor-linux cut to 2" 2 "$(until_eq 2 cpus)"
listen_down; sampler_down

t_section "events: an OS pressure notification reaches a decision"
reset; listen_up
echo 4 > "$FX/mem"; notifyutil -p com.apple.system.memorystatus
t_eq "the memorystatus post makes it read the pressure level: emergency" 1 "$(until_eq 1 ek on)"
t_eq "...with the budget at its floor" 2 "$(until_eq 2 st budget)"
t_eq "an emergency keeps the sampler running, for the recovery" yes "$(until_eq yes sampler_alive)"
listen_down; sampler_down
reset; listen_up
echo 4 > "$FX/mem"; notifyutil -p com.apple.system.thermalpressurelevel
t_eq "the thermal key wakes it too" 1 "$(until_eq 1 ek on)"
listen_down; sampler_down

t_section "events: a local run is a held core, released when it ends"
reset; listen_up; slot_up
t_eq "the run's post started the sampler" yes "$(until_eq yes sampler_alive)"
slot_down
t_eq "its exit posted again: the sampler is gone" no "$(until_eq no sampler_alive)"
listen_down; sampler_down

t_section "events: the listener told to stop undoes the ladder first"
reset; listen_up; slot_up
echo 4 > "$FX/mem"; notifyutil -p com.apple.system.memorystatus
t_eq "(setup) the emergency stopped the slot" yes "$(until_eq yes stopped "$KID")"
listen_down
t_eq "launchctl bootout's SIGTERM: the slot is continued" no "$(until_eq no stopped "$KID")"
t_eq "...and it stopped the sampler too" no "$(until_eq no sampler_alive)"
sampler_down; slot_down

t_section "the job hook: a line through the mount, a post on the host, and never a failed job"
reset; mkdir -p "$FX/events"
HARBOR_GOV_EVENTS="$FX/events" GITHUB_JOB=build sh "$T_ROOT/bin/ci-governor-hook.sh"; RC=$?
t_has "inside the container it appends to the mounted trigger" "$(cat "$FX/events/trigger")" " build"
t_has "on the host it posts the governor's event" "$(cat "$FX/posts")" "com.harbor.ci-governor.event"
t_eq "it exits 0" 0 "$RC"
chmod 0500 "$FX/events"; HARBOR_GOV_EVENTS="$FX/events" PATH="/bin" /bin/sh "$T_ROOT/bin/ci-governor-hook.sh"; RC=$?
chmod 0700 "$FX/events"
t_eq "an unwritable mount and no notifyutil still exit 0: the job is never failed for it" 0 "$RC"

# The container outlives its jobs: a fixed /tmp path one job left failed the next (uv venv /tmp/smoke-venv).
# Every call here aims the clear at a fixture: in harbor's own CI container an unaimed one emptied the pool's /tmp.
: > "$FX/dockerenv"
tmpfix() { rm -rf "$TR"; TR="$FX/tmproot"; mkdir -p "$TR/smoke-venv/bin"; : > "$TR/gitleaks.tmp"; ln -s /nonexistent "$TR/link"; mkfifo "$TR/clr-debug-pipe"; }
tmpfix; env -u HARBOR_GOV_EVENTS HARBOR_HOOK_DOCKERENV="$FX/dockerenv" HARBOR_HOOK_TMP="$TR" sh "$T_ROOT/bin/ci-governor-hook.sh"; RC=$?
t_eq "as the runner wires it in a container, it empties /tmp of the last job's files, dirs and links" "clr-debug-pipe" "$(ls "$TR")"
t_eq "...keeps the runner's live pipe, and still exits 0" 0 "$RC"
tmpfix; HARBOR_GOV_EVENTS="$FX/events" HARBOR_HOOK_DOCKERENV="$FX/dockerenv" HARBOR_HOOK_TMP="$TR" sh "$T_ROOT/bin/ci-governor-hook.sh"
t_eq "a suite calling it in a container (HARBOR_GOV_EVENTS set) clears nothing (harbor#1072)" 4 "$(ls "$TR" | wc -l | tr -d ' ')"
tmpfix; env -u HARBOR_GOV_EVENTS HARBOR_HOOK_DOCKERENV="$FX/no-dockerenv" HARBOR_HOOK_TMP="$TR" sh "$T_ROOT/bin/ci-governor-hook.sh"
t_eq "on the host (no /.dockerenv) it clears nothing" 4 "$(ls "$TR" | wc -l | tr -d ' ')"

# ── wiring: the two local suite entries wait for a slot, visibly ────────────────────────────────
# A fixture repo with the real hook, run.sh and governor; one live holder of the only slot.
full_box() {
  reset; gov tick >/dev/null; printf 'slots=1\nat=%s\n' "$(date +%s)" >> "$SD/state"
  sleep 30 & HOLDER=$!
  printf '%s\n%s\nholder\n' "$HOLDER" "$(ps -o lstart= -p "$HOLDER" | tr -s ' ')" > "$SD/slots/$HOLDER"
  printf 'run_deadline=1\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
}
FR="$T_TMP/fr"
mkdir -p "$FR/bin" "$FR/hooks" "$FR/tests/lib" "$FR/tests/x" "$FR/CONTRACTS"
cp "$T_ROOT/hooks/pre-push" "$T_ROOT/hooks/lib.sh" "$FR/hooks/"
cp "$T_ROOT/bin/ci-governor.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/suite-run.sh" "$FR/bin/"
cp "$T_ROOT/tests/lib/run.sh" "$T_ROOT/tests/lib/core.sh" "$FR/tests/lib/"
: > "$FR/bin/suite-select.sh"
printf '#!/bin/sh\nexit 0\n' > "$FR/bin/lint-conventions.sh"
printf '#!/bin/sh\necho "x-test: 1 passed, 0 failed"\n' > "$FR/tests/x/x-test.sh"
printf 'tests/x/x-test.sh\n' > "$FR/CONTRACTS/suites.txt"
git init -q -b main "$FR" >/dev/null 2>&1
( cd "$FR" && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -q -m base ) >/dev/null 2>&1

t_section "wiring: hooks/pre-push takes a slot per check"
full_box
O="$(cd "$FR" && printf '' | HARBOR_CACHE_DIR="$CACHE" HARBOR_GOV_POLL=0.2 sh hooks/pre-push 2>&1)"; RC=$?
t_has "the linter waited for the only slot, and said so" "$O" "waiting for a CPU slot: 1 of 1 in use"
t_has "...on its own line, not inside the hook's run line" "$O" "run   lint-conventions.sh
ci-governor: waiting"
t_eq "...and the push was not refused for it" 0 "$RC"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

t_section "wiring: bin/suite-run.sh takes a slot per suite"
full_box
O="$(HARBOR_CACHE_DIR="$CACHE" HARBOR_GOV_POLL=0.2 sh "$FR/bin/suite-run.sh" -j 1 tests/x/x-test.sh 2>&1)"; RC=$?
t_has "the suite waited for the only slot, and said so" "$O" "waiting for a CPU slot: 1 of 1 in use"
t_eq "...then passed" 0 "$RC"
t_hasnt "...and the wait is not in the suite's verdict" "$O" "FAIL"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

t_section "wiring: just test (tests/lib/run.sh) takes a slot per suite"
full_box
O="$(HARBOR_CACHE_DIR="$CACHE" HARBOR_GOV_POLL=0.2 sh "$FR/tests/lib/run.sh" 2>&1)"; RC=$?
t_has "the suite waited for the only slot, and said so" "$O" "waiting for a CPU slot: 1 of 1 in use"
t_has "...then ran, its summary read from the log --out wrote" "$O" "harbor: 1 passed, 0 failed"
t_eq "...and run.sh exits 0" 0 "$RC"
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

t_done
