#!/usr/bin/env sh
# skill-book.sh — the old name of bin/skill-catalog.sh, kept for one release (harbor#1010). Runs it with the same arguments.
#   sh bin/skill-book.sh [args]   same as: sh bin/skill-catalog.sh [args]
# Remove this file with the alias row for skill-book in standards/naming/renames.tsv when that row's release has passed.
set -eu
case "${1:-}" in
  -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR=. ;; esac
. "$SELF_DIR/library-log.sh"; log_init skill-book
log_note "renamed to skill-catalog.sh (harbor#1010); running it"
_rc=0; sh "$SELF_DIR/skill-catalog.sh" "$@" || _rc=$?
log_end || :
exit "$_rc"
