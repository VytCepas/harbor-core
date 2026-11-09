#!/usr/bin/env sh
# suggest-start.sh (harbor#1485): once a session, off the tool path, tick the session counter and print the short pointer, so a
# person's "stop suggesting that" has a route in a session where no line was shown. Shadow still ticks: the engine runs this first.
# With no stop tool installed there is nothing to tick and no route to name, so it prints nothing. Fails silent.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
SUGGEST_HERE="$HERE"
. "$HERE/suggest-subject.sh"
T="$(suggest_stop_tool)"
[ -n "$T" ] || exit 0
sh "$T" tick >/dev/null 2>&1 || :
printf 'Harbor shows a person at most one suggestion a session. When the person asks, and only then: `sh %s stop <id> --origin agent`, `start <id>`, `off` or `on` (each with --origin agent); `status --json` lists the ids.\n' "$T"
exit 0
