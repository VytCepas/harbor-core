#!/usr/bin/env sh
# harbor#173 · A3 follow-on — the memory hook that could not reach its moment.
#
# WHY THIS IS A PACK AND NOT A MEMORY LINE. The fact lives in the auto-memory as
# `zsh does not word-split`, and measured today it does not arrive: asked "I keep
# re-typing the same bq flags, how do I reuse them?", a live session answered
# `export BQ_FLAGS=...; bq $BQ_FLAGS ...` — precisely the defect the memory
# records. Two failures, both real:
#
#   1. The index hook states the FINDING ("does not word-split"); the operator
#      arrives with the SITUATION ("reuse these flags"). No match, no route.
#   2. Asked in the hook's own words, the session answered correctly and read
#      NOTHING — zero tool calls. A hook line self-sufficient enough to answer
#      from suppresses the read, so the estate-specific remedy never loads.
#
# E6 already measured the fix: the same sentence scored 0/4 in the prefix and 4/4
# injected at the tool call. A fact that matters WHEN A COMMAND RUNS belongs on
# the command, not in a document the model must remember to consult.
#
# PRECISION OVER REACH, because §2.11 makes a false positive a defect. This fires
# only where the trap actually bites: a BARE `$VAR` in argument position to a CLI
# whose arguments are conventionally a string of flags. `cd $HOME`, `echo $PATH`
# and every quoted `"$VAR"` stay silent — they pass one value and one value is
# what they want.
#
# stdin is the hook payload; stdout is the note (empty = no note).
set -u

CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null | head -c 65536 || true)"
[ -n "$CMD" ] || exit 0

# A HEREDOC BODY IS DOCUMENTATION, NOT A COMMAND, and this rule fired on its own
# ticket. `gh issue create --body "$(cat <<'EOF' … bq query $P '<sql>' … EOF)"`
# carries the trap as an EXAMPLE, and scanning the raw command matched it — the
# same self-referential false positive the injected-instruction detector already
# carries, arriving within the hour on a pack written to describe the trap.
# §2.11: a false positive is a defect, not safety. The engine strips heredocs
# before its own predicates match; a run: script gets the raw command and has to
# do it itself.
CMD="$(printf '%s\n' "$CMD" | awk '
  /<<-?[ ]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/ && !skip {
    t = $0; sub(/^.*<<-?[ ]*/, "", t); gsub(/['\''"]/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t)
    if (t != "") { term = t; skip = 1; print; next }
  }
  skip { s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == term) skip = 0; next }
  { print }')"
[ -n "$CMD" ] || exit 0

# The tools whose calling convention is a run of flags, so a variable standing in
# for several of them is the documented shape rather than a guess.
TOOLS='bq gcloud gsutil gh docker aws kubectl curl ffmpeg rsync jq psql'

# A bare $NAME or ${NAME}: not "$NAME" (quoted, one value intended), not $1/$@/$?
# (positional and special, which DO behave), not $(...) (substitution).
hit=$(printf '%s' "$CMD" | awk -v tools="$TOOLS" '
  BEGIN { n = split(tools, T, " "); for (i = 1; i <= n; i++) want[T[i]] = 1 }
  {
    line = $0
    # blank every double-quoted span: a quoted variable is not this trap
    out = ""; inq = 0
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (c == "\"") { inq = !inq; out = out c; continue }
      out = out (inq ? " " : c)
    }
    n2 = split(out, W, /[ \t]+/)
    for (i = 1; i <= n2; i++) {
      w = W[i]
      if (w in want) cur = w
      else if (cur != "" && w ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) { print cur; exit }
    }
  }')

[ -n "$hit" ] || exit 0

cat <<EOF
This shell does not word-split. \`$hit\` is being passed a bare \`\$VAR\`, and zsh
hands it over as ONE argument containing spaces rather than several — so a
variable holding \`--a --b --c\` arrives as the single garbled flag \`--a --b --c\`
and the tool answers with a confusing error about the first one. It cost a false
finding here on 2026-07-31: \`bq query \$P '<sql>'\` returned
\`ProjectId must be non-empty\`, which was recorded as "bq --dry_run is broken
under gcx" and had to be retracted after re-running with the flags spelled out.
The remedy is not an array or \`\${(z)VAR}\` — write the flags out literally, or
define a shell FUNCTION, because a function passes "\$@" correctly where a
variable does not. When a command fails in a way that implicates the TOOL, re-run
it fully spelled out before believing the tool is broken.
EOF
