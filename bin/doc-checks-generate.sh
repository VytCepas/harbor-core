#!/usr/bin/env sh
# doc-checks-generate.sh (harbor#1437) — docs/reference/checks.md, generated and never hand-written.
#
#   sh doc-checks-generate.sh --write   write docs/reference/checks.md
#   sh doc-checks-generate.sh --check   exit 1 when it is not what the generator makes (the contracts/fresh-checks.tsv row)
#   sh doc-checks-generate.sh --print   the page on stdout
#   --root <dir>   the tree to read and write (default: this checkout)
#
# The page is docs/reference/checks.md.tmpl with its <!-- gen:check-rows --> hole filled by one register row per `check` row of
# controls.tsv, sorted by id (a row's `emitted` when it has one, else its id: the id the check stamps). The four prose cells of a
# row (watches, schedule, notifies, red means) are the repo fragment docs/reference/check-rows/<unit>.txt, <unit> being the id with
# each dot a dash (a dot in a file name reads as an extension), `key: value` lines. A
# check row with no fragment still appears, from its controls cells (title, moment, red_proof), so a check is registered the moment
# its controls row is. A fragment with no controls row is refused: it would be a check the register does not know.
# exit 0 written / current · 1 stale (--check) · 2 usage or a refused fragment · 3 unchecked (a source is missing)
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$HERE/library-log.sh"
log_init doc-checks-generate
usage() { awk 'NR < 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$HERE/${0##*/}"; }
die() { log_fail "$2"; log_fix "$3"; log_end || :; exit "$1"; }

ACTION=""; ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --write) ACTION=apply ;;
    --check) ACTION=check ;;
    --print) ACTION=print ;;
    --root) [ $# -ge 2 ] || die 2 "--root needs a directory" "sh $0 --root DIR --check"; ROOT="$2"; shift ;;
    *) die 2 "unknown argument: $1" "sh $0 --help" ;;
  esac
  shift
done
[ -n "$ACTION" ] || die 2 "no action" "sh $0 --help"
ROOT="${ROOT:-$HERE/..}"
ROOT="$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P)" || die 2 "--root is not a directory" "sh $0 --root DIR --check"

TMPL="$ROOT/docs/reference/checks.md.tmpl"; OUT="$ROOT/docs/reference/checks.md"; FRAGS="$ROOT/docs/reference/check-rows"
CTL="$ROOT/standards/naming/controls.tsv"; [ -f "$CTL" ] || CTL="$ROOT/vendor/naming/registry/controls.tsv"
[ -f "$TMPL" ] || die 3 "no template at $TMPL" "restore docs/reference/checks.md.tmpl"
[ -f "$CTL" ] || die 3 "no controls register under $ROOT" "sh bin/standard-vendor.sh ."

T="$(mktemp -d "${TMPDIR:-/tmp}/doc-checks.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM HUP

# The ids the register knows, one per line, then the rows. awk reads each fragment itself, so a cell is never re-parsed by the shell.
awk -F'\t' '$0 !~ /^#/ && $3 == "check" { print (($12 != "-" && $12 != "") ? $12 : $1) "\t" $6 "\t" $11 "\t" $13 }' "$CTL" | LC_ALL=C sort > "$T/ids"
[ -s "$T/ids" ] || die 3 "controls.tsv has no check row" "sh bin/standard-vendor.sh ."

cut -f1 "$T/ids" | tr . - | LC_ALL=C sort | uniq -d > "$T/clash"
[ ! -s "$T/clash" ] || die 2 "two check ids share a fragment name (dots read as dashes): $(tr '\n' ' ' < "$T/clash")" "rename one of the checks"
if [ -d "$FRAGS" ]; then
  find "$FRAGS" -maxdepth 1 -type f -name '*.txt' | LC_ALL=C sort | while IFS= read -r _f; do
    _u="${_f##*/}"; _u="${_u%.txt}"
    cut -f1 "$T/ids" | tr . - | grep -qxF "$_u" || printf '%s\n' "$_u"
  done > "$T/orphans"
  if [ -s "$T/orphans" ]; then
    die 2 "fragment(s) with no check row in controls.tsv: $(tr '\n' ' ' < "$T/orphans")" "add the controls.tsv check row first (D-62), or delete the fragment"
  fi
fi

: > "$T/rows"
while IFS="$(printf '\t')" read -r _id _moment _red _title; do
  _f="$FRAGS/$(printf '%s' "$_id" | tr . -).txt"
  if [ -f "$_f" ]; then
    awk -v id="$_id" -v f="$_f" '
      /^watches: /  { w = substr($0, 10); next }
      /^schedule: / { s = substr($0, 11); next }
      /^notifies: / { n = substr($0, 11); next }
      /^red: /      { r = substr($0, 6); next }
      /^[ \t]*$/ { next }
      { printf "%s: unknown line: %s\n", f, $0 > "/dev/stderr"; bad = 1 }
      END { if (bad) exit 2
            if (w == "" || s == "" || n == "" || r == "") { printf "%s: needs watches, schedule, notifies and red lines\n", f > "/dev/stderr"; exit 2 }
            if (index(w s n r, "|")) { printf "%s: a cell holds a pipe\n", f > "/dev/stderr"; exit 2 }
            printf "| `%s` | %s | %s | %s | %s |\n", id, w, s, n, r }' "$_f" >> "$T/rows" || die 2 "fragment refused: $_f" "fix the fragment: four lines, watches: schedule: notifies: red:"
  else
    _sched="not scheduled: a command a person types"; [ "$_moment" = schedule ] && _sched="scheduled: see its plist"
    [ "$_red" = "-" ] || _sched="$_sched; falsifier: \`$_red\`"
    printf '| `%s` | %s | %s | none yet: write docs/reference/check-rows/%s.txt | - |\n' "$_id" "$_title" "$_sched" "$(printf '%s' "$_id" | tr . -)" >> "$T/rows"
  fi
done < "$T/ids"

# The generated-by header is written here, after the front matter, never kept in the template: a template that carried it would be a
# generated file itself (doc.fresh-registered).
awk -v rows="$T/rows" '/^<!-- gen:check-rows -->$/ { while ((getline l < rows) > 0) print l; next }
  { print } /^---$/ && ++fm == 2 {
    print "<!-- generated by sh bin/doc-checks-generate.sh --write from standards/naming/controls.tsv, docs/reference/check-rows/ and docs/reference/checks.md.tmpl — do not edit -->"
    print "<!-- generated-by: sh bin/doc-checks-generate.sh --write -->" }' "$TMPL" > "$T/out"
grep -q '^<!-- gen:check-rows -->$' "$TMPL" || die 3 "the template has no <!-- gen:check-rows --> hole" "restore docs/reference/checks.md.tmpl"

case "$ACTION" in
  print) cat "$T/out" ;;
  apply) cmp -s "$T/out" "$OUT" 2>/dev/null || cp "$T/out" "$OUT" ;;
  check)
    if cmp -s "$T/out" "$OUT" 2>/dev/null; then exit 0; fi
    log_fail "docs/reference/checks.md is not what controls.tsv, the fragments and the template make"
    log_fix "sh bin/doc-checks-generate.sh --write"; log_end || :; exit 1 ;;
esac
