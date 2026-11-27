#!/usr/bin/env sh
# suggest-tool-spoke.sh (harbor#1485): the engine runs this with the row id as its one argument, only after the person's line was
# really spoken. It records the line through the stop tool, which hooks reach beside the installed packs. Fails silent.
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
[ -n "${1:-}" ] || exit 0
[ -f "$HERE/../../bin/status-suggest.sh" ] || exit 0
# exec: the engine's time bound then lands on the tool itself, which frees its lock on TERM.
exec sh "$HERE/../../bin/status-suggest.sh" shown "$1" >/dev/null 2>&1
