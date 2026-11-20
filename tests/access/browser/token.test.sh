#!/usr/bin/env sh
# `harbor chrome attach` connects with the extension token only when the access register names it
# (harbor#1205): the token comes from the Keychain through bin/secret, reaches the attach daemon only,
# and a token in the caller's env is still refused. `harbor chrome hosts` prints the allow-list it reads.
# A temp private layer and the file-backed keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AGENT="$T_ROOT/bin/access-browser-agent.sh"
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
VAL="fake-extension-token-0123456789"
STUB="$T_TMP/pw-stub"
printf '#!/bin/sh\nprintf "STUB args=%%s token=%%s\\n" "$*" "${PLAYWRIGHT_MCP_EXTENSION_TOKEN:-none}"\n' > "$STUB"; chmod +x "$STUB"
PH="$T_TMP/private-hosts.txt"; printf '# a private vendor\nintranet.example.net\n' > "$PH"
# An AppleScript stub answering "Chrome is not running": the real osascript would open a window in the operator's Chrome, and
# where it was refused attach used to go on anyway, which these cases relied on until attach refused that (2026-11-20).
NOOSA="$T_TMP/osa-notrunning"; printf '#!/bin/sh\ncase "$(cat)" in *"make new window"*) printf notrunning ;; esac\n' > "$NOOSA"; chmod +x "$NOOSA"
ag() { env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_ACCESS_BROWSER_OSASCRIPT="$NOOSA" HARBOR_ACCESS_BROWSER_PRIVATE_HOSTS="$PH" HARBOR_ACCESS_PLAYWRIGHT_CLI="$STUB" \
  CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
out() { cat "$T_TMP/out"; }

t_section "no token registered: attach stays attended"
t_eq "attach exits 0" "exit 0" "$(ag attach --operator)"
t_has "the daemon got no token" "$(out)" "token=none"
t_has "and the operator is told to click Allow" "$(out)" "approve in Chrome"

t_section "the token registered and stored: attach connects with it, no click"
printf '\n## playwright-extension\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: playwright-extension-token\n' >> "$REG"
printf '%s' "$VAL" | sh "$T_ROOT/bin/secret" put playwright-extension-token >/dev/null 2>&1
t_eq "attach exits 0" "exit 0" "$(ag attach --operator)"
t_has "the daemon got the stored token" "$(out)" "token=$VAL"
t_has "the log says no Allow click" "$(out)" "no Allow click"
t_hasnt "and never prints the value outside the daemon's own line" "$(out | grep -v '^STUB ')" "$VAL"
t_eq "a later verb runs" "exit 0" "$(ag goto https://ads.google.com/)"
t_has "without the token: only attach carries it" "$(out)" "token=none"

t_section "with the token, focus goes back to the operator's app (harbor#1569)"
# An AppleScript stub: no case opens a window or activates an app on this box. It logs which focus script ran,
# answers the window step as the operator in $STUB_PREV_APP, and a watcher that outlives attach leaves a marker.
# The CLI stub takes 1 s, as a real connect takes time: the watcher runs while it does.
FOCUS_OSASCRIPT="$T_TMP/focus-osa"; FOCUS_CALLS="$T_TMP/focus-calls"; FOCUS_CLI="$T_TMP/pw-slow"; : > "$FOCUS_CALLS"
cat > "$FOCUS_OSASCRIPT" <<EOF
#!/bin/sh
sc="\$(cat)"
case "\$sc" in
  *'make new window'*) printf '9\t501\t%s\t7' "\${STUB_PREV_APP:-com.apple.Terminal}" ;;
  *'harbor-focus-watch'*) echo "focuswatch \$2" >> "$FOCUS_CALLS"
    [ -z "\${STUB_WATCH_SLEEP:-}" ] || { sleep "\$STUB_WATCH_SLEEP"; echo watchsurvived >> "$FOCUS_CALLS"; } ;;
  *'harbor-focus-back'*) echo "focusback \$2" >> "$FOCUS_CALLS"; [ -z "\${STUB_FOCUS_FAIL:-}" ] || exit 1 ;;
esac
EOF
# the CLI stub logs its connect into the same file, so the order of connect and hand-back is visible
printf '#!/bin/sh\nsleep 1\necho connected >> "%s"\nprintf "STUB args=%%s\\n" "$*"\n' "$FOCUS_CALLS" > "$FOCUS_CLI"; chmod +x "$FOCUS_OSASCRIPT" "$FOCUS_CLI"
focus_attach() { env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_ACCESS_BROWSER_OSASCRIPT="$FOCUS_OSASCRIPT" HARBOR_ACCESS_BROWSER_PRIVATE_HOSTS="$PH" \
  HARBOR_ACCESS_PLAYWRIGHT_CLI="$FOCUS_CLI" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
focus_count() { grep -c -- "$1" "$FOCUS_CALLS" 2>/dev/null || :; }
t_eq "attach exits 0" "exit 0" "$(focus_attach attach --operator)"
t_eq "a watcher hands focus back while the extension connects" 1 "$(focus_count 'focuswatch com.apple.Terminal')"
t_eq "and focus goes back once more after the connect" 1 "$(focus_count 'focusback com.apple.Terminal')"
t_eq "that hand-back comes after the connect, never before it" "connected focusback" \
  "$(grep -E '^(connected|focusback)' "$FOCUS_CALLS" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
STUB_FOCUS_FAIL=1; export STUB_FOCUS_FAIL; focus_attach attach --operator >/dev/null; unset STUB_FOCUS_FAIL
t_has "a refused hand-back is reported, not silent" "$(out)" "could not hand focus back to com.apple.Terminal"
_f0="$(focus_count focus)"; STUB_PREV_APP=com.google.Chrome; export STUB_PREV_APP; focus_attach attach --operator >/dev/null; unset STUB_PREV_APP
t_eq "with the operator in Chrome, no app is activated" "$_f0" "$(focus_count focus)"
_f0="$(focus_count focus)"; STUB_PREV_APP='com.x"; do shell script "id'; export STUB_PREV_APP; focus_attach attach --operator >/dev/null; unset STUB_PREV_APP
t_eq "an app id that is not a plain bundle id is never passed on" "$_f0" "$(focus_count focus)"
STUB_WATCH_SLEEP=2; export STUB_WATCH_SLEEP; focus_attach attach --operator >/dev/null; unset STUB_WATCH_SLEEP; sleep 3
t_eq "the watcher never outlives attach" 0 "$(focus_count watchsurvived)"

t_section "a token in the caller's env is still refused"
t_eq "attach with an ambient token exits 1" "exit 1" "$(env PLAYWRIGHT_MCP_EXTENSION_TOKEN=x HARBOR_ACCESS_PLAYWRIGHT_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" attach > "$T_TMP/out" 2>&1; echo "exit $?")"
t_hasnt "and the CLI never ran" "$(out)" "STUB"

t_section "hosts: the allow-list goto and tab-new read"
t_eq "hosts exits 0" "exit 0" "$(ag hosts)"
t_has "it lists a core host" "$(out)" "google.com"
t_has "and a private-layer host" "$(out)" "intranet.example.net"
t_has "each source is named" "$(out)" "# $PH"
t_eq "no comment line from the files leaks through" 0 "$(out | grep -c '^# a private vendor')"
t_done
