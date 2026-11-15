#!/usr/bin/env sh
# session-cleanup.sh (harbor#456) — runs the sweep's RECLAIM rows, on the agent's word.
#
#   session-cleanup.sh <session_id>
#
# Started DETACHED by hooks/session-state/session-state.sh when the agent ends a turn with the line [cleanup-ok]
# (the hook asks once each time a PR this session opened merges). It runs `housekeeping-clean.sh --apply --live`, which
# acts on RECLAIM rows only — a clean worktree whose PR merged with every commit, landed branches, empty session
# dirs — and never on DECIDE or RISK. Then it re-records the count the statusline shows. $STATE/cleanup-auto.off
# stops it. One run at a time (a pid file). Every outcome is a line in
# $STATE/backups/session-cleanup/<run>/log (library-log.sh); an action that failed is a FAIL line plus the rows it left.
# Exit 0 on every path. Its report-only sibling, which removes nothing, is session-cleanup-report.sh (the event.session-cleanup-report rule).
set -u
case "${1:-}" in -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;; esac
SID="${1:-}"
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
STATE="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
CLEAN="${HARBOR_SESSION_CLEANUP_TOOL:-$HERE/housekeeping-clean.sh}"
. "$HERE/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init session-cleanup
log() { log_note "$(printf '%.8s' "$SID") $1"; }

[ ! -e "$STATE/cleanup-auto.off" ] || exit 0
[ -f "$CLEAN" ] || exit 0
mkdir -p "$STATE/sessions" 2>/dev/null || exit 0
log_file "$STATE"
PIDF="$STATE/sessions/cleanup.pid"
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then log "already running: skipped"; exit 0; fi
printf '%s\n' "$$" > "$PIDF" 2>/dev/null || exit 0
trap 'rm -f "$PIDF"; log_end >/dev/null 2>&1 || :; exit 0' EXIT INT TERM

# The RECLAIM rows it acted on are the record; DECIDE and RISK rows are left for the operator's batch. A failed action
# is no RECLAIM row (housekeeping-clean.sh prints it as KEEP and exits 1), so it is logged as a failure, never as reclaimed.
OUT="$(sh "$CLEAN" --apply --live 2>&1)"; RC=$?
printf '%s\n' "$OUT" | awk '$1 == "RECLAIM" { $1 = ""; sub(/^ +/, ""); print }' | while IFS= read -r l; do log "reclaimed: $l"; done
if [ "$RC" -ne 0 ]; then
  log_fail "$(printf '%.8s' "$SID") cleanup did not complete: housekeeping-clean --apply exited $RC"
  log_fix "read the lines below, or run: sh bin/housekeeping-clean.sh --apply --live"
  printf '%s\n' "$OUT" | awk '/^  FAIL:/ || /^  note:   / { sub(/^  (FAIL|note): */, ""); print }' | while IFS= read -r l; do log "not reclaimed: $l"; done
fi
sh "$CLEAN" --record --live >/dev/null 2>&1 || :
log "sweep re-recorded: $(sed -n 1p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-sweep" 2>/dev/null)"
exit 0
