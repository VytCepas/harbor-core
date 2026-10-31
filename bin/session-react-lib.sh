#!/usr/bin/env sh
# session-react-lib.sh (harbor#1043, #1044) — what the session.* reaction handlers share. Sourced, never run.
#
#   . "$HERE/session-react-lib.sh"
#   react_event       parse $HARBOR_EVENT: RKIND RSID RSTATE RLINK; returns 1 unless RSID is a plain session id
#   react_rec <key>   one field of the session's state record (empty when there is none)
#   react_notify <subtitle> <body>   a desktop banner through bin/library-alert.sh's chain; 1 when it was only logged
#   react_log <id> <text>            one line in $RSTATE_DIR/reactions.log
#
# The event is the dispatcher's own raw bus line, data and not an instruction: every field is checked against a short
# charset before use, and nothing from it reaches a shell string.
# `set -u` is the callers' own mode (every handler sets it before sourcing), so this leaks nothing.
set -u
[ -n "${_LOG_LIB:-}" ] || . "${HERE:?session-react-lib.sh: set HERE to the caller bin/ before sourcing}/library-log.sh"
RSTATE_DIR="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
ALERT_LIB_DIR="$HERE"; . "$HERE/library-alert.sh"

react_event() {
  RKIND=""; RSID=""; RSTATE=""; RLINK=""; RDSID=""
  command -v jq >/dev/null 2>&1 || return 1
  eval "$(printf '%s' "${HARBOR_EVENT:-}" | jq -r '@sh "RKIND=\(.kind // "") RSID=\(.subject // "") RSTATE=\(.data.title // "") RLINK=\(.data.link // "") RDSID=\(.data.session_id // "")"' 2>/dev/null)" || return 1
  # pr.opened carries the owning session in data.session_id; session.* events use the subject.
  case "$RKIND" in session.*) ;; *) RSID="$RDSID" ;; esac
  case "$RSID" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
}

react_rec() { # <key>
  [ -r "$RSTATE_DIR/sessions/$RSID.json" ] || return 0
  jq -r --arg k "$1" '.[$k] // empty | tostring' "$RSTATE_DIR/sessions/$RSID.json" 2>/dev/null || :
}

react_notify() { # <subtitle> <body> -> 0 only if a desktop channel took it (bin/library-alert.sh, harbor#618)
  harbor_notify "$1" "$2"
  [ "$NOTIFY_SINK" != log ]
}

react_log() { # <check-id> <text>: one line in reactions.log
  { mkdir -p "$RSTATE_DIR" && printf '%s [check:%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$RSTATE_DIR/reactions.log"; } 2>/dev/null || :
}
