#!/usr/bin/env sh
# bin/ci-runners.sh tick's WEDGED item and the unwedge verb (harbor#1060, check ci-runner-alarm), against the stubbed
# docker's exec: a runner online and busy on a job that is dead in the water. The replay is 2026-10-13: an org runner's
# mutation-test job forked 8 workers into 1 GiB, the kernel OOM-killed one, and the job sat 3h at 0.4% CPU while the
# org's deploy queued behind it, with nothing said, because GitHub showed a busy online runner.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
export HARBOR_CI_UNWEDGE_GRACE=0
A="$CACHE/ci-runner-alarm.json"
alog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:ci-runner-alarm' "$CACHE/checks.log"; else echo 0; fi; }
last() { grep 'check:ci-runner-alarm' "$CACHE/checks.log" | tail -n 1; }
get() { jq -r "$1" "$A"; }
tick() { AT="$1" run tick >/dev/null; }
C=someorg-linux
# the org runner, online and busy on GitHub: the shape the old alarm could not see
base() { reset; orgconf; orgrunner online true; container "$C" port-linux-runner:local running
         container alpha-linux port-linux-runner:local running; runner alpha online false; runner harbor online false 9; }
# cg <container> <oom_kill> <cpu-usec> [<worker-pid> <job-age-s> <start-ticks> <jobs-run>] — what one exec inside it reads.
# jobs-run is the count of Worker_*.log files: one more each time a new job (pid.start) is seen, unless given
cg() { jf="$FX/wedge.jct.$1"; ji="$FX/wedge.jid.$1"; n="$(cat "$jf" 2>/dev/null || echo 100)"
       if [ -n "${4:-}" ] && [ "$(cat "$ji" 2>/dev/null)" != "$4.${6:-5000}" ]; then n=$((n + 1)); echo "$4.${6:-5000}" > "$ji"; fi
       n="${7:-$n}"; echo "$n" > "$jf"
       printf 'low 0\nhigh 0\nmax 599\noom 1\noom_kill %s\noom_group_kill 0\nusage_usec %s\nuser_usec 1\nsystem_usec 1\njobs %s\n' "$2" "$3" "$n" > "$FX/wedge.$1"
       [ -z "${4:-}" ] || printf 'worker %s %s %s\n' "$4" "$5" "${6:-5000}" >> "$FX/wedge.$1"; }
nexec() { if [ -f "$FX/docker.log" ]; then grep -c "^exec $1 " "$FX/docker.log" || true; else echo 0; fi; }

t_section "the 2026-10-13 replay: an OOM kill in the job, then flat CPU, seen within two ticks"
base; cg "$C" 0 50000000; tick "$NOW"                                 # 13:20 idle, no OOM ever
cg "$C" 1 60000000 87 120; tick "$((NOW + 300))"                    # 13:25 mutmut started, one worker OOM-killed
t_eq "the job's first sighting: no alarm (no CPU window yet)" 0 "$(alog)"
t_eq "...its oom_kill baseline is the idle sighting's, so the OOM counts" "0 1" "$(get '.wedge["'$C'"] | "\(.base) \(.oom)"')"
cg "$C" 1 60300000 87 420; tick "$((NOW + 600))"
t_eq "the first tick it is true (0.3s CPU in 5m): a suspicion, not an alarm" 0 "$(alog)"
t_eq "...recorded, so the next tick can confirm it" "$((NOW + 600))" "$(get '.since["wedged:'$C'"]')"
cg "$C" 1 60500000 87 720; tick "$((NOW + 900))"
t_eq "the second tick confirms it: one line" 1 "$(alog)"
t_has "...stamped with the registry id" "$(last)" "[check:ci-runner-alarm]"
t_has "...naming the container and how long the job has run" "$(last)" "wedged $C: job running 0h12m"
t_has "...the evidence: the oom_kill delta and the CPU seconds in the window" "$(last)" "oom_kill +1 during it, 0.5s CPU in the 10m since"
t_has "...and the exact clearing command" "$(last)" "clear: sh bin/ci-runners.sh unwedge $C --apply"
t_eq "the cache says so, for the statusline" "$C" "$(get '.wedged | join(" ")')"
t_eq "...and GitHub's view (online, busy) raised nothing else" "0 0" "$(get '"\(.offline | length) \(.stuck.jobs)"')"
u=60500000; tt=$((NOW + 900)); age=720
while [ "$age" -lt 10980 ]; do u=$((u + 100000)); tt=$((tt + 540)); age=$((age + 540)); cg "$C" 1 "$u" 87 "$age"; tick "$tt"; done
t_eq "three hours of it is one standing alarm, not a line per tick" 1 "$(alog)"
t_eq "...the cache carries the job's age" "3h03m" "$(get '.wedge["'$C'"].age | "\(. / 3600 | floor)h\((. % 3600) / 60 | floor | tostring | if length < 2 then "0" + . else . end)m"')"
cg "$C" 1 "$u"; tick "$((tt + 300))"
t_eq "the runner freed (no Runner.Worker): one line" 2 "$(alog)"
t_has "...saying it cleared and what it was" "$(last)" "cleared (was: wedged $C)"

t_section "a job busy far longer than any normal job, near-zero CPU over a long window, no OOM"
base; cg "$C" 0 1000000 87 7000; tick "$NOW"
u=1000000; tt=$NOW; age=7000
while [ "$tt" -lt "$((NOW + 3240))" ]; do u=$((u + 50000)); tt=$((tt + 540)); age=$((age + 540)); cg "$C" 0 "$u" 87 "$age"; tick "$tt"; done
u=$((u + 50000)); tt=$((tt + 360)); age=$((age + 360)); cg "$C" 0 "$u" 87 "$age"; tick "$tt"   # exactly the hour after the first
t_eq "an hour of 2h+ at ~0% CPU is first true only when the hour of samples exists: no line yet" 0 "$(alog)"
cg "$C" 0 "$((u + 50000))" 87 "$((age + 300))"; tick "$((tt + 300))"
t_eq "...and confirmed on the tick after" 1 "$(alog)"
t_has "...as a wedge with no oom_kill and the hour's CPU" "$(last)" "oom_kill +0 during it, 0.4s CPU in the last 65m"

t_section "what is not a wedge"
base; cg "$C" 5 1000000; tick "$NOW"; tick "$((NOW + 300))"; tick "$((NOW + 600))"
t_eq "an idle runner with an old oom_kill: nothing" 0 "$(alog)"
cg "$C" 5 1000000 87 100; tick "$((NOW + 900))"; cg "$C" 5 1100000 87 400; tick "$((NOW + 1200))"; cg "$C" 5 1200000 87 700; tick "$((NOW + 1500))"
t_eq "...and the next job, flat, is not charged with the old OOM" 0 "$(alog)"
t_eq "...its baseline is the counter as it found it" 5 "$(get '.wedge["'$C'"].base')"
base; cg "$C" 0 1000000 87 100; tick "$NOW"; cg "$C" 1 200000000 87 400; tick "$((NOW + 300))"   # a job OOMs, keeps working
cg "$C" 1 200000000 99 50 6000; tick "$((NOW + 600))"                                            # ... and a new job starts
cg "$C" 1 200100000 99 350 6000; tick "$((NOW + 900))"; cg "$C" 1 200200000 99 650 6000; tick "$((NOW + 1200))"
t_eq "a new job after an OOM'd one, flat: the OOM stays with the job it happened in" 0 "$(alog)"
base; cg "$C" 0 1000000; tick "$NOW"; cg "$C" 1 2000000 87 100; tick "$((NOW + 300))"
u=2000000; for _i in 1 2 3 4; do u=$((u + 200000000)); cg "$C" 1 "$u" 87 "$((100 + _i * 300))"; tick "$((NOW + 300 + _i * 300))"; done
t_eq "an OOM kill in a job that is still burning CPU (xdist losing a worker): nothing" 0 "$(alog)"
base; cg "$C" 0 1000000 87 100; tick "$NOW"; cg "$C" 1 2000000 87 400; tick "$((NOW + 300))"
cg "$C" 1 402000000 87 700; tick "$((NOW + 600))"; cg "$C" 1 402000000 87 1000; tick "$((NOW + 900))"
cg "$C" 1 402100000 87 1300; tick "$((NOW + 1200))"
t_eq "an OOM kill, then work, then a flat stretch (a docker build next door): not the OOM wedge" 0 "$(alog)"
base; cg "$C" 0 1000000 87 600; tick "$NOW"
u=1000000; for _i in 1 2 3 4 5 6 7 8; do u=$((u + 10000)); cg "$C" 0 "$u" 87 "$((600 + _i * 540))"; tick "$((NOW + _i * 540))"; done
t_eq "a flat job under the 2h busy limit, no OOM (a long wait on a service): nothing" 0 "$(alog)"
base; cg "$C" 0 1000000 87 7000; tick "$NOW"
u=1000000; for _i in 1 2 3 4 5 6 7 8; do u=$((u + 270000000)); cg "$C" 0 "$u" 87 "$((7000 + _i * 540))"; tick "$((NOW + _i * 540))"; done
t_eq "a job over 2h at half a core for over an hour is working: nothing" 0 "$(alog)"
base; cg "$C" 0 1000000; tick "$NOW"; cg "$C" 1 2000000 99 100 5000 102; tick "$((NOW + 300))"
cg "$C" 1 2100000 99 400 5000 102; tick "$((NOW + 600))"; cg "$C" 1 2200000 99 700 5000 102; tick "$((NOW + 900))"
t_eq "two jobs ran since the idle sighting (one OOM'd, then this flat one): the OOM is not this job's" 0 "$(alog)"
t_eq "...its baseline is the counter as it found it" 1 "$(get '.wedge["'$C'"].base')"
base; cg "$C" 0 1000000; tick "$NOW"; cg "$C" 1 2000000 87 100; tick "$((NOW + 300))"; cg "$C" 1 2100000 87 400; tick "$((NOW + 600))"
cg "$C" 2 2200000 99 50 6000; tick "$((NOW + 900))"; cg "$C" 2 2300000 99 350 6000; tick "$((NOW + 1200))"; cg "$C" 2 2400000 99 650 6000; tick "$((NOW + 1500))"
t_eq "a job first seen right after an OOM'd one: baselined at its own first sighting, no alarm" 0 "$(alog)"
t_eq "...base 2, not the job before's 1" 2 "$(get '.wedge["'$C'"].base')"
base; cg "$C" 0 1000000; tick "$NOW"; cg "$C" 0 100000000 87 100; tick "$((NOW + 300))"; cg "$C" 0 200000000 87 400; tick "$((NOW + 600))"
cg "$C" 1 200100000 87 700; tick "$((NOW + 900))"; cg "$C" 1 200200000 87 1000; tick "$((NOW + 1200))"
t_eq "worked, then the OOM, then flat: one flat tick is a suspicion" 0 "$(alog)"
cg "$C" 1 200300000 87 1300; tick "$((NOW + 1500))"
t_eq "...and the next confirms it: the CPU window starts at the OOM, not at the busy stretch before it" 1 "$(alog)"
t_has "...with the CPU since the OOM, not since the job began" "$(last)" "0.2s CPU in the 10m since"
base; printf '{"parked":["%s"]}\n' "$C" > "$CACHE/ci-governor.json"; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"
cg "$C" 1 1 87 400; tick "$((NOW + 600))"; cg "$C" 1 1 87 700; tick "$((NOW + 900))"
t_eq "a runner the governor parked is not wedged" 0 "$(alog)"
t_eq "...and is not even read" 0 "$(nexec "$C")"
base; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"
cg "$C" 1 1 87 1600; tick "$((NOW + 1700))"
t_eq "a sighting carried from a cache over 600s old (the Mac slept) starts again" 0 "$(alog)"
t_eq "...and so do its CPU samples: a sleep is not a flat job" null "$(get '.wedge["'$C'"].why')"
base; printf 'org SomeOrg\nwedge off\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; cg "$C" 0 1; tick "$NOW"
cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"; cg "$C" 1 1 87 700; tick "$((NOW + 900))"
t_eq "wedge off in the config: no wedged item" 0 "$(alog)"
t_eq "...and no container is read for it" 0 "$(nexec "$C")"

t_section "every runner container, whatever GitHub can read"
base; : > "$FX/runners.fail"; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"
cg "$C" 1 1 87 400; tick "$((NOW + 600))"; cg "$C" 1 1 87 700; tick "$((NOW + 900))"
t_eq "GitHub unreadable (the org's repos cannot be listed): the wedge still alarms" 1 "$(alog)"
t_eq "...the cache says GitHub was unread, and wedged" "true $C" "$(get '"\(.unread) \(.wedged | join(" "))"')"
for g in harbor-linux harbor-linux-2; do
  base; container "$g" port-linux-runner:local running; cg "$g" 0 1; tick "$NOW"
  cg "$g" 1 1 87 100; tick "$((NOW + 300))"; cg "$g" 1 1 87 400; tick "$((NOW + 600))"; cg "$g" 1 1 87 700; tick "$((NOW + 900))"
  t_has "the governance runner $g is watched too" "$(last)" "wedged $g:"
done

base; container someorg-linux-2 port-linux-runner:local running; cg someorg-linux-2 0 1; tick "$NOW"
cg someorg-linux-2 1 1 87 100; tick "$((NOW + 300))"; cg someorg-linux-2 1 1 87 400; tick "$((NOW + 600))"; cg someorg-linux-2 1 1 87 700; tick "$((NOW + 900))"
t_has "an org's second runner, someorg-linux-2, is watched too" "$(last)" "wedged someorg-linux-2:"

t_section "a read that fails is unread, not idle: a wedge survives a hung exec"
base; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"
cg "$C" 1 1 87 700; tick "$((NOW + 900))"
t_eq "control: the wedge is confirmed first" 1 "$(alog)"
: > "$FX/wedge.fail.$C"; tick "$((NOW + 1200))"
t_eq "one exec that fails: the standing alarm stands, no cleared line" 1 "$(alog)"
t_eq "...still wedged in the cache" "$C" "$(get '.wedged | join(" ")')"
rm -f "$FX/wedge.fail.$C"; cg "$C" 1 1 87 1300; tick "$((NOW + 1500))"
t_eq "the read comes back, same job, still flat: still one alarm, no new line" 1 "$(alog)"
t_eq "...with the job's baseline kept (the OOM is still the job's)" "0 1" "$(get '.wedge["'$C'"] | "\(.base) \(.oom)"')"
base; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"
: > "$FX/wedge.fail.$C"; tick "$((NOW + 600))"; rm -f "$FX/wedge.fail.$C"
cg "$C" 1 1 87 700; tick "$((NOW + 900))"; cg "$C" 1 1 87 1000; tick "$((NOW + 1200))"
t_eq "an exec that fails before the alarm: the job is still baselined from the idle sighting, and alarms" 1 "$(alog)"

t_section "the line is a delta even while GitHub is unread"
base; runner alpha offline false; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"
cg "$C" 1 1 87 700; tick "$((NOW + 900))"
t_has "control: an offline runner and a wedge stand together" "$(last)" "wedged $C"
: > "$FX/runners.fail"; cg "$C" 1 1; tick "$((NOW + 1200))"
t_hasnt "the wedge clears while GitHub is unread: the line is not an empty ALARM" "$(last)" "ALARM: ."
t_has "...it names the offline runner still standing" "$(last)" "ALARM: offline alpha-linux"
t_has "...and what it was" "$(last)" "(was: offline alpha-linux; wedged $C)"

t_section "unwedge: ends the step tree of a confirmed wedge, and nothing else"
# the process shape inside a runner container mid-job, plus a Listener child that is not part of the job
psx() { printf '%s\n' '1 0 /bin/bash ./run.sh' '10 1 /bin/bash /actions-runner/run-helper.sh' '14 10 /actions-runner/bin/Runner.Listener run' \
  '87 14 /actions-runner/bin/Runner.Worker spawnclient 115 118' '438 87 /usr/bin/bash -e /actions-runner/_work/_temp/0f3a.sh' \
  '443 438 uv run --with mutmut mutmut run' '447 443 python -m mutmut run' '449 447 python mutmut-worker' '452 447 python mutmut-worker' \
  '500 14 /actions-runner/bin/Runner.Listener-helper' > "$FX/ps.$C"; }
wedged() { base; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"
           cg "$C" 1 1 87 700; tick "$((NOW + 900))"; psx; AT=$((NOW + 1000)); }
# a suspicion is not a wedge: the job flat on one tick only, so the cache knows the job but has not confirmed it
base; cg "$C" 0 1; tick "$NOW"; cg "$C" 1 1 87 100; tick "$((NOW + 300))"; cg "$C" 1 1 87 400; tick "$((NOW + 600))"; psx; AT=$((NOW + 650))
O="$(run unwedge "$C" --apply)"; rc=$?
t_eq "not confirmed wedged (one flat tick): refuses" 1 "$rc"
t_has "...saying why" "$O" "not confirmed wedged"
t_eq "...and ends nothing" 0 "$(nlines "$FX/kills.log")"
wedged; O="$(run unwedge "$C")"; rc=$?
t_eq "a dry run exits 0" 0 "$rc"
t_has "...prints the step processes it would end" "$O" "443	uv run --with mutmut mutmut run"
t_has "control: the container's process list does hold the worker" "$(cat "$FX/ps.$C")" "Runner.Worker spawnclient"
t_hasnt "...never Runner.Worker itself" "$O" "Runner.Worker spawnclient"
t_eq "...and sends nothing" 0 "$(nlines "$FX/kills.log")"
t_eq "...and logs nothing" 1 "$(alog)"
echo 447 > "$FX/stubborn.$C"
O="$(run unwedge "$C" --apply)"; rc=$?
t_eq "--apply on a confirmed wedge exits 0" 0 "$rc"
t_eq "...TERM to exactly the step tree" "TERM $C 438 443 447 449 452" "$(sed -n 1p "$FX/kills.log")"
t_eq "...KILL to what TERM left, and only that" "KILL $C 447" "$(sed -n 2p "$FX/kills.log")"
t_eq "...Runner.Worker, Runner.Listener and the Listener's own child still run" "1 10 14 87 500" "$(awk '{ printf "%s%s", s, $1; s = " " }' "$FX/ps.$C")"
t_eq "...one checks.log line" 2 "$(alog)"
t_has "...that names the container and what was sent" "$(last)" "unwedge $C: job 0h11m in, sent TERM to 5 step processes, KILL to 1"
wedged; AT=$((NOW + 2000)); O="$(run unwedge "$C" --apply)"; rc=$?
t_eq "a wedge read from a cache over 900s old: refuses" 1 "$rc"
t_eq "...and ends nothing" 0 "$(nlines "$FX/kills.log")"
wedged; cg "$C" 1 1 99 30 6000; O="$(run unwedge "$C" --apply)"; rc=$?
t_eq "the wedged job ended and the runner took another: refuses" 1 "$rc"
t_has "...naming both jobs" "$O" "the wedged job (87.5000) is not the one running now (99.6000)"
t_eq "...and the new job is left alone" 0 "$(nlines "$FX/kills.log")"
O="$(run unwedge 'x;rm' --apply)"; rc=$?
t_eq "a name that is not a container name is refused before any read" 2 "$rc"

t_section "the stubs were told every call"
t_eq "no unexpected gh or docker call" 0 "$(nlines "$FX/unexpected.log")"
t_done
