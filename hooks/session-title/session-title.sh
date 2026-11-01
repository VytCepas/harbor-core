#!/usr/bin/env sh
# session-title.sh (harbor#1257) — applies the title the MODEL wrote for this session, via sessionTitle.
# Events: UserPromptSubmit, and SessionStart with source startup/resume/fork (only these two accept sessionTitle).
#
# THE TITLE FILE  <config dir>/session-titles/<session_id>.txt   (config dir: $CLAUDE_CONFIG_DIR, else ~/.claude)
# Model instruction: Write one line '<area>: <what>', at most 50 characters, to that path. A plain Write is
# allowed by guard-selfedit and the Edit deny array (only the floor's own surfaces are protected).
#
# Prints {"hookSpecificOutput":{"hookEventName":"<event>","sessionTitle":"<title>"}} when the file holds a
# title, the title is 1-50 characters and the payload's session_title is empty, equal to it, or the title this
# hook applied last (<session_id>.applied beside it), so a retitle replaces our own. Any other session_title is
# the operator's (/rename): print nothing. Over 50: print nothing and send a systemMessage naming the limit.
# Empty or missing file, any error: print nothing, exit 0.
set -u
trap 'exit 0' EXIT
case "${1-}" in -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
LC_ALL=C; export LC_ALL

P="$(cat 2>/dev/null)" || exit 0
[ -n "$P" ] || exit 0
SID="$(printf '%s' "$P" | jq -r '.session_id // ""' 2>/dev/null)" || exit 0
EV="$(printf '%s' "$P" | jq -r '.hook_event_name // ""' 2>/dev/null)" || exit 0
CUR="$(printf '%s' "$P" | jq -r '.session_title // ""' 2>/dev/null)" || exit 0
SRC="$(printf '%s' "$P" | jq -r '.source // ""' 2>/dev/null)" || exit 0
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
case "$EV" in
  UserPromptSubmit) ;;
  SessionStart) case "$SRC" in startup|resume|fork) ;; *) exit 0 ;; esac ;;
  *) exit 0 ;;
esac

F="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}/session-titles/$SID.txt"
[ -f "$F" ] || exit 0
# First line only, trimmed; the file is the model's, so never trusted past that.
T="$(head -n 1 "$F" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" || exit 0
[ -n "$T" ] || exit 0

N="$(jq -nr --arg t "$T" '$t | length' 2>/dev/null)" || exit 0   # codepoints; wc -m counts bytes under LC_ALL=C
if [ "${N:-0}" -gt 50 ]; then
  jq -n --arg m "session-title: title refused, $N characters; the limit is 50. Shorten $F" '{systemMessage: $m}' 2>/dev/null
  exit 0
fi
# The operator's /rename wins: only an empty, identical or self-applied session_title lets us speak.
A="${F%.txt}.applied"
PREV="$(head -n 1 "$A" 2>/dev/null)" || PREV=""
[ -z "$CUR" ] || [ "$CUR" = "$T" ] || { [ -n "$PREV" ] && [ "$CUR" = "$PREV" ]; } || exit 0
jq -nc --arg e "$EV" --arg t "$T" '{hookSpecificOutput: {hookEventName: $e, sessionTitle: $t}}' 2>/dev/null || exit 0
[ "$PREV" = "$T" ] || printf '%s\n' "$T" > "$A" 2>/dev/null || :
exit 0
