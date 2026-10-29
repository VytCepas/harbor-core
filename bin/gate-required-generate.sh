#!/usr/bin/env sh
# gate-required-generate.sh (harbor#1149, D-79) - the rows a local merge gate reads: core's contracts/required-checks.tsv
# (harbor's own checks and every repo whose name may be public) followed by the private layer's required-checks.tsv (the
# rows whose repo cannot be named in a public tree).
#
#   sh gate-required-generate.sh [--core FILE] [--private DIR]   the composed rows, on stdout
#   sh gate-required-generate.sh [--private DIR] --layer-revs    the commits of the layer's repo that touched its file, newest first
#   sh gate-required-generate.sh [--core FILE] [--private DIR] --private-rev SHA
#                                                                the sum with the layer's file as the layer's repo held it at SHA
#
# Both files are `repo<TAB>check name`, `#` lines and blank lines free, one row per required check. The private file is
# appended verbatim, so with no layer, or no file in it, or one holding no row, the output is core byte for byte. An
# overlay can add a check for any repo and cannot remove one core lists: a reader takes every row of a repo.
#
# The layer's file is NOT a protected path: core's needs the operator's approval to change, an edit to the layer's does not, and a
# reader sees it at once. So a row belongs there only when core cannot carry it, and a layer file that exists but cannot be read
# is a refusal, never "no rows" (which would drop every row it holds from a merge gate).
#
# A private file that cannot be composed refuses the whole read (exit 2, nothing on stdout): a row that is not two
# tab-separated fields, a repo that is not owner/name, an empty check name, a carriage return, or a file that exists and is
# not a readable file. Skipping the row would answer "this repo requires nothing" for a repo whose row is only mistyped, and a
# merge gate must not fail open on a typo.
# Readers: deploy-runtime-install.sh (the installed bin/required-checks.tsv), drift-install.sh (what that file is held to),
# gate-merge-check.sh and gate-pr-wait.sh (their default list, run from a checkout), gate-merge-stack.sh (harbor's rows, from a checkout).
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/library-log.sh"
log_init gate-required-generate
LOG_FD=2

CORE="$ROOT/contracts/required-checks.tsv"
PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
REV=""; LAYER_REVS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --core) [ $# -ge 2 ] || { log_fail "--core takes a file"; log_fix "sh $0 --core contracts/required-checks.tsv"; log_end || :; exit 2; }; CORE="$2"; shift 2 ;;
    --private) [ $# -ge 2 ] || { log_fail "--private takes a directory"; log_fix "sh $0 --private DIR"; log_end || :; exit 2; }; PRIV="$2"; shift 2 ;;
    --private-rev) [ $# -ge 2 ] || { log_fail "--private-rev takes a commit"; log_fix "sh $0 --layer-revs"; log_end || :; exit 2; }; REV="$2"; shift 2 ;;
    --layer-revs) LAYER_REVS=1; shift ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
    *) log_fail "unknown argument: $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
  esac
done
PRIV="${PRIV%/}"
if [ "$LAYER_REVS" = 1 ]; then git -C "$PRIV" log --format=%H -- required-checks.tsv 2>/dev/null || :; exit 0; fi
[ -f "$CORE" ] || { log_fail "no required-checks list at $CORE"; log_fix "sh $0 --core <path to required-checks.tsv>"; log_end || :; exit 2; }

OVL="$PRIV/required-checks.tsv"
FIXROWS="correct the private layer's required-checks.tsv (contracts/private-layer.md); its rows are repo<TAB>check name"
_refuse() { # <what is wrong with the layer's file> [fix]
  log_fail "$OVL $1"
  if [ $# -ge 2 ]; then log_fix "$2"; else log_fix "$FIXROWS"; fi
  log_end || :; exit 2
}
TMP=""; trap 'rm -f "$TMP"' EXIT INT TERM
if [ -n "$REV" ]; then
  case "$REV" in *[!0123456789abcdef]*|'') _refuse "--private-rev is not a commit id" ;; esac
  TMP="$(mktemp "${TMPDIR:-/tmp}/gate-required-rev.XXXXXX")" || { log_fail "could not make a temp file"; log_nofix "TMPDIR"; log_end || :; exit 2; }
  git -C "$PRIV" show "$REV:required-checks.tsv" > "$TMP" 2>/dev/null || _refuse "is not in the layer's repo at $REV"
  OVL="$TMP"
else
  # Absent is no layer file. One that exists and cannot be read is not: reading it as "no rows" would lower the gate silently.
  if [ -d "$PRIV" ] && [ ! -x "$PRIV" ]; then _refuse "cannot be reached: the layer's directory cannot be searched" "chmod u+x '$PRIV'"; fi
  if [ -e "$OVL" ] || [ -L "$OVL" ]; then [ -f "$OVL" ] || _refuse "exists and is not a file" "make '$OVL' a regular file, or remove it"; fi
fi
# A file with no row is not a source: 'scope install' may leave a header-only file, and an empty one adds nothing.
[ -f "$OVL" ] || { cat "$CORE"; exit 0; }
_g=0; grep -q '^[^#[:space:]]' "$OVL" 2>/dev/null || _g=$?
case "$_g" in 0) ;; 1) cat "$CORE"; exit 0 ;; *) _refuse "could not be read" "make '$OVL' readable (ls -l)" ;; esac

# Judged before a byte is printed, so a refusal leaves stdout empty.
_bad="$(awk -F'\t' '
  /\r/ { printf "line %d: a carriage return\n", FNR; next }
  /^[ \t]*#/ || /^[ \t]*$/ { next }
  NF != 2 { printf "line %d: expected repo TAB check name, got %d field(s)\n", FNR, NF; next }
  $1 !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/ { printf "line %d: the repo is not owner/name\n", FNR; next }
  $2 ~ /^[ \t]*$/ { printf "line %d: the check name is empty\n", FNR; next }' "$OVL")" || _bad="unreadable"
if [ -n "$_bad" ]; then
  while IFS= read -r _l; do log_fail "$OVL $_l"; done <<BAD
$_bad
BAD
  log_fix "$FIXROWS"
  log_end || :; exit 2
fi
cat "$CORE"
# core may lack its final newline; the overlay must not run into its last row
[ -z "$(tail -c 1 "$CORE")" ] || printf '\n'
cat "$OVL"
