#!/usr/bin/env sh
# memory-lint.sh's output follows contracts/logging.md (harbor#771): stdout is the findings (or the JSON) and only
# that; the verdict is log-lib's, on stderr; a FAIL is followed by its fix and the run ends with the summary, whose
# exit agrees. The store is a fixture; nothing reads the operator's.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/memory-lint.sh"
BAD="$T_TMP/bad"; OK="$T_TMP/ok"; mkdir -p "$BAD" "$OK"
printf '# a\n\nsee [[no-such-note]]\n' > "$BAD/a.md"; printf '# b\n' > "$BAD/b.md"
printf '# c\n\nsee [[d]]\n' > "$OK/c.md"; printf '# d\n' > "$OK/d.md"
run() { sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "--strict over a rotten store: the finding on stdout, FAIL then fix then the summary on stderr"
t_eq "exit 1" "exit 1" "$(run --root "$BAD" --strict)"
t_has "the finding is data on stdout" "$(OUT)" "DANGLING  a.md:3 (wikilink) -> no-such-note"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -c '^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):')"
t_has "the header names the store" "$(ERR | head -1)" "── memory-lint · 2 note(s) in $BAD"
t_has "the FAIL says what failed" "$(ERR)" "  FAIL: 1 dangling reference(s)"
t_eq "the next line is its fix" "  fix: write the note each DANGLING line names, or drop the link" "$(after_fail)"
t_eq "the summary ends it and counts the failure" "memory-lint: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "the old stdout summary is gone" 0 "$(OUT | grep -c '^memory-lint:')"

t_section "without --strict the same finding is a WARN that cannot change the exit"
t_eq "exit 0" "exit 0" "$(run --root "$BAD")"
t_has "a WARN, with its fix" "$(ERR)" "  WARN: 1 dangling reference(s)"
t_eq "the summary counts a warning, not a failure" "memory-lint: 0 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"

t_section "a healthy store: ok, exit 0"
t_eq "exit 0 under --strict" "exit 0" "$(run --root "$OK" --strict)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "an ok line says what held" "$(ERR)" "  ok: no dangling reference, dead path or slug collision"
t_eq "the summary" "memory-lint: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--json: stdout is the JSON and only that"
t_eq "exit 0" "exit 0" "$(run --root "$BAD" --json)"
t_eq "stdout parses as one JSON document" "1" "$(OUT | jq -s 'length')"
t_eq "and carries the finding" "no-such-note" "$(OUT | jq -r '.dangling[0].target')"
t_eq "the log is still on stderr" "memory-lint: 0 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"

t_section "a usage error: FAIL, its fix, the summary, exit 2, nothing on stdout"
t_eq "a non-numeric --stale-days exits 2" "exit 2" "$(run --root "$OK" --stale-days abc)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the value" "$(ERR)" "  FAIL: --stale-days expects a non-negative integer, got abc"
t_has "the next line is a fix" "$(after_fail)" "  fix: sh bin/memory-lint.sh"
t_eq "the summary ends it" "memory-lint: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no store exits 2" "exit 2" "$(run --root "$T_TMP/nope")"
t_has "and says where" "$(ERR)" "  FAIL: no store at $T_TMP/nope"
t_done
