#!/usr/bin/env sh
# ci-queue.sh's estimate and stall read against a fake gh (harbor#657, #152). The stub serves one
# fixture file per endpoint and fails for any it has none for: that is "GitHub did not answer".
# One repo, two runner folders: run 1 has A running 100s of its usual 600s, B done, C queued; run 2
# is queued with no jobs listed, so it needs the workflow's usual set. Schedules are worked by hand.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; RUN="$T_TMP/runners"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"
mkdir -p "$FX" "$RUN/r1" "$RUN/r2" "$RUN/s1"
NOW=1790000000
iso() { jq -rn --argjson t "$1" '$t | todate'; }
# The runner's own registration files, with the byte-order mark it writes.
printf '\357\273\277{"gitHubUrl":"https://github.com/o/r"}' > "$RUN/r1/.runner"
printf '\357\273\277{"gitHubUrl":"https://github.com/o/r"}' > "$RUN/r2/.runner"
printf '\357\273\277{"gitHubUrl":"https://github.com/o/s"}' > "$RUN/s1/.runner"
fxname() { printf '%s/%s' "$FX" "$(printf '%s' "$1" | tr '/?&=' '____')"; }
fx() { printf '%s\n' "$2" > "$(fxname "$1")"; }
cat > "$GH" <<'EOF'
#!/bin/sh
f="$FX/$(printf '%s' "$2" | tr '/?&=' '____')"
[ "$1" = api ] && [ -f "$f" ] && cat "$f"
EOF
chmod +x "$GH"

A_START="$(iso $((NOW - 100)))"
fx 'repos/o/r/actions/runs?status=in_progress&per_page=50' \
   '{"workflow_runs":[{"id":1,"workflow_id":7,"created_at":"'"$(iso $((NOW - 300)))"'"}]}'
fx 'repos/o/r/actions/runs?status=queued&per_page=50' \
   '{"workflow_runs":[{"id":2,"workflow_id":7,"created_at":"'"$(iso $((NOW - 60)))"'"},
                      {"id":3,"workflow_id":7,"created_at":"'"$(iso $((NOW - 40 * 86400)))"'"}]}'
fx 'repos/o/r/actions/runs/1/jobs?per_page=100' \
   '{"jobs":[{"name":"A","status":"in_progress","started_at":"'"$A_START"'"},
             {"name":"B","status":"completed","started_at":"'"$A_START"'"},
             {"name":"C","status":"queued","started_at":null}]}'
fx 'repos/o/r/actions/runs/2/jobs?per_page=100' '{"jobs":[]}'
fx 'repos/o/r/actions/workflows/7/runs?status=success&per_page=3' '{"workflow_runs":[{"id":10},{"id":11},{"id":12}]}'
hist() { # <run id> <A secs> — B is always 60s and C 300s
  fx "repos/o/r/actions/runs/$1/jobs?per_page=100" \
     '{"jobs":[{"name":"A","conclusion":"success","started_at":"'"$(iso 1000)"'","completed_at":"'"$(iso $((1000 + $2)))"'"},
               {"name":"B","conclusion":"success","started_at":"'"$(iso 1000)"'","completed_at":"'"$(iso 1060)"'"},
               {"name":"C","conclusion":"success","started_at":"'"$(iso 1000)"'","completed_at":"'"$(iso 1300)"'"}]}'
}
hist 10 580; hist 11 600; hist 12 900    # A's median is 600, not the 693 mean; o/s has no fixtures

qat() { _t="$1"; shift; FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_CI_RUNNERS_DIR="$RUN" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_DOCKER="${QDOCKER:-false}" \
          HARBOR_TEST_NOW="$_t" sh "$T_ROOT/bin/ci-queue.sh" "$@"; }
q() { qat "$NOW" "$@"; }
get() { jq -r --arg r "$1" ".repos[] | select(.repo == \$r) | $2" "$CACHE/ci-queue.json"; }

t_section "two runners: the hand-worked schedule"
t_exit "a good fixture exits 0" 0 q
# Left: run 1's A and C, plus run 2's assumed A, B, C. Run 3 is a 40-day-old ghost.
t_eq "o/r jobs left" 5 "$(get o/r .left)"
t_eq "o/r runners come from its .runner files" 2 "$(get o/r .runners)"
t_eq "the 40-day-old queued run is a ghost" 1 "$(get o/r .ghosts)"
# Free [0,500]. C 300 -> [300,500]; A 600 -> [500,900]; B 60 -> [560,900]; C 300 -> [860,900].
t_eq "o/r is free at NOW+900" $((NOW + 900)) "$(get o/r .eta)"
t_eq "a repo GitHub did not answer for is unread" true "$(get o/s .unread)"
t_eq "the cache carries the time it was written" "$NOW" "$(jq -r .at "$CACHE/ci-queue.json")"

t_section "a third runner shortens it, with no edit to the script"
mkdir -p "$RUN/r3"; cp "$RUN/r1/.runner" "$RUN/r3/.runner"; q
# Free [0,0,500]: C -> [0,300,500]; A -> [300,500,600]; B -> [360,500,600]; C -> [500,600,660].
t_eq "three runners finish at NOW+660" $((NOW + 660)) "$(get o/r .eta)"
rm -rf "$RUN/r3"

t_section "a job past its usual length is due now, never negative"
fx 'repos/o/r/actions/runs?status=queued&per_page=50' '{"workflow_runs":[]}'
fx 'repos/o/r/actions/runs/1/jobs?per_page=100' \
   '{"jobs":[{"name":"A","status":"in_progress","started_at":"'"$(iso $((NOW - 5000)))"'"}]}'
q
t_eq "an overrunning job reads as due now" "$NOW" "$(get o/r .eta)"

t_section "runner containers name their repo in RUNNER_URL; a gate container is not parallelism"
# A docker stub: three o/r containers (one a gate), one org runner with no repo.
cat > "$T_TMP/docker" <<'DK'
#!/bin/sh
case "$1" in
  ps) printf 'r-linux\nr-linux-2\nr-gate\norg-linux\n' ;;
  inspect) case "$4" in org-linux) echo 'RUNNER_URL=https://github.com/o' ;; *) echo 'RUNNER_URL=https://github.com/o/r' ;; esac ;;
esac
DK
chmod +x "$T_TMP/docker"
mv "$RUN" "$RUN.off"; mkdir -p "$RUN"
QDOCKER="$T_TMP/docker" q
t_eq "two o/r containers with no .runner on the host are two runners" 2 "$(get o/r .runners)"
t_eq "the org runner adds no repo" 1 "$(jq '.repos | length' "$CACHE/ci-queue.json")"
rm -rf "$RUN"; mv "$RUN.off" "$RUN"

t_section "idle, and no runners at all"
fx 'repos/o/r/actions/runs?status=in_progress&per_page=50' '{"workflow_runs":[]}'
q
t_eq "an idle repo has no jobs left" 0 "$(get o/r .left)"
t_eq "an idle repo has no eta" null "$(get o/r .eta)"
t_exit "no runner folders still exits 0" 0 env HARBOR_CI_RUNNERS_DIR="$T_TMP/none" HARBOR_DOCKER=false FX="$FX" HARBOR_TEST_GH="$GH" \
  HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_TEST_NOW="$NOW" sh "$T_ROOT/bin/ci-queue.sh"
t_eq "no runner folders write an empty repo list" '[]' "$(jq -c .repos "$CACHE/ci-queue.json")"

t_section "a wedged runner is not a busy one (harbor#152)"
stall_fx() { # <job-age-secs> <labels-json> <r1-busy true|false> [r1-labels-json]
  fx 'repos/o/r/actions/runs?status=in_progress&per_page=50' '{"workflow_runs":[]}'
  fx 'repos/o/r/actions/runs?status=queued&per_page=50' \
     '{"workflow_runs":[{"id":4,"workflow_id":7,"created_at":"'"$(iso $((NOW - $1)))"'"}]}'
  fx 'repos/o/r/actions/runs/4/jobs?per_page=100' \
     '{"jobs":[{"name":"A","status":"queued","started_at":null,"created_at":"'"$(iso $((NOW - $1)))"'","labels":'"$2"'}]}'
  fx 'repos/o/r/actions/runners?per_page=100' \
     '{"runners":[{"name":"r1","status":"online","busy":'"$3"',"labels":'"${4:-$MAC_RUNNER}"'},
                   {"name":"r2","status":"online","busy":true,"labels":'"$MAC_RUNNER"'}]}'
  rm -f "$CACHE/ci-queue.json"
}
SH_LBL='["self-hosted","macOS","ARM64"]'
# GitHub matches runner labels case-blind, so one is lower-cased here on purpose.
MAC_RUNNER='[{"name":"self-hosted"},{"name":"macos"},{"name":"ARM64"}]'
stall_fx 900 "$SH_LBL" false; qat "$NOW"
t_eq "one refresh is never a stall (#279)" false "$(get o/r .stall)"
t_eq "one refresh is a suspect, since now" "$NOW" "$(get o/r .suspect_since)"
qat $((NOW + 300))
t_eq "a queued job and an idle runner on two refreshes is a stall" true "$(get o/r .stall)"
t_eq "the suspicion keeps its first-seen time" "$NOW" "$(get o/r .suspect_since)"
t_eq "the stall does not disturb the estimate" 1 "$(get o/r .left)"
SP="$(qat $((NOW + 600)) --print)"
t_has "--print names the stall" "$SP" 'STALL'
t_has "--print names the idle runner's restart" "$SP" 'cd ~/runners/r1 && ./svc.sh stop && ./svc.sh start'
stall_fx 900 "$SH_LBL" true; qat "$NOW"; qat $((NOW + 300))
t_eq "every runner busy is a queue, not a stall" false "$(get o/r .stall)"
t_eq "…and raises no suspicion" null "$(get o/r .suspect_since)"
stall_fx 900 '["ubuntu-latest"]' false; qat "$NOW"; qat $((NOW + 300))
t_eq "a hosted job beside an idle self-hosted runner is not a stall" false "$(get o/r .stall)"
stall_fx 120 "$SH_LBL" false; qat "$NOW"; qat $((NOW + 300))
t_eq "a job queued two minutes is not stalled" false "$(get o/r .stall)"
t_eq "…and raises no suspicion" null "$(get o/r .suspect_since)"
stall_fx 900 "$SH_LBL" false; qat "$NOW"
stall_fx 900 "$SH_LBL" true
printf '%s\n' '{"at":'"$NOW"',"repos":[{"repo":"o/r","suspect_since":'"$NOW"'}]}' > "$CACHE/ci-queue.json"
qat $((NOW + 300))
t_eq "an unconfirmed suspicion does not ripen" false "$(get o/r .stall)"
t_eq "an unconfirmed suspicion clears" null "$(get o/r .suspect_since)"
stall_fx 900 "$SH_LBL" false; rm -f "$(fxname 'repos/o/r/actions/runners?per_page=100')"
qat "$NOW"; qat $((NOW + 300))
t_eq "an unreadable runner list is an unknown idle set" null "$(get o/r .idle)"
t_eq "an unreadable runner list is not a stall" false "$(get o/r .stall)"
t_eq "an unreadable runner list does not make the repo unread" yes "$([ "$(get o/r .unread)" != true ] && echo yes || echo no)"
t_eq "an unreadable runner list keeps the estimate" 1 "$(get o/r .left)"
stall_fx 900 "$SH_LBL" false '[{"name":"self-hosted"},{"name":"Linux"},{"name":"X64"}]'
qat "$NOW"; qat $((NOW + 300))
t_eq "an idle runner that could never take the job is not a stall (#699)" false "$(get o/r .stall)"
t_eq "…and raises no suspicion" null "$(get o/r .suspect_since)"
stall_fx 900 "$SH_LBL" false
printf '%s\n' '{"at":'"$((NOW - 7200))"',"repos":[{"repo":"o/r","suspect_since":'"$((NOW - 7500))"'}]}' > "$CACHE/ci-queue.json"
qat "$NOW"
t_eq "a suspicion across a two-hour gap is not a stall (#699)" false "$(get o/r .stall)"
t_eq "…it restarts the count from now" "$NOW" "$(get o/r .suspect_since)"

t_section "a failed write keeps the previous cache"
printf 'previous\n' > "$CACHE/ci-queue.json"; chmod 500 "$CACHE"
q >/dev/null 2>&1
chmod 700 "$CACHE"
t_eq "an unwritable cache dir leaves the previous file" previous "$(cat "$CACHE/ci-queue.json")"
t_done
