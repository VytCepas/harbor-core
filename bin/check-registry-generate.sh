#!/usr/bin/env sh
# check-registry-generate.sh (harbor#1149, D-79) - the one check registry: core CHECKS.md plus the private layer's rows
# plus every installed pack's rows.
#
#   sh check-registry-generate.sh [--core FILE] [--private DIR] [--packs DIR]   the composed register, on stdout
#
# The private layer holds <private>/checks.md, a fragment in the register's own shape: a "## Register" table
# body, a "## Platforms" table body and a "## Notes" prose block, each optional. A pack ships the same fragment as
# harbor-pack/checks.md, which `harbor pack install` puts at <config dir>/checks.d/<repo-id>.md; --packs names that
# directory (default: none). Core CHECKS.md carries the two insertion points <!-- private:register --> and
# <!-- private:platforms -->, one at the end of each table. The register rows go in at the first, the platforms rows
# at the second, private rows before pack rows (packs by repo id), and the notes close the file under "## Private notes"
# and "## Pack notes: <repo-id>". No fragment at all prints CHECKS.md unchanged: byte for byte.
#
# A fragment that cannot be composed refuses the whole read (exit 2, nothing on stdout) and never
# half-merges: a malformed row, an id twice or already in core or in another fragment, a register row with no
# platforms row (or the reverse), or rows with no insertion point to take them. Skipping a row would answer "no such
# check" for a check that is only mistyped. Readers: runtime-install.sh (the installed bin/CHECKS.md), pack.sh (the same
# file, after an install or a remove), install-drift.sh, findings.sh, lint-conventions.sh (X9, audit.finding-lanes).
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/log-lib.sh"
log_init check-registry-generate
LOG_FD=2

CORE="$ROOT/CHECKS.md"
PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
PACKS=''
while [ $# -gt 0 ]; do
  case "$1" in
    --core) [ $# -ge 2 ] || { log_fail "--core takes a file"; log_fix "sh $0 --core CHECKS.md"; log_end || :; exit 2; }; CORE="$2"; shift 2 ;;
    --private) [ $# -ge 2 ] || { log_fail "--private takes a directory"; log_fix "sh $0 --private DIR"; log_end || :; exit 2; }; PRIV="$2"; shift 2 ;;
    --packs) [ $# -ge 2 ] || { log_fail "--packs takes a directory"; log_fix "sh $0 --packs DIR"; log_end || :; exit 2; }; PACKS="$2"; shift 2 ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
    *) log_fail "unknown argument: $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
  esac
done
PRIV="${PRIV%/}"
[ -f "$CORE" ] || { log_fail "no register at $CORE"; log_fix "sh $0 --core <path to CHECKS.md>"; log_end || :; exit 2; }

FRAG="$PRIV/checks.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-registry.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

# The fragments, in composition order: the private layer's, then each installed pack's by repo id. A file with no
# content is not a source, so an empty checks.md ('scope install' writes one) leaves core unchanged.
: > "$TMP/srcs"
if [ -f "$FRAG" ] && grep -q '[^[:space:]]' "$FRAG"; then printf '%s\n' "$FRAG" >> "$TMP/srcs"; fi
if [ -n "$PACKS" ] && [ -d "$PACKS" ]; then
  find "$PACKS" -maxdepth 1 -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r _pf; do
    if grep -q '[^[:space:]]' "$_pf"; then printf '%s\n' "$_pf"; fi
  done >> "$TMP/srcs"
fi
if [ ! -s "$TMP/srcs" ]; then cat "$CORE"; exit 0; fi

# Each fragment, section by section. A section other than the three is refused, so a typo is not read as nothing.
_n=0
while IFS= read -r _f; do
  _n=$((_n + 1)); mkdir -p "$TMP/s$_n"
  awk -v d="$TMP/s$_n" -v e="$TMP/errors" '
  function bad(m) { printf "%s line %d: %s\n", FILENAME, FNR, m >> e; fail = 1 }
  { sub(/\r$/, "") }
  FNR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, length("\357\273\277") + 1) }  # 1 char to gawk in UTF-8
  /^## / {
    sec = ($0 == "## Register") ? "register" : ($0 == "## Platforms") ? "platforms" : ($0 == "## Notes") ? "notes" : ""
    if (sec == "") bad("section " $0 " is not Register, Platforms or Notes")
    else if (seen[sec]++) bad("section " $0 " appears twice")
    next
  }
  sec == "notes" { print > (d "/notes"); next }
  /^[ \t]*$/ || /^<!--.*-->[ \t]*$/ { next }
  sec == "register" {
    n = split($0, f, "|")
    if ($0 !~ /^\| `[a-z0-9.-]+` \|/ || n != 7) { bad("not a register row (| `id` | watches | schedule | notifies | red means |)"); next }
    id = f[2]; gsub(/[` ]/, "", id)
    if (id in rid) { bad("the id " id " repeats line " rid[id]); next }
    rid[id] = FNR; print > (d "/register"); print id > (d "/register.ids"); next
  }
  sec == "platforms" {
    n = split($0, f, "|")
    if ($0 !~ /^\| [a-z0-9.-]+ \|/ || n != 6) { bad("not a platforms row (| id | platforms | why | disable |)"); next }
    id = f[2]; gsub(/ /, "", id)
    if (id in pid) { bad("the id " id " repeats line " pid[id]); next }
    pid[id] = FNR; print > (d "/platforms"); print id > (d "/platforms.ids"); next
  }
  { bad("content before the first section") }
  END { exit fail }' "$_f" || :
  for _x in register register.ids platforms platforms.ids notes; do [ -f "$TMP/s$_n/$_x" ] || : > "$TMP/s$_n/$_x"; done
done < "$TMP/srcs"
if [ -s "$TMP/errors" ]; then
  while IFS= read -r _e; do log_fail "$_e"; done < "$TMP/errors"
  log_fix "edit the fragment named above; the composed register is refused until every row parses"; log_end || :; exit 2
fi

_rc=0
awk -F'|' '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `[a-z0-9.-]+` \|/ { id = $2; gsub(/[` ]/, "", id); print id }' "$CORE" | sort > "$TMP/cs"
# One registry, one row per id: an id may appear once across core and every fragment.
{ while IFS= read -r _i; do printf '%s\tcore CHECKS.md\n' "$_i"; done < "$TMP/cs"
  _n=0; while IFS= read -r _f; do _n=$((_n + 1)); while IFS= read -r _i; do printf '%s\t%s\n' "$_i" "$_f"; done < "$TMP/s$_n/register.ids"; done < "$TMP/srcs"; } > "$TMP/allids"
awk -F'\t' '$1 in first { printf "%s\t%s\t%s\n", $1, first[$1], $2; next } { first[$1] = $2 }' "$TMP/allids" > "$TMP/dups"
while IFS='	' read -r _i _a _b; do
  log_fail "the id $_i is in $_a and in $_b: one registry, one row"
  log_fix "drop it from one of the two"; _rc=2
done < "$TMP/dups"
_n=0
while IFS= read -r _f; do
  _n=$((_n + 1))
  sort "$TMP/s$_n/register.ids" > "$TMP/rs"; sort "$TMP/s$_n/platforms.ids" > "$TMP/ps"
  for _i in $(comm -3 "$TMP/rs" "$TMP/ps" | tr -d '\t'); do
    log_fail "the id $_i has a register row or a platforms row in $_f, not both"; log_fix "add the missing row to $_f"; _rc=2
  done
  if grep -q . "$TMP/s$_n/register" && ! grep -qxF '<!-- private:register -->' "$CORE"; then
    log_fail "$CORE has no <!-- private:register --> line to take the register rows"; log_fix "restore the line at the end of the Register table"; _rc=2
  fi
  if grep -q . "$TMP/s$_n/platforms" && ! grep -qxF '<!-- private:platforms -->' "$CORE"; then
    log_fail "$CORE has no <!-- private:platforms --> line to take the platforms rows"; log_fix "restore the line at the end of the Platforms table"; _rc=2
  fi
done < "$TMP/srcs"
if [ "$_rc" -ne 0 ]; then log_end || :; exit 2; fi

: > "$TMP/register"; : > "$TMP/platforms"; : > "$TMP/notes"
_n=0
while IFS= read -r _f; do
  _n=$((_n + 1))
  cat "$TMP/s$_n/register" >> "$TMP/register"; cat "$TMP/s$_n/platforms" >> "$TMP/platforms"
  if grep -q . "$TMP/s$_n/notes"; then
    if [ "$_f" = "$FRAG" ]; then printf '\n## Private notes\n\n' >> "$TMP/notes"
    else _pn="${_f##*/}"; printf '\n## Pack notes: %s\n\n' "${_pn%.md}" >> "$TMP/notes"; fi
    cat "$TMP/s$_n/notes" >> "$TMP/notes"
  fi
done < "$TMP/srcs"

awk -v d="$TMP" '
  function dump(f,   l) { while ((getline l < f) > 0) print l; close(f) }
  $0 == "<!-- private:register -->" { dump(d "/register"); next }
  $0 == "<!-- private:platforms -->" { dump(d "/platforms"); next }
  { print }' "$CORE" > "$TMP/out"
if grep -q . "$TMP/notes"; then cat "$TMP/notes" >> "$TMP/out"; fi
cat "$TMP/out"
