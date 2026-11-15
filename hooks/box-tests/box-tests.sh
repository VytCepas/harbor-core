#!/usr/bin/env sh
# box-tests.sh (harbor#1278) — the box's wiring of the check `member.tests` (bin/member-tests.sh): a code change in a registered
# project comes with a test. The manifest binds this one script to UserPromptSubmit (the snapshot) and Stop (the check); a manifest
# wire row carries no arguments, so the mode is read from the payload's hook_event_name and the work is member-tests.sh, beside it.
# Fails open: anything unreadable, any other event, a missing member-tests.sh: nothing printed, exit 0. Off: <config dir>/box-tests.off.
set -u
case "${1:-}" in -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)" || exit 0
[ -r "$HERE/member-tests.sh" ] || exit 0
JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -n "$JQ" ] || exit 0
IN="$(cat 2>/dev/null)" || exit 0
case "$(printf '%s' "$IN" | "$JQ" -r '.hook_event_name // ""' 2>/dev/null)" in
  UserPromptSubmit) printf '%s' "$IN" | sh "$HERE/member-tests.sh" snap ;;
  Stop) printf '%s' "$IN" | sh "$HERE/member-tests.sh" ;;
esac
exit 0
