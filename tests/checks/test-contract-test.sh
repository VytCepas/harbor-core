#!/usr/bin/env sh
# The test contract (harbor#734): six rules, each naming its mechanism, cited by tests/README.md,
# and `just test` (tests/lib/run.sh) summing every suite into the one line a fleet runner reads.
. "$(dirname "$0")/../lib/core.sh"; t_init
C="$T_ROOT/CONTRACTS/test-contract.md"
rc() { "$@" > "$T_TMP/out" 2> "$T_TMP/err"; echo "exit $?"; }  # the exit; output in out and err
last() { tail -1 "$T_TMP/out"; }
rule() { awk -v n="$1" '/^[0-9]\. \*\*/ { on = (substr($0, 1, 1) == n) } /^## / { on = 0 } on' "$C"; }  # <n>

t_section "the contract states six rules, each with its mechanism"
t_eq "the contract exists" yes "$([ -f "$C" ] && echo yes)"
t_eq "exactly six numbered rules (harbor#734's verify)" 6 "$(grep -c '^[0-9]\. \*\*' "$C" 2>/dev/null)"
i=1
for want in 'Hermetic by default' 'Exact exit codes' 'One summary line per suite' \
            "in the repo's CI manifest" 'A changed test shows it can fail' 'separate, read-only tier'; do
  t_has "rule $i is the #734 rule" "$(rule $i | head -1)" "$want"
  t_has "rule $i names Harbor's mechanism" "$(rule $i)" '*Harbor:*'
  t_has "rule $i names the Python mechanism" "$(rule $i)" '*Python:*'
  i=$((i + 1))
done
t_has "rule 1 names the inherited HARBOR_* class" "$(rule 1)" 'HARBOR_*'
t_has "rule 1 sends that class to its fix" "$(rule 1)" 'harbor#773'
t_has "rule 3 states the line's grammar" "$(rule 3)" '^[A-Za-z0-9._-]+: [0-9]+ passed, [0-9]+ failed$'
t_has "rule 6 names the live command" "$(rule 6)" 'harbor check --live'
_dead=''
for p in $(grep -oE '\]\(\.\.?/[^)#]*' "$C" | sed 's/^](//' | sort -u); do
  [ -e "$T_ROOT/CONTRACTS/$p" ] || _dead="$_dead $p"
done
t_eq "every mechanism the contract links resolves" "" "$_dead"
_off=''
for s in $(sed 's/#.*//' "$T_ROOT/CONTRACTS/suites.txt" | awk NF); do
  grep -qE '^[[:space:]]*\. .*core\.sh' "$T_ROOT/$s" 2>/dev/null && continue
  grep -qE ': %[sd] passed, %[sd] failed' "$T_ROOT/$s" 2>/dev/null || _off="$_off $s"
done
t_eq "every manifest suite prints the rule 3 line: on core.sh, or by its own printf" "" "$_off"
t_has "tests/README.md cites it as Harbor's implementation" "$(cat "$T_ROOT/tests/README.md")" 'CONTRACTS/test-contract.md'
t_has "CONTRACTS/README.md indexes it" "$(cat "$T_ROOT/CONTRACTS/README.md")" '(./test-contract.md)'

# A fake root: the real runner and harness, a manifest of planted suites.
R="$T_TMP/root"; mkdir -p "$R/tests/lib" "$R/tests/x" "$R/CONTRACTS"
cp "$T_ROOT/tests/lib/run.sh" "$T_ROOT/tests/lib/core.sh" "$R/tests/lib/" 2>/dev/null
plant() { printf '#!/bin/sh\n%s\n' "$2" > "$R/tests/x/$1-test.sh"; }  # <name> <body>
plant pass "echo 'pass-test: 3 passed, 0 failed'"
plant fail "echo 'fail-test: 1 passed, 2 failed'; exit 1"
plant crash "echo 'boom' >&2; exit 3"
plant liar "echo 'liar-test: 2 passed, 0 failed'; exit 1"
plant silent "exit 0"
plant late "echo 'late-test: 9 passed, 9 failed'; echo 'late-test: 4 passed, 0 failed'"
printf '%s\n' '. "$(dirname "$0")/../lib/core.sh"; t_init' 't_section real' 't_eq one 1 1' 't_eq two 2 2' 't_done' \
  > "$R/tests/x/core-test.sh"
printf '# a comment\n\ntests/x/pass-test.sh\ntests/x/core-test.sh  # trailing\n' > "$R/CONTRACTS/suites.txt"
for s in fail crash liar silent late; do printf 'tests/x/%s-test.sh\n' "$s" >> "$R/CONTRACTS/suites.all"; done
RUN="$R/tests/lib/run.sh"

t_section "just test: every manifest suite, then one total line"
t_eq "a green manifest exits 0" "exit 0" "$(rc sh "$RUN")"
t_eq "the total is the last line, summed across suites" "harbor: 5 passed, 0 failed" "$(last)"
t_has "it ran the real harness through the manifest" "$(cat "$T_TMP/out")" 'core-test: 2 passed, 0 failed'
t_eq "each suite's own line is printed once" 1 "$(grep -c '^pass-test: 3 passed, 0 failed$' "$T_TMP/out")"
t_eq "a comment in the manifest is not a suite" 2 "$(grep -c '^── ' "$T_TMP/out")"
t_eq "a suite named alone runs alone" "exit 0" "$(rc sh "$RUN" pass)"
t_eq "and totals itself" "harbor: 3 passed, 0 failed" "$(last)"
t_eq "a suite outside the manifest is refused" "exit 2" "$(rc sh "$RUN" tests/x/fail-test.sh)"
t_has "the refusal names it" "$(cat "$T_TMP/err")" 'is not a suite in CONTRACTS/suites.txt'

cat "$R/CONTRACTS/suites.all" >> "$R/CONTRACTS/suites.txt"
t_section "a red suite reddens the total, and a crash is never read as a pass"
t_eq "one red suite exits 1" "exit 1" "$(rc sh "$RUN" pass fail)"
t_eq "its failures are added" "harbor: 4 passed, 2 failed" "$(last)"
t_has "the FAIL names the suite and keeps its output" "$(cat "$T_TMP/err")" 'tests/x/fail-test.sh exited 1 — its full output is kept at'
t_has "a fix line follows" "$(cat "$T_TMP/err")" '  fix: none automatic — see tests/x/fail-test.sh'
_kept="$(sed -n 's/.*its full output is kept at //p' "$T_TMP/err" | head -1)"
t_has "the kept output is the suite's" "$(cat "$_kept" 2>/dev/null)" 'fail-test: 1 passed, 2 failed'
t_eq "a crash with no summary exits 1" "exit 1" "$(rc sh "$RUN" crash)"
t_eq "and counts one failure" "harbor: 0 passed, 1 failed" "$(last)"
t_has "and says it printed no summary" "$(cat "$T_TMP/err")" 'tests/x/crash-test.sh printed no summary line'
t_eq "a non-zero exit that counted nothing exits 1" "exit 1" "$(rc sh "$RUN" liar)"
t_eq "and counts one failure" "harbor: 2 passed, 1 failed" "$(last)"
t_eq "exit 0 with no summary line exits 1" "exit 1" "$(rc sh "$RUN" silent)"
t_eq "and counts one failure" "harbor: 0 passed, 1 failed" "$(last)"
t_eq "a suite's last summary line is its count" "exit 0" "$(rc sh "$RUN" late)"
t_eq "not an earlier one" "harbor: 4 passed, 0 failed" "$(last)"

t_section "the justfile's test recipe is the runner"
if command -v just >/dev/null 2>&1; then
  t_eq "just test runs the manifest at its working directory" "exit 1" \
    "$(rc just --justfile "$T_ROOT/justfile" --working-directory "$R" test)"
  t_eq "and ends with the runner's total" "harbor: 12 passed, 5 failed" "$(last)"
  t_eq "just test <name> runs that suite" "exit 0" \
    "$(rc just --justfile "$T_ROOT/justfile" --working-directory "$R" test pass)"
  t_eq "and totals it" "harbor: 3 passed, 0 failed" "$(last)"
else
  # No just here (the hosted runner has none), so the recipe cannot be run. Its text can still be held
  # to the contract, and the section must assert something or it fails as vacuous (core.sh _t_close).
  echo "  SKIP running the justfile recipe: no just on this host, so its text is checked instead"
  t_has "the test recipe hands its suites to the runner" \
    "$(awk '/^test \*SUITES:/ { getline; print; exit }' "$T_ROOT/justfile")" "sh tests/lib/run.sh {{ SUITES }}"
fi
t_done
