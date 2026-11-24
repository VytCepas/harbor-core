#!/usr/bin/env sh
# access-browser-agent.sh — `harbor chrome`: drive the operator's own Chrome through
# the Playwright Extension, attended and guarded (harbor#472; router row 4).
# platform: macOS-only — Chrome's windows and tabs are read and closed through AppleScript (`osascript`);
# without it those steps fail soft, and the CLI still drives the session's tab.
#
#   harbor chrome attach           the AGENT Chrome: a separate, headless Chrome on a copy of the agent profile; the
#                                  operator's own Chrome is never touched (--show: the same in a window of its own)
#   harbor chrome intake <ref> <add|rotate> <id> [add flags]   a key shown once, headless: clicks the page's Copy at <ref>
#                                  and pipes THIS Chrome's own clipboard (or the field at <ref>) into harbor access
#                                  --value-stdin, unseen. A plain click on a Copy is refused headless: its copy never
#                                  reaches the macOS clipboard (contracts/secret-intake.md, 2026-11-23)
#   harbor chrome signin [url] | --done   one window of the agent Chrome, for the operator to sign in once; --done closes it
#   harbor chrome attach --operator   the operator's own Chrome, through the Playwright Extension: only when a call says so;
#                                  the operator clicks Connect, or no click when the token is registered (playwright-extension-token)
#   harbor chrome attach --headless   a throwaway Chrome with no profile at all: signed out, loopback dev servers allowed
#   harbor chrome status           this session's name, pin, profile, workdir
#   harbor chrome state            the page's own visibility, focus and load state (fixed probe)
#   harbor chrome timing           the page's own clock as JSON: navigation, LCP, now, own-origin resources (fixed probe,
#                                  contracts/browser-script.tsv): a prod-vs-rebuild timing parity check needs the page's numbers
#   harbor chrome doctor           is row 4 ready on this box
#   harbor chrome detach           release the operator's Chrome
#   harbor chrome tabs             every Chrome tab, by window, query strings cut; `=` marks this session's page
#   HARBOR_ACCESS_BROWSER_LANE=<a-z0-9> harbor chrome …   a parallel agent's own browser session, <session>-<lane>
#   harbor chrome front            show this session's tab (only in a window of its own tabs; never raises)
#   harbor chrome wait-signin [s]  wait (default 300 s) while the operator signs in, then carry on
#   harbor chrome hosts            the allow-list goto/tab-new reads: core, then the private layer; plus http://localhost:<port>
#                                  and http://127.0.0.1:<port> (1024-65535), headless lane only: in the logged-in profile an
#                                  agent-written page could send credentialed cross-site requests and read localhost cookies
#   harbor chrome click <ref>      by script (contracts/browser-script.tsv): needs no paint, so a covered window takes it;
#                                  so do dblclick, hover, check, uncheck and select; --real is the CLI's own verb
#   harbor chrome scroll <px> [ref] | <ref>   scroll the page or an element at once, or a ref into view
#   harbor chrome click <ref> --force   a press at its box: through an overlay ("not stable", covered)
#   harbor chrome <verb> [args]    an allowed playwright-cli verb, in this session
#
# Guardrails against accidents and an injected agent's obvious moves — not a
# security boundary (the extension holds `debugger` on <all_urls>). Stdout is the
# CLI's data; the log goes to stderr. contracts/browser-routing.md, row 4.
#
# Deliberately one file (docs/explanation/modularity.md): `lint-module-shape.sh --seam` reads it "real but
# PRIVATE — leave it one file" (2026-10-02, 0 symbols with two outside callers). Every guard here
# serves the one verb dispatch at the bottom, and nothing else calls into them.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HERE%/bin}"
# Every byte this agent prints passes bin/access-redact.sh (contracts/secret-intake.md): stdout carries page text and
# stderr the hand-offs that quote it, and both are what an agent reads. One re-exec, each stream filtered on its own,
# the inner exit status kept (`|| _rx=$?`: under set -e a failing run would end the subshell before it is recorded).
if [ "${HARBOR_ACCESS_REDACTED:-}" != 1 ]; then
  # Missing, the pipe's reader dies at once and the run ends on SIGPIPE (141) with no word of why: say it instead.
  [ -f "$HERE/access-redact.sh" ] || { printf 'harbor chrome: output withheld: %s/access-redact.sh is missing\n' "$HERE" >&2; exit 3; }
  _rst="$(mktemp "${TMPDIR:-/tmp}/harbor-redact.XXXXXX")" || { printf 'harbor chrome: output withheld: no status file\n' >&2; exit 3; }
  HARBOR_ACCESS_REDACTED=1; export HARBOR_ACCESS_REDACTED
  { { _rx=0; sh "$HERE/access-browser-agent.sh" "$@" 3>&- || _rx=$?; printf '%s' "$_rx" > "$_rst"; } 2>&1 1>&3 3>&- \
      | sh "$HERE/access-redact.sh" >&2 3>&-; } 3>&1 | sh "$HERE/access-redact.sh" || :
  _rrc="$(cat "$_rst" 2>/dev/null || :)"; rm -f "$_rst"
  exit "${_rrc:-3}"
fi
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$HERE/library-log.sh"
log_init browser-agent

ROUTER='contracts/browser-routing.md, row 4'
HOSTS_FILE="$ROOT/contracts/browser-agent-hosts.txt"
# The private layer's own hosts (internal UIs and client tools; core names none), read after the core list. The
# env is the test seam; absent is the core list alone (contracts/private-layer.md).
PRIV_HOSTS="${HARBOR_ACCESS_BROWSER_PRIVATE_HOSTS:-}"
if [ -z "$PRIV_HOSTS" ]; then
  _pd="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"
  [ -z "$_pd" ] || PRIV_HOSTS="$_pd/browser-hosts.txt"
fi
# The extension token lives only in the Keychain, under this ref in the access register (harbor#1205); attach
# uses it when registered, so Chrome connects without the Allow click. A token in the caller's env stays refused.
TOKEN_REF='playwright-extension-token'
PW_CLI_PIN='0.1.24'   # exact pin (vendoring D1); 0.1.22 first read the profile name, 0.1.24 adds background attach (harbor#1507)
STATE_EXPR='JSON.stringify({visibility: document.visibilityState, focus: document.hasFocus(), ready: document.readyState, host: location.host, blank: location.href === "about:blank", online: navigator.onLine})'
PW_EXTENSION_ID='mmlmfjhmonkocbjadbfplnigmagldckm'
PROFILE="${HARBOR_ACCESS_BROWSER_PROFILE:-Default}"
IDLE_MS="${HARBOR_ACCESS_BROWSER_IDLE_MS:-14400000}"   # 4 h, the ceiling below: one Connect click covers a working block
# Where Chrome keeps its profiles: ~/Library on macOS, the XDG config dir on Linux (harbor#618).
case "$(uname -s 2>/dev/null)" in
  Darwin) _chrome_data_default="$HOME/Library/Application Support/Google/Chrome" ;;
  *)      _chrome_data_default="${XDG_CONFIG_HOME:-$HOME/.config}/google-chrome" ;;
esac
CHROME_DATA="${HARBOR_ACCESS_CHROME_DATA:-$_chrome_data_default}"
# THE AGENT CHROME (operator 2026-11-20): agents never drive the operator's own Chrome unless a call says --operator. A separate
# Chrome that Playwright launches on a profile of its own, headless: no window, no focus taken, nothing in the operator's Chrome.
# The operator signs in once, inside that profile (`signin`): Playwright starts every Chrome with --use-mock-keychain
# (playwright-core chromiumSwitches), so cookies a normal Chrome saved there would not decrypt. One Chrome holds one profile and a
# second open of it fails, so each session or lane runs its own APFS clone of it, side by side.
case "$(uname -s 2>/dev/null)" in
  Darwin) _agent_default="$HOME/Library/Application Support/harbor/agent-chrome" ;;
  *)      _agent_default="${XDG_DATA_HOME:-$HOME/.local/share}/harbor/agent-chrome" ;;
esac
AGENT_PROFILE="${HARBOR_ACCESS_AGENT_PROFILE:-$_agent_default}"
SIGNIN_SESSION='harbor-agent-signin'
CLAUDE_JSON="${HARBOR_ACCESS_CLAUDE_JSON:-$HOME/.claude.json}"
CONFIRM="${HARBOR_ACCESS_BROWSER_CONFIRM:-}"
# Whole words or phrases a click/dblclick target's label may not carry without the operator's
# per-call HARBOR_ACCESS_BROWSER_CONFIRM=<ref>: the live-change list (harbor#1541), one per line, which
# the MCP server reads too. Whole words, so status text (Paused, Removed, Payments) passes; the label
# comes from a fresh snapshot (_guard). Missing or empty, every guarded verb is refused (_live_check).
LIVE_WORDS="$ROOT/contracts/live-change-words.txt"
DESTRUCTIVE="$(sed 's/#.*//' "$LIVE_WORDS" 2>/dev/null | tr -s ' 	' '  ' | sed 's/^ //; s/ $//' | grep -v '^$' || :)"

_usage() { sed -n '/^#   harbor chrome attach/,/^#   harbor chrome <verb>/p' "$0" | sed 's/^# \{0,2\}//'; }

# Every refusal is FAIL, its fix, the summary, exit 1 — and the CLI never runs.
_refuse() { # <what failed> [fix command]
  _fx="${2:-none automatic — see $ROUTER}"
  log_fail "$1"
  log_fix "$_fx"
  log_end || :
  exit 1
}
# A refusal whose next step is the operator's, or one of harbor's own rules working: tagged so the
# failure ledger files it as `handoff`, not as the tool failing (FC-10, harbor#465).
_handoff() { _refuse "hand-off: $1" "${2:-}"; }

# The Chrome profiles holding the extension, comma-separated, or `none`.
_ext_profiles() {
  _ps=''
  # macOS privacy (TCC) lets -d pass but refuses the listing: an empty glob there is "could not look", not "none".
  if [ -d "$CHROME_DATA" ] && ! ls "$CHROME_DATA" >/dev/null 2>&1; then printf unreadable; return; fi
  if [ -d "$CHROME_DATA" ]; then
    for _d in "$CHROME_DATA"/*/Extensions/"$PW_EXTENSION_ID"; do
      [ -d "$_d" ] || continue
      _p="${_d%/Extensions/*}"; _p="${_p##*/}"
      _ps="${_ps:+$_ps, }$_p"
    done
  fi
  printf '%s' "${_ps:-none}"
}

# Is the extension switched off in $PROFILE? yes / no / unknown (no jq, no prefs).
# Off, Chrome answers its connect page with ERR_BLOCKED_BY_CLIENT and attach waits forever.
_ext_off() {
  _sp="$CHROME_DATA/$PROFILE/Secure Preferences"
  if [ -f "$_sp" ] && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$PW_EXTENSION_ID" \
      '.extensions.settings[$id] // {} | if ((.disable_reasons // []) | length) > 0 or .state == 0 then "yes" else "no" end' \
      "$_sp" 2>/dev/null || printf unknown
  else
    printf unknown
  fi
}

# PLAYWRIGHT_* variables the CLI would read: init scripts that run on every page,
# file access, config — any of them undoes the guards below.
_pw_env() { env | /usr/bin/grep '^PLAYWRIGHT_' | cut -d= -f1 | tr '\n' ' ' || :; }

_doctor() {
  log_head "row 4 — Chrome profile $PROFILE through the Playwright Extension"
  _ps="$(_ext_profiles)"
  if [ "$_ps" = unreadable ]; then
    log_warn "could not look for the Playwright Extension: this terminal may not list $CHROME_DATA (macOS privacy)"
    log_fix "check chrome://extensions in profile $PROFILE, or give this terminal Full Disk Access; harbor chrome attach is the real test"
  elif [ "$_ps" = none ]; then
    log_fail "the Playwright Extension is in no Chrome profile under $CHROME_DATA"
    log_fix "open 'https://chromewebstore.google.com/detail/playwright-extension/$PW_EXTENSION_ID' in Chrome profile $PROFILE and click Add"
  elif [ "$_ps" != "$PROFILE" ]; then
    log_warn "the extension is in [$_ps]; the agent attaches to [$PROFILE] only"
    log_fix "remove it from every other profile at chrome://extensions"
  else
    log_ok "the extension is installed in Chrome profile $PROFILE only"
  fi
  case "$(_ext_off)" in
    yes) log_fail "the extension is switched off in Chrome profile $PROFILE; Chrome blocks its connect page (ERR_BLOCKED_BY_CLIENT)"
         log_fix "chrome://extensions in profile $PROFILE: switch Playwright Extension on" ;;
    no)  log_ok "the extension is switched on in Chrome profile $PROFILE" ;;
  esac
  _pe="$(_pw_env)"
  if [ -n "$_pe" ]; then
    log_fail "PLAYWRIGHT_* set in the environment: ${_pe}— the approval token or a CLI override"
    log_fix "unset $_pe"
  else
    log_ok 'no PLAYWRIGHT_* variable (no approval-skipping token, no CLI override)'
  fi
  if [ -e "$HOME/.playwright" ]; then
    log_fail "$HOME/.playwright exists; the CLI would read its config"
    log_fix "mv '$HOME/.playwright' '$HOME/.playwright.disabled'"
  else
    log_ok 'no ~/.playwright config for the CLI to read'
  fi
  if command -v bunx >/dev/null 2>&1; then
    log_ok "bunx runs the pinned @playwright/cli@$PW_CLI_PIN"
  else
    log_fail 'no bunx on PATH to run the pinned CLI'
    log_fix "$(pkg_hint bun)"
  fi
  if [ -f "$CLAUDE_JSON" ] && /usr/bin/grep -q '@playwright/mcp' "$CLAUDE_JSON" 2>/dev/null; then
    log_warn 'the retired @playwright/mcp server is still configured (harbor#472)'
    log_fix 'claude mcp remove playwright -s user'
  else
    log_ok 'the retired @playwright/mcp server is not configured'
  fi
  log_note 'attended: every attach waits for the operator to click Connect in Chrome'
  log_end
}

# One browser session per Claude session: the CLI's default name is shared, and a
# second attach under it kills the first one's daemon. Inside Claude Code the
# name is always derived, so one session cannot name another's.
_session() {
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    _s="claude-$(printf '%s' "$CLAUDE_CODE_SESSION_ID" | tr -cd 'A-Za-z0-9' | cut -c1-12)"
  elif [ -n "${HARBOR_ACCESS_BROWSER_SESSION:-}" ]; then
    _s="${HARBOR_ACCESS_BROWSER_SESSION:-}"
  else
    _s=''
  fi
  case "$_s" in ''|claude-|*[!A-Za-z0-9_-]*) return 1 ;; esac
  # A lane: parallel agents of ONE session each get their own browser session, as
  # <own name>-<lane>. Appended, never replacing, so a lane cannot name another session's.
  _lane="${HARBOR_ACCESS_BROWSER_LANE:-}"   # the old name is read until 2026-11-15 (harbor#1097)
  if [ -n "$_lane" ]; then
    case "$_lane" in *[!abcdefghijklmnopqrstuvwxyz0-9]*) return 1 ;; esac
    [ "${#_lane}" -le 12 ] || return 1
    _s="$_s-$_lane"
  fi
  printf '%s' "$_s"
}

# Default-deny. Absent on purpose: run-code, eval (code in a logged-in page);
# cookie-*, *storage-*, state-save/load (session theft); requests, request*,
# response* (auth headers); route/unroute, drop, install*, open, close-all,
# kill-all, delete-data, tracing, video, recording, webmcp-*.
_allowed() {
  case "$1" in
    goto|tab-new|tab-list|tab-select|tab-close|snapshot|find|screenshot|pdf|\
    go-back|go-forward|reload|console|resize|\
    click|dblclick|hover|fill|type|select|check|uncheck|drag|\
    press|keydown|keyup|mousemove|mousedown|mouseup|mousewheel|\
    dialog-accept|dialog-dismiss|upload|scroll) return 0 ;;
  esac
  return 1
}

# A dev server (harbor#1507). The authority must equal localhost:<port> or 127.0.0.1:<port> (1024-65535) whole, so userinfo,
# a suffix host, an encoded byte or [::1]/0.0.0.0/127.1 never match; a backslash, space or control byte anywhere is refused.
_loopback_ok() {
  case "$1" in http://*) ;; *) return 1 ;; esac
  case "$1" in *\\*|*' '*|*[[:cntrl:]]*) return 1 ;; esac
  _a="${1#http://}"; _a="${_a%%[/?#]*}"
  case "$_a" in localhost:*|127.0.0.1:*) ;; *) return 1 ;; esac
  _p="${_a#*:}"
  case "$_p" in [1-9][0-9][0-9][0-9]|[1-9][0-9][0-9][0-9][0-9]) ;; *) return 1 ;; esac
  [ "$_p" -ge 1024 ] && [ "$_p" -le 65535 ]
}

# Loopback is the headless lane's only (operator, 2026-11-15): in the logged-in profile an agent-written page could send
# credentialed cross-site requests and read localhost cookies. Harbor's marker is a $TMPDIR file anyone can write, so the
# daemon's own record must agree: the CLI writes attached: true for the operator's Chrome. No record, or no jq: not headless.
_headless_lane() {
  [ -e "$WORKDIR/.headless" ] && command -v jq >/dev/null 2>&1 || return 1
  _sfs="$(for _c in "${XDG_CACHE_HOME:-$HOME/.cache}" "$HOME/Library/Caches"; do
    [ ! -d "$_c/ms-playwright/daemon" ] || find "$_c/ms-playwright/daemon" -name "$S.session" 2>/dev/null; done)"
  [ -n "$_sfs" ] || return 1
  printf '%s\n' "$_sfs" | while IFS= read -r _sf; do
    [ "$(jq -r '.attached // false' "$_sf" 2>/dev/null)" = false ] || echo attached
  done | grep -q . && return 1
  return 0
}

# https, host plain [a-z0-9.-] (a backslash once made Node load a different host
# than this check saw), equal to a listed host or a subdomain of one; or, in a headless lane only, a loopback dev server.
_host_ok() {
  if _loopback_ok "$1"; then _headless_lane; return; fi
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "$1" in *\\*|*' '*|*'	'*) return 1 ;; esac
  _h="${1#https://}"; _h="${_h%%/*}"; _h="${_h%%\?*}"; _h="${_h%%#*}"
  _h="$(printf '%s' "$_h" | tr 'A-Z' 'a-z')"
  case "$_h" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*|.*|*.|*..*) return 1 ;; esac
  for _hf in "$HOSTS_FILE" "$PRIV_HOSTS"; do
    [ -f "$_hf" ] || continue
    while IFS= read -r _l; do
      case "$_l" in ''|'#'*) continue ;; esac
      [ "$_h" = "$_l" ] && return 0
      case "$_h" in *".$_l") return 0 ;; esac
    done < "$_hf"
  done
  return 1
}

# bunx reuses its cache directory as it finds it: with a file gone, 8 attaches in 4 sessions failed on `Cannot find module
# .../cli-client/program.js` (2026-11-19..20) until the directory was replaced. The files the CLI loads first are checked; a
# directory missing one is moved aside (never deleted; mkdir is the lock, so two sessions never move it twice) and bunx fetches it whole.
_pw_cache_repair() {
  _bc="${BUN_TMPDIR:-${TMPDIR:-/tmp}}"; _bc="${_bc%/}/bunx-$(id -u)-@playwright/cli@$PW_CLI_PIN"
  [ -d "$_bc" ] || return 0
  _nm="$_bc/node_modules"
  [ -f "$_nm/@playwright/cli/playwright-cli.js" ] && [ -f "$_nm/playwright-core/package.json" ] \
    && [ -f "$_nm/playwright-core/lib/tools/cli-client/program.js" ] && return 0
  mkdir "$_bc.repair" 2>/dev/null || return 0
  if mv "$_bc" "$_bc.broken.$(date +%s).$$" 2>/dev/null; then log_warn "the cached @playwright/cli@$PW_CLI_PIN was missing files; moved it aside so bunx fetches it whole"; fi
  rmdir "$_bc.repair" 2>/dev/null || :
}

# Pinned CLI, from a per-session workdir so files never land in a repo. The CLI
# also takes config from any .playwright dir up that tree. HARBOR_ACCESS_PLAYWRIGHT_CLI is the
# test seam (a stub), as HARBOR_ACCESS_PROBE_DIR is for access-browser.sh.
_cli() {
  if [ -n "${HARBOR_ACCESS_PLAYWRIGHT_CLI:-}" ]; then
    set -- "${HARBOR_ACCESS_PLAYWRIGHT_CLI:-}" "$@"
  elif command -v bunx >/dev/null 2>&1; then
    _pw_cache_repair
    set -- bunx "@playwright/cli@$PW_CLI_PIN" "$@"
  else
    _refuse 'no bunx on PATH to run the pinned @playwright/cli' "$(pkg_hint bun)"
  fi
  # the token reaches the attach daemon only, through bin/secret, never this shell's env
  [ -z "${_CLI_TOKEN:-}" ] || set -- sh "$ROOT/bin/secret" run "$TOKEN_REF" PLAYWRIGHT_MCP_EXTENSION_TOKEN -- "$@"
  mkdir -p "$WORKDIR"
  _d="$WORKDIR"
  while [ -n "$_d" ] && [ "$_d" != / ]; do
    [ ! -e "$_d/.playwright" ] || _refuse "$_d/.playwright exists; the CLI would read its config" "mv '$_d/.playwright' '$_d/.playwright.disabled'"
    _d="${_d%/*}"
  done
  cd "$WORKDIR"
  # No verb reads stdin; inherited, the CLI drained a caller's `while read` loop (2026-10-14).
  exec "$@" </dev/null
}
_cli_run() { ( _cli "$@" ); }   # the same CLI, returning here instead of exec'ing

# Chrome itself, through AppleScript: tabs, which one is showing, which window is in front.
# A tab Chrome is not showing reports `hidden` and input verbs time out on it; a second session
# activating its own tab in the same window did that (2026-10-14). HARBOR_ACCESS_BROWSER_OSASCRIPT is the test seam.
_osa() { # <script on stdin> [args] — never launches Chrome
  "${HARBOR_ACCESS_BROWSER_OSASCRIPT:-/usr/bin/osascript}" - "$@"
}
# Lines: <window id> TAB <tab index> TAB <true|false: active> TAB <url> TAB <tab id>.
_chrome_tabs() {
  _osa <<'OSA'
on run argv
  if application "Google Chrome" is not running then return ""
  set out to ""
  set sep to character id 9 -- inside the tell, `tab` is Chrome's tab class
  tell application "Google Chrome"
    repeat with w in windows
      set a to active tab index of w
      repeat with t from 1 to (count tabs of w)
        set out to out & (id of w) & sep & t & sep & (t = a) & sep & (URL of tab t of w) & sep & (id of tab t of w) & linefeed
      end repeat
    end repeat
  end tell
  return out
end run
OSA
}
# Tabs this session opened (attach's window, tab-new), one Chrome tab id a line: detach closes
# these and nothing else, so the operator's own tabs are never touched (2026-10-14).
OWNED_NAME='.owned-tabs'
_tab_ids() { _chrome_tabs | awk -F '\t' 'NF >= 5 { print $5 }'; }
_close_tabs() { # <tab id>... — prints how many it closed; a tab already gone is skipped
  _osa "$@" <<'OSA'
on run argv
  if application "Google Chrome" is not running then return 0
  set n to 0
  tell application "Google Chrome"
    repeat with k from 1 to (count argv)
      set tid to (item k of argv) as integer
      -- ids, not refs: closing a window's last tab closes it and renumbers the rest
      set ids to id of every window
      repeat with j from 1 to (count ids)
        set w to window id (item j of ids)
        set hit to (every tab of w whose id is tid)
        if (count hit) > 0 then
          close (item 1 of hit)
          set n to n + 1
          exit repeat
        end if
      end repeat
    end repeat
  end tell
  return n
end run
OSA
}
# The extension's connect page carries its token in the query string; no output shows it
# (tab-list printed it, 2026-10-14).
_scrub() { sed -E 's#(chrome-extension://[^ )?]*)[?][^ )]*#\1?<cut>#g'; }
# A sign-in page, by its URL: a login host, or a sign-in path segment. Query and fragment are
# dropped first (a redirect parameter names login pages too). A password field alone is not
# enough: Commerce Manager's feed form shows one (2026-10-14).
_signin_url() { # <url>
  _su="$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | sed 's/[?#].*//')"
  case "$_su" in https://*) ;; *) return 1 ;; esac
  _sh="${_su#https://}"; _sp="/${_sh#*/}"; _sh="${_sh%%/*}"; [ "$_sp" != "/$_sh" ] || _sp=/
  case "$_sh" in login.*|signin.*|accounts.*|auth.*|sso.*|id.*|identity.*|passport.*) return 0 ;; esac
  printf '%s' "$_sp" | tr '/' '\n' | /usr/bin/grep -qxE '(login|signin|sign-in|log-in|logon|authorize|accountchooser|servicelogin|uas|checkpoint|oauth2?|sso)(\.(php|html?|aspx?|jsp))?'
}
_url_host() { printf '%s' "$1" | sed -E 's#^[a-z]+://([^/?#]*).*#\1#' | LC_ALL=C tr 'A-Z' 'a-z'; }
# The account to sign in with, from the access register's route cards (`account: <id> | primary
# | …`): the card that names the host, or failing that its parent domain. Empty when none does.
_account_for() { # <app host>
  _ad="${HARBOR_ACCESS_DIR:-}"
  [ -n "$_ad" ] || { _pd="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"; [ -z "$_pd" ] || _ad="$_pd/access"; }
  [ -d "$_ad" ] || return 0
  _h="$1"
  while :; do
    _c="$(find "$_ad" -maxdepth 1 -name '[a-z]*.md' -exec /usr/bin/grep -lF -- "$_h" {} + 2>/dev/null | sort | head -1)"
    if [ -n "$_c" ]; then
      _a="$(sed -n 's/^ *account: *\([^ |]*\) *| *primary *|.*/\1/p' "$_c" | head -1)"
      [ -z "$_a" ] || { printf '%s (%s)' "$_a" "${_c##*/}"; return 0; }
    fi
    case "$_h" in *.*.*) _h="${_h#*.}" ;; *) return 0 ;; esac
  done
}
_signed_out() { # <sign-in page url> — refuse naming the account the app wants
  _app="$(cat "$WORKDIR/.app-host" 2>/dev/null || :)"; [ -n "$_app" ] || _app="$(_url_host "$1")"
  _acct="$(_account_for "$_app")"
  _handoff "signed out: $_app sent this session to a sign-in page ($(_url_host "$1")). Signing in is the operator's: harbor never fills a password or picks a password-manager entry" \
    "operator: sign in${_acct:+ as $_acct}; then harbor chrome wait-signin"
}
_bare_url() { printf '%s' "$1" | sed 's/[?#].*//'; }   # query strings carry tokens and ids
# This session's page URL, from the CLI's own tab list.
_session_url() {
  _cli_run "-s=$S" tab-list 2>/dev/null | sed -n 's/^- [0-9]*: (current) \[.*\](\(.*\))$/\1/p' | head -1
}
# This session's relay log (the daemon's .err, written under DEBUG=pw:mcp:relay), if any.
_relay_err() {
  for _c in "${XDG_CACHE_HOME:-$HOME/.cache}" "$HOME/Library/Caches"; do
    [ ! -d "$_c/ms-playwright/daemon" ] || find "$_c/ms-playwright/daemon" -name "$S.err" 2>/dev/null
  done | head -1
}
# <held CLI output> — when it is the CLI's gone-session answer, refuse with the relay's recorded
# close and the attach that brings the session back. The CLI's own advice is its `open`, a fresh
# browser and not the operator's Chrome (harbor#920). Its exact wording only: a page's "Dialog
# is not open" is a page error, not a gone session.
_gone_check() {
  /usr/bin/grep -qE "^(The b|B)rowser '[^']*' is not open" "$1" 2>/dev/null || return 0
  rm -f "$1"; _e="$(_relay_err)"
  _why=''; [ -z "$_e" ] || _why="$(/usr/bin/grep -o 'ws closed> .*' "$_e" | tail -1 | cut -c12-200 || :)"
  _handoff "no Chrome is connected to session $S${_why:+ — the relay last closed with $_why}" \
    'harbor chrome attach   # then Connect in Chrome; for an app with a login, sign in first and Connect that tab'
}

# After an input verb: if the page is now about:blank, Chrome detached the extension
# from the tab and the CLI swapped in a blank one, so the verb reached nothing and
# "succeeded" (2026-10-14: typing into a Commerce Manager field, relay log
# Target.detachedFromTarget then Target.createTarget). The detach lands ~300 ms after
# the input, so settle first. A failed probe gives no verdict.
_lost_check() { # <held output>
  sleep "${HARBOR_ACCESS_BROWSER_SETTLE:-1}"
  _p="$(_cli_run "-s=$S" --raw eval "$STATE_EXPR" 2>/dev/null)" || return 0
  case "$_p" in *'blank\":true'*|*'"blank":true'*) ;; *) return 0 ;; esac
  _e="$(_relay_err)"; _t=''
  [ -z "$_e" ] || _t="$(/usr/bin/grep 'Target.detachedFromTarget' "$_e" | tail -1 | cut -c1-24 || :)"
  _scrub < "$1" >&2; rm -f "$1"
  # The relay's failed re-attach names the cause: another extension's frame is in the page, and
  # Chrome lets no extension debug another's (2026-10-14: a password manager's autofill frame on the
  # password field a page reveals, e.g. Commerce Manager's feed login after a valid URL).
  _x=''; [ -z "$_e" ] || ! tail -n 400 "$_e" | /usr/bin/grep -q 'chrome-extension:// URL of different extension' || _x=1
  if [ -n "$_x" ]; then
    _refuse "the tab was lost: another extension put a frame in the page${_t:+ at $_t} (usually a password manager's autofill on a password field), and Chrome lets no extension debug another's, so $VERB reached nothing" \
      "operator: set that extension's site access to 'On click' for this site (chrome://extensions > Details > Site access), then harbor chrome goto <url>"
  fi
  _refuse "the tab was lost: Chrome detached the extension from it${_t:+ at $_t}, and the CLI now drives a blank tab, so $VERB reached nothing" \
    'harbor chrome goto <url>   # re-open the page; a frame on an unknown scheme does this too'
}

# After a failed input verb: a hidden tab never paints, so the CLI's waits time out. Say so.
_hidden_check() { # <held output>
  _p="$(_cli_run "-s=$S" --raw eval "$STATE_EXPR" 2>/dev/null)" || return 0
  case "$_p" in *'visibility\":\"hidden'*|*'"visibility":"hidden'*) ;; *) return 0 ;; esac
  _scrub < "$1" >&2; rm -f "$1"
  _refuse "the tab is hidden: Chrome is showing another tab or window, so $VERB timed out" 'harbor chrome front'
}

# Lower-cased words of $1, space-padded; non-ASCII bytes stay letters (š, ė).
_words() {
  printf ' %s ' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/Ą/ą/g; s/Č/č/g; s/Ę/ę/g; s/Ė/ė/g; s/Į/į/g; s/Š/š/g; s/Ų/ų/g; s/Ū/ū/g; s/Ž/ž/g' \
    | LC_ALL=C tr -c 'a-z0-9\200-\377' ' ' | tr -s ' '
}
_destructive() { # <label> — prints the first entry of $DESTRUCTIVE (a word or a phrase) it carries
  _w=" $(_words "$1") "
  _old_ifs="$IFS"; IFS='
'
  for _d in $DESTRUCTIVE; do
    case "$_w" in *" $_d "*) IFS="$_old_ifs"; printf '%s' "$_d"; return 0 ;; esac
  done
  IFS="$_old_ifs"; return 1
}
# A click that copies to the clipboard: Copy ... clipboard or ... to clipboard (never Paste from clipboard), a bare Copy or Copy & Close, or Copy ... key|token|secret.
# Narrow on purpose: Copy campaign and Copy ad set duplicate a thing and copy nothing (contracts/secret-intake.md).
_copy_click() { # <label>
  _cl="$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')"
  _cw=" $(_words "$1") "
  case "$_cw" in *' clipboard '*) case "$_cw" in *' copy '*|*' to clipboard '*) return 0 ;; esac ;; esac
  _cb="$(printf '%s' "$_cl" | sed 's/^[a-z][a-z]* "/"/; s/"//g' | tr -s ' ' | sed 's/^ //; s/ $//')"
  case "$_cb" in copy|'copy & close'|'copy and close'|'copy to clipboard') return 0 ;; esac
  case "$_cw" in *' copy '*) ;; *) return 1 ;; esac
  case " ${_cw#* copy }" in *' key '*|*' token '*|*' secret '*) return 0 ;; esac
  return 1
}
# The agent Chrome or the headless lane with no window: a page's Copy lands in that Chrome's own clipboard, never the
# macOS one, so --value-clipboard reads and empties the operator's (2026-11-23). attach --show writes .shown.
_no_window() { { [ -e "$WORKDIR/.agent" ] || [ -e "$WORKDIR/.headless" ]; } && [ ! -e "$WORKDIR/.shown" ]; }
_live_check() { # the list itself: without it no label can be judged, so nothing that commits runs
  [ -n "$DESTRUCTIVE" ] || _refuse 'no live-change words: contracts/live-change-words.txt is missing or empty, so no label can be checked' 'git checkout -- contracts/live-change-words.txt'
}
# press/keydown Enter or Space, and fill/type --submit, commit what the focus sits on (harbor#1541): the fixed
# submit-focus/submit-of probe of contracts/browser-script.tsv reads the label of that control and of its form's
# submit buttons, and a live-change label is refused as a click on it is. A probe that cannot answer refuses too.
_submit_guard() { # <arg>... of $VERB
  _sk=''; _sr=''; _ss=''
  for _a in "$@"; do case "$_a" in --submit) _ss=1 ;; -*) ;; *) [ -n "$_sk" ] || _sk="$_a" ;; esac; done
  case "$VERB" in
    press|keydown) printf '%s' "$_sk" | grep -Eq '^([A-Za-z]+\+)*(Enter|NumpadEnter|Space| )$' || return 0 ;;
    type) [ -n "$_ss" ] || return 0; _sk='' ;;
    fill) [ -n "$_ss" ] || return 0; _sr="$_sk"
      case "$_sr" in e[0-9]*|f[0-9]*e[0-9]*) case "$_sr" in *[!abcdefghijklmnopqrstuvwxyz0-9]*) _sr='' ;; esac ;; *) _sr='' ;; esac
      [ -n "$_sr" ] || _refuse "fill --submit takes a snapshot ref, not '$_sk': a selector carries no label for the live-change check" 'harbor chrome snapshot' ;;
    *) return 0 ;;
  esac
  _live_check
  _sn=submit-focus; [ -z "$_sr" ] || _sn=submit-of
  _fn="$(awk -F '\t' -v k="$_sn" '$1 == k { print substr($0, length(k) + 2); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
  [ -n "$_fn" ] || _refuse "no $_sn row in contracts/browser-script.tsv, so $VERB cannot be checked" 'git checkout -- contracts/browser-script.tsv'
  _o="$WORKDIR/.submit-probe"; mkdir -p "$WORKDIR"
  _cli_run "-s=$S" --raw eval "$_fn" ${_sr:+"$_sr"} > "$_o" 2>/dev/null \
    || { _gone_check "$_o"; _refuse "no answer from the submit probe, so $VERB cannot be checked for a live change" 'harbor chrome snapshot'; }
  _sl="$({ jq -r 'if type == "string" then . else tostring end' "$_o" 2>/dev/null || cat "$_o"; } | tr -s ' \t\n' '   ' | sed 's/^ //; s/ $//' | cut -c1-200)"
  case "$VERB" in press|keydown)
    if _no_window && _copy_click "$_sl"; then
      _refuse "copy key refused: '$_sk' on the focused '$_sl' would copy into the headless Chrome's own clipboard, never the macOS one" 'harbor chrome snapshot, then harbor chrome intake <ref of that Copy> rotate <id>'
    fi ;;
  esac
  if _hit="$(_destructive "$_sl")"; then
    case "$VERB" in fill|type) _sw='--submit' ;; *) _sw="'$_sk'" ;; esac
    _handoff "destructive $VERB refused: $_sw would commit '$_sl', which matches '$_hit' — the operator confirms one click" 'harbor chrome snapshot, then HARBOR_ACCESS_BROWSER_CONFIRM=<ref> harbor chrome click <ref> on that button'
  fi
}

# click/dblclick: take a fresh full snapshot (a partial one replaces the CLI's ref
# table and breaks the next click; refs are element-bound, so a full one keeps
# them), read the target's label and box, and refuse a destructive label unless
# the operator confirmed this ref for this call. Sets G_LABEL, G_BOX.
_guard() { # <verb> <ref>
  _live_check
  case "$2" in
    e[0-9]*|f[0-9]*e[0-9]*) case "$2" in *[!abcdefghijklmnopqrstuvwxyz0-9]*) _refuse "target refused: '$2' — $1 takes a snapshot ref" ;; esac ;;
    *) _refuse "target refused: '$2' — $1 takes a snapshot ref (e12, f3e12); a selector carries no label for the destructive check" 'harbor chrome snapshot' ;;
  esac
  mkdir -p "$WORKDIR"; _g="$WORKDIR/harbor-guard.yml"; rm -f "$_g"
  _cli_run "-s=$S" snapshot --boxes --filename=harbor-guard.yml >"$WORKDIR/harbor-guard.out" 2>&1 && [ -s "$_g" ] \
    || { _gone_check "$WORKDIR/harbor-guard.out"; cat "$WORKDIR/harbor-guard.out" >&2; _refuse "no guard snapshot, so $1 $2 cannot be checked" 'harbor chrome status'; }
  # Tab-separated: root frame prefix, target frame prefix, box, label. A nameless
  # target (`- button [ref=e9]:`) is labelled by its subtree, as a reader sees it.
  # ref, frame and box are read from attrs() only: a name or text is the page's,
  # and a button named "x [ref=e4]" must not stand in for e4.
  _rec="$(awk -v ref="[ref=$2]" '
    function attrs(s) { gsub(/"([^"\\]|\\.)*"/, "", s); sub(/:( .*)?$/, "", s); return s }
    function frame(s) { if (match(s, /\[ref=f[0-9]+e/)) return substr(s, RSTART + 5, RLENGTH - 6); return "" }
    function indent(s) { match(s, /^ */); return RLENGTH }
    function bare(s) { gsub(/\[(ref|box|cursor|level|active|expanded|disabled|checked|selected|pressed|url)(=[^]]*)?\]/, "", s); return s }
    { a = attrs($0) }
    root == "" && a ~ /\[ref=/ { root = "-" frame(a) }
    found && indent($0) <= ind { exit }
    found { label = label " " bare($0); next }
    index(a, ref) {
      found = 1; ind = indent($0); tf = frame(a)
      box = ""; if (match(a, /\[box=[-0-9.,]+\]/)) box = substr(a, RSTART + 5, RLENGTH - 6)
      label = bare($0); t = label; sub(/^ *- *[a-z]+/, "", t)
      if (t ~ /[^ \t:"-]/) exit
    }
    END { if (found) printf "%s\t-%s\t%s\t%s\n", root, tf, box, label }' "$_g")"
  [ -n "$_rec" ] || _refuse "ref $2 is not in the current snapshot (stale after a page change)" 'harbor chrome snapshot'
  G_ROOT="$(printf '%s' "$_rec" | cut -f1)"; G_FRAME="$(printf '%s' "$_rec" | cut -f2)"
  G_BOX="$(printf '%s' "$_rec" | cut -f3)"; G_LABEL="$(printf '%s' "$_rec" | cut -f4- | tr -s ' 	' ' ' | sed 's/^ *- //; s/ $//')"
  if _hit="$(_destructive "$G_LABEL")"; then
    if [ "$CONFIRM" = "$2" ]; then
      log_warn "operator-confirmed destructive $1: '$G_LABEL' ($2, matches '$_hit')"
    else
      _handoff "destructive $1 refused: '$G_LABEL' ($2) matches '$_hit' — the operator confirms one call" "HARBOR_ACCESS_BROWSER_CONFIRM=$2 harbor chrome $1 $2"
    fi
  fi
  case "$1" in click|dblclick)
    if _no_window && _copy_click "$G_LABEL"; then
      _refuse "copy click refused: '$G_LABEL' ($2) would copy into the headless Chrome's own clipboard, never the macOS one, so --value-clipboard would read the operator's (2026-11-23)" \
        "use harbor chrome intake $2 rotate <id>   # or add <id> [the add flags]: it clicks, reads this Chrome's clipboard and stores the key unseen"
    fi ;;
  esac
}

# --force: the pinned CLI's click has no force option (0.1.22: [button],
# --modifiers), so this is Playwright's force done by hand — a real mouse press at
# the box centre, skipping the visible/stable/receives-events wait. Lands on
# whatever is topmost there.
_force_click() { # <ref> [button]
  [ -n "$G_BOX" ] || _refuse "no box for $1; nothing to force-click at"
  [ "$G_FRAME" = "$G_ROOT" ] || _refuse "$1 is inside an iframe; its box is frame-relative, so a forced click would land elsewhere" "harbor chrome click $1"
  _xy="$(printf '%s' "$G_BOX" | awk -F, '$3 > 0 && $4 > 0 && $1 >= 0 && $2 >= 0 { printf "%d %d", $1 + $3 / 2, $2 + $4 / 2 }')"
  [ -n "$_xy" ] || _refuse "$1 has box [$G_BOX]: hidden, zero-size or scrolled out of view" 'harbor chrome mousewheel 0 -400'
  # The press lands on whatever is on top there — a dialog's Delete over a benign
  # ref is --force's normal case. Snapshot order is not z-order, so every
  # top-frame element whose box holds the point is checked, by its own line.
  _over="$(awk -v x="${_xy% *}" -v y="${_xy#* }" -v root="$G_ROOT" -v self="[ref=$1]" '
    function attrs(s) { gsub(/"([^"\\]|\\.)*"/, "", s); sub(/:( .*)?$/, "", s); return s }
    function frame(s) { if (match(s, /\[ref=f[0-9]+e/)) return substr(s, RSTART + 5, RLENGTH - 6); return "" }
    { a = attrs($0) }
    !index(a, self) && "-" frame(a) == root && match(a, /\[box=[-0-9.,]+\]/) {
      split(substr(a, RSTART + 5, RLENGTH - 6), b, ",")
      if (x >= b[1] && x <= b[1] + b[3] && y >= b[2] && y <= b[2] + b[4]) {
        r = a; sub(/.*\[ref=/, "", r); sub(/\].*/, "", r)
        l = $0; gsub(/\[(ref|box|cursor|level|active|expanded|disabled|checked|selected|pressed|url)(=[^]]*)?\]/, "", l)
        sub(/^ *- /, "", l); gsub(/  +/, " ", l); sub(/ +$/, "", l); print r "\t" l
      }
    }' "$WORKDIR/harbor-guard.yml")"
  if [ -n "$_over" ] && [ "$CONFIRM" != "$1" ]; then
    printf '%s\n' "$_over" | while IFS='	' read -r _r _l; do
      if _hit="$(_destructive "$_l")"; then printf '%s\t%s\t%s\n' "$_r" "$_l" "$_hit"; fi
    done > "$WORKDIR/harbor-force.hit"
    if [ -s "$WORKDIR/harbor-force.hit" ]; then
      IFS='	' read -r _r _l _hit < "$WORKDIR/harbor-force.hit"
      _refuse "forced click on $1 refused: the press at $_xy lands on or through '$_l' ($_r), which matches '$_hit'" "HARBOR_ACCESS_BROWSER_CONFIRM=$1 harbor chrome click $1 --force"
    fi
  fi
  log_note "forced click at $_xy on '$G_LABEL' ($1)"
  # shellcheck disable=SC2086  # $_xy is two integers, split on purpose
  { _cli_run "-s=$S" mousemove $_xy && _cli_run "-s=$S" mousedown ${2:+"$2"}; } >"$WORKDIR/harbor-force.out" 2>&1 \
    || { _gone_check "$WORKDIR/harbor-force.out"; cat "$WORKDIR/harbor-force.out" >&2; _refuse "the forced click on $1 did not complete"; }
  _cli "-s=$S" mouseup ${2:+"$2"}
}

if [ $# -lt 1 ]; then
  printf 'usage:\n' >&2; _usage >&2
  exit 2
fi
VERB="$1"; shift
case "$VERB" in
  help|--help|-h) _usage; exit 0 ;;
  doctor) _doctor; exit $? ;;
  hosts) # the effective allow-list: core, then the private layer, one bare host per line under its source
    for _hf in "$HOSTS_FILE" "$PRIV_HOSTS"; do
      [ -n "$_hf" ] && [ -f "$_hf" ] || continue
      printf '# %s\n' "$_hf"; grep -vE '^[[:space:]]*(#|$)' "$_hf"
    done
    printf '# built in (_loopback_ok), headless lane only: http://localhost:<port> and http://127.0.0.1:<port>, port 1024-65535, for local dev servers\n'
    exit 0 ;;
esac

# A token in the CALLER's env is refused: it would ride into every verb and any child. The operator's
# opt-in is registering it (TOKEN_REF), which attach alone hands to the daemon. Checked before anything runs.
if [ -n "${PLAYWRIGHT_MCP_EXTENSION_TOKEN:-}" ]; then  # secret-seam: read only to refuse it; the value is never used
  _refuse 'PLAYWRIGHT_MCP_EXTENSION_TOKEN is set; it skips the approval dialog and this verb runs attended only' 'unset PLAYWRIGHT_MCP_EXTENSION_TOKEN'
fi
_pe="$(_pw_env)"
[ -z "$_pe" ] || _refuse "PLAYWRIGHT_* set in the environment: $_pe" "unset $_pe"
[ ! -e "$HOME/.playwright" ] || _refuse "$HOME/.playwright exists; the CLI would read its config" "mv '$HOME/.playwright' '$HOME/.playwright.disabled'"
[ -f "$HOSTS_FILE" ] || _refuse "missing host allowlist: $HOSTS_FILE" 'git checkout -- contracts/browser-agent-hosts.txt'
# Per call, never exported: set on any other verb, it is set session-wide.
case "$VERB" in
  click|dblclick|hover|check|uncheck|select) ;;
  *) [ -z "$CONFIRM" ] || _refuse "HARBOR_ACCESS_BROWSER_CONFIRM is set for '$VERB'; it confirms one click and is set on that call only, never exported" 'unset HARBOR_ACCESS_BROWSER_CONFIRM' ;;
esac

# ENFORCED FOR AGENTS (operator 2026-11-20): an agent never takes the operator's own Chrome, takes a route card's cli/api/mcp
# before its UI, and runs the agent Chrome headless. An agent's call is either MCP server's (they set HARBOR_ACCESS_ENFORCE);
# `harbor chrome` typed in a terminal is the operator's. --ui=<why> on goto, tab-new and attach --show states why the UI.
_enforced() { [ "${HARBOR_ACCESS_ENFORCE:-}" = 1 ]; }
UI_WHY=''
case "$VERB" in
  goto|tab-new|attach)
    _n=0
    for _a in "$@"; do case "$_a" in --ui=*) _n=$((_n + 1)); UI_WHY="${_a#--ui=}" ;; esac; done
    [ "$_n" -le 1 ] || _refuse "$VERB takes one --ui=" "harbor chrome $VERB --ui='<why>'"
    if [ "$_n" = 1 ]; then
      case "$UI_WHY" in *[[:cntrl:]]*) _refuse '--ui= takes why the task needs the UI, on one line' "harbor chrome $VERB --ui='<why>'" ;; esac
      [ "${#UI_WHY}" -ge 3 ] && [ "${#UI_WHY}" -le 200 ] || _refuse '--ui= takes why the task needs the UI, 3..200 characters' "harbor chrome $VERB --ui='<why>'"
      for _a in "$@"; do shift; case "$_a" in --ui=*) ;; *) set -- "$@" "$_a" ;; esac; done
    fi ;;
esac
# A url whose route card ranks cli, api or mcp above the browser: the card's first move, unless --ui= says why the UI.
_api_first() { # <url>
  _enforced && [ -z "$UI_WHY" ] || return 0
  [ -f "$ROOT/context-rules/user/browser-last-tier.sh" ] || return 0
  _m="$(sh "$ROOT/context-rules/user/browser-last-tier.sh" --check "$1" 2>/dev/null | head -1)" || _m=''
  [ -n "$_m" ] || return 0
  _card="$(printf '%s' "$_m" | cut -f1)"; _tier="$(printf '%s' "$_m" | cut -f2)"; _use="$(printf '%s' "$_m" | cut -f3)"
  _refuse "api first: $_card is reached at tier $_tier, ahead of the browser (cli > api > mcp > browser). Its first move: ${_use:-see the card}" \
    "take that route; only when the task needs this UI: harbor chrome $VERB '$1' --ui='<why the UI and not the $_tier>'"
}

# 0 disables the CLI's idle timer (armed only when truthy), so it is bounded.
case "$IDLE_MS" in
  ''|*[!0-9]*) _refuse "HARBOR_ACCESS_BROWSER_IDLE_MS is not milliseconds: $IDLE_MS" 'unset HARBOR_ACCESS_BROWSER_IDLE_MS' ;;
esac
if [ "$IDLE_MS" -lt 60000 ] || [ "$IDLE_MS" -gt 14400000 ]; then
  _refuse "HARBOR_ACCESS_BROWSER_IDLE_MS must be 60000..14400000 (1 min to 4 h): $IDLE_MS" 'unset HARBOR_ACCESS_BROWSER_IDLE_MS'
fi
case "$PROFILE" in
  ''|*[!A-Za-z0-9\ ]*) _refuse "HARBOR_ACCESS_BROWSER_PROFILE is not a Chrome profile dir name: $PROFILE" 'unset HARBOR_ACCESS_BROWSER_PROFILE' ;;
esac

S="$(_session)" || _refuse 'no session: run inside Claude Code (CLAUDE_CODE_SESSION_ID), or set HARBOR_ACCESS_BROWSER_SESSION outside it; a HARBOR_ACCESS_BROWSER_LANE is 1-12 of a-z0-9' 'export HARBOR_ACCESS_BROWSER_SESSION=manual'
WORKDIR="${TMPDIR:-/tmp}"; WORKDIR="${WORKDIR%/}/harbor-browser/$S"

case "$VERB" in
  attach)
    _mode=agent; _show=''
    case "$*" in
      '') ;;
      --headless) _mode=headless ;;
      --operator) _mode=operator
        ! _enforced || _refuse "attach --operator refused: agents never drive the operator's own Chrome (operator 2026-11-20)" \
          'harbor chrome attach   # the agent Chrome; the operator opens their own from their own terminal' ;;
      --show) _show=--headed
        ! _enforced || [ -n "$UI_WHY" ] || _refuse 'attach --show refused: the agent Chrome runs headless unless the call says why it needs a window' \
          "harbor chrome attach --show --ui='<why a window>'" ;;
      *) _refuse "attach takes [] (the agent Chrome), [--show] (the agent Chrome in a window), [--headless] (no profile) or [--operator] (the operator's own Chrome): '$*'" 'harbor chrome attach' ;;
    esac
    if [ "$_mode" = agent ]; then
      [ ! -s "$WORKDIR/$OWNED_NAME" ] || _refuse "session $S holds tabs in the operator's Chrome; detach it first, or take a lane" 'harbor chrome detach'
      [ -d "$AGENT_PROFILE/Default" ] || _refuse "hand-off: there is no agent Chrome profile yet: the operator signs in to it once, in a window of its own (their own Chrome is never used)" \
        'mcp__harbor_chrome__signin with args ["https://<vendor host>/"]; the operator signs in there, then mcp__harbor_chrome__signin with args ["--done"]'
      [ ! -L "$AGENT_PROFILE/SingletonLock" ] || _refuse "the agent Chrome's sign-in window is still open, so its profile cannot be copied" 'mcp__harbor_chrome__signin with args ["--done"]   # once the operator has signed in'
      _pd="$WORKDIR/profile"; mkdir -p "$WORKDIR"
      [ ! -e "$WORKDIR/.agent" ] || _cli_run "-s=$S" close >/dev/null 2>&1 || :   # a re-attach: its old Chrome lets go of the copy first
      rm -rf "$_pd"
      cp -cR "$AGENT_PROFILE" "$_pd" 2>/dev/null || { rm -rf "$_pd"; cp -R "$AGENT_PROFILE" "$_pd"; } || _refuse "could not copy the agent profile into $_pd" 'df -h "$TMPDIR"'
      rm -f "$_pd"/Singleton*
      rm -f "$WORKDIR/.headless" "$WORKDIR/.shown"; : > "$WORKDIR/.agent"; [ -z "$_show" ] || : > "$WORKDIR/.shown"
      DEBUG='pw:mcp:relay,pw:mcp:error'; export DEBUG   # never the caller's: pw:protocol logs every request's headers
      _rc=0; _cli_run "-s=$S" open --browser=chrome "--profile=$_pd" "--idle-timeout=$IDLE_MS" ${_show:+"$_show"} || { _rc=$?; rm -f "$WORKDIR/.agent" "$WORKDIR/.shown"; rm -rf "$_pd"; }
      [ "$_rc" -ne 0 ] || log_ok "attach: session $S runs the agent Chrome (its own profile copy${_show:+, in a window}); the operator's Chrome is untouched"
      exit "$_rc"
    fi
    rm -f "$WORKDIR/.agent" "$WORKDIR/.shown"
    if [ "$_mode" = headless ]; then
      # The headless lane (harbor#1507): a throwaway, in-memory system Chrome with no profile, so no login and no
      # window; the same verbs and the same host allow-list (the operator's decision, 2026-11-11). `open` stays refused
      # as a verb: this fixed call is its only use. A lane already attached to the operator's Chrome is refused.
      [ ! -s "$WORKDIR/$OWNED_NAME" ] || _refuse "session $S holds tabs in the operator's Chrome; a headless browser takes its own lane" "harbor_chrome attach with lane set and args [\"--headless\"]"
      mkdir -p "$WORKDIR"; : > "$WORKDIR/.headless"
      DEBUG='pw:mcp:relay,pw:mcp:error'; export DEBUG   # never the caller's: pw:protocol logs every request's headers
      _rc=0; _cli_run "-s=$S" open --browser=chrome "--idle-timeout=$IDLE_MS" || { _rc=$?; rm -f "$WORKDIR/.headless"; }
      exit "$_rc"
    fi
    rm -f "$WORKDIR/.headless"
    [ "$(_ext_off)" != yes ] || _refuse "the Playwright Extension is switched off in Chrome profile $PROFILE; Chrome would block its connect page (ERR_BLOCKED_BY_CLIENT)" "chrome://extensions in profile $PROFILE: switch Playwright Extension on"
    if sh "$ROOT/bin/access.sh" has "$TOKEN_REF" >/dev/null 2>&1; then
      _CLI_TOKEN=1
      log_note "attach: connecting with the registered extension token ($TOKEN_REF), no Allow click; the host allow-list still holds"
    else
      log_note "approve in Chrome: the Playwright Extension tab that just opened (connect.html) IS the approval page; click Allow, then click Connect next to any tab. One click lasts until 4 h idle or harbor chrome detach"
    fi
    PLAYWRIGHT_MCP_PROFILE_DIR_NAME="$PROFILE"; export PLAYWRIGHT_MCP_PROFILE_DIR_NAME
    # Background (CLI 0.1.24) is opt-in: with extension 0.5 on Chrome 157 its tab landed inactive in the operator's
    # window, read hidden, timed out a click, and detach did not close it (harbor#1507, 2026-11-12).
    rm -f "$WORKDIR/.background"
    if [ "${HARBOR_ACCESS_BROWSER_BACKGROUND:-0}" = 1 ]; then
      PLAYWRIGHT_MCP_BACKGROUND=1; export PLAYWRIGHT_MCP_BACKGROUND; mkdir -p "$WORKDIR"; : > "$WORKDIR/.background"
    fi
    # The daemon inherits DEBUG and writes it to its .err: pw:mcp:relay logs CDP
    # method names and why the relay closed (status reads it); a caller's
    # DEBUG=pw:protocol would log every request's headers there (2026-10-01). pw:mcp:error
    # logs the relay's swallowed errors, e.g. a failed re-attach after a detach (2026-10-14).
    DEBUG='pw:mcp:relay,pw:mcp:error'; export DEBUG
    # A window of its own: the extension opens its connect page as a new tab in the focused
    # window, and that tab is the session's. The window opens on about:blank, closed once the
    # connect tab is there: a New Tab page another extension replaced lost the first goto 3 of 3
    # (2026-10-14). Attaches take turns, or two lanes race for the focused window. The
    # operator's app gets focus straight back.
    mkdir -p "$WORKDIR"; _lk="${WORKDIR%/*}/.attach-lock"; _i=0
    until ( set -C; : > "$_lk" ) 2>/dev/null; do  # a file with O_EXCL, never mkdir (harbor#1378)
      _i=$((_i + 1)); [ "$_i" -le 60 ] || { log_warn "attach: $_lk held for 60 s; taking it"; break; }
      sleep 1
    done
    trap '{ rm -f "$_lk" || rmdir "$_lk"; } 2>/dev/null' EXIT INT TERM HUP
    _before=" $(_tab_ids 2>/dev/null | tr '\n' ' ') "
    _oef="$WORKDIR/.osa-err"
    _nw="$(_osa <<'OSA' 2>"$_oef"
on run argv
  if application "Google Chrome" is not running then return "notrunning"
  set sep to character id 9
  tell application "System Events" to set prev to bundle identifier of first process whose frontmost is true
  tell application "Google Chrome"
    set pw to ""
    if (count windows) > 0 then set pw to id of window 1
    set w to make new window
    set URL of active tab of w to "about:blank#harbor"
    set res to (id of w as text) & sep & (id of active tab of w as text) & sep & prev & sep & pw
  end tell
  if prev is not "com.google.Chrome" then tell application id prev to activate
  return res
end run
OSA
)" || _nw=''
    _wid="$(printf '%s' "$_nw" | cut -f1)"; _tid="$(printf '%s' "$_nw" | cut -f2)"
    # No window of its own means the extension opens its tab in the window the operator is working in (2 attaches, 2026-11-19..20),
    # so attach refuses. Chrome not running is the one exception: no window of theirs to land in.
    case "$_nw:$_tid" in
      notrunning:*) _tid='' ;;
      *:|*:*[!0-9]*) _tid=''; _oe="$(head -c 200 "$_oef" 2>/dev/null | tr '\n' ' ')"; rm -f "$_oef"
        _refuse "attach refused: AppleScript could not open a window of its own${_oe:+ ($_oe)}, so the extension would open its tab in the window you are working in" \
          "operator: System Settings > Privacy & Security > Automation: allow the app that runs Claude Code to control Google Chrome and System Events; or, for a page with no login, attach a lane with --headless" ;;
    esac
    rm -f "$_oef"
    _ao="$(mktemp "$WORKDIR/.out.XXXXXX")"; _watch_pid=''
    trap '{ rm -f "$_lk" || rmdir "$_lk"; } 2>/dev/null; rm -f "$_ao"; [ -z "$_watch_pid" ] || kill "$_watch_pid" 2>/dev/null || :' EXIT INT TERM HUP
    [ -z "$_tid" ] || printf '%s\n' "$_wid" > "$WORKDIR/.window"
    # harbor#1569: while the extension connects, whenever Chrome comes to the front, focus goes straight back (measured
    # 1.3-1.8 s in front otherwise). One AppleScript polls until the connect returns (at most ~15 s); the check after stays.
    # Only on the token path: attended, the operator is in Chrome on purpose, to click Allow and Connect.
    _prev_app="$(printf '%s' "$_nw" | cut -f3)"
    [ "${_CLI_TOKEN:-}" = 1 ] || _prev_app=''
    case "$_prev_app" in ''|com.google.Chrome|*[!A-Za-z0-9.-]*) _prev_app='' ;; *)
      # exec, so $! is osascript itself: a killed _osa subshell left its osascript polling (review of harbor#1569)
      ( exec "${HARBOR_ACCESS_BROWSER_OSASCRIPT:-/usr/bin/osascript}" - "$_prev_app" ) >/dev/null 2>&1 <<'OSA' &
-- harbor-focus-watch
on run argv
  repeat 150 times
    tell application "System Events" to set fb to bundle identifier of first process whose frontmost is true
    if fb is "com.google.Chrome" then tell application id (item 1 of argv) to activate
    delay 0.05
  end repeat
end run
OSA
      _watch_pid=$! ;;
    esac
    _rc=0; _cli_run "-s=$S" attach --extension=chrome "--idle-timeout=$IDLE_MS" > "$_ao" 2>&1 || _rc=$?
    [ -z "$_watch_pid" ] || { kill "$_watch_pid" 2>/dev/null; wait "$_watch_pid" 2>/dev/null; _watch_pid=''; } || :
    _scrub < "$_ao"
    if [ -n "$_tid" ]; then
      # Ours: the tabs that appeared in our window, or the extension's connect page wherever it
      # went. A tab the operator opened meanwhile elsewhere is not.
      _new="$(_chrome_tabs 2>/dev/null | awk -F '\t' -v w="$_wid" -v p="$_tid" -v b="$_before" -v x="chrome-extension://$PW_EXTENSION_ID/" \
        'NF >= 5 && $5 != p && index(b, " " $5 " ") == 0 && ($1 == w || index($4, x) == 1) { print $5 }')"
      if [ -n "$_new" ]; then
        printf '%s\n' "$_new" >> "$WORKDIR/$OWNED_NAME"
        _close_tabs "$_tid" >/dev/null 2>&1 || printf '%s\n' "$_tid" >> "$WORKDIR/$OWNED_NAME"
      else
        printf '%s\n' "$_tid" >> "$WORKDIR/$OWNED_NAME"   # the connect page took no tab of its own
      fi
    fi
    # The operator was in Chrome: the window they were in goes back on top.
    _pw="$(printf '%s' "$_nw" | cut -f4)"
    if [ "$(printf '%s' "$_nw" | cut -f3)" = com.google.Chrome ] && [ -n "$_pw" ]; then
      _osa "$_pw" >/dev/null 2>&1 <<'OSA' || :
on run argv
  tell application "Google Chrome" to set index of (window id ((item 1 of argv) as integer)) to 1
end run
OSA
    fi
    # The operator was in another app: the extension's connect step brings Chrome to the front and leaves it there
    # (harbor#1569, measured: 27 s until restored by hand), so focus goes back. Only if Chrome is still in front.
    if [ -n "$_prev_app" ]; then
      _osa "$_prev_app" >/dev/null 2>&1 <<'OSA' || log_warn "attach: could not hand focus back to $_prev_app (AppleScript refused); Chrome may still be in front"
-- harbor-focus-back
on run argv
  tell application "System Events" to set fb to bundle identifier of first process whose frontmost is true
  if fb is "com.google.Chrome" then tell application id (item 1 of argv) to activate
end run
OSA
    fi
    exit "$_rc"
    ;;
  signin)
    # The one window the agent Chrome ever shows unasked: the operator signs in to the vendors the agents use, inside the agent
    # profile, never their own Chrome. Every later attach copies that profile, so one sign-in covers every session and lane.
    case "${1:-}" in
      --done)
        [ $# -eq 1 ] || _refuse 'signin takes [url] or [--done]' 'harbor chrome signin --done'
        _rc=0; _cli_run "-s=$SIGNIN_SESSION" close || _rc=$?
        [ ! -L "$AGENT_PROFILE/SingletonLock" ] || log_warn "signin: the agent profile is still held; close the sign-in window by hand (Cmd-W)"
        exit "$_rc" ;;
      '') ;;
      *) [ $# -eq 1 ] || _refuse 'signin takes [url] or [--done]' 'harbor chrome signin https://ads.google.com/'
         _host_ok "$1" || _refuse "signin refused: '$1' is not https on an allowed host" 'harbor chrome hosts' ;;
    esac
    [ ! -L "$AGENT_PROFILE/SingletonLock" ] || _refuse 'the agent Chrome sign-in window is already open' 'mcp__harbor_chrome__signin with args ["--done"]   # once the operator has signed in'
    mkdir -p "$AGENT_PROFILE" && chmod 700 "$AGENT_PROFILE" || _refuse "could not create the agent profile at $AGENT_PROFILE" "ls -ld '${AGENT_PROFILE%/*}'"
    DEBUG='pw:mcp:relay,pw:mcp:error'; export DEBUG
    _rc=0; _cli_run "-s=$SIGNIN_SESSION" open --browser=chrome "--profile=$AGENT_PROFILE" --headed ${1:+"$1"} || _rc=$?
    [ "$_rc" -ne 0 ] || log_note "signin: a window of the AGENT Chrome is open (not your own Chrome): sign in to every vendor the agents use, then tell the agent; it runs mcp__harbor_chrome__signin with args [\"--done\"]"
    exit "$_rc"
    ;;
  detach)
    if [ -e "$WORKDIR/.agent" ]; then   # the agent Chrome: the daemon's own browser on this session's profile copy, closed whole
      _rc=0; _cli_run "-s=$S" close || _rc=$?
      rm -rf "$WORKDIR/profile"; rm -f "$WORKDIR/.agent" "$WORKDIR/.shown" "$WORKDIR/.last-url"; exit "$_rc"
    fi
    if [ -e "$WORKDIR/.headless" ]; then   # the headless lane: its browser is the daemon's own, so close it whole
      _rc=0; _cli_run "-s=$S" close || _rc=$?
      rm -f "$WORKDIR/.headless" "$WORKDIR/.shown" "$WORKDIR/.last-url"; exit "$_rc"
    fi
    rm -f "$WORKDIR/.last-url" "$WORKDIR/.background" "$WORKDIR/.shown"   # a detach is deliberate: nothing re-attaches after it
    # Then close what this session opened, and only that.
    _rc=0; _cli_run "-s=$S" detach || _rc=$?
    # Every tab in the window attach opened is this session's (a dropped tab's replacement, later
    # navigated, too) except Chrome's own pages, where an operator's Cmd-T lands.
    _wid="$(cat "$WORKDIR/.window" 2>/dev/null || :)"; rm -f "$WORKDIR/.window"
    case "$_wid" in ''|*[!0-9]*) ;; *)
      _chrome_tabs 2>/dev/null | awk -F '\t' -v w="$_wid" '$1 == w && $4 !~ /^chrome:/ { print $5 }' >> "$WORKDIR/$OWNED_NAME" ;;
    esac
    if [ -s "$WORKDIR/$OWNED_NAME" ]; then
      # shellcheck disable=SC2046 # one numeric id a line
      _n="$(_close_tabs $(/usr/bin/grep -E '^[0-9]+$' "$WORKDIR/$OWNED_NAME") 2>/dev/null)" || _n=''
      case "$_n" in
        ''|*[!0-9]*) log_warn "detach: could not close this session's tabs (AppleScript refused); ids in $WORKDIR/$OWNED_NAME" ;;
        *) rm -f "$WORKDIR/$OWNED_NAME"; log_ok "detach: closed $_n tab(s) this session opened; no other tab touched" ;;
      esac
    fi
    exit "$_rc"
    ;;
  timing)
    [ $# -eq 0 ] || _refuse 'timing takes no arguments; its expression is fixed' 'harbor chrome timing'
    # One fixed, read-only function from contracts/browser-script.tsv, which the MCP route reads too: eval stays refused.
    _fn="$(awk -F '\t' '$1 == "timing" { print substr($0, 8); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
    [ -n "$_fn" ] || _refuse 'no timing row in contracts/browser-script.tsv' 'git checkout -- contracts/browser-script.tsv'
    mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
    trap 'rm -f "$_o"' EXIT INT TERM HUP
    _rc=0; _cli_run "-s=$S" --raw eval "$_fn" > "$_o" || _rc=$?
    [ "$_rc" -eq 0 ] || _gone_check "$_o"
    _scrub < "$_o"; exit "$_rc"
    ;;
  state)
    [ $# -eq 0 ] || _refuse 'state takes no arguments; its expression is fixed' 'harbor chrome state'
    # One fixed expression, never the caller's: eval stays off the allow-list. A hidden tab
    # takes fills and clicks without error and never updates (Commerce Manager, 2026-10-14).
    mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
    trap 'rm -f "$_o"' EXIT INT TERM HUP
    _rc=0; _cli_run "-s=$S" --raw eval "$STATE_EXPR" > "$_o" || _rc=$?
    [ "$_rc" -eq 0 ] || _gone_check "$_o"
    _scrub < "$_o"; exit "$_rc"
    ;;
  text)
    # The visible text of the page or one element (harbor#1507), through two fixed functions: eval stays refused.
    [ $# -le 1 ] || _refuse 'text takes [] or [ref]' 'harbor chrome text'
    case "${1:-}" in
      '') _fn='() => document.body ? document.body.innerText : ""' ;;
      e[0-9]*|f[0-9]*e[0-9]*)
        case "$1" in *[!abcdefghijklmnopqrstuvwxyz0123456789]*) _refuse "text takes a snapshot ref (e12, f3e12), not '$1'" 'harbor chrome snapshot' ;; esac
        _fn='(el) => el.innerText ?? el.textContent ?? ""' ;;
      *) _refuse "text takes a snapshot ref (e12, f3e12), not '$1'" 'harbor chrome snapshot' ;;
    esac
    mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
    trap 'rm -f "$_o"' EXIT INT TERM HUP
    _rc=0; _cli_run "-s=$S" --raw eval "$_fn" ${1:+"$1"} > "$_o" || _rc=$?
    [ "$_rc" -eq 0 ] || _gone_check "$_o"
    { jq -r '.' "$_o" 2>/dev/null || cat "$_o"; } | _scrub | head -c 40000; exit "$_rc"   # --raw prints a JSON string
    ;;
  tabs)
    [ $# -eq 0 ] || _refuse 'tabs takes no arguments' 'harbor chrome tabs'
    [ ! -e "$WORKDIR/.headless" ] || _refuse "session $S is headless: it has no Chrome window; its tabs are tab-list" 'harbor chrome tab-list'
    [ ! -e "$WORKDIR/.agent" ] || _refuse "session $S runs the agent Chrome, not a window of the operator's; its tabs are tab-list" 'harbor chrome tab-list'
    _me="$(_session_url)"; _me="$(_bare_url "$_me")"
    _own=" $(cat "$WORKDIR/$OWNED_NAME" 2>/dev/null | tr '\n' ' ') "   # a pipe: under set -e a failed < aborts
    _chrome_tabs | while IFS="$(printf '\t')" read -r _w _t _a _u _id; do
      [ -n "$_w" ] || continue
      _b="$(_bare_url "$_u")"; _m=' '
      [ -z "$_me" ] || [ "$_b" != "$_me" ] || _m='='
      # Another tab is the operator's or another session's: its host says what it is, its
      # path can be a message thread (field test, 2026-10-14).
      _keep="$_m"; [ -z "$_id" ] || case "$_own" in *" $_id "*) _keep='=' ;; esac
      [ "$_keep" = '=' ] || _b="$(printf '%s' "$_b" | sed -E 's#^([a-z-]+://[^/]*).*#\1#')"
      [ "$_a" = true ] && _a='active' || _a='      '
      printf '%s window %s tab %s %s %s\n' "$_m" "$_w" "$_t" "$_a" "$_b"
    done
    ;;
  front)
    [ $# -eq 0 ] || _refuse 'front takes no arguments' 'harbor chrome front'
    [ ! -e "$WORKDIR/.headless" ] || { log_ok "front: session $S is headless; its page is always rendered"; exit 0; }
    [ ! -e "$WORKDIR/.agent" ] || { log_ok "front: session $S runs the agent Chrome; nothing of the operator's to raise"; exit 0; }
    _me="$(_session_url)"
    [ -n "$_me" ] || _refuse "no page in session $S to bring to the front" 'harbor chrome attach'
    # Matched by suffix: the whole URL, or after marking, the mark alone.
    _n="$(_chrome_tabs | awk -F '\t' -v u="$_me" 'substr($4, length($4) - length(u) + 1) == u' | wc -l | tr -d ' ')"
    _own=" $(cat "$WORKDIR/$OWNED_NAME" 2>/dev/null | tr '\n' ' ') "   # a pipe: under set -e a failed < aborts
    # Several tabs on our URL, one of them ours by id (the operator had the same page open: 9 of
    # 30 front failures, 2026-11-10..12): that one, by id, with no mark.
    _tid=''
    if [ "$_n" -gt 1 ]; then
      _tid="$(_chrome_tabs | awk -F '\t' -v u="$_me" -v own="$_own" 'substr($4, length($4) - length(u) + 1) == u && index(own, " " $5 " ") > 0 { print $5 }')"
      case "$_tid" in ''|*[!0-9]*) _tid='' ;; *) _n=1 ;; esac   # none, or more than one (a newline): not told apart
    fi
    if [ "$_n" -ne 1 ]; then
      # Not exactly one tab on this URL (several share it, or the page rewrote it since the
      # CLI looked): mark ours with a same-document fragment and find the mark.
      case "$_me" in *'#'*) _refuse "$_n Chrome tabs show this session's URL and it has a fragment already, so it cannot be told apart" 'harbor chrome tabs' ;; esac
      _cli_run "-s=$S" goto "$_me#harbor-$S" >/dev/null 2>&1 || _refuse "could not mark this session's tab ($_n Chrome tabs show its URL)" 'harbor chrome tabs'
      _me="#harbor-$S"
      for _i in 1 2 3 4 5; do   # Chrome reports the new URL a moment after the CLI returns
        _n="$(_chrome_tabs | awk -F '\t' -v u="$_me" 'substr($4, length($4) - length(u) + 1) == u' | wc -l | tr -d ' ')"
        [ "$_n" -eq 0 ] || break; sleep 1
      done
    fi
    [ "$_n" -eq 1 ] || _refuse "$_n Chrome tabs show this session's URL; need exactly one" 'harbor chrome tabs'
    # Never switch a window under someone reading it. Switching the active tab is the only thing
    # front does to a window, and nothing switches it back (the tab must stay shown for the click
    # that follows), so it is allowed only where every tab in the window is this session's. Else the
    # operator's tab in the session's window was replaced for hours (2026-11-06). A shared window
    # whose active tab already is ours needs no switch and passes.
    _hit="$(_chrome_tabs | awk -F '\t' -v u="$_me" -v id="$_tid" '(id != "" ? $5 == id : substr($4, length($4) - length(u) + 1) == u) { print $1 "\t" $3; exit }')"
    _hw="$(printf '%s' "$_hit" | cut -f1)"; _ha="$(printf '%s' "$_hit" | cut -f2)"
    _foreign="$(_chrome_tabs | awk -F '\t' -v w="$_hw" -v own="$_own" '$1 == w && index(own, " " $5 " ") == 0 { n++ } END { print n + 0 }')"
    if [ "$_foreign" -gt 0 ] && [ "$_ha" != true ]; then
      _refuse "this session's tab is hidden behind another tab in window $_hw, which holds $_foreign tab(s) that are not this session's; showing it would take that tab away from whoever is reading it" \
        "operator: click this session's tab in window $_hw (harbor chrome tabs marks it =), or harbor chrome detach then attach for a window of its own"
    fi
    _r="$(_osa "$_me" "${_tid:-none}" <<'OSA'
on run argv
  set u to item 1 of argv
  set tid to item 2 of argv
  set res to ""
  tell application "System Events" to set prev to bundle identifier of first process whose frontmost is true
  tell application "Google Chrome"
    -- by id: `w` is "window k" by position, and raising it renumbers the windows
    set ids to id of every window
    repeat with k from 1 to (count ids)
      set wid to item k of ids
      set w to window id wid
      repeat with t from 1 to (count tabs of w)
        if (tid is "none" and URL of tab t of w ends with u) or (tid is not "none" and (id of tab t of w as text) is tid) then
          -- shown first, raised only if the page then reads hidden (below)
          set active tab index of w to t
          if minimized of w then set minimized of w to false
          set res to "window " & wid & " tab " & t
          exit repeat
        end if
      end repeat
      if res is not "" then exit repeat
    end repeat
  end tell
  -- focus goes back to whoever had it (un-minimising can take it), from outside the Chrome tell
  delay 0.5
  if res is not "" and prev is not "com.google.Chrome" then tell application id prev to activate
  return res
end run
OSA
)" || _r=''
    [ -n "$_r" ] || _refuse 'AppleScript could not show the tab' 'System Settings > Privacy & Security > Automation: let the terminal control Google Chrome and System Events'
    # Checked, not assumed: front once said ok on a tab that stayed hidden (field test, 2026-10-14).
    sleep "${HARBOR_ACCESS_BROWSER_SETTLE:-1}"
    _p="$(_cli_run "-s=$S" --raw eval "$STATE_EXPR" 2>/dev/null)" || _p=''
    case "$_p" in *'visibility\":\"hidden'*|*'"visibility":"hidden'*)
      # A window fully covered by another, same-size one reads hidden too (macOS occlusion), and
      # attach puts the operator's window back over ours (2026-10-29). Raising ours would sit over
      # the operator's windows with nothing to lower it again, so shift it 40 px instead: still
      # under theirs, no longer fully covered, and nothing of theirs moves. Never a shared window.
      [ "$_foreign" -eq 0 ] || _handoff "front: $_r reads hidden and its window holds tabs that are not this session's, so it is not moved or raised" 'harbor chrome tabs   # then move that window where it shows'
      _w="${_r#window }"; _w="${_w%% *}"
      _osa "$_w" >/dev/null 2>&1 <<'OSA' || :
on run argv
  tell application "Google Chrome"
    set b to bounds of (window id ((item 1 of argv) as integer))
    set bounds of (window id ((item 1 of argv) as integer)) to {(item 1 of b) + 40, (item 2 of b) + 40, (item 3 of b) + 40, (item 4 of b) + 40}
  end tell
end run
OSA
      sleep "${HARBOR_ACCESS_BROWSER_SETTLE:-1}"
      _p="$(_cli_run "-s=$S" --raw eval "$STATE_EXPR" 2>/dev/null)" || _p=''
      case "$_p" in *'visibility\":\"hidden'*|*'"visibility":"hidden'*)
        _handoff "front: $_r was moved 40 px off the window covering it, but the page is still hidden (another app's window covers it, or it is on another Space)" 'harbor chrome tabs   # then move that window where it shows' ;;
      esac
      log_ok "front: $_r was covered by another window; moved it 40 px clear, nothing raised, focus left where it was"; exit 0 ;;
    esac
    log_ok "front: $_r is the tab Chrome shows; focus left where it was"
    ;;
  wait-signin)
    [ ! -e "$WORKDIR/.agent" ] || _refuse "session $S runs the agent Chrome: the operator signs in to it in its own window, not this session's" 'mcp__harbor_chrome__signin with args ["https://<vendor host>/"], then attach again'
    [ ! -e "$WORKDIR/.headless" ] || _refuse "session $S is headless and signed out by design: sign-in happens in the operator's Chrome" 'harbor chrome attach   # in a lane without --headless'
    _max="${1:-300}"
    case "$_max" in ''|*[!0-9]*) _refuse "wait-signin takes seconds: $_max" 'harbor chrome wait-signin 300' ;; esac
    [ "$_max" -ge 10 ] && [ "$_max" -le 900 ] || _refuse "wait-signin waits 10..900 s: $_max" 'harbor chrome wait-signin 300'
    [ -s "$WORKDIR/$OWNED_NAME" ] || _refuse "no tab of this session's to watch" 'harbor chrome attach'
    _own=" $(cat "$WORKDIR/$OWNED_NAME" 2>/dev/null | tr '\n' ' ') "
    # Read through AppleScript, not the extension: the password manager's frame on the sign-in
    # form drops the extension's connection, so the CLI may see nothing.
    _pick() { _chrome_tabs 2>/dev/null | awk -F '\t' -v o="$_own" 'NF >= 5 && index(o, " " $5 " ") > 0 { print $5 "\t" $4 }'; }
    _tid=''; _u=''
    while IFS="$(printf '\t')" read -r _i _x; do
      if _signin_url "$_x"; then _tid="$_i"; _u="$_x"; break; fi
    done <<EOF
$(_pick)
EOF
    [ -n "$_tid" ] || { log_ok 'wait-signin: no tab of this session is on a sign-in page'; exit 0; }
    log_note "wait-signin: waiting up to $_max s for the operator to sign in on $(_url_host "$_u")"
    _t=0
    while _signin_url "$_u" || [ "$_u" = about:blank ]; do
      [ "$_t" -lt "$_max" ] || _handoff "still on a sign-in page after $_max s ($(_url_host "$_u"))" 'harbor chrome wait-signin   # again, once signed in'
      sleep "${HARBOR_ACCESS_BROWSER_POLL:-3}"; _t=$((_t + ${HARBOR_ACCESS_BROWSER_POLL:-3}))
      _u="$(_pick | awk -F '\t' -v t="$_tid" '$1 == t { print $2 }')"
      [ -n "$_u" ] || _handoff 'the sign-in tab was closed' 'harbor chrome attach'
    done
    _host_ok "$_u" || _refuse "signed in, but the page went to $(_url_host "$_u"), which is not on the allow-list" 'harbor chrome hosts'
    if [ -n "$(_session_url)" ]; then
      log_ok "wait-signin: signed in on $(_url_host "$_u"); this session still drives the tab"; exit 0
    fi
    # The password manager's frame cost the connection: close that tab, attach afresh, and open
    # the page it reached. The profile is signed in now, so the new tab is too.
    log_note "wait-signin: signed in on $(_url_host "$_u"); the connection dropped during sign-in, reconnecting"
    sh "$HERE/access-browser-agent.sh" detach >&2 || :
    sh "$HERE/access-browser-agent.sh" attach --operator >&2 || _refuse 'signed in, but the re-attach failed' 'harbor chrome attach --operator'
    exec sh "$HERE/access-browser-agent.sh" goto "$_u"
    ;;
  intake)
    # A key shown once (contracts/secret-intake.md, 2026-11-23): click the page's Copy at <ref>, read THIS Chrome's own
    # clipboard with the fixed intake-read row (a <ref> that is itself the key's input or textarea: its value), and pipe it into
    # harbor access <add|rotate> <id> --value-stdin. Never printed, never argv, never a file; the macOS clipboard untouched.
    [ $# -ge 3 ] || _refuse 'intake takes <ref> <add|rotate> <access-entry-id> [the add flags...]' 'harbor chrome snapshot, then harbor chrome intake <ref> rotate <id>'
    _iref="$1"; _iop="$2"; _iid="$3"; shift 3
    case "$_iop" in add|rotate) ;; *) _refuse "intake takes add or rotate, not '$_iop'" "harbor chrome intake $_iref rotate <id>" ;; esac
    case "$_iid" in ''|-*|*[!A-Za-z0-9._-]*) _refuse "intake: '$_iid' is not an access entry id" 'harbor access list' ;; esac
    for _a in "$@"; do
      case "$_a" in
        --value-*) _refuse "intake supplies the value itself (--value-stdin): '$_a' is refused" "harbor chrome intake $_iref $_iop $_iid" ;;
        *[[:cntrl:]]*) _refuse 'intake: an add flag carries a control character' ;;
      esac
    done
    # Headless only: with a window (attach --show) or in the operator's Chrome, the page's Copy and readText are the macOS
    # clipboard's, and that is --value-clipboard's route.
    if ! _no_window; then
      _w='the operator'"'"'s Chrome'; [ ! -e "$WORKDIR/.agent" ] || _w='the agent Chrome in a window (attach --show)'
      _refuse "intake refused: session $S runs $_w, where the page's Copy reaches the macOS clipboard" "the page's own Copy, then: harbor access $_iop $_iid --value-clipboard"
    fi
    command -v jq >/dev/null 2>&1 || _refuse 'intake needs jq to read the intake-read answer' "$(pkg_hint jq)"
    _fn="$(awk -F '\t' '$1 == "intake-read" { print substr($0, 13); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
    case "$_fn" in *__ARG__*) ;; *) _refuse 'no intake-read row in contracts/browser-script.tsv' 'git checkout -- contracts/browser-script.tsv' ;; esac
    _fc="$(awk -F '\t' '$1 == "intake-clear" { print substr($0, 14); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
    [ -n "$_fc" ] || _refuse 'no intake-clear row in contracts/browser-script.tsv' 'git checkout -- contracts/browser-script.tsv'
    [ -z "$CONFIRM" ] || [ "$CONFIRM" = "$_iref" ] \
      || _refuse "HARBOR_ACCESS_BROWSER_CONFIRM=$CONFIRM does not name this target ($_iref); it confirms one call on one ref"
    _guard intake "$_iref"   # the ref and its label, as on click; the copy-click net is for click and dblclick, not this
    # The guard's snapshot is of the open dialog, so it can hold the key itself (measured live, 2026-11-23): gone at once.
    rm -f "$WORKDIR/harbor-guard.yml" "$WORKDIR/harbor-guard.out"
    _fn="${_fn%%__ARG__*}\"$_iref\"${_fn#*__ARG__}"
    # Empty THIS Chrome's clipboard first: a Copy that copies nothing then reads as empty, never as the last intake's key.
    _ic="$({ _cli_run "-s=$S" --raw run-code "$_fc" 2>/dev/null || :; } | jq -rRj 'fromjson? | objects | select(.intake == 1) | .cleared // 0' 2>/dev/null || :)"
    [ "$_ic" = 1 ] || _refuse "intake: this Chrome's clipboard could not be emptied before the click, so a stale value could be stored; nothing was clicked or stored" 'harbor chrome status, then harbor chrome intake again'
    # The CLI's own click (trusted input: a Copy handler may need the user activation a dispatched event lacks); its
    # output, which may show the page, is dropped.
    _cli_run "-s=$S" --raw click "$_iref" >/dev/null 2>&1 || _refuse "intake: the click on $_iref did not complete; nothing was stored" 'harbor chrome status, then harbor chrome snapshot'
    # The value: the CLI's stdout, down a pipe, into access.sh's stdin. A ref that is a field holding a value is the key
    # itself (a stale clipboard must not win over it); any other ref, the clipboard its Copy filled.
    # The read's exit and its error name go to two files that never hold the value, so a failed read is not told as an empty one.
    _irc=0; _irs="$WORKDIR/.intake-run"; _ije="$WORKDIR/.intake-read.err"; rm -f "$_irs" "$_ije"
    { _cli_run "-s=$S" --raw run-code "$_fn" 2>/dev/null; echo "$?" > "$_irs"; } \
      | jq -rRj 'fromjson? | objects | select(.intake == 1) | if ((.field // "") | length) > 0 then .field elif ((.err // "") | tostring | length) > 0 then error("the clipboard read failed: " + (.err | tostring | gsub("[^A-Za-z]"; ""))) else (.clip // "") end' 2>"$_ije" \
      | sh "$HERE/access.sh" "$_iop" "$_iid" "$@" --value-stdin || _irc=$?
    _irun="$(cat "$_irs" 2>/dev/null || echo '?')"; _ierr="$(sed -n 's/.*\(the clipboard read failed: [A-Za-z]*\).*/\1/p' "$_ije" 2>/dev/null | head -1)"
    rm -f "$_irs" "$_ije"
    if [ "$_irc" -ne 0 ]; then
      if [ "$_irun" != 0 ]; then _iwhy="the read itself failed (run-code exit $_irun): the page navigated or the session dropped"
      elif [ -n "$_ierr" ]; then _iwhy="$_ierr"
      else _iwhy="an empty value means the page's Copy filled no clipboard (emptied before the click) and $_iref holds no key"; fi
      _refuse "intake: harbor access $_iop $_iid stored nothing new (exit $_irc, its reason above); $_iwhy" \
        "harbor chrome snapshot, then harbor chrome intake <the key's field ref> $_iop $_iid"
    fi
    log_ok "intake: $_iop $_iid stored from this Chrome's own clipboard or the field at $_iref, unseen; the macOS clipboard untouched"
    ;;
  status)
    _e="$(_relay_err)"
    _r=''; [ -z "$_e" ] || _r="$(/usr/bin/grep 'WebSocket closed' "$_e" | tail -1 | cut -c1-200 || :)"
    _mode='operator Chrome'; [ ! -e "$WORKDIR/.headless" ] || _mode='headless, in-memory, no profile'
    [ ! -e "$WORKDIR/.agent" ] || _mode="agent Chrome (a copy of $AGENT_PROFILE)"
    [ ! -e "$WORKDIR/.background" ] || _mode="$_mode, background"
    printf 'session  %s\npin      @playwright/cli@%s\nmode     %s\nprofile  %s\nworkdir  %s\nidle     %s ms\nrelay    %s\n' \
      "$S" "$PW_CLI_PIN" "$_mode" "$PROFILE" "$WORKDIR" "$IDLE_MS" "${_r:-no close recorded${_e:+ in $_e}}"
    _cli list
    ;;
  *)
    _allowed "$VERB" || _refuse "verb refused: $VERB — not on the allowlist in bin/access-browser-agent.sh" 'harbor chrome help'
    # Options are default-deny too: `--session <url>` once smuggled an off-list
    # URL past the host check, and --filename wrote anywhere (the CLI skips its
    # path check in skill mode). Allowed: --filename=<bare name>, negative numbers,
    # and on click/dblclick the CLI's own --modifiers=<key> plus harbor's --force.
    for _a in "$@"; do
      case "$_a" in
        --filename=*)
          _f="${_a#--filename=}"
          case "$_f" in
            ''|.*|*/*|*\\*|*[!A-Za-z0-9._-]*) _refuse "filename refused: '$_f' — a bare name only; files land in $WORKDIR" ;;
          esac ;;
        -[0-9]*)
          case "$_a" in *[!0-9-]*) _refuse "option refused: $_a" ;; esac ;;
        --modifiers=Alt|--modifiers=Control|--modifiers=ControlOrMeta|--modifiers=Meta|--modifiers=Shift)
          case "$VERB" in click|dblclick) ;; *) _refuse "option refused: $_a — --modifiers is for click and dblclick" ;; esac ;;
        --force)
          [ "$VERB" = click ] || _refuse "option refused: --force is for click only; the mouse verbs it uses carry no click count" ;;
        --submit)
          # Enter in the same call as the text: a page that loses the tab within ~300 ms of a
          # typed URL leaves no time for a second call (Commerce Manager, 2026-10-14).
          case "$VERB" in fill|type) ;; *) _refuse "option refused: --submit is for fill and type" ;; esac ;;
        --real)
          case "$VERB" in click|dblclick|hover|check|uncheck|select) ;; *) _refuse "option refused: --real is for click, dblclick, hover, check, uncheck and select" ;; esac ;;
        -*) _refuse "option refused: $_a — only --filename=<name>, on fill and type --submit, on click --force and --modifiers=<Alt|Control|ControlOrMeta|Meta|Shift>, and --real on the scripted verbs" ;;
      esac
    done
    case "$VERB" in press|keydown|type|fill) _submit_guard "$@" ;; esac
    # An image cannot be redacted: a screenshot or pdf of a page that SHOWS a credential is refused, by the shown-secret
    # probe of contracts/browser-script.tsv the MCP route runs too (contracts/secret-intake.md). Fail closed.
    case "$VERB" in screenshot|pdf)
      _fn="$(awk -F '\t' '$1 == "shown-secret" { print substr($0, 14); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
      [ -n "$_fn" ] || _refuse "$VERB refused: no shown-secret row in contracts/browser-script.tsv, so the page cannot be checked" 'git checkout -- contracts/browser-script.tsv'
      mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
      _rc=0; _cli_run "-s=$S" --raw eval "$_fn" > "$_o" || _rc=$?
      [ "$_rc" -eq 0 ] || { _gone_check "$_o"; rm -f "$_o"; _refuse "$VERB refused: the page could not be checked for a shown credential" 'harbor chrome snapshot, then try again'; }
      _rc=0; sh "$HERE/access-redact.sh" --check < "$_o" || _rc=$?
      rm -f "$_o"
      [ "$_rc" -ne 1 ] || _refuse "$VERB refused: the page shows a credential (a key or token, or a secret URL parameter), and an image cannot be redacted" \
        "store it unseen: harbor chrome intake <ref of the page's Copy button> add|rotate <id> (contracts/secret-intake.md); close the dialog before any screenshot"
      [ "$_rc" -eq 0 ] || _refuse "$VERB refused: the credential check failed (exit $_rc)" 'sh bin/access-redact.sh --check </dev/null'
      ;;
    esac
    # Script-first (harbor#1507, operator 2026-11-12): a fixed script from contracts/browser-script.tsv, which needs no
    # paint, so a window covered by another app still takes it. --real is the CLI's own verb, which waits for the tab to show.
    _real=''; _sfn=''; _sref=''; _sarg='null'
    for _a in "$@"; do [ "$_a" != --real ] || _real=1; done
    if [ -n "$_real" ]; then for _a in "$@"; do shift; [ "$_a" = --real ] || set -- "$@" "$_a"; done; fi
    if [ "$VERB" = click ] || [ "$VERB" = dblclick ]; then
      _ref=''; _btn=''; _force=''; _mods=''
      for _a in "$@"; do
        case "$_a" in
          --force) _force=1 ;;
          --modifiers=*) _mods=1 ;;
          ''|-[0-9]*) _refuse "$VERB takes <ref> [button]; '$_a' would shift the CLI's own reading of the target" ;;
          -*) ;;
          *) if [ -z "$_ref" ]; then _ref="$_a"; elif [ -z "$_btn" ]; then _btn="$_a"; else _refuse "$VERB takes <ref> [button]"; fi ;;
        esac
      done
      [ -n "$_ref" ] || _refuse "$VERB takes a snapshot ref" 'harbor chrome snapshot'
      [ -z "$CONFIRM" ] || [ "$CONFIRM" = "$_ref" ] \
        || _refuse "HARBOR_ACCESS_BROWSER_CONFIRM=$CONFIRM does not name this target ($_ref); it confirms one call on one ref"
      _guard "$VERB" "$_ref"
      if [ -n "$_force" ]; then
        [ -z "$_mods" ] || _refuse '--force cannot carry --modifiers; the mouse verbs it uses take none'
        _force_click "$_ref" "$_btn"
      fi
      if [ -z "$_real" ] && [ -z "$_mods" ] && { [ -z "$_btn" ] || [ "$_btn" = left ]; }; then _sfn="$VERB"; _sref="$_ref"; fi
    fi
    if [ -z "$_real" ]; then
      case "$VERB" in
        hover|check|uncheck)
          [ $# -eq 1 ] || _refuse "$VERB takes <ref>" 'harbor chrome snapshot'
          _sref="$1"; _sfn="$VERB"
          case "$VERB" in check) _sarg=true ;; uncheck) _sfn=check; _sarg=false ;; esac ;;
        select)
          [ $# -ge 2 ] || _refuse 'select takes <ref> <value> [value...]' 'harbor chrome snapshot'
          _sref="$1"; _sfn=select; shift; _sarg='['
          for _v in "$@"; do
            case "$_v" in *[[:cntrl:]]*) _refuse 'select value refused: it carries a control character' ;; esac
            _sarg="$_sarg$([ "$_sarg" = '[' ] || printf ,)\"$(printf '%s' "$_v" | sed 's/\\/\\\\/g; s/"/\\"/g')\""
          done
          _sarg="$_sarg]" ;;
        scroll)
          _sfn=scroll
          for _a in "$@"; do
            case "$_a" in
              -[0-9]*|[0-9]*) case "$_a" in -*[!0-9]*|[0-9]*[!0-9]*) _refuse "scroll takes pixels or a ref, not '$_a'" ;; esac
                [ "$_sarg" = null ] || _refuse 'scroll takes [pixels] (the page), [pixels ref] (that element) or [ref] (into view)' 'harbor chrome scroll 800'
                _sarg="$_a" ;;
              *) [ -z "$_sref" ] || _refuse 'scroll takes [pixels] (the page), [pixels ref] (that element) or [ref] (into view)' 'harbor chrome scroll 800'
                _sref="$_a" ;;
            esac
          done
          [ "$_sarg" != null ] || [ -n "$_sref" ] || _refuse 'scroll takes [pixels] (the page), [pixels ref] (that element) or [ref] (into view)' 'harbor chrome scroll 800' ;;
      esac
      case "$VERB" in hover|check|uncheck|select) [ -z "$CONFIRM" ] || [ "$CONFIRM" = "$_sref" ] \
        || _refuse "HARBOR_ACCESS_BROWSER_CONFIRM=$CONFIRM does not name this target ($_sref); it confirms one call on one ref" ;; esac
      case "$VERB" in hover|check|uncheck|select|scroll) [ -z "$_sref" ] || _guard "$VERB" "$_sref" ;; esac
    fi
    if [ -n "$_sfn" ]; then
      _fn="$(awk -F '\t' -v k="$_sfn" '$1 == k { print substr($0, length(k) + 2); exit }' "$ROOT/contracts/browser-script.tsv" 2>/dev/null)"
      [ -n "$_fn" ] || _refuse "no script for $_sfn in contracts/browser-script.tsv" 'git checkout -- contracts/browser-script.tsv'
      case "$_fn" in *__ARG__*) _sfn="${_fn%%__ARG__*}$_sarg${_fn#*__ARG__}" ;; *) _sfn="$_fn" ;; esac
    fi
    # upload: allowed from anywhere at the operator's call (2026-10-14), except ~/.claude, which
    # never goes to a web tool (CONSTITUTION №3). The CLI checks no path in skill mode, so this is the check.
    if [ "$VERB" = upload ]; then
      [ $# -ge 1 ] || _refuse 'upload takes one or more absolute file paths, after a click that opens the file chooser' 'harbor chrome upload /abs/path/file.csv'
      # Paths compare physical (links followed, /var is /private/var) and lower-cased: APFS
      # ignores case, so ~/.CLAUDE is ~/.claude. A hardlink has no path to resolve, so a file
      # with other links is refused outright (adversarial review, 2026-10-14).
      _lc() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z'; }
      _phys() { # <path> — its physical path, every link followed (at most 40)
        _p="$1"; _n=0
        while [ -L "$_p" ]; do
          _n=$((_n + 1)); [ "$_n" -le 40 ] || return 1
          _l="$(readlink -- "$_p")" || return 1
          case "$_l" in /*) _p="$_l" ;; *) _p="$(dirname -- "$_p")/$_l" ;; esac
        done
        _d="$(CDPATH='' cd -- "$(dirname -- "$_p")" 2>/dev/null && pwd -P)" || return 1
        printf '%s/%s' "$_d" "$(basename -- "$_p")"
      }
      _root() { CDPATH='' cd -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
      _cd="$(_lc "$(_root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")")"; _hc="$(_lc "$(_root "$HOME/.claude")")"
      for _a in "$@"; do
        case "$_a" in /*) ;; *) _refuse "upload refused: '$_a' is not an absolute path" ;; esac
        [ -f "$_a" ] || _refuse "upload refused: '$_a' is not a regular file"
        _rf="$(_phys "$_a")" || _refuse "upload refused: '$_a' could not be resolved (a link loop, or an unreadable directory)"
        case "$(_lc "$_rf")/" in "$_cd"/*|"$_hc"/*) _refuse "upload refused: '$_a' is under ~/.claude, which never goes to a web tool (CONSTITUTION №3)" ;; esac
        _links="$(ls -ld -- "$_rf" | awk '{ print $2 }')"
        [ "$_links" = 1 ] || _refuse "upload refused: '$_a' has $_links hard links, so where else it lives cannot be checked" "cp '$_a' \"\$TMPDIR/\" and upload the copy"
      done
    fi
    if [ "$VERB" = goto ] && [ $# -ne 1 ]; then _refuse 'goto takes exactly one url: https on an allowed host, or a dev server in a headless lane' "harbor chrome goto 'https://ads.reddit.com/'"; fi
    if [ "$VERB" = tab-new ] && [ $# -gt 1 ]; then _refuse 'tab-new takes at most one url: https on an allowed host, or a dev server in a headless lane' 'harbor chrome tab-new'; fi
    if { [ "$VERB" = goto ] || [ "$VERB" = tab-new ]; } && [ $# -eq 1 ]; then
      if _loopback_ok "$1" && ! _headless_lane; then
        _refuse "loopback refused: '$1' is a dev server, opened in a headless lane only (no profile, no cookies); in the operator's logged-in profile an agent-written page could send credentialed cross-site requests" \
          "HARBOR_ACCESS_BROWSER_LANE=dev harbor chrome attach --headless   # then $VERB in that lane"
      fi
      if ! _host_ok "$1"; then
        # The live-walk repo is the private layer's (harbor.toml live_walk_repo, harbor#1273), its checkout the
        # registry's (harbor#966); unset or unregistered, the hint says which, never a guessed path.
        _m="host refused: '$1' is not https on a host in contracts/browser-agent-hosts.txt or the private layer's browser-hosts.txt, nor, in a headless lane, a loopback dev server (http://localhost:<port> or http://127.0.0.1:<port>, port 1024-65535); client live sites go through the live-walk repo"
        _lr=0; _lw="$(sh "$HERE/scope-roots.sh" --conf live_walk_repo 2>/dev/null)" || _lr=$?
        [ "$_lr" -ne 2 ] || _handoff "$_m" "harbor-private/harbor.toml did not read: sh bin/scope-roots.sh --conf live_walk_repo"
        [ -n "$_lw" ] || _handoff "$_m" "no live-walk repo is set on this box: live_walk_repo in harbor-private/harbor.toml (contracts/private-layer.md)"
        _ts="$(sh "$HERE/scope-roots.sh" --repo "$_lw" 2>/dev/null)" || _ts=""
        case "$_ts" in "$HOME"/*) _ts="~${_ts#"$HOME"}" ;; esac
        if [ -n "$_ts" ]; then _handoff "${_m%the live-walk repo}$_lw" "cd $_ts && just live"
        else _handoff "${_m%the live-walk repo}$_lw" "$_lw is not registered on this box (sh bin/scope-roots.sh --repos); register it in harbor-private/repos.tsv"; fi
      fi
    fi
    { [ "$VERB" = goto ] || [ "$VERB" = tab-new ]; } && [ $# -eq 1 ] && _api_first "$1"
    # Held, not exec'd, so a gone session can be told apart (_gone_check, harbor#920).
    mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
    [ "$VERB" != tab-new ] || _before=" $(_tab_ids 2>/dev/null | tr '\n' ' ') "
    # The app asked for, so a sign-in it sends us to names the app's account, not the login host's.
    if { [ "$VERB" = goto ] || [ "$VERB" = tab-new ]; } && [ $# -eq 1 ] && ! _signin_url "$1"; then
      _url_host "$1" > "$WORKDIR/.app-host"
    fi
    _e="$(_relay_err)"; _el=0; [ -z "$_e" ] || _el="$(wc -l < "$_e" | tr -d ' ')"
    trap 'rm -f "$_o"' EXIT INT TERM HUP
    _rc=0
    if [ -n "$_sfn" ]; then
      _cli_run "-s=$S" --raw eval "$_sfn" ${_sref:+"$_sref"} > "$_o.raw" || _rc=$?
      # --raw prints the script's two lines as one JSON string; decoded here, so a refused line is never missed for want of jq
      awk '{ s = $0; sub(/^"/, "", s); sub(/"$/, "", s); o = ""
        while ((i = index(s, "\\")) > 0) { c = substr(s, i + 1, 1); o = o substr(s, 1, i - 1) (c == "n" ? "\n" : c == "t" ? "\t" : c); s = substr(s, i + 2) }
        print o s }' "$_o.raw" > "$_o"; rm -f "$_o.raw"
      case "$(head -n 1 "$_o")" in 'refused: '*|'unchanged: '*)
        _l="$(head -n 1 "$_o")"; rm -f "$_o"
        _refuse "$VERB${_sref:+ $_sref} by script: $_l" "harbor chrome $VERB $* --real   # the CLI's own verb; it needs the tab shown" ;;
      esac
    else
      _cli_run "-s=$S" "$VERB" "$@" > "$_o" || _rc=$?
    fi
    if [ "$VERB" = tab-new ] && [ "$_rc" -eq 0 ]; then
      _tab_ids 2>/dev/null | while IFS= read -r _id; do
        case "$_before" in *" $_id "*) ;; *) printf '%s\n' "$_id" >> "$WORKDIR/$OWNED_NAME" ;; esac
      done
    fi
    # A goto that fails on another extension's frame says so (login pages with a password field).
    if [ "$VERB" = goto ] && [ "$_rc" -ne 0 ] && [ -n "$_e" ] \
      && tail -n "+$((_el + 1))" "$_e" 2>/dev/null | /usr/bin/grep -q 'chrome-extension:// URL of different extension'; then
      _scrub < "$_o" >&2; rm -f "$_o"
      _acct="$(_account_for "$(_url_host "$1")")"
      _handoff "the tab was lost on load: another extension put a frame in the page (usually a password manager's autofill on a sign-in form), and Chrome lets no extension debug another's" \
        "operator: sign in to $(_url_host "$1")${_acct:+ as $_acct}; then harbor chrome wait-signin"
    fi
    # A failed navigation whose tab Chrome shows on a sign-in page: signed out, whatever the CLI
    # says (an ad platform, 2026-10-14: `TypeError … reading 'url'`, the page on its login host).
    if [ "$_rc" -ne 0 ] && [ -s "$WORKDIR/$OWNED_NAME" ]; then
      case "$VERB" in goto|tab-new|reload|go-back|go-forward|click|dblclick)
        _own=" $(cat "$WORKDIR/$OWNED_NAME" 2>/dev/null | tr '\n' ' ') "
        _pu="$(_chrome_tabs 2>/dev/null | awk -F '\t' -v o="$_own" 'NF >= 5 && index(o, " " $5 " ") > 0 { print $4 }' | while IFS= read -r _x; do
          if _signin_url "$_x"; then printf '%s\n' "$_x"; break; fi
        done)"
        if [ -n "$_pu" ]; then _scrub < "$_o" >&2; rm -f "$_o"; _signed_out "$_pu"; fi ;;
      esac
    fi
    [ "$_rc" -eq 0 ] || _gone_check "$_o"
    # Chrome lets an extension set a file input only with file-URL access (measured 2026-10-14).
    if [ "$VERB" = upload ] && [ "$_rc" -ne 0 ] && /usr/bin/grep -q 'setFileInputFiles.*Not allowed' "$_o"; then
      _scrub < "$_o" >&2; rm -f "$_o"
      _refuse 'upload refused by Chrome: the Playwright Extension has no access to file URLs' \
        "operator: chrome://extensions > Playwright Extension > Details > Allow access to file URLs (the extension can then read local files)"
    fi
    case "$VERB" in
      click|dblclick|fill|type|select|check|uncheck|drag|press|keydown|keyup|hover|mousedown|mouseup|mousewheel)
        if [ "$_rc" -eq 0 ]; then _lost_check "$_o"; else _hidden_check "$_o"; fi ;;
    esac
    # Signed out: the app sent the tab to sign-in. Stop and name the account (2026-10-14 field
    # test: ad-platform and shop sign-ins, a LinkedIn account picker).
    if [ "$_rc" -eq 0 ]; then
      _pu="$(sed -n 's/^- Page URL: //p' "$_o" | tail -1)"
      if [ -n "$_pu" ] && _signin_url "$_pu"; then _scrub < "$_o"; rm -f "$_o"; _signed_out "$_pu"; fi
    fi
    _scrub < "$_o"; exit "$_rc"
    ;;
esac
