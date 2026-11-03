#!/usr/bin/env sh
# A long wait on a background task (harbor#1010): `sleep` of 300 s or more, or `wait-for -t` / `event wait --timeout`
# of 600 s or more.
#
# Measured 2026-11-02: one lane idled 7.5 h on a background run that no longer existed. The harness re-invokes the model
# when a task finishes, but a task that was killed or never started finishes nothing, so the wait is silent.
# PRECISION OVER REACH (CONSTITUTION 2.11): only a duration over the bar fires; quoted text and heredocs are data, and a
# short sleep, a short wait-for and a command that merely mentions `sleep` stay silent.
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
  { print }' | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"
[ -n "$CMD" ] || exit 0

HIT="$(printf '%s\n' "$CMD" | tr ';&|(){}' '\n\n\n\n\n\n\n' | awk '
  function secs(t,   n, u) {
    if (t !~ /^[0-9]+[smhd]?$/) return 0
    u = substr(t, length(t), 1); n = t + 0
    return (u == "m") ? n * 60 : (u == "h") ? n * 3600 : (u == "d") ? n * 86400 : n }
  { n = split($0, w, /[ \t]+/); i = 1
    while (i <= n && (w[i] == "" || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[i] == "time" || w[i] == "nohup")) i++
    if (i > n) next
    c = w[i]; sub(/^.*\//, "", c)
    if (c == "sleep") { tot = 0; for (j = i + 1; j <= n; j++) tot += secs(w[j]); if (tot >= 300) { print "hit"; exit } }
    if (c == "wait-for") { for (j = i + 1; j < n; j++) if (w[j] == "-t" && secs(w[j+1]) >= 600) { print "hit"; exit } }
    if (c == "harbor" || c == "event-bus.sh") { m = 0
      for (j = i + 1; j <= n; j++) if (w[j] == "wait") m = 1
      if (m) for (j = i + 1; j < n; j++) if (w[j] == "--timeout" && secs(w[j+1]) >= 600) { print "hit"; exit } } }')"
[ -n "$HIT" ] || exit 0

cat <<'EOF'
Before you wait this long on a background task, confirm the process exists: `ps -p <pid>` (or `ps aux | grep <name>`), or
the harness task list. A task that was killed, never started or already finished sends no completion, and the wait looks
exactly like "not yet": a lane sat 7.5 h on a background run that no longer existed (measured 2026-11-02). If the wait
has produced nothing for 30 minutes, check the process again; if it is gone, stop waiting and carry on or report. Work the
harness tracks (background Bash, a Workflow, an Agent) re-invokes you on completion, so do not poll it at all; a PR's CI
is `sh ~/port/harbor/bin/ci-wait.sh <owner/repo>#<n> --timeout N` in the background.
EOF
