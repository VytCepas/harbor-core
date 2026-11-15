#!/usr/bin/env sh
# A suite started by hand (harbor#1010): `sh tests/**/x.test.sh`, `bash ...`, or the path itself.
#
# bin/test-suite-run.sh carries the idle and hard timeouts and the CI governor's CPU slot; a suite run outside it
# hung 14 h (measured 2026-11-02). PRECISION OVER REACH (CONSTITUTION 2.11): the command word of a segment must be a
# shell or the suite path itself, with a *.test.sh as its first non-flag argument; quoted text and heredocs are data.
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
case "$CMD" in *.test.sh*) ;; *) exit 0 ;; esac

HIT="$(printf '%s\n' "$CMD" | tr ';&|(){}' '\n\n\n\n\n\n\n' | awk '
  { n = split($0, w, /[ \t]+/); i = 1
    while (i <= n && (w[i] == "" || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || w[i] == "time" || w[i] == "nohup" || w[i] == "env")) i++
    if (i > n) next
    c = w[i]; b = c; sub(/^.*\//, "", b)
    if (c ~ /\.test\.sh$/) { print "hit"; exit }
    if (b !~ /^(sh|bash|zsh|dash)$/) next
    for (j = i + 1; j <= n; j++) { if (w[j] == "" || w[j] ~ /^-/) continue
      if (w[j] ~ /\.test\.sh$/) { print "hit"; exit }
      break } }')"
[ -n "$HIT" ] || exit 0

cat <<'EOF'
Run a suite through the runner, not by hand: `sh bin/test-suite-run.sh --select <suite-or-path>` (harbor checkout; the
suite list is contracts/suites.txt). The runner carries the idle and hard timeouts and takes a CPU slot from the CI
governor; a suite run directly has neither, and one hung 14 h before anyone looked (measured 2026-11-02). `--plan` prints
the queue and runs nothing; `sed -n 2,17p bin/test-suite-run.sh` lists the flags. A suite that clones the repo can fail
inside the Claude sandbox only: rerun outside it before believing a red.
EOF
