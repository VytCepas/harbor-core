#!/usr/bin/env sh
# bin/lint-name-ratchet.sh and lint.name-ratchet: the naming findings only shrink (harbor#967).
# Each case runs the real bin/lint-name.sh over a throwaway copy of what it reads (fixture.sh mini): a bad name planted
# is NEW and red, removed is green; a baseline line for a live finding deleted is red; a line for a fixed one is STALE.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_SCOPE_PRIVATE="$TMP/no-private"; export HARBOR_SCOPE_PRIVATE; unset PORT_ROOT
. "$T_ROOT/tests/checks/lint-fixture.sh"
LN="$T_ROOT/bin/lint-name.sh"
REG="$T_ROOT/standards/naming"
. "$T_ROOT/tests/lint/name/fixture.sh"
R="$T_ROOT/bin/lint-name-ratchet.sh"
rat() { HARBOR_SCOPE_ROOT="$1" sh "$R" "${2:---check}" 2>&1; }
rrc() { HARBOR_SCOPE_ROOT="$1" sh "$R" "${2:---check}" >/dev/null 2>&1; echo $?; }

D="$TMP/ratchet"; mini "$D"
cp "$R" "$D/bin/"
BL="$D/contracts/lint-name-baseline.txt"
sh "$D/bin/lint-name-ratchet.sh" --current > "$TMP/cur0" 2>/dev/null || :
{ printf '# test baseline\n'; cat "$TMP/cur0"; } > "$BL"

t_section "a tree whose findings are all baselined is green"
t_eq "at the baseline the check exits 0" "0" "$(rrc "$D")"
t_has "...and says none are new" "$(rat "$D")" "none new"

t_section "a bad name planted is NEW and red; removed, green again"
: > "$D/Planted_Bad.md"
t_eq "a planted bad name exits 1" "1" "$(rrc "$D")"
t_has "...and names the finding as NEW" "$(rat "$D")" "NEW name.case Planted_Bad.md"
t_has "lint.name-ratchet reports it as a violation" "$(lint1 lint.name-ratchet "$D")" "VIOLATION [lint.name-ratchet]"
rm "$D/Planted_Bad.md"
t_eq "removed, it exits 0" "0" "$(rrc "$D")"
t_eq "...and the rule is silent" "0" "$(vcount "$(lint1 lint.name-ratchet "$D")")"

t_section "the baseline holds a finding; deleting its line for a live finding is red, and a fixed finding's line is STALE"
: > "$D/Held_Bad.md"
sh "$D/bin/lint-name-ratchet.sh" --current > "$TMP/cur1" 2>/dev/null || :
{ printf '# test baseline\n'; cat "$TMP/cur1"; } > "$BL"
t_eq "a baselined bad name is green" "0" "$(rrc "$D")"
grep -v 'Held_Bad.md' "$BL" > "$TMP/bl.new"; cp "$TMP/bl.new" "$BL"
t_eq "deleting its baseline line while it is live is red" "1" "$(rrc "$D")"
t_has "...as NEW" "$(rat "$D")" "NEW name.case Held_Bad.md"
{ printf '# test baseline\n'; cat "$TMP/cur1"; } > "$BL"
rm "$D/Held_Bad.md"
t_eq "the name is fixed but its line stays: red" "1" "$(rrc "$D")"
t_has "...as STALE, with the line to delete" "$(rat "$D")" "STALE name.case Held_Bad.md no longer occurs"
t_has "lint.name-ratchet reports the stale line" "$(lint1 lint.name-ratchet "$D")" "VIOLATION [lint.name-ratchet]"
{ printf '# test baseline\n'; cat "$TMP/cur0"; } > "$BL"
t_eq "the line deleted, green" "0" "$(rrc "$D")"

t_section "a key survives a rename of something else, and --current prints the baseline's own shape"
t_has "--current prints rule TAB subject" "$(printf 'x\n' > "$D/Cur_Bad.md"; rat "$D" --current)" "name.case	Cur_Bad.md"
rm "$D/Cur_Bad.md"

t_section "harbor-core has no dev layer: a dev-only exemption is not judged stale there, and is everywhere else"
printf 'path\tlayer\tnote\ndev-only/\tdev\tnot exported\n' > "$D/contracts/layers.tsv"; mkdir -p "$D/dev-only"
cp "$D/standards/naming/exemptions.tsv" "$TMP/ex.keep"
printf 'legacy-9999\tname.case\tGone_Dev.md\tlegacy\t2027-01-01\ttest: the subject lives in the dev layer only\n' >> "$D/standards/naming/exemptions.tsv"
t_eq "with the dev layer present, the absent subject's row is red" "1" "$(rrc "$D")"
t_has "...as NEW name.exemption-stale" "$(rat "$D")" "NEW name.exemption-stale exemption:legacy-9999"
cp "$BL" "$TMP/bl.keep"
: > "$D/dev-only/Dev_Bad.md"
sh "$D/bin/lint-name-ratchet.sh" --current > "$TMP/cur2" 2>/dev/null || :
{ printf '# test baseline\n'; cat "$TMP/cur2"; } > "$BL"
rm -r "$D/dev-only"
t_eq "in an export (no dev row exists) neither is judged: green" "0" "$(rrc "$D")"
t_has "...and says what it skipped" "$(rat "$D")" "no dev layer in this tree"
t_hasnt "...a baselined dev file's finding is not STALE there" "$(rat "$D")" "STALE name.case dev-only/Dev_Bad.md"
cp "$TMP/ex.keep" "$D/standards/naming/exemptions.tsv"; rm "$D/contracts/layers.tsv"; cp "$TMP/bl.keep" "$BL"
t_eq "restored, green" "0" "$(rrc "$D")"

t_section "what it cannot judge is never a pass"
rm "$BL"
t_eq "a missing baseline is red" "1" "$(rrc "$D")"
: > "$BL"
t_eq "an empty baseline is valid: the clean copy has no finding to hold" "0" "$(rrc "$D")"
printf '#!/bin/sh\necho boom >&2\nexit 2\n' > "$TMP/judge-broken.sh"
printf 'name.case\tx\n' > "$BL"
t_eq "a judge that exits above 1 is red (exit 2), not green" "2" "$(HARBOR_SCOPE_ROOT="$D" LINT_NAME_BIN="$TMP/judge-broken.sh" sh "$R" >/dev/null 2>&1; echo $?)"
t_exit "an unknown argument is a usage error" 2 sh "$R" --bogus
t_done
