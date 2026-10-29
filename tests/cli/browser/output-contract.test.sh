#!/usr/bin/env sh
# browser.sh's output follows CONTRACTS/logging.md (harbor#1149): the verbs that print data (route, doctor, a worker's
# JSON) keep stdout for it and log on stderr; the self-tests are runs and log on stdout; a refusal is FAIL, fix,
# summary, exit 1; an unavailable verifier is `skip`, the summary and the contract's exit 2, never a pass.
. "$(dirname "$0")/../../lib/core.sh"; t_init
BROWSER="$T_ROOT/bin/browser.sh"; ROUTING="$T_ROOT/CONTRACTS/browser-routing.md"
. "$T_ROOT/tests/lib/linux-sim.sh"
run() { "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }
( PATH=/usr/bin:/bin; linux_path "$T_TMP/nonode" node )  # a PATH with every tool but node

t_section "a refusal: FAIL, its fix, the summary, exit 1, stdout empty"
t_eq "an unknown verb" "exit 1" "$(run sh "$BROWSER" nonsense-verb)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names the verb" "$(ERR)" "  FAIL: unknown verb: nonsense-verb"
t_eq "the next line is its fix" "  fix: harbor browser help" "$(after_fail)"
t_eq "the last line is the summary" "browser: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "a verb with no url" "exit 1" "$(run sh "$BROWSER" probe)"
t_has "its FAIL" "$(ERR)" "  FAIL: probe wants a url"
t_has "its fix is the usage" "$(after_fail)" "  fix: harbor browser probe <url>"
t_eq "no legacy browser: prefix is left" 0 "$(ERR | grep -c '^browser: [^0-9]')"
t_eq "the gated session" "exit 1" "$(run sh "$BROWSER" session)"
t_has "its FAIL says it is GATED" "$(ERR)" "  FAIL: session is GATED and will not run"
t_has "its fix reads the router" "$(after_fail)" "Row 5"

t_section "an unavailable verifier is a skip with exit 2, and the summary says nothing failed"
t_eq "no pack worker" "exit 2" "$(run sh "$BROWSER" hosts https://example.invalid)"
t_has "the skip line names the worker" "$(ERR)" "  skip: SKIPPED — no bin/browser-hosts.mjs: a pack ships this worker"
t_eq "the summary counts no failure" "browser: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "stdout is empty" "" "$(OUT)"
# The worker present (as a pack installs it beside browser.sh), node absent (harbor#1273 moved the worker out of core).
mkdir -p "$T_TMP/pk/bin" "$T_TMP/pk/CONTRACTS"; cp "$BROWSER" "$T_ROOT/bin/log-lib.sh" "$T_TMP/pk/bin/"
cp "$ROUTING" "$T_TMP/pk/CONTRACTS/"; : > "$T_TMP/pk/bin/browser-hosts.mjs"
t_eq "no node" "exit 2" "$(run env PATH="$T_TMP/nonode" /bin/sh "$T_TMP/pk/bin/browser.sh" hosts https://example.invalid)"
t_has "the skip line names it" "$(ERR)" "  skip: SKIPPED — no node on PATH"
t_eq "the summary counts no failure" "browser: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "stdout is empty" "" "$(OUT)"

t_section "the data verbs keep stdout clean"
t_eq "route exits 0" "exit 0" "$(run sh "$BROWSER" route)"
t_eq "route is byte-identical to the contract" same "$(cmp -s "$T_TMP/out" "$ROUTING" && echo same)"
t_eq "and logs nothing" "" "$(ERR)"
t_eq "doctor --json exits 0" "exit 0" "$(run sh "$BROWSER" doctor --json)"
t_eq "its stdout opens as JSON and no log line" 1 "$(OUT | head -1 | grep -c '^{$')"
t_eq "and logs nothing" "" "$(ERR)"
t_eq "--help exits 0" "exit 0" "$(run sh "$BROWSER" --help)"
t_eq "and logs nothing" "" "$(ERR)"

t_section "--self-test is a run: its log is on stdout, the summary agrees with the exit"
HAVE_NODE=0; ! command -v node >/dev/null 2>&1 || HAVE_NODE=1
if [ "$HAVE_NODE" = 1 ]; then
  P="$T_TMP/probe"; mkdir -p "$P/node_modules/playwright" "$T_TMP/empty"
  printf '%s\n' "export const chromium = { launch: async () => { throw new Error('stub'); } };" > "$P/node_modules/playwright/index.mjs"
  t_eq "it passes" "exit 0" "$(run env HARBOR_PROBE_DIR="$P" sh "$BROWSER" --self-test)"
  t_has "the header is the library's" "$(OUT)" "── browser · self-test"
  t_has "a case is an ok line" "$(OUT)" "  ok: route prints the contract (exit 0)"
  t_eq "the summary is the last stdout line" 1 "$(OUT | tail -1 | grep -c '^browser: [0-9][0-9]* ok, 0 failed, 0 warnings$')"
  t_eq "and stderr is empty" "" "$(ERR)"
  t_eq "no PASS/FAIL words of the old shape" 0 "$(OUT | grep -c '^  PASS  ')"
else echo "  SKIP --self-test shape: no node on this host (the runner image carries it)"; fi

t_section "--self-test-live needs a storefront, and takes it from the environment or the private layer"
PV="$T_TMP/pv"; mkdir -p "$PV"
t_eq "with none it is a skip, exit 2" "exit 2" "$(run env HARBOR_SCOPE_PRIVATE="$PV" sh "$BROWSER" --self-test-live)"
t_has "the skip says where to set it" "$(OUT)" "  skip: SKIPPED — no storefront to load: set HARBOR_BROWSER_LIVE_URL, or browser_live_url in harbor.toml"
t_eq "and the summary counts no failure" "browser: 0 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
printf 'browser_live_url = "https://shop.example.invalid"\n' > "$PV/harbor.toml"
run env HARBOR_SCOPE_PRIVATE="$PV" HARBOR_PROBE_DIR="$T_TMP/empty" PATH="$T_TMP/nonode" /bin/sh "$BROWSER" --self-test-live >/dev/null
t_has "browser_live_url in harbor.toml is the storefront" "$(OUT)" "  note: needs network; url: https://shop.example.invalid"
t_has "an unavailable backend is a skip" "$(OUT)" "  skip: backend unavailable"
run env HARBOR_SCOPE_PRIVATE="$PV" HARBOR_BROWSER_LIVE_URL=https://other.example.invalid HARBOR_PROBE_DIR="$T_TMP/empty" PATH="$T_TMP/nonode" /bin/sh "$BROWSER" --self-test-live >/dev/null
t_has "HARBOR_BROWSER_LIVE_URL wins over the file" "$(OUT)" "url: https://other.example.invalid"
t_done
