#!/usr/bin/env sh
# member-bootstrap.sh (harbor#1278) — the first step on a clean laptop, before any harbor exists on it. Copied there alone, run as root.
#   sudo sh member-bootstrap.sh --pin <commit> [--source <git url>] [--dir <path>] --user <member> --hub <owner/name> --login <login> --signers <file>
# Clones harbor-core, the public export, at the pinned commit, into a folder only root writes, then hands every other argument to member-install.sh.
# The pin is a harbor-core commit, the same value as `core.commit` in the hub policy (R25). Core is not on the laptop yet (R3), so until the clone
# exists this prints plain lines; library-log.sh comes with the clone and takes over from there.
set -eu
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
[ "$(id -u)" -ne 0 ] || { PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; }
umask 022   # the member reads this checkout, whatever IT's own umask is
SOURCE='https://github.com/VytCepas/harbor-core.git'
DIR=/opt/harbor-core
PIN=''

fail() { printf 'member-bootstrap: %s (%s)\n' "$1" "$2" >&2; exit "${3:-1}"; }

# Under root the checkout's location decides what root runs next, so no variable may move it; a test moves it with --dir and runs without root.
[ "$(id -u)" -ne 0 ] || [ -z "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ] \
  || fail 'HARBOR_SCOPE_MANAGED_SETTINGS is set under root: refusing a caller-chosen target' "sudo env -u HARBOR_SCOPE_MANAGED_SETTINGS sh $0"
[ "$(id -u)" -eq 0 ] || [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ] \
  || fail 'not root: this installs what only root may write' "sudo sh $0"

# Everything that isn't ours goes to the install, in order.
_n=$#
while [ "$_n" -gt 0 ]; do
  case "$1" in
    --pin|--source|--dir)
      [ "$_n" -ge 2 ] || fail "$1 needs a value" "sh $0 --help" 2
      case "$1" in --pin) PIN="$2" ;; --source) SOURCE="$2" ;; --dir) DIR="$2" ;; esac
      shift 2; _n=$((_n - 2)) ;;
    *) set -- "$@" "$1"; shift; _n=$((_n - 1)) ;;
  esac
done
case "$PIN" in *[!0123456789abcdef]*|'') fail "--pin wants a 40-hex commit, got '$PIN'" "sh $0 --help" 2 ;; esac
[ "${#PIN}" -eq 40 ] || fail "--pin wants a 40-hex commit, got '$PIN'" "sh $0 --help" 2

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then apt-get update -q && apt-get install -y -q --no-install-recommends git ca-certificates || fail 'could not install git' 'apt-get install -y git ca-certificates'
  elif command -v dnf >/dev/null 2>&1; then dnf install -y -q git ca-certificates || fail 'could not install git' 'dnf install -y git ca-certificates'
  else fail 'git is missing' 'on macOS: xcode-select --install'; fi
fi

[ ! -L "$DIR" ] || fail "$DIR is a symbolic link, and root would run what it points at" "rm '$DIR'"
if [ -d "$DIR/.git" ]; then
  # Root runs what is in here next, so a folder someone else owns is not reused.
  [ "$(id -u)" -ne 0 ] || [ "$(ls -ldn "$DIR" | awk '{ print $3 }')" = 0 ] || fail "$DIR is not owned by root" "move it aside, then run this again"
  git -C "$DIR" fetch --quiet origin || fail "could not fetch into $DIR" "git -C '$DIR' fetch origin"
else
  [ ! -e "$DIR" ] || fail "$DIR exists and is not a checkout" "move it aside, then run this again"
  git clone --quiet "$SOURCE" "$DIR" || fail "could not clone $SOURCE" "git clone '$SOURCE' '$DIR'"
fi
git -C "$DIR" checkout --quiet --force --detach "$PIN" 2>/dev/null \
  || fail "$PIN is not a commit of $SOURCE: an export must reach harbor-core before a pin can name it" "git -C '$DIR' log --oneline -3"
. "$DIR/bin/library-log.sh"
log_init member-bootstrap
if [ "$(git -C "$DIR" rev-parse HEAD)" != "$PIN" ]; then
  log_fail "$DIR is not at $PIN after the checkout"; log_fix "git -C '$DIR' status"; log_end || :; exit 1
fi
git -C "$DIR" clean -fdxq
chmod -R go-w "$DIR"
if [ ! -f "$DIR/bin/member-install.sh" ]; then
  log_fail "the commit $PIN has no bin/member-install.sh: it predates the member install"; log_nofix 'pin a later harbor-core commit'; log_end || :; exit 1
fi
log_ok "$DIR is at $PIN"
exec sh "$DIR/bin/member-install.sh" --pin "$PIN" "$@"
