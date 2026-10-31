#!/usr/bin/env sh
# lint-name-ratchet.sh (harbor#967) - the naming findings as a ratchet: a new bad name is red, a fixed one must leave the baseline.
#
#   sh bin/lint-name-ratchet.sh            judge the tree against contracts/lint-name-baseline.txt (--check)
#   sh bin/lint-name-ratchet.sh --current  print the findings now, one key per line, in the baseline's own shape
#
# WHY A RATCHET. Every naming rule is advisory (standards/naming.md 10.3), so nothing stopped a new bad name while the
# rename waves were still retiring the old ones. A cliff on the legacy findings would fail every branch for names it
# never touched, and a guard that blocks ordinary work gets switched off. So today's findings are baselined and the
# baseline may only shrink:
#   NEW    a finding the baseline lacks              -> red: fix the name, or register the word if it is genuine vocabulary
#   STALE  a baselined finding that no longer occurs -> red: delete its line, so the same defect cannot return unseen
# There is no --bless. Adding a line is a hand edit in a diff a reviewer reads.
#
# KEY: `<rule> TAB <subject>` from `bin/lint-name.sh --format findings`, never a count and never a line number. A renamed
# env variable or path leaves the key set by itself and turns STALE, which is the only-shrinks path. One subject with
# two findings of one rule is one key: fixing one of them leaves the other held, so read the lint's WARN line for the word.
#
#   LINT_NAME_BIN       override the judge (the falsifier suite uses it)
#   LINT_NAME_BASELINE  override the baseline path
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
JUDGE="${LINT_NAME_BIN:-$ROOT/bin/lint-name.sh}"
BASE="${LINT_NAME_BASELINE:-$ROOT/contracts/lint-name-baseline.txt}"
. "$SRC/library-log.sh"
log_init lint-name-ratchet
LOG_FD=2

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint-name-ratchet.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

# current <out>: the findings now as sorted unique `rule TAB subject`; returns 1 when the judge could not look.
current() {
  _rc=0
  sh "$JUDGE" --root "$ROOT" --format findings > "$TMP/raw" 2> "$TMP/err" || _rc=$?
  if [ "$_rc" -gt 1 ]; then
    log_fail "bin/lint-name.sh exited $_rc and judged nothing: $(grep -m1 'FAIL:' "$TMP/err" | sed 's/^ *FAIL: //')"
    log_fix "sh bin/lint-name.sh --root $ROOT (read its first FAIL line)"
    return 1
  fi
  awk -F'\t' 'NF >= 3 && $1 ~ /^[A-Z]$/ { print $2 "\t" $3 }' "$TMP/raw" | LC_ALL=C sort -u > "$1"
}

# export: true in harbor-core, where no dev row of layers.tsv exists. A dev file's finding and an exemption row for a
# dev-only name read as fixed there, so both are judged only in a tree that has the dev layer (harbor#967).
export_tree() {
  [ -f "$ROOT/contracts/layers.tsv" ] || return 1
  _dev="$(awk -F'\t' '!/^[ \t]*#/ && $2 == "dev" && !index($1, "*") && !index($1, "?") { print $1 }' "$ROOT/contracts/layers.tsv")"
  [ -n "$_dev" ] || return 1
  for _p in $_dev; do [ ! -e "$ROOT/${_p%/}" ] || return 1; done
}
# unjudged <file>: drops what this tree cannot judge, in place.
unjudged() {
  export_tree || return 0
  cut -f2 "$1" | HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-layers.sh" --classify > "$1.l" 2>/dev/null || :
  awk -F'\t' 'NR == FNR { if ($2 == "dev") d[$1] = 1; next } $1 != "name.exemption-stale" && !($2 in d)' "$1.l" "$1" > "$1.j"
  mv "$1.j" "$1"
}

case "${1:---check}" in
  --current)
    current "$TMP/now" || { log_end || :; exit 2; }
    cat "$TMP/now" ;;
  --check)
    if [ ! -r "$BASE" ]; then
      log_fail "no baseline at ${BASE#$ROOT/}: an empty file is a valid baseline, a missing one is not"
      log_fix "sh bin/lint-name-ratchet.sh --current > contracts/lint-name-baseline.txt, then review the diff"
      log_end || :; exit 1
    fi
    current "$TMP/now" || { log_end || :; exit 2; }
    grep -vE '^[[:space:]]*(#|$)' "$BASE" | LC_ALL=C sort -u > "$TMP/base" || :
    if export_tree; then log_skip "no dev layer in this tree: dev files' findings and name.exemption-stale are not judged"; fi
    unjudged "$TMP/now"; unjudged "$TMP/base"
    LC_ALL=C comm -23 "$TMP/now" "$TMP/base" > "$TMP/new"
    LC_ALL=C comm -13 "$TMP/now" "$TMP/base" > "$TMP/stale"
    known="$(LC_ALL=C comm -12 "$TMP/now" "$TMP/base" | grep -c . || :)"
    RC=0
    while IFS="$(printf '\t')" read -r _r _s; do
      log_fail "NEW $_r $_s"
      log_fix "rename it to the standard; a genuine tool, file-convention or English word goes in standards/naming/words.tsv with its reason; never in the baseline"
      RC=1
    done < "$TMP/new"
    while IFS="$(printf '\t')" read -r _r _s; do
      log_fail "STALE $_r $_s no longer occurs"
      log_fix "delete its line from contracts/lint-name-baseline.txt so it cannot come back unseen"
      RC=1
    done < "$TMP/stale"
    [ "$RC" -ne 0 ] || log_ok "$known naming finding(s) held by the baseline, none new"
    log_end || :; exit "$RC" ;;
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
  *) echo "lint-name-ratchet: unknown argument '$1'" >&2; exit 2 ;;
esac
