#!/usr/bin/env sh
# access-browser-agent.sh — `harbor chrome`: drive the operator's own Chrome through
# the Playwright Extension, attended and guarded (harbor#472; router row 4).
# platform: macOS-only — Chrome's windows and tabs are read and closed through AppleScript (`osascript`);
# without it those steps fail soft, and the CLI still drives the session's tab.
#
#   harbor chrome attach           connect; the operator clicks Connect in Chrome, or no click when
#                                  the extension token is registered (ref playwright-extension-token)
#   harbor chrome status           this session's name, pin, profile, workdir
#   harbor chrome state            the page's own visibility, focus and load state (fixed probe)
#   harbor chrome doctor           is row 4 ready on this box
#   harbor chrome detach           release the operator's Chrome
#   harbor chrome tabs             every Chrome tab, by window, query strings cut; `=` marks this session's page
#   HARBOR_BROWSER_LANE=<a-z0-9> harbor chrome …   a parallel agent's own browser session, <session>-<lane>
#   harbor chrome front            make this session's tab the visible one and give focus back
#   harbor chrome wait-signin [s]  wait (default 300 s) while the operator signs in, then carry on
#   harbor chrome hosts            the allow-list goto/tab-new reads: core, then the private layer
#   harbor chrome click <ref> --force   click through an overlay ("not stable", covered)
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
LOG_FD=2
. "$HERE/library-log.sh"
log_init browser-agent

ROUTER='contracts/browser-routing.md, row 4'
HOSTS_FILE="$ROOT/contracts/browser-agent-hosts.txt"
# The private layer's own hosts (internal UIs and client tools; core names none), read after the core list. The
# env is the test seam; absent is the core list alone (contracts/private-layer.md).
PRIV_HOSTS="${HARBOR_BROWSER_PRIVATE_HOSTS:-}"
if [ -z "$PRIV_HOSTS" ]; then
  _pd="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"
  [ -z "$_pd" ] || PRIV_HOSTS="$_pd/browser-hosts.txt"
fi
# The extension token lives only in the Keychain, under this ref in the access register (harbor#1205); attach
# uses it when registered, so Chrome connects without the Allow click. A token in the caller's env stays refused.
TOKEN_REF='playwright-extension-token'
PW_CLI_PIN='0.1.22'   # exact pin (vendoring D1); 0.1.22 is the first that reads the profile name
STATE_EXPR='JSON.stringify({visibility: document.visibilityState, focus: document.hasFocus(), ready: document.readyState, host: location.host, blank: location.href === "about:blank", online: navigator.onLine})'
PW_EXTENSION_ID='mmlmfjhmonkocbjadbfplnigmagldckm'
PROFILE="${HARBOR_BROWSER_PROFILE:-Default}"
IDLE_MS="${HARBOR_BROWSER_IDLE_MS:-14400000}"   # 4 h, the ceiling below: one Connect click covers a working block
# Where Chrome keeps its profiles: ~/Library on macOS, the XDG config dir on Linux (harbor#618).
case "$(uname -s 2>/dev/null)" in
  Darwin) _chrome_data_default="$HOME/Library/Application Support/Google/Chrome" ;;
  *)      _chrome_data_default="${XDG_CONFIG_HOME:-$HOME/.config}/google-chrome" ;;
esac
CHROME_DATA="${HARBOR_CHROME_DATA:-$_chrome_data_default}"
CLAUDE_JSON="${HARBOR_CLAUDE_JSON:-$HOME/.claude.json}"
CONFIRM="${HARBOR_BROWSER_CONFIRM:-}"
# Whole words a click/dblclick target's label may not carry without the operator's
# per-call HARBOR_BROWSER_CONFIRM=<ref>. Whole words, so status text (Paused,
# Removed, Payments) passes; the label comes from a fresh snapshot (_guard).
DESTRUCTIVE='delete remove archive pause publish unpublish discard pay purchase buy unlink disconnect
  ištrinti pašalinti archyvuoti sustabdyti pristabdyti publikuoti paskelbti išjungti apmokėti'

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
  elif [ -n "${HARBOR_BROWSER_SESSION:-}" ]; then
    _s="$HARBOR_BROWSER_SESSION"
  else
    _s=''
  fi
  case "$_s" in ''|claude-|*[!A-Za-z0-9_-]*) return 1 ;; esac
  # A lane: parallel agents of ONE session each get their own browser session, as
  # <own name>-<lane>. Appended, never replacing, so a lane cannot name another session's.
  if [ -n "${HARBOR_BROWSER_LANE:-}" ]; then
    case "$HARBOR_BROWSER_LANE" in *[!abcdefghijklmnopqrstuvwxyz0-9]*) return 1 ;; esac
    [ "${#HARBOR_BROWSER_LANE}" -le 12 ] || return 1
    _s="$_s-$HARBOR_BROWSER_LANE"
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
    dialog-accept|dialog-dismiss|upload) return 0 ;;
  esac
  return 1
}

# https, host plain [a-z0-9.-] (a backslash once made Node load a different host
# than this check saw), equal to a listed host or a subdomain of one.
_host_ok() {
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

# Pinned CLI, from a per-session workdir so files never land in a repo. The CLI
# also takes config from any .playwright dir up that tree. HARBOR_PW_CLI is the
# test seam (a stub), as HARBOR_PROBE_DIR is for access-browser.sh.
_cli() {
  if [ -n "${HARBOR_PW_CLI:-}" ]; then
    set -- "$HARBOR_PW_CLI" "$@"
  elif command -v bunx >/dev/null 2>&1; then
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
# activating its own tab in the same window did that (2026-10-14). HARBOR_OSASCRIPT is the test seam.
_osa() { # <script on stdin> [args] — never launches Chrome
  "${HARBOR_OSASCRIPT:-/usr/bin/osascript}" - "$@"
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
  sleep "${HARBOR_CHROME_SETTLE:-1}"
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
  printf ' %s ' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/Š/š/g; s/Ė/ė/g' | LC_ALL=C tr -c 'a-z0-9\200-\377' ' '
}
_destructive() { # <label> — prints the first word of $DESTRUCTIVE it carries
  _w=" $(_words "$1") "
  for _d in $DESTRUCTIVE; do
    case "$_w" in *" $_d "*) printf '%s' "$_d"; return 0 ;; esac
  done
  return 1
}

# click/dblclick: take a fresh full snapshot (a partial one replaces the CLI's ref
# table and breaks the next click; refs are element-bound, so a full one keeps
# them), read the target's label and box, and refuse a destructive label unless
# the operator confirmed this ref for this call. Sets G_LABEL, G_BOX.
_guard() { # <verb> <ref>
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
      _handoff "destructive $1 refused: '$G_LABEL' ($2) matches '$_hit' — the operator confirms one call" "HARBOR_BROWSER_CONFIRM=$2 harbor chrome $1 $2"
    fi
  fi
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
      _refuse "forced click on $1 refused: the press at $_xy lands on or through '$_l' ($_r), which matches '$_hit'" "HARBOR_BROWSER_CONFIRM=$1 harbor chrome click $1 --force"
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
  click|dblclick) ;;
  *) [ -z "$CONFIRM" ] || _refuse "HARBOR_BROWSER_CONFIRM is set for '$VERB'; it confirms one click and is set on that call only, never exported" 'unset HARBOR_BROWSER_CONFIRM' ;;
esac

# 0 disables the CLI's idle timer (armed only when truthy), so it is bounded.
case "$IDLE_MS" in
  ''|*[!0-9]*) _refuse "HARBOR_BROWSER_IDLE_MS is not milliseconds: $IDLE_MS" 'unset HARBOR_BROWSER_IDLE_MS' ;;
esac
if [ "$IDLE_MS" -lt 60000 ] || [ "$IDLE_MS" -gt 14400000 ]; then
  _refuse "HARBOR_BROWSER_IDLE_MS must be 60000..14400000 (1 min to 4 h): $IDLE_MS" 'unset HARBOR_BROWSER_IDLE_MS'
fi
case "$PROFILE" in
  ''|*[!A-Za-z0-9\ ]*) _refuse "HARBOR_BROWSER_PROFILE is not a Chrome profile dir name: $PROFILE" 'unset HARBOR_BROWSER_PROFILE' ;;
esac

S="$(_session)" || _refuse 'no session: run inside Claude Code (CLAUDE_CODE_SESSION_ID), or set HARBOR_BROWSER_SESSION outside it; a HARBOR_BROWSER_LANE is 1-12 of a-z0-9' 'export HARBOR_BROWSER_SESSION=manual'
WORKDIR="${TMPDIR:-/tmp}"; WORKDIR="${WORKDIR%/}/harbor-browser/$S"

case "$VERB" in
  attach)
    [ "$(_ext_off)" != yes ] || _refuse "the Playwright Extension is switched off in Chrome profile $PROFILE; Chrome would block its connect page (ERR_BLOCKED_BY_CLIENT)" "chrome://extensions in profile $PROFILE: switch Playwright Extension on"
    if sh "$ROOT/bin/access.sh" has "$TOKEN_REF" >/dev/null 2>&1; then
      _CLI_TOKEN=1
      log_note "attach: connecting with the registered extension token ($TOKEN_REF), no Allow click; the host allow-list still holds"
    else
      log_note "approve in Chrome: the Playwright Extension tab that just opened (connect.html) IS the approval page; click Allow, then click Connect next to any tab. One click lasts until 4 h idle or harbor chrome detach"
    fi
    PLAYWRIGHT_MCP_PROFILE_DIR_NAME="$PROFILE"; export PLAYWRIGHT_MCP_PROFILE_DIR_NAME
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
    until mkdir "$_lk" 2>/dev/null; do
      _i=$((_i + 1)); [ "$_i" -le 60 ] || { log_warn "attach: $_lk held for 60 s; taking it"; break; }
      sleep 1
    done
    trap 'rmdir "$_lk" 2>/dev/null' EXIT INT TERM HUP
    _before=" $(_tab_ids 2>/dev/null | tr '\n' ' ') "
    _nw="$(_osa <<'OSA' 2>/dev/null
on run argv
  if application "Google Chrome" is not running then return ""
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
    case "$_tid" in
      ''|*[!0-9]*) _tid=''; log_warn 'attach: no window of its own (AppleScript refused); the extension opens its tab in the focused window, and another session there can hide it' ;;
    esac
    _ao="$(mktemp "$WORKDIR/.out.XXXXXX")"
    trap 'rmdir "$_lk" 2>/dev/null; rm -f "$_ao"' EXIT INT TERM HUP
    [ -z "$_tid" ] || printf '%s\n' "$_wid" > "$WORKDIR/.window"
    _rc=0; _cli_run "-s=$S" attach --extension=chrome "--idle-timeout=$IDLE_MS" > "$_ao" 2>&1 || _rc=$?
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
    exit "$_rc"
    ;;
  detach)
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
  tabs)
    [ $# -eq 0 ] || _refuse 'tabs takes no arguments' 'harbor chrome tabs'
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
    _me="$(_session_url)"
    [ -n "$_me" ] || _refuse "no page in session $S to bring to the front" 'harbor chrome attach'
    # Matched by suffix: the whole URL, or after marking, the mark alone.
    _n="$(_chrome_tabs | awk -F '\t' -v u="$_me" 'substr($4, length($4) - length(u) + 1) == u' | wc -l | tr -d ' ')"
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
    _r="$(_osa "$_me" <<'OSA'
on run argv
  set u to item 1 of argv
  set res to ""
  tell application "System Events" to set prev to bundle identifier of first process whose frontmost is true
  tell application "Google Chrome"
    -- by id: `w` is "window k" by position, and raising it renumbers the windows
    set ids to id of every window
    repeat with k from 1 to (count ids)
      set wid to item k of ids
      set w to window id wid
      repeat with t from 1 to (count tabs of w)
        if URL of tab t of w ends with u then
          -- shown, not raised: a covered window still paints; a minimised one does not
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
    sleep "${HARBOR_CHROME_SETTLE:-1}"
    _p="$(_cli_run "-s=$S" --raw eval "$STATE_EXPR" 2>/dev/null)" || _p=''
    case "$_p" in *'visibility\":\"hidden'*|*'"visibility":"hidden'*)
      _handoff "front: $_r is active in its window, but the page is still hidden (the window is minimised again, or on another Space)" 'harbor chrome tabs   # then bring that window up by hand; never minimise a harbor window' ;;
    esac
    log_ok "front: $_r is the tab Chrome shows; focus left where it was"
    ;;
  wait-signin)
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
      sleep "${HARBOR_CHROME_POLL:-3}"; _t=$((_t + ${HARBOR_CHROME_POLL:-3}))
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
    sh "$HERE/access-browser-agent.sh" attach >&2 || _refuse 'signed in, but the re-attach failed' 'harbor chrome attach'
    exec sh "$HERE/access-browser-agent.sh" goto "$_u"
    ;;
  status)
    _e="$(_relay_err)"
    _r=''; [ -z "$_e" ] || _r="$(/usr/bin/grep 'WebSocket closed' "$_e" | tail -1 | cut -c1-200 || :)"
    printf 'session  %s\npin      @playwright/cli@%s\nprofile  %s\nworkdir  %s\nidle     %s ms\nrelay    %s\n' \
      "$S" "$PW_CLI_PIN" "$PROFILE" "$WORKDIR" "$IDLE_MS" "${_r:-no close recorded${_e:+ in $_e}}"
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
        -*) _refuse "option refused: $_a — only --filename=<name>, on fill and type --submit, and on click --force and --modifiers=<Alt|Control|ControlOrMeta|Meta|Shift>" ;;
      esac
    done
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
        || _refuse "HARBOR_BROWSER_CONFIRM=$CONFIRM does not name this target ($_ref); it confirms one call on one ref"
      _guard "$VERB" "$_ref"
      if [ -n "$_force" ]; then
        [ -z "$_mods" ] || _refuse '--force cannot carry --modifiers; the mouse verbs it uses take none'
        _force_click "$_ref" "$_btn"
      fi
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
    if [ "$VERB" = goto ] && [ $# -ne 1 ]; then _refuse 'goto takes exactly one https url' "harbor chrome goto 'https://ads.reddit.com/'"; fi
    if [ "$VERB" = tab-new ] && [ $# -gt 1 ]; then _refuse 'tab-new takes at most one https url' 'harbor chrome tab-new'; fi
    if { [ "$VERB" = goto ] || [ "$VERB" = tab-new ]; } && [ $# -eq 1 ]; then
      if ! _host_ok "$1"; then
        # The live-walk repo is the private layer's (harbor.toml live_walk_repo, harbor#1273), its checkout the
        # registry's (harbor#966); unset or unregistered, the hint says which, never a guessed path.
        _m="host refused: '$1' is not https on a host in contracts/browser-agent-hosts.txt or the private layer's browser-hosts.txt; client live sites go through the live-walk repo"
        _lr=0; _lw="$(sh "$HERE/scope-roots.sh" --conf live_walk_repo 2>/dev/null)" || _lr=$?
        [ "$_lr" -ne 2 ] || _handoff "$_m" "harbor-private/harbor.toml did not read: sh bin/scope-roots.sh --conf live_walk_repo"
        [ -n "$_lw" ] || _handoff "$_m" "no live-walk repo is set on this box: live_walk_repo in harbor-private/harbor.toml (contracts/private-layer.md)"
        _ts="$(sh "$HERE/scope-roots.sh" --repo "$_lw" 2>/dev/null)" || _ts=""
        case "$_ts" in "$HOME"/*) _ts="~${_ts#"$HOME"}" ;; esac
        if [ -n "$_ts" ]; then _handoff "${_m%the live-walk repo}$_lw" "cd $_ts && just live"
        else _handoff "${_m%the live-walk repo}$_lw" "$_lw is not registered on this box (sh bin/scope-roots.sh --repos); register it in harbor-private/repos.tsv"; fi
      fi
    fi
    # Held, not exec'd, so a gone session can be told apart (_gone_check, harbor#920).
    mkdir -p "$WORKDIR"; _o="$(mktemp "$WORKDIR/.out.XXXXXX")"
    [ "$VERB" != tab-new ] || _before=" $(_tab_ids 2>/dev/null | tr '\n' ' ') "
    # The app asked for, so a sign-in it sends us to names the app's account, not the login host's.
    if { [ "$VERB" = goto ] || [ "$VERB" = tab-new ]; } && [ $# -eq 1 ] && ! _signin_url "$1"; then
      _url_host "$1" > "$WORKDIR/.app-host"
    fi
    _e="$(_relay_err)"; _el=0; [ -z "$_e" ] || _el="$(wc -l < "$_e" | tr -d ' ')"
    trap 'rm -f "$_o"' EXIT INT TERM HUP
    _rc=0; _cli_run "-s=$S" "$VERB" "$@" > "$_o" || _rc=$?
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
