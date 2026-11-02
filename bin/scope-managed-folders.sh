#!/usr/bin/env sh
# MANAGED FOLDERS (harbor#1442, #1440) — the Edit deny rows for the main folders, in the root-owned managed-settings.json
# where no user, project or local setting can remove them. The folders are contracts/main-folders.txt (then the private
# layer's file of the same name); each renders as `Edit(<path>/**)`.
#   sudo sh scope-managed-folders.sh              merge the rows into permissions.deny (every other key and row stays)
#   sh scope-managed-folders.sh --dry-run         print the target path and the merged JSON, write nothing
#   sudo sh scope-managed-folders.sh --uninstall  remove exactly these rows, keep the rest
#   sh scope-managed-folders.sh --rows            print the rendered rows, one per line
#   sh scope-managed-folders.sh --missing         print the rows the installed file lacks; exit 0 readable (empty = all held), 3 unreadable
# HARBOR_MANAGED_SETTINGS moves the file (tests, no root) and is refused under root. A session cannot run the install.
set -eu
# Under sudo a user-writable dir on PATH would run its jq/mkdir/chown as root: pin it first.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CORE="$HERE/../contracts"
LOG_FD=2; export LOG_FD   # stdout is data (--rows, --missing)
. "$HERE/library-log.sh"
log_init managed-folders
if [ "$(id -u)" -eq 0 ] && [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then
  log_fail "HARBOR_MANAGED_SETTINGS is set under root: refusing to write a caller-chosen path"
  log_fix "sudo env -u HARBOR_MANAGED_SETTINGS sh $0"; exit 1
fi
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then FILE="$HARBOR_MANAGED_SETTINGS"
elif [ "$(uname -s)" = Darwin ]; then FILE='/Library/Application Support/ClaudeCode/managed-settings.json'
else FILE=/etc/claude-code/managed-settings.json; fi
BASE="$(dirname -- "$FILE")"
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;; --rows) MODE=rows ;; --missing) MODE=missing ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh $0 --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq not found on the pinned PATH ($PATH)"; log_nofix "install jq at /usr/bin"; exit 1; }

# rows <file> -> its rows, comments and blank lines dropped; nothing for an absent file
rows() { [ -f "$1" ] || return 0; sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"; }
_priv="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"
FOLDERS="$({ rows "$CORE/main-folders.txt"; [ -z "$_priv" ] || rows "$_priv/main-folders.txt"; } | awk '!seen[$0]++')"
# A row that is not home-relative would anchor somewhere else (bin/admission-deny.sh ANCHORING): refuse it, never render it.
_bad="$(printf '%s\n' "$FOLDERS" | grep -vE '^~/[^[:space:]*]+$' | grep . || :)"
if [ -n "$_bad" ]; then
  printf '%s\n' "$_bad" | while IFS= read -r _r; do log_fail "main-folders.txt: not a home-relative path without a glob: $_r"; done
  log_fix "edit contracts/main-folders.txt (format: its own header)"; exit 1
fi
[ -n "$FOLDERS" ] || { log_fail "no main folder rows: contracts/main-folders.txt is missing or empty"; log_nofix "contracts/main-folders.txt"; exit 1; }
ROWS="$(printf '%s\n' "$FOLDERS" | sed 's|.*|Edit(&/**)|')"
RJ="$(printf '%s\n' "$ROWS" | jq -R . | jq -s .)"
if [ "$MODE" = rows ]; then printf '%s\n' "$ROWS"; exit 0; fi

CUR='{}'
if [ -f "$FILE" ]; then
  CUR="$(cat "$FILE")"
  if ! printf '%s' "$CUR" | jq -e 'type == "object"' >/dev/null 2>&1; then
    [ "$MODE" != missing ] || exit 3
    log_fail "$FILE is not a JSON object; not touching it"; log_nofix "fix or remove $FILE by hand"; exit 1
  fi
fi
if [ "$MODE" = missing ]; then
  printf '%s' "$CUR" | jq -r --argjson r "$RJ" '($r - (.permissions.deny // []))[]' 2>/dev/null || exit 3
  exit 0
fi
if [ "$MODE" = uninstall ]; then
  NEW="$(printf '%s' "$CUR" | jq --argjson r "$RJ" 'if .permissions.deny then .permissions.deny -= $r | if (.permissions.deny | length) == 0 then del(.permissions.deny) else . end else . end | if (.permissions // {}) == {} then del(.permissions) else . end')"
else
  NEW="$(printf '%s' "$CUR" | jq --argjson r "$RJ" '.permissions.deny = (((.permissions.deny // []) + $r) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end))')"
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
# Read back: "the folders are denied" closes on the file, not on the write having returned.
_miss="$(sh "$0" --missing 2>/dev/null | grep -c . || :)"
_want=0; [ "$MODE" = install ] || _want="$(printf '%s\n' "$ROWS" | grep -c .)"
[ "$_miss" = "$_want" ] || { log_fail "$FILE lacks $_miss rows after the write, want $_want"; log_nofix "inspect $FILE"; exit 1; }
log_ok "$MODE: $FILE holds $(printf '%s\n' "$ROWS" | grep -c .) Edit rows for the main folders"; log_end
