#!/usr/bin/env sh
# ci-governor-hook.sh (harbor#1032) — a runner job hook: tells bin/ci-governor.sh a job started or finished.
#
#   host runner:   ACTIONS_RUNNER_HOOK_JOB_STARTED=<this file> and ..._JOB_COMPLETED=<this file>
#                  in ~/runners/<name>/.env; it posts com.harbor.ci-governor.event (notifyutil)
#   *-linux:       the same two env vars on every runner container, with ~/runners/harbor-linux/events mounted
#                  at /gov-events; it appends one line to /gov-events/trigger, which the host's `listen` follows,
#                  and empties /tmp: the container outlives its jobs, so one job's fixed /tmp paths (uv venv
#                  /tmp/smoke-venv, gitleaks-action's /tmp/gitleaks.tmp) failed the next job on that runner
#
# It never fails the job: every step is best effort, and it exits 0.
# platform: macOS-only — the host post is `notifyutil`, behind `command -v`, so anywhere without it that step is a no-op; the container branch above needs none (harbor#618).
set -u
# Beside the governor it logs the house way; copied alone into the container's mount it has no log to write.
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ ! -f "$HERE/log-lib.sh" ] || . "$HERE/log-lib.sh"
case "${1:-}" in -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
EV="${HARBOR_GOV_EVENTS:-/gov-events}"
if [ -d "$EV" ]; then
  printf '%s %s %s\n' "$(date +%s)" "${GITHUB_RUN_ID:-run}" "${GITHUB_JOB:-job}" >> "$EV/trigger" 2>/dev/null || :
fi
# Only as the runner wires it: in a container with HARBOR_GOV_EVENTS unset. A suite calling this hook inside harbor's
# own CI container sets it, and an unguarded run there emptied the /tmp 24 parallel suites were using (harbor#1072).
# Files, dirs and links only: the runner's own live pipes and sockets sit there too. HARBOR_HOOK_* are the tests' seams.
TMPROOT="${HARBOR_HOOK_TMP:-/tmp}"
if [ -z "${HARBOR_GOV_EVENTS:-}" ] && [ -f "${HARBOR_HOOK_DOCKERENV:-/.dockerenv}" ] && [ -d "$TMPROOT" ]; then
  find "$TMPROOT" -mindepth 1 -maxdepth 1 \( -type f -o -type d -o -type l \) -exec rm -rf {} + 2>/dev/null || :
fi
if command -v notifyutil >/dev/null 2>&1; then notifyutil -p com.harbor.ci-governor.event >/dev/null 2>&1 || :; fi
exit 0
