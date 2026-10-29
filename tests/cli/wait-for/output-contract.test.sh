#!/usr/bin/env sh
# wait-for's output follows CONTRACTS/logging.md (harbor#771): every line is log-lib's, on stderr (stdout is empty,
# the predicate's output is discarded); the exit codes 0 met, 2 usage, 3 gave up, 4 broken predicate are unchanged;
# a FAIL is followed by its fix and the run ends with the summary. Deadlines are one second.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/wait-for"
run() { sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "a condition met: a header, an ok line naming the witness value, the summary, exit 0"
t_eq "exit 0" "exit 0" "$(run -t 5 -i 1 -n demo -w 'echo seen' -- true)"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the header carries the label" "── wait-for · demo" "$(ERR | head -1)"
t_has "the ok line carries the witness" "$(ERR)" "  ok: MET after 0s, 1 attempt(s). observed: seen"
t_eq "the summary ends it" "wait-for: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy [HH:MM:SS] line is left" 0 "$(ERR | grep -c '^\[')"

t_section "no witness is said, not hidden"
run -t 5 -i 1 -- true >/dev/null
t_has "a note" "$(ERR)" "  note: no -w witness given: a frozen predicate cannot be detected"
run -q -t 5 -i 1 -- true >/dev/null
t_eq "-q silences notes but not the verdict" 0 "$(ERR | grep -c 'no -w witness')"
t_has "...the verdict stays" "$(ERR)" "  ok: MET"

t_section "the deadline: FAIL, its fix, the summary, exit 3"
t_eq "exit 3" "exit 3" "$(run -t 1 -i 1 -n slow -w 'echo same' -- false)"
t_has "the last witness is a note" "$(ERR)" "last observed value: same"
t_has "the FAIL says it gave up" "$(ERR)" "  FAIL: gave up after "
t_has "the next line is a longer deadline" "$(after_fail)" "  fix: wait-for -t 3600 -n slow -- false"
t_eq "the summary counts the failure" "wait-for: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a predicate that cannot run: FAIL, fix, summary, exit 4 without waiting"
t_eq "exit 4" "exit 4" "$(run -t 30 -i 1 -- /nonexistent/predicate)"
t_has "the FAIL" "$(ERR)" "  FAIL: predicate broken on first evaluation (exit 127): not waiting"
t_has "the fix runs it by hand" "$(after_fail)" "  fix: /nonexistent/predicate"
t_eq "the summary" "wait-for: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a frozen witness is a WARN with a fix, and the wait goes on"
t_eq "the deadline still ends it with exit 3" "exit 3" "$(run -t 3 -i 1 -s 1 -w 'echo frozen' -- false)"
t_has "the STALL WARN" "$(ERR)" "  WARN: STALL: observed value unchanged for "
t_has "...with a fix naming the witness" "$(ERR)" "  fix: sh -c '<the -w witness>'"
t_eq "the summary counts the warning and the failure" "wait-for: 0 ok, 1 failed, 1 warnings" "$(ERR | tail -1)"

t_section "a usage error is exit 2, FAIL, fix, summary"
t_eq "a non-integer -t exits 2" "exit 2" "$(run -t x -- true)"
t_has "the FAIL" "$(ERR)" "  FAIL: -t must be an integer"
t_eq "the fix is the help" "  fix: wait-for -h" "$(after_fail)"
t_eq "the summary" "wait-for: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "an unknown option exits 2" "exit 2" "$(run -Z -- true)"
t_has "and says which" "$(ERR)" "  FAIL: unknown option -Z"
t_done
