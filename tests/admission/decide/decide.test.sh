#!/usr/bin/env sh
# bin/admission-decide.sh and bin/admission-replay.sh (harbor#1030): one decision function reads a fired rule's mode from its row;
# an unreadable register fails closed with its remedy; the egress guard asks it and keeps every verdict it had.
. "$(dirname "$0")/../../lib/core.sh"; t_init
D="$T_ROOT/bin/admission-decide.sh"; REG="$T_ROOT/standards/naming/controls.tsv"; RP="$T_ROOT/bin/admission-replay.sh"

t_section "the decision function"
t_has "--self-test: every row of the admission controls returns the verdict its mode declares" "$(sh "$D" --self-test 2>&1)" "0 failed"
t_eq "a block row blocks" "block	admission.key-material-read	register" "$(sh "$D" egress key-material-read --register "$REG" 2>/dev/null)"
t_eq "...and prints its stamp, from this function only" "(control:admission.key-material-read mode:block verdict:block)" "$(sh "$D" egress key-material-read --register "$REG" 2>&1 >/dev/null)"
t_eq "a shadow session shadows a block row that does not keep enforcing" "shadow" "$(sh "$D" egress key-material-read --shadow 1 --register "$REG" 2>/dev/null | cut -f1)"
t_eq "...but not one that does" "block" "$(sh "$D" egress key-material-read --shadow 1 --enforcing 1 --register "$REG" 2>/dev/null | cut -f1)"
printf 'id\tmode\ttype\nadmission.softened\twarn\tadmission\n' > "$T_TMP/warnreg"
t_eq "a warn row warns" "warn" "$(sh "$D" egress softened --register "$T_TMP/warnreg" 2>/dev/null | cut -f1)"
t_eq "...and cannot loosen a rule that keeps enforcing" "block" "$(sh "$D" egress softened --enforcing 1 --register "$T_TMP/warnreg" 2>/dev/null | cut -f1)"

t_section "the failure mode, decided: an unreadable register fails closed and names its remedy"
t_eq "a missing register: block, source unreadable" "block	admission.key-material-read	unreadable" "$(sh "$D" egress key-material-read --register "$T_TMP/none" 2>/dev/null)"
t_has "...and the remedy is printed" "$(sh "$D" egress key-material-read --register "$T_TMP/none" 2>&1 >/dev/null)" "Remedy: restore standards/naming/controls.tsv"
t_eq "a rule with no row: block, source norow" "block	admission.not-a-rule	norow" "$(sh "$D" egress not-a-rule --register "$REG" 2>/dev/null)"
t_has "...and the remedy names the row to add" "$(sh "$D" egress not-a-rule --register "$REG" 2>&1 >/dev/null)" "add the row"

t_section "red then green: the self-test fails when the table is broken"
cp "$D" "$T_TMP/broken.sh"; sed 's/block)  if \[ "\$_sh" = 1 \] \&\& \[ "\$_en" != 1 \]; then _v=shadow; else _v=block; fi ;;/block)  _v=block ;;/' "$D" > "$T_TMP/broken.sh"
t_eq "the mutation changed the file" 1 "$(cmp -s "$D" "$T_TMP/broken.sh" && echo 0 || echo 1)"
t_has "a decision function that ignores the shadow session fails its own self-test" "$(sh "$T_TMP/broken.sh" --self-test 2>&1 || :)" "mismatch"

t_section "no stamp lives in a guard: the decision function prints it"
t_eq "no guard prints a control stamp" 0 "$(grep -l '(control:' "$T_ROOT"/bin/admission-*.sh "$T_ROOT/bin/library-admission.sh" | grep -vc 'admission-decide.sh' || :)"

t_section "the replay diff"
printf 's1\tr1\tallow\ns1\tr2\tblock\n' > "$T_TMP/a.tsv"; cp "$T_TMP/a.tsv" "$T_TMP/b.tsv"
t_eq "equal runs: empty diff, exit 0" 0 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"
printf 's1\tr1\tallow\ns1\tr2\tallow\n' > "$T_TMP/b.tsv"
t_eq "a moved verdict: exit 1" 1 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"
t_has "...named with both verdicts" "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" 2>&1 || :)" "DIFF	s1	r2	block	allow"
printf 's1\tr1\tallow\n' > "$T_TMP/b.tsv"
t_has "a row missing from the second run is a difference, not a pass" "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" 2>&1 || :)" "MISSING	s1	r2"
: > "$T_TMP/b.tsv"
t_eq "an empty run compares nothing: exit 2" 2 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"
t_done
