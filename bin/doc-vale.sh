#!/usr/bin/env sh
# doc-vale.sh (harbor#978) — prose against the registry: legacy aliases, UK spelling, banned words, via Vale.
#
#   sh bin/doc-vale.sh <file.md>...    generate the Vale config (never committed) and run it on the files
#
#   exit  0 no error (warnings print) · 1 Vale found an error-level rule broken · 2 usage · 3 unchecked
# Without Vale on PATH this prints "verified NOTHING" and exits 3: a missing checker is never a pass.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
LOG_FD=2   # stdout stays the checker's own output
. "$HERE/log-lib.sh"
log_init doc-vale
ROOT="${HARBOR_ROOT:-$HERE/..}"
case "${1:-}" in ''|-h|--help) awk 'NR < 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$HERE/${0##*/}"; [ -n "${1:-}" ] && exit 0; exit 2 ;; esac
command -v vale >/dev/null 2>&1 || { log_fail "vale is not on PATH — verified NOTHING"; log_fix "$(pkg_hint vale)"; log_end || :; exit 3; }
sh "$HERE/lint-name.sh" --root "$ROOT" --gen vale >/dev/null 2>&1 || { log_fail "--gen vale failed — verified NOTHING"; log_fix "sh $HERE/lint-name.sh --gen vale"; log_end || :; exit 3; }
CFG="$(CDPATH='' cd -- "$ROOT" && pwd)/build/vale"
for f in "$@"; do
  case "$f" in /*) ;; *) f="$(pwd)/$f" ;; esac
  [ -f "$f" ] || { log_fail "no such file: $f"; log_fix "sh $0 <file.md>"; log_end || :; exit 2; }
  set -- "$@" "$f"; shift
done
cd "$CFG" && vale --config .vale.ini --no-wrap "$@"
