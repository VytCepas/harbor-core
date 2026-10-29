#!/usr/bin/env sh
# policy-resolve.sh (harbor#957, #1001) — one config order: flag, then env, then repo config, then user config, then default.
#   sh bin/policy-resolve.sh <key> [--flag V] [--env VAR] [--repo FILE] [--user FILE] [--default V]
# The first stdout line is the value, then a `note: source:` line (flag|env|repo|user|default). A config file is `key=value` lines.
# Exit 0 resolved, 1 no source holds the key and no default, 2 usage. The order is the contract; CLIs call this or match its fixture.
set -u
. "$(dirname -- "$0")/library-log.sh"
fail() { log_fail "$1"; log_fix "$2"; log_end >/dev/null || :; exit "$3"; }
case "${1:-}" in -h|--help) sed -n 2,6p "$0"; exit 0 ;; esac
key="${1:-}"; [ -n "$key" ] || fail "needs a key" "sh $0 <key> [--flag V] [--env VAR] [--repo FILE] [--user FILE] [--default V]" 2
shift
flag=""; envv=""; repo=""; user=""; dflt=""; have_d=0; have_f=0
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || fail "$1 needs a value" "sh $0 --help" 2
  case "$1" in
    --flag) flag="$2"; have_f=1 ;;
    --env) envv="$2" ;;
    --repo) repo="$2" ;;
    --user) user="$2" ;;
    --default) dflt="$2"; have_d=1 ;;
    *) fail "unknown option $1" "sh $0 --help" 2 ;;
  esac
  shift 2
done
# value of key in a key=value file: the last line wins; empty and absent are the same (no source)
fileval() { [ -f "$1" ] || return 0; awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); v = $0 } END { print v }' "$1"; }
out() { printf '%s\n' "$1"; log_note "source: $2"; log_end >/dev/null || :; exit 0; }
[ "$have_f" = 1 ] && [ -n "$flag" ] && out "$flag" flag
if [ -n "$envv" ]; then ev="$(printenv "$envv" 2>/dev/null)"; [ -n "$ev" ] && out "$ev" env; fi
[ -n "$repo" ] && { v="$(fileval "$repo")"; [ -n "$v" ] && out "$v" repo; }
[ -n "$user" ] && { v="$(fileval "$user")"; [ -n "$v" ] && out "$v" user; }
[ "$have_d" = 1 ] && out "$dflt" default
fail "no source holds $key" "give --default, or set it in a repo or user config" 1
