#!/usr/bin/env sh
# session-cleanup-report.sh (harbor#1043, #1044) — rule event.session-cleanup-report: what a finished session left behind. REPORT ONLY.
#
# On session.state -> done it writes $STATE/sessions/<id>.cleanup.txt: processes whose parent is init and whose command
# line names the session's directory (orphans), and linked worktrees of the session's repo whose branch is merged into
# origin/main with a clean tree (stale). It kills nothing, removes nothing, and writes no other file. On/off:
# harbor event on --preset|--off event.session-cleanup-report.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
. "$HERE/library-log.sh"
LOG_FD=2; log_init "session-cleanup-report"
. "$HERE/session-react-lib.sh"
react_event || exit 0
[ "$RKIND" = session.state ] || exit 0
[ "$RSTATE" = done ] || exit 0
CWD="$(react_rec cwd)"
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0
OUT="$RSTATE_DIR/sessions/$RSID.cleanup.txt"
{
  printf 'cleanup report for session %.6s — report only, nothing was killed or removed\n\n' "$RSID"
  printf 'orphan processes (parent is init, command names %s):\n' "$CWD"
  PS_OUT="$(ps -axo pid=,ppid=,etime=,command= 2>/dev/null)" || PS_OUT=""
  printf '%s\n' "$PS_OUT" | awk -v d="$CWD" -v me="$$" '$2 == 1 && $1 != me && index($0, d) { c = $0; sub(/^ *[0-9]+ +[0-9]+ +/, "", c); printf "  pid %s up %s  %.100s\n", $1, $3, substr(c, index(c, $4)) ; n++ }
    END { if (!n) print "  none" }'
  printf '\nstale worktrees (branch merged into origin/main, tree clean):\n'
  _n=0; _wt=""
  git -C "$CWD" worktree list --porcelain 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in
      "worktree "*) _wt="${_l#worktree }" ;;
      "branch refs/heads/"*)
        _b="${_l#branch refs/heads/}"
        [ "$_wt" != "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" ] || continue
        git -C "$CWD" merge-base --is-ancestor "refs/heads/$_b" origin/main 2>/dev/null || continue
        [ -z "$(git -C "$_wt" status --porcelain 2>/dev/null)" ] || continue
        printf '  %s  (%s)\n' "$_wt" "$_b" ;;
    esac
  done | tee "$OUT.wt" | sed -n '1,50p'
  [ -s "$OUT.wt" ] || printf '  none\n'
  rm -f "$OUT.wt"
} > "$OUT.new" 2>/dev/null && mv -f "$OUT.new" "$OUT" 2>/dev/null
rm -f "$OUT.new" 2>/dev/null
react_log event.session-cleanup-report "$(printf '%.6s' "$RSID"): wrote $(basename "$OUT")"
log_end || :
exit 0
