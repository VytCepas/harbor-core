#!/usr/bin/env sh
# ci-runners.sh (harbor#1060) — one Linux runner container per fleet repo that wants local CI, owned by this box.
#
#   sh ci-runners.sh list [--json]       desired (fleet repos whose workflows read vars.CI_RUNS_ON) against actual
#                                        (container, image, runner online on GitHub, CI_RUNS_ON); writes nothing
#   sh ci-runners.sh up [--apply]        create the missing <repo>-linux containers, start stopped ones, and set an adopted
#                                        one's memory to its configured value LIVE (docker update, no recreate); a dry run without --apply
#   sh ci-runners.sh down <repo|org> [--apply]   remove the container and its GitHub registration; refuses a busy runner
#   sh ci-runners.sh refresh [--apply]   recreate (busy re-read right before each removal), as up does, each container on an image older than the configured tag (list says
#                                        `stale`); skips a busy runner, one at a time, stops at the first failure; tick never runs it
#   sh ci-runners.sh refresh --apply --include-governance   also recreate harbor-linux, the governance runner `list` shows as a
#                                        read-only `governance` row: only when it is stale, idle AND GitHub shows no queued or
#                                        in-progress run on the governance repo; it keeps its mounts, memory and hooks (harbor#1083)
#   sh ci-runners.sh up --apply --include-governance   also create (or start) a governance runner that is absent or stopped: with
#                                        `governance 2` in the config, harbor-linux-2, made as harbor-linux is (image, events mount,
#                                        hooks, restart policy, memory, --cpus linux_min), registered on the governance repo
#   sh ci-runners.sh switch [--apply]    set CI_RUNS_ON=self-hosted on every repo (or org) with a local runner when its
#                                        owner's ci-runner-switch.sh verdict says the minutes are short, unset it when not
#   sh ci-runners.sh rerun-refused [--apply]   re-run, once, each run of the last 48h GitHub refused for billing
#   sh ci-runners.sh rerun-lost [--apply]      re-run, once, a job of the last 48h that no runner took (harbor#675) or whose runner dropped
#                                        mid-job: a step with no conclusion, or the runner's own lost-connection text (harbor#1060)
#   sh ci-runners.sh tick                switch + rerun-refused + rerun-lost applied, and the drift report; run by status-fleet-snapshot-refresh.sh
#   sh ci-runners.sh unwedge <container> [--apply]   a container the alarm confirmed WEDGED (busy on a dead job): prints the job's
#                                        step processes (every descendant of Runner.Worker); --apply sends them TERM, then KILL to any
#                                        left after 10s (HARBOR_CI_UNWEDGE_GRACE), so the runner fails the job and takes the next. Never
#                                        Runner.Worker or Runner.Listener; refuses unless cache/ci-runner-alarm.json (<=900s old)
#                                        confirms it wedged and the job running now is that job; one checks.log line
#   (up --apply and tick also install bin/ci-governor-hook.sh into the events mount every container runs it from)
#
# THE FLEET is the fleet snapshot (fleet.yaml's roots and projects, read through cache/fleet-snapshot.json).
# A repo wants a runner when its workflows read vars.CI_RUNS_ON, unless its .agents/config.yaml says `ci_runner: hosted`
# or its origin names no GitHub repo (never pushed: nothing to register a runner to); a repo under another owner is listed as `foreign` and left alone (personal-account runners are per repo).
# CONFIG is $CLAUDE_CONFIG_DIR/.harbor-ci-runners: `image NAME` (else HARBOR_CI_IMAGE, else port-linux-runner:local),
# `cpus N`, `memory SIZE`, and `hold REPO why` for a repo another runner still serves (listed, never provisioned or switched).
# `governance N` (default 1, max 9) is how many governance runners harbor's own checks get: harbor-linux, harbor-linux-2, ...
# `list` shows each as a read-only `governance` row; the governor keeps an idle one at linux_min and splits cores among busy ones.
# `gate N` (default 0, max 9) is how many GATE runners the small jobs get (harbor#1286): harbor-gate, harbor-gate-2, ... made as the
# governance runners are but labelled `self-hosted,Linux,ARM64,harbor-gate`, at cpus 1 and memory 2g (a `limits harbor-gate ...` line
# changes either). Governance runners carry `harbor-pool` as well. The workflow sends shard legs to harbor-pool and the small jobs to
# harbor-gate, so the small jobs never queue behind a 15-20 min leg. `list` shows each as a read-only `gate` row; `up --apply
# --include-governance` creates (or starts) one; they are not *-linux, so the governor never changes their cpus.
# Going back down is the operator's: `docker rm -f harbor-linux-2`, delete its registration (id in `list --json`:
# gh api -X DELETE repos/OWNER/harbor/actions/runners/<id>), then `governance 1`; `down` refuses a governance row.
# `repo OWNER/NAME` adds a repo the fleet does not list (not cloned here): wanted as if its workflows read the variable.
# `org ORG [cap] [runners N]` gives the organisation N org-level runners (default 1, max 9), <org lower-cased>-linux,
# then -linux-2 .. -linux-N (rows <org>, <org>-2 ..), each registered at the org with the same labels; its repos
# are listed as `org` (served by them, no container of their own) and its CI_RUNS_ON is the ORG-level variable
# (visibility private), which every private repo of the org reads. `hold <org lower-cased> why` holds the org.
# Going down from N: `down <org>-N --apply` (container and registration), then lower N.
# LIMITS: `limits NAME [memory SIZE] [cpus N]`, NAME one container (exampleorg-linux-2) or a group: <repo>, <org
# lower-cased> (every runner of it) or `harbor` (every governance runner). Its own line beats its group's, which
# beats the global `memory`/`cpus` lines (fleet and org runners only), then 1g / 1. A new container is made with
# them. MEMORY is also kept: `list` reports an adopted container whose cap differs from an EXPLICIT value (a limits
# or memory line; the 1g default is never enforced on what exists) as drift, and `up --apply` sets it live with
# docker update (swap 2x, as docker run makes it): a raise even under a job, a lowering never under a job nor below
# what the container uses now (refused, said, the rest carried on). A governance runner only with a limits line naming
# it and --include-governance. CPUS are set at creation only: the governor moves them live (ci-governor.sh).
# `list` ends with the memory budget: every runner container's cap against the VM's memory (docker info).
# `mount REPO HOST-PATH CONTAINER-PATH` bind-mounts a host path into REPO's container when up creates it, ALWAYS read-only
# (no mode field); `~` in the container path is the runner's HOME. A host path outside /Users/ or that does not exist is
# refused (Colima shares only /Users into its VM: it would mount empty). list reports an adopted container's drift.
# PER OWNER: the personal repos follow cache/runner-switch.json, an org follows cache/runner-switch.<ORG>.json
# (ci-runner-switch.sh --org ORG, the org's minutes cap); each verdict is read, and trusted or not, on its own.
# A container that exists is ADOPTED: up never recreates, stops or removes one, and never touches one running a job
# beyond raising its memory live (the LIMITS rule above).
# THE TOKEN goes GitHub -> a 0600 file -> docker --env-file -> deleted: never an argv, a URL, a log line or the screen.
# NOTHING HERE READS OR WRITES BILLING: the minutes rule is ci-runner-switch.sh's, read from its cache.
# `lost-rerun off` in CONF turns rerun-lost off (tick then skips it). Its lines are `[check:ci-lost-rerun]`, each naming the reason.
# Findings: one `[check:ci-runners]` line in cache/checks.log per CHANGE (and per change of drift), cache/ci-runners.json.
# POSIX sh, jq, gh, docker (HARBOR_GH and HARBOR_DOCKER swap in fakes).
# SPLIT (harbor#1060, docs/explanation/modularity; `lint-module-shape.sh --seam` called it earned): this file is the entry point, the
# flags and the config; each verb group is a sourced lib beside it: ci-runners-fleet-lib.sh (the desired and actual
# sets, `list`, mounts), -provision-lib.sh (`up`, `refresh`, `down`, the governance runners, the hook sync),
# -github-lib.sh (`switch`, `rerun-refused`, `rerun-lost`), -watch-lib.sh (the alarm, the drift cache, `tick`).
set -eu
. "$(dirname -- "$0")/library-log.sh"
LOG_FD=2; log_init ci-runners

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
CMD="${1:-}"; [ "$#" -gt 0 ] && shift
APPLY=0; JSON=0; INCGOV=0; TARGET=""
for _a in "$@"; do
  case "$_a" in
    --apply) APPLY=1 ;;
    --json) JSON=1 ;;
    --include-governance) INCGOV=1 ;;
    -*) log_fail "unknown option $_a"; log_fix "sh $0 --help"; exit 2 ;;
    *) TARGET="$_a" ;;
  esac
done
case "$CMD" in
  list|up|refresh|switch|rerun-refused|rerun-lost|tick) ;;
  unwedge) case "$TARGET" in *[!A-Za-z0-9._-]*|''|-*) log_fail "unwedge needs a container name (letters, digits . _ -)"; log_fix "sh $0 unwedge <name>-linux"; exit 2 ;; esac ;;
  down) case "$TARGET" in *[!A-Za-z0-9._-]*|'') log_fail "down needs a repo name (letters, digits . _ -)"; log_fix "sh $0 down <repo>"; exit 2 ;; esac
        case "$TARGET" in harbor|harbor-[0-9]) log_fail "$TARGET-linux is a governance runner, not a fleet runner"; log_fix "docker rm -f harbor-linux-N, then governance 1 in the config (see --help)"; exit 2 ;; esac ;;
  *) log_fail "unknown command '$CMD'"; log_fix "sh $0 --help"; exit 2 ;;
esac

[ "$INCGOV" = 0 ] || [ "$CMD" = refresh ] || [ "$CMD" = up ] || { log_fail "--include-governance belongs to refresh and up only"; log_fix "sh $0 refresh --apply --include-governance"; exit 2; }

OWNER="${HARBOR_CI_OWNER:-VytCepas}"
GH="${HARBOR_GH:-gh}"
DOCKER="${HARBOR_DOCKER:-docker}"
GOV_REPO="${HARBOR_SWITCH_REPO:-$OWNER/harbor}"   # the repo harbor's own checks run on (the governance runners)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CFG/.harbor-ci-runners"
CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
LOG="$CACHE_DIR/checks.log"
SNAP="${HARBOR_FLEET_SNAPSHOT:-$CACHE_DIR/fleet-snapshot.json}"
# the fleet file through the registry-aware reader beside this script (harbor#966)
FLEET="${HARBOR_FLEET_FILE:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_FLEET_FILE 2>/dev/null || :)}"
# the fleet CLI, a roots.tsv row read through the same reader (harbor#966)
ORCH="${HARBOR_ORCH_BIN:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_ORCH_BIN 2>/dev/null || :)}"
EVENTS="${HARBOR_CI_EVENTS_DIR:-$HOME/runners/harbor-linux/events}"
LABELS="${HARBOR_CI_LABELS:-self-hosted,Linux,ARM64}"
NOW="${HARBOR_NOW:-$(date +%s)}"
case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; exit 2; }

conf() { [ -f "$CONF" ] && awk -v k="$1" '$1 == k { print $2; exit }' "$CONF" 2>/dev/null || :; }
IMAGE="${HARBOR_CI_IMAGE:-$(conf image)}"; IMAGE="${IMAGE:-port-linux-runner:local}"
CPUS="$(conf cpus)"; CPUS="${CPUS:-1}"
MEMORY="$(conf memory)"; MEMORY="${MEMORY:-1g}"
GOVN="$(conf governance)"; case "$GOVN" in [1-9]) ;; *) GOVN=1 ;; esac   # how many governance runners; anything else is the default 1
GATEN="$(conf gate)"; case "$GATEN" in [1-9]) ;; *) GATEN=0 ;; esac   # how many gate runners (harbor#1286); anything else is the default 0
is_hold() { [ -f "$CONF" ] && awk -v r="$1" '$1 == "hold" && $2 == r { f = 1 } END { exit !f }' "$CONF"; }
# the organisations with an org-level runner, and what a slug's scope is: OWNER/NAME is a repo, a bare ORG is an org
ORGS="$( [ -f "$CONF" ] && awk '$1 == "org" && $2 ~ /^[A-Za-z0-9][A-Za-z0-9-]*$/ { printf "%s ", $2 }' "$CONF" 2>/dev/null || :)"
is_org() { case " $ORGS " in *" $1 "*) return 0 ;; esac; return 1; }
org_n() { # <ORG> — how many runners `org ORG [cap] [runners N]` asks for: N when a digit 1-9, else 1
  _on="$( [ -f "$CONF" ] && awk -v o="$1" '$1 == "org" && $2 == o { for (i = 3; i < NF; i++) if ($i == "runners") { print $(i + 1); exit } }' "$CONF" 2>/dev/null || :)"
  case "$_on" in [1-9]) printf '%s' "$_on" ;; *) printf 1 ;; esac
}
orgrow() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }     # ExampleOrg -> exampleorg (its container: exampleorg-linux)
api_base() { case "$1" in */*) printf 'repos/%s' "$1" ;; *) printf 'orgs/%s' "$1" ;; esac; }
var_get() { case "$1" in */*) "$GH" variable get CI_RUNS_ON -R "$1" ;; *) "$GH" variable get CI_RUNS_ON --org "$1" ;; esac; }
var_set() { case "$1" in */*) "$GH" variable set CI_RUNS_ON --body self-hosted -R "$1" ;;
                         *) "$GH" variable set CI_RUNS_ON --body self-hosted --org "$1" --visibility private ;; esac; }
var_del() { case "$1" in */*) "$GH" variable delete CI_RUNS_ON -R "$1" ;; *) "$GH" variable delete CI_RUNS_ON --org "$1" ;; esac; }
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

umask 077
T="$(mktemp -d "${TMPDIR:-/tmp}/ci-runners.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$CACHE_DIR"
logline() { # <message> — one checks.log line, only ever called on a write path
  printf '[check:ci-runners] %s %s\n' "$(iso "$NOW")" "$1" >> "$LOG" 2>/dev/null || :
}
TAB="$(printf '\t')"
# the verbs, one lib each (harbor#1060 split; each is sourced, never run): fleet view, container lifecycle, GitHub side, watching
_here="$(dirname -- "$0")"
. "$_here/ci-runners-fleet-lib.sh"
. "$_here/ci-runners-provision-lib.sh"
. "$_here/ci-runners-github-lib.sh"
. "$_here/ci-runners-watch-lib.sh"
RC=0
case "$CMD" in
  down) do_down ;;
  tick) do_tick ;;
  unwedge) do_unwedge ;;
  *) collect
     case "$CMD" in list) do_list; [ "$JSON" = 1 ] || { do_mounts; do_memory; } ;; up) do_up ;; refresh) do_refresh ;; switch) do_switch ;; rerun-refused) do_rerun ;; rerun-lost) do_rerun_lost ;; esac ;;
esac || RC=$?
[ "$JSON" = 1 ] || log_end || RC=1
exit "$RC"
