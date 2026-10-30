#!/usr/bin/env sh
# A session polling CI (harbor#1367): `gh pr checks` or `gh run` inside a wait, or a `--watch`.
#
# Every runner this box hosts puts ci.job.done on the event bus, and `harbor event ci <owner/repo>#<n>`
# (bin/ci-wait.sh) sleeps on it and reads the checks once per finished job. A poll costs a GitHub read every
# interval and, measured 2026-10-25, waited 31 minutes on review/decision, a status that is not CI.
#
# PRECISION OVER REACH (CONSTITUTION §2.11). It fires only on a read that is being REPEATED:
#   · `gh run watch`, or `gh pr checks … --watch`;
#   · `gh pr checks` or `gh run view|list` inside `wait-for`, or inside a `while`/`until` loop.
# A single `gh pr checks <n>` is a read, not a wait, and never fires; nor does a command already using
# `harbor event ci` or `ci-wait.sh`. A heredoc body is documentation and is stripped first.
#
# stdin is the hook payload; stdout is the note (empty = no note).
set -u

CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null | head -c 65536 || true)"
[ -n "$CMD" ] || exit 0
CMD="$(printf '%s\n' "$CMD" | awk '
  /<<-?[ ]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/ && !skip {
    t = $0; sub(/^.*<<-?[ ]*/, "", t); gsub(/['\''"]/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t)
    if (t != "") { term = t; skip = 1; print; next }
  }
  skip { s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == term) skip = 0; next }
  { print }')"
[ -n "$CMD" ] || exit 0

case "$CMD" in *'event ci '*|*ci-wait.sh*) exit 0 ;; esac
case "$CMD" in *'gh run watch'*) ;; *'gh pr checks'*'--watch'*) ;;
  *'gh pr checks'*|*'gh run view'*|*'gh run list'*)
    case "$CMD" in *wait-for*) ;; *)
      printf '%s\n' "$CMD" | grep -Eq '(^|[;&|(){}[:space:]])(while|until)[[:space:]]' || exit 0 ;;
    esac ;;
  *) exit 0 ;;
esac

cat <<'EOF'
This polls CI. Wait on the event bus instead: `harbor event ci <owner/repo>#<n>` (bin/ci-wait.sh) sleeps until a
runner this box hosts reports ci.job.done, reads the checks once, and prints one line: exit 0 green, 1 red,
3 still running at --timeout (default 1800 s). It never waits on `review/decision`: that status is a person's
review, pending until approved, and a poll for "nothing pending" sat 31 minutes on it with CI green. For a PR
you just opened, a bare `gh pr create` (no pipe after it) already starts the same wait and a banner
(event.session-ci-watch). Other kinds on the bus, and their emitters: contracts/event-kinds.tsv; any of them
can be waited on with `harbor event wait '<pattern>' --timeout N`.
EOF
