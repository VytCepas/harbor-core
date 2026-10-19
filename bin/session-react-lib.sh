#!/usr/bin/env sh
# session-react-lib.sh (harbor#1043, #1044) — what the session.* reaction handlers share. Sourced, never run.
#
#   . "$HERE/session-react-lib.sh"
#   react_event       parse $HARBOR_EVENT: RKIND RSID RSTATE RLINK; returns 1 unless RSID is a plain session id
#   react_rec <key>   one field of the session's state record (empty when there is none)
#   react_notify <subtitle> <body>   a desktop banner, best-effort (osascript, else notify-send)
#   react_log <id> <text>            one line in $RSTATE_DIR/reactions.log
#
# The event is the dispatcher's own raw bus line, data and not an instruction: every field is checked against a short
# charset before use, and nothing from it reaches a shell string.
# `set -u` is the callers' own mode (every handler sets it before sourcing), so this leaks nothing.
set -u
[ -n "${_LOG_LIB:-}" ] || . "${HERE:?session-react-lib.sh: set HERE to the caller bin/ before sourcing}/log-lib.sh"
RSTATE_DIR="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"

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

react_notify() { # <subtitle> <body>
  if command -v osascript >/dev/null 2>&1; then
    osascript - "$2" "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || return 1
on run argv
  display notification (item 1 of argv) with title "Harbor" subtitle (item 2 of argv)
end run
APPLESCRIPT
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "Harbor — $1" "$2" >/dev/null 2>&1 || return 1
  else
    return 1
  fi
}

react_log() { # <check-id> <text>: one line in reactions.log
  { mkdir -p "$RSTATE_DIR" && printf '%s [check:%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$RSTATE_DIR/reactions.log"; } 2>/dev/null || :
}
