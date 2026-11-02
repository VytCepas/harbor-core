#!/usr/bin/env sh
# confinement-read-escape (harbor#1441) — a read-only Bash call that asks to leave the sandbox.
#
# Reads need no escape: the confinement denies writes and hosts, not reads of the repo. The `readonly` class in
# contracts/confinement-classes.tsv is the one whose treatment is this note on the call itself. Precision over reach
# (a false positive is a defect): it fires only when EVERY segment of the command starts with a read-only verb and the
# command redirects nowhere but to /dev/null, so a pipeline with one writer or a mutating verb stays silent.
#
# stdin is the hook payload; stdout is the note (empty = no note). Fail-open.
set -u
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat 2>/dev/null | head -c 262144)" || exit 0
[ "$(printf '%s' "$P" | jq -r '.tool_input.dangerouslyDisableSandbox // false' 2>/dev/null || echo false)" = true ] || exit 0
CMD="$(printf '%s' "$P" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$CMD" ] || exit 0
# A redirect to a file is a write, and a write outside the zone is a real reason to escape.
_c="$CMD"
for _n in '2>&1' '>/dev/null' '2>/dev/null' '&>/dev/null'; do _c="$(printf '%s' "$_c" | sed "s|$_n||g")"; done
case "$_c" in *'>'*|*'$('*|*'`'*|*'<<'*) exit 0 ;; esac
_segs="$(printf '%s\n' "$_c" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }')"
_any=0
while IFS= read -r _s; do
  _s="$(printf '%s' "$_s" | sed 's/^[[:space:]]*//')"
  [ -n "$_s" ] || continue
  _v="${_s%%[[:space:]]*}"; _v="${_v##*/}"
  case "$_v" in
    grep|egrep|fgrep|rg|cat|ls|head|tail|wc|jq|stat|file|diff|cmp|pwd|echo|printf|sort|uniq|basename|dirname|cut|tr|nl|column|du|df|which|date|true|false|cd) _any=1 ;;
    *) exit 0 ;;
  esac
done <<SEGS
$_segs
SEGS
[ "$_any" = 1 ] || exit 0
cat <<'NOTE'
That call asked to run outside the sandbox, and every verb in it is a read, which runs confined. Drop
dangerouslyDisableSandbox and run it again. If it fails, the refusal names a host or a path; that is the reason to
escape, and the treatment for each is in contracts/confinement-classes.tsv. Each escape is counted by class (the
read-only class is the cheapest to remove).
NOTE
