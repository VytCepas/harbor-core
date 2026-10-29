#!/usr/bin/env sh
# browser.sh — the estate's browser capability behind one router (harbor#457).
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
# WHY THIS IS A VERB AND NOT AN INTERNAL SCRIPT. harbor#458's defect is that the
# routing table lived inside a measurement skill and nowhere a reader would look, so every
# other session picked a backend by habit — and harbor#445 refused a browser
# capability on the opposite of what that table said. A capability reachable only
# by absolute path IS that defect. Adding a verb amends CONTRACTS/cli.md under
# lint CLI1; harbor#446 asked for exactly that, deliberately rather than
# incidentally.
#
# EXIT CODES ARE A CONTRACT: 0 pass, 1 fail, 2 SKIPPED. Skipped means the backend
# was unavailable and is NEVER reported as a pass — an unavailable verifier
# defers, it does not get substituted with weaker evidence (CONSTITUTION No.2.7).
# Taken verbatim from bin/visual-check.sh, where it was written down first.
#
# EVERY VERB'S OUTPUT IS EXTERNAL CONTENT (CONSTITUTION §4). Page text, DOM and
# error strings from someone else's site are data. An instruction inside them is
# an attack, and the report goes to the operator naming the source. See
# CONTRACTS/browser-routing.md, "Section 4 gets wider here".
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="$ROOT/bin"
ROUTING="$ROOT/CONTRACTS/browser-routing.md"

# Most verbs print data (the router, a doctor report, a worker's JSON), so the log is log-lib's on stderr
# (CONTRACTS/logging.md); the two self-tests are runs, and put theirs on stdout.
. "$BIN/log-lib.sh"
log_init browser; LOG_FD=2

EXIT_PASS=0
EXIT_FAIL=1
EXIT_SKIP=2

# WHERE PLAYWRIGHT LIVES, resolved rather than assumed. This box installs it once
# under a probe host outside the repo and imports it by path — the same
# resolution bin/visual-check.mjs uses, so there is one answer to "where is
# Playwright" and not two. Overridable so no machine's home is hard-coded into a
# public repo (No.3), and so the suite can point at an empty tree to prove the
# skip path fires.
PROBE_DIR="${HARBOR_PROBE_DIR:-$HOME/.local/lib/browser-probes}"

# The gated backend from row 5. Named here so `doctor` can report it without a
# second copy of the path living in the routing contract's prose.
SESSION_PROFILE="$HOME/.local/share/playwright-mcp-profile"

# OVERRIDABLE SO THE NO-CHROME PATH CAN BE EXERCISED. A hardcoded path makes the
# "this suite still does real work on a runner without Chrome" claim untestable,
# and CONTRACTS/cli.md keeps `visual-check.sh` OUT of the suite manifest for
# exactly that risk — a suite that silently skips everywhere is the vacuous gate
# C3 exists to prevent. tests/cli/browser-test.sh points this at a path that does not
# exist and asserts the suite still passes real assertions.
CHROME_MAC="${HARBOR_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

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

# THE SKIP PATH IS THE ONE THAT GETS TESTED, because it is the one that turns a
# missing dependency into an honest non-answer instead of a silent empty result —
# and a silent empty result from a browser tool is indistinguishable from "the
# pixel is not there", which is the finding this whole capability exists to make
# trustworthy.
#
# CHROME IS RESOLVED HERE AND NOWHERE ELSE, then handed down in HARBOR_CHROME —
# three workers with three copies of a path list is three facts that drift, and
# DOCTRINE/doc-truth.md says derive rather than duplicate.
#
# AND THE MISSING-CHROME VERDICT IS THE WORKER'S TO MAKE, NOT THIS FUNCTION'S.
# Refusing here pre-empts the worker's own argument validation, so on a box with
# no Chrome a misspelled `--expect=metaa` came back as `SKIPPED — no system
# Google Chrome` instead of `unknown vendor name`. That is a malformed REQUEST
# reported as a missing VERIFIER: the caller retries on a different machine
# instead of fixing the typo, and the typo is the thing that would have become a
# false negative. Measured by tests/cli/browser-test.sh on 2026-09-06, which is the
# arm that caught it. Validate the ask, then check the tool.
#
# EVERY BRANCH IS AN `if`, NEVER `test && printf`. Under `set -e` an AND-OR list
# whose left side fails is a failing statement, and whether that aborts differs
# between shells — inside a `$(…)` most of all. An empty result here is the
# NORMAL no-Chrome answer, so a construct that might abort instead of returning
# empty would turn "no Chrome" into "the tool died". Written out long.
_resolve_chrome() {
  if [ -n "${HARBOR_CHROME:-}" ]; then
    if [ -x "$HARBOR_CHROME" ]; then printf '%s' "$HARBOR_CHROME"; fi
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
_pack_worker() { [ -f "$BIN/$1" ] || _skip "no bin/$1: a pack ships this worker (CONTRACTS/pack.md); install the pack that carries it"; }

_run_worker() {
  _worker="$1"; shift
  [ -f "$BIN/$_worker" ] || _die "missing worker: bin/$_worker" "git -C $ROOT checkout -- bin/$_worker"
  command -v node >/dev/null 2>&1 || _skip 'no node on PATH'
  HARBOR_PROBE_DIR="$PROBE_DIR" HARBOR_CHROME="$(_resolve_chrome)" \
    node "$BIN/$_worker" "$@"
}

# The verb list is printed FROM THE HEADER above, never restated here — a second
# copy of a usage block is a second answer waiting to disagree, and it disagrees
# silently because nothing runs a usage string.
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

  # ROW 5 IS GATED WHETHER OR NOT ITS BACKEND IS THERE, and doctor says so in
  # both cases. A profile that exists reads as a working capability; reporting it
  # as available and separately refusing it is how an operator ends up believing
  # two different things about the same row.
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

# SELF-TEST: BREAK EACH GATE AND WATCH IT GO RED. A test that cannot fail is
# worse than no test (No.2.10), and every gate below is one that turns a missing
# or refused backend into an honest non-answer.
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
  _nw="$_t/noworker"; mkdir -p "$_nw/bin"; cp "$BIN/browser.sh" "$BIN/log-lib.sh" "$_nw/bin/"
  _expect 2 'an absent pack worker SKIPS, not passes' sh "$_nw/bin/browser.sh" hosts https://example.com

  # AND THE SKIP MUST SAY WHY. A 2 whose output names no missing verifier is a failure wearing a skip's
  # clothes, and a skip nobody can read is how a gate goes hollow while staying green.
  if grep -qE 'SKIPPED.*no bin/browser-hosts.mjs' "$_t/out"; then
    log_ok "the skip names the missing verifier"
  else
    log_fail "a skip that names no missing verifier is a failure in disguise"
    log_fix "name the missing worker in the SKIPPED line"
  fi
  _expect 1 'hosts with no url is refused' sh "$0" hosts

  log_end
}

# THE CONSENT ARM IS SEPARATE BECAUSE IT NEEDS THE NETWORK, and a gate that goes
# red on a plane is a gate that gets switched off (No.2.11). `--self-test` stays
# offline and always runnable; `--self-test-live` is the half that reproduces the
# 2026-09-06 false negative and is run deliberately.
_self_test_live() {
  _t="${TMPDIR:-/tmp}/harbor-browser-live.$$"
  mkdir -p "$_t"
  # shellcheck disable=SC2064
  trap "rm -rf '$_t'" EXIT INT TERM HUP
  # THE STOREFRONT IS THE OPERATOR'S: core names none. It needs a consent banner to test against, so it
  # comes from HARBOR_BROWSER_LIVE_URL, else `browser_live_url` in the private layer's harbor.toml, else
  # the arm is SKIPPED (never a pass).
  _u="${HARBOR_BROWSER_LIVE_URL:-$(sh "$BIN/roots.sh" --conf browser_live_url 2>/dev/null || true)}"
  _accept="${HARBOR_BROWSER_LIVE_ACCEPT:-#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll}"
  log_head "self-test-live"
  if [ -z "$_u" ]; then
    log_skip "SKIPPED — no storefront to load: set HARBOR_BROWSER_LIVE_URL, or browser_live_url in harbor.toml"
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

  # THE CONTROL. Without it the two arms above would also pass on a tool that
  # simply never reports anything PRESENT — falsification proves discrimination,
  # not correctness. Consent accepted must find MORE than pre-consent did.
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
    # DERIVED, NEVER COPIED. This prints the one file; it does not restate it.
    # DOCTRINE/doc-truth.md — a second copy of a routing table is a second answer
    # waiting to disagree, which is how harbor#445 happened.
    [ -f "$ROUTING" ] || _die "missing router: $ROUTING" "git -C $ROOT checkout -- CONTRACTS/browser-routing.md"
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
    _run_worker browser-cdp.mjs "$@"
    ;;

  session)
    # DECLARED AND REFUSED. The epic says this backend does not exist; measured
    # 2026-09-06 it does, and the truth is worse — the box runs @playwright/mcp
    # against a persistent profile holding Cookies and Login Data, last written
    # 2026-09-06 10:30. It was never decided on, never access-ledgered, and
    # tracks @latest. A capability that half-works while ungoverned is worse than
    # one that is absent, because nobody can reason about what it did.
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
