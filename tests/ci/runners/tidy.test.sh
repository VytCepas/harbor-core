#!/usr/bin/env sh
# tidy.test.sh (harbor#1060) — bin/ci-runners.sh tidy and the json-file log cap (check ci.runner-tidy, operator decision 2026-11-23): the log cap on every container
# create makes, and the weekly tidy run for real against fake runner homes through the stubbed docker and colima: what is always removed,
# what only an idle runner loses, a metered network, the dry default, the Sunday 04:00 --if-due gate, fstrim and the MB freed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
export TZ=UTC
COLIMA="$T_TMP/colima"
cat > "$COLIMA" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/colima.log"
[ ! -f "$FX/colima.fail" ] || { echo "colima is not running" >&2; exit 1; }
[ "$1 $2 $3" = "ssh -- sudo" ] || { echo "UNEXPECTED colima call: $*" >> "$FX/unexpected.log"; exit 1; }
shift 3
case "$1" in
  stat) id="$(basename "$(dirname "$4")")"; [ -f "$FX/logsize.$id" ] && cat "$FX/logsize.$id" || exit 1 ;;
  truncate) [ ! -f "$FX/truncate.fail" ] || exit 1; id="$(basename "$(dirname "$4")")"; echo 0 > "$FX/logsize.$id" ;;
  fstrim) [ ! -f "$FX/fstrim.fail" ] || { echo "fstrim: the discard operation is not supported" >&2; exit 1; }
          dd if=/dev/zero of="$FX/datadisk" bs=1024 count=1024 2>/dev/null; echo "/var/lib/docker: 3 MiB (3145728 bytes) trimmed" ;;
  *) echo "UNEXPECTED colima call: $*" >> "$FX/unexpected.log"; exit 1 ;;
esac
STUB
chmod +x "$COLIMA"
export HARBOR_CI_COLIMA="$COLIMA" HARBOR_CI_DATADISK="$FX/datadisk" HARBOR_STATUS_DIR="$FX/state"
OLD=202001010000
# home <container> — a runner's home: live bin/externals (2.2.0) and superseded ones (2.1.0), update staging, old and new diag logs,
# the caches, and files that must survive anything tidy does (a checkout under _work, the runner's config)
home() {
  h="$FX/home.$1"; rm -rf "$h"
  mkdir -p "$h/bin.2.1.0" "$h/bin.2.2.0" "$h/externals.2.1.0" "$h/externals.2.2.0" "$h/_work/_update/x" "$h/_work/_tool/node" "$h/_work/repo" \
           "$h/_diag/pages" "$h/.cache/uv" "$h/.npm/_cacache" "$h/.bun/install/cache"
  ln -s bin.2.2.0 "$h/bin"; ln -s externals.2.2.0 "$h/externals"
  : > "$h/_work/_update.sh"; : > "$h/_work/_update/x/pkg"; : > "$h/_work/_tool/node/n"; : > "$h/.cache/uv/c"; : > "$h/.npm/_cacache/c"; : > "$h/.bun/install/cache/c"
  : > "$h/_diag/old.log"; : > "$h/_diag/pages/old2.log"; : > "$h/_diag/new.log"; : > "$h/_work/repo/keep.txt"; : > "$h/.runner"; : > "$h/bin.2.2.0/Runner.Listener"
  touch -t $OLD "$h/_work/_update.sh" "$h/_work/_update/x/pkg" "$h/_work/_update/x" "$h/_work/_update" "$h/_diag/old.log" "$h/_diag/pages/old2.log"
}
# tidyfx — the state tidy reads: one running runner, a home, a json log of the size given, the datadisk 4 MB
tidyfx() { # [log-size-bytes]
  reset; rm -rf "$FX"/home.* "$FX"/logsize.* "$FX"/logpath.* "$FX/state" "$FX"/*.fail "$FX"/exec.fail.* "$FX/ps.calls" "$CACHE/ci-runner-tidy.stamp"
  mkdir -p "$FX/state/net"
  container alpha-linux port-linux-runner:local running; home alpha-linux
  echo /var/lib/docker/containers/abc123/abc123-json.log > "$FX/logpath.alpha-linux"; echo "${1:-3000000000}" > "$FX/logsize.abc123"
  dd if=/dev/zero of="$FX/datadisk" bs=1024 count=4096 2>/dev/null
}
has() { [ -e "$FX/home.alpha-linux/$1" ] || [ -L "$FX/home.alpha-linux/$1" ] && echo yes || echo no; }
DAY=1795339800   # Sunday 2026-11-22 09:30 UTC

t_section "the log cap: every container create makes is created with it"
reset; run up --apply >/dev/null
RUNLINE="$(grep '^run -d' "$FX/docker.log" | head -n 1)"
t_has "the default cap is 20m" "$RUNLINE" "--log-opt max-size=20m"
t_has "...over 2 files" "$RUNLINE" "--log-opt max-file=2"
reset; printf 'logsize 50m\nlogfiles 5\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run up --apply >/dev/null
RUNLINE="$(grep '^run -d' "$FX/docker.log" | head -n 1)"
t_has "the config's logsize is the cap" "$RUNLINE" "max-size=50m"
t_has "...and its logfiles the count" "$RUNLINE" "max-file=5"
reset; printf 'logsize 50m\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
( export HARBOR_CI_LOG_SIZE=7g HARBOR_CI_LOG_FILES=3; run up --apply >/dev/null )
RUNLINE="$(grep '^run -d' "$FX/docker.log" | head -n 1)"
t_has "the environment outranks the config: size" "$RUNLINE" "max-size=7g"
t_has "...and count" "$RUNLINE" "max-file=3"
reset; printf 'logsize lots\nlogfiles 0\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run up --apply >/dev/null
RUNLINE="$(grep '^run -d' "$FX/docker.log" | head -n 1)"
t_has "a size that is not N[kmg] falls back to 20m" "$RUNLINE" "max-size=20m"
t_has "a count that is not 1-99 falls back to 2" "$RUNLINE" "max-file=2"

t_section "tidy: dry by default, and it says what it would do"
tidyfx; OUT="$(run tidy)"
t_has "a dry run names the runner and what it would remove" "$OUT" "alpha-linux: would remove, update=2 versions=2 diag=2 caches=4"
t_has "...the log it would truncate" "$OUT" "would truncate alpha-linux's json log: 2861 MB over the 20m cap"
t_has "...and says how to act" "$OUT" "dry run: pass --apply"
t_eq "a dry run removed no superseded dir" yes "$(has bin.2.1.0)"
t_eq "...no staging" yes "$(has _work/_update)"
t_eq "...no cache" yes "$(has .cache)"
t_eq "...no diag log" yes "$(has _diag/old.log)"
t_eq "...and no log was truncated" 3000000000 "$(cat "$FX/logsize.abc123")"
t_eq "...no fstrim" 0 "$(grep -c fstrim "$FX/colima.log" || true)"
t_eq "...no stamp" no "$([ -e "$CACHE/ci-runner-tidy.stamp" ] && echo yes || echo no)"
t_eq "...no checks.log line" 0 "$(nlines "$CACHE/checks.log")"

t_section "tidy --apply: the always-safe set goes, the caches go from an idle runner"
tidyfx; OUT="$(run tidy --apply)"; RC=$?
t_eq "exit 0" 0 "$RC"
t_eq "the superseded bin dir is gone" no "$(has bin.2.1.0)"
t_eq "...and the superseded externals dir" no "$(has externals.2.1.0)"
t_eq "the live bin dir stays" yes "$(has bin.2.2.0)"
t_eq "...and the live externals dir" yes "$(has externals.2.2.0)"
t_eq "...and both symlinks" yes "$([ -L "$FX/home.alpha-linux/bin" ] && [ -L "$FX/home.alpha-linux/externals" ] && echo yes)"
t_eq "the update staging is gone" no "$(has _work/_update)"
t_eq "...and the update script" no "$(has _work/_update.sh)"
t_eq "a diag log over 3 days old is gone" no "$(has _diag/old.log)"
t_eq "...in the pages directory too" no "$(has _diag/pages/old2.log)"
t_eq "a recent diag log stays" yes "$(has _diag/new.log)"
t_eq ".cache is gone" no "$(has .cache)"
t_eq ".npm is gone" no "$(has .npm)"
t_eq "_work/_tool is gone" no "$(has _work/_tool)"
t_eq ".bun/install/cache is gone" no "$(has .bun/install/cache)"
t_eq "a checkout under _work stays" yes "$(has _work/repo/keep.txt)"
t_eq "the runner's registration stays" yes "$(has .runner)"
t_eq "the over-cap json log is truncated, in the VM, through sudo" 0 "$(cat "$FX/logsize.abc123")"
t_has "...by the exact path docker named" "$(cat "$FX/colima.log")" "ssh -- sudo truncate -s 0 /var/lib/docker/containers/abc123/abc123-json.log"
t_has "the VM is trimmed" "$(cat "$FX/colima.log")" "ssh -- sudo fstrim -v /var/lib/docker"
t_has "the Mac-side MB freed is reported (4096 -> 1024 KB)" "$OUT" "3 MB freed on the Mac (datadisk 4 -> 1 MB)"
t_has "one checks.log line carries the check's own id" "$(cat "$CACHE/checks.log")" "[check:ci.runner-tidy] 20"
t_has "...the figure" "$(cat "$CACHE/checks.log")" "1 runners, 2861 MB of json logs truncated, 3 MB freed on the Mac"
t_eq "...and it is one line" 1 "$(grep -c 'check:ci.runner-tidy' "$CACHE/checks.log")"
t_eq "the stamp holds this run's time" "$NOW" "$(cat "$CACHE/ci-runner-tidy.stamp")"
t_eq "neither stub was called off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "tidy: update staging written in the last 10 minutes may be a self-update in flight"
tidyfx; touch "$FX/home.alpha-linux/_work/_update/x/pkg"; run tidy --apply >/dev/null
t_eq "a staging dir with a fresh file stays" yes "$(has _work/_update)"
t_eq "...while the old update script beside it goes" no "$(has _work/_update.sh)"

t_section "tidy: a log under the cap is not touched, one over it is truncated once"
tidyfx 1000; run tidy --apply >/dev/null
t_eq "1000 bytes is under 20m: no truncate" 0 "$(grep -c truncate "$FX/colima.log" || true)"
tidyfx 20971520; run tidy --apply >/dev/null
t_eq "exactly the cap is not over it" 0 "$(grep -c truncate "$FX/colima.log" || true)"
tidyfx 20971521; run tidy --apply >/dev/null
t_eq "one byte over is" 1 "$(grep -c truncate "$FX/colima.log" || true)"
tidyfx; printf 'logsize 1g\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run tidy --apply >/dev/null
t_eq "the cap is the configured one: 3 GB is over 1g" 0 "$(cat "$FX/logsize.abc123")"
tidyfx; echo '/etc/passwd' > "$FX/logpath.alpha-linux"; run tidy --apply >/dev/null
t_eq "a log path outside docker's containers dir is never handed to sudo" 0 "$(grep -c 'stat\|truncate' "$FX/colima.log" || true)"
tidyfx; echo '/var/lib/docker/containers/abc/../../../../etc/x-json.log' > "$FX/logpath.alpha-linux"; run tidy --apply >/dev/null
t_eq "...nor one that climbs out of it" 0 "$(grep -c 'stat\|truncate' "$FX/colima.log" || true)"

t_section "tidy: a busy runner loses the always-safe set and nothing else"
tidyfx; : > "$FX/busy.alpha-linux"; OUT="$(run tidy --apply)"
t_eq "superseded dirs still go" no "$(has bin.2.1.0)"
t_eq "...staging, diag logs" no "$(has _diag/old.log)"
t_eq ".cache stays" yes "$(has .cache)"
t_eq ".npm stays" yes "$(has .npm)"
t_eq "_work/_tool stays" yes "$(has _work/_tool)"
t_eq ".bun cache stays" yes "$(has .bun/install/cache)"
t_has "it says the runner is running a job" "$OUT" "alpha-linux is running a job"
t_eq "...and the trim still runs" 1 "$(grep -c fstrim "$FX/colima.log" || true)"
t_section "tidy: a job that starts mid-run stops the cache removal at the next directory"
tidyfx; echo 1 > "$FX/busyafter.alpha-linux"; run tidy --apply >/dev/null
t_eq "the first cache went while it was idle" no "$(has .cache)"
t_eq "the job then started: the next stays" yes "$(has .npm)"
t_eq "...and the rest" yes "$(has _work/_tool)"

t_section "tidy: a metered network keeps the caches, whoever is idle"
tidyfx; printf '%s metered android-hotspot:en0\n' "$NOW" > "$FX/state/net/mode"; OUT="$(run tidy --apply)"
t_eq "the caches stay" yes "$(has .cache)"
t_eq "...all four" 4 "$(for d in .cache .npm _work/_tool .bun/install/cache; do has "$d"; done | grep -c yes)"
t_eq "the always-safe set still goes" no "$(has bin.2.1.0)"
t_has "it says why" "$OUT" "the network is metered"
t_has "...and the log line says the caches were left" "$(cat "$CACHE/checks.log")" "caches left (metered)"
tidyfx; printf '%s unmetered en0\n' "$NOW" > "$FX/state/net/mode"; run tidy --apply >/dev/null
t_eq "control: unmetered, the same run takes the caches" no "$(has .cache)"
tidyfx; printf '%s metered forced\n' "$NOW" > "$FX/state/net/mode"; run tidy >/dev/null
t_has "a dry run on a metered network passes nocaches too" "$(cat "$FX/docker.log")" "sh -s -- dry nocaches"

t_section "tidy: a runner it cannot tidy is reported, the rest carry on"
tidyfx; container beta-linux port-linux-runner:local running; home beta-linux
echo /var/lib/docker/containers/def456/def456-json.log > "$FX/logpath.beta-linux"; echo 100 > "$FX/logsize.def456"
: > "$FX/exec.fail.alpha-linux"; OUT="$(run tidy --apply)"; RC=$?
t_eq "exit 1" 1 "$RC"
t_has "the failing runner is named" "$OUT" "alpha-linux: the tidy script did not run in it"
t_eq "the other runner was tidied" no "$(h=$FX/home.beta-linux; [ -e "$h/bin.2.1.0" ] && echo yes || echo no)"
tidyfx; mkdir -p "$FX/home.alpha-linux"; rm -rf "$FX/home.alpha-linux"/*; rm -f "$FX/home.alpha-linux/bin"
mkdir -p "$FX/home.alpha-linux/bin.1" "$FX/home.alpha-linux/.cache"; OUT="$(run tidy --apply)"
t_eq "a home with no live bin/externals symlinks is left whole" yes "$(has .cache)"
t_eq "...its version dirs too" yes "$(has bin.1)"
tidyfx; container stopped-linux port-linux-runner:local exited; OUT="$(run tidy --apply)"
t_has "a stopped container is skipped, said" "$OUT" "stopped-linux is exited"
t_eq "...and never exec'd" 0 "$(grep -c 'stopped-linux sh' "$FX/docker.log" || true)"
tidyfx; container other port-linux-runner:local running; run tidy --apply >/dev/null
t_eq "a container that is not a runner is never exec'd" 0 "$(grep -c 'exec -i other' "$FX/docker.log" || true)"
tidyfx; container harbor-gate port-linux-runner:local running; home harbor-gate; run tidy --apply >/dev/null
t_eq "harbor-gate is a runner" no "$(h=$FX/home.harbor-gate; [ -e "$h/bin.2.1.0" ] && echo yes || echo no)"
tidyfx; : > "$FX/fstrim.fail"; OUT="$(run tidy --apply)"; RC=$?
t_eq "a failed fstrim is a failure, not a clean run" 1 "$RC"
t_has "...that says the Mac keeps what was deleted" "$OUT" "fstrim in the VM failed"
tidyfx; : > "$FX/colima.fail"; OUT="$(run tidy --apply)"; RC=$?
t_eq "colima not answering: the runner homes are still tidied" no "$(has bin.2.1.0)"
t_eq "...and it is a failure" 1 "$RC"
tidyfx; : > "$FX/docker.fail"; OUT="$(run tidy --apply)"; RC=$?
t_eq "docker not answering is exit 1, never a stamp" 1 "$RC"
t_eq "...no stamp" no "$([ -e "$CACHE/ci-runner-tidy.stamp" ] && echo yes || echo no)"
tidyfx; rm -f "$FX/datadisk"; OUT="$(run tidy --apply)"
t_has "no datadisk to measure: said, not guessed" "$OUT" "unmeasured"

t_section "tidy --if-due: Sundays from 04:00, once"
due() { _n=0; [ ! -f "$FX/docker.log" ] || _n="$(grep -c '^ps -a' "$FX/docker.log" || :)"; echo "${_n:-0}"; }   # 1 when the run reached docker
tidyfx; AT=1795320000 run tidy --apply --if-due >/dev/null
t_eq "a box with no stamp is not due, even Sunday 04:00: its first run is the next Sunday's" 0 "$(due)"
t_eq "...the run seeded the stamp with now" 1795320000 "$(cat "$CACHE/ci-runner-tidy.stamp")"
tidyfx; echo 1794718800 > "$CACHE/ci-runner-tidy.stamp"; AT=1795319999 run tidy --apply --if-due >/dev/null
t_eq "Sunday 03:59:59, last run the Sunday before: not due" 0 "$(due)"
tidyfx; echo 1794718800 > "$CACHE/ci-runner-tidy.stamp"; AT=1795320000 run tidy --apply --if-due >/dev/null
t_eq "Sunday 04:00:00 is due" 1 "$(due)"
t_eq "...the run took its time as its stamp" 1795320000 "$(cat "$CACHE/ci-runner-tidy.stamp")"
rm -f "$FX/docker.log"; AT=1795339800 run tidy --apply --if-due >/dev/null
t_eq "later that Sunday it is done: not due again" 0 "$(due)"
AT=1795608000 run tidy --apply --if-due >/dev/null
t_eq "Wednesday after that Sunday's run: not due" 0 "$(due)"
AT=1795925100 run tidy --apply --if-due >/dev/null
t_eq "the next Sunday 04:05 is due" 1 "$(due)"
tidyfx; echo 1794200000 > "$CACHE/ci-runner-tidy.stamp"; AT=1795003200 run tidy --apply --if-due >/dev/null
t_eq "a missed Sunday (Mac asleep): the Wednesday after it runs it" 1 "$(due)"
tidyfx; echo 1794718800 > "$CACHE/ci-runner-tidy.stamp"; AT=1795003200 run tidy --apply --if-due >/dev/null
t_eq "a run last Sunday 05:00 covers the Wednesday" 0 "$(due)"
tidyfx; echo 1794718800 > "$CACHE/ci-runner-tidy.stamp"; AT=1795339800 run tidy --apply --if-due >/dev/null
t_eq "...and not the Sunday after it" 1 "$(due)"
tidyfx; run tidy --apply >/dev/null
t_eq "without --if-due it runs whenever asked" 1 "$(grep -c '^ps -a' "$FX/docker.log" || true)"
t_exit "--if-due belongs to tidy" 2 env FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_CI_DOCKER="$DOCKER" HARBOR_SCOPE_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/ci-runners.sh" list --if-due

t_red check.ci-runner-tidy   # 13 planted defects each went red, 2026-11-23: log flags dropped, idle check, metered skip, due gate, live-dir guard, dry default, cap -gt, log-path guard, stamp seed, fstrim, fresh-staging guard, diag age, nocaches arg
t_done
