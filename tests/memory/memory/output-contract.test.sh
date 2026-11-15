#!/usr/bin/env sh
# memory.sh's output follows contracts/logging.md (harbor#771): stdout is the answer and only that; every status line
# is log-lib's, on stderr; a clean search logs nothing; a refusal is FAIL, its fix, the summary. The store is a
# fixture and the engine is never reached (HARBOR_MEMORY_BUN names a runtime that is not there).
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/memory.sh"
S="$T_TMP/store"; mkdir -p "$S"; printf '# alpha\nfindme here\n' > "$S/alpha.md"; printf '# beta\n' > "$S/beta.md"
NOBUN="$T_TMP/no-bun"
run() { env HARBOR_MEMORY_BUN="$NOBUN" sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "a search that answers: the results on stdout, an empty stderr"
t_eq "exit 0" "exit 0" "$(run --root "$S" findme)"
t_has "the hit is data" "$(OUT)" "alpha.md"
t_has "the tier line is the answer's" "$(OUT)" "memory: 1 result(s), tier grep"
t_eq "nothing is logged" "" "$(ERR)"
t_eq "a miss is still a clean answer" "exit 0" "$(run --root "$S" zznothingzz)"
t_eq "...with nothing logged" "" "$(ERR)"

t_section "a verb that needs the runtime: FAIL, its fix, the summary, exit 2"
t_eq "graph without bun exits 2" "exit 2" "$(run --root "$S" graph alpha)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the verb" "$(ERR)" '  FAIL: `graph` needs bun, which is not installed'
t_has "the next line is its fix" "$(after_fail)" "  fix: memory <terms>"
t_eq "the summary ends it" "memory: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a bad flag value is a usage error with the same shape"
t_eq "a non-numeric --limit exits 2" "exit 2" "$(run --root "$S" --limit abc findme)"
t_has "the FAIL names it" "$(ERR)" "  FAIL: --limit expects a non-negative integer, got abc"
t_has "and has a fix" "$(after_fail)" "  fix: memory --limit 10 <terms>"
t_eq "the summary ends it" "memory: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "--root with no directory exits 2" "exit 2" "$(run --root)"
t_has "and says so" "$(ERR)" "  FAIL: --root needs a directory"

t_section "no store is an empty answer (exit 0), said as a WARN with its fix"
t_eq "exit 0" "exit 0" "$(run --root "$T_TMP/none" findme)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the WARN names the path" "$(ERR)" "  WARN: no store at $T_TMP/none"
t_eq "the summary counts a warning" "memory: 0 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"
t_done
