#!/usr/bin/env sh
# session-subagent-check (harbor#445 item E) — advisory SubagentStop hook. Registered in docs/reference/checks.md as `subagent-stop`.
# Warns, never blocks, when a subagent (1) stops with the same final report as its previous stop, or
# (2) stops while a background task it started is still running.
#
# WHAT THE PAYLOAD CARRIES (docs: code.claude.com/docs/en/hooks, SubagentStop): agent_id, agent_type,
# agent_transcript_path, last_assistant_message, stop_hook_active, background_tasks. background_tasks is
# scoped to the PARENT SESSION, not the subagent, so "started by this agent" is decided by finding the
# task id in this agent's own transcript. No transcript, or an id that is absent from it: silent, because
# a warning about another agent's task is a false positive (No.2 clause 11).
#
# CHANNEL: systemMessage, to the operator. SubagentStop has no non-blocking arm that reaches the parent
# model (additionalContext and decision:block both keep the subagent running), so this never uses them.
# EXIT 0 ON EVERY PATH. OFF: SUBAGENT_STOP_CHECK=off, or the sentinel $CFG/subagent-stop.off.
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
case "${1:-}" in --help|-h) echo "usage: session-subagent-check.sh < SubagentStop payload  (advisory hook; see docs/reference/checks.md subagent-stop)"; exit 0 ;; esac
case "${SUBAGENT_STOP_CHECK:-on}" in off|OFF|0|no|false) exit 0 ;; esac
[ -e "$CFG/subagent-stop.off" ] && exit 0

JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -n "$JQ" ] || exit 0

PAYLOAD="$(cat 2>/dev/null)" || exit 0
[ -n "$PAYLOAD" ] || exit 0
f() { printf '%s' "$PAYLOAD" | "$JQ" -r "$1" 2>/dev/null; }
[ "$(f '.stop_hook_active // false')" = "true" ] && exit 0
AID="$(f '.agent_id // ""')" || exit 0
case "$AID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
TX="$(f '.agent_transcript_path // ""')"

MSG=""
# (1) duplicate report: this agent's previous stop left a hash behind.
ST="${HARBOR_SESSION_STATE_DIR:-$HOME/.local/state/harbor}/agent-stop"
H="$(f '.last_assistant_message // ""' | cksum | cut -d' ' -f1,2 | tr ' ' '-')"
if [ -n "$H" ] && [ "$(f '(.last_assistant_message // "") | length')" -gt 0 ] 2>/dev/null; then
  if [ -r "$ST/$AID" ] && [ "$(cat "$ST/$AID" 2>/dev/null)" = "$H" ]; then
    MSG="A duplicate final report: this agent's last stop carried the same text. Report once; a repeat adds nothing."
  fi
  mkdir -p "$ST" 2>/dev/null && printf '%s' "$H" > "$ST/$AID" 2>/dev/null
  # one file per agent: age them out after 7 days
  for _old in $(find "$ST" -type f -mtime +7 2>/dev/null); do rm -f -- "$_old"; done
fi

# (2) running or pending background tasks whose launch receipt ("with ID: <id>") is in this agent's own transcript.
if [ -n "$TX" ] && [ -f "$TX" ] && [ -r "$TX" ]; then
  RUNNING=""
  for id in $(f '[.background_tasks[]? | select(.status=="running" or .status=="pending") | .id] | .[]'); do
    case "$id" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
    [ "$id" = "$AID" ] && continue   # a background agent's own task id is its agent id, on every line of its transcript
    grep -qF -- "with ID: $id" "$TX" 2>/dev/null && RUNNING="$RUNNING $id"
  done
  if [ -n "$RUNNING" ]; then
    MSG="${MSG:+$MSG
}Background work this agent started is still running:$RUNNING. Stop it before reporting."
  fi
fi
[ -n "$MSG" ] || exit 0

MSG="[check:subagent-stop] warn (advisory, never blocks) agent $AID
$MSG
Disable: touch $CFG/subagent-stop.off"
printf '%s' "$MSG" | "$JQ" -Rs '{systemMessage: .}' 2>/dev/null || true
exit 0
