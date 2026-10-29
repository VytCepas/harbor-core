#!/usr/bin/env sh
# `harbor chrome attach` connects with the extension token only when the access register names it
# (harbor#1205): the token comes from the Keychain through bin/secret, reaches the attach daemon only,
# and a token in the caller's env is still refused. `harbor chrome hosts` prints the allow-list it reads.
# A temp private layer and the file-backed keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../keychain-stub.sh"
AGENT="$T_ROOT/bin/browser-agent.sh"
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
VAL="fake-extension-token-0123456789"
STUB="$T_TMP/pw-stub"
printf '#!/bin/sh\nprintf "STUB args=%%s token=%%s\\n" "$*" "${PLAYWRIGHT_MCP_EXTENSION_TOKEN:-none}"\n' > "$STUB"; chmod +x "$STUB"
PH="$T_TMP/private-hosts.txt"; printf '# a private vendor\nintranet.example.net\n' > "$PH"
ag() { env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_PRIVATE_HOSTS="$PH" HARBOR_PW_CLI="$STUB" \
  CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
out() { cat "$T_TMP/out"; }

t_section "no token registered: attach stays attended"
t_eq "attach exits 0" "exit 0" "$(ag attach)"
t_has "the daemon got no token" "$(out)" "token=none"
t_has "and the operator is told to click Allow" "$(out)" "approve in Chrome"

t_section "the token registered and stored: attach connects with it, no click"
printf '\n## playwright-extension\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: playwright-extension-token\n' >> "$REG"
printf '%s' "$VAL" | sh "$T_ROOT/bin/secret" put playwright-extension-token >/dev/null 2>&1
t_eq "attach exits 0" "exit 0" "$(ag attach)"
t_has "the daemon got the stored token" "$(out)" "token=$VAL"
t_has "the log says no Allow click" "$(out)" "no Allow click"
t_hasnt "and never prints the value outside the daemon's own line" "$(out | grep -v '^STUB ')" "$VAL"
t_eq "a later verb runs" "exit 0" "$(ag goto https://ads.google.com/)"
t_has "without the token: only attach carries it" "$(out)" "token=none"

t_section "a token in the caller's env is still refused"
t_eq "attach with an ambient token exits 1" "exit 1" "$(env PLAYWRIGHT_MCP_EXTENSION_TOKEN=x HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" attach > "$T_TMP/out" 2>&1; echo "exit $?")"
t_hasnt "and the CLI never ran" "$(out)" "STUB"

t_section "hosts: the allow-list goto and tab-new read"
t_eq "hosts exits 0" "exit 0" "$(ag hosts)"
t_has "it lists a core host" "$(out)" "google.com"
t_has "and a private-layer host" "$(out)" "intranet.example.net"
t_has "each source is named" "$(out)" "# $PH"
t_eq "no comment line from the files leaks through" 0 "$(out | grep -c '^# a private vendor')"
t_done
