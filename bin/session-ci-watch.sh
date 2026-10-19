#!/usr/bin/env sh
# session-ci-watch.sh (harbor#1043, #1044) — rule event.session-ci-watch: when a session opens a PR, wait for its checks and say how they ended.
#
# On a pr.opened event whose link is one whole github.com pull URL, it starts ~/.local/bin/wait-for DETACHED (its own
# deadline, at most HARBOR_CI_WATCH_SECS, default 1800, polling every 30 s) on `gh pr checks`, then sends one banner with
# the verdict: green, red or timed out. Owner, repo and number are validated before they reach a command. It reads checks
# and never merges, approves or re-runs anything. On/off: harbor event on --preset|--off event.session-ci-watch.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/log-lib.sh"
LOG_FD=2; log_init "session-ci-watch"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = pr.opened ] || exit 0
case "$RLINK" in https://github.com/*/*/pull/*) ;; *) exit 0 ;; esac
_p="${RLINK#https://github.com/}"; OWNER="${_p%%/*}"; _p="${_p#*/}"; REPO="${_p%%/*}"; N="${_p##*/}"
case "$OWNER" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$REPO" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$N" in ''|*[!0-9]*) exit 0 ;; esac
WAIT_FOR="${HARBOR_SESSION_WAIT_FOR:-${HOME:-/nonexistent}/.local/bin/wait-for}"
[ -x "$WAIT_FOR" ] || { react_log event.session-ci-watch "wait-for is missing at $WAIT_FOR: $OWNER/$REPO#$N not watched"; exit 0; }
SECS="${HARBOR_CI_WATCH_SECS:-1800}"; case "$SECS" in ''|*[!0-9]*) SECS=1800 ;; esac
BUCKETS="gh pr checks $N -R $OWNER/$REPO --json bucket -q '.[].bucket'"
# Detached: no inherited fd, no controlling stdin; the dispatcher's bounded() waits for this shell, not for the watch.
(
  "$WAIT_FOR" -t "$SECS" -i 30 -q -n "ci-$N" -w "$BUCKETS | sort -u" -- sh -c "$BUCKETS | grep -q . && ! $BUCKETS | grep -q pending"
  rc=$?
  B="$(sh -c "$BUCKETS" 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ "$rc" -ne 0 ]; then V="checks still running after ${SECS}s"
  else case "$B" in *fail*|*cancel*) V="checks red" ;; *) V="checks green" ;; esac; fi
  react_log event.session-ci-watch "$OWNER/$REPO#$N: $V"
  react_notify "PR #$N" "$V" || :
) </dev/null >/dev/null 2>&1 3<&- 9<&- &
log_end || :
exit 0
