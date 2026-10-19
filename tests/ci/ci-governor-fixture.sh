#!/usr/bin/env sh
# tests/ci/ci-governor-fixture.sh — what both ci-governor suites share (harbor#1032, harbor#817's budget).
# Source after t_init: the PATH shims for ioreg, sysctl, pgrep, docker, gh and a fake runners dir whose
# svc.sh only records, then reset() and the gov/tick helpers. Nothing real is touched.
FX="$T_TMP/fx"; CACHE="$T_TMP/cache"; RUNNERS="$T_TMP/runners"; GOV="$T_ROOT/bin/ci-governor.sh"
export FX
HARBOR_GOV_TRIGGER="$FX/trigger"; export HARBOR_GOV_TRIGGER
unset GITHUB_ACTIONS   # CI sets it, and run would then (rightly) take no slot
mkdir -p "$FX" "$CACHE" "$RUNNERS/harbor-mac"

# ── shims ───────────────────────────────────────────────────────────────────────────────────────
# What the runner container has on its PATH: a pgrep that is busy/idle from <c>.lbusy (or fails with the code in <c>.execrc:
# 127 = missing, 2 = erroring), and a ps that prints the job's age from <c>.age. harbor-linux's files have no prefix.
INBIN="$T_TMP/inbin"; export INBIN; mkdir -p "$INBIN"
cat > "$INBIN/pgrep" <<'EOF'
#!/bin/sh
f() { if [ "$FXC" = harbor-linux ]; then printf '%s/%s' "$FX" "$1"; else printf '%s/%s.%s' "$FX" "$FXC" "$1"; fi; }
[ ! -f "$(f execrc)" ] || exit "$(cat "$(f execrc)")"
[ -f "$(f lbusy)" ] || exit 1
echo 4242
EOF
cat > "$INBIN/ps" <<'EOF'
#!/bin/sh
f() { if [ "$FXC" = harbor-linux ]; then printf '%s/%s' "$FX" "$1"; else printf '%s/%s.%s' "$FX" "$FXC" "$1"; fi; }
[ ! -f "$(f age)" ] || cat "$(f age)"
EOF
chmod +x "$INBIN/pgrep" "$INBIN/ps"
cat > "$T_BIN/ioreg" <<'EOF'
#!/bin/sh
printf '    | |   "HIDIdleTime" = %s000000000\n' "$(cat "$FX/idle")"
EOF
cat > "$T_BIN/sysctl" <<'EOF'
#!/bin/sh
case "$*" in
  "-n vm.loadavg") printf '{ %s 1.00 1.00 }\n' "$(cat "$FX/load")" ;;
  "-n hw.ncpu") echo 10 ;;
  "-n kern.memorystatus_vm_pressure_level") cat "$FX/mem" ;;
  *) exit 1 ;;
esac
EOF
# pgrep -lf <regex>: the matching lines of the fake process table.
cat > "$T_BIN/pgrep" <<'EOF'
#!/bin/sh
[ "$1" = -lf ] || exit 3
awk -v re="$2" '$0 ~ re { print; n++ } END { exit n ? 0 : 1 }' "$FX/procs"
EOF
# docker: `ps` lists $FX/ps ("<name> <image source label>"); harbor-linux reads $FX/{lrun,nano,lbusy,age}, any
# other container <c> $FX/<c>.{nano,lbusy,age} (running; age = the Runner.Worker's seconds, as `ps -o etimes=` prints). Every update is also "<c> <cpus>" in $FX/updates.log.
cat > "$T_BIN/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "$FX/docker.calls"
[ -f "$FX/docker.down" ] && exit 1
f() { if [ "$1" = harbor-linux ]; then printf '%s/%s' "$FX" "$2"; else printf '%s/%s.%s' "$FX" "$1" "$2"; fi; }
case "$1" in
  info) cat "$FX/vmcpus" ;;
  ps) cat "$FX/ps" ;;
  inspect) [ -f "$(f "$4" nano)" ] || exit 1
           r=true; [ "$4" != harbor-linux ] || r="$(cat "$FX/lrun")"; printf '%s %s\n' "$r" "$(cat "$(f "$4" nano)")" ;;
  exec) c="$2"; shift 2   # the real in-container script runs, against a fake pgrep and ps that answer from $FX (see $INBIN)
         FXC="$c" PATH="$INBIN:$PATH" "$@" ;;
  update) [ -f "$FX/update.fail" ] && exit 1
          echo "$3" >> "$FX/updates"; echo "$4 $3" >> "$FX/updates.log"
          awk -v c="$3" 'BEGIN { printf "%d\n", c * 1000000000 }' > "$(f "$4" nano)" ;;
  *) exit 1 ;;
esac
EOF
# iostat -n0 -c 2 -w 1: the since-boot line, then the 1s sample whose idle is 100 minus $FX/cpu.
cat > "$T_BIN/iostat" <<'EOF'
#!/bin/sh
echo x >> "$FX/iostat.calls"
printf '      cpu    load average\n us sy id   1m   5m   15m\n 10 10 80  1.00 1.00 1.00\n'
b="$(cat "$FX/cpu")"; printf ' %d 0 %d  1.00 1.00 1.00\n' "$b" "$((100 - b))"
EOF
cat > "$T_BIN/pmset" <<'EOF'
#!/bin/sh
if [ -f "$FX/therm" ]; then cat "$FX/therm"; else
  printf 'Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded\nNote: No CPU power status has been recorded\n'; fi
EOF
cat > "$T_BIN/notifyutil" <<'EOF'
#!/bin/sh
case "$1" in
  -p) echo "$2" >> "$FX/posts"; echo "$2" >> "$FX/notify.stream" ;;
  -w) k=" "; while [ "${1:-}" = -w ]; do k="$k$2 "; shift 2; done   # only the keys registered, as notifyd does
      # From the stream's size NOW, marked: a post after the marker is never missed (a fixed sleep raced under CI load).
      o=$(( $(wc -c < "$FX/notify.stream") + 1 )); : > "$FX/notify.waiting"
      # The real notifyutil is one process; this fake is a pipeline, so a kill of it must reach its children
      # or every listen test leaves a tail and an awk running forever.
      tail -c +"$o" -f "$FX/notify.stream" | awk -v k="$k" 'index(k, " " $0 " ") { print; fflush() }' &
      trap 'pkill -P $$ 2>/dev/null; exit 0' TERM INT HUP
      wait ;;
  *) exit 1 ;;
esac
EOF
cat > "$T_BIN/taskpolicy" <<'EOF'
#!/bin/sh
echo "$*" >> "$FX/taskpolicy.log"
EOF
# gh api: the runners list answers $FX/ghbusy; the runs lists and each run's jobs answer from the JSON that
# ghjob writes (empty when none declared), filtered by the caller's own --jq. $FX/gh.fail fails every call,
# $FX/jobs.fail only the jobs calls.
cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$FX/gh.calls"
[ -f "$FX/gh.fail" ] && exit 1
q=""; prev=""; for a; do [ "$prev" = --jq ] && q="$a"; prev="$a"; done
case "$2" in
  */actions/runners*) cat "$FX/ghbusy" ;;
  */actions/runs\?status=*) f="${2##*status=}"; f="$FX/runs.${f%%&*}"
    [ -f "$f" ] || echo '{"workflow_runs":[]}' > "$f"; jq -r "${q:-.}" "$f" ;;
  */actions/runs/*/jobs*) [ ! -f "$FX/jobs.fail" ] || exit 1
    f="${2#*/runs/}"; f="$FX/jobs.${f%%/*}"
    [ -f "$f" ] || echo '{"jobs":[]}' > "$f"; jq -r "${q:-.}" "$f" ;;
  *) exit 1 ;;
esac
EOF
cat > "$RUNNERS/harbor-mac/svc.sh" <<'EOF'
#!/bin/sh
echo "$1" >> "$FX/svc.log"
case "$1" in
  stop) grep -v 'harbor-mac/bin/Runner.Listener' "$FX/procs" > "$FX/procs.n"; mv "$FX/procs.n" "$FX/procs" ;;
  start) echo "72550 /x/runners/harbor-mac/bin/Runner.Listener run" >> "$FX/procs" ;;
esac
EOF
chmod +x "$T_BIN"/* "$RUNNERS/harbor-mac/svc.sh"

MACL="72550 /x/runners/harbor-mac/bin/Runner.Listener run --startuptype service"
GTML="72780 /x/runners/other-mac/bin/Runner.Listener run --startuptype service"
MACW="80001 /x/runners/harbor-mac/bin.2.337.0/Runner.Worker spawnclient 3 4"
GTMW="80002 /x/runners/other-mac/bin.2.337.0/Runner.Worker spawnclient 5 6"
T0=1790000000; AT=$T0
RL=https://github.com/actions/runner   # the actions-runner image's org.opencontainers.image.source
reset() {
  rm -rf "$FX" "$CACHE" "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; mkdir -p "$FX" "$CACHE"
  echo 30 > "$FX/idle"; echo 2.00 > "$FX/load"; echo 10 > "$FX/cpu"; echo 1 > "$FX/mem"; : > "$FX/notify.stream"; : > "$FX/trigger"; echo 8 > "$FX/vmcpus"; echo true > "$FX/lrun"
  echo 2000000000 > "$FX/nano"; echo false > "$FX/ghbusy"; printf '%s\n%s\n' "$MACL" "$GTML" > "$FX/procs"
  echo "harbor-linux $RL" > "$FX/ps"; printf 'mac_runners=harbor-mac\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
  AT=$T0
}
# ctr <name> [busy] — one more running runner container, discovered by `docker ps`, at 2 cpus.
ctr() { echo "$1 $RL" >> "$FX/ps"; echo 2000000000 > "$FX/$1.nano"; [ -z "${2:-}" ] || : > "$FX/$1.lbusy"; }
ccpus() { if [ "$1" = harbor-linux ]; then cpus; else echo $(( $(cat "$FX/$1.nano") / 1000000000 )); fi; }
# ghjob <run id> <run status: queued|in_progress> <job status> <labels, comma-separated> — one job GitHub reports.
ghjob() {
  [ -f "$FX/runs.$2" ] || echo '{"workflow_runs":[]}' > "$FX/runs.$2"
  jq --argjson i "$1" 'if any(.workflow_runs[]; .id == $i) then . else .workflow_runs += [{id: $i}] end' "$FX/runs.$2" > "$FX/x" && mv "$FX/x" "$FX/runs.$2"
  [ -f "$FX/jobs.$1" ] || echo '{"jobs":[]}' > "$FX/jobs.$1"
  jq --arg s "$3" --arg l "$4" '.jobs += [{id: (.jobs | length + 1), status: $s, labels: ($l | split(","))}]' "$FX/jobs.$1" > "$FX/x" && mv "$FX/x" "$FX/jobs.$1"
}
gov() { HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" "$@" 2>&1; }
tick() { AT=$((AT + ${1:-30})); gov tick >/dev/null; }
st() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print }' "$CACHE/ci-governor/state"; }
cpus() { echo $(( $(cat "$FX/nano") / 1000000000 )); }
nlog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:ci-governor' "$CACHE/checks.log"; else echo 0; fi; }
nsvc() { if [ -f "$FX/svc.log" ]; then grep -c "$1" "$FX/svc.log"; else echo 0; fi; }
ngh() { if [ -f "$FX/gh.calls" ]; then grep -c "$1" "$FX/gh.calls"; else echo 0; fi; }
nupd() { if [ -f "$FX/updates" ]; then wc -l < "$FX/updates" | tr -d ' '; else echo 0; fi; }
SD="$CACHE/ci-governor"
