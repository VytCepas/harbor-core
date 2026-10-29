#!/usr/bin/env sh
# ci-governor.sh (harbor#1032) — a CPU-core budget that every CI job and local suite run on this Mac goes through.
#
#   sh ci-governor.sh listen                 what launchd keeps alive: blocks on events, never on a timer
#   sh ci-governor.sh event [what]           one decision (a tick), and the sampler started if cores are held
#   sh ci-governor.sh sampler                the emergency sampler: runs only while CI or a local slot holds cores
#   sh ci-governor.sh tick [--dry-run]       one idempotent control step; --dry-run prints what it would do, writes nothing
#   sh ci-governor.sh sample [--dry-run]     one fast emergency sample; a tick follows when the emergency state flips
#   sh ci-governor.sh resume                 undo every emergency rung now (SIGCONT, priority back); listen does it on exit
#   sh ci-governor.sh status                 the signals, the budget, the runners and the local slots
#   sh ci-governor.sh run [--out F] -- <cmd> run <cmd> once a local CPU slot is free, waiting with a message and
#                                            a deadline; --out sends <cmd>'s output to F, the waits stay on stderr
#
# platform: macOS-only — it budgets a Mac's cores through launchd, `pmset -g therm` and `notifyutil` events; the *-linux runner containers it throttles are reached through docker, not run on Linux (harbor#618).
#
# JOBS RUN AT NORMAL PRIORITY AND FULL CLOCK; THIS DECIDES HOW MANY CORES CI MAY HOLD. Measured 2026-10-04:
# runners at launchd ProcessType=Background (E-cores only, throttled) made every CI job 2-3x slower. A quota
# on parallelism keeps the box responsive without that cost.
#
# THE POLICY. Defaults below; each is a key=value line in $CLAUDE_CONFIG_DIR/.harbor-ci-governor.
#   budget = active_budget (4) while the user is active, idle_budget (8) after idle_after (600) seconds with
#   no keyboard or mouse. A 1-min load above load_ceiling (8) halves it at once, never below min_budget (2),
#   and again at most every cut_interval (60) seconds, because the load average lags the cut it already
#   caused. A fall in the target (the user is back) applies at once. A RISE waits raise_interval (120)
#   seconds since the last change and a load under raise_below (6), and climbs raise_step (2) at a time.
#
# APPLIED BY. `docker update --cpus` on each Linux runner container (live: a running job slows, never dies),
# capped at the Colima VM's CPUs. The containers are linux_runners if listed, else DISCOVERED each tick by one
# `docker ps`: every running one named *-linux or *-linux-<N> whose image is the actions runner's (harbor#1060; harbor-linux-2 is the second
# governance runner). A gate runner (harbor-gate, harbor#1286) is not *-linux: never discovered, never moved; it keeps the cpus it was made with.
# PRIORITY CLASSES (harbor#1060). low_priority (harbor-linux, projects-orchestrator-linux, project-init-linux:
# harbor, Fleet, Yard; a listed name's numbered twin, harbor-linux-2, is low too, so a second runner is never unmanaged) yields to every other container. Per tick: each busy normal container gets an even share
# of the budget less linux_min (1) for each busy low one; busy low ones split what is left, never under
# linux_min; an idle one sits at linux_min. NORMAL_MIN (normal_min, 2): a busy normal container never gets fewer
# than normal_min cpus however many are busy (measured: with several busy at budget 4 the even share was ~1 and
# a perf-budget test failed only for that); still capped at the Colima VM's cpus. When busy-normal x normal_min
# exceeds the budget, normal_min WINS over the even share: the box is oversubscribed on purpose (--cpus is a
# cap, not a reservation, and the kernel shares what is really there), and low ones still keep linux_min, never
# less; a lifted low job leaves each busy normal one its normal_min first. normal_min=1 is the plain even share. A normal job starting cuts a busy low one on that tick, cuts before
# raises, and its end restores it.
# A managed host runner (mac_runners, none by default) is stopped only when the budget leaves no room for one
# more job AND it is idle both here (no Runner.Worker) and on GitHub AND no macOS job is queued there
# (liveness beats the budget; an unreadable answer parks and is logged); it is started again only if this
# governor stopped it, so a runner the operator stopped stays stopped. Any other runner's busy Worker on this
# host (other-mac, or harbor-mac when unmanaged) is counted at job_cores (2) and never managed.
#
# LOCAL SLOTS = budget minus the cores CI holds, at least 1. `run` takes one per command; a slot whose pid
# died (or was reused) is reclaimed. With no state dir (a CI container, a box that never ran `tick`), under
# GitHub Actions, or nested inside another slot, `run` just runs the command. At the deadline it runs anyway
# and says so: this is a throttle, not a gate.
#
# EVENT-DRIVEN: AN IDLE BOX IS NEVER POLLED. `listen` blocks on two streams and wakes only when one speaks:
#   - `notifyutil -w` on com.harbor.ci-governor.event (posted by a host runner's job hook, bin/ci-governor-hook.sh,
#     and by `run` on every slot taken and given back) and on the OS keys com.apple.system.thermalpressurelevel,
#     com.apple.system.memorystatus and kern.memorystatus_level. A user cannot post those three (measured: the
#     post returns 0 and nothing arrives), and which of them fires on a real pressure change is UNMEASURED here
#     (simulating pressure needs root); each wake reads the sysctl and pmset, which are measured, not the key.
#   - `tail -f` on trigger_file (~/runners/harbor-linux/events/trigger): every runner container mounts that
#     events dir at /gov-events, and its job hook appends a line through the bind mount. tail -f waits on
#     kqueue; a container write reached it in under 100 ms (2026-10-04). Content is ignored: a line only means
#     "decide again".
# Each wake is one tick (budget, caps, parking), then the sampler if anything holds cores. There is no event for
# the user going idle, so HIDIdleTime is read when something else wakes the governor.
#
# THE LIMIT, PLAINLY: a CPU spike from an unrelated process has no kernel event. It is seen only while the
# sampler runs, and the sampler runs only while CI or a local slot holds cores (or an emergency is on) — which
# is the only time the governor has anything to throttle. On a box holding nothing, a spike is not seen at all,
# and costs nothing.
#
# EMERGENCY (a spike the load average would show 30-90s late). The sampler samples every sample_interval (2) s
# plus iostat's 1s: CPU busy over that second at or above cpu_emergency (95) % on spike_samples (2) samples
# in a row while the user is active (idle, CI is meant to fill the box), memory pressure at or above
# mem_emergency (4, critical; kern.memorystatus_vm_pressure_level), or a recorded thermal or performance warning
# level or a CPU speed limit under thermal_speed_min (90) % (`pmset -g therm`), the last two on one sample. The
# ladder, each rung undone on recovery and the whole change one log line: (a) budget to min_budget at once;
# (b) SIGSTOP every process under a local `run` slot, SIGCONT after, and at most stop_max (300) s;
# (c) every Linux runner to linux_emergency_cpus (0.5); (d) a busy managed Mac job's Runner.Worker tree to
# darwin background (`taskpolicy -b -p`), `taskpolicy -B` after. No job is killed; `docker pause` is not used
# (a paused runner sends GitHub no heartbeat, and how long GitHub waits is unmeasured). Recovery needs
# clear_secs (60) with no hot sample, then the slow raise above. A sample over 60s old counts as clear.
#
# OUTPUT. One `[check:ci-governor]` line in cache/checks.log per change of budget or runner state, never per
# tick; cache/ci-governor.json for the statusline. POSIX sh; docker, gh, ioreg, sysctl, pgrep, iostat, pmset,
# notifyutil, taskpolicy from PATH.
set -eu
# `run` with nothing to govern is a plain exec, before any config is read: every CI suite passes through here.
if [ "${1:-}" = run ] && { [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${HARBOR_GOV_SLOT:-}" ] \
     || [ ! -d "${HARBOR_GOVERNOR_DIR:-${HARBOR_CACHE_DIR:-$HOME/.claude/cache}/ci-governor}" ]; }; then
  shift; _o=""
  [ "${1:-}" != --out ] || { _o="${2:-}"; shift 2; }
  [ "${1:-}" != -- ] || shift
  if [ $# -gt 0 ]; then if [ -n "$_o" ]; then exec "$@" > "$_o" 2>&1; else exec "$@"; fi; fi
  set -- run
fi
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
# shellcheck disable=SC2034  # read by library-log.sh: stdout is status output, the log goes to stderr
LOG_FD=2
log_init ci-governor

usage() { awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CFG/.harbor-ci-governor"
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
STATE_DIR="${HARBOR_GOVERNOR_DIR:-$CACHE_DIR/ci-governor}"
STATE="$STATE_DIR/state"
OUT="$CACHE_DIR/ci-governor.json"
LOG="$CACHE_DIR/checks.log"
RUNNERS_DIR="${HARBOR_RUNNERS_DIR:-$HOME/runners}"
EMERG="$STATE_DIR/emergency"      # the sampler's state (key=value)
STOPPED="$STATE_DIR/stopped"      # "pid lstart" of every process SIGSTOPped, for the SIGCONT
LISTENER="$STATE_DIR/listener"    # "pid lstart" of the live `listen`
SAMPLER="$STATE_DIR/sampler"      # "pid lstart" of the live `sampler`
EVENT_KEY=com.harbor.ci-governor.event
OS_KEYS="com.apple.system.thermalpressurelevel com.apple.system.memorystatus kern.memorystatus_level"
BGED="$STATE_DIR/backgrounded"    # "pid lstart" of every process moved to darwin background

now() { case "${HARBOR_NOW:-}" in ''|*[!0-9]*) date +%s ;; *) printf '%s' "$HARBOR_NOW" ;; esac; }
NOW="$(now)"

# cfg <key> <default> — a number from the config file; anything else is the default.
cfg() {
  _cv=""
  [ -f "$CONF" ] && _cv="$(awk -F= -v k="$1" '{ gsub(/[ \t]/, "") } $1 == k { v = $2 } END { print v }' "$CONF" 2>/dev/null || true)"
  case "$_cv" in ''|.*|*.*.*|*[!0-9.]*) printf '%s' "$2" ;; *) printf '%s' "$_cv" ;; esac
}
# cfgs <key> <default> — a list of names (runner, container, repo): letters, digits, . _ / - and commas.
cfgs() {
  _cv=""
  [ -f "$CONF" ] && _cv="$(awk -F= -v k="$1" '{ gsub(/[ \t]/, "") } $1 == k { v = $2 } END { print v }' "$CONF" 2>/dev/null || true)"
  case "$_cv" in ''|*[!A-Za-z0-9._/,-]*) printf '%s' "$2" ;; *) printf '%s' "$_cv" ;; esac
}
int() { awk -v x="$1" 'BEGIN { printf "%d", x }'; }

ACTIVE_BUDGET="$(int "$(cfg active_budget 4)")"
IDLE_BUDGET="$(int "$(cfg idle_budget 8)")"
IDLE_AFTER="$(int "$(cfg idle_after 600)")"
LOAD_CEILING="$(cfg load_ceiling 8)"
RAISE_BELOW="$(cfg raise_below 6)"
RAISE_INTERVAL="$(int "$(cfg raise_interval 120)")"
RAISE_STEP="$(int "$(cfg raise_step 2)")"
CUT_INTERVAL="$(int "$(cfg cut_interval 60)")"
MIN_BUDGET="$(int "$(cfg min_budget 2)")"
JOB_CORES="$(int "$(cfg job_cores 2)")"
LINUX_MIN="$(int "$(cfg linux_min 1)")"
NORMAL_MIN="$(int "$(cfg normal_min 2)")"
LIFT_AFTER="$(int "$(cfg lift_after 900)")"   # a low job older than this keeps lift_cpus; 900 is half of harbor's 30-minute job timeout, 0 = off
LIFT_CPUS="$(int "$(cfg lift_cpus 2)")"
RUN_DEADLINE="$(int "$(cfg run_deadline 1800)")"
STALE_AFTER="$(int "$(cfg stale_after 180)")"
MAC_RUNNERS="$(cfgs mac_runners '' | tr ',' ' ')"
LINUX_LIST="$(cfgs linux_runners '' | tr ',' ' ')"
LOW_PRIORITY="$(cfgs low_priority harbor-linux,projects-orchestrator-linux,project-init-linux | tr ',' ' ')"
REPO="$(cfgs repo '')"; [ -n "$REPO" ] || REPO="$(repo_slug "$HERE")"   # the config's `repo`, else harbor's own (harbor#1149)
MAC_LABELS="$(cfgs mac_labels self-hosted,macOS,ARM64)"
SAMPLE_INTERVAL="$(cfg sample_interval 2)"
TICK_INTERVAL="$(int "$(cfg tick_interval 30)")"
CPU_EMERGENCY="$(cfg cpu_emergency 95)"
SPIKE_SAMPLES="$(int "$(cfg spike_samples 2)")"
MEM_EMERGENCY="$(int "$(cfg mem_emergency 4)")"
THERMAL_SPEED_MIN="$(cfg thermal_speed_min 90)"
CLEAR_SECS="$(int "$(cfg clear_secs 60)")"
LINUX_EMERG_CPUS="$(awk -v x="$(cfg linux_emergency_cpus 0.5)" 'BEGIN { printf "%g", x }')"
STOP_MAX="$(int "$(cfg stop_max 300)")"
TRIGGER="${HARBOR_GOV_TRIGGER:-$HOME/runners/harbor-linux/events/trigger}"
[ "$MIN_BUDGET" -ge 1 ] || MIN_BUDGET=1
[ "$LINUX_MIN" -ge 1 ] || LINUX_MIN=1
[ "$NORMAL_MIN" -ge "$LINUX_MIN" ] || NORMAL_MIN=$LINUX_MIN

# st <key> — one value from the state file (key=value lines; read, never sourced).
kv() { [ -f "$1" ] && awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); v = $0 } END { print v }' "$1" 2>/dev/null || true; }
st() { kv "$STATE" "$1"; }
ek() { kv "$EMERG" "$1"; }
kv_pid() { [ -f "$1" ] && awk 'NR == 1 { print $1 }' "$1" 2>/dev/null || true; }
# alive <pidfile> — its pid runs and still has the start time recorded beside it (a recycled pid is not it).
alive() {
  [ -f "$1" ] || return 1
  _ap="$(awk 'NR == 1 { print $1 }' "$1")"; _al="$(awk 'NR == 1 { $1 = ""; sub(/^ /, ""); print }' "$1")"
  [ -n "$_ap" ] && kill -0 "$_ap" 2>/dev/null && [ "$(lstart "$_ap" | awk '{ $1 = $1; print }')" = "$(printf '%s' "$_al" | awk '{ $1 = $1; print }')" ]
}
pidfile() { printf '%s %s\n' "$$" "$(lstart $$)" > "$1"; }
num_or() { case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }   # float a > b
lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 < b + 0) }'; }
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }   # <word> <space list>

# ── signals ─────────────────────────────────────────────────────────────────────────────────────
signals() {
  IDLE_S="$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }' || true)"
  case "$IDLE_S" in ''|*[!0-9]*) IDLE_S="" ;; esac
  LOAD1="$(sysctl -n vm.loadavg 2>/dev/null | awk '{ gsub(/[{}]/, ""); print $1 }' || true)"
  case "$LOAD1" in ''|*[!0-9.]*) LOAD1="" ;; esac
  NCPU="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  # Unknown idle reads as ACTIVE (the smaller budget); unknown load neither cuts nor raises.
  if [ -n "$IDLE_S" ] && [ "$IDLE_S" -ge "$IDLE_AFTER" ]; then MODE=idle; TARGET="$IDLE_BUDGET"
  else MODE=active; TARGET="$ACTIVE_BUDGET"; fi
}

# Fast signals, each measured cheap (2026-10-04, this box): iostat's 1s sample costs ~0 CPU and 1s wall;
# sysctl and pmset well under 10ms.
fast_signals() {
  CPU_BUSY="$(iostat -n0 -c 2 -w 1 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { id = $3 } END { if (id != "") print 100 - id }' || true)"
  MEM_LEVEL="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || true)"
  case "$MEM_LEVEL" in ''|*[!0-9]*) MEM_LEVEL="" ;; esac
  THERM="$(pmset -g therm 2>/dev/null | awk -v lim="$THERMAL_SPEED_MIN" '
      /[Ww]arning level/ && !/No / { for (i = 1; i <= NF; i++) { v = $i; sub(/\.$/, "", v)
          if (v ~ /^[0-9]+$/ && v + 0 > 0) { w = ($0 ~ /[Pp]erformance/) ? "performance" : "thermal"; print w " warning level " v; exit } } }
      /CPU_Speed_Limit/ { v = $NF; if (v ~ /^[0-9]+$/ && v + 0 < lim + 0) { print "CPU speed limited to " v "%"; exit } }' || true)"
}

# The emergency state: in this process when `watch`/`sample` already holds it, else from the sampler's file,
# which a stale sampler (over 60s) cannot hold on.
emergency_state() {
  [ -z "${EM_LOADED:-}" ] || return 0
  EM_ON=0; EM_SINCE=0; EM_WHY=""
  _sa="$(num_or "$(ek sampled_at)" 0)"
  if [ $(( NOW - _sa )) -le 60 ]; then
    EM_ON="$(num_or "$(ek on)" 0)"; EM_SINCE="$(num_or "$(ek since)" 0)"; EM_WHY="$(ek why)"
  fi
}

cmd_sample() {
  DRY=0
  case "${1:-}" in --dry-run) DRY=1 ;; '') ;; *) log_fail "unknown option $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;; esac
  [ "$DRY" = 1 ] || mkdir -p "$STATE_DIR/slots" "$CACHE_DIR"
  NOW="$(now)"
  if [ -z "${EM_LOADED:-}" ]; then
    EM_ON="$(num_or "$(ek on)" 0)"; EM_HOT="$(num_or "$(ek hot)" 0)"; EM_SINCE="$(num_or "$(ek since)" 0)"
    EM_CLEAR="$(num_or "$(ek clear_since)" "")"; EM_WHY="$(ek why)"; EM_LOADED=1
  fi
  signals; fast_signals
  _cpu=""; _hard=""
  if [ "$MODE" = active ] && [ -n "$CPU_BUSY" ] && ! lt "$CPU_BUSY" "$CPU_EMERGENCY"; then _cpu="cpu ${CPU_BUSY}% busy"; fi
  if [ -n "$MEM_LEVEL" ] && [ "$MEM_LEVEL" -ge "$MEM_EMERGENCY" ]; then _hard="memory pressure level $MEM_LEVEL"; fi
  [ -z "$THERM" ] || _hard="${_hard:+$_hard, }$THERM"
  if [ -n "$_cpu" ]; then EM_HOT=$(( EM_HOT + 1 )); else EM_HOT=0; fi
  _was="$EM_ON"
  if [ -n "$_hard" ] || [ "$EM_HOT" -ge "$SPIKE_SAMPLES" ]; then
    EM_CLEAR=""
    if [ "$EM_ON" = 0 ]; then EM_ON=1; EM_SINCE="$NOW"; EM_WHY="${_hard}${_hard:+${_cpu:+, }}${_cpu}"; fi
  elif [ "$EM_ON" = 1 ]; then
    # Any hot sample, even one short of spike_samples, restarts the clear clock.
    if [ -n "$_cpu" ]; then EM_CLEAR=""; else
      [ -n "$EM_CLEAR" ] || EM_CLEAR="$NOW"
      [ $(( NOW - EM_CLEAR )) -lt "$CLEAR_SECS" ] || { EM_ON=0; EM_CLEAR=""; }
    fi
  fi
  if [ "$DRY" = 1 ]; then
    printf '%s sample: cpu %s%% busy (%s), memory pressure %s, thermal %s; emergency %s%s\n' "$(date +%H:%M:%S)" \
      "${CPU_BUSY:-?}" "$MODE" "${MEM_LEVEL:-?}" "${THERM:-none}" "$EM_ON" "${EM_WHY:+ ($EM_WHY)}"
  else
    printf 'sampled_at=%s\non=%s\nhot=%s\nsince=%s\nclear_since=%s\nwhy=%s\ncpu=%s\nmem=%s\ntherm=%s\n' \
      "$NOW" "$EM_ON" "$EM_HOT" "$EM_SINCE" "$EM_CLEAR" "$(printf '%s' "$EM_WHY" | tr '\n=' '  ')" "$CPU_BUSY" "$MEM_LEVEL" \
      "$(printf '%s' "$THERM" | tr '\n=' '  ')" > "$EMERG.tmp.$$" && mv -f "$EMERG.tmp.$$" "$EMERG"
  fi
  TICKED=0
  if [ "$EM_ON" != "$_was" ]; then
    TICKED=1
    if [ "$DRY" = 1 ]; then cmd_tick --dry-run; else cmd_tick; fi
    LAST_TICK="$NOW"
  fi
  return 0
}

# ── the budget, with hysteresis ─────────────────────────────────────────────────────────────────
decide() {
  P_BUDGET="$(num_or "$(st budget)" "")"
  CHANGED_AT="$(num_or "$(st changed_at)" 0)"
  CUT_AT="$(num_or "$(st cut_at)" 0)"
  BUDGET="$P_BUDGET"; REASON=""
  # Rung (a): an emergency takes the budget to its floor at once, whatever cut_interval says.
  if [ "${EM_ON:-0}" = 1 ]; then
    BUDGET="$MIN_BUDGET"
    if [ "$P_BUDGET" != "$MIN_BUDGET" ]; then REASON="emergency: $EM_WHY"; CHANGED_AT="$NOW"; CUT_AT="$NOW"; fi
    return 0
  fi
  # Out of one: the slow raise starts its clock now.
  [ "$(st emerg_applied)" != 1 ] || CHANGED_AT="$NOW"
  if [ -z "$P_BUDGET" ]; then
    BUDGET="$TARGET"; REASON="first tick, $MODE"; CHANGED_AT="$NOW"
  elif [ -n "$LOAD1" ] && gt "$LOAD1" "$LOAD_CEILING"; then
    _c=$(( P_BUDGET / 2 )); [ "$_c" -le "$TARGET" ] || _c="$TARGET"; [ "$_c" -ge "$MIN_BUDGET" ] || _c="$MIN_BUDGET"
    if [ "$P_BUDGET" -gt "$TARGET" ]; then
      BUDGET="$TARGET"; REASON="user active"; CHANGED_AT="$NOW"
    fi
    if [ "$_c" -lt "$BUDGET" ] && [ $(( NOW - CUT_AT )) -ge "$CUT_INTERVAL" ]; then
      BUDGET="$_c"; REASON="load $LOAD1 over $LOAD_CEILING"; CHANGED_AT="$NOW"; CUT_AT="$NOW"
    fi
  elif [ "$TARGET" -lt "$P_BUDGET" ]; then
    BUDGET="$TARGET"; REASON="user active"; CHANGED_AT="$NOW"
  elif [ "$TARGET" -gt "$P_BUDGET" ] && [ -n "$LOAD1" ] && lt "$LOAD1" "$RAISE_BELOW" \
       && [ $(( NOW - CHANGED_AT )) -ge "$RAISE_INTERVAL" ]; then
    BUDGET=$(( P_BUDGET + RAISE_STEP )); [ "$BUDGET" -le "$TARGET" ] || BUDGET="$TARGET"
    REASON="raise toward $TARGET ($MODE, load $LOAD1)"; CHANGED_AT="$NOW"
  fi
  # min_budget is a floor, not only a limit on cuts: a raised one lifts a budget left under it, load or not.
  if [ -n "$P_BUDGET" ] && [ "$BUDGET" -lt "$MIN_BUDGET" ]; then BUDGET="$MIN_BUDGET"; REASON="raised to min_budget $MIN_BUDGET"; CHANGED_AT="$NOW"; fi
}

# ── the runners ─────────────────────────────────────────────────────────────────────────────────
# The runner a host process belongs to: the path component before its bin*/ directory.
proc_names() { # <Runner.Worker|Runner.Listener>
  pgrep -lf "Runner\\.$1" 2>/dev/null | awk -v p="Runner.$1" '{
    for (i = 2; i <= NF; i++) { n = split($i, c, "/"); if (n >= 3 && c[n] == p && c[n-1] ~ /^bin/) { print c[n-2]; break } } }' || true
}
# Every pid of a managed runner's Runner.Worker.
managed_worker_pids() {
  pgrep -lf 'Runner\.Worker' 2>/dev/null | awk -v m=" $MAC_RUNNERS " '{
    for (i = 2; i <= NF; i++) { n = split($i, c, "/")
      if (n >= 3 && c[n] == "Runner.Worker" && c[n-1] ~ /^bin/) { if (index(m, " " c[n-2] " ")) print $1; break } } }' || true
}
# descendants <pid…> — every descendant pid of the given ones, roots excluded.
descendants() {
  ps -A -o pid=,ppid= 2>/dev/null | awk -v roots="$*" '{ kids[$2] = kids[$2] " " $1 }
    END { t = split(roots, q, " "); h = 1
      while (h <= t) { p = q[h++]; m = split(kids[p], k, " ")
        for (j = 1; j <= m; j++) if (!(k[j] in seen)) { seen[k[j]] = 1; q[++t] = k[j]; print k[j] } } }' || true
}
probe() {
  WORKERS="$(proc_names Worker | tr '\n' ' ')"
  LISTENERS="$(proc_names Listener | tr '\n' ' ')"
  FOREIGN=0; MAC_BUSY=0
  for _w in $WORKERS; do
    if in_list "$_w" "$MAC_RUNNERS"; then MAC_BUSY=$(( MAC_BUSY + JOB_CORES )); else FOREIGN=$(( FOREIGN + JOB_CORES )); fi
  done
  VM_CPUS="$(docker info --format '{{.NCPU}}' 2>/dev/null || true)"
  case "$VM_CPUS" in ''|*[!0-9]*) VM_CPUS="" ;; esac
  linux_runners
  LINUX=""; N_LINUX=0
  for _c in $LINUX_RUNNERS; do
    _cls=normal; in_list "$_c" "$LOW_PRIORITY" && _cls=low
    in_list "${_c%-[0-9]}" "$LOW_PRIORITY" && _cls=low   # harbor-linux-2 follows harbor-linux (a twin has one digit: ci-runners caps it at 9)
    _i="$(docker inspect --format '{{.State.Running}} {{.HostConfig.NanoCpus}}' "$_c" 2>/dev/null || true)"
    _run="${_i%% *}"; _nano="${_i#* }"
    case "$_run" in true) ;; false) LINUX="$LINUX$_c stopped - $_cls -
" ; continue ;; *) LINUX="$LINUX$_c unread - $_cls -
" ; continue ;; esac
    _cur="$(awk -v n="$_nano" 'BEGIN { if (n + 0 > 0) printf "%g", n / 1e9; else print "all" }')"
    # one exec: busy when a Runner.Worker runs, and then how long it has (the job's age; ps absent or silent reads "-").
    # `Runner[.]Worker` keeps the shell's own command line from matching itself.
    # pgrep's own status is kept: 1 is "no worker" (idle); 2, 3 or 127 (pgrep missing) is an error, which reads unknown and is never aged.
    if _age="$(docker exec "$_c" sh -c 'p=$(pgrep -o -f "Runner[.]Worker"); r=$?; [ "$r" = 0 ] || exit "$r"; ps -o etimes= -p "$p" 2>/dev/null; exit 0' 2>/dev/null)"; then
      _b=busy; _age="$(printf '%s' "$_age" | tr -d ' \n')"; case "$_age" in ''|*[!0-9]*) _age=- ;; esac
    else case $? in 1) _b=idle ;; *) _b=unknown ;; esac; _age=-; fi
    LINUX="$LINUX$_c $_b $_cur $_cls $_age
"
    N_LINUX=$(( N_LINUX + 1 ))
  done
}
# linux_runners → LINUX_RUNNERS: the configured list, else every running container named *-linux (or *-linux-<digit>) whose image
# is the actions runner's (its org.opencontainers.image.source label), from one `docker ps` (harbor#1060).
linux_runners() {
  if [ -n "$LINUX_LIST" ]; then LINUX_RUNNERS="$LINUX_LIST"; return 0; fi
  LINUX_RUNNERS=""
  _ps="$(docker ps --format '{{.Names}} {{.Label "org.opencontainers.image.source"}}' 2>/dev/null)" || { fail "docker ps failed: no Linux runner governed"; return 0; }
  LINUX_RUNNERS="$(printf '%s\n' "$_ps" | awk '$1 ~ /-linux(-[0-9])?$/ && $2 ~ /^https:\/\/github\.com\/actions\/runner/ { print $1 }' | sort | tr '\n' ' ')"
}
gh_busy() { # <runner> → true | false | unknown, from GitHub's own view
  [ -n "$REPO" ] || { printf unknown; return 0; }   # no repository named: unknown, as a read that failed
  _g="$(gh api "repos/$REPO/actions/runners" --jq ".runners[] | select(.name == \"$1\") | .busy" 2>/dev/null || true)"
  case "$_g" in true|false) printf '%s' "$_g" ;; *) printf unknown ;; esac
}

# gh_mac_queued → MAC_Q = yes | no | unknown: a QUEUED job a managed Mac runner could take (every label of the job is one
# of mac_labels), read from the active runs only. Asked at most once a tick, and only when the decision would
# park or keep parked (harbor#1032): liveness beats the budget, a job being bounded by its timeout.
MAC_Q=""
gh_mac_queued() {
  [ -z "$MAC_Q" ] || return 0
  [ -n "$REPO" ] || { MAC_Q=unknown; fail "macOS queue unreadable (no repository named: set repo in $CONF)"; return 0; }
  _lbl="$(printf '%s' "$MAC_LABELS" | tr 'A-Z,' 'a-z\n' | awk 'NF { printf "%s\"%s\"", n++ ? "," : "", $0 }')"
  _jq=".jobs[] | select(.status == \"queued\" and (.labels | length) > 0 and all(.labels[] | ascii_downcase; IN($_lbl))) | .id"
  MAC_Q=no
  for _s in queued in_progress; do
    _ids="$(gh api "repos/$REPO/actions/runs?status=$_s&per_page=100" --jq '.workflow_runs[].id' 2>/dev/null)" || { MAC_Q=unknown; break; }
    for _id in $_ids; do
      _j="$(gh api "repos/$REPO/actions/runs/$_id/jobs?per_page=100" --jq "$_jq" 2>/dev/null)" || { MAC_Q=unknown; continue; }
      [ -z "$_j" ] || { MAC_Q=yes; break 2; }
    done
  done
  [ "$MAC_Q" != unknown ] || fail "macOS queue unreadable (GitHub API failed)"
  return 0
}

# ── act (or say what would be done) ─────────────────────────────────────────────────────────────
CHANGES=""; FAILS=""
change() { CHANGES="${CHANGES:+$CHANGES; }$1"; }
fail() { FAILS="${FAILS:+$FAILS; }$1"; }
act() { # <description> <cmd…>
  _d="$1"; shift
  if [ "$DRY" = 1 ]; then printf 'would: %s\n' "$_d"; return 0; fi
  if "$@" >/dev/null 2>&1; then change "$_d"; return 0; fi
  fail "$_d failed"; return 1
}
svc() { ( cd "$RUNNERS_DIR/$1" && ./svc.sh "$2" ); }

# is_aged <state> <age seconds or -> — a busy job older than lift_after (an unread age is never aged)
is_aged() { [ "$1" = busy ] && [ "$LIFT_AFTER" -gt 0 ] && case "$2" in ''|-|*[!0-9]*) return 1 ;; esac && [ "$2" -ge "$LIFT_AFTER" ]; }

allocate() {
  P_PARKED="$(st parked | tr ',' ' ')"; PARKED=""; MAC_Q=""
  AVAIL=$(( BUDGET - FOREIGN - MAC_BUSY ))
  # Room for one more host job while every running Linux container keeps its floor.
  ROOM=no; [ $(( AVAIL - JOB_CORES )) -ge $(( LINUX_MIN * N_LINUX )) ] && ROOM=yes
  MAC=""
  for _m in $MAC_RUNNERS; do
    _busy=no; in_list "$_m" "$WORKERS" && _busy=yes
    _up=no; in_list "$_m" "$LISTENERS" && _up=yes
    _was=no; in_list "$_m" "$P_PARKED" && _was=yes
    _state="$([ "$_up" = yes ] && echo running || echo stopped)"
    _ask=yes; [ "$DRY" = 1 ] && [ "${NO_GH:-0}" = 1 ] && _ask=no   # `status` asks GitHub nothing
    if [ "$_up" = yes ] && [ "$_busy" = no ] && [ "$ROOM" = no ]; then
      _gb="not asked"; _q=no
      if [ "$_ask" = yes ]; then _gb="$(gh_busy "$_m")"; [ "$_gb" != false ] || { gh_mac_queued; _q="$MAC_Q"; }; fi
      if [ "$_q" = yes ]; then
        _state="running (kept: a macOS job is queued)"   # liveness beats the budget (harbor#1032)
      elif [ "$_gb" = false ] || [ "$_gb" = "not asked" ]; then
        _qn=""; [ "$_q" != unknown ] || _qn=" (queued jobs unreadable: GitHub API failed)"
        if act "$_m stopped (budget $BUDGET leaves no room for a job)$_qn" svc "$_m" stop; then _state="parked$_qn"; PARKED="$PARKED $_m"; fi
      else
        _state="running (kept: GitHub says busy=$_gb)"
      fi
    elif [ "$_up" = no ] && [ "$_was" = yes ]; then
      _q=no; [ "$ROOM" = yes ] || [ "$_ask" = no ] || { gh_mac_queued; _q="$MAC_Q"; }
      if [ "$ROOM" = yes ]; then
        if act "$_m started (budget $BUDGET has room)" svc "$_m" start; then _state=running
        else _state=parked; PARKED="$PARKED $_m"; fi
      elif [ "$_q" = yes ]; then
        if act "$_m started: a macOS job is queued (budget $BUDGET leaves no room)" svc "$_m" start; then _state="running (started: a macOS job is queued)"
        else _state=parked; PARKED="$PARKED $_m"; fi
      else
        _state=parked; [ "$_q" != unknown ] || _state="parked (queued jobs unreadable: GitHub API failed)"
        PARKED="$PARKED $_m"
      fi
    fi
    [ "$_busy" = yes ] && _state="$_state, busy"
    MAC="$MAC$_m $_state
"
  done
  PARKED="$(printf '%s' "$PARKED" | awk '{ $1 = $1; print }')"

  # Priority classes (harbor#1060). A busy normal container gets an even share of the budget less a floor for
  # each busy low one; busy low ones split what remains; neither ever under linux_min. Idle: linux_min.
  # LIFT (harbor#1060, 2026-10-06: harbor's `suites` job hit its 30-minute timeout twice at load 20+ with its container
  # at the floor): a busy low job older than lift_after keeps lift_cpus (never more than leaves every other busy
  # container its floor), so a job the floor would time out finishes; a day-to-day job still gets the rest, and a
  # young low job is cut exactly as before. lift_after=0 turns it off.
  CI_CORES=$(( FOREIGN + MAC_BUSY )); LINUX_OUT=""; WANT_VM=0; _bn=0; _bl=0; _na=0
  while read -r _c _b _cur _cls _ag; do
    case "$_b" in busy|unknown) if [ "$_cls" = low ]; then _bl=$(( _bl + 1 )); ! is_aged "$_b" "$_ag" || _na=$(( _na + 1 )); else _bn=$(( _bn + 1 )); fi ;; esac
  done <<EOF
$LINUX
EOF
  _lift=$LINUX_MIN
  if [ "$_na" -gt 0 ]; then
    _lift=$(( (AVAIL - NORMAL_MIN * _bn - LINUX_MIN * (_bl - _na)) / _na ))
    [ "$_lift" -le "$LIFT_CPUS" ] || _lift=$LIFT_CPUS; [ "$_lift" -ge "$LINUX_MIN" ] || _lift=$LINUX_MIN
  fi
  _ns=$LINUX_MIN; [ "$_bn" = 0 ] || _ns=$(( (AVAIL - LINUX_MIN * (_bl - _na) - _lift * _na) / _bn )); [ "$_ns" -ge "$NORMAL_MIN" ] || _ns=$NORMAL_MIN   # normal_min, after the share, so low ones below keep linux_min
  _ls=$LINUX_MIN; [ "$_bl" = 0 ] || _ls=$(( (AVAIL - _ns * _bn) / _bl )); [ "$_ls" -ge "$LINUX_MIN" ] || _ls=$LINUX_MIN
  _as=$_lift                                                           # an aged low job's cap: the lift, never what division left over
  [ "$_bn" != 0 ] || [ "$_ls" -le "$_as" ] || _as=$_ls                 # ...unless no day-to-day job is running: then its share of the budget
  if [ "$_bl" -gt "$_na" ]; then                                       # the young low ones split what the aged ones leave
    _ls=$(( (AVAIL - _ns * _bn - _as * _na) / (_bl - _na) )); [ "$_ls" -ge "$LINUX_MIN" ] || _ls=$LINUX_MIN
  fi
  _plan=""
  while read -r _c _b _cur _cls _ag; do
    [ -n "$_c" ] || continue
    _lf=-
    case "$_b" in busy|unknown) _cap=$_ns
        if [ "$_cls" != normal ]; then _cap=$_ls; if is_aged "$_b" "$_ag"; then _cap=$_as; _lf=aged; fi; fi ;;
      idle) _cap=$LINUX_MIN ;;
      *) LINUX_OUT="$LINUX_OUT$_c $_cls $_b
"; continue ;; esac
    [ "$_cap" -le "$WANT_VM" ] || WANT_VM=$_cap
    [ "${EM_ON:-0}" != 1 ] || _cap="$LINUX_EMERG_CPUS"          # rung (c)
    if [ -n "$VM_CPUS" ] && gt "$_cap" "$VM_CPUS"; then _cap=$VM_CPUS; fi
    _plan="$_plan$_c $_b $_cur $_cap $_cls $_lf
"
  done <<EOF
$LINUX
EOF
  # Every cut before any raise, so a low job gives its cores up before a normal one takes them.
  _kept=""
  for _pass in cut raise; do
    while read -r _c _b _cur _cap _cls _lf; do
      [ -n "$_c" ] && [ "$_cur" != "$_cap" ] || continue
      _down=raise; { [ "$_cur" = all ] || gt "$_cur" "$_cap"; } && _down=cut
      [ "$_down" = "$_pass" ] || continue
      act "$_c --cpus $_cur -> $_cap$([ "$_lf" != aged ] || echo " (job over ${LIFT_AFTER}s keeps its lift)")" docker update --cpus "$_cap" "$_c" || _kept="$_kept $_c"
    done <<EOF
$_plan
EOF
  done
  while read -r _c _b _cur _cap _cls _lf; do
    [ -n "$_c" ] || continue
    ! in_list "$_c" "$_kept" || _cap=$_cur
    case "$_b" in idle) ;; *) case "$_cap" in all) _cap="${VM_CPUS:-$AVAIL}" ;; esac; CI_CORES=$(( CI_CORES + $(int "$_cap") )) ;; esac
    LINUX_OUT="$LINUX_OUT$_c $_cls $_b cpus=$_cap$([ "$_lf" != aged ] || echo " aged")
"
  done <<EOF
$_plan
EOF
  SLOTS=$(( BUDGET - CI_CORES )); [ "$SLOTS" -ge 1 ] || SLOTS=1
}

# ── the emergency rungs (b) and (d) ─────────────────────────────────────────────────────────────
# A pid is acted on and undone only with the start time it had when recorded, so a recycled pid is left alone.
record() { # <file> <pids> — each pid once
  for _p in $2; do
    [ -f "$1" ] && awk -v p="$_p" '$1 == p { f = 1 } END { exit !f }' "$1" && continue
    printf '%s %s\n' "$_p" "$(lstart "$_p")" >> "$1"
  done
}
replay() { # <file> <cmd…> — run <cmd…> <pid> for every recorded pid whose start time still matches
  _rf="$1"; shift
  [ -f "$_rf" ] || return 0
  while read -r _p _ls; do
    [ -n "$_p" ] || continue
    [ "$(lstart "$_p" | awk '{ $1 = $1; print }')" = "$(printf '%s' "$_ls" | awk '{ $1 = $1; print }')" ] || continue
    "$@" "$_p" >/dev/null 2>&1 || :
  done < "$_rf"
  rm -f "$_rf"
}
slot_pids() { # live slot holders (start time checked), then everything under them
  _roots=""
  for _f in "$STATE_DIR"/slots/*; do
    [ -f "$_f" ] || continue
    _p="${_f##*/}"
    kill -0 "$_p" 2>/dev/null && [ "$(sed -n 2p "$_f")" = "$(lstart "$_p")" ] && _roots="$_roots $_p"
  done
  # shellcheck disable=SC2086  # a pid list, split on purpose
  [ -z "$_roots" ] || descendants $_roots
}
resume_all() { # <why> — rungs (b) and (d) undone
  _n=0; [ -f "$STOPPED" ] && _n="$(wc -l < "$STOPPED" | tr -d ' ')"
  _b=0; [ -f "$BGED" ] && _b="$(wc -l < "$BGED" | tr -d ' ')"
  replay "$STOPPED" kill -CONT
  # A slot that started during the emergency was never recorded; SIGCONT to a running process is a no-op.
  for _p in $(slot_pids); do kill -CONT "$_p" 2>/dev/null || :; done
  replay "$BGED" taskpolicy -B -p
  [ "$_n" = 0 ] || change "$_n local slot process(es) continued ($1)"
  [ "$_b" = 0 ] || change "$_b Mac job process(es) back to normal priority ($1)"
}
ladder() {
  P_APPLIED="$(num_or "$(st emerg_applied)" 0)"
  if [ "${EM_ON:-0}" = 1 ]; then
    [ "$P_APPLIED" = 1 ] || change "EMERGENCY: $EM_WHY"
    # Rung (b): local slots stop, for stop_max at most.
    if [ $(( NOW - EM_SINCE )) -lt "$STOP_MAX" ]; then
      _sp="$(slot_pids | tr '\n' ' ')"
      if [ -n "$(printf '%s' "$_sp" | tr -d ' ')" ]; then
        if [ "$DRY" = 1 ]; then printf 'would: SIGSTOP local slot processes %s\n' "$_sp"
        else
          _first=0; [ -s "$STOPPED" ] || _first=1
          for _p in $_sp; do kill -STOP "$_p" 2>/dev/null || :; done
          record "$STOPPED" "$_sp"
          [ "$_first" = 0 ] || change "$(printf '%s' "$_sp" | wc -w | tr -d ' ') local slot process(es) stopped"
        fi
      fi
    elif [ -s "$STOPPED" ] && [ "$DRY" = 0 ]; then
      _sv="$CHANGES"; CHANGES=""; replay "$STOPPED" kill -CONT
      CHANGES="$_sv"; change "local slots continued: stop_max ${STOP_MAX}s reached, the emergency is not over"
    fi
    # Rung (d): a busy managed Mac job to darwin background; never killed, never stopped.
    _wp="$(managed_worker_pids | tr '\n' ' ')"
    if [ -n "$(printf '%s' "$_wp" | tr -d ' ')" ]; then
      # shellcheck disable=SC2086  # a pid list, split on purpose
      _tree="$_wp $(descendants $_wp | tr '\n' ' ')"
      if [ "$DRY" = 1 ]; then printf 'would: taskpolicy -b -p on the Mac job %s\n' "$_tree"
      else
        _first=0; [ -s "$BGED" ] || _first=1
        for _p in $_tree; do taskpolicy -b -p "$_p" >/dev/null 2>&1 || :; done
        record "$BGED" "$_tree"
        [ "$_first" = 0 ] || change "Mac job to darwin background ($(printf '%s' "$_tree" | wc -w | tr -d ' ') process(es))"
      fi
    fi
    EMERG_APPLIED=1
  else
    if [ "$P_APPLIED" = 1 ]; then
      change "emergency over (clear ${CLEAR_SECS}s)"
      if [ "$DRY" = 1 ]; then printf 'would: SIGCONT the stopped slots and taskpolicy -B the Mac job\n'; else resume_all "emergency over"; fi
    elif [ "$DRY" = 0 ] && { [ -s "$STOPPED" ] || [ -s "$BGED" ]; }; then
      resume_all "no emergency"
    fi
    EMERG_APPLIED=0
  fi
}

logline() { printf '[check:ci-governor] %s %s\n' "$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG" 2>/dev/null || :; }

write_out() {
  _tmp="$STATE.tmp.$$"
  printf 'at=%s\nbudget=%s\ntarget=%s\nmode=%s\nchanged_at=%s\ncut_at=%s\nparked=%s\nslots=%s\nci_cores=%s\nheld=%s\nemerg_applied=%s\nfails=%s\n' \
    "$NOW" "$BUDGET" "$TARGET" "$MODE" "$CHANGED_AT" "$CUT_AT" "$(printf '%s' "$PARKED" | tr ' ' ',')" "$SLOTS" "$CI_CORES" "$HELD" "$EMERG_APPLIED" \
    "$(printf '%s' "$FAILS" | tr '\n=' '  ')" > "$_tmp" && mv -f "$_tmp" "$STATE"
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --argjson at "$NOW" --argjson budget "$BUDGET" --argjson target "$TARGET" --arg mode "$MODE" \
    --arg load "${LOAD1:-}" --arg idle "${IDLE_S:-}" --argjson slots "$SLOTS" --argjson ci "$CI_CORES" \
    --arg parked "$PARKED" --arg reason "$REASON" --arg linux "$LINUX_OUT" --arg mac "$MAC" --arg vm "${VM_CPUS:-}" \
    --argjson em "${EMERG_APPLIED:-0}" --arg emwhy "${EM_WHY:-}" --arg lpid "$(kv_pid "$LISTENER")" \
    '{at: $at, budget: $budget, target: $target, mode: $mode, held: ($budget < $target),
      emergency: ($em == 1), emergency_why: (if $em == 1 then $emwhy else null end),
      listener_pid: (if $lpid == "" then null else ($lpid | tonumber) end),
      load1: (if $load == "" then null else ($load | tonumber) end), idle_s: (if $idle == "" then null else ($idle | tonumber) end),
      slots: $slots, ci_cores: $ci, vm_cpus: (if $vm == "" then null else ($vm | tonumber) end), reason: $reason,
      parked: ($parked | split(" ") | map(select(. != ""))),
      linux: ($linux | split("\n") | map(select(. != ""))), mac: ($mac | split("\n") | map(select(. != ""))),
      runners: ($linux | split("\n") | map(select(. != "") | split(" ")
        | {name: .[0], class: .[1], state: .[2], cpus: ((.[3] // "") | ltrimstr("cpus=") | tonumber? // null)}))}' \
    > "$OUT.tmp.$$" 2>/dev/null || { rm -f "$OUT.tmp.$$"; return 0; }
  mv -f "$OUT.tmp.$$" "$OUT"
}

# One tick at a time: an event, the sampler and `run` may all ask at once. A tick that cannot get the lock
# in 5s is skipped; the one holding it sees the same state.
tick_lock() {
  _tw=0
  while ! mkdir "$STATE_DIR/tick.lock" 2>/dev/null; do
    _tl="$(cat "$STATE_DIR/tick.lock/pid" 2>/dev/null || true)"
    # Re-read before taking over: a lock released and re-taken since the first read is a live one (as event-bus.sh).
    if [ -n "$_tl" ] && ! kill -0 "$_tl" 2>/dev/null && [ "$(cat "$STATE_DIR/tick.lock/pid" 2>/dev/null || true)" = "$_tl" ]; then
      rm -rf "$STATE_DIR/tick.lock"; continue
    fi
    _tw=$(( _tw + 1 )); [ "$_tw" -lt 25 ] || return 1
    sleep 0.2
  done
  echo $$ > "$STATE_DIR/tick.lock/pid"
}
tick_unlock() { rm -rf "$STATE_DIR/tick.lock"; }

cmd_tick() {
  DRY=0
  case "${1:-}" in --dry-run) DRY=1 ;; '') ;; *) log_fail "unknown option $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;; esac
  if [ "$DRY" = 0 ]; then mkdir -p "$STATE_DIR/slots" "$CACHE_DIR"; tick_lock || return 0; fi
  CHANGES=""; FAILS=""; NOW="$(now)"
  signals; emergency_state; decide; probe; allocate; ladder
  # Cores are held while any CI job runs here or a local slot is taken: the only time the sampler runs.
  HELD=0; [ "$CI_CORES" -eq 0 ] || HELD=1
  [ -z "$(find "$STATE_DIR/slots" -type f 2>/dev/null | head -1)" ] || HELD=1
  if [ "$DRY" = 1 ]; then
    printf 'budget %s -> %s (target %s, %s; %s)\n' "${P_BUDGET:-none}" "$BUDGET" "$TARGET" "$MODE" "${REASON:-hold}"
    printf 'local slots %s (CI holds %s cores)\n' "$SLOTS" "$CI_CORES"
    [ -z "$CHANGES" ] || printf 'change: %s\n' "$CHANGES"
    printf 'cores held: %s\n' "$([ "$CI_CORES" -gt 0 ] && echo yes || echo no)"
    return 0
  fi
  _msg=""
  [ "$BUDGET" = "$P_BUDGET" ] || _msg="budget ${P_BUDGET:-none} -> $BUDGET ($REASON)"
  [ -z "$CHANGES" ] || _msg="${_msg:+$_msg; }$CHANGES"
  # A failure is said once, on the way in, never on every tick of a standing outage.
  _pf="$(st fails)"
  if [ -n "$FAILS" ] && [ "$(printf '%s' "$FAILS" | tr '\n=' '  ')" != "$_pf" ]; then
    _msg="${_msg:+$_msg; }WARN $FAILS"
    log_warn "$FAILS"; log_fix "sh $0 status"; log_end || :
  fi
  [ -z "$_msg" ] || logline "$_msg"
  write_out
  tick_unlock
}

cmd_status() {
  DRY=1; NO_GH=1
  signals
  _at="$(st at)"
  printf 'signals   idle %ss (%s; idle after %ss), load1 %s (ceiling %s, raise below %s), %s cores\n' \
    "${IDLE_S:-?}" "$MODE" "$IDLE_AFTER" "${LOAD1:-?}" "$LOAD_CEILING" "$RAISE_BELOW" "${NCPU:-?}"
  if [ -n "$_at" ]; then
    printf 'budget    %s of target %s (last tick %ss ago; last change %ss ago)\n' "$(st budget)" "$(st target)" \
      "$(( NOW - $(num_or "$_at" "$NOW") ))" "$(( NOW - $(num_or "$(st changed_at)" "$NOW") ))"
  else
    printf 'budget    none: no tick has run (%s)\n' "$STATE"
  fi
  printf 'events    listener %s, sampler %s, trigger %s\n' "$(alive "$LISTENER" && echo "running (pid $(kv_pid "$LISTENER"))" || echo "NOT running")" \
    "$(alive "$SAMPLER" && echo running || echo idle)" "$TRIGGER"
  emergency_state
  if [ -f "$EMERG" ]; then
    printf 'emergency %s%s (last sample: cpu %s%%, memory pressure %s, thermal %s)\n' "$([ "$EM_ON" = 1 ] && echo ON || echo off)" \
      "${EM_WHY:+: $EM_WHY}" "$(ek cpu)" "$(ek mem)" "$(ek therm | sed 's/^$/none/')"
  else printf 'emergency off (no sample yet: the sampler runs only while cores are held)\n'; fi
  decide; probe
  printf 'next tick budget %s -> %s (%s)\n' "${P_BUDGET:-none}" "$BUDGET" "${REASON:-hold}"
  allocate
  printf 'runners   busy on this host: %s\n' "$(printf '%s' "${WORKERS:-none}" | awk '{ $1 = $1; print }')"
  printf '%s' "$MAC" | sed 's/^/          /'
  printf 'linux     %s container(s), %s; low priority: %s\n' "$(printf '%s' "$LINUX_RUNNERS" | wc -w | tr -d ' ')" \
    "$([ -n "$LINUX_LIST" ] && echo "listed in linux_runners" || echo "discovered (*-linux, actions-runner image)")" "$LOW_PRIORITY"
  printf '%s' "$LINUX_OUT" | sed 's/^/          /'
  printf '          colima VM cpus: %s\n' "${VM_CPUS:-unread}"
  if [ -n "$VM_CPUS" ] && [ "$WANT_VM" -gt "$VM_CPUS" ]; then
    printf '          the budget would give a Linux runner %s cpus; the VM has %s (resize while it is idle: colima start --cpu %s)\n' \
      "$WANT_VM" "$VM_CPUS" "$IDLE_BUDGET"
  fi
  _used=0; [ -d "$STATE_DIR/slots" ] && _used="$(find "$STATE_DIR/slots" -type f | wc -l | tr -d ' ')"
  _sl="$(st slots)"; _sc="$(st ci_cores)"
  printf 'slots     %s in use of %s (CI holds %s cores at the last tick)\n' "$_used" "${_sl:-none yet}" "${_sc:-?}"
  [ -d "$STATE_DIR/slots" ] && find "$STATE_DIR/slots" -type f -exec sh -c 'for f; do printf "          pid %s  %s\n" "${f##*/}" "$(sed -n 3p "$f")"; done' _ {} +
  return 0
}

# ── run: one local slot per command ─────────────────────────────────────────────────────────────
lstart() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' || true; }
reclaim() {
  for _f in "$STATE_DIR"/slots/*; do
    [ -f "$_f" ] || continue
    _p="${_f##*/}"
    if ! kill -0 "$_p" 2>/dev/null || [ "$(sed -n 2p "$_f")" != "$(lstart "$_p")" ]; then rm -f "$_f"; fi
  done
}
lock() {
  if mkdir "$STATE_DIR/slots.lock" 2>/dev/null; then echo $$ > "$STATE_DIR/slots.lock/pid"; return 0; fi
  _lp="$(cat "$STATE_DIR/slots.lock/pid" 2>/dev/null || true)"
  if [ -n "$_lp" ] && ! kill -0 "$_lp" 2>/dev/null && [ "$(cat "$STATE_DIR/slots.lock/pid" 2>/dev/null || true)" = "$_lp" ]; then
    rm -rf "$STATE_DIR/slots.lock"
  fi
  return 1
}
unlock() { rm -rf "$STATE_DIR/slots.lock"; }
post() { notifyutil -p "$EVENT_KEY" >/dev/null 2>&1 || :; }
limit() {
  _a="$(num_or "$(st at)" 0)"
  # An event-driven governor may not have ticked for hours: a stale state is decided now, not trusted.
  if [ $(( NOW - _a )) -gt "$STALE_AFTER" ]; then ( cmd_tick ) >/dev/null 2>&1 || :; NOW="$(now)"; _a="$(num_or "$(st at)" 0)"; fi
  _s="$(num_or "$(st slots)" "")"
  if [ -n "$_s" ] && [ $(( NOW - _a )) -le "$STALE_AFTER" ]; then LIMIT="$_s"; LIMIT_WHY="budget $(st budget), CI holds $(st ci_cores) cores"
  else LIMIT=$(( ACTIVE_BUDGET / 2 )); [ "$LIMIT" -ge 1 ] || LIMIT=1; LIMIT_WHY="no fresh tick, so a fallback of $LIMIT"; fi
}

cmd_run() {
  _out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) [ $# -ge 2 ] || { log_fail "--out needs a file"; log_fix "sh $0 --help"; log_end || :; exit 2; }; _out="$2"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { log_fail "run needs a command"; log_fix "sh $0 run -- <cmd…>"; log_end || :; exit 2; }
  if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${HARBOR_GOV_SLOT:-}" ] || [ ! -d "$STATE_DIR" ]; then
    if [ -n "$_out" ]; then exec "$@" > "$_out" 2>&1; else exec "$@"; fi
  fi
  mkdir -p "$STATE_DIR/slots" 2>/dev/null || :
  # A state dir it cannot write (the confinement denies ~/.claude, harbor#555) never yields the lock, and the deadline
  # is read only under it: the command waited forever. A throttle, not a gate: run it now, and say so.
  if ! { printf "" > "$STATE_DIR/.w.$$"; } 2>/dev/null; then
    printf 'ci-governor: %s is not writable here, so this runs without a slot\n' "$STATE_DIR" >&2
    if [ -n "$_out" ]; then exec "$@" > "$_out" 2>&1; else exec "$@"; fi
  fi
  rm -f "$STATE_DIR/.w.$$"
  _t0="$(date +%s)"; _said=""
  take() { printf '%s\n%s\n%s\n' "$$" "$(lstart $$)" "$*" > "$STATE_DIR/slots/$$" 2>/dev/null || :; unlock; }
  while :; do
    if lock; then
      reclaim; limit
      _used="$(find "$STATE_DIR/slots" -type f 2>/dev/null | wc -l | tr -d ' ')"
      if [ "$_used" -lt "$LIMIT" ]; then take "$@"; break; fi
      _el=$(( $(date +%s) - _t0 ))
      # Any wait is said, even one the deadline ends at once; then every 60s.
      if [ -z "$_said" ] || [ $(( _el - _said )) -ge 60 ]; then
        # An --out caller prints its own status line without a newline (pre-push's `run X … ok`): break it first.
        [ -n "$_said" ] || [ -z "$_out" ] || printf '\n' >&2
        printf 'ci-governor: waiting for a CPU slot: %s of %s in use (%s); runs anyway in %ss\n' \
          "$_used" "$LIMIT" "$LIMIT_WHY" "$(( RUN_DEADLINE - _el ))" >&2
        _said=$_el
      fi
      if [ "$_el" -ge "$RUN_DEADLINE" ]; then
        printf 'ci-governor: waited %ss, the deadline; running over budget (%s of %s slots in use)\n' "$_el" "$_used" "$LIMIT" >&2
        take "$@"; break
      fi
      unlock
    fi
    sleep "${HARBOR_GOV_POLL:-3}"
  done
  post   # a slot is held: the governor decides, and samples while it is
  trap 'rm -f "$STATE_DIR/slots/$$"; post' EXIT
  trap 'rm -f "$STATE_DIR/slots/$$"; post; exit 130' INT TERM HUP
  HARBOR_GOV_SLOT=$$; export HARBOR_GOV_SLOT
  if [ -n "$_out" ]; then
    if "$@" > "$_out" 2>&1; then _rc=0; else _rc=$?; fi
  else
    if "$@"; then _rc=0; else _rc=$?; fi
  fi
  exit "$_rc"
}

cmd_resume() {
  DRY=0; CHANGES=""; NOW="$(now)"
  resume_all "resumed by hand"
  [ -z "$CHANGES" ] || logline "$CHANGES"
  printf '%s\n' "${CHANGES:-nothing was stopped or backgrounded}"
}

# One wake-up: a sample (unless the sampler is already sampling), a tick, and the sampler if cores are held.
cmd_event() {
  mkdir -p "$STATE_DIR/slots" "$CACHE_DIR"
  NOW="$(now)"
  if alive "$SAMPLER"; then cmd_tick; else cmd_sample; [ "$TICKED" = 1 ] || cmd_tick; fi
  if [ "$(st held)" = 1 ] || [ "$(ek on)" = 1 ]; then
    alive "$SAMPLER" || { nohup sh "$0" sampler >/dev/null 2>&1 & }
  fi
  return 0
}

# Samples every sample_interval and ticks every tick_interval while cores are held or an emergency is on,
# then exits: the only loop in the governor, and it does not outlive the work.
cmd_sampler() {
  mkdir -p "$STATE_DIR/slots" "$CACHE_DIR"
  alive "$SAMPLER" && exit 0
  pidfile "$SAMPLER"
  trap 'DRY=0; CHANGES=""; resume_all "the sampler stopped"; [ -z "$CHANGES" ] || logline "$CHANGES"; rm -f "$SAMPLER"; exit 0' TERM INT HUP
  LAST_TICK="$(num_or "$(st at)" 0)"
  while :; do
    cmd_sample
    NOW="$(now)"
    if [ $(( NOW - LAST_TICK )) -ge "$TICK_INTERVAL" ]; then cmd_tick; LAST_TICK="$NOW"; fi
    [ "$(st held)" = 1 ] || [ "$EM_ON" = 1 ] || break
    sleep "$SAMPLE_INTERVAL"
  done
  rm -f "$SAMPLER"
}

# A container job's trigger line becomes ci.job.start or ci.job.done on the event bus (harbor#1367, contracts/event-kinds.tsv),
# detached so the bus never delays a decision. An old three-field line, or one with an odd field, publishes nothing.
publish_job() { # <trigger line>
  [ -f "$HERE/event-bus.sh" ] || return 0
  # The group's stdin is the line: a `</dev/null` on it would replace the pipe, and read would see nothing.
  printf '%s\n' "$1" | {
    read -r _ts _run _job _ph _repo _rest || exit 0
    case "$_ph" in start) _kind=ci.job.start ;; done) _kind=ci.job.done ;; *) exit 0 ;; esac
    case "$_run$_job$_repo" in *[!A-Za-z0-9._/-]*) exit 0 ;; esac
    case "$_repo" in */*) ;; *) exit 0 ;; esac
    sh "$HERE/event-bus.sh" emit "$_kind" "$_repo:$_run:$_job" --src ci-governor --repo "${_repo##*/}" \
      --data "{\"run_id\":\"$_run\",\"job\":\"$_job\",\"repo\":\"$_repo\"}" </dev/null
  } >/dev/null 2>&1 &
}

# What launchd keeps alive. Two blocking streams into one FIFO; the read below is the only wait.
cmd_listen() {
  mkdir -p "$STATE_DIR/slots" "$CACHE_DIR"
  alive "$LISTENER" && { log_fail "a listener already runs"; log_fix "sh $0 status"; log_end || :; exit 2; }
  pidfile "$LISTENER"
  [ -f "$TRIGGER" ] || { mkdir -p "$(dirname "$TRIGGER")" && : > "$TRIGGER"; } 2>/dev/null || :
  _fifo="$STATE_DIR/events.fifo"; rm -f "$_fifo"; mkfifo "$_fifo"
  _np=""; _tp=""
  # shellcheck disable=SC2046,SC2086  # the key list, split on purpose
  notifyutil -w "$EVENT_KEY" $(for _k in $OS_KEYS; do printf ' -w %s' "$_k"; done) > "$_fifo" 2>/dev/null & _np=$!
  if [ -f "$TRIGGER" ]; then tail -n0 -f "$TRIGGER" > "$_fifo" 2>/dev/null & _tp=$!; fi
  trap 'kill $_np $_tp 2>/dev/null; _sp="$(kv_pid "$SAMPLER")"; [ -z "$_sp" ] || kill "$_sp" 2>/dev/null; DRY=0; CHANGES=""; resume_all "the governor stopped"; [ -z "$CHANGES" ] || logline "$CHANGES"; rm -f "$LISTENER" "$_fifo"; exit 0' TERM INT HUP
  sh "$0" event start || :
  exec 3< "$_fifo"
  while read -r _line <&3; do
    case " $_line " in *" $EVENT_KEY "*|*" com.apple.system."*|*" kern.memorystatus"*) _what="notify" ;; *) _what="trigger" ;; esac
    [ "$_what" != trigger ] || publish_job "$_line"
    sh "$0" event "$_what" || :
  done
  kill $_np $_tp 2>/dev/null || :
}

case "${1:-}" in
  listen) cmd_listen ;;
  event) cmd_event ;;
  sampler) cmd_sampler ;;
  sample) shift; cmd_sample "$@" ;;
  resume) cmd_resume ;;
  tick) shift; cmd_tick "$@" ;;
  status) cmd_status ;;
  run) shift; cmd_run "$@" ;;
  -h|--help|'') usage; exit 0 ;;
  *) log_fail "unknown command $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
