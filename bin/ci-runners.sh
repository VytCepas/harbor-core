#!/usr/bin/env sh
# ci-runners.sh (harbor#1060) — one Linux runner container per fleet repo that wants local CI, owned by this box.
#
# Verbs: list [--json] (desired against actual, writes nothing) | up [--apply] (create missing <repo>-linux containers, start stopped
# ones, set an adopted one's memory live) | down <repo|org> [--apply] (refuses a busy runner) | refresh [--apply] [--include-governance]
# (recreate containers on a stale image, one at a time, skipping busy ones; tick never runs it) | switch [--apply] (CI_RUNS_ON=self-hosted
# per ci-runner-switch.sh's verdict) | rerun-refused, rerun-lost [--apply] (once, last 48h) | tick (switch + both reruns + drift report;
# run by status-fleet-snapshot-refresh.sh) | unwedge <container> [--apply] (TERM then KILL on the step processes of a runner the alarm confirmed wedged).
# THE FLEET is the fleet snapshot: a repo wants a runner when its workflows read vars.CI_RUNS_ON, unless `ci_runner: hosted` or it has no GitHub origin; other owners are `foreign`.
# CONFIG $CLAUDE_CONFIG_DIR/.harbor-ci-runners: image, cpus, memory, hold REPO why, governance N, gate N (harbor#1286), repo OWNER/NAME,
# org ORG [cap] [runners N], limits NAME [memory SIZE] [cpus N], mount REPO HOST-PATH CONTAINER-PATH (always read-only), lost-rerun off.
# A container that exists is ADOPTED (up never recreates, stops or removes one); CPUS are set at creation, the governor moves them live. Per owner: personal repos follow cache/runner-switch.json, an org cache/runner-switch.<ORG>.json. No billing is read or written here.
# Removed notes: docs/explanation/code-cases/bin-ci-runners.md
# THE TOKEN goes GitHub -> 0600 file -> docker --env-file -> deleted: never an argv, a URL, a log line or the screen.
# Findings: one `[check:ci.runners]` line in cache/checks.log per change, plus cache/ci-runners.json. Needs POSIX sh, jq, gh, docker (HARBOR_TEST_GH and HARBOR_CI_DOCKER swap in fakes).
# SPLIT (harbor#1060): this file is the entry point, flags and config; each verb group is a sourced lib (ci-runners-{fleet,provision,github,watch}-lib.sh).
set -eu
. "$(dirname -- "$0")/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init ci-runners

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
CMD="${1:-}"; [ "$#" -gt 0 ] && shift
APPLY=0; JSON=0; INCGOV=0; TARGET=""
for _a in "$@"; do
  # shellcheck disable=SC2034 # APPLY: read by the ci-runners-*-lib.sh this sources
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
GH="${HARBOR_TEST_GH:-gh}"
# shellcheck disable=SC2034 # DOCKER: read by the ci-runners-*-lib.sh this sources
DOCKER="${HARBOR_CI_DOCKER:-docker}"
# shellcheck disable=SC2034 # GOV_REPO: read by the ci-runners-*-lib.sh this sources
GOV_REPO="${HARBOR_CI_SWITCH_REPO:-$OWNER/harbor}"   # the repo harbor's own checks run on (the governance runners)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CFG/.harbor-ci-runners"
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$HOME/.claude/cache}"
LOG="$CACHE_DIR/checks.log"
# shellcheck disable=SC2034 # SNAP: read by the ci-runners-*-lib.sh this sources
SNAP="${HARBOR_STATUS_FLEET_SNAPSHOT:-$CACHE_DIR/fleet-snapshot.json}"
# shellcheck disable=SC2034 # FLEET: read by the ci-runners-*-lib.sh this sources
FLEET="${HARBOR_SCOPE_FLEET_FILE:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)}"
# shellcheck disable=SC2034 # ORCH: read by the ci-runners-*-lib.sh this sources
ORCH="${HARBOR_SCOPE_FLEET_CONTROLLER_BIN:-${HARBOR_ORCH_BIN:-$(sh "$(dirname -- "$0")/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN 2>/dev/null || :)}}"
# shellcheck disable=SC2034 # EVENTS: read by the ci-runners-*-lib.sh this sources
EVENTS="${HARBOR_CI_EVENTS_DIR:-$HOME/runners/harbor-linux/events}"
# shellcheck disable=SC2034 # LABELS: read by the ci-runners-*-lib.sh this sources
LABELS="${HARBOR_CI_LABELS:-self-hosted,Linux,ARM64}"
NOW="${HARBOR_TEST_NOW:-$(date +%s)}"
case "$NOW" in ''|*[!0-9]*) NOW="$(date +%s)" ;; esac
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; exit 2; }

conf() { [ -f "$CONF" ] && awk -v k="$1" '$1 == k { print $2; exit }' "$CONF" 2>/dev/null || :; }
IMAGE="${HARBOR_CI_IMAGE:-$(conf image)}"; IMAGE="${IMAGE:-port-linux-runner:local}"
CPUS="$(conf cpus)"; CPUS="${CPUS:-1}"
MEMORY="$(conf memory)"; MEMORY="${MEMORY:-1g}"
GOVN="$(conf governance)"; case "$GOVN" in [1-9]) ;; *) GOVN=1 ;; esac   # how many governance runners; anything else is the default 1
GATEN="$(conf gate)"; case "$GATEN" in [1-9]) ;; *) GATEN=0 ;; esac   # how many gate runners (harbor#1286); anything else is the default 0
is_hold() { [ -f "$CONF" ] && awk -v r="$1" '$1 == "hold" && $2 == r { f = 1 } END { exit !f }' "$CONF"; }
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
  printf '[check:ci.runners] %s %s\n' "$(iso "$NOW")" "$1" >> "$LOG" 2>/dev/null || :
}
# shellcheck disable=SC2034 # TAB: read by the ci-runners-*-lib.sh this sources
TAB="$(printf '\t')"
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
