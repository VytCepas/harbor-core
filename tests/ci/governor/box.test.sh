#!/usr/bin/env sh
# ci-governor.sh as the box's one budget owner (harbor#1630): background jobs through `admit`, memory in `run`, the Colima
# VM's size through `vm`, the disk through `prune`, and pid checks that read one lstart spelling whatever the locale.
# Shims and helpers in ci-governor-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../ci-governor-fixture.sh"

conf() { printf '%s\n' "$@" >> "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; }
adm() { gov admit job -- sh -c ': > "$FX/ran"'; }   # one admit; $FX/ran says whether the job ran
ran() { if [ -f "$FX/ran" ]; then rm -f "$FX/ran"; echo yes; else echo no; fi; }
nl() { if [ -f "$CACHE/checks.log" ]; then grep -c "$1" "$CACHE/checks.log"; else echo 0; fi; }
ncol() { if [ -f "$FX/colima.calls" ]; then grep -c "^$1" "$FX/colima.calls"; else echo 0; fi; }
ndk() { if [ -f "$FX/docker.calls" ]; then grep -c "^$1" "$FX/docker.calls"; else echo 0; fi; }

t_section "pid checks read one lstart spelling: a C-locale pidfile is alive to a session in another locale"
reset; tick
sleep 60 & SP=$!
printf '%s %s\n' "$SP" "$(LC_ALL=C ps -o lstart= -p "$SP" | tr -s ' ')" > "$SD/listener"   # what launchd (C) writes
if [ "$(LC_ALL=C ps -o lstart= -p "$SP")" = "$(LC_ALL=en_NZ.UTF-8 ps -o lstart= -p "$SP" 2>/dev/null)" ]; then
  echo "  note: this ps spells lstart the same in en_NZ (no such locale here); the reading below is only the plain case"
fi
t_has "status from an en_NZ session names the live listener" \
  "$(LANG=en_NZ.UTF-8 LC_ALL=en_NZ.UTF-8 gov status)" "listener running (pid $SP)"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
t_has "...and a listener that is gone reads NOT running" "$(gov status)" "listener NOT running"

t_section "admit: a background job runs on a quiet box, and is skipped on a loaded one"
reset; rm -rf "$SD"; adm
t_eq "no state dir (nothing governs here): the job just runs" yes "$(ran)"
reset; tick; adm
t_eq "load 2 under the ceiling of 8: it runs" yes "$(ran)"
t_eq "...and leaves no skip record" no "$([ -f "$SD/admit/job" ] && echo yes || echo no)"
echo 12.00 > "$FX/load"; adm
t_eq "load 12 over the ceiling of 8: skipped" no "$(ran)"
t_exit "...and a skip exits 0 (launchd sees no failure)" 0 gov admit job -- false
t_eq "...one log line for the streak, not one a skip" 1 "$(nl 'admit job: skipped (load 12.00 over 8)')"
t_eq "...the record counts both skips" 2 "$(kv() { awk -F= -v k="$1" '$1 == k { print $2 }' "$SD/admit/job"; }; kv skips)"
t_has "...and status shows the streak" "$(gov status)" "admit     job skipped 2 time(s)"
echo 2.00 > "$FX/load"; AT=$((AT + 60)); adm
t_eq "the load gone: it runs" yes "$(ran)"
t_eq "...the end of the streak is one log line" 1 "$(nl 'admit job: runs after 2 skip(s)')"
t_eq "...and the record is gone" no "$([ -f "$SD/admit/job" ] && echo yes || echo no)"
echo 12.00 > "$FX/load"; adm; AT=$((AT + 1799)); adm
t_eq "skipped 1799s: still skipped" no "$(ran)"
AT=$((AT + 1)); adm
t_eq "skipped admit_max_defer (1800s): it runs anyway, loaded or not" yes "$(ran)"
t_eq "...and says so" 1 "$(nl 'deferred the maximum 1800s (load 12.00 over 8)')"
conf load_ceiling=20; adm
t_eq "load_ceiling=20: load 12 runs" yes "$(ran)"

t_section "admit: memory and an emergency are reasons too"
reset; tick; echo 2 > "$FX/mem"; adm
t_eq "memory pressure level 2 (warn): skipped" no "$(ran)"
t_eq "...and the log names it" 1 "$(nl 'skipped (memory pressure level 2)')"
reset; tick; echo 10 > "$FX/avail"; adm
t_eq "10% memory available, at or under 15: skipped" no "$(ran)"
reset; tick; echo 40 > "$FX/avail"; adm
t_eq "40% available: runs" yes "$(ran)"
reset; tick; printf 'sampled_at=%s\non=1\nwhy=cpu 99%% busy\n' "$AT" > "$SD/emergency"; adm
t_eq "an emergency on (a fresh sample): skipped" no "$(ran)"
reset; tick; printf 'sampled_at=%s\non=1\nwhy=x\n' "$((AT - 120))" > "$SD/emergency"; adm
t_eq "an emergency from a sample 2 minutes old: not held, runs" yes "$(ran)"
t_exit "admit with no command: usage, exit 2" 2 gov admit job --
t_exit "admit with a bad name: usage, exit 2" 2 gov admit 'a b' -- true

t_section "the fleet snapshot refresher goes through admit"
reset; tick; echo 12.00 > "$FX/load"
HARBOR_TEST_NOW="$AT" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_SCOPE_FLEET_FILE=/nonexistent sh "$T_ROOT/bin/status-fleet-snapshot-refresh.sh" >/dev/null 2>&1
t_eq "load 12: the refresh is skipped, under its own name" yes "$([ -f "$SD/admit/status.fleet-snapshot" ] && echo yes || echo no)"
t_eq "...before it wrote a snapshot" no "$([ -f "$CACHE/fleet-snapshot.json" ] && echo yes || echo no)"

t_section "run: under memory pressure, one local slot at a time"
reset; tick; conf run_deadline=0
sleep 60 & SP=$!
printf '%s\n%s\n%s\n' "$SP" "$(LC_ALL=C ps -o lstart= -p "$SP" | tr -s ' ')" "a suite" > "$SD/slots/$SP"
o="$(gov run -- true)"
t_hasnt "memory fine, budget 4: a second slot without a wait" "${o:-ran at once}" "waiting for a CPU slot"
echo 10 > "$FX/avail"; o="$(gov run -- true)"
t_has "10% available: the second waits, and says why" "$o" "1 of 1 in use (memory available 10%, so one at a time)"
rm -f "$FX/avail"; echo 2 > "$FX/mem"; o="$(gov run -- true)"
t_has "pressure level 2: the same" "$o" "(memory pressure level 2, so one at a time)"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
t_has "status says the limit is on" "$(gov status)" "memory    pressure level 2 (warn at 2), available ?% (min 15): local slots one at a time"

t_section "vm: the Colima VM's size is held, and changed only while nothing runs in it"
reset; tick; echo 8 > "$FX/colima.cpus"; echo 8 > "$FX/colima.mem"
t_has "no size held: says so, touches nothing" "$(gov vm)" "vm: no size held"
t_eq "...not even a colima list" 0 "$(ncol list)"
conf colima_cpus=4 colima_memory=4
o="$(gov vm)"
t_has "held at 4/4, VM at 8/8, all idle: says what resize would do" "$o" "would restart it to 4 / 4 GiB"
t_eq "...and does not stop it" 0 "$(ncol stop)"
: > "$FX/lbusy"
t_exit "a busy runner: resize refuses, exit 1" 1 gov vm resize
t_has "...naming the runner" "$(gov vm resize)" "runner(s) not idle: harbor-linux busy"
t_eq "...and never stops the VM" 0 "$(ncol stop)"
rm -f "$FX/lbusy"; : > "$FX/docker.down"
t_has "docker unread: refuses (an unread runner is not an idle one)" "$(gov vm resize)" "not restarted now: docker ps failed"
rm -f "$FX/docker.down"
sleep 60 & SP=$!
printf '%s\n%s\n%s\n' "$SP" "$(LC_ALL=C ps -o lstart= -p "$SP" | tr -s ' ')" "a suite" > "$SD/slots/$SP"
t_has "a local slot taken: refuses" "$(gov vm resize)" "1 local slot(s) taken"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null; rm -f "$SD/slots/$SP"
t_exit "every runner idle, no slot: resize restarts it" 0 gov vm resize
t_eq "...stopped once" 1 "$(ncol stop)"
t_eq "...and started at the held size" 1 "$(ncol 'start --cpu 4 --memory 4')"
t_eq "...read back at 4/4 and logged" 1 "$(nl 'vm: Colima up at 4 cpus/4GiB')"
t_has "at its size: nothing to do" "$(gov vm resize)" "vm: at its size"
t_eq "...no second stop" 1 "$(ncol stop)"
echo 8 > "$FX/colima.cpus"; : > "$FX/colima.startfail"
t_exit "the sized start fails: exit 1" 1 gov vm resize
t_eq "...and it is started again as it was, so the runners come back" 1 "$(ncol 'start$')"
t_eq "...with a WARN line" 1 "$(nl 'WARN vm: the Colima restart')"

t_section "vm: an idle tick resizes only with colima_auto=1, at most once a vm_retry"
reset; tick; echo 8 > "$FX/colima.cpus"; echo 8 > "$FX/colima.mem"; conf colima_cpus=4 colima_memory=4
HARBOR_CI_GOVERNOR_SYNC=1; export HARBOR_CI_GOVERNOR_SYNC
tick; tick
t_eq "colima_auto unset (off): ticks never touch the VM" 0 "$(ncol stop)"
conf colima_auto=1; : > "$FX/lbusy"; tick
t_eq "colima_auto=1, a runner busy: no restart" 0 "$(ncol stop)"
rm -f "$FX/lbusy"; tick
t_eq "colima_auto=1, all idle: the tick restarts it" 1 "$(ncol 'start --cpu 4 --memory 4')"
echo 8 > "$FX/colima.cpus"; tick
t_eq "drifted again inside vm_retry (3600s): left alone" 1 "$(ncol stop)"
tick 3600
t_eq "...and tried again once vm_retry has passed" 2 "$(ncol stop)"

t_section "prune: off unless prune_every is set, then only on an idle box, once a period"
reset; echo 700 > "$FX/idle"; tick; tick
t_eq "prune_every unset: an idle box prunes nothing" 0 "$(ndk builder)"
t_has "...and status says it is off" "$(gov status)" "prune     off (prune_every=0)"
conf prune_every=604800; echo 30 > "$FX/idle"; tick
t_eq "prune_every set, the user active: nothing" 0 "$(ndk builder)"
echo 700 > "$FX/idle"; tick
t_eq "idle: the build cache over 7 days is pruned" 1 "$(ndk 'builder prune -f --filter until=168h')"
t_eq "...dangling images" 1 "$(ndk 'image prune -f')"
t_eq "...the uv cache" 1 "$(grep -c '^cache prune' "$FX/uv.calls")"
t_eq "...one log line" 1 "$(nl 'prune: docker build cache older than 7 days pruned')"
tick; tick 86400
t_eq "a day later: not again inside the week" 1 "$(ndk builder)"
tick 604800
t_eq "a week later: again" 2 "$(ndk builder)"
: > "$FX/lbusy"; tick 604800
t_eq "a runner busy: never prunes under a job" 2 "$(ndk builder)"
rm -f "$FX/lbusy"
o="$(gov prune --dry-run)"
t_has "prune --dry-run says what it would do" "$o" "would: docker build cache older than 7 days pruned"
t_eq "...and runs none of it" 2 "$(ndk builder)"
: > "$FX/prune.fail"
t_has "a docker prune that fails is a WARN, the rest still runs" "$(gov prune)" "WARN docker build cache older than 7 days pruned failed"
unset HARBOR_CI_GOVERNOR_SYNC

t_done
