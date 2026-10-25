#!/usr/bin/env sh
# An unbounded shell wait loop — the one mistake whose failure mode is silence.
#
# THE INCIDENT, 2026-08-24. A session waiting on a 5-agent workflow ran
#   until [ "$(grep -c 'completed\|failed\|finished' journal.jsonl)" -ge 5 ]
#   do sleep 15; done
# The journal writes `"type":"result"`; none of those three words is a status
# there. The count sat at 4 forever and needed 5, so the loop COULD NOT EXIT. It
# spun 39 minutes and was killed by hand. Two separate defects:
#
#   1. Unnecessary. Background Bash, Workflow and Agent all re-invoke the model on
#      completion, so polling harness-tracked work adds zero information.
#   2. Unterminating, and invisibly so. With no deadline, no distinct "gave up"
#      status and no output, a permanently-false predicate is indistinguishable
#      from "not yet" — which is why 39 minutes passed before anyone looked.
#
# PRECISION OVER REACH (CONSTITUTION §2.11 — a false positive is a defect). This
# fires only on a loop that is unbounded BY CONSTRUCTION and carries a sleep:
#   · `for` never fires — its word list bounds it.
#   · `while read` / `while IFS=… read` never fires — EOF bounds it, and it is the
#     idiom this box's own memory recommends over `set -- $var` under zsh.
#   · a command computing a deadline (`date +%s`, `$SECONDS`) never fires — the
#     author has already bounded it.
#   · a command already calling `wait-for` never fires.
#
# stdin is the hook payload; stdout is the note (empty = no note).
set -u

CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null | head -c 65536 || true)"
[ -n "$CMD" ] || exit 0

# A HEREDOC BODY IS DOCUMENTATION, NOT A COMMAND. The $VAR pack shipped with
# exactly this false positive and fired on its own ticket within the hour: a
# heredoc quoting the trap as an EXAMPLE matched the raw command. The engine
# strips heredocs before its own predicates match; a run: script gets the raw
# command and must do it itself.
CMD="$(printf '%s\n' "$CMD" | awk '
  /<<-?[ ]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/ && !skip {
    t = $0; sub(/^.*<<-?[ ]*/, "", t); gsub(/['\''"]/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t)
    if (t != "") { term = t; skip = 1; print; next }
  }
  skip { s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == term) skip = 0; next }
  { print }')"
[ -n "$CMD" ] || exit 0

# Already bounded, or already using the helper: silence.
case "$CMD" in
  *wait-for*)   exit 0 ;;
  *'date +%s'*) exit 0 ;;
  *'$SECONDS'*) exit 0 ;;
  *SECONDS=*)   exit 0 ;;
esac

# A poll loop needs a sleep. No sleep, no note.
case "$CMD" in *sleep*) ;; *) exit 0 ;; esac

# An UNBOUNDED loop keyword, in command position.
KIND="$(printf '%s\n' "$CMD" | awk '
  {
    line = $0
    if (match(line, /(^|[;&|(){}[:space:]])until[[:space:]]/)) { print "until"; exit }
    if (match(line, /(^|[;&|(){}[:space:]])while[[:space:]]/)) {
      rest = substr(line, RSTART + RLENGTH)
      sub(/^[[:space:]]+/, "", rest)
      # `while read` and `while IFS=... read` terminate at EOF — not this trap.
      if (rest ~ /^(IFS=[^[:space:]]*[[:space:]]+)?read([[:space:]]|$)/) next
      print "while"; exit
    }
  }')"
[ -n "$KIND" ] || exit 0

cat <<EOF
This \`$KIND\` loop has a \`sleep\` and no deadline, so it cannot report giving up.
First: if you are waiting on background Bash, a Workflow or an Agent, DELETE the
loop — the harness re-invokes you when that work completes, so polling it buys
nothing. Measured here on 2026-08-24: a loop waiting on a 5-agent workflow spun
39 minutes because its predicate could never match the file's real format (it
read 4 forever and needed 5), and the workflow's own notification is what
actually reported completion. With no deadline, no "gave up" status and no
output, a permanently-false predicate looks exactly like "not yet". If the thing
you are waiting on is genuinely EXTERNAL — Cloud Build, a data-sync run, a
warehouse job, CI, a port — use \`wait-for\`, which cannot hang and prints what it
observed: \`wait-for -t 900 -i 30 -w 'CMD printing the observed value' -- PREDICATE\`
(exit 0 met, 3 gave up, 4 broken predicate). Either way, do not \`set -e\` around a
wait predicate: non-zero is the normal "not yet" and would abort on the first poll.
EOF
