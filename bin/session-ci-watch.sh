#!/usr/bin/env sh
# session-ci-watch.sh (harbor#1043, #1044) — rule event.session-ci-watch: when a session opens a PR, wait for its checks and say how they ended.
#
# On a pr.opened event whose link is one whole github.com pull URL, it starts bin/ci-wait.sh DETACHED in rounds of
# HARBOR_CI_WATCH_SECS (default 1800). ci-wait reads `gh pr checks` once per ci.job.done rather than polling and never
# waits on a status that is not CI (review/decision; harbor#1367). A round that ends still running RE-ARMS, up to
# HARBOR_CI_WATCH_CEILING (default 7200: harbor's mirrored CI takes about an hour), and the first such round sends one
# "still running at <N>m" notice naming what is pending or failed. The end is one verdict: green, red, or stuck past the
# ceiling, naming any failed or cancelled check (2026-11-16: a relay job cancelled at 1 h read only "still running").
# Each notice and the verdict go to a banner, reactions.log and the opening session's note (react_session_note), which
# the ci-verdict-for-session context rule prints on that session's next tool call. Owner, repo and number are validated
# before they reach a command. It reads checks and never merges, approves or re-runs anything.
# On/off: harbor event on --preset|--off event.session-ci-watch.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
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
SECS="${HARBOR_CI_WATCH_SECS:-1800}"; case "$SECS" in ''|*[!0-9]*|0) SECS=1800 ;; esac
CEIL="${HARBOR_CI_WATCH_CEILING:-7200}"; case "$CEIL" in ''|*[!0-9]*|0) CEIL=7200 ;; esac
[ "$CEIL" -ge "$SECS" ] || CEIL="$SECS"
# names <ci-wait line>: the failed/cancelled and pending checks it named, or nothing
names() { printf '%s' "$1" | sed -n 's/.*\(failed: [^;)]*\).*\(pending: [^;)]*\).*/\1; \2/p; t
  s/.*\(failed: [^;)]*\).*/\1/p; t
  s/.*\(pending: [^;)]*\).*/\1/p'; }
say() { # <verdict> <ci-wait line>: one banner, one reactions.log line, one note for the opening session
  react_log event.session-ci-watch "$OWNER/$REPO#$N: $1${2:+ — $2}"
  react_session_note event.session-ci-watch "PR $OWNER/$REPO#$N: $1"
  react_notify "PR #$N" "$1" || :
}
# Detached: no inherited fd, no controlling stdin; the dispatcher's bounded() waits for this shell, not for the watch.
(
  _el=0; _told=0
  while :; do
    _r="$SECS"; [ $((CEIL - _el)) -ge "$_r" ] || _r=$((CEIL - _el))
    L="$(sh "$WAIT" "$OWNER/$REPO#$N" --timeout "$_r" 2>/dev/null)"; rc=$?
    _el=$((_el + _r)); _nm="$(names "$L")"
    case "$rc" in
      0) say "checks green" "$L"; break ;;
      1) say "checks red${_nm:+ — $_nm}" "$L"; break ;;
      3) if [ "$_el" -ge "$CEIL" ]; then say "checks stuck: still running after $((_el / 60))m, watch stopped${_nm:+ — $_nm}" "$L"; break; fi
         [ "$_told" = 1 ] || { say "checks still running at $((_el / 60))m, still watching${_nm:+ — $_nm}" "$L"; _told=1; } ;;
      *) say "checks unreadable (ci-wait exit $rc)" "$L"; break ;;
    esac
  done
) </dev/null >/dev/null 2>&1 3<&- 9<&- &
log_end || :
exit 0
