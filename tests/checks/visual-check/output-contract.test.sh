#!/usr/bin/env sh
# visual-check.sh's output follows CONTRACTS/logging.md (harbor#771): the probe's TAG lines are said through log-lib,
# a FAIL is followed by its fix, an unavailable verifier is unchecked (D-29): a FAIL naming it, its fix, the summary and exit 3
# (never a pass), a bad argument is exit 2, and 0 / 1 are unchanged. Hermetic: a stub `node` plays the probe, so no browser is launched.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/visual-check.sh"
printf '#!/bin/sh\ncase "$2" in *bad.html) exit 1 ;; esac\n[ -z "$STUB_OUT" ] || printf "%%s\\n" "$STUB_OUT"\nexit "${STUB_RC:-0}"\n' > "$T_BIN/node"; chmod +x "$T_BIN/node"
printf '<!doctype html><style>p{color:#111}</style><p>x</p>\n' > "$T_TMP/p.html"
export HARBOR_ARCHIFY="$T_TMP/no-archify" STUB_RC=0 STUB_OUT=""
run() { sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
with() { _v="$1"; shift; ( export "$_v"; "$@" ); }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/out"; }
NL='
'

t_section "a pass: the probe's ok lines are the library's, then the summary, exit 0"
t_eq "exit 0" "exit 0" "$(with "STUB_OUT=  ok: p.html light/wide${NL}  note: 1 render(s), 0 failure(s)" run "$T_TMP/p.html")"
t_has "an ok line" "$(OUT)" "  ok: p.html light/wide"
t_has "the probe's closing line is a note" "$(OUT)" "  note: 1 render(s), 0 failure(s)"
t_eq "the summary counts the ok" "visual-check: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "no legacy PASS/FAIL double-space shape" 0 "$(OUT | grep -c '^  \(PASS\|FAIL\|ok\|SKIP\)  ')"

t_section "a failure: FAIL, its fix, the summary, exit 1"
t_eq "exit 1" "exit 1" "$(with STUB_RC=1 with "STUB_OUT=  FAIL: p.html dark/wide: 1.2:1 under 4.5:1${NL}  fix: sh bin/visual-check.sh p.html   # after repairing${NL}  ok: p.html light/wide" run "$T_TMP/p.html")"
t_has "the FAIL is counted" "$(OUT)" "  FAIL: p.html dark/wide: 1.2:1 under 4.5:1"
t_has "the next line is its fix" "$(after_fail)" "  fix: sh bin/visual-check.sh p.html"
t_eq "the summary" "visual-check: 1 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "a FAIL the probe left without a fix still gets one" "exit 1" "$(with STUB_RC=1 with "STUB_OUT=  FAIL: p.html: broken" run "$T_TMP/p.html")"
t_has "none automatic" "$(after_fail)" "  fix: none automatic — see bin/visual-check.mjs"

t_section "an unavailable verifier is unchecked (D-29), never a pass: FAIL, its fix, the summary, exit 3"
t_eq "the probe's unchecked exits 3" "exit 3" "$(with STUB_RC=3 with "STUB_OUT=  FAIL: unchecked — no playwright at /x, so nothing was judged${NL}  fix: set HARBOR_PROBE_DIR to a tree with playwright installed" run "$T_TMP/p.html")"
t_has "the FAIL line names the reason" "$(OUT)" "  FAIL: unchecked — no playwright at /x, so nothing was judged"
t_has "the next line is its fix" "$(after_fail)" "  fix: set HARBOR_PROBE_DIR to a tree with playwright installed"
t_eq "the summary counts it as a failure, so 0 still means failed is 0" "visual-check: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "the probe's usage error stays 2, not 3" "exit 2" "$(with STUB_RC=2 with "STUB_OUT=  FAIL: no such file: x${NL}  fix: sh bin/visual-check.sh <an existing .html file>" run "$T_TMP/p.html")"
mkdir -p "$T_TMP/nonode"; ln -s "$(command -v dirname)" "$T_TMP/nonode/dirname"  # the one command it runs before looking for node
ln -s "$(command -v uname)" "$T_TMP/nonode/uname"                                 # and the one pkg_hint asks for the fix line
t_eq "no node on PATH is unchecked too" "exit 3" "$(env PATH="$T_TMP/nonode" /bin/sh "$TOOL" "$T_TMP/p.html" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "that names the missing verifier" "$(OUT)" "  FAIL: unchecked — no node on PATH, so nothing was judged"
t_has "...and is followed by its fix" "$(after_fail)" "  fix: "
t_eq "an unknown flag is a usage error, exit 2, even with no node" "exit 2" "$(env PATH="$T_TMP/nonode" /bin/sh "$TOOL" --bogus >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"

t_section "--self-test: an ok per arm, the summary; a verifier that is missing is unchecked"
t_eq "exit 0" "exit 0" "$(run --self-test)"
t_has "the red arm is an ok" "$(OUT)" "  ok: #eeeeee text on #ffffff is rejected"
t_has "the cleanup arm is an ok" "$(OUT)" "  ok: every shape of archify exhaust is swept, the page is not"
t_eq "the summary is the library's" "visual-check: 3 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "a checker that passes the bad page exits 1" "exit 1" "$(printf '#!/bin/sh\nexit 0\n' > "$T_BIN/node"; run --self-test)"
t_has "its FAIL" "$(OUT)" "  FAIL: the checker passed text at 1.1:1"
t_has "and a fix line follows" "$(after_fail)" "  fix: none automatic — see"
t_eq "no browser is unchecked: exit 3" "exit 3" "$(printf '#!/bin/sh\nexit 3\n' > "$T_BIN/node"; run --self-test)"
t_has "and says so" "$(OUT)" "  FAIL: unchecked — no browser available, so the self-test judged nothing"
t_has "followed by its fix" "$(after_fail)" "  fix: sh "
t_done
