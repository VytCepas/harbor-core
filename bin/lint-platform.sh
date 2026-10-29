#!/usr/bin/env sh
# lint-platform.sh (harbor#618) — a macOS-only call in bin/ is ported, declared or in a helper, never bare.
#
#   sh lint-platform.sh [<dir>]   one `<file>: <tool>` line per bare call in <dir> (default: this checkout's bin/); exit 1 if any
#   sh lint-platform.sh --called [<dir>]   the files whose code holds any call at all (the derive's non-vacuity)
#
# A file that calls launchctl, plutil, ditto, caffeinate, pbcopy, pbpaste, osascript, notifyutil, pmset, scutil, dscl,
# xattr or brew (comments stripped, extensionless files included) names a Linux counterpart for each in its own code
# (systemctl, a clipboard tool, pkg_hint, useradd), or carries `# platform: macOS-only — <reason>` in its first 40 lines.
# osascript has no counterpart: a notification goes through bin/alert-lib.sh, the one helper allowed to call it.
# Guards and the lint hold a call as a pattern they refuse or match, so they are not judged. Run by lint.platform-calls.
# The `<file>: <tool>` lines are data on stdout; the verdict is log-lib's, on stderr. Exit 0 clean, 1 a bare call, 2 usage.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/log-lib.sh"
log_init lint-platform
LOG_FD=2
CALLS='launchctl|plutil|ditto|caffeinate|pbcopy|pbpaste|osascript|notifyutil|pmset|scutil|dscl|xattr|brew'
CLIP='wl-paste|wl-copy|xclip|xsel|powershell\.exe|clip\.exe'

# Files that hold a call as DATA the floor refuses or matches, with no call to port: the guards' rule patterns,
# the lint's own rules, this file, and the wrapper-name list the command normalizer reads. A new name is a decision.
exempt() { case "$1" in guard-*.sh|lint-conventions.sh|lint-platform.sh|floor-normalize.awk) return 0 ;; esac; return 1; }
# The helpers: the one place each call is allowed to live (harbor#618).
helper() { case "$1" in alert-lib.sh) return 0 ;; esac; return 1; }
# doctor.sh is macOS-only for its optional `launchctl` probe, declared here and not in its header: lint LOG1's
# ratchet makes any edit to it convert the file onto log-lib, a rewrite of its table output. Move the line into its header then.
declared_here() { case "$1" in doctor.sh) return 0 ;; esac; return 1; }
counter() { case "$1" in launchctl) echo 'systemctl' ;; pbcopy|pbpaste) echo "$CLIP" ;; brew) echo 'pkg_hint|apt-get|= Darwin' ;; dscl) echo 'useradd' ;; *) echo '' ;; esac; }

uncovered() { # <dir>
  for _f in "$1"/*; do
    [ -f "$_f" ] || continue
    _n="${_f##*/}"; exempt "$_n" && continue
    helper "$_n" && continue
    declared_here "$_n" && continue
    _code="$(sed -e 's/^[[:space:]]*#.*//' "$_f")"
    _tools="$(printf '%s\n' "$_code" | grep -oE "(^|[^[:alnum:]_.-])($CALLS)([^[:alnum:]_-]|\$)" | grep -oE "$CALLS" | sort -u)" || :
    [ -n "$_tools" ] || continue
    head -n 40 "$_f" | grep -qE '^# platform: macOS-only — .+' && continue
    for _t in $_tools; do
      _c="$(counter "$_t")"
      [ -z "$_c" ] || ! printf '%s\n' "$_code" | grep -qE "(^|[^[:alnum:]_-])($_c)([^[:alnum:]_-]|\$)" || continue
      printf '%s: %s\n' "$_n" "$_t"
    done
  done
}

called() { # <dir>
  for _f in "$1"/*; do
    [ -f "$_f" ] || continue
    sed -e 's/^[[:space:]]*#.*//' "$_f" | grep -qE "(^|[^[:alnum:]_.-])($CALLS)([^[:alnum:]_-]|\$)" && printf '%s\n' "${_f##*/}"
  done
  return 0
}

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --called) called "${2:-$HERE}"; exit 0 ;;
  -*) log_fail "unknown option '$1'"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
DIR="${1:-$HERE}"
[ -d "$DIR" ] || { log_fail "no directory $DIR, so nothing was judged"; log_nofix "bin/lint-platform.sh"; log_end || :; exit 2; }
_out="$(uncovered "$DIR")"
if [ -z "$_out" ]; then log_ok "no bare macOS-only call in $DIR"; log_end || :; exit 0; fi
printf '%s\n' "$_out"
log_fail "$(printf '%s\n' "$_out" | wc -l | tr -d ' ') bare macOS-only call(s)"
log_fix "port each beside its Linux counterpart, call bin/alert-lib.sh for a notification, or declare it in the header"
log_end || :; exit 1
