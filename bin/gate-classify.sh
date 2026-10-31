#!/usr/bin/env sh
# gate-classify.sh (harbor#1018) — which of these paths may only the operator merge or deploy (ship contract §2)?
#
#   sh gate-classify.sh <repo-root> [path…]     the paths, or one per line on stdin
#
# Prints `PROTECTED TAB path TAB class` for each protected path and nothing for the rest. Exit 0 none is
# protected, 1 at least one is, 2 usage or a manifest naming an absent register. The register is the one
# <repo-root>/.agents/ship.conf names (default .agents/protected-paths.tsv); the register itself, the manifest and
# .github/ are protected in every repo whatever it says. Judge both paths of a rename. Read-only.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
LOG_FD=2   # stdout is the verdict
. "$HERE/library-log.sh"
. "$HERE/library-gate.sh"
log_init gate-classify
case "${1:-}" in
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') log_fail "a repo root is required"; log_fix "sh $0 <repo-root> [path…]"; log_end || :; exit 2 ;;
esac
[ -d "$1" ] || { log_fail "no directory: $1"; log_fix "sh $0 <repo-root> [path…]"; log_end || :; exit 2; }
ROOT="$1"; shift
GATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gate-classify.XXXXXX")"; trap 'rm -rf "$GATE_TMP"' EXIT
rc=0
if [ $# -gt 0 ]; then printf '%s\n' "$@" | gate_classify "$ROOT" || rc=$?
else gate_classify "$ROOT" || rc=$?; fi
exit "$rc"
