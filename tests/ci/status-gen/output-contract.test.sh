#!/usr/bin/env sh
# status-generate.sh's output follows contracts/logging.md (harbor#771): stdout is the generated docs/generated/status.md text or the
# JSON and only that; the run log is on stderr; a stale or unmeasured docs/generated/status.md is a FAIL or WARN with its fix, and
# the run ends with the summary. Suites are three-line fakes in a fixture tree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_IN_SUITE HARBOR_SUITE_COUNTS  # t_init keeps the re-entry marker; these runs must reach the run branch
P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; R="$P/repo"; mkdir -p "$R/bin" "$R/build"
cp "$T_ROOT/bin/status-generate.sh" "$T_ROOT/bin/library-log.sh" "$R/bin/"
mk_suite() { printf '#!/usr/bin/env sh\necho "%s: %s passed, 0 failed"\n' "$2" "$3" > "$R/bin/$1"; }
mk_suite floor-test.sh floor-test 100; mk_suite normalize-test.sh normalize-test 20; mk_suite marker-test.sh marker-test 8
TOOL="$R/bin/status-generate.sh"
run() { HARBOR_ROOT="$R" sh "$TOOL" "$@" >"$P/out" 2>"$P/err"; echo "exit $?"; }
OUT() { cat "$P/out"; }; ERR() { cat "$P/err"; }
after() { awk -v p="$1" '$0 ~ p { f = 1; next } f { print; exit }' "$P/err"; }
LOGLINE='^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):'

t_section "--apply: the write is an ok line on stderr, stdout is empty"
t_eq "exit 0" "exit 0" "$(run --apply)"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the header" "── status-gen · apply" "$(ERR | head -1)"
t_has "the write is an ok line" "$(ERR)" "  ok: wrote $R/docs/generated/status.md"
t_eq "the summary ends stderr" 1 "$(ERR | tail -1 | grep -c '^status-gen: [0-9][0-9]* ok, 0 failed, [0-9]* warnings$')"
t_eq "docs/generated/status.md exists" yes "$([ -s "$R/docs/generated/status.md" ] && echo yes || echo no)"

t_section "--check on a current file: ok; on a stale one: FAIL, its fix, exit 1"
t_eq "current exits 0" "exit 0" "$(run --check)"
t_has "and says so" "$(ERR)" "  ok: docs/generated/status.md is current"
mk_suite floor-test.sh floor-test 101; rm -f "$R/build/suite-counts.tsv"
t_eq "stale exits 1" "exit 1" "$(run --check)"
t_has "the FAIL names the file" "$(ERR)" "  FAIL: docs/generated/status.md is stale ($R/docs/generated/status.md)"
t_eq "its fix" "  fix: sh $TOOL --apply" "$(after '^  FAIL: docs/generated/status.md is stale')"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the summary counts it" 1 "$(ERR | tail -1 | grep -c '^status-gen: 0 ok, 1 failed, 0 warnings$')"

t_section "the default mode: the document alone on stdout"
t_eq "exit 0" "exit 0" "$(run)"
t_eq "stdout is the document" "# STATUS" "$(OUT | head -1 | cut -c1-8)"
t_eq "no log line is mixed into it" 0 "$(OUT | grep -c "$LOGLINE")"
t_has "the log is on stderr" "$(ERR)" "── status-gen · generate"
t_eq "the summary ends stderr" 1 "$(ERR | tail -1 | grep -c '^status-gen: [0-9][0-9]* ok, 0 failed, [0-9]* warnings$')"

t_section "--json-fast: the object alone on stdout"
t_eq "exit 0" "exit 0" "$(run --json-fast)"
t_has "stdout is JSON" "$(OUT)" '"counted"'
t_eq "no log line on stdout" 0 "$(OUT | grep -c "$LOGLINE")"
t_eq "the summary ends stderr" 1 "$(ERR | tail -1 | grep -c '^status-gen: [0-9][0-9]* ok, 0 failed, [0-9]* warnings$')"

t_section "a suite that prints no count: a WARN with its fix, then --apply refuses with a FAIL"
mk_suite floor-test.sh floor-test 100; rm -f "$R/build/suite-counts.tsv"; run --apply >/dev/null
cp "$R/docs/generated/status.md" "$P/good.md"
printf '#!/usr/bin/env sh\necho "no count here"\n' > "$R/bin/normalize-test.sh"; rm -f "$R/build/suite-counts.tsv"
t_eq "--apply exits 1" "exit 1" "$(run --apply)"
t_has "the WARN names the suite" "$(ERR)" "  WARN: bin/normalize-test.sh printed NO parseable assertion count"
t_eq "its fix" "  fix: sh $R/bin/normalize-test.sh" "$(after '^  WARN: bin/normalize-test.sh')"
t_has "the FAIL says docs/generated/status.md is untouched" "$(ERR)" "  FAIL: an assertion count is not a positive integer: docs/generated/status.md left UNCHANGED"
t_eq "the summary counts 1 failed and the warning" 1 "$(ERR | tail -1 | grep -c '^status-gen: [0-9][0-9]* ok, 1 failed, 1 warnings$')"
t_exit "docs/generated/status.md survives" 0 cmp -s "$R/docs/generated/status.md" "$P/good.md"

t_section "a bad HARBOR_SUITE_COUNTS: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(HARBOR_SUITE_COUNTS=zz run --check)"
t_has "the FAIL" "$(ERR)" "  FAIL: HARBOR_SUITE_COUNTS: zz is not <suite>=<count>"
t_eq "its fix" "  fix: unset HARBOR_SUITE_COUNTS" "$(after '^  FAIL: HARBOR_SUITE_COUNTS')"
t_section "a core-only checkout (a layer table, no docs/generated/status.md) writes to the state directory, never the tree (harbor#1275)"
C="$P/core"; SD="$P/state"; mkdir -p "$C/bin" "$C/contracts" "$SD"
cp "$T_ROOT/bin/status-generate.sh" "$T_ROOT/bin/library-log.sh" "$C/bin/"
for _s in floor-test normalize-test marker-test; do printf '#!/usr/bin/env sh\necho "%s: 7 passed, 0 failed"\n' "$_s" > "$C/bin/$_s.sh"; done
printf 'path\tlayer\tnote\nbin/\tcore\t\nSTATUS.md\tdev\t\n' > "$C/contracts/layers.tsv"
corerun() { HARBOR_ROOT="$C" HARBOR_STATUS_DIR="$SD" sh "$C/bin/status-generate.sh" "$@" >"$P/out" 2>"$P/err"; echo "exit $?"; }
t_eq "--apply exits 0" "exit 0" "$(corerun --apply)"
t_eq "docs/generated/status.md is in the state directory" yes "$([ -s "$SD/status/docs/generated/status.md" ] && echo yes || echo no)"
t_eq "the tree gained no docs/generated/status.md and no build/" 0 "$(find "$C" \( -name docs/generated/status.md -o -name 'docs/generated/status.md.tmp.*' -o -name build \) | wc -l | tr -d ' ')"
t_eq "--check reads the state directory's file" "exit 0" "$(corerun --check-fast)"
t_eq "a dev checkout that lost its docs/generated/status.md can force the tree" "exit 0" "$(HARBOR_STATUS_IN_TREE=1 corerun --apply)"
t_eq "...and then the tree has it" yes "$([ -s "$C/docs/generated/status.md" ] && echo yes || echo no)"
t_done
