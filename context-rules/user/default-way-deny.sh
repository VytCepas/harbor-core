#!/usr/bin/env sh
# default-way-deny.sh (harbor#1397) — the deny half of default-way-route: a Write or Edit of the INSTALLED copy of a skill,
# a script, a hook or the hooks block, which no deploy performs. The rows and the wording are default-way-route.tsv's and
# default-way-route.sh's (--deny); this adds only the sentinel. The engine honours it when the pack's controls.tsv row is
# block and delivers it as a note otherwise (born warn, harbor/D-64). Fail-open: no output, no decision.
set -u
HERE="${0%/*}"; [ "$HERE" != "$0" ] || HERE=.
[ -f "$HERE/default-way-route.sh" ] || exit 0
_msg="$(sh "$HERE/default-way-route.sh" --deny 2>/dev/null)" || exit 0
[ -z "$_msg" ] || printf 'HARBOR-DECISION deny: %s\n' "$_msg"
exit 0
