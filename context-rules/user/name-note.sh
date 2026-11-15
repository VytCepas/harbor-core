#!/usr/bin/env sh
# 98-name-note (harbor#978): a Write that creates a file whose name breaks the naming standard draws a
# note naming the finding and the surface's grammar. It prints a note, never a decision: the
# HARBOR-DECISION sentinel appears nowhere below, so this cannot block a call.
#
# FAIL-OPEN, like every run: script. No jq, no git, a path that already exists, a repo with no
# bin/lint-name.sh and standards/naming/, or a lint that errors prints nothing and exits 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
F="$(printf '%s' "$P" | jq -r '.tool_input.file_path // empty | strings' 2>/dev/null)" || exit 0
[ -n "$F" ] || exit 0
case "$F" in /*) ;; *) F="${CLAUDE_PROJECT_DIR:-$PWD}/$F" ;; esac
[ ! -e "$F" ] || exit 0

# The nearest folder that exists, and the new tail below it; paths are compared physically, as git prints them.
D="${F%/*}"; TAIL="${F##*/}"
while [ -n "$D" ] && [ ! -d "$D" ]; do TAIL="${D##*/}/$TAIL"; D="${D%/*}"; done
[ -n "$D" ] || exit 0
DP="$(CDPATH= cd -- "$D" 2>/dev/null && pwd -P)" || exit 0
R="$(git -C "$DP" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$R/bin/lint-name.sh" ] && [ -f "$R/standards/naming/surfaces.tsv" ] || exit 0
case "$DP" in "$R") REL="$TAIL" ;; "$R"/*) REL="${DP#"$R"/}/$TAIL" ;; *) exit 0 ;; esac

# exit 1 is a block-mode finding, which is exactly what the note is for; 2 and above judged nothing.
_rc=0; OUT="$(sh "$R/bin/lint-name.sh" --root "$R" --check path "$REL" 2>&1)" || _rc=$?
[ "$_rc" -le 1 ] || exit 0
# `WARN|FAIL: [name.x] <subject> — <message>`; a subject already on disk is a choice made before this write.
FIND="$(printf '%s\n' "$OUT" | sed -n -E 's/^[[:space:]]*(WARN|FAIL): (\[[^]]*\] )(.*)$/\2\3/p' | while IFS= read -r _l; do
  _s="${_l#*] }"; _s="${_s%% — *}"
  [ -e "$R/$_s" ] || printf '%s\n' "$_l"
done)"
[ -n "$FIND" ] || exit 0
printf '%s\n' "Name check (harbor#978, advisory, the call was not blocked). \`$REL\` is a new name, and the naming standard (standards/naming/) says: $(printf '%s' "$FIND" | awk 'NR > 1 { printf "; " } { printf "%s", $0 }'). Choose the name before the file exists: a rename later has to move every reference with it."
