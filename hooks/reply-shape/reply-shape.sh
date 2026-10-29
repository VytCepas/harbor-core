#!/usr/bin/env sh
# reply-shape (harbor#952, #949 D-23) — advisory Stop hook. Registered in docs/reference/checks.md as `reply-shape`.
# Flags, never blocks, a turn whose reply breaks the shape: a turn that WROTE (Write, Edit, a writing
# Bash call) whose final reply cites no command output, test result or diff; or a reply far longer
# than an answer-first reply runs.
#
# "LEADS WITH THE ANSWER" IS NOT CHECKED. Whether line one answers cannot be decided mechanically, so
# it stays review-only, and every note says so. A heuristic for it would be a false positive on
# ordinary work, which gets a guard switched off (No.2 clause 11).
#
# NEVER BLOCKS, EXIT 0 ON EVERY PATH. The audience is the operator, so the channel is systemMessage,
# as ticket-note.sh: a Stop hook has no additionalContext arm. Outcome word (D-29 mode): warn.
#
# THE LENGTH THRESHOLD IS 300 WORDS, from the only reply text readable without PII: the 154 final
# replies in evals/context/e10inject and evals/skill/e5trap (claude -p results; p50 55, p90 85, p95 107, max 141
# words, measured 2026-10-04). 300 is ~2x that max, so an ordinary reply never trips it. It was NOT
# measured on real operator sessions (their transcripts are private); a reply that carries a table or
# a design can legitimately exceed it, which is why the note is a question, not a verdict.
# Override: REPLY_SHAPE_MAX_WORDS. Falsifier: a plain one-paragraph answer draws the note.
#
# OFF SWITCH, surviving a reinstall (as ticket-note): REPLY_SHAPE=off, or the sentinel
# $CFG/reply-shape.off, which no installer writes or removes.
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
case "${REPLY_SHAPE:-on}" in off|OFF|0|no|false) exit 0 ;; esac
[ -e "$CFG/reply-shape.off" ] && exit 0

JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -n "$JQ" ] || exit 0

PAYLOAD="$(cat 2>/dev/null)" || exit 0
[ -n "$PAYLOAD" ] || exit 0
[ "$(printf '%s' "$PAYLOAD" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
TX="$(printf '%s' "$PAYLOAD" | "$JQ" -r '.transcript_path // ""' 2>/dev/null)"
[ -n "$TX" ] && [ -f "$TX" ] && [ -r "$TX" ] || exit 0

MAX_WORDS="${REPLY_SHAPE_MAX_WORDS:-300}"
case "$MAX_WORDS" in ''|*[!0-9]*) MAX_WORDS=300 ;; esac

# THE TURN is everything after the last real user prompt (a user record that is not a tool_result).
# One jq pass, slurped: WROTE = a Write/Edit/NotebookEdit call, or a Bash command that writes
# (redirect to a file, tee, sed -i, git add/commit/apply/mv/rm, mv, cp, rm, touch, mkdir);
# REPLY = the text of the last assistant record in the turn that carries text.
OUT="$("$JQ" -rs '
  def isprompt: .type=="user" and ((.message.content|type)=="string"
    or ([.message.content[]? | select(.type=="tool_result")] | length) == 0);
  (. as $a | [range(0; $a|length) | select($a[.] | isprompt)] | last // -1) as $p
  | .[($p+1):] as $turn
  | ([$turn[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
      | select(.name=="Write" or .name=="Edit" or .name=="MultiEdit" or .name=="NotebookEdit"
          or (.name=="Bash" and ((.input.command // "")
            | test("(^|[^0-9&>])>>?[ ]*[^ &>/]|\\btee\\b|\\bsed +-i|\\bgit +(add|commit|apply|mv|rm)\\b|(^|[;&| ])(mv|cp|rm|touch|mkdir) "))))] | length > 0) as $w
  | ([$turn[] | select(.type=="assistant")
      | [.message.content[]? | select(.type=="text") | .text] | select(length>0) | join("\n")] | last // "") as $r
  | "\($w)\t\($r | split(" ") | map(select(length>0)) | length)\t\($r | @base64)"' "$TX" 2>/dev/null)" || exit 0
[ -n "$OUT" ] || exit 0

WROTE="$(printf '%s' "$OUT" | cut -f1)"
WORDS="$(printf '%s' "$OUT" | cut -f2)"
REPLY="$(printf '%s' "$OUT" | cut -f3 | (base64 -D 2>/dev/null || base64 -d 2>/dev/null))"
case "$WORDS" in ''|*[!0-9]*) exit 0 ;; esac
[ "$WORDS" -gt 0 ] || exit 0

# EVIDENCE = a fenced block, a diff, a pass/fail count, an exit code. Words like "tests pass" with no
# output do not count. Falsifier: a reply that quotes a real result and is flagged, or a bare claim that is not.
HAS_EVIDENCE=0
if printf '%s\n' "$REPLY" | LC_ALL=C /usr/bin/grep -Eq '```|^@@ |^diff --git|^[+-]{3} [ab/]|[0-9]+ (passed|failed|files? changed|insertions?)|exit( code| status)? ?[:=]? ?[0-9]|\brc ?= ?[0-9]'; then
  HAS_EVIDENCE=1
fi

MSG=""
if [ "$WROTE" = "true" ] && [ "$HAS_EVIDENCE" = 0 ]; then
  MSG="This turn wrote files but the reply cites no command output, test result or diff. Changed needs its evidence beside the claim."
fi
if [ "$WORDS" -gt "$MAX_WORDS" ]; then
  MSG="${MSG:+$MSG
}The reply is $WORDS words (advisory threshold $MAX_WORDS). Answer first; keep the rest in reserve."
fi
[ -n "$MSG" ] || exit 0

MSG="[check:reply-shape] warn (advisory, never blocks)
$MSG
Not checked: whether line one answers the question. That stays review-only.
Disable: touch $CFG/reply-shape.off"
printf '%s' "$MSG" | "$JQ" -Rs '{systemMessage: .}' 2>/dev/null || true
exit 0
