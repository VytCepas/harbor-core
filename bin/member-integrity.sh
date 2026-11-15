#!/usr/bin/env sh
# member-integrity.sh (harbor#1278, F12) — is the floor on this laptop the one IT installed? B6 reads wiring from user settings, so a member box needs this instead.
#   sh member-integrity.sh hash     16 hex over the managed root and managed settings
#   sh member-integrity.sh check    exit 0 when that equals <managed root>/floor.pin, 1 when not
#
# The hash is of content and relative names only, so a stage and the real path agree, and a hash on /mnt/c agrees with one on ext4. floor.pin,
# core.commit, pin.serial, bin/.core-files and MEMORY/ are out: the updater and the ledger change them. core-source is out: IT adds it to steer the updater, which then
# refuses a floor failing this check. managed-settings.d is out too: other writers own it.
# check also refuses a group- or world-writable file, which no hash of content can see. HARBOR_MEMBER_ROOT and HARBOR_SCOPE_MANAGED_SETTINGS move what is read
# for the install's stage and for tests: never under root, and never from the real root, where a user `env` block could point check at a copy.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
log_init member-integrity
LOG_FD=2
SCOPE_SETTINGS="${HARBOR_SCOPE_MANAGED_SETTINGS:-}"
# Past the env, this reads no fact: an absent member.conf is the hash's to report, and the install hashes a stage.
hub_env_clean || :

ROOT="${HERE%/*}"
# W4: the managed roots. If scripts move, the new real path goes here too.
case "$ROOT" in
  '/Library/Application Support/ClaudeCode/harbor'|/etc/claude-code/harbor|'/mnt/c/Program Files/ClaudeCode/harbor') SCOPE_SETTINGS="" ;;
  *) if [ "$(id -u)" -ne 0 ]; then ROOT="${HARBOR_MEMBER_ROOT:-$ROOT}"; else SCOPE_SETTINGS=""; fi ;;
esac
# W4: the managed settings sit one above the root on every platform today.
SETTINGS="${SCOPE_SETTINGS:-${ROOT%/*}/managed-settings.json}"
PIN="$ROOT/floor.pin"

floor_hash() {
  [ -d "$ROOT/bin" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then _sum=sha256sum; else _sum='shasum -a 256'; fi
  (
    cd "$ROOT"
    {
      # shellcheck disable=SC2086 # $_sum is the command and its one flag
      find . -type f ! -path ./floor.pin ! -path ./core.commit ! -path ./core-source ! -path ./pin.serial ! -path ./bin/.core-files ! -path './MEMORY/*' -exec $_sum {} +
      find . -type l ! -path './MEMORY/*' -exec sh -c 'for l; do printf "link %s %s\n" "$(readlink "$l")" "$l"; done' sh {} +
      if [ -f "$SETTINGS" ]; then printf 'settings %s\n' "$(hub_sha256 < "$SETTINGS")"; else printf 'settings none\n'; fi
    } | LC_ALL=C sort | hub_sha256 | cut -c1-16
  )
}

# W4: drvfs reports every file writable, so this can't speak on /mnt/c; only a Windows admin can write there anyway.
loosened() {
  case "$ROOT" in /mnt/*) return 1 ;; esac
  [ -n "$(cd "$ROOT" && find . ! -type l ! -path './MEMORY' ! -path './MEMORY/*' \( -perm -020 -o -perm -002 \) -print | head -n 1)" ]
}

# floor.extra names what the install placed in bin beside contracts/member-files.txt (upterm). The hash is recomputed after an update, so it alone
# can't see one of them lost: check needs each to be there (N3).
extra_present() {
  [ -f "$ROOT/floor.extra" ] || return 0
  while IFS= read -r _x || [ -n "$_x" ]; do
    case "$_x" in ''|*/*|.*) return 1 ;; esac
    [ -f "$ROOT/bin/$_x" ] && [ ! -L "$ROOT/bin/$_x" ] || return 1
  done < "$ROOT/floor.extra"
}

case "${1:-}" in
  -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  hash) floor_hash ;;
  check)
    [ -r "$PIN" ] || exit 1
    IFS= read -r _want < "$PIN" || :
    _got="$(floor_hash)" || exit 1
    [ -n "$_got" ] && [ "$_got" = "${_want:-}" ] || exit 1
    extra_present || exit 1
    ! loosened || exit 1 ;;
  *) log_fail "unknown verb: ${1:-none}"; log_nofix "sh $0 --help"; log_end || :; exit 2 ;;
esac
exit 0
