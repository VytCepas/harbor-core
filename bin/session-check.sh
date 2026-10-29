#!/usr/bin/env sh
# session-check.sh (harbor#1043, #1044) — rule event.session-check: lint what a finished session changed.
#
# On session.state -> done, for the session's repo (when it carries bin/lint-conventions.sh and has files changed against
# origin/main) it runs the repo's lint and writes $STATE/sessions/<id>.check: `ok` or `red <N>`. Nothing is edited. The
# glyph reads the file at the next turn. Read-only on the repo. On/off: harbor event on --preset|--off event.session-check.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
LOG_FD=2; log_init "session-check"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = session.state ] || exit 0
[ "$RSTATE" = done ] || exit 0
CWD="$(react_rec cwd)"
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0
TOP="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$TOP/bin/lint-conventions.sh" ] || exit 0
CH="$(git -C "$TOP" diff --name-only origin/main...HEAD 2>/dev/null | grep -c .)" || CH=0
[ "${CH:-0}" -gt 0 ] || exit 0
OUT="$RSTATE_DIR/sessions/$RSID.check"
LINT="$(HARBOR_ROOT="$TOP" sh "$TOP/bin/lint-conventions.sh" 2>&1)"; RC=$?
V="$(printf '%s\n' "$LINT" | grep -c 'VIOLATION')"
if [ "$RC" -eq 0 ]; then R=ok; else R="red ${V:-$RC}"; fi
printf '%s\n' "$R" > "$OUT.new" 2>/dev/null && mv -f "$OUT.new" "$OUT" 2>/dev/null
react_log event.session-check "$(printf '%.6s' "$RSID"): lint $R over $CH changed file(s)"
log_end || :
exit 0
