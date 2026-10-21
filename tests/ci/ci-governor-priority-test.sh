#!/usr/bin/env sh
# ci-governor.sh governs every Linux runner container it discovers, in two priority classes (harbor#1060):
# day-to-day repos' jobs get cores first, harbor / Fleet / Yard (low_priority) what remains, never under
# linux_min. Shims and helpers in ci-governor-fixture.sh; the budget itself is ci-governor-test.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/ci-governor-fixture.sh"

CONF="$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
fresh() { reset; rm -f "$CONF"; }   # the shipped defaults: no mac_runners, discovery, the default low_priority
busy() { if [ "$1" = harbor-linux ]; then : > "$FX/lbusy"; else : > "$FX/$1.lbusy"; fi; }
idle() { if [ "$1" = harbor-linux ]; then rm -f "$FX/lbusy"; else rm -f "$FX/$1.lbusy"; fi; }
nps() { grep -c '^ps' "$FX/docker.calls"; }
ran_on() { grep -c "^inspect .* $1\$" "$FX/docker.calls"; }
J="$CACHE/ci-governor.json"

t_section "discovery: every running *-linux container built on the actions-runner image, one docker ps a tick"
fresh; ctr quuxmail-linux; ctr estate-linux
echo "postgres-db $RL" >> "$FX/ps"; echo "web-linux https://github.com/nginx/nginx" >> "$FX/ps"; echo "bare-linux" >> "$FX/ps"
gov tick >/dev/null
t_eq "three runner containers discovered" "estate-linux harbor-linux quuxmail-linux" "$(jq -r '[.runners[].name] | join(" ")' "$J")"
t_eq "...from exactly one docker ps" 1 "$(nps)"
t_eq "a runner image not named *-linux is not governed" 0 "$(ran_on postgres-db)"
t_eq "a *-linux container of another image is not governed" 0 "$(ran_on web-linux)"
t_eq "...nor one with no image source label" 0 "$(ran_on bare-linux)"
tick
t_eq "the next tick discovers again: one more docker ps, not one per container" 2 "$(nps)"
ctr studio-linux; tick
t_eq "a container provisioned since the last tick is governed on the next" 1 "$(ran_on studio-linux)"

t_section "linux_runners in the config overrides discovery"
fresh; ctr quuxmail-linux; ctr estate-linux; printf 'linux_runners=quuxmail-linux\n' > "$CONF"; gov tick >/dev/null
t_eq "only the listed container is governed" quuxmail-linux "$(jq -r '[.runners[].name] | join(" ")' "$J")"
t_eq "...and docker ps is never asked" 0 "$(nps)"
t_eq "...the unlisted one is left alone" 0 "$(ran_on estate-linux)"

t_section "idle containers sit at linux_min"
fresh; ctr quuxmail-linux; ctr estate-linux; gov tick >/dev/null
t_eq "harbor-linux idle: 1" 1 "$(ccpus harbor-linux)"
t_eq "quuxmail-linux idle: 1" 1 "$(ccpus quuxmail-linux)"
t_eq "estate-linux idle: 1" 1 "$(ccpus estate-linux)"
t_eq "no CI cores are held by idle containers" 0 "$(st ci_cores)"
fresh; printf 'linux_min=2\n' > "$CONF"; ctr quuxmail-linux; gov tick >/dev/null
t_eq "the floor follows linux_min" 2 "$(ccpus quuxmail-linux)"

t_section "a low-priority job alone gets the whole budget"
fresh; ctr quuxmail-linux; busy harbor-linux; gov tick >/dev/null
t_eq "harbor-linux busy, every day-to-day container idle: budget 4 to harbor-linux" 4 "$(ccpus harbor-linux)"
t_eq "...the idle one at its floor" 1 "$(ccpus quuxmail-linux)"
fresh; ctr projects-orchestrator-linux busy; busy harbor-linux; gov tick >/dev/null
t_eq "two low jobs (harbor, Fleet) split it evenly: harbor-linux 2" 2 "$(ccpus harbor-linux)"
t_eq "...projects-orchestrator-linux 2" 2 "$(ccpus projects-orchestrator-linux)"

t_section "a normal job cuts a busy low job to linux_min on the same tick, and the end restores it"
fresh; ctr quuxmail-linux; busy harbor-linux; gov tick >/dev/null
t_eq "(setup) harbor-linux busy alone at 4" 4 "$(ccpus harbor-linux)"
busy quuxmail-linux; : > "$FX/updates.log"; tick
t_eq "quuxmail-linux's job starts: harbor-linux is cut to linux_min 1 on that tick" 1 "$(ccpus harbor-linux)"
t_eq "...and quuxmail-linux gets the rest, 3" 3 "$(ccpus quuxmail-linux)"
t_eq "...the cut is applied before the raise" "harbor-linux 1" "$(head -1 "$FX/updates.log")"
t_has "...in one log line naming both" "$(tail -1 "$CACHE/checks.log")" "harbor-linux --cpus 4 -> 1"
t_has "...both" "$(tail -1 "$CACHE/checks.log")" "quuxmail-linux --cpus 1 -> 3"
idle quuxmail-linux; tick
t_eq "quuxmail-linux's job ends: harbor-linux is back to 4 on that tick" 4 "$(ccpus harbor-linux)"
t_eq "...and quuxmail-linux back at its floor" 1 "$(ccpus quuxmail-linux)"
fresh; ctr project-init-linux busy; ctr studio-linux busy; gov tick >/dev/null
t_eq "Yard (project-init-linux) is low too: cut to 1 under studio-linux's job" 1 "$(ccpus project-init-linux)"
t_eq "...studio-linux 3" 3 "$(ccpus studio-linux)"

t_section "two normal jobs split evenly; a low job is never starved"
fresh; ctr quuxmail-linux busy; ctr estate-linux busy; gov tick >/dev/null
t_eq "budget 4, two day-to-day jobs: quuxmail-linux 2" 2 "$(ccpus quuxmail-linux)"
t_eq "...estate-linux 2" 2 "$(ccpus estate-linux)"
t_eq "...harbor-linux idle at 1" 1 "$(ccpus harbor-linux)"
fresh; echo 700 > "$FX/idle"; ctr quuxmail-linux busy; ctr estate-linux busy; busy harbor-linux; gov tick >/dev/null
t_eq "budget 8, two normal and one low: each normal job 3 (8 less the low floor, halved)" 3 "$(ccpus estate-linux)"
t_eq "...harbor-linux the remaining 2" 2 "$(ccpus harbor-linux)"
fresh; ctr quuxmail-linux busy; ctr estate-linux busy; ctr studio-linux busy; ctr zarija-linux busy; busy harbor-linux; gov tick >/dev/null
t_eq "four normal jobs on budget 4 still leave harbor-linux its floor, never 0" 1 "$(ccpus harbor-linux)"
t_eq "...and each normal one at least linux_min" 1 "$(ccpus zarija-linux)"

t_section "a low job past lift_after keeps lift_cpus under a day-to-day job (harbor#1060: suites timed out at its floor, load 20+)"
age() { if [ "$1" = harbor-linux ]; then echo "$2" > "$FX/age"; else echo "$2" > "$FX/$1.age"; fi; }
fresh; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 300; gov tick >/dev/null
t_eq "a young low job (300s) is cut to linux_min under a day-to-day job, as before" 1 "$(ccpus harbor-linux)"
t_eq "...and the day-to-day job gets the rest" 3 "$(ccpus quuxmail-linux)"
age harbor-linux 899; tick
t_eq "899s, one second short of lift_after 900: still cut" 1 "$(ccpus harbor-linux)"
age harbor-linux 900; : > "$FX/updates.log"; tick
t_eq "900s: harbor-linux keeps lift_cpus 2" 2 "$(ccpus harbor-linux)"
t_eq "...the day-to-day job still gets the other 2, never starved" 2 "$(ccpus quuxmail-linux)"
t_has "...in one log line that says why" "$(tail -1 "$CACHE/checks.log")" "harbor-linux --cpus 1 -> 2 (job over 900s keeps its lift)"
t_has "status marks the aged job" "$(gov status)" "harbor-linux low busy cpus=2 aged"
t_eq "the cache stays the same shape" '{"name":"harbor-linux","class":"low","state":"busy","cpus":2}' "$(jq -c '.runners[0]' "$J")"
age harbor-linux 5; tick
t_eq "the next job on that runner is young again: cut back to linux_min" 1 "$(ccpus harbor-linux)"
fresh; busy harbor-linux; age harbor-linux 2000; gov tick >/dev/null
t_eq "an old low job with no day-to-day job still gets the whole budget, not just the lift" 4 "$(ccpus harbor-linux)"
fresh; ctr quuxmail-linux busy; busy harbor-linux; gov tick >/dev/null
t_eq "no age readable (ps silent): never aged, so cut" 1 "$(ccpus harbor-linux)"
fresh; printf 'lift_after=0\n' > "$CONF"; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 5000; gov tick >/dev/null
t_eq "lift_after=0 turns the lift off: a very old low job is cut" 1 "$(ccpus harbor-linux)"
fresh; printf 'lift_after=60\nlift_cpus=3\n' > "$CONF"; echo 700 > "$FX/idle"; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 61; gov tick >/dev/null
t_eq "lift_after and lift_cpus are config keys (budget 8: lift 3)" 3 "$(ccpus harbor-linux)"
t_eq "...the day-to-day job gets the other 5" 5 "$(ccpus quuxmail-linux)"
fresh; ctr quuxmail-linux busy; ctr estate-linux busy; ctr studio-linux busy; busy harbor-linux; age harbor-linux 1000; gov tick >/dev/null
t_eq "three day-to-day jobs on budget 4: the lift is limited to what leaves each its floor (1)" 1 "$(ccpus harbor-linux)"
t_eq "...so no day-to-day job is cut under linux_min to pay for it" "1 1 1" "$(ccpus quuxmail-linux) $(ccpus estate-linux) $(ccpus studio-linux)"
fresh; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 1000; ctr projects-orchestrator-linux busy; age projects-orchestrator-linux 5; gov tick >/dev/null
t_eq "an aged and a young low job beside one day-to-day job: aged keeps 2" 2 "$(ccpus harbor-linux)"
t_eq "...the young one is cut to linux_min" 1 "$(ccpus projects-orchestrator-linux)"
t_eq "...the day-to-day job is not cut under linux_min" 1 "$(ccpus quuxmail-linux)"
fresh; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 1000; echo 4 > "$FX/mem"; gov sample >/dev/null
t_eq "an emergency still takes every runner to its emergency cap, lift or not" "0.5" "$(awk -v n="$(cat "$FX/nano")" 'BEGIN { printf "%g", n / 1e9 }')"

t_section "the lift is lift_cpus exactly, never what integer division left over (review of #1129)"
fresh; printf 'idle_budget=10\n' > "$CONF"; echo 16 > "$FX/vmcpus"; echo 700 > "$FX/idle"
ctr quuxmail-linux busy; ctr estate-linux busy; ctr studio-linux busy; busy harbor-linux; age harbor-linux 1000; gov tick >/dev/null
t_eq "budget 10, three day-to-day jobs and an aged harbor job: harbor-linux gets lift_cpus, 2" 2 "$(ccpus harbor-linux)"
t_eq "...the day-to-day jobs 2 each, never under what the lift costs them" "2 2 2" "$(ccpus quuxmail-linux) $(ccpus estate-linux) $(ccpus studio-linux)"
printf 'idle_budget=10\nlift_after=0\n' > "$CONF"; tick
t_eq "control, lift off: harbor-linux 1" 1 "$(ccpus harbor-linux)"
t_eq "...and the day-to-day jobs 3 each" "3 3 3" "$(ccpus quuxmail-linux) $(ccpus estate-linux) $(ccpus studio-linux)"

t_section "a probe that errors is unknown, and unknown is never lifted (review of #1129)"
fresh; ctr quuxmail-linux busy; busy harbor-linux; age harbor-linux 1000; gov tick >/dev/null
t_eq "(setup) aged and readable: lifted" 2 "$(ccpus harbor-linux)"
echo 127 > "$FX/execrc"; tick
t_has "pgrep missing (exit 127) reads unknown, not idle" "$(gov status)" "harbor-linux low unknown"
t_eq "...and an unknown job is not lifted: cut to linux_min" 1 "$(ccpus harbor-linux)"
echo 2 > "$FX/execrc"; tick
t_has "pgrep erroring (exit 2) reads unknown too" "$(gov status)" "harbor-linux low unknown"
t_eq "...not lifted" 1 "$(ccpus harbor-linux)"
echo 1 > "$FX/execrc"; tick
t_has "control: exit 1 is still no worker, idle" "$(gov status)" "harbor-linux low idle"
rm -f "$FX/execrc"; tick
t_eq "the probe back: lifted again" 2 "$(ccpus harbor-linux)"

t_section "harbor-linux-2, the second governance runner, is discovered and low priority (harbor#1060)"
fresh; ctr harbor-linux-2; ctr quuxmail-linux; gov tick >/dev/null
t_eq "a *-linux-<digit> runner container is discovered" "harbor-linux harbor-linux-2 quuxmail-linux" "$(jq -r '[.runners[].name] | join(" ")' "$J")"
t_eq "...idle at linux_min" 1 "$(ccpus harbor-linux-2)"
t_eq "...low priority with no config, by the numbered twin of harbor-linux" "low low normal" "$(jq -r '[.runners[].class] | join(" ")' "$J")"
fresh; ctr harbor-linux-2 busy; gov tick >/dev/null
t_eq "a busy harbor-linux-2 alone gets the whole budget" 4 "$(ccpus harbor-linux-2)"
fresh; ctr harbor-linux-2 busy; busy harbor-linux; gov tick >/dev/null
t_eq "two busy governance runners split it evenly: harbor-linux 2" 2 "$(ccpus harbor-linux)"
t_eq "...harbor-linux-2 2" 2 "$(ccpus harbor-linux-2)"
fresh; ctr harbor-linux-2 busy; ctr quuxmail-linux busy; gov tick >/dev/null
t_eq "a day-to-day job cuts a busy harbor-linux-2 to linux_min, as it does harbor-linux" "1 3" "$(ccpus harbor-linux-2) $(ccpus quuxmail-linux)"
fresh; printf 'low_priority=quuxmail-linux\n' > "$CONF"; ctr harbor-linux-2; gov tick >/dev/null
t_eq "a twin follows its base name: with harbor-linux out of low_priority, so is harbor-linux-2" "normal normal" "$(jq -r '[.runners[].class] | join(" ")' "$J")"
fresh; ctr harbor-linux-2; printf 'web-linux-2 %s\n' "https://github.com/nginx/nginx" >> "$FX/ps"; gov tick >/dev/null
t_eq "a *-linux-<digit> container of another image is not governed" 0 "$(ran_on web-linux-2)"

fresh; ctr someorg-linux busy; ctr someorg-linux-2 busy; gov tick >/dev/null
t_eq "an org's second runner, <org>-linux-2, is discovered beside its first" "harbor-linux someorg-linux someorg-linux-2" "$(jq -r '[.runners[].name] | join(" ")' "$J")"
t_eq "...at normal priority, as its first is" "low normal normal" "$(jq -r '[.runners[].class] | join(" ")' "$J")"
t_eq "...the two busy ones split the budget evenly" "2 2" "$(ccpus someorg-linux) $(ccpus someorg-linux-2)"

t_section "gate runners are outside the governor (harbor#1286)"
fresh; ctr harbor-gate busy; ctr harbor-gate-2 busy; busy harbor-linux; gov tick >/dev/null
t_eq "a gate runner (harbor-gate, not *-linux) is never discovered: the governor never moves its cpus (harbor#1286)" "harbor-linux" "$(jq -r '[.runners[].name] | join(" ")' "$J")"
t_eq "...the governor never inspected or updated it, even busy beside a busy pool runner" 0 "$(grep -c 'harbor-gate' "$FX/docker.calls")"

t_section "low_priority in the config names the classes"
fresh; printf 'low_priority=quuxmail-linux\n' > "$CONF"; ctr quuxmail-linux busy; busy harbor-linux; gov tick >/dev/null
t_eq "quuxmail-linux made low: harbor-linux (now normal) gets 3" 3 "$(ccpus harbor-linux)"
t_eq "...quuxmail-linux 1" 1 "$(ccpus quuxmail-linux)"
t_eq "the state names each runner's class" "harbor-linux=normal quuxmail-linux=low" \
  "$(jq -r '[.runners[] | "\(.name)=\(.class)"] | join(" ")' "$J")"

t_section "no mac runners configured (the default): nothing on the Mac is managed or asked about"
fresh; ctr quuxmail-linux busy; gov tick >/dev/null; echo 12.00 > "$FX/load"; tick 30; tick 60
t_eq "(setup) a sustained load cut the budget to 2" 2 "$(st budget)"
t_eq "harbor-mac's idle listener is never stopped" 0 "$(nsvc stop)"
t_eq "...GitHub is never asked" 0 "$(ngh api)"
t_eq "...nothing is parked" "" "$(st parked)"
t_eq "...and quuxmail-linux still gets the budget" 2 "$(ccpus quuxmail-linux)"
fresh; printf '%s\n%s\n%s\n' "$MACL" "$GTML" "$MACW" > "$FX/procs"; ctr quuxmail-linux busy; gov tick >/dev/null
t_eq "a harbor-mac Worker, unmanaged, counts as a foreign job: quuxmail-linux gets 2 of 4" 2 "$(ccpus quuxmail-linux)"
echo 4 > "$FX/mem"; gov sample >/dev/null
t_eq "...and an emergency never backgrounds it" no "$([ -f "$FX/taskpolicy.log" ] && echo yes || echo no)"

t_section "status and the statusline cache"
fresh; ctr quuxmail-linux busy; busy harbor-linux; gov tick >/dev/null
O="$(gov status)"
t_has "status lists each container with its class, busy/idle and cpus" "$O" "harbor-linux low busy cpus=1"
t_has "...every one" "$O" "quuxmail-linux normal busy cpus=3"
t_eq "the cache's runner entry" '{"name":"quuxmail-linux","class":"normal","state":"busy","cpus":3}' "$(jq -c '.runners[1]' "$J")"
t_eq "...and its existing fields stay" "4 4 false false" "$(jq -r '"\(.budget) \(.target) \(.held) \(.emergency)"' "$J")"
t_eq "...listener_pid included" true "$(jq 'has("listener_pid") and has("linux") and has("mac")' "$J")"

t_section "a job event from any container reaches a decision"
fresh; printf 'sample_interval=0.2\n' > "$CONF"; ctr quuxmail-linux; busy harbor-linux
HARBOR_NOW="$AT" HARBOR_CACHE_DIR="$CACHE" HARBOR_RUNNERS_DIR="$RUNNERS" sh "$GOV" listen >/dev/null 2>&1 & LST=$!
_i=0; while [ ! -f "$FX/notify.waiting" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
_i=0; while [ "$(ccpus harbor-linux)" != 4 ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
t_eq "(setup) the listener gave harbor-linux the budget" 4 "$(ccpus harbor-linux)"
busy quuxmail-linux; echo "1790000000 1 build" >> "$FX/trigger"
_i=0; while [ "$(ccpus harbor-linux)" != 1 ] && [ "$_i" -lt 50 ]; do sleep 0.1; _i=$((_i + 1)); done
t_eq "quuxmail-linux's hook line in the shared trigger file: harbor-linux cut to 1" 1 "$(ccpus harbor-linux)"
kill -TERM "$LST" 2>/dev/null; wait "$LST" 2>/dev/null
_sp="$(awk '{print $1}' "$SD/sampler" 2>/dev/null)"; [ -z "$_sp" ] || kill "$_sp" 2>/dev/null

t_done
