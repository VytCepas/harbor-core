#!/usr/bin/env sh
# ci-governor.sh never parks a Mac runner a queued macOS job is waiting for (harbor#1032): liveness beats the
# budget. Shims and helpers in ci-governor-fixture.sh; the budget policy itself is ci-governor-test.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/ci-governor-fixture.sh"

MACJOB=self-hosted,macOS,ARM64
# cut — sustained load from something unrelated: the budget is cut to the floor of 2, harbor-mac up and idle.
cut() { gov tick >/dev/null; echo 12.00 > "$FX/load"; tick 30; tick 60; }
runs() { ngh 'actions/runs'; }   # runs lists and each run's jobs; the runners list is actions/runners

t_section "budget 2 and a macOS job queued: the idle Mac runner is kept, never parked"
reset; ghjob 11 queued queued "$MACJOB"; cut
t_eq "(setup) the load cut the budget to the floor of 2" 2 "$(st budget)"
t_eq "ROOM=no, GitHub says idle, a macOS job is queued: harbor-mac is not stopped" 0 "$(nsvc stop)"
t_has "...and the status line says why" "$(jq -r .mac "$CACHE/ci-governor.json")" "harbor-mac running (kept: a macOS job is queued)"
t_eq "...nothing is recorded as parked" "" "$(st parked)"
tick; tick
t_eq "later ticks, job still queued: still never stopped" 0 "$(nsvc stop)"
reset; ghjob 12 in_progress queued "$MACJOB"; ghjob 12 in_progress completed "$MACJOB"; cut
t_eq "a queued job inside a run that is in_progress counts too" 0 "$(nsvc stop)"

t_section "a parked Mac runner is started for a queued macOS job"
reset; cut
t_eq "(setup) nothing queued: harbor-mac was parked" 1 "$(nsvc stop)"
ghjob 13 queued queued "$MACJOB"; tick
t_eq "a macOS job queues while the budget is 2 (ROOM=no): the parked runner is started" 1 "$(nsvc start)"
t_has "...with the reason in the log line" "$(tail -1 "$CACHE/checks.log")" "harbor-mac started: a macOS job is queued"
t_has "...and the status says why" "$(jq -r .mac "$CACHE/ci-governor.json")" "harbor-mac running (started: a macOS job is queued)"
t_eq "...and it is no longer parked" "" "$(st parked)"
tick; tick
t_eq "next ticks, job still queued: not stopped again before it picks the job up (no flap)" 1 "$(nsvc stop)"
printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$MACW" > "$FX/procs"; rm -f "$FX/runs.queued"; tick
t_eq "the job picked up (a Worker runs, nothing queued): a busy runner is still not stopped" 1 "$(nsvc stop)"

t_section "controls: nothing here for this runner to take, harbor-mac parks as before"
reset; cut
t_eq "budget 2, no queued job: parked" 1 "$(nsvc stop)"
t_eq "...and recorded as parked" harbor-mac "$(st parked)"
reset; ghjob 14 queued queued "self-hosted,Linux,ARM64"; cut
t_eq "a queued Linux job is not this runner's: parked" 1 "$(nsvc stop)"
reset; ghjob 15 queued queued "macos-latest"; cut
t_eq "a queued GitHub-hosted macOS job is not this runner's: parked" 1 "$(nsvc stop)"
reset; ghjob 16 in_progress in_progress "$MACJOB"; cut
t_eq "a macOS job already running is not queued: parked" 1 "$(nsvc stop)"
tick; tick
t_eq "...and stays parked, never started with nothing queued" 0 "$(nsvc start)"

t_section "GitHub unreadable: today's behaviour (park), and it says so"
reset; ghjob 17 queued queued "$MACJOB"; : > "$FX/jobs.fail"; cut
t_eq "the jobs call fails: no start on an unreadable answer, harbor-mac is parked" 1 "$(nsvc stop)"
t_eq "...never started" 0 "$(nsvc start)"
t_has "...and the log carries it" "$(cat "$CACHE/checks.log")" "WARN macOS queue unreadable"
t_has "...and the status names it" "$(jq -r .mac "$CACHE/ci-governor.json")" "harbor-mac parked (queued jobs unreadable"
tick; tick
t_eq "parked on the next ticks too" 0 "$(nsvc start)"
rm -f "$FX/jobs.fail"; tick
t_eq "the answer readable again and a job queued: started" 1 "$(nsvc start)"
reset; cut; : > "$FX/gh.fail"; tick
t_eq "every GitHub call failing on a parked runner: stays parked" 0 "$(nsvc start)"
reset; : > "$FX/gh.fail"; cut
t_eq "control: an idle runner GitHub cannot be asked about is kept, as before" 0 "$(nsvc stop)"

t_section "the GitHub question is asked only when the decision would park"
reset; ghjob 18 queued queued "$MACJOB"; gov tick >/dev/null; tick; tick
t_eq "an idle box with room (budget 4): no runs or jobs call at all" 0 "$(runs)"
reset; cut; ghjob 19 queued queued "$MACJOB"; rm -f "$FX/gh.calls"; echo 2.00 > "$FX/load"; tick 120
t_eq "(setup) load gone, the budget raised to 4: room for the parked runner" 4 "$(st budget)"
t_eq "...it is started for the room, and no queue question is asked" 1 "$(nsvc start)"
t_eq "...and not one runs or jobs call was made" 0 "$(runs)"
reset; printf '%s\n' "$GTML" > "$FX/procs"; ghjob 20 queued queued "$MACJOB"; cut
t_eq "a runner the operator stopped (not parked by the governor) is never asked about" 0 "$(runs)"
reset; gov tick >/dev/null; echo 12.00 > "$FX/load"; rm -f "$FX/gh.calls"; tick 30
t_eq "ROOM=no, idle runner, nothing queued: the runners list, then the queued and in_progress run lists" 3 "$(ngh actions/run)"
t_eq "...of which two are run lists" 2 "$(runs)"
reset; ghjob 21 queued queued "$MACJOB"; gov tick >/dev/null; echo 12.00 > "$FX/load"; rm -f "$FX/gh.calls"; tick 30
t_eq "...with a queued macOS run: its jobs are read and the search stops (queued list + that run's jobs)" 2 "$(runs)"

t_done
