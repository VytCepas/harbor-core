#!/usr/bin/env sh
# lint-module-shape.sh's output follows contracts/logging.md (harbor#771): stdout is the measurement and only that (a line,
# or --json); the run log is on stderr; a usage error is a FAIL, its fix, and the summary, exit 2.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/lint-module-shape.sh"; FX="$T_TMP/fx"; mkdir -p "$FX"
printf '#!/usr/bin/env sh\nalpha_one() { echo one; }\nalpha_two() { echo two; }\n' > "$FX/a.sh"
run() { sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }
LOGLINE='^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):'

t_section "classify: the measurement alone on stdout, the log on stderr"
t_eq "exit 0" "exit 0" "$(run "$FX/a.sh")"
t_eq "stdout is one measurement line" 1 "$(OUT | wc -l | tr -d ' ')"
t_has "it carries the quadrant" "$(OUT)" "files=1"
t_eq "no log line on stdout" 0 "$(OUT | grep -c "$LOGLINE")"
t_eq "the header" "── module-shape · classify 1 file(s)" "$(ERR | head -1)"
t_has "the ok line" "$(ERR)" "  ok: classified 1 file(s)"
t_eq "the summary ends stderr" "module-shape: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--json: the object alone on stdout"
t_eq "exit 0" "exit 0" "$(run --json "$FX/a.sh")"
t_has "stdout is JSON" "$(OUT)" '{"files":1,'
t_eq "the summary" "module-shape: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--seam: the verdict line on stdout"
t_eq "exit 0" "exit 0" "$(run --seam "$FX/a.sh" "$FX")"
t_has "stdout names the file" "$(OUT)" "a.sh"
t_eq "the header" "── module-shape · seam $FX/a.sh" "$(ERR | head -1)"
t_eq "the summary" "module-shape: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a usage error: FAIL, its fix, the summary, exit 2, nothing on stdout"
t_eq "an unknown flag exits 2" "exit 2" "$(run --bogus)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL" "$(ERR)" "  FAIL: unknown flag --bogus"
t_eq "its fix" "  fix: sh $TOOL --help" "$(after_fail)"
t_eq "the summary" "module-shape: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "a missing path exits 2" "exit 2" "$(run "$FX/nope.sh")"
t_has "and is named" "$(ERR)" "  FAIL: no such path: $FX/nope.sh"
t_eq "no argument exits 2" "exit 2" "$(run)"
t_has "and says so" "$(ERR)" "  FAIL: missing argument"
t_done
