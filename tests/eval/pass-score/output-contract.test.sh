#!/usr/bin/env sh
# eval-pass-score.sh's output follows contracts/logging.md (harbor#771): every line is the log's shape, each verdict
# that blocks an install is a FAIL followed by its fix, the run ends with the summary, and the exit codes it
# reports to floor-install.sh (0 no worsening, 1 no register, 2 do not install, 3 the gate did not run) stay.
# The register is a fixture, copied beside a copy of the tool.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$T_TMP"; R="$B/repo"; mkdir -p "$R/bin" "$R/docs/explanation"
cp "$T_ROOT/bin/eval-pass-score.sh" "$T_ROOT/bin/library-log.sh" "$R/bin/"
TOOL="$R/bin/eval-pass-score.sh"
floor() { # <criticals series…>
  { printf '| | pass 1 | pass 2 | pass 3 | pass 4 |\n'
    printf '| confirmed | 10 | 11 | 12 | 13 |\n'
    if [ "$#" -gt 0 ]; then printf '| criticals | %s | %s | %s | %s |\n' "$@"; fi; } > "$R/docs/explanation/admission-baseline.md"
}
ps() { HOME="$B/h" CLAUDE_CONFIG_DIR="$B/c" sh "$TOOL" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$B/out"; }
shaped() { OUT | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |pass-score: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "a flat zero criticals series: the table as notes, the ok verdict, the summary, exit 0"
floor 0 0 0 0
t_eq "it exits 0" "exit 0" "$(ps)"
t_has "the header names the passes" "$(OUT)" "── pass-score · adversarial passes:"
t_has "the table row is a note" "$(OUT)" "  note: confirmed "
t_has "the verdict is an ok line" "$(OUT)" "  ok: VERDICT: no series shows a significant worsening."
t_eq "the summary ends it" "pass-score: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"
t_eq "stderr is empty" "" "$(cat "$B/err")"

t_section "criticals above zero: the FAIL, its fix, the summary, exit 2"
floor 0 2 3 7
t_eq "it exits 2, as floor-install reads it" "exit 2" "$(ps)"
t_has "the FAIL states the verdict" "$(OUT)" "  FAIL: VERDICT: the latest pass still reports 7 critical(s). Do not install."
t_has "the next line is its fix" "$(after_fail)" "  fix: none automatic — see docs/explanation/admission-baseline.md"
t_eq "the summary counts the failure" "pass-score: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"

t_section "decision 23: the latest adjudicated pass's open criticals gate, the found series is the signal (harbor#1149)"
floor 0 2 3 12; printf '| open criticals | - | - | - | 0 |\n' >> "$R/docs/explanation/admission-baseline.md"
t_eq "12 found, 0 open: it exits 0" "exit 0" "$(ps)"
t_has "the ok verdict names the decision" "$(OUT)" "  ok: VERDICT: no critical is open after the latest adjudicated pass (decision 23)."
t_has "...and still says how many were found" "$(OUT)" "found 12 critical(s)"
t_eq "every line is the log's shape" 0 "$(shaped)"
floor 0 2 3 12; printf '| open criticals | - | - | - | **0** |\n' >> "$R/docs/explanation/admission-baseline.md"
t_eq "a bold cell, as docs/explanation/admission-baseline.md writes the latest pass, reads the same: exit 0" "exit 0" "$(ps)"
floor 0 2 3 12; printf '| open criticals | - | - | - | 2 |\n' >> "$R/docs/explanation/admission-baseline.md"
t_eq "2 open: it exits 2" "exit 2" "$(ps)"
t_has "the FAIL counts the open ones" "$(OUT)" "  FAIL: VERDICT: the latest adjudicated pass leaves 2 critical(s) open. Do not install."
t_has "its fix names the two ways out" "$(after_fail)" "or accept it in writing as a published residual"
floor 0 2 3 12; printf '| open criticals | - | - | 0 | - |\n' >> "$R/docs/explanation/admission-baseline.md"
t_eq "an earlier complete pass does not vouch for the latest: the found series gates, exit 2" "exit 2" "$(ps)"
t_has "...with the found verdict" "$(OUT)" "the latest pass still reports 12 critical(s)"
floor 0 2 3 12; printf '| open criticals | 0 |\n' >> "$R/docs/explanation/admission-baseline.md"
t_eq "a row without one cell per pass: the gate did not run, exit 3" "exit 3" "$(ps)"
t_has "...and says so" "$(OUT)" "not one cell per pass"

t_section "no criticals row: the gate did not run, FAIL, its fix, exit 3"
floor
t_eq "it exits 3" "exit 3" "$(ps)"
t_has "the FAIL says the gate did not run" "$(OUT)" "THE GATE DID NOT RUN"
t_has "its fix reads the row" "$(after_fail)" "  fix: grep -n '^| criticals |' $R/docs/explanation/admission-baseline.md"
t_eq "the summary ends it" "pass-score: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"

t_section "no register at all: FAIL, its fix, exit 1"
rm -f "$R/docs/explanation/admission-baseline.md"
t_eq "it exits 1" "exit 1" "$(ps)"
t_has "the FAIL names the file" "$(OUT)" "  FAIL: no $R/docs/explanation/admission-baseline.md"
t_has "its fix restores it" "$(after_fail)" "  fix: git checkout -- docs/explanation/admission-baseline.md"
t_eq "the summary ends it" "pass-score: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_done
