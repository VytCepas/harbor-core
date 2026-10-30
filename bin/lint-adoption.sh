#!/usr/bin/env sh
# lint-adoption.sh (harbor#117 · A4) — every vendored asset has an intake row.
#
#   sh bin/lint-adoption.sh          the run log (contracts/logging.md); exit 1 with the gaps
#
# WHAT A4 ACTUALLY ASKED FOR, AND WHY THIS IS NOT ADOPTION.md. The ticket's own
# Build line says: "fold the per-asset change record into vendor/skills/PROVENANCE.md — ONE
# FILE, NOT TWO." Its first falsifier here was `test -f ADOPTION.md`, which the
# ticket forbids: it would have gone green only by building the second file A4
# exists to avoid, and stayed red forever otherwise. A falsifier that can only be
# satisfied by violating its own ticket is worse than none.
#
# The real Done-when is a COVERAGE property — "every vendored asset has a row; a
# reader can re-run the intake from the row without diffing" — and coverage is
# exactly the kind of claim that rots silently. Vendoring a 29th skill without a
# row breaks it, and nothing about the repo looks different.
#
# BOTH DIRECTIONS, because each fails differently. A directory with no row is an
# asset whose intake surgery is unrecorded, and a re-harvest reverts it. A row
# with no directory is the T6 failure in the other table: a record that tells a
# reader something is vendored when it is not.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/library-log.sh"
log_init adoption-check
DIR="$ROOT/vendor/skills"
DOC="$ROOT/vendor/skills/PROVENANCE.md"

log_head "vendor/skills against vendor/skills/PROVENANCE.md"
if [ ! -d "$DIR" ]; then
  log_skip "no vendor/skills here: it is dev-layer, so an export has none to check"
  log_end; exit $?
fi
if [ ! -f "$DOC" ]; then
  log_fail "no vendor/skills/PROVENANCE.md ($DOC)"
  log_nofix "bin/lint-adoption.sh (one intake row per vendored asset lives in that file)"
  log_end; exit $?
fi

for d in "$DIR"/*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  if grep -qE "^\| *$n *\|" "$DOC"; then
    log_ok "$n has an intake row"
  else
    log_fail "$n is vendored with NO intake row — a re-harvest will silently revert its edits"
    log_fix "add a '| $n | … |' row to vendor/skills/PROVENANCE.md"
  fi
done

# The separator row `|---|---|` is not an asset name. Anchoring on a leading dash
# rather than on a row count keeps this working when the table gains a column.
# Rows go through a file, not a pipe: a pipe would run the loop in a subshell and lose the counts.
_rows="$(grep -oE '^\| *[a-z0-9][a-z0-9-]* *\|' "$DOC" | tr -d '| ' | sort -u)"
for r in $_rows; do
  [ -d "$DIR/$r" ] && continue
  log_fail "vendor/skills/PROVENANCE.md has a row for $r, which is not vendored here"
  log_fix "delete the '$r' row from vendor/skills/PROVENANCE.md, or vendor vendor/skills/$r"
done

log_end; exit $?
