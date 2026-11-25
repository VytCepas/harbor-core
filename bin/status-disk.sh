#!/usr/bin/env sh
# status-disk.sh (harbor#1060) — check status.disk: free space on the Mac's data volume under a floor (operator decision 2026-11-23).
#
#   sh status-disk.sh [check]   read the free space, write cache/disk-free.json, and say it in cache/checks.log when the verdict CHANGES
#   sh status-disk.sh status    the same read, printed, writing nothing
#   Exit: 0 free space is at or over the floor (or the check is off), 1 under it, 2 usage or the volume could not be read.
#
# Measured 2026-11-23: free space fell to 23 GB of 460 GB (the Colima VM's disk held 99 GB of runner garbage) and nothing said so. Run by
# status-fleet-snapshot-refresh.sh every tick; the statusline reads cache/disk-free.json and shows `DISK LOW 24G`, never probing itself.
# Floor, volume and df are HARBOR_STATUS_DISK_MIN_GB (30; 0 is off), _PATH, _DF (contracts/env.tsv). First look when low: ci-runners.sh tidy.
# platform: macOS, and any POSIX df -Pk. Removed notes: none.
set -eu
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac
. "$(dirname -- "$0")/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; log_init status-disk
CMD="${1:-check}"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end || :; exit 2; }
case "$CMD" in check|status) ;; *) log_fail "unknown command '$CMD'"; log_fix "sh $0 --help"; log_end || :; exit 2 ;; esac
CACHE_DIR="${HARBOR_SCOPE_CACHE_DIR:-$HOME/.claude/cache}"
OUT="$CACHE_DIR/disk-free.json"
LOG="$CACHE_DIR/checks.log"
NOW="${HARBOR_TEST_NOW:-$(date +%s)}"
DF="${HARBOR_STATUS_DISK_DF:-df}"
VOL="${HARBOR_STATUS_DISK_PATH:-/System/Volumes/Data}"
[ -d "$VOL" ] || VOL="$HOME"
MIN="${HARBOR_STATUS_DISK_MIN_GB:-30}"
case "$MIN" in ''|*[!0-9.]*|*.*.*|.) MIN=30 ;; esac
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

if awk -v m="$MIN" 'BEGIN { exit !(m + 0 == 0) }'; then   # off: the cache goes, the statusline shows nothing
  [ "$CMD" = status ] || rm -f "$OUT"
  log_skip "the check is off (HARBOR_STATUS_DISK_MIN_GB=0)"; log_end || :; exit 0
fi
# df -Pk: one line per volume, 1024-byte blocks, the fourth field is what a user can still write
FREE_KB="$("$DF" -Pk "$VOL" 2>/dev/null | awk 'NR == 2 && $4 ~ /^[0-9]+$/ { print $4 }')" || FREE_KB=""
[ -n "$FREE_KB" ] || { log_fail "free space on $VOL could not be read"; log_fix "df -Pk $VOL"; log_end || :; exit 2; }
LOW="$(awk -v f="$FREE_KB" -v m="$MIN" 'BEGIN { print (f < m * 1048576) ? "true" : "false" }')"
FREE_GB="$(awk -v f="$FREE_KB" 'BEGIN { printf "%.1f", f / 1048576 }')"
if [ "$CMD" = status ]; then
  printf '%s GB free on %s, floor %s GB: %s\n' "$FREE_GB" "$VOL" "$MIN" "$([ "$LOW" = true ] && echo LOW || echo ok)"
  [ "$LOW" = false ]; exit $?
fi
mkdir -p "$CACHE_DIR"
PREV=""
[ ! -f "$OUT" ] || PREV="$(jq -r '.low // empty | tostring' "$OUT" 2>/dev/null || :)"
# one line on a CHANGE of verdict, never one per tick; a first reading that is fine says nothing
MSG=""
if [ "$LOW" = true ] && [ "$PREV" != true ]; then
  MSG="LOW: $FREE_GB GB free on $VOL, under the $MIN GB floor; first look: sh bin/ci-runners.sh tidy (the runners' VM), then sh bin/housekeeping-clean.sh"
elif [ "$LOW" = false ] && [ "$PREV" = true ]; then
  MSG="cleared (was low): $FREE_GB GB free on $VOL"
fi
jq -cn --argjson at "$NOW" --arg path "$VOL" --argjson free "$FREE_GB" --argjson min "$MIN" --argjson low "$LOW" \
  '{at: $at, path: $path, free_gb: $free, min_gb: $min, low: $low}' > "$OUT.tmp.$$" \
  && mv -f "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; log_fail "$OUT could not be written"; log_fix "ls -ld $CACHE_DIR"; log_end || :; exit 2; }
# The line goes after the cache: a line without its cache would repeat next tick.
[ -z "$MSG" ] || printf '[check:status.disk] %s %s\n' "$(iso "$NOW")" "$MSG" >> "$LOG" 2>/dev/null || :
log_end || :
[ "$LOW" = false ]
