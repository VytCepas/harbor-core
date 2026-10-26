#!/usr/bin/env sh
# bin/doc-vale.sh (harbor#978): Vale warns once on a legacy alias and once on a UK spelling, not inside backticks,
# and says "verified NOTHING" when Vale is missing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
command -v vale >/dev/null 2>&1 || { echo "vale-test: vale is not installed — verified NOTHING" >&2; exit 3; }
DV="$T_ROOT/bin/doc-vale.sh"
R="$T_TMP/r"; mkdir -p "$R/standards" "$R/bin"; cp -R "$T_ROOT/standards/naming" "$R/standards/naming"
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/log-lib.sh" "$DV" "$R/bin/"
printf 'The floor is high.\n\nPaint it the colour red.\n' > "$T_TMP/bad.md"
printf 'Use `floor` and `colour` in code.\n' > "$T_TMP/ticks.md"
printf 'Nothing to say here.\n' > "$T_TMP/clean.md"
printf 'Ban the self-healing thing.\n' > "$T_TMP/banned.md"
run() { sh "$R/bin/doc-vale.sh" "$@" 2>&1; }
t_section "warnings"
_o="$(run "$T_TMP/bad.md")"
t_has "a legacy alias draws one warning" "$_o" "Harbor.Legacy"
t_has "a UK spelling draws one warning" "$_o" "Harbor.Spelling"
t_eq "…exactly two in all" 2 "$(printf '%s\n' "$_o" | grep -c 'Harbor\.')"
t_eq "an alias or spelling inside backticks draws none" 0 "$(run "$T_TMP/ticks.md" | grep -c 'Harbor\.')"
t_eq "clean prose draws none" 0 "$(run "$T_TMP/clean.md" | grep -c 'Harbor\.')"
t_exit "warnings exit 0" 0 sh "$R/bin/doc-vale.sh" "$T_TMP/bad.md"
t_has "a banned word is an error" "$(run "$T_TMP/banned.md")" "error"
t_exit "…and exits 1" 1 sh "$R/bin/doc-vale.sh" "$T_TMP/banned.md"
t_section "Vale missing"
SAFE="$T_TMP/nopath"; mkdir -p "$SAFE"; for t in sh awk sed cat mkdir cp dirname date rm mktemp head tr sort uniq grep; do ln -s "$(command -v $t)" "$SAFE/$t" 2>/dev/null; done
_m="$(PATH="$SAFE" /bin/sh "$R/bin/doc-vale.sh" "$T_TMP/bad.md" 2>&1)"; _rc=$?
t_has "without vale it says verified NOTHING" "$_m" "verified NOTHING"
t_eq "…and exits 3, never 0" 3 "$_rc"
t_done
