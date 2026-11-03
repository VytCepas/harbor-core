#!/usr/bin/env sh
# standard-id-resolve.sh (harbor#957 item 10, #949) - the ONE reader that turns an old or printed id into its control.
#
#   sh standard-id-resolve.sh <id>...        one line per id: given TAB kind TAB current TAB control   (exit 1 when one is unknown)
#   sh standard-id-resolve.sh --incidents <file>   red on a `lint:` mechanism of the incident register that resolves to no control
#
# Three registers used to answer this on their own: the check-id rows of renames.tsv, the deprecated letter column of
# `lint-conventions.sh --ids`, and the `emitted` column of controls.tsv. An id is looked up in the order
#   control   it is a controls.tsv id                          current = the id
#   lint      it is a deprecated letter (D2, K1)               current = the rule id the letter became
#   rename    it is the old half of a check-id rename row      current = the new check id
#   emitted   it is what a control prints today (alert.probe, bash:cd-cfg-then-fetch)
# and the answer is always the controls.tsv row that owns it. A `lint:`, `check:` or `guard:` prefix on the given id is ignored.
# --root <dir> reads another tree (a fixture). Exit 0 all resolved, 1 one is not, 2 usage, 3 a register could not be read.
set -eu
case "${1:-}" in -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="$(CDPATH= cd -- "$SRC/.." && pwd)"
. "$SRC/library-log.sh"
log_init id-resolve
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2   # stdout is data
usage() { log_fail "$1"; log_fix "sh bin/standard-id-resolve.sh <id>...  |  --incidents [file]  |  --root <dir>"; log_end || :; exit 2; }
unchecked() { log_fail "unchecked - $1, so nothing was judged"; log_fix "$2"; log_end || :; exit 3; }

MODE=ids; INC=""; IDS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ -n "${2:-}" ] || usage "--root needs a directory"; ROOT="$2"; shift ;;
    --incidents) MODE=incidents; [ -n "${2:-}" ] || usage "--incidents needs the incident register"; INC="$2"; shift ;;
    -*) usage "unknown option $1" ;;
    *) IDS="$IDS
$1" ;;
  esac
  shift
done
[ "$MODE" = incidents ] || [ -n "$IDS" ] || usage "no id given"
CT="$ROOT/standards/naming/controls.tsv"; RN="$ROOT/standards/naming/renames.tsv"; LC="$ROOT/bin/lint-conventions.sh"
[ -f "$CT" ] || unchecked "no standards/naming/controls.tsv under $ROOT" "git checkout origin/main -- standards/naming/controls.tsv"
[ -f "$RN" ] || unchecked "no standards/naming/renames.tsv under $ROOT" "git checkout origin/main -- standards/naming/renames.tsv"
[ -f "$LC" ] || unchecked "no bin/lint-conventions.sh under $ROOT" "git checkout origin/main -- bin/lint-conventions.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM
# the three registers as one table: alias TAB kind TAB current TAB control, in lookup order
sh "$LC" --ids 2>/dev/null | awk -F'\t' 'NR > 1 && $2 != "-" && $2 != "" { print $2 "\tlint\t" $1 "\t" $1 }' > "$T/lint" \
  || unchecked "bin/lint-conventions.sh --ids failed" "sh bin/lint-conventions.sh --ids"
awk -F'\t' '/^#/ || $1 == "id" { next }
  { print $1 "\tcontrol\t" $1 "\t" $1 }' "$CT" > "$T/control"
awk -F'\t' '/^#/ || $1 == "id" || $12 == "-" || $12 == "" { next }
  { print $12 "\temitted\t" $12 "\t" $1 }' "$CT" > "$T/emitted"
# a check-id rename names the new id, and the new id is what a control prints: current stays the new id, control is its row
awk -F'\t' 'FNR == NR { if ($1 !~ /^#/ && $1 != "id" && $12 != "-") own[$12] = $1; next }
  $4 == "check-id" && $2 ~ /^check:/ && $3 ~ /^check:/ { o = substr($2, 7); n = substr($3, 7); if (n in own) print o "\trename\t" n "\t" own[n] }' "$CT" "$RN" > "$T/rename"
cat "$T/control" "$T/lint" "$T/rename" "$T/emitted" > "$T/table"
[ -s "$T/control" ] || unchecked "controls.tsv holds no control" "git checkout origin/main -- standards/naming/controls.tsv"

resolve() { # <given>: the table row that answers it, first in lookup order; empty when none does
  _k="${1#lint:}"; _k="${_k#check:}"; _k="${_k#guard:}"
  awk -F'\t' -v k="$_k" '$1 == k { print; exit }' "$T/table"
}

if [ "$MODE" = ids ]; then
  _bad=0
  printf '%s\n' "$IDS" | while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _r="$(resolve "$_g")"
    if [ -n "$_r" ]; then printf '%s\t%s\n' "$_g" "$(printf '%s' "$_r" | cut -f2-)"
    else printf '%s\tunknown\t-\t-\n' "$_g"; fi
  done > "$T/out"
  cat "$T/out"
  if grep -q '	unknown	' "$T/out"; then
    awk -F'\t' '$2 == "unknown" { print $1 }' "$T/out" | while IFS= read -r _g; do log_fail "$_g is no control id, deprecated letter, renamed check id or printed id"; done
    log_fix "sh bin/lint-conventions.sh --ids; awk -F'\\t' '\$12 == \"<id>\"' standards/naming/controls.tsv"
    log_end || :; exit 1
  fi
  exit 0
fi

# --incidents: the register names its lint mechanisms by the letter they had (lint:D2). Every one must resolve.
[ -f "$INC" ] || unchecked "no incident register at $INC" "name the register file: --incidents <file>"
awk -F'\t' '/^#/ || $1 == "incident" { next }
  { n = split($5, a, ","); for (i = 1; i <= n; i++) if (a[i] ~ /^lint:/) print $1 "\t" substr(a[i], 6) }' "$INC" > "$T/mech"
[ -s "$T/mech" ] || unchecked "$INC names no lint mechanism" "the register is read by column 5; check its header"
_n=0; _red=0
while IFS='	' read -r _inc _m; do
  _n=$((_n + 1))
  [ -n "$(resolve "$_m")" ] || { _red=$((_red + 1)); log_fail "$_inc names the lint mechanism $_m, which resolves to no control"; log_fix "name the rule id it became: sh bin/standard-id-resolve.sh <id>"; }
done < "$T/mech"
[ "$_red" -eq 0 ] && log_ok "$_n lint mechanisms, every one resolves to a control"
log_end || exit 1
