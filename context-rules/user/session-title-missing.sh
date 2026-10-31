#!/usr/bin/env sh
# 55-session-title-missing — asks for a session title when hooks/session-title has no file to apply.
# Silent in a subagent (its tool calls carry agent_id), with no session id, when the title file exists
# or the operator switched titles off. FAIL-OPEN: any error prints nothing and exits 0.
set -u
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
SID="$(printf '%s' "$P" | jq -r '.session_id // empty | strings' 2>/dev/null)" || exit 0
AID="$(printf '%s' "$P" | jq -r '.agent_id // empty | strings' 2>/dev/null)" || exit 0
[ -z "$AID" ] || exit 0
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
CFG="${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}"
[ ! -e "$CFG/session-title.off" ] || exit 0
F="$CFG/session-titles/$SID.txt"
[ ! -s "$F" ] || exit 0
printf 'This session has no title. Once the topic is clear, Write one line `<area>: <what>` (at most 50 characters, concrete nouns, no ticket numbers) to %s; the session-title hook applies it on the next prompt. Rewrite the file when the work moves to another topic.\n' "$F"
exit 0
