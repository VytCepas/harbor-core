#!/usr/bin/env sh
# browser.sh: the offline gates, a router derived from its contract, honest skips (harbor#446, #457, #458, #724).
# Playwright is a stub probe dir, so the offline arms run the same on every host. The live
# consent arms run only when HARBOR_PROBE_DIR is exported at a real Playwright install.
LIVE_PROBE="${HARBOR_PROBE_DIR:-}"; LIVE_URL="${HARBOR_BROWSER_LIVE_URL:-}"  # before t_init clears them
REQUIRE_NODE="${HARBOR_REQUIRE_NODE:-}"  # set by the runner image that carries node (harbor#1060)
. "$(dirname "$0")/../lib/core.sh"; t_init
BROWSER="$T_ROOT/bin/browser.sh"; AGENT="$T_ROOT/bin/browser-agent.sh"; ROUTING="$T_ROOT/CONTRACTS/browser-routing.md"
unset HARBOR_CHROME
# No settle after input verbs, except in the one test that measures the race.
HARBOR_CHROME_SETTLE=0; export HARBOR_CHROME_SETTLE
P="$T_TMP/probe"; mkdir -p "$P/node_modules/playwright" "$T_TMP/empty"
printf '%s\n' "export const chromium = { launch: async () => { throw new Error('playwright stub: no launch offline'); } };" \
  > "$P/node_modules/playwright/index.mjs"
HARBOR_PROBE_DIR="$P"; export HARBOR_PROBE_DIR
. "$(dirname "$0")/browser/agent-stub.sh"

# The gates and workers run on node; a runner whose image has none yet skips those arms, loudly (harbor#1060).
HAVE_NODE=0; ! command -v node >/dev/null 2>&1 || HAVE_NODE=1
[ "$HAVE_NODE" = 1 ] || echo "  SKIP the node arms: no node on PATH (the runner image carries it)"
# A skip is only for a box that never promised node: the runner image does, so there it is a failure.
[ "$REQUIRE_NODE" != 1 ] || t_eq "node is on PATH where the image promises it (HARBOR_REQUIRE_NODE)" 1 "$HAVE_NODE"

if [ "$HAVE_NODE" = 1 ]; then
t_section "the offline gate suite, delegated"
t_eq "--self-test passes" "exit 0" "$(rc sh "$BROWSER" --self-test)"
fi

t_section "route prints the contract, and only the contract"
t_eq "the routing contract exists" yes "$([ -f "$ROUTING" ] && echo yes)"
t_eq "route exits 0" "exit 0" "$(rc sh "$BROWSER" route)"
t_has "route prints the verb table" "$(out)" "harbor browser probe"
t_eq "route is byte-identical to the contract" same "$(cmp -s "$T_TMP/out" "$ROUTING" && echo same)"

t_section "the exit contract at the dispatcher's boundary"
t_exit "unknown verb exits 1" 1 sh "$BROWSER" no-such-verb
t_exit "session is refused, not run" 1 sh "$BROWSER" session
t_exit "--help answers (lint S4)" 0 sh "$BROWSER" --help
t_eq "doctor --json answers" "exit 0" "$(rc sh "$BROWSER" doctor --json)"
if command -v node >/dev/null 2>&1; then
  t_exit "doctor --json emits parseable JSON" 0 node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$T_TMP/out"
else echo "  SKIP doctor --json shape: no node on this host to parse it with"; fi

if [ "$HAVE_NODE" = 1 ]; then
t_section "a missing backend SKIPS and names the missing verifier"
# probe and hosts run a worker a pack ships (harbor#1273): without it they skip. The workers' own skips (no Playwright,
# no Chrome, an unknown --expect vendor) are asserted by the pack's suite, beside the worker.
t_eq "no pack worker exits 2" "exit 2" "$(rc sh "$BROWSER" hosts https://example.com)"
t_has "the skip names the worker" "$(out)" "SKIPPED — no bin/browser-hosts.mjs"
t_eq "probe skips the same way" "exit 2" "$(rc sh "$BROWSER" probe https://example.com)"
t_eq "the no-Chrome self-test passes" "exit 0" "$(rc env HARBOR_CHROME="$T_TMP/no-such-chrome" sh "$BROWSER" --self-test)"
t_eq "and runs 10 or more arms, none failing" yes "$(awk '/^browser: .* ok, 0 failed/ && $2 + 0 >= 10 { print "yes"; exit }' "$T_TMP/out")"
fi

t_section "agent: the guardrails, against a stub CLI (harbor#472)"
t_eq "a vendor UI passes" "exit 0" "$(ag goto https://ads.reddit.com/account/x)"
t_has "it runs in this Claude session's browser session" "$(out)" "args=-s=claude-abc123def456 goto https://ads.reddit.com/account/x"
t_has "from a per-session workdir, never the caller's cwd" "$(out)" "pwd=$T_TMP/harbor-browser/claude-abc123def456"
t_eq "a subdomain of a listed host passes" "exit 0" "$(ag tab-new https://eu.business.facebook.com/)"
t_eq "tab-new with no url passes" "exit 0" "$(ag tab-new)"
t_eq "a client live site is refused" "exit 1" "$(ag goto https://www.autogidas.lt/)"
t_has "the refusal names the live-walk repo" "$(out)" "client live sites go through the live-walk repo"
t_eq "and the CLI never ran" no "$(grep -q STUB "$T_TMP/out" && echo yes || echo no)"
# The live-walk repo is harbor.toml's live_walk_repo, its path the repo registry's (harbor#966, #1273).
PRIV="$T_TMP/priv"; mkdir -p "$PRIV"; printf 'live_walk_repo = "walker"\n' > "$PRIV/harbor.toml"
printf 'walker\tw-checkout\tworkload\t-\n' > "$PRIV/repos.tsv"
agr() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" PORT_ROOT="$T_TMP/pr" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$AGENT" "$@"; }
t_eq "registry row: the refusal still exits 1" "exit 1" "$(agr goto https://www.autogidas.lt/)"
t_has "registry row: the refusal names the configured repo" "$(out)" "client live sites go through walker"
t_has "registry row: the hint cds into the registered checkout" "$(out)" "cd $T_TMP/pr/w-checkout && just live"
printf 'other\tx\tworkload\t-\n' > "$PRIV/repos.tsv"
t_eq "no row: the refusal still exits 1" "exit 1" "$(agr goto https://www.autogidas.lt/)"
t_has "no row: it says the repo is not registered" "$(out)" "walker is not registered on this box"
t_hasnt "no row: no guessed cd path" "$(out)" "just live"
rm -f "$PRIV/repos.tsv"
t_eq "no registry: the refusal still exits 1" "exit 1" "$(agr goto https://www.autogidas.lt/)"
t_has "no registry: the hint is the old literal, PORT_ROOT/<id>" "$(out)" "cd $T_TMP/pr/walker && just live"
printf 'live_walk_repo = \n' > "$PRIV/harbor.toml"
t_eq "a harbor.toml that does not read: the refusal still exits 1" "exit 1" "$(agr goto https://www.autogidas.lt/)"
t_has "...and says the file did not read" "$(out)" "harbor.toml did not read"
EMPTYP="$T_TMP/emptypriv"; mkdir -p "$EMPTYP"; PRIV="$EMPTYP"
t_eq "no private layer at all: the refusal still exits 1" "exit 1" "$(agr goto https://www.autogidas.lt/)"
t_has "no private layer: it says no live-walk repo is set, never a guess" "$(out)" "no live-walk repo is set on this box"
t_hasnt "no private layer: no cd path" "$(out)" "just live"
t_eq "a lookalike host is refused" "exit 1" "$(ag goto https://ads.reddit.com.evil.example/)"
t_eq "userinfo smuggling is refused" "exit 1" "$(ag goto https://ads.reddit.com@evil.example/)"
t_eq "plain http is refused" "exit 1" "$(ag goto http://ads.reddit.com/)"
t_eq "javascript: is refused" "exit 1" "$(ag goto 'javascript:alert(1)')"
t_eq "tab-new to a client site is refused" "exit 1" "$(ag tab-new https://shop.example.invalid/)"
t_eq "goto with no url is refused" "exit 1" "$(ag goto)"
for v in run-code eval cookie-list cookie-get state-save state-load localstorage-list requests request-headers route install open kill-all; do
  t_eq "verb $v is refused" "exit 1" "$(ag "$v" x)"
done
t_eq "an allowed interaction verb passes" "exit 0" "$(ag click e12)"
t_eq "attach passes" "exit 0" "$(ag attach)"
t_has "attach uses the extension and an idle timeout" "$(out)" "args=-s=claude-abc123def456 attach --extension=chrome --idle-timeout=14400000"
t_has "attach names the Chrome profile" "$(out)" "STUB profile=Default"
t_eq "attach pins the daemon's DEBUG to relay close reasons" yes \
  "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN DEBUG=pw:protocol HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" attach >/dev/null; grep -q 'debug=pw:mcp:relay,pw:mcp:error$' "$T_TMP/out" && echo yes)"
t_has "attach tells the operator what to click" "$(out)" "click Connect"
_w0="$(osa window)"; ag attach >/dev/null
t_eq "attach first opens a Chrome window of its own" "$((_w0 + 1))" "$(osa window)"
OWN="$T_TMP/harbor-browser/claude-abc123def456/.owned-tabs"; rm -f "$OWN"
_w0="$(osa window)"; ag attach >/dev/null
t_eq "the window opens on about:blank, which another extension's New Tab page is not" yes "$(grep -q 'about:blank#harbor' "$AGENT" && echo yes)"
t_eq "attach records the one tab it opened" 501 "$(cat "$OWN")"
t_eq "and its window" 9 "$(cat "${OWN%/*}/.window")"
t_eq "with the operator in another app, no Chrome window is raised after" 0 "$(osa raise)"
_r0="$(osa 'raise 7')"; STUB_PREV_APP=com.google.Chrome; export STUB_PREV_APP; ag attach >/dev/null; unset STUB_PREV_APP
t_eq "with the operator in Chrome, the window they were in goes back on top" "$((_r0 + 1))" "$(osa 'raise 7')"
t_eq "attaches take turns: the lock is released" no "$([ -d "$T_TMP/harbor-browser/.attach-lock" ] && echo yes || echo no)"
t_eq "detach passes" "exit 0" "$(ag detach)"
t_eq "and closes exactly the tabs this session opened" 1 "$(osa 'close 501')"
t_has "saying no other tab was touched" "$(out)" "no other tab touched"
t_eq "and forgets them" no "$([ -e "$OWN" ] && echo yes || echo no)"
printf '501\n' > "$OWN"; printf '9\n' > "${OWN%/*}/.window"
printf '%s\n' "9${TAB}1${TAB}true${TAB}about:blank${TAB}777" "9${TAB}2${TAB}false${TAB}https://login.example.test/${TAB}778" "9${TAB}3${TAB}false${TAB}chrome://newtab/${TAB}779" "7${TAB}1${TAB}true${TAB}about:blank${TAB}11" > "$OSA_TABS"
ag detach >/dev/null
t_eq "detach closes every tab in this session's window, a dropped tab's replacements too" 1 "$(osa 'close 501 777 778$')"
t_eq "but never a Chrome page there, where an operator's Cmd-T lands, nor a tab in another window" 0 "$(grep -c 'close.* \(779\|11\)' "$OSACALLS")"
: > "$OSA_TABS"
_c0="$(osa close)"; ag detach >/dev/null
t_eq "a detach with nothing opened closes nothing" "$_c0" "$(osa close)"
printf '501\n' > "$OWN"
t_eq "a detach whose close AppleScript refuses still detaches" "exit 0" "$(STUB_OSA_FAIL=1; export STUB_OSA_FAIL; ag detach)"
t_has "and says which ids it kept" "$(out)" "could not close"
t_eq "keeping them for the next detach" 501 "$(cat "$OWN")"
rm -f "$OWN"
# Chrome before attach, then after: the extension's connect tab in our window 9, and an
# operator's tab opened meanwhile in their window 7.
printf '%s\n' "7${TAB}1${TAB}true${TAB}https://mail.google.com/x${TAB}11" > "$OSA_TABS"
printf '%s\n' "7${TAB}1${TAB}false${TAB}https://mail.google.com/x${TAB}11" "7${TAB}2${TAB}true${TAB}https://www.youtube.com/${TAB}12" \
  "9${TAB}1${TAB}false${TAB}about:blank#harbor${TAB}501" "9${TAB}2${TAB}true${TAB}chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?token=x${TAB}502" > "$OSA_TABS.next"
_c0="$(osa 'close 501')"; ag attach >/dev/null
t_eq "attach takes the connect tab the extension opened as the session's" 502 "$(cat "$OWN")"
t_eq "and closes the empty window tab it started on" "$((_c0 + 1))" "$(osa 'close 501')"
t_hasnt "never the operator's tab opened meanwhile" "$(cat "$OWN")" "12"
rm -f "$OWN"; : > "$OSA_TABS"
t_eq "attach output with the connect page passes" "exit 0" "$(STUB_TOKEN_URL=1; export STUB_TOKEN_URL; ag attach)"
t_hasnt "never shows the extension's token" "$(out)" "SEKRET99"
t_has "only that the query was cut" "$(out)" "connect.html?<cut>"
t_eq "tab-list with the connect page passes" "exit 0" "$(STUB_TOKEN_URL=1; export STUB_TOKEN_URL; ag tab-list)"
t_hasnt "and hides the token too" "$(out)" "SEKRET99"
rm -f "$OWN"
t_eq "attach still connects when AppleScript fails" "exit 0" "$(STUB_OSA_FAIL=1; export STUB_OSA_FAIL; HARBOR_OSASCRIPT=/no/such/osascript; export HARBOR_OSASCRIPT; ag attach)"
t_has "and warns that the tab shares a window" "$(out)" "no window of its own"
t_eq "the approval token is refused" "exit 1" "$(rc env PLAYWRIGHT_MCP_EXTENSION_TOKEN=x HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc sh "$AGENT" tab-list)"
t_eq "a lane passes" "exit 0" "$(HARBOR_BROWSER_LANE=ads1; export HARBOR_BROWSER_LANE; ag tab-list)"
t_has "as this session's own name plus the lane" "$(out)" "args=-s=claude-abc123def456-ads1 tab-list"
t_eq "a lane with other characters is refused" "exit 1" "$(HARBOR_BROWSER_LANE='x/../y'; export HARBOR_BROWSER_LANE; ag tab-list)"
t_eq "a lane in capitals is refused, whatever the locale" "exit 1" "$(LANG=en_NZ.UTF-8 LC_ALL=en_NZ.UTF-8 HARBOR_BROWSER_LANE=ADS; export HARBOR_BROWSER_LANE; ag tab-list)"
t_eq "a lane over 12 characters is refused" "exit 1" "$(HARBOR_BROWSER_LANE=abcdefghijklm; export HARBOR_BROWSER_LANE; ag tab-list)"
t_eq "no session id is refused" "exit 1" "$(rc env -u CLAUDE_CODE_SESSION_ID -u HARBOR_BROWSER_SESSION -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_PW_CLI="$STUB" sh "$AGENT" tab-list)"
t_eq "a non-numeric idle timeout is refused" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_IDLE_MS=soon HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc sh "$AGENT" attach)"

t_section "agent: the bypasses the 2026-09-30 adversarial review found"
t_eq "--session cannot smuggle an off-list URL" "exit 1" "$(ag goto --session https://ads.reddit.com https://evil.example/)"
t_eq "and the CLI never ran" no "$(grep -q STUB "$T_TMP/out" && echo yes || echo no)"
t_eq "goto takes exactly one url" "exit 1" "$(ag goto https://ads.reddit.com/ https://evil.example/)"
t_eq "tab-new takes at most one url" "exit 1" "$(ag tab-new https://ads.reddit.com/ https://evil.example/)"
t_eq "a backslash host is refused" "exit 1" "$(ag goto 'https://evil.example\.ads.reddit.com/')"
t_eq "a percent-encoded host is refused" "exit 1" "$(ag goto 'https://evil%2eexample.ads.reddit.com/')"
t_eq "an idle timeout of 0 is refused" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_IDLE_MS=0 HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$AGENT" attach)"
t_eq "an init script in the env is refused" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN PLAYWRIGHT_MCP_INIT_SCRIPT=x HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$AGENT" attach)"
t_eq "a CLI config env is refused" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN PLAYWRIGHT_MCP_CONFIG=/tmp/x HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$AGENT" tab-list)"
mkdir -p "$T_TMP/harbor-browser/.playwright"
t_eq "a .playwright config up the tree is refused" "exit 1" "$(ag tab-list)"
rm -rf "$T_TMP/harbor-browser/.playwright"
t_eq "an absolute --filename is refused" "exit 1" "$(ag screenshot --filename=/tmp/x.png)"
t_eq "a ../ --filename is refused" "exit 1" "$(ag snapshot --filename=../x.yml)"
t_eq "a dotfile --filename is refused" "exit 1" "$(ag pdf --filename=.zshrc)"
t_eq "a bare --filename passes" "exit 0" "$(ag snapshot --filename=page.yml)"
t_eq "any other option is refused" "exit 1" "$(ag click e1 --config=/tmp/c.json)"
t_eq "a negative number passes" "exit 0" "$(ag mousewheel 0 -300)"
t_eq "inside Claude Code the session cannot be named" "exit 0" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_SESSION=claude-other HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" tab-list)"
t_has "it stays this session's own" "$(out)" "args=-s=claude-abc123def456 tab-list"

t_section "agent: every core vendor UI opens, a client site does not (2026-10-01)"
_bad=''
for u in https://ads.openai.com/conversions https://ui.ads.microsoft.com/campaign/ https://ads.microsoft.com/ \
  https://campaignmanager.google.com/trafficking/ https://searchads.google.com/aw/campaigns https://datastudio.google.com/reporting/x \
  https://github.com/ https://console.cloud.google.com/ https://mail.google.com/ https://eventsmanager.facebook.com/ \
  https://claude.ai/ https://portal.azure.com/ https://anthropic.skilljar.com/ \
  https://m365.cloud.microsoft/ https://www.office.com/ https://ads.x.com/ https://www.linkedin.com/campaignmanager/ \
  https://onedrive.live.com/ https://outlook.com/ https://g.co/x; do
  [ "$(ag goto "$u")" = "exit 0" ] || _bad="$_bad $u"
done
t_eq "goto opens every listed vendor UI" "" "$_bad"
t_eq "a client live site is still refused" "exit 1" "$(ag goto https://shop.client.example/lt/)"
# One operator's stack is the private layer's list (harbor#1273): core alone refuses a vendor that only it names.
t_eq "core alone refuses a vendor the private layer names" "exit 1" "$(ag goto https://example-adtech.test/)"
t_eq "amazon.com, the shop, is not admitted" "exit 1" "$(ag goto https://www.amazon.com/)"
t_eq "a client site on a vendor-like name is refused" "exit 1" "$(ag goto https://m.cars-portal.example/)"
t_eq "a customer Azure endpoint is not admitted (portal.azure.com only)" "exit 1" "$(ag goto https://evil.openai.azure.com/)"
t_eq "no SharePoint tenant is admitted by core: *.sharepoint.com is every tenant" "exit 1" "$(ag goto https://other-my.sharepoint.com/)"
t_eq "core lists no SharePoint tenant host" "" "$(grep -v '^[[:space:]]*#' "$T_ROOT/CONTRACTS/browser-agent-hosts.txt" | grep -i sharepoint || :)"
t_eq "another Docebo tenant is not admitted" "exit 1" "$(ag goto https://other.docebosaas.com/)"
t_eq "every host line sits under a comment saying why" "" \
  "$(awk '/^#/ { why = 1; next } /^[[:space:]]*$/ { why = 0; next } !why { print }' "$T_ROOT/CONTRACTS/browser-agent-hosts.txt")"

# What a company, a client and one operator's tenants need is the private layer's list (harbor#1149): stand-in hosts here, the
# real ones live in harbor-private/browser-hosts.txt. The overlay opens them, core alone refuses them, and its tenants are exact hosts.
OV="$T_TMP/overlay-hosts.txt"
printf '# A partner agency\npartner.example.net\n# A university tenant, exact hosts (*.sharepoint.com is every tenant)\ntenant-a.sharepoint.com\ntenant-a-my.sharepoint.com\n# The university LMS\nlms.example.edu\n' > "$OV"
ago() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_PRIVATE_HOSTS="$OV" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@"; }
_bad=''
for u in https://partner.example.net/roadmap https://lms.example.edu/course/1 https://tenant-a-my.sharepoint.com/personal/x https://tenant-a.sharepoint.com/; do
  [ "$(ago goto "$u")" = "exit 0" ] || _bad="$_bad $u"
done
t_eq "the private layer's hosts open: a partner, a university LMS, a tenant's exact hosts" "" "$_bad"
t_eq "...and core alone refuses a partner host" "exit 1" "$(ag goto https://partner.example.net/roadmap)"
t_eq "...and core alone refuses a tenant host" "exit 1" "$(ag goto https://tenant-a-my.sharepoint.com/personal/x)"
t_eq "...and the overlay does not widen to another tenant" "exit 1" "$(ago goto https://tenant-b-my.sharepoint.com/)"

t_section "agent: the destructive-click guard reads the label from a fresh snapshot"
: > "$CALLS"
t_eq "an ordinary button is clicked" "exit 0" "$(ag click e3)"
t_eq "after a full guard snapshot, never a partial one" 1 "$(called 'snapshot --boxes --filename=harbor-guard.yml')"
t_eq "and the click itself ran" 1 "$(called 'click e3')"
t_eq "a Delete button is refused" "exit 1" "$(ag click e4)"
t_has "naming the label and the word" "$(out)" "'button \"Delete campaign\"' (e4) matches 'delete'"
t_has "with the per-call confirm as its fix" "$(out)" "fix: HARBOR_BROWSER_CONFIRM=e4 harbor chrome click e4"
t_eq "and the click never reached the CLI" 0 "$(called 'click e4')"
t_eq "dblclick is guarded too" "exit 1" "$(ag dblclick e4)"
t_eq "an aria-label Remove is refused" "exit 1" "$(ag click e5)"
t_eq "a Lithuanian label is refused" "exit 1" "$(ag click e6)"
t_eq "an upper-case Lithuanian label is refused" "exit 1" "$(ag click e14)"
t_eq "a nameless button is labelled by its subtree" "exit 1" "$(ag click e10)"
t_eq "status words pass (Paused, Removed: whole words only)" "exit 0" "$(ag click e12)"
t_eq "Payments is not pay" "exit 0" "$(ag click e13)"
t_eq "page text carrying [ref=e4] cannot stand in for e4's label" "exit 1" "$(ag click e4)"
t_has "the label read is the real e4's" "$(out)" "'button \"Delete campaign\"' (e4)"
t_eq "nor its box (a forced click lands on the real e9)" 1 "$(: > "$CALLS"; ag click e9 --force >/dev/null; called 'mousemove 926 78')"
t_eq "a selector target is refused (no label to check)" "exit 1" "$(ag click 'text=Delete')"
{ printf '%s\n' '  - button [ref=e30] [box=8,200,20,20]:'; i=0; while [ $i -lt 45 ]; do printf '    - generic [ref=e%s]\n' $((100 + i)); i=$((i + 1)); done
  printf '%s\n' '    - img "Delete" [ref=e199]'; } >> "$SNAP"
t_eq "a nameless button's whole subtree is read, not 40 lines" "exit 1" "$(ag click e30)"
t_eq "a bracketed name keeps its word" "exit 1" "$(ag click e22)"
t_eq "Unlink is destructive" "exit 1" "$(ag click e23)"
t_eq "a leading number cannot shift the CLI's target" "exit 1" "$(ag click -5 e3)"
t_eq "nor an empty argument" "exit 1" "$(ag click '' e3)"
t_eq "a ref missing from the snapshot is refused" "exit 1" "$(ag click e99)"
t_has "as stale" "$(out)" "not in the current snapshot"
t_eq "the operator's per-call confirm clicks it" "exit 0" "$(rc env HARBOR_BROWSER_CONFIRM=e4 HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" click e4)"
t_has "and says so" "$(out)" "WARN: operator-confirmed destructive click"
t_eq "a confirm naming another ref is refused" "exit 1" "$(rc env HARBOR_BROWSER_CONFIRM=e3 HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$AGENT" click e4)"
t_eq "a confirm set on any other verb is refused (exported)" "exit 1" "$(rc env HARBOR_BROWSER_CONFIRM=e4 HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$AGENT" snapshot)"
t_has "naming it per-call" "$(out)" "never exported"
# The guard line removed, the same Delete click must go through: the arms above can fail.
M="$T_TMP/mutant"; mkdir -p "$M/bin" "$M/CONTRACTS"
sed 's/^\( *\)_refuse "destructive .*/\1:/' "$AGENT" > "$M/bin/browser-agent.sh"
cp "$T_ROOT/bin/log-lib.sh" "$M/bin/"; cp "$T_ROOT/CONTRACTS/browser-agent-hosts.txt" "$M/CONTRACTS/"
t_eq "the mutant differs from the script" yes "$(cmp -s "$AGENT" "$M/bin/browser-agent.sh" || echo yes)"
t_eq "and without the guard line the Delete click goes through" "exit 0" \
  "$(rc env HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc TMPDIR="$T_TMP" sh "$M/bin/browser-agent.sh" click e4)"

t_section "agent: click options the pinned CLI has, and harbor's --force"
: > "$CALLS"
t_eq "click --force passes" "exit 0" "$(ag click e9 --force)"
t_eq "as a mouse press at the box centre" 1 "$(called 'mousemove 926 78')"
t_eq "down" 1 "$(called 'mousedown')"
t_eq "and up" 1 "$(called 'mouseup')"
t_eq "never the CLI's click, which waits for 'stable'" 0 "$(called 'click e9')"
t_eq "a forced right click presses the right button" "exit 0" "$(ag click e9 right --force)"
t_eq "on down" 1 "$(called 'mousedown right')"
t_eq "--force on a Delete button is still refused" "exit 1" "$(ag click e4 --force)"
t_eq "--force onto a Delete button covering the target is refused" "exit 1" "$(ag click e19 --force)"
t_has "naming what sits at the point" "$(out)" "'button \"Delete\"' (e21)"
t_eq "--force on a zero-size box is refused" "exit 1" "$(ag click e15 --force)"
t_eq "--force inside an iframe is refused (frame-relative box)" "exit 1" "$(ag click f2e3 --force)"
t_eq "an ordinary click inside an iframe passes" "exit 0" "$(ag click f2e3)"
t_eq "dblclick --force is refused" "exit 1" "$(ag dblclick e9 --force)"
t_eq "--force on another verb is refused" "exit 1" "$(ag fill e9 x --force)"
t_eq "--force with --modifiers is refused" "exit 1" "$(ag click e9 --force --modifiers=Shift)"
t_eq "--modifiers=Shift on click passes" "exit 0" "$(ag click e3 --modifiers=Shift)"
t_has "through to the CLI" "$(out)" "args=-s=claude-abc123def456 click e3 --modifiers=Shift"
t_eq "an unknown modifier is refused" "exit 1" "$(ag click e3 --modifiers=Hyper)"
t_eq "--modifiers on another verb is refused" "exit 1" "$(ag hover e3 --modifiers=Shift)"

t_section "agent: status names why the relay last closed"
ERR="$HOME/Library/Caches/ms-playwright/daemon/0123/claude-abc123def456.err"; mkdir -p "${ERR%/*}"
printf '%s\n' '2026-10-01T13:20:00.000Z pw:mcp:relay Extension WebSocket closed: All controlled tabs detached' > "$ERR"
t_eq "status passes" "exit 0" "$(ag status)"
t_has "with the close reason from the daemon's log" "$(out)" "relay    2026-10-01T13:20:00.000Z pw:mcp:relay Extension WebSocket closed: All controlled tabs detached"
rm -f "$ERR"; ag status >/dev/null
t_has "and says when none is recorded" "$(out)" "relay    no close recorded"

t_section "doctor looks where Chrome keeps its profiles on this OS (harbor#618)"
LXU="$T_TMP/lxu"; mkdir -p "$LXU/linux" "$LXU/darwin"
printf '#!/bin/sh\necho Linux\n' > "$LXU/linux/uname"; printf '#!/bin/sh\necho Darwin\n' > "$LXU/darwin/uname"; chmod +x "$LXU/linux/uname" "$LXU/darwin/uname"
printf '{}\n' > "$T_TMP/claude-os.json"
dd_os() { # <uname dir> [XDG_CONFIG_HOME] -> doctor with no HARBOR_CHROME_DATA override
  rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN -u HARBOR_CHROME_DATA -u XDG_CONFIG_HOME ${2:+XDG_CONFIG_HOME="$2"} PATH="$LXU/$1:$PATH" HARBOR_CLAUDE_JSON="$T_TMP/claude-os.json" sh "$AGENT" doctor
}
dd_os linux >/dev/null; t_has "Linux: ~/.config/google-chrome" "$(out)" "under $HOME/.config/google-chrome"
dd_os linux "$T_TMP/xdg" >/dev/null; t_has "Linux: XDG_CONFIG_HOME is honoured" "$(out)" "under $T_TMP/xdg/google-chrome"
dd_os darwin >/dev/null; t_has "macOS: ~/Library/Application Support/Google/Chrome" "$(out)" "under $HOME/Library/Application Support/Google/Chrome"

t_section "doctor derives row 4 from the box"
CD="$T_TMP/chrome"; mkdir -p "$CD/Default"
dr() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_CHROME_DATA="$CD" HARBOR_CLAUDE_JSON="$T_TMP/claude.json" sh "$AGENT" doctor; }
printf '{"mcpServers":{"playwright":{"args":["@playwright/mcp@latest"]}}}\n' > "$T_TMP/claude.json"
t_eq "no extension anywhere fails doctor" "exit 1" "$(dr)"
t_has "and says where to install it" "$(out)" "the Playwright Extension is in no Chrome profile"
t_has "with the fix on the next line" "$(out)" "fix: open 'https://chromewebstore.google.com/detail/playwright-extension/"
t_has "a still-wired MCP is reported" "$(out)" "the retired @playwright/mcp server is still configured"
chmod 000 "$CD"
dr >/dev/null; t_has "a Chrome dir it may not list reads could-not-look" "$(out)" "WARN: could not look for the Playwright Extension"
t_has "...never no-profile" "$(out | grep -c 'in no Chrome profile')" "0"
chmod 755 "$CD"
mkdir -p "$CD/Default/Extensions/mmlmfjhmonkocbjadbfplnigmagldckm" "$CD/Profile 5/Extensions/mmlmfjhmonkocbjadbfplnigmagldckm"
dr >/dev/null; t_has "the extension in a second profile is flagged" "$(out)" "WARN: the extension is in [Default, Profile 5]"
rm -rf "$CD/Profile 5"; printf '{}\n' > "$T_TMP/claude.json"
dr >/dev/null; t_has "a retired MCP reads retired" "$(out)" "ok: the retired @playwright/mcp server is not configured"
t_has "doctor ends on the log summary" "$(out)" "browser-agent: "
if command -v jq >/dev/null 2>&1; then
  ID=mmlmfjhmonkocbjadbfplnigmagldckm
  printf '{"extensions":{"settings":{"%s":{"disable_reasons":[1]}}}}\n' "$ID" > "$CD/Default/Secure Preferences"
  t_eq "an extension switched off fails doctor" "exit 1" "$(dr)"
  t_has "and names the fix" "$(out)" "switch Playwright Extension on"
  t_eq "attach refuses while it is switched off" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_CHROME_DATA="$CD" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc sh "$AGENT" attach)"
  t_eq "and the CLI never ran" no "$(grep -q STUB "$T_TMP/out" && echo yes || echo no)"
  printf '{"extensions":{"settings":{"%s":{"disable_reasons":[]}}}}\n' "$ID" > "$CD/Default/Secure Preferences"
  dr >/dev/null; t_has "switched on reads ok" "$(out)" "ok: the extension is switched on in Chrome profile Default"
  rm -f "$CD/Default/Secure Preferences"
else echo "  SKIP switched-off arms: no jq on this host"; fi
t_eq "doctor with the token set fails" "exit 1" "$(rc env PLAYWRIGHT_MCP_EXTENSION_TOKEN=x HARBOR_CHROME_DATA="$CD" HARBOR_CLAUDE_JSON="$T_TMP/claude.json" sh "$AGENT" doctor)"
t_has "naming the variable" "$(out)" "FAIL: PLAYWRIGHT_* set in the environment: PLAYWRIGHT_MCP_EXTENSION_TOKEN"
t_eq "--help answers (lint S4)" "exit 0" "$(rc sh "$AGENT" --help)"
t_eq "no verb is a usage error, exit 2" "exit 2" "$(rc sh "$AGENT")"
t_has "a refusal carries its fix line" "$(ag run-code x; out)" "fix: harbor chrome help"

t_section "agent: a session whose Chrome is gone says so, and how to reconnect (harbor#920)"
_gone() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN STUB_GONE=1 XDG_CACHE_HOME="$T_TMP/cache" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@"; }
t_eq "a verb on a gone session fails" "exit 1" "$(_gone tab-list)"
t_has "naming the session" "$(out)" "no Chrome is connected to session claude-abc123def456"
t_has "and the reconnect, not the CLI's own advice" "$(out)" "fix: harbor chrome attach"
t_hasnt "the CLI's fresh-browser advice is not passed on" "$(out)" "please run open first"
t_has "positive control: the stub does print that advice" "$(STUB_GONE=1 "$STUB" -s=x tab-list)" "please run open first"
mkdir -p "$T_TMP/cache/ms-playwright/daemon/h"
printf '2026-10-02T13:41:01.756Z pw:mcp:relay <ws closed> code=1000 reason=All controlled tabs detached\n' > "$T_TMP/cache/ms-playwright/daemon/h/claude-abc123def456.err"
_gone snapshot > /dev/null
t_has "with the relay's recorded close when there is one" "$(out)" "the relay last closed with code=1000 reason=All controlled tabs detached"
t_eq "a verb that works still passes its output through" "exit 0" "$(ag tab-list)"
t_has "positive control: the stub's own line is on stdout" "$(out)" "STUB profile="
printf '#!/bin/sh\necho "Error: ref e9 not found"; exit 3\n' > "$T_TMP/pwfail"; chmod +x "$T_TMP/pwfail"
t_eq "a CLI failure that is not a gone session keeps its exact exit" "exit 3" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_PW_CLI="$T_TMP/pwfail" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" tab-list)"
t_has "and its text" "$(out)" "Error: ref e9 not found"
t_hasnt "and is not called a gone session" "$(out)" "no Chrome is connected"
printf '#!/bin/sh\necho "Error: Dialog is not open"; exit 1\n' > "$T_TMP/pwdialog"; chmod +x "$T_TMP/pwdialog"
rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_PW_CLI="$T_TMP/pwdialog" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" tab-list > /dev/null
t_has "a page error that merely says 'is not open' passes through as itself" "$(out)" "Error: Dialog is not open"
t_hasnt "and is not called a gone session" "$(out)" "no Chrome is connected"
t_eq "click on a gone session: the guard's snapshot is told apart too" "exit 1" "$(_gone click e3)"
t_has "with the attach fix" "$(out)" "fix: harbor chrome attach"
t_hasnt "and not the CLI's advice" "$(out)" "please run open first"
t_eq "no held output is left in the workdir" "" "$(find "$T_TMP/harbor-browser" -name '.out.*' 2>/dev/null)"

URL="$LIVE_URL"
if [ -z "$LIVE_PROBE" ]; then
  echo "  SKIP live consent arms: export HARBOR_PROBE_DIR at a Playwright install to run them"
elif [ -z "$URL" ]; then
  echo "  SKIP live consent arms: export HARBOR_BROWSER_LIVE_URL at a storefront with a consent banner"
elif ! curl -sS -o /dev/null --max-time 8 --head "$URL" >/dev/null 2>&1; then
  echo "  SKIP live consent arms: $URL is not reachable"
else
  t_section "the live consent arms"
  R="$(rc env HARBOR_PROBE_DIR="$LIVE_PROBE" HARBOR_BROWSER_LIVE_URL="$URL" sh "$BROWSER" --self-test-live)"
  if [ "$R" = "exit 2" ]; then t_has "--self-test-live's skip names the missing verifier" "$(out)" "SKIPPED"
  else t_eq "--self-test-live passes" "exit 0" "$R"; fi
fi
t_done
