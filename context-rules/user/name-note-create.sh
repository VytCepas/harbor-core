#!/usr/bin/env sh
# name-note-create (harbor#978 item 9): a create command whose new name breaks the standard draws a note
# with the compliant form. A note, never a decision: the HARBOR-DECISION sentinel appears nowhere below.
#
# FAIL-OPEN: no jq, no rows, no match, a name made of $VARS, no lint, or a lint error prints nothing and exits 0.
set -u
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null | head -c 65536 || true)"
[ -n "$CMD" ] || exit 0
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# A heredoc body is documentation, not a command (the same strip unbounded-wait-loop.sh does).
CMD="$(printf '%s\n' "$CMD" | awk '
  /<<-?[ ]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/ && !skip {
    t = $0; sub(/^.*<<-?[ ]*/, "", t); gsub(/['\''"]/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t)
    if (t != "") { term = t; skip = 1; print; next }
  }
  skip { s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == term) skip = 0; next }
  { print }')"
[ -n "$CMD" ] || exit 0

R="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null)" || R=""
if [ -n "$R" ] && [ -f "$R/bin/lint-name.sh" ] && [ -f "$R/standards/naming/surfaces.tsv" ]; then LINT="$R/bin/lint-name.sh"; LROOT="$R"
elif [ -f "$CFG/bin/lint-name.sh" ]; then LINT="$CFG/bin/lint-name.sh"; LROOT=""
else exit 0; fi

TAB="$(printf '\t')"
for F in "$CFG"/name-create.d/*.tsv; do
  [ -f "$F" ] || continue
  while IFS="$TAB" read -r RE SURF NOTE _; do
    case "$RE" in ''|'#'*) continue ;; esac
    [ -n "$SURF" ] || continue
    # The text after the first match of RE, or nothing.
    REST="$(printf '%s\n' "$CMD" | RE="$RE" awk '{ if (match($0, ENVIRON["RE"])) { print substr($0, RSTART + RLENGTH); exit } }')"
    [ -n "$REST" ] || continue
    NAME=""
    for W in $REST; do
      case "$W" in -*) continue ;; esac
      NAME="$W"; break
    done
    NAME="${NAME#[\'\"]}"; NAME="${NAME%[\'\"]}"
    case "$NAME" in ''|*[\$\`\;\&\|\(\)\<\>\\]*) continue ;; esac
    # exit 1 is a block-mode finding, which is what the note is for; 2 and above judged nothing.
    _rc=0
    if [ -n "$LROOT" ]; then OUT="$(sh "$LINT" --root "$LROOT" --check "$SURF" "$NAME" 2>&1)" || _rc=$?
    else OUT="$(sh "$LINT" --check "$SURF" "$NAME" 2>&1)" || _rc=$?; fi
    [ "$_rc" -le 1 ] || continue
    FIND="$(printf '%s\n' "$OUT" | sed -n -E 's/^[[:space:]]*(WARN|FAIL): (\[[^]]*\] )(.*)$/\2\3/p')"
    [ -n "$FIND" ] || continue
    printf '%s\n' "Name check (harbor#978, advisory, the command was not blocked). \`$NAME\` is a new $SURF name, and the naming standard (standards/naming/) says: $(printf '%s' "$FIND" | awk 'NR > 1 { printf "; " } { printf "%s", $0 }').${NOTE:+ $NOTE} Choose the name before the thing exists: a rename later has to move every reference with it."
    exit 0
  done < "$F"
done
exit 0
