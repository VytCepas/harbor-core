#!/usr/bin/env sh
# MANAGED RETENTION (harbor#1181 lane 6) — pins transcript retention in the root-owned managed-settings.json,
# where no user, project, local or session setting can lower it. Claude Code deletes transcripts after
# cleanupPeriodDays (default 30), and they are the only full record of what an agent did.
#   sudo sh managed-retention.sh              write cleanupPeriodDays (merged into any existing managed file)
#   sh managed-retention.sh --dry-run         print the target path and the merged JSON, write nothing
#   sudo sh managed-retention.sh --uninstall  remove exactly the key this wrote, keep the rest
# HARBOR_MANAGED_SETTINGS moves the file (tests, no root) and is refused under root. A session cannot run this.
set -eu
# Under sudo a user-writable dir on PATH would run its jq/mkdir/chown as root: pin it first.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init managed-retention
DAYS=365   # operator decision 2026-10-09 (harbor#1181)
if [ "$(id -u)" -eq 0 ] && [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then
  log_fail "HARBOR_MANAGED_SETTINGS is set under root: refusing to write a caller-chosen path"
  log_fix "sudo env -u HARBOR_MANAGED_SETTINGS sh $0"; exit 1
fi
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then
  FILE="$HARBOR_MANAGED_SETTINGS"
else
  case "$(uname -s)" in
    Darwin) FILE='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
    *) FILE='/etc/claude-code/managed-settings.json' ;;
  esac
fi
BASE="$(dirname -- "$FILE")"
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/managed-retention.sh --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq not found on the pinned PATH ($PATH)"; log_nofix "install jq at /usr/bin"; exit 1; }

CUR='{}'
if [ -f "$FILE" ]; then
  CUR="$(cat "$FILE")"
  printf '%s' "$CUR" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || { log_fail "$FILE is not a JSON object; not touching it"; log_nofix "fix or remove $FILE by hand"; exit 1; }
fi
if [ "$MODE" = uninstall ]; then
  NEW="$(printf '%s' "$CUR" | jq 'del(.cleanupPeriodDays)')"
else
  NEW="$(printf '%s' "$CUR" | jq --argjson d "$DAYS" '.cleanupPeriodDays = $d')"
fi
log_note "target: $FILE"
if [ "$MODE" = dry ]; then printf '%s\n' "$NEW"; log_note "dry run: nothing written"; exit 0; fi

if [ -z "${HARBOR_MANAGED_SETTINGS:-}" ] && [ "$(id -u)" -ne 0 ]; then
  log_fail "not root: this file is root-owned by design"
  log_fix "sudo sh $0$([ "$MODE" = uninstall ] && echo ' --uninstall')"; exit 1
fi
mkdir -p "$BASE"
TMPF="$(mktemp "$BASE/.managed-settings.XXXXXX")"; trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$NEW" > "$TMPF"
if [ "$(id -u)" -eq 0 ]; then
  grp=wheel; [ "$(uname -s)" = Darwin ] || grp=root
  chown root:"$grp" "$TMPF"
fi
chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"; trap - EXIT
# Read back: the claim "retention is pinned" closes on the file, not on the write having returned.
_got="$(jq -r '.cleanupPeriodDays // "absent"' "$FILE" 2>/dev/null || echo unreadable)"
_want="$DAYS"; [ "$MODE" = install ] || _want=absent
[ "$_got" = "$_want" ] || { log_fail "$FILE reads cleanupPeriodDays=$_got after the write, want $_want"; log_nofix "inspect $FILE"; exit 1; }
log_ok "$MODE: $FILE cleanupPeriodDays=$_got"; log_end
