#!/usr/bin/env sh
# session-notify.sh (harbor#1043, #1044) — rule event.session-notify: a banner when a session starts waiting on the operator or is done.
#
# Runs only as the dispatcher's handler, on a session.state event; any other kind or state is a quiet exit 0. The body names
# the state and the first six characters of the session id, never a path, a branch or a message (the banner lands on a
# lock screen). Best-effort: a missing sink is logged, not failed. On/off: harbor event on --preset|--off event.session-notify.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
LOG_FD=2; log_init "session-notify"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = session.state ] || exit 0
case "$RSTATE" in
  waiting-operator) BODY="waiting for you" ;;
  done)             BODY="done" ;;
  *)                exit 0 ;;
esac
SID6="$(printf '%.6s' "$RSID")"
if react_notify "session $SID6" "$BODY"; then react_log event.session-notify "$SID6 $RSTATE: banner sent"
else react_log event.session-notify "$SID6 $RSTATE: no notification sink answered"; fi
log_end || :
exit 0
