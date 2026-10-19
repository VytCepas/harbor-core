#!/usr/bin/env sh
# deliver-drive (harbor#422) — copy a filed deliverable into Google Drive and print
# the link a person can actually open.
#
#     sh bin/deliver-drive.sh ~/Deliverables/2026-09-04-example-audit --shared
#     sh bin/deliver-drive.sh ~/Deliverables/2026-09-04-draft     --private
#     sh bin/deliver-drive.sh --self-test
#
# platform: macOS-only — Drive for Desktop mounts under ~/Library/CloudStorage and stamps the item id as the `xattr` com.google.drivefs.item-id; Google ships no such client for Linux (harbor#618).
#
# WHY THIS EXISTS AND NOT AN UPLOAD API. Google Drive is already a filesystem on this
# box — Drive for Desktop mounts it — so delivery is `cp`, and every OAuth token, API
# client and MCP round-trip in the obvious design is machinery for a problem that does
# not exist here.
#
# WHY THREE DESTINATIONS AND NOT A SHARING FLAG. Drive permissions inherit down a tree,
# so each folder is shared ONCE and every artefact placed inside is reachable by the same
# people for ever, with no per-file step. Per-file sharing is how a link ends up either
# wider than intended or never granted at all — this script cannot grant permission and
# deliberately does not try. Where a file LANDS is the whole decision.
#
# `_confidential` is a tier and not an exception because the alternative was tested and
# failed immediately: the first artefact filed here was an audit whose own findings
# include a client dashboard shared with three personal webmail addresses and editable by
# anyone in the domain with the link, and it also documents an endpoint that needs no
# secret to write conversions into live ad accounts. Two tiers would have put that in
# front of everyone or forced a per-file exception, and an exception is the thing this
# design exists to avoid.
#
# THE LINK LIVES IN AN EXTENDED ATTRIBUTE whose name ends `#S`. Without that suffix
# `xattr -p com.google.drivefs.item-id` returns empty and reads as "no such feature".
# It appears only after Drive finishes uploading, so this waits rather than reporting
# a missing id as a failure.
set -eu

# The link is this tool's stdout, so the log is log-lib's on stderr (CONTRACTS/logging.md).
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init deliver-drive; LOG_FD=2

# THE MOUNT IS FOUND, NOT ASSUMED. Drive for Desktop owns the real path under
# ~/Library/CloudStorage and may make its own ~/Google Drive alias; a second alias added
# by hand is a duplicate that drifts the day one of them is renamed. So look for the
# real thing first and treat any alias as a convenience, never as the contract.
find_mount() {
  [ -n "${HARBOR_DRIVE_MOUNT:-}" ] && { printf '%s' "$HARBOR_DRIVE_MOUNT"; return 0; }
  for _m in "$HOME"/Library/CloudStorage/GoogleDrive-*; do
    [ -d "$_m/My Drive" ] && { printf '%s' "$_m"; return 0; }
  done
  for _m in "$HOME/gdrive" "$HOME/Google Drive"; do
    [ -d "$_m/My Drive" ] && { printf '%s' "$_m"; return 0; }
  done
  return 1
}
MOUNT="$(find_mount || true)"
ROOT="$MOUNT/My Drive/Artefacts"
IDATTR='com.google.drivefs.item-id#S'
WAIT="${HARBOR_DRIVE_WAIT:-30}"

usage() {
  cat <<'USAGE'
deliver-drive — copy a filed deliverable into Drive, print its link

  sh bin/deliver-drive.sh <dir> --shared    everyone _shared is shared with
  sh bin/deliver-drive.sh <dir> --private   not shared — a waiting room, not a vault
  sh bin/deliver-drive.sh --self-test

The directory must be a ~/Deliverables/<YYYY-MM-DD>-<slug>/ folder; the Drive copy
keeps that exact name so the two can be compared without translation.

Environment:
  HARBOR_DRIVE_MOUNT   override; otherwise the CloudStorage mount is found
  HARBOR_DRIVE_WAIT    seconds to wait for the Drive id (default 30)
USAGE
}

# The id is the deliverable. A copy nobody can link to has not been delivered, so an
# absent id is a real failure and not a cosmetic one — but it is usually just slow.
drive_id() {
  _p="$1"; _n=0
  while [ "$_n" -lt "$WAIT" ]; do
    _id="$(xattr -p "$IDATTR" "$_p" 2>/dev/null | tr -d ' \n' || true)"
    [ -n "$_id" ] && { printf '%s' "$_id"; return 0; }
    _n=$((_n + 1)); sleep 1
  done
  return 1
}

self_test() {
  log_head "self-test"
  _t() { # <label> <got> <want>
    if [ "$2" = "$3" ]; then log_ok "$1"
    else log_fail "$1 (got $2, want $3)"; log_fix "sh $0 --self-test, then read the case in bin/deliver-drive.sh"; fi
  }
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"

  # A deliverable is a DATED FOLDER. Accepting a bare file would put a loose document
  # in Drive under a name that says nothing, which is the filing failure this repo
  # already has a guard for.
  set +e
  ( HARBOR_DRIVE_MOUNT="$_tmp" sh "$0" "$_tmp/not-a-deliverable" --shared ) >/dev/null 2>&1
  _t "an undated folder name is refused" "$?" "2"

  printf 'x' > "$_tmp/plain.html"
  ( HARBOR_DRIVE_MOUNT="$_tmp" sh "$0" "$_tmp/plain.html" --shared ) >/dev/null 2>&1
  _t "a bare file is refused" "$?" "2"

  mkdir -p "$_tmp/2026-09-04-probe"
  ( HARBOR_DRIVE_MOUNT="$_tmp" sh "$0" "$_tmp/2026-09-04-probe" ) >/dev/null 2>&1
  _t "no destination flag is refused" "$?" "2"

  ( HARBOR_DRIVE_MOUNT="$_tmp" sh "$0" "$_tmp/2026-09-04-probe" --team ) >/dev/null 2>&1
  _t "a removed flag (--team) is refused" "$?" "2"

  # A missing mount must not be reported as a missing deliverable.
  ( HARBOR_DRIVE_MOUNT="$_tmp/no-such-mount" sh "$0" "$_tmp/2026-09-04-probe" --shared ) \
    >/dev/null 2>&1
  _t "an absent Drive mount is refused" "$?" "3"

  rm -rf "$_tmp"
  log_end
}

case "${1:-}" in
  ''|-h|--help) usage; exit 0 ;;
  --self-test)  self_test; exit $? ;;
esac

SRC="${1%/}"
case "${2:-}" in
  --shared)  DEST_ROOT="$ROOT/_shared" ;;
  --private) DEST_ROOT="$ROOT/_private" ;;
  *) log_fail "say --shared or --private: where it lands IS the sharing decision, so there is no default"
     log_fix "sh $0 ${SRC:-<dir>} --shared    # or --private"
     log_end || :; exit 2 ;;
esac

[ -d "$SRC" ] || {
  log_fail "$SRC is not a directory: a deliverable is a dated FOLDER"
  log_fix "sh $0 ~/Deliverables/<YYYY-MM-DD>-<slug> ${2:-}"
  log_end || :; exit 2
}
case "${SRC##*/}" in
  20[0-9][0-9]-[01][0-9]-[0-3][0-9]-*) ;;
  *) log_fail "${SRC##*/} is not <YYYY-MM-DD>-<slug>: the Drive copy keeps this name"
     log_fix "mv \"$SRC\" \"${SRC%/*}/$(date +%Y-%m-%d)-${SRC##*/}\""
     log_end || :; exit 2 ;;
esac
[ -d "$ROOT" ] || {
  log_fail "no Drive mount at $ROOT: is Drive for Desktop running and signed in?"
  log_fix "open -a 'Google Drive'    # or set HARBOR_DRIVE_MOUNT"
  log_end || :; exit 3
}

DEST="$DEST_ROOT/${SRC##*/}"
mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"  # `src/.`: the contents, on BSD and GNU cp alike; `src/` nests one level under GNU
log_ok "copied ${SRC##*/} -> ${DEST_ROOT##*/}"

if ID="$(drive_id "$DEST")"; then
  log_end || :
  printf 'https://drive.google.com/drive/folders/%s\n' "$ID"
else
  log_fail "copied, but Drive has not assigned an id after ${WAIT}s"
  log_fix "xattr -p '$IDATTR' \"$DEST\""
  log_end || :; exit 4
fi
