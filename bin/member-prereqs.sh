#!/usr/bin/env sh
# member-prereqs.sh (harbor#1278) — the one thing a member may run as root: installs the fixed list in member-prereqs.txt beside it, asking nothing.
#   sudo -n /bin/sh <managed root>/bin/member-prereqs.sh
# Exit 0 installed, 1 refused or failed, 2 given an argument. It takes none: an argument is how a root helper grows a second purpose. --help prints this
# and installs nothing, and the sudoers rule allows no argument at all, so root never reaches even that.
# member-install.sh writes the sudoers rule, member-session.sh calls this at SessionStart when a probe in the list finds nothing.
# W5: root runs this file, so it is only as strong as its folder. On WSL that is /mnt/c, where a Windows ACL decides, not the owner shown here.
set -eu
if [ $# -eq 1 ]; then case "$1" in --help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac; fi
# Under root a user-writable dir on PATH would run its tools as root. A test needs its stubs, and has no privilege to protect.
[ "$(id -u)" -ne 0 ] || { PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH; }
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd -P)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init member-prereqs
refuse() { log_fail "$1"; log_nofix 'docs/how-to/member-install.md'; log_end || :; exit "${2:-1}"; }

[ $# -eq 0 ] || refuse 'this takes no arguments: it installs the list beside it and nothing else' 2
[ -f "$HERE/harbor-member-mode" ] || refuse "no harbor-member-mode beside $HERE/member-prereqs.sh: not a managed root"
[ -f "$HERE/member-prereqs.txt" ] || refuse "no member-prereqs.txt beside this script"
# A list that changed since IT installed it is not the fixed list, so nothing is installed from it.
sh "$HERE/member-integrity.sh" check >/dev/null 2>&1 || refuse 'the floor fails member-integrity.sh check, so its list can not be trusted'

if command -v apt-get >/dev/null 2>&1; then _col=2
elif command -v dnf >/dev/null 2>&1; then _col=3
else refuse 'no apt-get or dnf here: on this box the prerequisites are IT'"'"'s'; fi
_pkgs="$(awk -v c="$_col" '/^[[:space:]]*#/ || !NF { next } NF != 3 { print "?"; next } $c != "-" { print $c }' "$HERE/member-prereqs.txt")"
[ -n "$_pkgs" ] || refuse 'member-prereqs.txt names no package'
# Only plain names: an option, a path, a version or a .deb is something beyond the list, and the whole run stops on it.
# The alphabet is spelled out: under a UTF-8 locale a-z can collate capitals in.
for _p in $_pkgs; do
  case "$_p" in -*|*[!abcdefghijklmnopqrstuvwxyz0123456789+.-]*) refuse "member-prereqs.txt holds '$_p', not a package name" ;; esac
done

# shellcheck disable=SC2086 # one package per word, each checked above
set -- $_pkgs
# env -i: nothing the caller set reaches the package manager, whatever sudo was told to keep.
if [ "$_col" = 2 ]; then
  env -i PATH="$PATH" HOME=/root DEBIAN_FRONTEND=noninteractive apt-get update -q >&2 || refuse 'apt-get update failed'
  env -i PATH="$PATH" HOME=/root DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "$@" >&2 || refuse 'apt-get install failed'
else
  env -i PATH="$PATH" HOME=/root dnf install -y -q "$@" >&2 || refuse 'dnf install failed'
fi
log_ok "installed the list: $*"
log_end
