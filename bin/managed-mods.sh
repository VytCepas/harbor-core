#!/usr/bin/env sh
# MANAGED MODS LOCKDOWN (harbor#1022, #603 stage 0) — the root-owned managed-settings.json that refuses user mods.
#   sudo sh managed-mods.sh              write (merge into any existing managed file)
#   sh managed-mods.sh --dry-run         print the target path and the merged JSON, write nothing
#   sudo sh managed-mods.sh --uninstall  remove exactly the keys this wrote, keep the rest
#
# Holds only: allowManagedModsOnly (pluginConfigs["cc-plugin-sec-default@builtin"].options),
# disableSideloadFlags, and the root-owned marketplace directory registered in extraKnownMarketplaces.
# NEVER allowManagedHooksOnly: it would switch off the floor, which is still user-tier until #603 moves it.
# Target: macOS /Library/Application Support/ClaudeCode/, Linux and WSL /etc/claude-code/.
# HARBOR_MANAGED_SETTINGS moves the file (tests, no root); then the directory is its sibling harbor-mods.
# A session cannot run this: writing there needs root, by design.
set -eu
# Under sudo a user-writable dir on PATH would run its jq/mkdir/chown as root: pin it first.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init managed-mods
# As root the target is never caller-chosen: sudo -E or env_keep would otherwise let the variable
# aim a root write and chown anywhere. <uid> is a parameter so the test can decide without root.
managed_refuse_override() { # <uid> -> 1 and a FAIL when root is handed a path override
  [ "$1" -eq 0 ] && [ -n "${HARBOR_MANAGED_SETTINGS:-}" ] || return 0
  log_fail "HARBOR_MANAGED_SETTINGS is set under root: refusing to write a caller-chosen path"
  log_fix "sudo env -u HARBOR_MANAGED_SETTINGS sh $0"; return 1
}
# The write is read back (harbor#457): what is on disk must be the JSON this run meant to write, and an install's
# marketplace file must exist. Without it a write that landed nowhere exits 0, and a green exit with nothing installed
# is the vacuous pass step 07 of tests/install/stranger-ubuntu.sh asserts against from outside.
managed_verify() { # <mode> <file> <expected json> <marketplace dir> -> 0, or 1 and a FAIL naming what differs
  _mv_got="$(jq -S . "$2" 2>/dev/null)" || {
    log_fail "read-back: $2 is missing or not JSON after the write"; log_fix "sh $0 --dry-run"; return 1; }
  _mv_want="$(printf '%s' "$3" | jq -S .)"
  if [ "$_mv_got" != "$_mv_want" ]; then
    log_fail "read-back: $2 is not the JSON this run meant to write"; log_fix "sh $0 --dry-run"; return 1
  fi
  if [ "$1" = install ] && [ ! -f "$4/.claude-plugin/marketplace.json" ]; then
    log_fail "read-back: the marketplace file $4/.claude-plugin/marketplace.json is missing after the write"; log_fix "sh $0 --dry-run"; return 1
  fi
  return 0
}
[ "${MANAGED_MODS_LIB:-0}" = 1 ] && return 0
managed_refuse_override "$(id -u)" || exit 1
KEY='cc-plugin-sec-default@builtin'
MKT='harbor-mods'
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then
  FILE="$HARBOR_MANAGED_SETTINGS"
else
  case "$(uname -s)" in
    Darwin) FILE='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
    *) FILE='/etc/claude-code/managed-settings.json' ;;
  esac
fi
BASE="$(dirname -- "$FILE")"; MDIR="$BASE/$MKT"
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/managed-mods.sh --help"; exit 2 ;;
esac; done
command -v jq >/dev/null 2>&1 || { log_fail "jq not found on the pinned PATH ($PATH): /usr/bin/jq is expected"; log_nofix "install jq at /usr/bin or /usr/local/bin is not searched by design (harbor#902)"; exit 1; }

CUR='{}'
if [ -f "$FILE" ]; then
  CUR="$(cat "$FILE")"
  printf '%s' "$CUR" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || { log_fail "$FILE is not a JSON object; not touching it"; log_nofix "fix or remove $FILE by hand"; exit 1; }
fi
if [ "$MODE" = uninstall ]; then
  NEW="$(printf '%s' "$CUR" | jq --arg k "$KEY" --arg m "$MKT" '
    del(.disableSideloadFlags, .pluginConfigs[$k].options.allowManagedModsOnly, .extraKnownMarketplaces[$m])
    | if (.pluginConfigs[$k].options // null) == {} then del(.pluginConfigs[$k].options) else . end
    | if (.pluginConfigs[$k] // null) == {} then del(.pluginConfigs[$k]) else . end
    | if (.pluginConfigs // null) == {} then del(.pluginConfigs) else . end
    | if (.extraKnownMarketplaces // null) == {} then del(.extraKnownMarketplaces) else . end')"
else
  NEW="$(printf '%s' "$CUR" | jq --arg k "$KEY" --arg m "$MKT" --arg d "$MDIR" '
    .pluginConfigs[$k].options.allowManagedModsOnly = true
    | .disableSideloadFlags = true
    | .extraKnownMarketplaces[$m] = {source: {source: "directory", path: $d}}')"
fi
log_note "target: $FILE"
if [ "$MODE" = dry ]; then printf '%s\n' "$NEW"; log_note "dry run: nothing written"; exit 0; fi

if [ -z "${HARBOR_MANAGED_SETTINGS:-}" ] && [ "$(id -u)" -ne 0 ]; then
  log_fail "not root: this file is root-owned by design"; log_fix "sudo sh $0${MODE:+ }$([ "$MODE" = uninstall ] && echo --uninstall)"; exit 1
fi
mkdir -p "$BASE"
TMPF="$(mktemp "$BASE/.managed-settings.XXXXXX")"; trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$NEW" > "$TMPF"
if [ "$MODE" = install ]; then
  mkdir -p "$MDIR/.claude-plugin"
  [ -f "$MDIR/.claude-plugin/marketplace.json" ] || \
    printf '{"name":"%s","owner":{"name":"Harbor"},"plugins":[]}\n' "$MKT" > "$MDIR/.claude-plugin/marketplace.json"
fi
if [ "$(id -u)" -eq 0 ]; then
  grp=wheel; [ "$(uname -s)" = Darwin ] || grp=root
  chown root:"$grp" "$TMPF"; [ "$MODE" != install ] || chown -R root:"$grp" "$MDIR"
fi
chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"; trap - EXIT
managed_verify "$MODE" "$FILE" "$NEW" "$MDIR" || { log_end || :; exit 1; }
log_ok "$MODE: wrote $FILE, and read it back"; log_end
