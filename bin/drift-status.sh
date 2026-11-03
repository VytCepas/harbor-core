#!/usr/bin/env sh
# drift-status.sh (harbor#1031 item 5, #949) - every drift check's `--status`, read through ONE parser.
#
#   sh drift-status.sh [--root DIR] [--only CHECK-ID]...   run each adopter's `--status`; print only what is off
#   sh drift-status.sh --list [--root DIR]                  the adopters, derived: one check id TAB script per line
#
# The consumers of the reconcile interface (the console, the batch report) read this output, never a check's own format.
# stdout is data, tab-separated, the delta and the ages and not the census:
#   <check> TAB new|standing TAB <key> TAB <desired> TAB <observed> TAB <delta> TAB <age>   a row not at its desired state
#   <check> TAB unchecked TAB <reason>      the check could not judge, or its report breaks contracts/reconcile.md
#   total TAB <adopters> TAB <drifted rows> TAB <unchecked adopters>                        closes every run
# Adopters are never listed: a check row of standards/naming/controls.tsv whose bin/<emitted id, each . a ->.sh answers
# `--status` (it calls status_init or takes the flag). Exit 0 all green, 1 a row is off, 2 usage, 3 an adopter could not
# judge and nothing else is off (never a green). A report that does not conform is an adopter that could not judge.
set -eu
case "${1:-}" in -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="$(CDPATH= cd -- "$SRC/.." && pwd)"
. "$SRC/library-log.sh"
log_init drift-status
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2   # stdout is data
usage() { log_fail "$1"; log_fix "sh bin/drift-status.sh [--root DIR] [--only CHECK-ID]...  |  --list"; log_end || :; exit 2; }

LIST=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ -n "${2:-}" ] || usage "--root needs a directory"; ROOT="$2"; shift ;;
    --only) [ -n "${2:-}" ] || usage "--only needs a check id"; ONLY="$ONLY
$2"; shift ;;
    --list) LIST=1 ;;
    *) usage "unknown argument $1" ;;
  esac
  shift
done
CT="$ROOT/standards/naming/controls.tsv"
unchecked() { log_fail "unchecked - $1, so nothing was judged"; log_fix "$2"; log_end || :; exit 3; }
[ -f "$CT" ] || unchecked "no $CT" "git checkout origin/main -- standards/naming/controls.tsv"

# The derivation tests/drift/reconcile/contract.test.sh audits: only a command word counts, never a comment or a string.
answers() { grep -v '^[[:space:]]*#' "$1" | grep -Eq -e '(^|[;&|({]|then|do)[[:space:]]*status_init[[:space:]]' -e '--status\)'; }
adopters() { # check id TAB script path
  awk -F'\t' '/^#/ || $1 == "id" { next } $3 == "check" && $12 != "-" { s = $12; gsub(/\./, "-", s); print $12 "\t" s }' "$CT" \
    | while IFS='	' read -r _id _s; do
        [ -f "$ROOT/bin/$_s.sh" ] && answers "$ROOT/bin/$_s.sh" && printf '%s\t%s\n' "$_id" "$ROOT/bin/$_s.sh" || :
      done
}
if [ "$LIST" = 1 ]; then adopters | sed "s|	$ROOT/bin/|	|; s|\.sh\$||"; exit 0; fi

T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM
adopters > "$T/adopters"
[ -s "$T/adopters" ] || unchecked "no check row of controls.tsv names a script that answers --status" "sh bin/drift-status.sh --list"

# the one parser: a report and the exit code it came with -> rows, or the reason it is not a report
parse() { # <check id> <exit> <report file>
  awk -F'\t' -v id="$1" -v rc="$2" '
    function bad(m) { why = (why == "" ? m : why); }
    NR == 1 { if ($0 != "reconcile\t1\t" id) bad("the first line is not reconcile<TAB>1<TAB>" id); next }
    fin { bad("a record after the closing one"); next }
    $1 == "new" || $1 == "standing" { if (NF != 6) { bad($1 " has " NF " fields, not 6"); next }
      row[++n] = id "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6; next }
    $1 == "cleared" { next }
    $1 == "summary" { if (NF != 4) bad("summary is not three numbers"); sm = 1; dr = $3 + 0; fin = 1; next }
    $1 == "unchecked" { un = 1; reason = $2; fin = 1; next }
    { bad("an unknown record " $1) }
    END {
      if (NR == 0) bad("no output")
      else if (!sm && !un) bad("no closing record")
      if (sm && dr != n + 0) bad("summary counts " dr " drifted and " n + 0 " rows are listed")
      if (sm && rc != (dr > 0 ? 1 : 0)) bad("exit " rc " beside " dr " drifted")
      if (un && rc != 3) bad("unchecked beside exit " rc)
      if (un && n + 0 > 0) bad("rows before unchecked")
      if (!sm && !un && rc !~ /^[013]$/) bad("exit " rc)
      if (why != "") { print id "\tunchecked\tthe report breaks contracts/reconcile.md: " why; exit }
      if (un) { print id "\tunchecked\t" reason; exit }
      for (i = 1; i <= n; i++) print row[i]
    }' "$3"
}

NA=0; ND=0; NU=0
: > "$T/out"
while IFS='	' read -r _id _sc; do
  if [ -n "$ONLY" ]; then case "$ONLY" in *"
$_id
"*|*"
$_id") ;; *) continue ;; esac; fi
  NA=$((NA + 1))
  _rc=0; sh "$_sc" --status > "$T/rep" 2>/dev/null < /dev/null || _rc=$?
  parse "$_id" "$_rc" "$T/rep" > "$T/rows"
  grep -q "^$_id	unchecked	" "$T/rows" && NU=$((NU + 1)) || ND=$((ND + $(wc -l < "$T/rows")))
  cat "$T/rows" >> "$T/out"
done < "$T/adopters"
[ "$NA" -gt 0 ] || usage "--only names no adopter: sh bin/drift-status.sh --list"
cat "$T/out"
printf 'total\t%s\t%s\t%s\n' "$NA" "$ND" "$NU"
[ "$ND" -eq 0 ] || exit 1
[ "$NU" -eq 0 ] || exit 3
exit 0
