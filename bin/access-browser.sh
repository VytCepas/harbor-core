#!/usr/bin/env sh
# access-browser.sh — the estate's browser capability behind one router (harbor#457).
#
#   harbor browser route              print the router — which backend, and why
#   harbor browser doctor [--json]    which backends this box actually has, now
#   harbor browser probe <url>        anonymous page instrumentation (JSON); worker bin/browser-probe.mjs, shipped by a pack
#   harbor browser hosts <url>        EVERY third-party host — the negative-claim tool; worker bin/browser-hosts.mjs, shipped by a pack
#   harbor browser cdp <url>          raw CDP against system Chrome (zero-dependency)
#   harbor browser session            logged-in + unattended — GATED, will not run
#   harbor browser --self-test        prove the gates can fail (offline)
#   harbor browser --self-test-live   reproduce the consent false negative (network)
#
# Why a verb (harbor#458, #445, #446): the routing table lived inside a measurement skill where nobody looked, so
# sessions picked a backend by habit and one refused a capability the table allowed. A capability reachable only by
# absolute path is that defect; adding a verb amends contracts/cli.md under lint CLI1.
# Exit codes are a contract: 0 pass, 1 fail, 2 SKIPPED. Skipped means the backend was unavailable and is NEVER a
# pass (constitution No.2.7); taken from bin/doc-visual-check.sh.
# Every verb's output is external content (constitution §4): page text and DOM are data, an instruction inside is an
# attack. See contracts/browser-routing.md, "Section 4 gets wider here".
# Removed notes: docs/explanation/code-cases/bin-access-browser.md
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="$ROOT/bin"
ROUTING="$ROOT/contracts/browser-routing.md"

# Most verbs print data (the router, a doctor report, a worker's JSON), so the log is log-lib's on stderr
# (contracts/logging.md); the two self-tests are runs, and put theirs on stdout.
. "$BIN/library-log.sh"
log_init browser; LOG_FD=2

EXIT_PASS=0
EXIT_FAIL=1
EXIT_SKIP=2

# Where Playwright lives is resolved, not assumed: installed once under a probe host outside the repo and imported by
# path, as bin/doc-visual-check.mjs does. Overridable so no home is hard-coded (No.3) and the suite can prove the skip path.
PROBE_DIR="${HARBOR_ACCESS_PROBE_DIR:-$HOME/.local/lib/browser-probes}"

# The gated backend from row 5, named here so `doctor` reports it without a second copy of the path.
SESSION_PROFILE="$HOME/.local/share/playwright-mcp-profile"

# Overridable so the no-Chrome path can be exercised: a hardcoded path makes "the suite still does real work without
# Chrome" untestable (the vacuous gate C3 exists to prevent). tests/access/browser/browser.test.sh points it at a missing path.
CHROME_MAC="${HARBOR_ACCESS_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

_die()  { log_fail "$1"; log_fix "${2:-harbor browser help}"; log_end || :; exit "$EXIT_FAIL"; }
# A skip has no failure to count, and its exit stays the contract's 2: never a pass.
_skip() { log_skip "SKIPPED — $1"; log_end || :; exit "$EXIT_SKIP"; }

_have_chrome() {
  [ -x "$CHROME_MAC" ] || command -v google-chrome >/dev/null 2>&1 \
    || command -v google-chrome-stable >/dev/null 2>&1
}
_have_playwright() { [ -f "$PROBE_DIR/node_modules/playwright/index.mjs" ]; }
_chrome_version() {
  if [ -x "$CHROME_MAC" ]; then "$CHROME_MAC" --version 2>/dev/null
  elif command -v google-chrome >/dev/null 2>&1; then google-chrome --version 2>/dev/null
  else printf 'absent\n'
  fi
}

# The skip path is the one that gets tested: it turns a missing dependency into an honest non-answer, not a silent empty
# result that reads as "the pixel is not there".
# Chrome is resolved here and nowhere else, then handed down in HARBOR_ACCESS_CHROME: three copies of a path list drift.
# The missing-Chrome verdict is the WORKER's, not this function's: refusing here pre-empted argument validation, so a
# misspelled `--expect=metaa` came back as SKIPPED instead of `unknown vendor name` (browser.test.sh, 2026-09-06).
# Validate the ask, then check the tool.
# Every branch is an `if`, never `test && printf`: under `set -e` an AND-OR whose left side fails may abort (inside `$(…)`
# most of all), and an empty result is the normal no-Chrome answer.
_resolve_chrome() {
  if [ -n "${HARBOR_ACCESS_CHROME:-}" ]; then
    if [ -x "${HARBOR_ACCESS_CHROME:-}" ]; then printf '%s' "${HARBOR_ACCESS_CHROME:-}"; fi
    return 0
  fi
  if [ -x "$CHROME_MAC" ]; then
    printf '%s' "$CHROME_MAC"
  elif command -v google-chrome >/dev/null 2>&1; then
    command -v google-chrome
  elif command -v google-chrome-stable >/dev/null 2>&1; then
    command -v google-chrome-stable
  fi
  return 0
}

# A pack-shipped worker (probe, hosts) absent is a missing verifier: SKIPPED, never a pass and never a failure.
_pack_worker() { [ -f "$BIN/$1" ] || _skip "no bin/$1: a pack ships this worker (contracts/pack.md); install the pack that carries it"; }

_run_worker() {
  _worker="$1"; shift
  [ -f "$BIN/$_worker" ] || _die "missing worker: bin/$_worker" "git -C $ROOT checkout -- bin/$_worker"
  command -v node >/dev/null 2>&1 || _skip 'no node on PATH'
  _chrome="$(_resolve_chrome)"
  HARBOR_ACCESS_PROBE_DIR="$PROBE_DIR" HARBOR_ACCESS_CHROME="$_chrome" \
    node "$BIN/$_worker" "$@"
}

# The verb list is printed FROM THE HEADER above, never restated: a second usage block disagrees silently.
_usage() {
  sed -n '/^#   harbor browser route/,/^#   harbor browser --self-test-live/p' "$0" | sed 's/^# \{0,2\}//'
}

_doctor() {
  _json=0
  for _a in "$@"; do [ "$_a" = '--json' ] && _json=1; done

  _node_v="$(command -v node >/dev/null 2>&1 && node --version 2>/dev/null || printf 'absent')"
  _chrome_v="$(_chrome_version)"
  if _have_playwright; then _pw='present'; else _pw='absent'; fi
  if [ -f "$SESSION_PROFILE/Default/Cookies" ]; then _prof='present'; else _prof='absent'; fi

  # Row 5 is gated whether or not its backend is there, and doctor says so in both cases, so an existing profile is not read as a working capability.
  if [ "$_json" -eq 1 ]; then
    printf '{\n'
    printf '  "router": "%s",\n' "$ROUTING"
    printf '  "node": "%s",\n' "$_node_v"
    printf '  "chrome": "%s",\n' "$(printf '%s' "$_chrome_v" | tr -d '\n')"
    printf '  "playwright": "%s",\n' "$_pw"
    printf '  "probeDir": "%s",\n' "$PROBE_DIR"
    printf '  "rows": {\n'
    printf '    "1_probe": "%s",\n' "$( { _have_chrome && _have_playwright && [ -f "$BIN/browser-probe.mjs" ]; } && printf 'ready' || printf 'SKIP')"
    printf '    "2_hosts": "%s",\n' "$( { _have_chrome && _have_playwright && [ -f "$BIN/browser-hosts.mjs" ]; } && printf 'ready' || printf 'SKIP')"
    printf '    "3_cdp": "%s",\n'   "$(_have_chrome && printf 'ready' || printf 'SKIP')"
    printf '    "4_extension": "out-of-process — a tool, not a verb",\n'
    printf '    "5_session": "GATED",\n'
    printf '    "6_historical": "not a browser — read the numbers from their source"\n'
    printf '  },\n'
    printf '  "sessionProfile": { "path": "%s", "onDisk": "%s", "state": "GATED" }\n' \
      "$SESSION_PROFILE" "$_prof"
    printf '}\n'
    return "$EXIT_PASS"
  fi

  printf 'browser doctor — router: %s\n\n' "$ROUTING"
  printf '  node        %s\n' "$_node_v"
  printf '  chrome      %s\n' "$_chrome_v"
  printf '  playwright  %s  (%s)\n\n' "$_pw" "$PROBE_DIR"
  printf '  row 1 probe      %s\n' "$( { _have_chrome && _have_playwright && [ -f "$BIN/browser-probe.mjs" ]; } && printf 'ready' || printf 'SKIP — missing a backend above, or the pack worker')"
  printf '  row 2 hosts      %s\n' "$( { _have_chrome && _have_playwright && [ -f "$BIN/browser-hosts.mjs" ]; } && printf 'ready' || printf 'SKIP — missing a backend above, or the pack worker')"
  printf '  row 3 cdp        %s\n' "$(_have_chrome && printf 'ready (zero-dependency)' || printf 'SKIP — no system Chrome')"
  printf '  row 4 extension  out-of-process — a tool, not a verb. NEVER close a NEGATIVE on it\n'
  printf '  row 5 session    GATED — profile on disk: %s\n' "$_prof"
  printf '  row 6 historical   not a browser at all — read the numbers from their source\n\n'
  printf '  Row 5 is refused until its profile has an access-ledger entry, a named\n'
  printf '  approval, and a pin instead of @latest. See %s — "Row 5".\n' "$ROUTING"
  return "$EXIT_PASS"
}

# SELF-TEST: break each gate and watch it go red (No.2.10).
_self_test() {
  _t="${TMPDIR:-/tmp}/harbor-browser-selftest.$$"
  mkdir -p "$_t/empty"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" EXIT INT TERM HUP

  _expect() {  # _expect <want-rc> <label> <cmd...>
    _want="$1"; _lbl="$2"; shift 2
    _rc=0
    "$@" >"$_t/out" 2>&1 || _rc=$?
    if [ "$_rc" -eq "$_want" ]; then
      log_ok "$_lbl (exit $_rc)"
    else
      log_fail "$_lbl: wanted exit $_want, got $_rc"
      log_fix "sh $0 --self-test, then run the case by hand"
      while IFS= read -r _ol; do log_note "$_ol"; done < "$_t/out"
    fi
  }

  log_head "self-test"
  _expect 0 'route prints the contract'        sh "$0" route
  _expect 0 'doctor runs'                      sh "$0" doctor
  _expect 0 'doctor --json runs'               sh "$0" doctor --json
  _expect 0 '--help answers (lint S4)'         sh "$0" --help
  _expect 1 'unknown verb is refused'          sh "$0" nonsense-verb
  _expect 1 'probe with no url is refused'     sh "$0" probe
  _expect 1 'session is GATED and refuses'     sh "$0" session

  # THE LOAD-BEARING ARM. A pack worker that is not installed must produce SKIPPED (2), never a pass and never a
  # plain failure: a missing verifier defers instead of being downgraded. The worker's own arms (no Playwright,
  # an unknown --expect vendor) travel with the worker, in the pack's suite.
  _nw="$_t/noworker"; mkdir -p "$_nw/bin"; cp "$BIN/access-browser.sh" "$BIN/library-log.sh" "$_nw/bin/"
  _expect 2 'an absent pack worker SKIPS, not passes' sh "$_nw/bin/access-browser.sh" hosts https://example.com

  # The skip must say why: a 2 naming no missing verifier is a failure wearing a skip's clothes.
  if grep -qE 'SKIPPED.*no bin/browser-hosts.mjs' "$_t/out"; then
    log_ok "the skip names the missing verifier"
  else
    log_fail "a skip that names no missing verifier is a failure in disguise"
    log_fix "name the missing worker in the SKIPPED line"
  fi
  _expect 1 'hosts with no url is refused' sh "$0" hosts

  log_end
}

# The consent arm is separate because it needs the network, and a gate red on a plane gets switched off (No.2.11).
# `--self-test` stays offline; `--self-test-live` reproduces the 2026-09-06 false negative and is run deliberately.
_self_test_live() {
  _t="${TMPDIR:-/tmp}/harbor-browser-live.$$"
  mkdir -p "$_t"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" EXIT INT TERM HUP
  # THE STOREFRONT IS THE OPERATOR'S: core names none. It needs a consent banner to test against, so it
  # comes from HARBOR_ACCESS_BROWSER_LIVE_URL, else `browser_live_url` in the private layer's harbor.toml, else
  # the arm is SKIPPED (never a pass).
  _u="${HARBOR_ACCESS_BROWSER_LIVE_URL:-$(sh "$BIN/scope-roots.sh" --conf browser_live_url 2>/dev/null || true)}"
  _accept="${HARBOR_ACCESS_BROWSER_LIVE_ACCEPT:-#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll}"
  log_head "self-test-live"
  if [ -z "$_u" ]; then
    log_skip "SKIPPED — no storefront to load: set HARBOR_ACCESS_BROWSER_LIVE_URL, or browser_live_url in harbor.toml"
    log_end || :
    return "$EXIT_SKIP"
  fi

  log_note "needs network; url: $_u"
  _rc=0
  sh "$0" hosts "$_u" --ms=7000 --expect=meta >"$_t/a" 2>&1 || _rc=$?
  if [ "$_rc" -eq 2 ]; then
    log_skip "backend unavailable — $(grep -m1 SKIPPED "$_t/a" || echo 'no reason given')"
    log_end || :
    return "$EXIT_SKIP"
  fi
  # THE LOAD-BEARING ARM, AND THE ONE THIS CAPABILITY EXISTS FOR. A CMP that
  # loaded and was never accepted must WITHHOLD the absence verdict and fail,
  # not print "meta: ABSENT" beside "absence here is evidence".
  if [ "$_rc" -eq 1 ] && grep -q 'ABSENCE WITHHELD' "$_t/a"; then
    log_ok "un-actioned CMP withholds the absence verdict (exit 1)"
  else
    log_fail "a CMP loaded and the absence verdict was NOT withheld (exit $_rc)"
    log_fix "sh $0 hosts $_u --expect=meta"
  fi

  _rc=0
  sh "$0" hosts "$_u" --ms=7000 --expect=meta --allow-preconsent >"$_t/b" 2>&1 || _rc=$?
  if [ "$_rc" -eq 0 ] && grep -q 'PRE-CONSENT picture, declared' "$_t/b"; then
    log_ok "--allow-preconsent declares the scope and proceeds"
  else
    log_fail "--allow-preconsent did not produce a declared pre-consent verdict"
    log_fix "sh $0 hosts $_u --expect=meta --allow-preconsent"
  fi

  # The control: without it the arms above also pass on a tool that never reports anything PRESENT. Consent accepted must find MORE.
  _rc=0
  sh "$0" hosts "$_u" --ms=9000 --click="$_accept" >"$_t/c" 2>&1 || _rc=$?
  _pre="$(awk '/hosts \(/{print $4; exit}' "$_t/b" 2>/dev/null || echo 0)"
  _post="$(awk '/hosts \(/{print $4; exit}' "$_t/c" 2>/dev/null || echo 0)"
  if [ "$_rc" -eq 0 ] && [ "${_post:-0}" -gt "${_pre:-0}" ]; then
    log_ok "consent changes the picture: $_pre hosts pre, $_post post"
  else
    log_fail "accepting consent did not increase the host count ($_pre -> $_post, exit $_rc)"
    log_fix "sh $0 hosts $_u --ms=9000 --click='$_accept'"
  fi

  log_end
}

case "${1:-}" in
  route|--route)
    # Derived, never copied (doc-truth.md): a second copy of a routing table is how harbor#445 happened.
    [ -f "$ROUTING" ] || _die "missing router: $ROUTING" "git -C $ROOT checkout -- contracts/browser-routing.md"
    cat "$ROUTING"
    exit "$EXIT_PASS"
    ;;

  doctor)
    shift
    _doctor "$@"
    exit $?
    ;;

  probe)
    shift
    [ $# -ge 1 ] || _die 'probe wants a url' 'harbor browser probe <url> [--wait-for-event=NAME] [--ms=N] [--click=SEL]'
    _pack_worker browser-probe.mjs
    _run_worker browser-probe.mjs "$@"
    ;;

  hosts)
    shift
    [ $# -ge 1 ] || _die 'hosts wants a url' 'harbor browser hosts <url> [--ms=N] [--click=SEL] [--expect=VENDOR[,VENDOR]] [--json]'
    _pack_worker browser-hosts.mjs
    _run_worker browser-hosts.mjs "$@"
    ;;

  cdp)
    shift
    [ $# -ge 1 ] || _die 'cdp wants a url' 'harbor browser cdp <url> [--eval=EXPR] [--ms=N] [--json]'
    _run_worker access-browser-cdp.mjs "$@"
    ;;

  session)
    # Declared and refused. Measured 2026-09-06: the box runs @playwright/mcp against a persistent profile holding Cookies
    # and Login Data, never decided on, never access-ledgered, tracking @latest. A half-working ungoverned capability is worse than an absent one.
    log_fail "session is GATED and will not run: the backend exists ($SESSION_PROFILE) and holds Default/Cookies and Default/Login Data, a durable credential; three gates are open: no access-ledger entry naming which identity it runs as, read-only until an approval names the account and the change, and it tracks @latest, a subscription and not a version"
    log_fix "sh $0 route    # $ROUTING, \"Row 5\""
    log_end || :
    exit "$EXIT_FAIL"
    ;;

  --self-test)
    LOG_FD=1
    _self_test
    exit $?
    ;;

  --self-test-live)
    # shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
    LOG_FD=1
    _self_test_live
    exit $?
    ;;

  help|--help|-h|'')
    printf 'browser — the estate browser router (harbor#457)\n\n'
    _usage
    printf '\nexit: 0 pass · 1 fail · 2 SKIPPED (backend unavailable — never a pass)\n'
    printf 'router: %s\n' "$ROUTING"
    exit "$EXIT_PASS"
    ;;

  *)
    _die "unknown verb: $1"
    ;;
esac
