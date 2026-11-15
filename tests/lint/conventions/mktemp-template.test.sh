#!/usr/bin/env sh
# mktemp template (harbor#1298): every mktemp in shipped shell code names a template under $TMPDIR.
# Under the confinement a bare `mktemp`/`mktemp -d` fails on macOS: it creates in /var/folders/…/T even with
# TMPDIR set to the writable sandbox dir (#1297 round 2). Linux honours TMPDIR, so the bug is invisible there.
# Interim tripwire: the repo-wide lint rule is a human-gated change.
. "$(dirname "$0")/../../lib/core.sh"; t_init
BARE='(^|[^[:alnum:]_-])mktemp([[:space:]]+-[dq]+)*[[:space:]]*($|\)|;|\||&|2>)'
# bare <file>… -> one "<file>:<line>" per bare call in code (comment lines skipped)
bare() {
  for _f in "$@"; do
    [ -f "$_f" ] || continue
    awk -v f="${_f#"$T_ROOT"/}" '/^[[:space:]]*#/ { next } { print f ":" NR ":" $0 }' "$_f"
  done | grep -E "$BARE" | cut -d: -f1,2
}
# shipped shell code: bin/, hooks/, skills/*/bin/. Data that holds a bare call on purpose is not here
# (guard fixtures, and the work-log check deploy-runtime-install.sh prints for the operator to paste).
shipped() { find "$T_ROOT/bin" "$T_ROOT/hooks" "$T_ROOT"/skills/*/bin -type f ! -name '*.md' ! -name '*.tsv' ! -name '*.json' 2>/dev/null | grep -v '/deploy-runtime-install\.sh$'; }

t_section "shipped shell code holds no bare mktemp"
# shellcheck disable=SC2046 # the file list is paths without spaces
t_eq "every mktemp names a template" "" "$(bare $(shipped))"

t_section "controls: the derive sees what it must"
M="$T_TMP/m"; mkdir -p "$M"
printf '%s\n' 'A="$(mktemp)"' 'B="$(mktemp -d)"; echo' 'C=$(mktemp 2>/dev/null)' > "$M/bad.sh"
printf '%s\n' 'A="$(mktemp "${TMPDIR:-/tmp}/x.XXXXXX")"' '# mktemp in a comment' 'echo mktemp-free' > "$M/good.sh"
t_eq "three bare forms are caught" "3" "$(bare "$M/bad.sh" | wc -l | tr -d ' ')"
t_eq "a templated call, a comment and a word are not" "" "$(bare "$M/good.sh")"
t_has "the scan reaches hooks/" "$(shipped)" "/hooks/pre-commit"
t_has "the scan reaches skills/*/bin/" "$(shipped)" "/skills/access-ledger/bin/check-routes.sh"
t_done
