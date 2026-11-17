#!/usr/bin/env sh
# The CI verdict of a PR this session opened (harbor#1044): event.session-ci-watch writes one line per notice to
# <state>/session-notes/<session id> (bin/session-react-lib.sh react_session_note); this prints them once and removes them.
# Measured 2026-11-16: a stuck PR's verdict went to the desktop and reactions.log, and the session that opened it never knew.
#
# stdin is the hook payload; stdout is the note (empty = no note). Another session's file is never read: the path is
# this payload's own session id, checked against the id charset before it names a file.
set -u
SID="$(jq -r '.session_id // empty' 2>/dev/null || true)"
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
D="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}/session-notes"
F="$D/$SID"
[ -s "$F" ] || exit 0
# Taken by a rename, so a note the watch appends meanwhile lands in a new file and waits for the next call.
T="$D/.$SID.$$"
mv -f "$F" "$T" 2>/dev/null || exit 0
L="$(tail -n 5 "$T" | cut -c1-300)"
rm -f "$T"
[ -n "$L" ] || exit 0
printf 'CI on a PR this session opened (event.session-ci-watch):\n%s\nAct on it before you wait on, merge or build on that PR.\n' "$L"
