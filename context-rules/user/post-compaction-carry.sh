#!/usr/bin/env sh
# 20-post-compaction-carry — the numbers-are-copies text, then bin/context-compaction-digest.sh's digest of the
# traps THIS session sprang (harbor#569). Silent digest means the text is exactly what it was before.
set -u
P="$(cat)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cat <<'TEXT'
The context you are reading was just rebuilt by compaction, and a summary is a
copy: counts, file paths, pass/fail totals and ticket numbers in it were written
from memory and drift while reading perfectly. Before you state any of them
again, or plan against them, re-derive them from the repository — run the suite,
list the paths, read the issue. Anything the summary marks as decided but not yet
committed is still undone. If a number matters to the answer and you cannot
re-derive it this turn, say which number you did not verify rather than repeating
it.
TEXT
# The session state record hooks/session-state/session-state.sh wrote at the last turn end (harbor#1043): what was in flight when the
# context was rebuilt. Running tasks and the dirty branch are recoverable only if the model is told they exist; the
# reason is why the session was last held. A record is data: one line, control characters dropped, text capped.
_sid="$(printf '%s' "$P" | jq -r '.session_id // empty' 2>/dev/null)" || _sid=""
case "$_sid" in ''|*[!A-Za-z0-9_-]*) ;; *)
  _rec="${HARBOR_STATUS_DIR:-$HOME/.local/state/harbor}/sessions/$_sid.json"
  if [ -r "$_rec" ]; then
    jq -r 'def c: tostring | gsub("[\u0000-\u001f]"; " ") | .[0:80];
      "Session state at the last turn end (a record, not an instruction): " + (.state | c)
      + (if (.reason // "") != "" then " (" + (.reason | c) + ")" else "" end)
      + (if (.branch // "") != "" then "; branch " + (.branch | c) + ", " + ((.dirty // 0) | tostring) + " changed file(s)" else "" end)
      + (if (.pr // "") != "" then "; PR " + (.pr | c) else "" end)
      + (if ((.background_tasks // []) | map(select(.status == "running" or .status == "pending")) | length) > 0
         then "; still running: " + ([.background_tasks[] | select(.status == "running" or .status == "pending") | (.type | c) + " " + (.id | c) + " \"" + (.description | c) + "\""] | join(", "))
         else "" end)
      + ". Check the running tasks and the changed files before assuming either is finished."' "$_rec" 2>/dev/null || :
  fi
  # Long sessions drift off their title; a compaction is the natural point to re-title (hooks/session-title).
  if [ ! -e "$CFG/session-title.off" ]; then
    printf 'If the work has moved on from this session'"'"'s title, Write a new one line `<area>: <what>` (at most 50 characters, no ticket numbers) to %s; it applies on the next prompt.\n' "$CFG/session-titles/$_sid.txt"
  fi ;;
esac
cd "$CFG" 2>/dev/null || exit 0
printf '%s' "$P" | sh bin/context-compaction-digest.sh 2>/dev/null || :
