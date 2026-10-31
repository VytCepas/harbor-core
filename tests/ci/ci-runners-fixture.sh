#!/usr/bin/env sh
# Shared fixture for the ci-runners suites (harbor#1060): a fleet of seven repos under a temp port root, a
# fleet snapshot naming them, a stubbed gh and a stubbed docker. Both stubs record every call and fail on
# any call they were not told about, so the real GitHub, the real bill and the real containers are never reached.
# Sourced after t_init; sets FX CACHE GH DOCKER and the helpers below.
FX="$T_TMP/fx"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"; DOCKER="$T_TMP/docker"; PORT="$T_TMP/port"
EVENTS="$T_TMP/events"
mkdir -p "$FX" "$CACHE" "$PORT" "$EVENTS"
cat > "$GH" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/gh.log"
# key <slug> — the fixture file a scope is kept in: OWNER/NAME -> NAME, a bare org -> org.ORG. Only VytCepas and
# SomeOrg (the org the suites configure) are known: a call about any other owner is off script.
key() { case "$1" in VytCepas/*|SomeOrg/*) echo "${1#*/}" ;; SomeOrg) echo "org.$1" ;; *) echo "OFF-SCRIPT" ;; esac; }
scope() { echo "$1" | sed 's#^repos/##; s#^orgs/##; s#/actions/.*##; s#/check-runs/.*##'; }
# skey <api path> — key of the scope a path names; repos/ must name OWNER/NAME and orgs/ a bare org, or it is off script
skey() { _s="$(scope "$1")"; case "$1:$_s" in repos/*:*/*|orgs/*:*) case "$1:$_s" in orgs/*:*/*) echo OFF-SCRIPT; return ;; esac; key "$_s" ;; *) echo OFF-SCRIPT ;; esac; }
off() { echo "UNEXPECTED gh call: $*" >> "$FX/unexpected.log"; exit 1; }
flagok() { case "$1:$2" in --org:org.*|-R:*) case "$1:$2" in -R:org.*) return 1 ;; esac; return 0 ;; esac; return 1; }  # --org takes an org, -R a repo
case "$*" in
  "api -X POST repos/"*"/actions/runners/registration-token"|"api -X POST orgs/"*"/actions/runners/registration-token")
    n="$(skey "$4")"; [ "$n" != OFF-SCRIPT ] || off "$@"
    echo "$n" >> "$FX/token.asked"
    echo '{"token":"TOKEN-SECRET-4242"}' ;;
  "api repos/"*"/actions/runners"|"api orgs/"*"/actions/runners")
    n="$(skey "$2")"; [ "$n" != OFF-SCRIPT ] || off "$@"
    if [ -f "$FX/runners.fail" ]; then echo "gh: HTTP 500" >&2; exit 1; fi
    flip=cat   # ghflip.<scope>: N honest answers, then every runner reads busy (a job taken mid-run)
    if [ -f "$FX/ghflip.$n" ]; then c="$(cat "$FX/ghflip.$n")"; if [ "$c" -gt 0 ]; then echo $((c - 1)) > "$FX/ghflip.$n"; else flip="sed s/\"busy\":false/\"busy\":true/"; fi; fi
    if [ -f "$FX/runners/$n.json" ]; then $flip "$FX/runners/$n.json"; else echo '{"runners":[]}'; fi ;;
  "api -X DELETE repos/"*"/actions/runners/"*|"api -X DELETE orgs/"*"/actions/runners/"*)
    [ "$(skey "$4")" != OFF-SCRIPT ] || off "$@"
    echo "$*" >> "$FX/deletes.log" ;;
  "variable get CI_RUNS_ON -R "*|"variable get CI_RUNS_ON --org "*)
    n="$(key "$5")"; [ "$n" != OFF-SCRIPT ] || off "$@"
    flagok "$4" "$n" || off "$@"
    if [ -f "$FX/var/$n" ]; then cat "$FX/var/$n"; else echo "variable CI_RUNS_ON was not found" >&2; exit 1; fi ;;
  "variable set CI_RUNS_ON --body "*" -R "*|"variable set CI_RUNS_ON --body "*" --org "*" --visibility private")
    n="$(key "$7")"; [ "$n" != OFF-SCRIPT ] && flagok "$6" "$n" || off "$@"
    mkdir -p "$FX/var"; printf '%s\n' "$5" > "$FX/var/$n"; echo "set $n $5" >> "$FX/writes.log" ;;
  "variable delete CI_RUNS_ON -R "*|"variable delete CI_RUNS_ON --org "*)
    n="$(key "$5")"; [ "$n" != OFF-SCRIPT ] && flagok "$4" "$n" || off "$@"
    rm -f "$FX/var/$n"; echo "delete $n" >> "$FX/writes.log" ;;
  "run list -R "*)
    n="$(key "$4")"; case "$n" in OFF-SCRIPT|org.*) off "$@" ;; esac
    if [ -f "$FX/runs/$n.json" ]; then cat "$FX/runs/$n.json"; else echo '[]'; fi ;;
  "api repos/"*"/actions/runs?status="*)
    n="$(skey "$2")"; [ "$n" != OFF-SCRIPT ] || off "$@"
    st="$(echo "$2" | sed 's#.*status=##; s#&.*##')"
    if [ -f "$FX/queue.fail" ]; then echo "gh: HTTP 500" >&2; exit 1; fi
    if [ -f "$FX/queue/$n.$st.json" ]; then cat "$FX/queue/$n.$st.json"; else echo '{"workflow_runs":[]}'; fi ;;
  "api repos/"*"/actions/runs/"*"/jobs")
    [ "$(skey "$2")" != OFF-SCRIPT ] || off "$@"
    id="$(echo "$2" | sed 's#.*/runs/##; s#/jobs##')"; cat "$FX/jobs/$id.json" ;;
  "api repos/"*"/check-runs/"*"/annotations --jq "*)
    [ "$(skey "$2")" != OFF-SCRIPT ] || off "$@"
    id="$(echo "$2" | sed 's#.*/check-runs/##; s#/annotations##')"; jq -r '.[].message' "$FX/ann/$id.json" ;;
  "api repos/"*"/check-runs/"*"/annotations")
    [ "$(skey "$2")" != OFF-SCRIPT ] || off "$@"
    id="$(echo "$2" | sed 's#.*/check-runs/##; s#/annotations##')"; cat "$FX/ann/$id.json" ;;
  "run rerun "*" -R "*)
    [ "$(key "$5")" != OFF-SCRIPT ] || off "$@"
    [ ! -f "$FX/rerun.fail" ] || exit 1
    if [ "${6:-}" = --job ]; then echo "rerun $3 $5 job $7" >> "$FX/reruns.log"; else echo "rerun $3 $5" >> "$FX/reruns.log"; fi ;;
  *) off "$@" ;;
esac
STUB
cat > "$DOCKER" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/docker.log"
[ -f "$FX/docker.fail" ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
C="$FX/containers"; touch "$C"
case "$1 $2" in
  "ps -a") awk -F' ' '{printf "%s\t%s\t%s\n", $1, $2, $3}' "$C" ;;
  "top "*) if [ -f "$FX/busyafter.$2" ]; then n="$(cat "$FX/busyafter.$2")"   # idle for the first N looks, busy after: a job taken mid-run
             if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$FX/busyafter.$2"; else : > "$FX/busy.$2"; fi; fi
           [ -f "$FX/busy.$2" ] && echo "runner 1 Runner.Worker" || echo "runner 1 Runner.Listener"; true ;;
  "image inspect") [ "$3" = --format ] && { grep -qx "$5" "$FX/images" 2>/dev/null || exit 1; cat "$FX/tagid" 2>/dev/null || echo sha256:cur; exit 0; }
                   grep -qx "$3" "$FX/images" 2>/dev/null || { echo "No such image" >&2; exit 1; } ;;
  "inspect --format") case "$3" in '{{.Image}}') cat "$FX/cid.$4" 2>/dev/null || echo sha256:cur ;;
      '{{.HostConfig.Memory}}') cat "$FX/memory.$4" 2>/dev/null || echo 0 ;;
      '{{.State.Status}}') awk -v n="$4" '$1 == n { print $3; exit }' "$C" ;;   # running, exited: the state in the containers file
      *gov-events*) cat "$FX/events.$4" 2>/dev/null; true ;;
      *) cat "$FX/mounts.$4" 2>/dev/null; true ;; esac ;;
  "exec "*) c="$2"; shift 2   # wedge.<c>: the cgroup/worker read; ps.<c>: its processes; stubborn.<c>: pids TERM does not end
    case "$1" in
      ps) cat "$FX/ps.$c" 2>/dev/null; true ;;
      cat) [ "$2" = /sys/fs/cgroup/memory.current ] && [ -f "$FX/memcur.$c" ] || exit 1; cat "$FX/memcur.$c" ;;   # memcur.<c>: bytes in use; absent = unread
      sh) case "$3" in
            *Runner.Worker*) [ -f "$FX/wedge.fail.$c" ] && exit 1   # a hung or refused exec
              if [ -f "$FX/wedge.$c" ]; then cat "$FX/wedge.$c"; else printf 'oom_kill 0\nusage_usec 1000\n'; fi ;;
            *"kill -TERM"*|*"kill -KILL"*) sig=TERM; case "$3" in *KILL*) sig=KILL ;; esac; shift 4
              echo "$sig $c $*" >> "$FX/kills.log"
              for p in "$@"; do [ "$sig" = TERM ] && grep -qx "$p" "$FX/stubborn.$c" 2>/dev/null && continue
                awk -v p="$p" '$1 != p' "$FX/ps.$c" > "$FX/ps.$c.n"; mv "$FX/ps.$c.n" "$FX/ps.$c"; done ;;
            *) echo "UNEXPECTED docker call: exec $c $*" >> "$FX/unexpected.log"; exit 1 ;;
          esac ;;
      *) echo "UNEXPECTED docker call: exec $c $*" >> "$FX/unexpected.log"; exit 1 ;;
    esac ;;
  "info --format") [ "$3" = '{{.MemTotal}}' ] || { echo "UNEXPECTED docker call: $*" >> "$FX/unexpected.log"; exit 1; }
                   cat "$FX/vmmem" 2>/dev/null || echo 6442450944 ;;   # vmmem: the VM's memory in bytes (default 6 GiB)
  "update --memory") [ "$4" = --memory-swap ] && [ "$#" = 6 ] || { echo "UNEXPECTED docker call: $*" >> "$FX/unexpected.log"; exit 1; }
                     [ ! -f "$FX/update.fail" ] || { echo "Error response from daemon: cannot update" >&2; exit 1; }
                     echo "$3" > "$FX/memory.$6" ;;
  "start "*) sed "s/^$2 \([^ ]*\) .*/$2 \1 running/" "$C" > "$C.n"; mv "$C.n" "$C" ;;
  "rm -f") grep -v "^$3 " "$C" > "$C.n"; mv "$C.n" "$C"; rm -f "$FX/mounts.$3" "$FX/cid.$3" "$FX/memory.$3" "$FX/events.$3" ;;
  "run -d")
    [ -f "$FX/docker.runfail" ] && { echo "docker: run failed" >&2; exit 1; }
    shift; env=""; name=""; img=""; mem=0; : > "$FX/mounts.new"
    while [ $# -gt 0 ]; do
      case "$1" in --env-file) env="$2"; shift ;; --name) name="$2"; shift ;; --memory) mem="$2"; shift ;;
        -v) case "$2" in *:*:ro) rw=false ;; *) rw=true ;; esac
            echo "$2" | awk -F: -v rw="$rw" '{ print $1, $2, rw }' >> "$FX/mounts.new"; shift ;;
        -d|--restart|--cpus|--memory|-e) [ "$1" = -d ] || shift ;; *) img="$1" ;; esac
      shift
    done
    mv "$FX/mounts.new" "$FX/mounts.$name"
    printf '%s\n' "$mem" | awk '{ s = tolower($0); u = substr(s, length(s)); m = (u == "k") ? 1024 : (u == "m") ? 1048576 : (u == "g") ? 1073741824 : 1; printf "%.0f\n", (s + 0) * m }' > "$FX/memory.$name"
    m="$(stat -f %Lp "$env" 2>/dev/null || true)"; case "$m" in [0-7][0-7][0-7]) ;; *) m="$(stat -c %a "$env")" ;; esac
    echo "$m" > "$FX/envfile.mode"
    cp "$env" "$FX/envfile.captured"; echo "$env" > "$FX/envfile.path"
    echo "$name $img running" >> "$C"; echo "cid" ;;
  *) echo "UNEXPECTED docker call: $*" >> "$FX/unexpected.log"; exit 1 ;;
esac
STUB
chmod +x "$GH" "$DOCKER"

NOW=1790000000
NOWISO="$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)"
# mkrepo <name> <workflow-line> [manifest-line] [owner] — a fleet repo with a GitHub remote; owner "-": no remote at all
mkrepo() {
  mkdir -p "$PORT/$1/.github/workflows" "$PORT/$1/.agents"
  printf 'jobs:\n  t:\n    %s\n' "$2" > "$PORT/$1/.github/workflows/ci.yml"
  printf 'context: repo\n%s\n' "${3:-}" > "$PORT/$1/.agents/config.yaml"
  git -C "$PORT/$1" init -q 2>/dev/null
  [ "${4:-}" = - ] || git -C "$PORT/$1" remote add origin "https://github.com/${4:-VytCepas}/$1.git" 2>/dev/null || :
}
VARS="runs-on: \${{ vars.CI_RUNS_ON || 'ubuntu-24.04' }}"
mkrepo alpha "$VARS"
mkrepo beta "$VARS"
mkrepo held "$VARS"
mkrepo opted "$VARS" "ci_runner: hosted"
mkrepo plain "runs-on: ubuntu-24.04"
mkrepo orgrepo "$VARS" "" SomeOrg
mkrepo stranger "$VARS" "" OtherOrg          # an owner no config names: foreign whatever else is configured
mkrepo unpushed "$VARS" "" -                  # never pushed: no GitHub repo to register a runner to
printf '[' > "$FX/snap.json"; _c=""
for _n in alpha beta held opted plain orgrepo stranger unpushed; do
  printf '%s{"descriptor":{"name":"%s","path":"%s/%s"}}' "$_c" "$_n" "$PORT" "$_n" >> "$FX/snap.json"; _c=","
done
printf ']\n' >> "$FX/snap.json"
cp "$FX/snap.json" "$CACHE/fleet-snapshot.json"

# runner <name> <status> <busy> — what GitHub says about <name>-linux
runner() {
  mkdir -p "$FX/runners"
  printf '{"runners":[{"id":%s,"name":"%s-linux","status":"%s","busy":%s,"labels":[{"name":"self-hosted"}]}]}\n' \
    "${4:-7}" "$1" "$2" "$3" > "$FX/runners/$1.json"
}
# orgrunner <status> <busy> [id] — what GitHub says about SomeOrg's org-level runner, someorg-linux
orgrunner() {
  mkdir -p "$FX/runners"
  printf '{"runners":[{"id":%s,"name":"someorg-linux","status":"%s","busy":%s,"labels":[{"name":"self-hosted"}]}]}\n' \
    "${3:-9}" "$1" "$2" > "$FX/runners/org.SomeOrg.json"
}
# orgrunners <status> <busy> <status-2> <busy-2> — SomeOrg's two org runners, someorg-linux (id 9) and someorg-linux-2 (id 10)
orgrunners() {
  mkdir -p "$FX/runners"
  printf '{"runners":[{"id":9,"name":"someorg-linux","status":"%s","busy":%s,"labels":[{"name":"self-hosted"}]},{"id":10,"name":"someorg-linux-2","status":"%s","busy":%s,"labels":[{"name":"self-hosted"}]}]}\n' \
    "$1" "$2" "$3" "$4" > "$FX/runners/org.SomeOrg.json"
}
# orgconf — SomeOrg gets an org runner, and zarija (not in the fleet) is named as an extra repo
orgconf() { printf 'org SomeOrg\nrepo VytCepas/zarija\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
# stale <name> — the container was made from an older build of the image tag than the one the tag names now
stale() { echo sha256:old > "$FX/cid.$1"; }
# container <name> <image> <state> — a container the docker stub knows
container() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$FX/containers"; }
reset() {
  rm -rf "$FX/runners" "$FX/var" "$FX/runs" "$FX/jobs" "$FX/ann" "$FX/queue"
  rm -f "$FX/docker.fail" "$FX/docker.runfail" "$FX/tagid" "$FX"/cid.* "$FX"/mounts.* "$FX"/memory.* "$FX"/events.* "$FX/queue.fail" "$FX"/*.log "$FX"/*.asked "$FX/containers" "$FX"/busy.* "$FX"/busyafter.* "$FX"/ghflip.* "$FX/runners.fail" "$FX/rerun.fail" "$FX"/envfile.* "$FX/unexpected.log" "$FX"/wedge.* "$FX"/ps.* "$FX"/stubborn.* "$FX"/memcur.* "$FX/vmmem" "$FX/update.fail" \
        "$CACHE"/checks.log "$CACHE"/ci-*.json "$CACHE"/runner-switch*.json "$CACHE"/ci-reruns.tsv "$CACHE"/ci-lost-*.tsv "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
  mkdir -p "$FX/var"; printf 'port-linux-runner:local\nport-linux-runner:interim\n' > "$FX/images"
  AT=$NOW
}
run() { FX="$FX" HARBOR_CI_MOUNT_ROOT="${MROOT:-}" HARBOR_TEST_GH="$GH" HARBOR_CI_DOCKER="$DOCKER" HARBOR_SCOPE_CACHE_DIR="$CACHE" HARBOR_TEST_NOW="${AT:-$NOW}" \
          HARBOR_CI_EVENTS_DIR="${EVDIR:-$EVENTS}" HARBOR_SCOPE_FLEET_CONTROLLER_BIN=/nonexistent-orch sh "$T_ROOT/bin/ci-runners.sh" "$@" 2>&1; }
nlines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
nlog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:ci.runners' "$CACHE/checks.log"; else echo 0; fi; }
