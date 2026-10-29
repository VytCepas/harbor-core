#!/usr/bin/env sh
# plan-status.sh's output follows CONTRACTS/logging.md (harbor#771): --summary's stdout is the counts line lint T1c
# reads and only that; the run log is on stderr; a stale PLAN.md or a missing plan is a FAIL with its fix; the run
# ends with the summary. A fixture plan stands in for harbor-build-tickets.md.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/plan-status.sh"; P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
PLAN="$P/tickets.md"; OUT="$P/derived.md"; : > "$P/present.txt"
printf '## X · fixture\n\n**Z1 · built** — effort S\n- Evidence: %s\n\n**Z2 · not built** — effort S\n- Evidence: %s\n' "$P/present.txt" "$P/absent.txt" > "$PLAN"
run() { HARBOR_PLAN_SRC="${SRC:-$PLAN}" HARBOR_PLAN_OUT="$OUT" sh "$TOOL" "$@" >"$P/out" 2>"$P/err"; echo "exit $?"; }
O() { cat "$P/out"; }; E() { cat "$P/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$P/err"; }

t_section "--summary: the counts line alone on stdout, the log on stderr"
t_eq "exit 0" "exit 0" "$(run --summary)"
t_eq "stdout is the counts line" "plan: 1 done, 1 open, 0 UNDECLARED, 0 host-dependent, 0 void, of 2 ticket(s)" "$(O)"
t_eq "the header" "── plan-status · summary" "$(E | head -1)"
t_eq "the summary ends stderr" "plan-status: 1 ok, 0 failed, 0 warnings" "$(E | tail -1)"

t_section "write: an ok line, then --check agrees"
t_eq "exit 0" "exit 0" "$(run)"
t_has "the ok line" "$(E)" "  ok: wrote "
t_eq "stdout is empty" "" "$(O)"
t_eq "the summary ends the write run" "plan-status: 1 ok, 0 failed, 0 warnings" "$(E | tail -1)"
t_eq "--check passes" "exit 0" "$(run --check)"
t_has "and says current" "$(E)" "is current"

t_section "--check on a stale file: FAIL, its fix, exit 1"
printf '\n**Z3 · added later** — effort S\n- Evidence: %s\n' "$P/present.txt" >> "$PLAN"
t_eq "exit 1" "exit 1" "$(run --check)"
t_has "the FAIL" "$(E)" "is stale"
t_has "its fix" "$(after_fail)" "  fix: sh $TOOL"
t_eq "the summary" "plan-status: 0 ok, 1 failed, 0 warnings" "$(E | tail -1)"

t_section "no plan: FAIL, its fix, exit 1"
SRC="$P/nope.md"; t_eq "exit 1" "exit 1" "$(run --summary)"; unset SRC
t_has "the FAIL" "$(E)" "  FAIL: no plan at"
t_has "its fix" "$(after_fail)" "  fix: git -C"
t_eq "stdout is empty" "" "$(O)"

t_section "an unknown flag: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(run --bogus)"
t_has "the FAIL" "$(E)" "  FAIL: unknown flag --bogus"
t_eq "its fix" "  fix: sh $TOOL --help" "$(after_fail)"
t_done
