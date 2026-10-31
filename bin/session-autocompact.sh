#!/usr/bin/env sh
# session-autocompact.sh (harbor#187) — types /compact into a session's Terminal tab, on the agent's word.
#
#   session-autocompact.sh <session_id> <tty>
#
# Started DETACHED by hooks/session-state/session-state.sh when the agent ends a turn with the line [compact-ok]:
# no hook and no tool can start a compaction, but the session's own terminal can. It waits
# HARBOR_SESSION_AUTOCOMPACT_DELAY seconds (2) for the prompt to return, then types /compact into the macOS Terminal tab
# whose tty is <tty>. Nothing else is judged here: the Stop hook already did. $STATE/compact-auto.off stops it.
# One run per session at a time (a pid file). Every outcome is one line in
# $STATE/backups/session-autocompact/<run>/log (library-log.sh). Exit 0 on every path.
set -u
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
SID="${1:-}"; TTY="${2:-}"
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
case "${TTY#ttys}" in ''|"$TTY"|*[!0123456789]*) exit 0 ;; esac
STATE="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
DELAY="${HARBOR_SESSION_AUTOCOMPACT_DELAY:-${HARBOR_AUTOCOMPACT_DELAY:-2}}"; case "$DELAY" in ''|*[!0-9.]*) DELAY=2 ;; esac
OSA="${HARBOR_SESSION_AUTOCOMPACT_OSASCRIPT:-${HARBOR_AUTOCOMPACT_OSA:-osascript}}"
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/library-log.sh"
LOG_FD=2; log_init session-autocompact
log() { log_note "$(printf '%.8s' "$SID") $1"; }

[ ! -e "$STATE/compact-auto.off" ] || exit 0
mkdir -p "$STATE/sessions" 2>/dev/null || exit 0
log_file "$STATE"
PIDF="$STATE/sessions/$SID.autocompact"
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then log "already running: skipped"; exit 0; fi
printf '%s\n' "$$" > "$PIDF" 2>/dev/null || exit 0
trap 'rm -f "$PIDF"; log_end >/dev/null 2>&1 || :; exit 0' EXIT INT TERM

sleep "$DELAY" & wait $!
# `do script ... in` types into the tab without bringing Terminal forward.
R="$("$OSA" - "/dev/$TTY" 2>&1 <<'OSA'
on run argv
  set want to item 1 of argv
  tell application "Terminal"
    repeat with w in windows
      repeat with t in tabs of w
        if tty of t is want then
          do script "/compact" in t
          return "sent"
        end if
      end repeat
    end repeat
  end tell
  return "no tab"
end run
OSA
)"
log "typed /compact on $TTY: $R"
exit 0
