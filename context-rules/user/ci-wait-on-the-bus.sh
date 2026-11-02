#!/usr/bin/env sh
# A session polling CI (harbor#1367): `gh pr checks` or `gh run` inside a wait, or a `--watch`.
#
# Every runner this box hosts puts ci.job.done on the event bus, and `harbor event ci <owner/repo>#<n>`
# (bin/ci-wait.sh) sleeps on it and reads the checks once per finished job. A poll costs a GitHub read every
# interval and, measured 2026-10-25, waited 31 minutes on review/decision, a status that is not CI.
#
# PRECISION OVER REACH (CONSTITUTION §2.11). It fires only on a read that is being REPEATED:
#   · `gh run watch`, or `gh pr checks … --watch`;
#   · `gh pr checks`, `gh pr view` or `gh run view|list` inside `wait-for`, `watch`, a `while`/`until` loop (not
#     `while read`), or a `for` loop that sleeps (harbor#1010).
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
# A hand-rolled repeat, by construction: while/until (never `while read`, which EOF bounds), `watch`, or a `for` that
# sleeps between reads. `gh pr view` is a read people also loop on, so it needs the sleep too (harbor#1010).
_loop() {
  printf '%s\n' "$CMD" | awk '
    /(^|[;&|(){}[:space:]])(until|watch)[[:space:]]/ { f = 1 }
    match($0, /(^|[;&|(){}[:space:]])while[[:space:]]/) {
      r = substr($0, RSTART + RLENGTH); sub(/^[[:space:]]+/, "", r)
      if (r !~ /^(IFS=[^[:space:]]*[[:space:]]+)?read([[:space:]]|$)/) f = 1 }
    /(^|[;&|(){}[:space:]])for[[:space:]]/ { fr = 1 }
    /sleep/ { sl = 1 }
    END { exit !((f && (sl || !need)) || (fr && sl)) }' need="$1"
}
case "$CMD" in *'gh run watch'*) ;; *'gh pr checks'*'--watch'*) ;;
  *'gh pr checks'*|*'gh run view'*|*'gh run list'*)
    case "$CMD" in *wait-for*) ;; *) _loop 0 || exit 0 ;; esac ;;
  *'gh pr view'*)
    case "$CMD" in *wait-for*) ;; *) _loop 1 || exit 0 ;; esac ;;
  *) exit 0 ;;
esac

cat <<'EOF'
This polls CI by hand. Wait on the event bus instead, in the background so you are re-invoked when it returns:
`sh ~/port/harbor/bin/ci-wait.sh <owner/repo>#<n> --timeout 1800` (run_in_background; `harbor event ci <owner/repo>#<n>`
is the same tool). It sleeps until a runner this box hosts reports ci.job.done, reads the checks once, and prints one
line: exit 0 green, 1 red, 3 still running at --timeout. It never waits on `review/decision`: that status is a person's
review, pending until approved, and a poll for "nothing pending" sat 31 minutes on it with CI green. For a PR you just
opened, a bare `gh pr create` (no pipe after it) already starts the same wait and a banner (event.session-ci-watch).
Other kinds on the bus, and their emitters: contracts/event-kinds.tsv; any of them can be waited on with
`harbor event wait '<pattern>' --timeout N`.
EOF
