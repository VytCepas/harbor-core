#!/usr/bin/env sh
# doc-isa-index.sh's output follows contracts/logging.md (harbor#771): the index goes to a file, the run is log-lib's, and
# a refusal is FAIL, its fix, the summary. Everything is a fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/doc-isa-index.sh"; STORE="$T_TMP/WORK"; OUTF="$T_TMP/isa-index.md"; mkdir -p "$STORE"
run() { env HARBOR_DOC_ISA_STORE="$STORE" HARBOR_DOC_ISA_OUT="$OUTF" sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }

t_section "a write run: an ok line and the summary, no legacy shape"
t_eq "exit 0" "exit 0" "$(run)"
t_has "the ok line says what was written" "$(OUT)" "  ok: wrote "
t_eq "the summary is last" "isa-index: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "the old bare 'wrote' line is gone" 0 "$(OUT | grep -c '^wrote ')"

t_section "--summary is a run too"
t_eq "exit 0" "exit 0" "$(run --summary)"
t_has "the count is an ok line" "$(OUT)" "  ok: 0 ISA run(s) in "
t_eq "the summary is last" "isa-index: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"

t_section "an unknown flag: FAIL, its fix, the summary, exit 2"
t_eq "exit 2" "exit 2" "$(run --wat)"
t_has "the FAIL names the flag" "$(OUT)" "  FAIL: unknown flag --wat"
t_eq "the next line is its fix" "  fix: sh bin/doc-isa-index.sh --help" "$(OUT | awk '/^  FAIL:/ { f = 1; next } f { print; exit }')"
t_eq "the summary ends it" "isa-index: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(ERR)"
t_done
