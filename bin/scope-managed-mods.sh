#!/usr/bin/env sh
# MANAGED MODS LOCKDOWN (harbor#1022, #603 stage 0) — the root-owned managed-settings.json that refuses user mods.
#   sudo sh scope-managed-mods.sh              write (merge into any existing managed file)
#   sh scope-managed-mods.sh --dry-run         print the target path and the merged JSON, write nothing
#   sudo sh scope-managed-mods.sh --uninstall  remove exactly the keys this wrote, keep the rest
#
# Holds only: allowManagedModsOnly (pluginConfigs["cc-plugin-sec-default@builtin"].options),
# disableSideloadFlags, the root-owned marketplace directory registered in extraKnownMarketplaces, and
# enabledPlugins["<mod>@harbor-mods"] for each mods/<mod>/ of this checkout, copied into that directory (harbor#1480).
# Under allowManagedModsOnly that is the one seat a mod loads from: a user-scope install is refused, and
# CLAUDE_CODE_PLUGIN_DIRS is a sideload. Run it again after a mod changes; deploy.sh names a stale copy.
# NEVER allowManagedHooksOnly: it would switch off the floor, which is still user-tier until #603 moves it.
# Target: macOS /Library/Application Support/ClaudeCode/, Linux and WSL /etc/claude-code/.
# HARBOR_SCOPE_MANAGED_SETTINGS moves the file (tests, no root); then the directory is its sibling harbor-mods.
# A session cannot run this: writing there needs root, by design.
set -eu
# Under sudo a user-writable dir on PATH would run its jq/mkdir/chown as root: pin it first.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
log_init managed-mods
# As root the target is never caller-chosen: sudo -E or env_keep would otherwise let the variable
# aim a root write and chown anywhere. <uid> is a parameter so the test can decide without root.
managed_refuse_override() { # <uid> -> 1 and a FAIL when root is handed a path override
  [ "$1" -eq 0 ] && [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ] || return 0
  log_fail "HARBOR_SCOPE_MANAGED_SETTINGS (or HARBOR_MANAGED_SETTINGS) is set under root: refusing to write a caller-chosen path"
  log_fix "sudo env -u HARBOR_SCOPE_MANAGED_SETTINGS -u HARBOR_MANAGED_SETTINGS sh $0"; return 1
}
# The write is read back (harbor#457): what is on disk must be the JSON this run meant to write, and an install's
# marketplace file must exist. Without it a write that landed nowhere exits 0, and a green exit with nothing installed
# is the vacuous pass step 07 of tests/install/stranger-ubuntu.sh asserts against from outside.
managed_verify() { # <mode> <file> <expected json> <marketplace dir> [<mods dir>] -> 0, or 1 and a FAIL naming what differs
  _mv_got="$(jq -S . "$2" 2>/dev/null)" || {
    log_fail "read-back: $2 is missing or not JSON after the write"; log_fix "sh $0 --dry-run"; return 1; }
  _mv_want="$(printf '%s' "$3" | jq -S .)"
  if [ "$_mv_got" != "$_mv_want" ]; then
    log_fail "read-back: $2 is not the JSON this run meant to write"; log_fix "sh $0 --dry-run"; return 1
  fi
  if [ "$1" = install ] && [ ! -f "$4/.claude-plugin/marketplace.json" ]; then
    log_fail "read-back: the marketplace file $4/.claude-plugin/marketplace.json is missing after the write"; log_fix "sh $0 --dry-run"; return 1
  fi
  if [ "$1" = install ] && [ -n "${5:-}" ] && [ -n "$(managed_mods_drift "$5" "$4")" ]; then
    log_fail "read-back: a mod in $4 is not the copy of $5: $(managed_mods_drift "$5" "$4" | tr '\n' ' ')"; log_fix "sh $0 --dry-run"; return 1
  fi
  return 0
}
MKT='harbor-mods'
# The managed file and its marketplace directory, the sibling harbor-mods (FILE, BASE, MDIR).
managed_target() {
  if [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ]; then
    FILE="${HARBOR_SCOPE_MANAGED_SETTINGS:-$HARBOR_MANAGED_SETTINGS}"
  else
    case "$(uname -s)" in
      Darwin) FILE='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
      *) FILE='/etc/claude-code/managed-settings.json' ;;
    esac
  fi
  BASE="$(dirname -- "$FILE")"; MDIR="$BASE/$MKT"
}
# THE MODS (harbor#1480). A mod is mods/<name>/ whose .claude-plugin/plugin.json names it <name>, [a-z0-9-] only.
managed_mods_list() { # <mods dir> -> one name per line
  [ -d "$1" ] || return 0
  for _mm in "$1"/*/.claude-plugin/plugin.json; do
    [ -f "$_mm" ] || continue
    _mn="$(jq -r '.name // empty' "$_mm" 2>/dev/null)" || continue
    _md="${_mm%/.claude-plugin/plugin.json}"; _md="${_md##*/}"
    case "$_mn" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) continue ;; esac
    [ "$_mn" != "$_md" ] || printf '%s\n' "$_mn"
  done
}
managed_mods_sums() { # <mod dir> -> a checksum line per file, the engine's own .claude-plugin/types/ left out
  ( cd "$1" && find . -type f ! -path './.claude-plugin/types/*' | LC_ALL=C sort | while IFS= read -r _f; do
      printf '%s %s\n' "$(cksum < "$_f" | awk '{ print $1 "-" $2 }')" "$_f"; done )
}
managed_mods_drift() { # <mods dir> <marketplace dir> -> "<name> missing" or "<name> differs" per mod not installed as it is here
  for _n in $(managed_mods_list "$1"); do
    if [ ! -d "$2/$_n" ]; then printf '%s missing\n' "$_n"
    elif [ "$(managed_mods_sums "$1/$_n")" != "$(managed_mods_sums "$2/$_n")" ]; then printf '%s differs\n' "$_n"; fi
  done
}
# What deploy reports (harbor#1480): `ok`, or one line per mod not live. Silence is never ok: mods it could not list read `unjudged`.
managed_mods_state() { # <mods dir>, after managed_target
  _ms_w="$(find "$1" -mindepth 3 -maxdepth 3 -path '*/.claude-plugin/plugin.json' 2>/dev/null | wc -l | tr -d ' ')"
  _ms_g="$(managed_mods_list "$1" | wc -l | tr -d ' ')"
  [ "$_ms_w" = "$_ms_g" ] || { printf 'unjudged: %s of %s mods listed\n' "$_ms_g" "$_ms_w"; return 0; }
  _ms_o="$(managed_mods_drift "$1" "$MDIR"
    for _n in $(managed_mods_list "$1"); do
      jq -e --arg k "$_n@$MKT" '.enabledPlugins[$k] == true' "$FILE" >/dev/null 2>&1 || printf '%s not enabled\n' "$_n"
    done)"
  printf '%s\n' "${_ms_o:-ok}"
}
[ "${MANAGED_MODS_LIB:-0}" = 1 ] && return 0
managed_refuse_override "$(id -u)" || exit 1
KEY='cc-plugin-sec-default@builtin'
managed_target
MODS="$(CDPATH='' cd -- "$HERE/.." && pwd)/mods"
NAMES="$(managed_mods_list "$MODS")"
NAMESJ="$(printf '%s\n' "$NAMES" | jq -R . | jq -s -c 'map(select(length > 0))')"
MODE=install
for a in "$@"; do case "$a" in
  --dry-run) MODE=dry ;; --uninstall) MODE=uninstall ;;
  -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
  *) log_fail "unknown argument $a"; log_nofix "sh bin/scope-managed-mods.sh --help"; exit 2 ;;
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
    | (if .enabledPlugins then .enabledPlugins |= with_entries(select(.key | endswith("@" + $m) | not)) else . end)
    | if (.enabledPlugins // null) == {} then del(.enabledPlugins) else . end
    | if (.pluginConfigs[$k].options // null) == {} then del(.pluginConfigs[$k].options) else . end
    | if (.pluginConfigs[$k] // null) == {} then del(.pluginConfigs[$k]) else . end
    | if (.pluginConfigs // null) == {} then del(.pluginConfigs) else . end
    | if (.extraKnownMarketplaces // null) == {} then del(.extraKnownMarketplaces) else . end')"
else
  # Every mod of this checkout enabled, and only those: a mod removed from mods/ is no longer enabled.
  NEW="$(printf '%s' "$CUR" | jq --arg k "$KEY" --arg m "$MKT" --arg d "$MDIR" --argjson names "$NAMESJ" '
    .pluginConfigs[$k].options.allowManagedModsOnly = true
    | .disableSideloadFlags = true
    | .extraKnownMarketplaces[$m] = {source: {source: "directory", path: $d}}
    | .enabledPlugins = ((.enabledPlugins // {}) | with_entries(select(.key | endswith("@" + $m) | not)))
        + ($names | map({key: (. + "@" + $m), value: true}) | from_entries)
    | if .enabledPlugins == {} then del(.enabledPlugins) else . end')"
fi
log_note "target: $FILE"
[ "$MODE" = uninstall ] || log_note "mods: $(printf '%s ' $NAMES)(from $MODS, copied into $MDIR)"
if [ "$MODE" = dry ]; then printf '%s\n' "$NEW"; log_note "dry run: nothing written"; exit 0; fi

if [ -z "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ] && [ "$(id -u)" -ne 0 ]; then
  log_fail "not root: this file is root-owned by design"; log_fix "sudo sh $0${MODE:+ }$([ "$MODE" = uninstall ] && echo --uninstall)"; exit 1
fi
mkdir -p "$BASE"
TMPF="$(mktemp "$BASE/.managed-settings.XXXXXX")"; trap 'rm -f "$TMPF"' EXIT
printf '%s\n' "$NEW" > "$TMPF"
if [ "$MODE" = install ]; then
  mkdir -p "$MDIR/.claude-plugin"
  # Each mod is copied whole, then swapped in, before the settings that enable it are written. A link could point a
  # root-owned mod at a file anyone may edit, so a mod holding one is refused.
  for _n in $NAMES; do
    if [ -n "$(find "$MODS/$_n" -type l | head -1)" ]; then
      log_fail "mods/$_n holds a symbolic link: not copied"; log_nofix "replace the link with the file in mods/$_n"; exit 1
    fi
    rm -rf "$MDIR/.$_n.new"; cp -R "$MODS/$_n" "$MDIR/.$_n.new"; rm -rf "$MDIR/.$_n.new/.claude-plugin/types"
    rm -rf "${MDIR:?}/$_n"; mv "$MDIR/.$_n.new" "$MDIR/$_n"
  done
  for _d in "$MDIR"/*/; do  # a mod no longer in mods/ leaves the marketplace too
    [ -f "$_d.claude-plugin/plugin.json" ] || continue
    _d="${_d%/}"; printf '%s\n' "$NAMES" | grep -qxF -- "${_d##*/}" || rm -rf "$_d"
  done
  printf '%s' "$NAMESJ" | jq -c --arg m "$MKT" '{name: $m, owner: {name: "Harbor"}, plugins: map({name: ., source: ("./" + .)})}' \
    > "$MDIR/.claude-plugin/marketplace.json"
fi
if [ "$(id -u)" -eq 0 ]; then
  grp=wheel; [ "$(uname -s)" = Darwin ] || grp=root
  chown root:"$grp" "$TMPF"; [ "$MODE" != install ] || chown -R root:"$grp" "$MDIR"
fi
chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"; trap - EXIT
managed_verify "$MODE" "$FILE" "$NEW" "$MDIR" "$MODS" || { log_end || :; exit 1; }
log_ok "$MODE: wrote $FILE, and read it back"; log_end
