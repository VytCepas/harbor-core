#!/usr/bin/env sh
# access-browser-flow.sh (harbor#1445, #457) — record a flow once, replay it as a script, on a
# disposable SIGNED-OUT headless browser. Never the attended `harbor chrome` channel, which refuses
# recording on purpose (access-browser-agent.sh, _allowed).
#
#   sh bin/access-browser-flow.sh record <flow.js> <url> <steps.tsv|->   run the steps once, save what the CLI recorded
#   sh bin/access-browser-flow.sh replay <flow.js> [--shot <png>] [--text <css>]   run the saved file in a fresh browser
#   sh bin/access-browser-flow.sh check <flow.js>                         is the file one this tool would run (no browser)
#
# steps.tsv: one step per line, TAB-separated `verb<TAB>css-selector<TAB>value`; verbs click dblclick hover
# fill type select check uncheck press. --text prints the element's text (the end state) on stdout.
# The browser is a fresh isolated context (in memory) with a throwaway profile dir, removed on exit;
# every run asserts no Cookies / Login Data database in it holds a row. Stdout is data, the log is stderr.
# A guardrail against accidents and an injected agent's obvious moves, not a security boundary.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$HERE/library-log.sh"
log_init browser-flow

# One pin for both tools: read it from the attended channel's file rather than copy it.
PW_CLI_PIN="$(sed -n "s/^PW_CLI_PIN='\\([^']*\\)'.*/\\1/p" "$HERE/access-browser-agent.sh" | head -n 1)"
TAB="$(printf '\t')"
WORK='' SESSION="hbflow-$$" _tmpflow='' _stepfile=''

_refuse() { log_fail "$1"; log_fix "${2:-sh bin/access-browser-flow.sh --help}"; log_end || :; exit 1; }
_usage() { sed -n '/^#   sh bin\/access-browser-flow.sh record/,/^# every run asserts/p' "$0" | sed 's/^# \{0,2\}//'; }

# The test seam is the attended channel's own: a stub CLI instead of bunx. stdin is cut: the CLI drains it,
# and a call inside the steps loop would eat the remaining steps.
_cli() {
  if [ -n "${HARBOR_ACCESS_PLAYWRIGHT_CLI:-}" ]; then "$HARBOR_ACCESS_PLAYWRIGHT_CLI" -s="$SESSION" "$@" </dev/null
  else bunx "@playwright/cli@$PW_CLI_PIN" -s="$SESSION" "$@" </dev/null; fi
}

_cleanup() {
  [ -z "$_tmpflow" ] || rm -f "$_tmpflow"
  [ -z "$_stepfile" ] || rm -f "$_stepfile"
  if [ -n "$WORK" ]; then _cli close >/dev/null 2>&1 || :; rm -rf "$WORK"; fi
}

trap _cleanup EXIT
trap 'exit 130' INT TERM

# http(s) only, no userinfo, nothing that could leave the quotes of the saved file.
_url_ok() {
  case "$1" in http://*|https://*) ;; *) return 1 ;; esac
  case "$1" in *\'*|*\"*|*\\*|*\`*|*' '*|*"$TAB"*|*@*|*'$'*) return 1 ;; esac
  return 0
}

# The file is run as code in the page's browser, so it must be one this tool wrote: header, one goto, locator
# actions only. Not a sandbox: it keeps a hand-edited file from carrying anything but the recorded shape.
_flow_ok() { # <file>
  [ -f "$1" ] || { _FLOW_WHY="no such file: $1"; return 1; }
  _FLOW_WHY="$(awk '
    NR == 1 { if ($0 != "// access-browser-flow v1") { print "line 1 is not the v1 header"; exit } next }
    NR == 2 { if ($0 != "async (page) => {") { print "line 2 is not the function opener"; exit } next }
    /^  page\.setDefaultTimeout\([0-9]+\);$/ { to++; next }
    /^  await page\.goto\(.http(s)?:\/\/[^'"'"'"` \\@$]*.\);$/ { go++; next }
    /^}$/ { closed = NR; next }
    closed { print "line " NR " follows the closing brace"; exit }
    /^  await page\.(getBy[A-Za-z]+|locator)\(.*\)\.(click|dblclick|hover|fill|type|selectOption|check|uncheck|press|pressSequentially)\(.*\);$/ {
      if ($0 ~ /(require|import|process|eval|Function|constructor|fetch|globalThis|child_process|=>|`|\$\{)/) { print "line " NR " names something a flow may not"; exit }
      n++; next }
    { print "line " NR " is not a recorded locator action"; exit }
    END { if (!closed && !NR) print "empty file"; else if (!closed) print "no closing brace"
          else if (go != 1) print "want exactly one goto"; else if (to != 1) print "want exactly one default timeout"; else if (!n) print "no recorded action" }
  ' "$1")"
  [ -z "$_FLOW_WHY" ]
}

# No Cookies / Login Data database under <dir> holds a row. Chromium makes those files empty in every profile,
# so their names prove nothing; their rows do. Fails closed: no sqlite3 means no verdict.
_profile_signed_out() { # <dir>
  command -v sqlite3 >/dev/null 2>&1 || { _PROF_WHY='no sqlite3 on PATH to count rows'; return 1; }
  _PROF_WHY=''
  _pl="$(find "$1" -type f \( -name Cookies -o -name 'Login Data' -o -name 'Login Data For Account' \) 2>/dev/null)"
  _pn=0
  while IFS= read -r _pf; do
    [ -n "$_pf" ] || continue
    case "${_pf##*/}" in Cookies) _pt=cookies ;; *) _pt=logins ;; esac
    # Chromium holds Login Data under an exclusive lock, so the count is taken on a copy.
    _pc="$(mktemp "${TMPDIR:-/tmp}/hbf-db.XXXXXX")"; cp "$_pf" "$_pc" 2>/dev/null || :
    _pr="$(sqlite3 "$_pc" "select count(*) from $_pt" 2>/dev/null)" || _pr=unreadable
    rm -f "$_pc"
    [ "$_pr" != unreadable ] || { _PROF_WHY="cannot read $_pf"; return 1; }
    _pn=$((_pn + 1))
    [ "$_pr" = 0 ] || { _PROF_WHY="${_pf##*/} holds $_pr rows"; return 1; }
  done <<EOF
$_pl
EOF
  _PROF_N="$_pn"
  return 0
}

# A fresh work dir (the env is the test seam). Short on purpose: the CLI's daemon socket lives under TMPDIR and a unix socket path stops
# near 100 bytes. TMPDIR is pointed inside it so the browser's throwaway profile is ours to inspect and remove.
_start() {
  WORK="$(mktemp -d "${HARBOR_ACCESS_BROWSER_FLOW_WORKROOT:-/tmp}/hbf.XXXXXX")"; mkdir -p "$WORK/t"
  TMPDIR="$WORK/t"; export TMPDIR
  cd "$WORK"
  _before="$(find "$WORK/t" -type f \( -name Cookies -o -name 'Login Data' \) 2>/dev/null | wc -l | tr -d ' ')"
  [ "$_before" = 0 ] || _refuse "the profile dir was not empty before the run ($_before files)"
  log_ok 'profile before the run: no Cookies or Login Data under the empty throwaway dir'
  # No --headed, --persistent or --profile exist in this tool: the browser is headless and in memory.
  _cli open --idle-timeout=600000 >/dev/null 2>&1 || _refuse 'the browser would not open' 'bunx on PATH? (harbor chrome doctor)'
  log_ok 'headless isolated browser open'
}

_finish() { # after the steps, before close: the profile still exists, so this is the live check
  if _profile_signed_out "$WORK/t"; then log_ok "profile during the run: ${_PROF_N:-0} Cookies/Login Data databases, no row in any"
  else _refuse "the profile is not signed out: $_PROF_WHY" 'discard the run; use the attended channel only for signed-in work'; fi
}

_after() { # after close
  _cli close >/dev/null 2>&1 || :
  _left="$(find "$WORK/t" -type f \( -name Cookies -o -name 'Login Data' \) 2>/dev/null | wc -l | tr -d ' ')"
  [ "$_left" = 0 ] || _refuse "the profile still holds $_left Cookies/Login Data files after the run"
  log_ok 'profile after the run: no Cookies or Login Data left'
}

_record() { # <flow.js> <url> <steps>
  [ $# -eq 3 ] || _refuse 'record wants <flow.js> <url> <steps.tsv|->'
  _flow="$1"; _url="$2"; _steps="$3"
  _url_ok "$_url" || _refuse "not an http(s) URL this tool will record: $_url"
  _stepfile="$(mktemp "${TMPDIR:-/tmp}/hbf-steps.XXXXXX")"
  if [ "$_steps" = - ]; then cat > "$_stepfile"; else [ -f "$_steps" ] || _refuse "no such steps file: $_steps"; cp "$_steps" "$_stepfile"; fi
  # Validate every step before a browser exists.
  _ln=0
  while IFS="$TAB" read -r _v _a _b || [ -n "$_v" ]; do
    _ln=$((_ln + 1))
    case "$_v" in ''|'#'*) continue ;; esac
    case "$_v:$_a" in
      click:?*|dblclick:?*|hover:?*|check:?*|uncheck:?*|press:?*|type:?*) [ -z "${_b:-}" ] || { rm -f "$_stepfile"; _refuse "steps line $_ln: $_v takes one argument"; } ;;
      fill:?*|select:?*) [ -n "${_b:-}" ] || { rm -f "$_stepfile"; _refuse "steps line $_ln: $_v wants a selector and a value"; } ;;
      *) rm -f "$_stepfile"; _refuse "steps line $_ln: '$_v' is not a recordable step (click dblclick hover fill type select check uncheck press)" ;;
    esac
  done < "$_stepfile"
  _outdir="$(CDPATH='' cd -- "$(dirname -- "$_flow")" && pwd)" || { rm -f "$_stepfile"; _refuse "no such directory for $_flow"; }
  _flow="$_outdir/$(basename -- "$_flow")"
  _start
  _cli goto "$_url" >/dev/null 2>&1 || _refuse "could not load $_url"
  _cli recording-start >/dev/null 2>&1 || _refuse 'the CLI would not start recording'
  while IFS="$TAB" read -r _v _a _b || [ -n "$_v" ]; do
    case "$_v" in ''|'#'*) continue ;; esac
    if [ "$_v" = fill ] || [ "$_v" = select ]; then _cli "$_v" "$_a" "$_b" >/dev/null 2>&1 || _refuse "step failed: $_v $_a"
    else _cli "$_v" "$_a" >/dev/null 2>&1 || _refuse "step failed: $_v $_a"; fi
  done < "$_stepfile"
  rm -f "$_stepfile"
  _rec="$(_cli recording-stop 2>&1)" || _refuse 'the CLI would not stop recording'
  _body="$(printf '%s\n' "$_rec" | awk '/Recorded actions:/ { s = 1; next } s && /^```js$/ { c = 1; next } c && /^```$/ { exit } c { print }')"
  [ -n "$_body" ] || _refuse 'the CLI recorded no actions' 'check the selectors in the steps file against the page'
  _tmpflow="$_flow.tmp.$$"
  {
    printf '%s\n' '// access-browser-flow v1' 'async (page) => {' '  page.setDefaultTimeout(5000);'
    printf "  await page.goto('%s');\n" "$_url"
    printf '%s\n' "$_body" | sed 's/^/  /'
    printf '%s\n' '}'
  } > "$_tmpflow"
  _finish
  _after
  _flow_ok "$_tmpflow" || { rm -f "$_tmpflow"; _refuse "the recorded file would not replay: $_FLOW_WHY" 'the CLI printed code this tool does not accept'; }
  mv "$_tmpflow" "$_flow"
  log_ok "recorded $(printf '%s\n' "$_body" | wc -l | tr -d ' ') actions to $_flow"
  printf '%s\n' "$_flow"
}

_replay() { # <flow.js> [--shot png] [--text css]
  [ $# -ge 1 ] || _refuse 'replay wants <flow.js>'
  _flow="$1"; shift; _shot='' _text=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --shot) [ $# -ge 2 ] || _refuse '--shot needs a path'; _shot="$2"; shift ;;
      --text) [ $# -ge 2 ] || _refuse '--text needs a selector'; _text="$2"; shift ;;
      *) _refuse "unknown option: $1" ;;
    esac
    shift
  done
  _flow_ok "$_flow" || _refuse "not a flow this tool will run: $_FLOW_WHY" 'record one: sh bin/access-browser-flow.sh record <flow.js> <url> <steps.tsv>'
  case "$_text" in *\'*|*\"*|*\\*|*'`'*) _refuse '--text takes a plain CSS selector' ;; esac
  _flow="$(CDPATH='' cd -- "$(dirname -- "$_flow")" && pwd)/$(basename -- "$_flow")"
  if [ -n "$_shot" ]; then
    _sd="$(CDPATH='' cd -- "$(dirname -- "$_shot")" 2>/dev/null && pwd)" || _refuse "no such directory for $_shot"
    _shot="$_sd/$(basename -- "$_shot")"
  fi
  _start
  _o="$WORK/replay.out"
  if ! _cli run-code --filename="$_flow" > "$_o" 2>&1; then
    _refuse "the replay failed: $(grep -m1 -E '^[A-Za-z]*Error' "$_o" || echo 'see the flow file')" 'a recorded selector no longer matches the page: record the flow again'
  fi
  log_ok "replayed $_flow"
  if [ -n "$_text" ]; then
    _cli --raw eval 'e => e.innerText' "$_text" 2>/dev/null | sed 's/^"//; s/"$//'
  fi
  if [ -n "$_shot" ]; then
    _cli screenshot --filename="$_shot" >/dev/null 2>&1 || _refuse 'the screenshot failed'
    log_ok "end state saved: $_shot"
  fi
  _finish
  _after
}

case "${1:-}" in
  -h|--help|help|'') _usage; exit 0 ;;
  record) shift; _record "$@" ;;
  replay) shift; _replay "$@" ;;
  check) shift; [ $# -eq 1 ] || _refuse 'check wants <flow.js>'
         _flow_ok "$1" || _refuse "not a flow this tool will run: $_FLOW_WHY"
         log_ok "$1 is a flow this tool will run" ;;
  *) _refuse "unknown verb: $1" ;;
esac
log_end
