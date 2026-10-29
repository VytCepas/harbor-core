#!/usr/bin/env sh
# bin/ci-runners.sh tick's alarm (harbor#1060, check ci-runner-alarm) against stubbed gh and docker: a registered
# runner offline or docker down, seen on two ticks, and a self-hosted job queued past the limit with no runner able
# to take it, each logged once on the way in and once on the way out. The replay is 2026-10-05 19:53, when the Mac
# rebooted, Colima stayed down and every Linux runner sat offline ~18 minutes with nothing said.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
A="$CACHE/ci-runner-alarm.json"
alog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:ci-runner-alarm' "$CACHE/checks.log"; else echo 0; fi; }
last() { grep 'check:ci-runner-alarm' "$CACHE/checks.log" | tail -n 1; }
get() { jq -r "$1" "$A"; }
tick() { AT="$1" run tick >/dev/null; }
ago() { date -u -r "$(($1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(($1))" +%Y-%m-%dT%H:%M:%SZ; }
healthy() { reset; container alpha-linux port-linux-runner:local running; runner alpha online false; runner harbor online false 9; }
# queue <repo> <status> <run-id> <run-age-s> <job-labels-json> <job-age-s> — one run and its one queued job
queue() {
  mkdir -p "$FX/queue" "$FX/jobs"; _f="$FX/queue/$1.$2.json"; [ -f "$_f" ] || echo '{"workflow_runs":[]}' > "$_f"
  jq -c --argjson id "$3" --arg at "$(ago "NOW - $4")" '.workflow_runs += [{id: $id, created_at: $at}]' "$_f" > "$_f.n" && mv "$_f.n" "$_f"
  printf '{"jobs":[{"id":%s,"status":"queued","labels":%s,"created_at":"%s"}]}\n' "$(($3 * 10))" "$5" "$(ago "NOW - $6")" > "$FX/jobs/$3.json"
}

t_section "a healthy fleet: nothing to say"
healthy; tick "$NOW"; tick "$((NOW + 300))"
t_eq "no alarm line" 0 "$(alog)"
t_eq "the cache says no runner is down" "false 0 0" "$(get '"\(.docker_down) \(.offline | length) \(.stuck.jobs)"')"
t_eq "the governance repo's runner is watched too" yes "$(grep -q 'repos/VytCepas/harbor/actions/runners' "$FX/gh.log" && echo yes || echo no)"

t_section "the 2026-10-05 reboot: docker down, every runner offline"
healthy; : > "$FX/docker.fail"; runner alpha offline false; runner harbor offline false 9
tick "$NOW"
t_eq "one tick is a suspicion, not an alarm" 0 "$(alog)"
t_eq "...recorded, so the next tick can confirm it" "$NOW" "$(get '.since.docker')"
tick "$((NOW + 300))"
t_eq "the second tick confirms it: one line" 1 "$(alog)"
t_has "...stamped with the registry id" "$(last)" "[check:ci-runner-alarm]"
t_has "...saying docker is down" "$(last)" "docker down"
t_has "...and which registered runners are offline" "$(last)" "offline alpha-linux harbor-linux"
t_eq "the cache says so, for the statusline" "true alpha-linux harbor-linux" "$(get '"\(.docker_down) \(.offline | join(" "))"')"
tick "$((NOW + 600))"; tick "$((NOW + 900))"
t_eq "a standing outage is not a change: no line per tick" 1 "$(alog)"
rm -f "$FX/docker.fail"; runner alpha online false; runner harbor online false 9
tick "$((NOW + 1200))"
t_eq "recovery is one line" 2 "$(alog)"
t_has "...that says it cleared and what it was" "$(last)" "cleared (was: docker down"
t_eq "...and the cache is clean" "false 0" "$(get '"\(.docker_down) \(.offline | length)"')"
tick "$((NOW + 1500))"
t_eq "control: the tick after adds nothing" 2 "$(alog)"

t_section "an org's second runner is watched like its first (harbor#1060)"
o2h() { healthy; printf 'org SomeOrg runners 2\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
        container someorg-linux port-linux-runner:local running; container someorg-linux-2 port-linux-runner:local running; }
o2h; orgrunners online false offline false; tick "$NOW"; tick "$((NOW + 300))"
t_has "someorg-linux-2 offline on two ticks: alarmed by name" "$(last)" "offline someorg-linux-2"
t_eq "...once, though the org has two rows" someorg-linux-2 "$(get '.offline | join(" ")')"
o2h; orgrunners online false online false; tick "$NOW"; tick "$((NOW + 300))"
t_eq "control: both online, nothing" 0 "$(alog)"

t_section "what is not an alarm"
healthy; runner alpha offline false; tick "$NOW"; runner alpha online false; tick "$((NOW + 300))"
t_eq "a runner offline on one tick only (updating itself) never alarms" 0 "$(alog)"
healthy; runner alpha offline false; tick "$NOW"; tick "$((NOW + 1000))"
t_eq "a sighting carried from a cache over 600s old starts again" 0 "$(alog)"
tick "$((NOW + 1300))"
t_eq "...and confirms on the tick after" 1 "$(alog)"
healthy; runner alpha offline false; printf '{"parked":["alpha-linux"]}\n' > "$CACHE/ci-governor.json"
tick "$NOW"; tick "$((NOW + 300))"
t_eq "a runner the governor parked on purpose is not an alarm" 0 "$(alog)"
healthy; printf 'alarm off\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; : > "$FX/docker.fail"; runner alpha offline false
tick "$NOW"; tick "$((NOW + 300))"
t_eq "alarm off in the config: no line" 0 "$(alog)"
t_eq "...and no cache for the statusline" no "$([ -f "$A" ] && echo yes || echo no)"
healthy; : > "$FX/runners.fail"; tick "$NOW"; tick "$((NOW + 300))"
t_eq "GitHub not answering about any runner is unread, not an outage" true "$(get .unread)"
t_eq "...and no line" 0 "$(alog)"

t_section "a held repo's runner is watched: other-mac serving zorbcorp"
healthy; printf 'hold held other-mac serves it\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
printf '{"runners":[{"id":3,"name":"other-mac","status":"offline","busy":false,"labels":[{"name":"self-hosted"}]}]}\n' > "$FX/runners/held.json"
tick "$NOW"; tick "$((NOW + 300))"
t_has "an offline runner registered to a held repo alarms" "$(last)" "offline other-mac"

t_section "an org-level runner and its org's repos are watched (the org runner of #1067)"
healthy; orgconf; orgrunner offline false
tick "$NOW"; tick "$((NOW + 300))"
t_has "an offline org runner alarms" "$(last)" "offline someorg-linux"
healthy; orgconf; orgrunner offline false; queue orgrepo queued 601 1200 '["self-hosted"]' 1200; tick "$NOW"
t_has "an org repo's job its offline org runner cannot take alarms at once" "$(last)" "with no runner able to take them on orgrepo"
healthy; orgconf; orgrunner online false; queue orgrepo queued 601 1200 '["self-hosted"]' 1200; tick "$NOW"; tick "$((NOW + 300))"
t_eq "control: the org runner online, the org's queue is only a queue" 0 "$(alog)"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "a self-hosted job queued past the limit with no runner able to take it"
MAC='["self-hosted","macOS"]'; LIN='["self-hosted"]'
healthy; queue alpha queued 501 1200 "$MAC" 1200; tick "$NOW"
t_eq "a macOS job 20 minutes queued, only a Linux runner online: one line at once" 1 "$(alog)"
t_has "...naming the repo" "$(last)" "with no runner able to take them on alpha"
t_eq "the cache counts it, with when it was queued" "1 $((NOW - 1200))" "$(get '"\(.stuck.jobs) \(.stuck.oldest)"')"
tick "$((NOW + 300))"
t_eq "...and not again while it waits" 1 "$(alog)"
healthy; queue alpha queued 501 300 "$MAC" 300; tick "$NOW"
t_eq "control: queued 5 minutes is under the 10-minute limit" 0 "$(alog)"
healthy; queue alpha queued 501 1200 "$LIN" 1200; tick "$NOW"
t_eq "control: a runner whose labels cover the job is online, so it is a queue, not an alarm" 0 "$(alog)"
healthy; queue alpha queued 501 1200 '["ubuntu-24.04"]' 1200; tick "$NOW"
t_eq "control: a hosted job is GitHub's to start" 0 "$(alog)"
healthy; queue alpha queued 501 100000 "$MAC" 100000; tick "$NOW"
t_eq "control: a run over a day old is a ghost, never an alarm" 0 "$(alog)"
healthy; runner alpha offline false; queue alpha in_progress 502 1200 "$LIN" 900; tick "$NOW"
t_eq "a job left queued in a running run, its only runner offline, alarms at once" 1 "$(alog)"
t_has "...as a job with no runner" "$(last)" "with no runner able to take them on alpha"

t_section "a gate job with no online gate runner is an alarm, a pool-only fleet cannot take it (harbor#1286)"
GATE='["self-hosted","Linux","ARM64","harbor-gate"]'
gharbor() { # <gate status> — the governance repo's runners: a pool runner online, and harbor-gate as given
  mkdir -p "$FX/runners"
  printf '{"runners":[{"id":9,"name":"harbor-linux","status":"online","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"ARM64"},{"name":"harbor-pool"}]},{"id":11,"name":"harbor-gate","status":"%s","busy":false,"labels":[{"name":"self-hosted"},{"name":"Linux"},{"name":"ARM64"},{"name":"harbor-gate"}]}]}\n' "$1" > "$FX/runners/harbor.json"
}
healthy; gharbor online; queue harbor queued 701 1200 "$GATE" 1200; tick "$NOW"
t_eq "control: harbor-gate online, a gate job queued is only a queue" 0 "$(alog)"
healthy; gharbor offline; queue harbor queued 701 1200 "$GATE" 1200; tick "$NOW"
t_eq "harbor-gate offline, a gate job queued 20 minutes: no online runner carries harbor-gate, so one line at once" 1 "$(alog)"
t_has "...naming harbor" "$(last)" "with no runner able to take them on harbor"
tick "$((NOW + 300))"
t_has "...and the offline gate runner by name on the confirming tick" "$(last)" "offline harbor-gate"

t_section "the stubs were told every call, and no billing was read"
t_eq "no unexpected gh or docker call" 0 "$(nlines "$FX/unexpected.log")"
t_eq "no billing, budget or spending-limit call" 0 "$(grep -c -i -e billing -e budget -e spending "$FX/gh.log" || true)"
t_done
