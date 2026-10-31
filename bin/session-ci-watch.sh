#!/usr/bin/env sh
# session-ci-watch.sh (harbor#1043, #1044) — rule event.session-ci-watch: when a session opens a PR, wait for its checks and say how they ended.
#
# On a pr.opened event whose link is one whole github.com pull URL, it starts bin/ci-wait.sh DETACHED (deadline
# HARBOR_CI_WATCH_SECS, default 1800), which reads `gh pr checks` once per ci.job.done rather than polling and never
# waits on a status that is not CI (review/decision; harbor#1367), then sends one banner with the verdict: green, red or
# still running. Owner, repo and number are validated before they reach a command. It reads checks and never merges,
# approves or re-runs anything. On/off: harbor event on --preset|--off event.session-ci-watch.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
LOG_FD=2; log_init "session-ci-watch"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = pr.opened ] || exit 0
case "$RLINK" in https://github.com/*/*/pull/*) ;; *) exit 0 ;; esac
_p="${RLINK#https://github.com/}"; OWNER="${_p%%/*}"; _p="${_p#*/}"; REPO="${_p%%/*}"; N="${_p##*/}"
case "$OWNER" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$REPO" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$N" in ''|*[!0-9]*) exit 0 ;; esac
WAIT="${HARBOR_SESSION_CI_WAIT:-$HERE/ci-wait.sh}"
[ -f "$WAIT" ] || { react_log event.session-ci-watch "ci-wait.sh is missing at $WAIT: $OWNER/$REPO#$N not watched"; exit 0; }
SECS="${HARBOR_CI_WATCH_SECS:-1800}"; case "$SECS" in ''|*[!0-9]*) SECS=1800 ;; esac
# Detached: no inherited fd, no controlling stdin; the dispatcher's bounded() waits for this shell, not for the watch.
(
  L="$(sh "$WAIT" "$OWNER/$REPO#$N" --timeout "$SECS" 2>/dev/null)"; rc=$?
  case "$rc" in
    0) V="checks green" ;; 1) V="checks red" ;; 3) V="checks still running after ${SECS}s" ;;
    *) V="checks unreadable (ci-wait exit $rc)" ;;
  esac
  react_log event.session-ci-watch "$OWNER/$REPO#$N: $V${L:+ — $L}"
  react_notify "PR #$N" "$V" || :
) </dev/null >/dev/null 2>&1 3<&- 9<&- &
log_end || :
exit 0
