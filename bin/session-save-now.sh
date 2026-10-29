#!/usr/bin/env sh
# session-save-now.sh (harbor#1043, #1044) — rule event.session-save-now: the audit trail of a "write the handoff now" nudge.
#
# The nudge itself is the Stop hook's (hooks/session-state/session-state.sh): only a Stop hook can continue a turn, and it does so ONCE per
# trigger, guarded by stop_hook_active, when this rule is installed. It then puts session.save-now on the bus; this
# handler records that it happened in reactions.log. It sends nothing to the session and runs nothing else.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/log-lib.sh"
LOG_FD=2; log_init "session-save-now"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = session.save-now ] || exit 0
react_log event.session-save-now "$(printf '%.6s' "$RSID"): asked to write the handoff ($RSTATE)"
log_end || :
exit 0
