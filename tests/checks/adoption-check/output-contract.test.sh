#!/usr/bin/env sh
# adoption-check.sh's output follows CONTRACTS/logging.md (harbor#771): every vendored asset is an ok line, a gap is a
# FAIL then its fix, and the run ends with the summary. A fixture tree stands in for vendor/skills.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$T_TMP/r"; mkdir -p "$R/bin" "$R/vendor/skills/alpha" "$R/vendor/skills/beta"
cp "$T_ROOT/bin/adoption-check.sh" "$T_ROOT/bin/log-lib.sh" "$R/bin/"
doc() { printf '# fixture\n\n| Skill | Verdict |\n|---|---|\n%s' "$1" > "$R/vendor/skills/PROVENANCE.md"; }
run() { sh "$R/bin/adoption-check.sh" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/out"; }

t_section "full coverage: ok lines, the summary, exit 0"
doc '| alpha | adapted |
| beta | adapted |
'
t_eq "exit 0" "exit 0" "$(run)"
t_eq "the header" "── adoption-check · vendor/skills against PROVENANCE.md" "$(OUT | head -1)"
t_has "an asset is an ok line" "$(OUT)" "  ok: alpha has an intake row"
t_eq "the summary ends it" "adoption-check: 2 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(ERR)"

t_section "a vendored directory with no row: FAIL, its fix, exit 1"
doc '| alpha | adapted |
'
t_eq "exit 1" "exit 1" "$(run)"
t_has "the FAIL names the asset" "$(OUT)" "  FAIL: beta is vendored with NO intake row"
t_has "the next line is its fix" "$(after_fail)" "  fix: add a '| beta | … |' row to vendor/skills/PROVENANCE.md"
t_eq "the summary counts it" "adoption-check: 1 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "no legacy prefix is left" 0 "$(OUT | grep -c '^adoption-check: [^0-9]')"

t_section "a row with no directory: FAIL, its fix"
doc '| alpha | adapted |
| beta | adapted |
| gamma | adapted |
'
t_eq "exit 1" "exit 1" "$(run)"
t_has "the FAIL names the row" "$(OUT)" "  FAIL: PROVENANCE.md has a row for gamma, which is not vendored here"
t_has "its fix" "$(after_fail)" "  fix: delete the 'gamma' row"

t_section "no PROVENANCE.md: FAIL, a no-fix line, the summary"
rm "$R/vendor/skills/PROVENANCE.md"
t_eq "exit 1" "exit 1" "$(run)"
t_has "the FAIL" "$(OUT)" "  FAIL: no vendor/skills/PROVENANCE.md"
t_has "the fix" "$(after_fail)" "  fix: none automatic — see"
t_eq "the summary" "adoption-check: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_done
