#!/usr/bin/env sh
# access-chrome-mcp.ts (harbor#1421): the MCP server that keeps one connection to the session's daemon, and every guard
# access-browser-agent.sh enforces, shown refusing in that server. A fake daemon (fake-daemon.ts) answers on a unix socket in
# the shape the real one does; a refused case is proved by the daemon's call log staying empty, never by the message alone.
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"
# Where bun is absent (the hosted runner image) the suite skips loudly with one assertion, as panels.test.sh does (harbor#738).
if ! command -v bun >/dev/null 2>&1; then
  echo "  SKIP session: bun is not installed (the server's interpreter)"
  t_section "bun is absent: only an image that does not promise it may skip"
  t_eq "HARBOR_TEST_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
  t_done; exit 0
fi
SRVSRC="$T_ROOT/bin/access-chrome-mcp.ts"; AG="$T_ROOT/bin/access-browser-agent.sh"
X="$T_TMP/x"; mkdir -p "$X/bin" "$X/contracts"; cp "$SRVSRC" "$X/bin/"; cp "$T_ROOT/contracts/browser-agent-hosts.txt" "$X/contracts/"
cp "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$X/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$X/contracts/"
SRV="$X/bin/access-chrome-mcp.ts"
CTL="$T_TMP/ctl"; mkdir -p "$CTL"; SOCK="$T_TMP/d.sock"; PH="$T_TMP/priv-hosts.txt"; : > "$PH"
DD="$T_TMP/daemons"; mkdir -p "$DD/0123"; WD="$T_TMP/harbor-browser/claude-abc123def456"
sess() { printf '{"name":"claude-abc123def456","version":"1.64.0","timestamp":%s,"socketPath":"%s"}\n' "$1" "$SOCK" > "$DD/0123/claude-abc123def456.session"; }
seams() { printf '{"daemonDir":"%s","settleMs":%s,"privHosts":"%s","accessDir":"%s","scopeEnv":{"HARBOR_SCOPE_PRIVATE":"%s","PORT_ROOT":"%s"},"agentEnv":{"STUB_TABS":"%s"}}\n' \
  "$DD" "$1" "$PH" "$ACC" "${PRIV:-$T_TMP/nopriv}" "$T_TMP/pr" "$T_TMP/tabs-out" > "$X/bin/access-chrome-mcp.seams.json"; }
PRIV="$T_TMP/nopriv"; mkdir -p "$PRIV"; seams 0; sess 1
# the stub shell agent: what the verbs that are Chrome's own run (attach, tabs, ...), and the tab list the sign-in stop reads
cat > "$X/bin/access-browser-agent.sh" <<'EOF'
for a in "$@"; do printf 'arg=%s\n' "$a"; done
printf 'session=%s lane=%s path=%s private=%s\n' "${HARBOR_ACCESS_BROWSER_SESSION:-}" "${HARBOR_BROWSER_LANE:-}" "$PATH" "${HARBOR_BROWSER_PRIVATE_HOSTS:-none}"
case "$1" in tabs) cat "$STUB_TABS" 2>/dev/null || : ;; esac
EOF
bun "$T_ROOT/tests/access/chrome/fake-daemon.ts" "$SOCK" "$CTL" "$SNAP" & DPID=$!
trap 'kill $DPID 2>/dev/null; chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT
_i=0; while [ ! -e "$CTL/ready" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
[ -e "$CTL/ready" ] || { t_fail "the fake daemon did not start"; t_done; exit 1; }
CALLS="$CTL/calls"; : > "$CALLS"
clean() { rm -f "$CTL"/blank "$CTL"/hidden "$CTL"/eval_fail "$CTL"/tablist_fail "$CTL"/fail "$CTL"/upload_denied "$CTL"/late_blank* "$CTL"/xerr "$CTL"/page_url "$CTL"/delay_ms "$CTL"/token_url; }

# mcp <tool> <arg>... -> "exit 0|1"; the result text is left in $T_TMP/out. The environment is the launcher's: nothing else reaches it.
envs() { env -i HOME="$HOME" TMPDIR="$T_TMP" PATH="$PATH" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 "$@"; }
mcpe() { # <env assignment or ''> <tool> <arg>...
  _e="$1"; _t="$2"; shift 2
  _q="$(for _a in "$@"; do printf '%s\0' "$_a"; done | jq -Rs --arg t "$_t" '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:$t,arguments:{args:(split("\u0000")[:-1])}}}' -c)"
  _r="$(printf '%s\n' "$_q" | envs ${_e:+"$_e"} bun "$SRV" 2>&1)"
  printf '%s' "$_r" | jq -r '.result.content[0].text' > "$T_TMP/out" 2>/dev/null || printf '%s' "$_r" > "$T_TMP/out"
  [ "$(printf '%s' "$_r" | jq -r '.result.isError' 2>/dev/null)" = false ] && echo "exit 0" || echo "exit 1"
}
mcp() { mcpe '' "$@"; }
rpc() { printf '%s\n' "$@" | envs bun "$SRV" 2>&1; }
n() { grep -c -- "$1" "$CALLS" 2>/dev/null || :; }   # how many daemon requests carried $1
txt() { cat "$T_TMP/out"; }

t_section "the protocol, and one tool per allowed verb"
OUT="$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"ping"}')"
t_eq "initialize echoes a version it speaks" 2025-03-26 "$(printf '%s\n' "$OUT" | head -1 | jq -r .result.protocolVersion)"
t_eq "...names the server harbor_chrome" harbor_chrome "$(printf '%s\n' "$OUT" | head -1 | jq -r .result.serverInfo.name)"
t_eq "a notification gets no reply (two requests, two replies)" 2 "$(printf '%s\n' "$OUT" | grep -c .)"
t_eq "an unknown method is -32601" -32601 "$(rpc '{"jsonrpc":"2.0","id":1,"method":"resources/list"}' | jq -r .error.code)"
t_eq "a line that is not JSON is -32700, and the server keeps serving" "-32700 {}" \
  "$(rpc 'not json' '{"jsonrpc":"2.0","id":2,"method":"ping"}' | jq -rc '.error.code // .result' | tr '\n' ' ' | sed 's/ $//')"
OUT="$(rpc '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":["goto"]}}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":[1]}' '{"jsonrpc":"2.0","id":3}' '{"jsonrpc":"2.0","id":4,"method":"ping"}')"
t_eq "a list for a tool name, a list for params, no method; then a ping" "-32602 -32602 -32600 {}" \
  "$(printf '%s\n' "$OUT" | jq -rc '.error.code // .result' | tr '\n' ' ' | sed 's/ $//')"
TL="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[].name' | sort)"
ALLOWED="$(awk '/^_allowed\(\) \{/ { f = 1; next } f && /case "\$1" in/ { next } f && /return 0/ { sub(/\).*/, ""); gsub(/[ \t\\]/, ""); print; exit } f { gsub(/[ \t\\]/, ""); printf "%s", $0 }' "$AG" | tr '|' '\n' | sed '/^$/d')"
WANT="$(printf '%s\n' $ALLOWED attach status state doctor detach tabs front wait-signin hosts | tr '-' '_' | sort -u)"
t_eq "CONTROL: the shell agent's allowlist parses" yes "$([ "$(printf '%s\n' "$ALLOWED" | grep -c .)" -ge 20 ] && echo yes || echo no)"
t_eq "the tools are exactly the shell agent's allowed verbs and its session verbs" "$WANT" "$TL"
t_hasnt "no tool runs code in a logged-in page" "$TL" "eval"
t_eq "an unknown tool is an error result, the daemon untouched" "exit 1" "$(mcp run_code)"
t_eq "args that are not strings are an error result" true "$(printf '%s\n' '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"goto","arguments":{"args":[1]}}}' | envs bun "$SRV" | jq -r .result.isError)"
t_eq "...and nothing reached the daemon" 0 "$(grep -c . "$CALLS")"

t_section "a call goes to the daemon's socket: one connection for the server's life"
: > "$CALLS"; : > "$CTL/conns"
_q1="$(jq -cn '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:"tab_list",arguments:{}}}')"
R="$(printf '%s\n' "$_q1" "$_q1" "$_q1" "$_q1" "$_q1" | envs bun "$SRV" | jq -r '.result.content[0].text' | grep -c STUB)"
t_eq "five calls in one server" 5 "$R"
t_eq "ran over ONE daemon connection" 1 "$(grep -c . "$CTL/conns")"
t_eq "the daemon saw five requests" 5 "$(n tab-list)"
mcp tab_list >/dev/null
t_has "the verb runs from the session workdir, so --filename lands there" "$(txt)" "pwd=$WD"
sess 2; : > "$CTL/conns"; mcp tab_list >/dev/null; mcp tab_list >/dev/null
t_eq "a daemon the shell agent restarted (a new session file) is reconnected to" 2 "$(grep -c . "$CTL/conns")"
t_eq "the timings of a call are kept for the operator: verb, total, guards, daemon, settle (ms)" yes \
  "$(awk -F '\t' '$2 == "tab-list" && $3 + 0 >= 0 && NF == 6 { f = 1 } END { print f ? "yes" : "no" }' "$WD/.timings.tsv")"

t_section "the host allowlist (goto)"
: > "$CALLS"
t_eq "a vendor UI passes" "exit 0" "$(mcp goto https://ads.reddit.com/account/x)"
t_eq "the daemon got it" 1 "$(n 'goto https://ads.reddit.com/account/x')"
t_eq "a subdomain of a listed host passes" "exit 0" "$(mcp goto https://eu.business.facebook.com/)"
: > "$CALLS"
t_eq "a client live site is refused" "exit 1" "$(mcp goto https://www.autogidas.lt/)"
t_has "the refusal names the live-walk repo" "$(txt)" "client live sites go through the live-walk repo"
t_eq "and the daemon never ran" 0 "$(grep -c . "$CALLS")"
t_has "as a hand-off the failure ledger does not count (FC-10)" "$(txt)" "FAIL: hand-off: host refused"
for u in https://ads.reddit.com.evil.example/ https://ads.reddit.com@evil.example/ http://ads.reddit.com/ 'javascript:alert(1)' \
  'https://evil.example\.ads.reddit.com/' 'https://evil%2eexample.ads.reddit.com/' 'https://ads.reddit.com/ x' https://ads.reddit.com:8443/ 'https://.ads.reddit.com/'; do
  t_eq "refused: $u" "exit 1" "$(mcp goto "$u")"
done
t_eq "goto with no url is refused" "exit 1" "$(mcp goto)"
t_eq "goto takes exactly one url" "exit 1" "$(mcp goto https://ads.reddit.com/ https://evil.example/)"
t_eq "--session cannot smuggle an off-list URL" "exit 1" "$(mcp goto --session https://ads.reddit.com https://evil.example/)"
t_eq "none of those reached the daemon" 0 "$(grep -c . "$CALLS")"
printf '# a partner\npartner.example.net\n' > "$PH"
t_eq "the private layer's host opens" "exit 0" "$(mcp goto https://partner.example.net/roadmap)"
t_eq "...and does not widen to a lookalike" "exit 1" "$(mcp goto https://partner.example.net.evil.example/)"
: > "$PH"
t_eq "...and core alone refuses it" "exit 1" "$(mcp goto https://partner.example.net/roadmap)"
# the live-walk hint is the private layer's own and the registry's (harbor#966, #1273)
PRIV="$T_TMP/priv"; mkdir -p "$PRIV"; printf 'live_walk_repo = "walker"\n' > "$PRIV/harbor.toml"; printf 'walker\tw-checkout\tworkload\t-\n' > "$PRIV/repos.tsv"; seams 0
t_eq "registry row: the refusal still exits 1" "exit 1" "$(mcp goto https://www.autogidas.lt/)"
t_has "registry row: it names the configured repo" "$(txt)" "client live sites go through walker"
t_has "registry row: the hint cds into the registered checkout" "$(txt)" "cd $T_TMP/pr/w-checkout && just live"
printf 'other\tx\tworkload\t-\n' > "$PRIV/repos.tsv"
t_eq "no row: the refusal still exits 1" "exit 1" "$(mcp goto https://www.autogidas.lt/)"
t_has "no row: it says the repo is not registered" "$(txt)" "walker is not registered on this box"
t_hasnt "no row: no guessed cd path" "$(txt)" "just live"
rm -f "$PRIV/repos.tsv"; PRIV="$T_TMP/nopriv"; seams 0
t_has "no private layer: it says no live-walk repo is set, never a guess" "$(mcp goto https://www.autogidas.lt/ >/dev/null; txt)" "no live-walk repo is set on this box"

t_section "options are default-deny"
: > "$CALLS"
t_eq "an absolute --filename is refused" "exit 1" "$(mcp screenshot --filename=/tmp/x.png)"
t_eq "a ../ --filename is refused" "exit 1" "$(mcp snapshot --filename=../x.yml)"
t_eq "a dotfile --filename is refused" "exit 1" "$(mcp pdf --filename=.zshrc)"
t_eq "an empty --filename is refused" "exit 1" "$(mcp pdf --filename=)"
t_eq "a --filename with a space is refused" "exit 1" "$(mcp pdf '--filename=a b')"
t_eq "any other option is refused" "exit 1" "$(mcp click e1 --config=/tmp/c.json)"
t_eq "--submit on click is refused" "exit 1" "$(mcp click e3 --submit)"
t_eq "--submit on hover is refused" "exit 1" "$(mcp hover e3 --submit)"
t_eq "--modifiers on another verb is refused" "exit 1" "$(mcp hover e3 --modifiers=Shift)"
t_eq "an unknown modifier is refused" "exit 1" "$(mcp click e3 --modifiers=Hyper)"
t_eq "--force on another verb is refused" "exit 1" "$(mcp fill e9 x --force)"
t_eq "--force with --modifiers is refused" "exit 1" "$(mcp click e9 --force --modifiers=Shift)"
t_eq "dblclick --force is refused" "exit 1" "$(mcp dblclick e9 --force)"
t_eq "a malformed negative number is refused" "exit 1" "$(mcp mousewheel 0 -3x)"
t_eq "...and none of them reached the daemon" 0 "$(grep -c . "$CALLS")"
t_eq "a bare --filename passes" "exit 0" "$(mcp snapshot --filename=page.yml)"
t_has "...as an option of the daemon's run" "$(cat "$CALLS")" "snapshot --filename=page.yml"
t_eq "a negative number passes as an argument" "exit 0" "$(mcp mousewheel 0 -300)"
t_has "...in order" "$(cat "$CALLS")" "mousewheel 0 -300"
t_eq "fill --submit passes: Enter in the same call" "exit 0" "$(mcp fill e9 hello --submit)"
t_has "...and reaches the daemon" "$(cat "$CALLS")" "fill e9 hello --submit"

t_section "the environment: a token, PLAYWRIGHT_*, a config up the tree"
: > "$CALLS"
t_eq "the approval token is refused" "exit 1" "$(mcpe PLAYWRIGHT_MCP_EXTENSION_TOKEN=x tab_list)"
t_eq "an init script in the env is refused" "exit 1" "$(mcpe PLAYWRIGHT_MCP_INIT_SCRIPT=x tab_list)"
t_eq "a CLI config env is refused" "exit 1" "$(mcpe PLAYWRIGHT_MCP_CONFIG=/tmp/x tab_list)"
mkdir -p "$T_TMP/harbor-browser/.playwright"
t_eq "a .playwright config up the workdir's tree is refused" "exit 1" "$(mcp tab_list)"
rm -rf "$T_TMP/harbor-browser/.playwright"; mkdir -p "$HOME/.playwright"
t_eq "a ~/.playwright config is refused" "exit 1" "$(mcp tab_list)"
rm -rf "$HOME/.playwright"
t_eq "none of them reached the daemon" 0 "$(grep -c . "$CALLS")"
t_eq "CONTROL: without them the same call passes" "exit 0" "$(mcp tab_list)"
t_eq "a lane is its own browser session: the daemon of THAT name" "exit 1" "$(printf '%s\n' "$(jq -cn '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"tab_list",arguments:{lane:"ads1"}}}')" | envs bun "$SRV" | jq -r '.result.isError' | sed 's/true/exit 1/;s/false/exit 0/')"
t_has "...which has no daemon here, so it is the gone-session hand-off" "$(printf '%s\n' "$(jq -cn '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"tab_list",arguments:{lane:"ads1"}}}')" | envs bun "$SRV" | jq -r '.result.content[0].text')" "no Chrome is connected to session claude-abc123def456-ads1"
lane() { printf '%s\n' "$(jq -cn --arg l "$1" '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"tab_list",arguments:{lane:$l}}}')" | envs bun "$SRV" | jq -r '.result.content[0].text'; }
t_has "a lane with other characters is refused as no session, not as a missing daemon" "$(lane 'x/../y')" "no session: run inside Claude Code"
t_has "a lane over 12 characters is refused the same way" "$(lane abcdefghijklm)" "no session: run inside Claude Code"
t_has "a lane in capitals is refused" "$(lane ADS)" "no session: run inside Claude Code"

t_section "the destructive-click guard reads the label from a fresh snapshot"
: > "$CALLS"
t_eq "an ordinary button is clicked" "exit 0" "$(mcp click e3)"
t_eq "after a full guard snapshot, never a partial one" 1 "$(n 'snapshot --boxes --filename=harbor-guard.yml')"
t_eq "and the click itself ran" 1 "$(n '^click e3')"
t_eq "the guard snapshot landed in the session workdir" yes "$([ -s "$WD/harbor-guard.yml" ] && echo yes)"
: > "$CALLS"
t_eq "a Delete button is refused" "exit 1" "$(mcp click e4)"
t_has "...as a hand-off, so the failure ledger does not count it (FC-10)" "$(txt)" "FAIL: hand-off: destructive click refused"
t_has "naming the label and the word" "$(txt)" "'button \"Delete campaign\"' (e4) matches 'delete'"
t_has "with the per-call confirm as its fix" "$(txt)" "fix: HARBOR_ACCESS_BROWSER_CONFIRM=e4 harbor chrome click e4"
t_eq "and the click never reached the daemon" 0 "$(n '^click e4')"
t_eq "the operator's confirm in the server's environment is not honoured" "exit 1" "$(mcpe HARBOR_ACCESS_BROWSER_CONFIRM=e4 click e4)"
t_eq "dblclick is guarded too" "exit 1" "$(mcp dblclick e4)"
t_eq "an aria-label Remove is refused" "exit 1" "$(mcp click e5)"
t_eq "a Lithuanian label is refused" "exit 1" "$(mcp click e6)"
t_eq "an upper-case Lithuanian label is refused" "exit 1" "$(mcp click e14)"
t_eq "a nameless button is labelled by its subtree" "exit 1" "$(mcp click e10)"
t_eq "Unlink is destructive" "exit 1" "$(mcp click e23)"
t_eq "a bracketed name keeps its word" "exit 1" "$(mcp click e22)"
t_eq "page text carrying [ref=e4] cannot stand in for e4's label" "exit 1" "$(mcp click e4)"
t_has "the label read is the real e4's" "$(txt)" "'button \"Delete campaign\"' (e4)"
t_eq "a selector target is refused (no label to check)" "exit 1" "$(mcp click 'text=Delete')"
t_eq "a leading number cannot shift the target" "exit 1" "$(mcp click -5 e3)"
t_eq "nor an empty argument" "exit 1" "$(mcp click '' e3)"
t_eq "a ref missing from the snapshot is refused" "exit 1" "$(mcp click e99)"
t_has "as stale" "$(txt)" "not in the current snapshot"
t_eq "none of those clicked" 0 "$(n '^click\|^dblclick')"
t_eq "status words pass (Paused, Removed: whole words only)" "exit 0" "$(mcp click e12)"
t_eq "Payments is not pay" "exit 0" "$(mcp click e13)"
t_eq "an ordinary click inside an iframe passes" "exit 0" "$(mcp click f2e3)"
{ printf '%s\n' '  - button [ref=e30] [box=8,200,20,20]:'; i=0; while [ $i -lt 45 ]; do printf '    - generic [ref=e%s]\n' $((100 + i)); i=$((i + 1)); done
  printf '%s\n' '    - img "Delete" [ref=e199]'; } >> "$SNAP"
t_eq "a nameless button's whole subtree is read, not 40 lines" "exit 1" "$(mcp click e30)"
t_eq "a guard snapshot the daemon could not take refuses the click" "exit 1" "$(: > "$CTL/fail"; mcp click e3)"
clean
# The guard line removed, the same Delete click must go through: the arms above can fail.
mkdir -p "$T_TMP/mutant/bin" "$T_TMP/mutant/contracts"; cp "$X/bin/access-chrome-mcp.seams.json" "$X/bin/access-browser-agent.sh" "$X/bin/scope-roots.sh" "$T_TMP/mutant/bin/"; cp "$X/contracts/browser-agent-hosts.txt" "$T_TMP/mutant/contracts/"
sed 's/^  if (hit) handoff(`destructive .*/  if (false) handoff("");/' "$SRV" > "$T_TMP/mutant/bin/access-chrome-mcp.ts"
t_eq "the mutant differs from the server" yes "$(cmp -s "$SRV" "$T_TMP/mutant/bin/access-chrome-mcp.ts" || echo yes)"
_old="$SRV"; SRV="$T_TMP/mutant/bin/access-chrome-mcp.ts"
t_eq "and without the destructive-label line the Delete click goes through" "exit 0" "$(mcp click e4)"
SRV="$_old"

t_section "click --force is a mouse press, and it checks what it lands on"
: > "$CALLS"
t_eq "click --force passes" "exit 0" "$(mcp click e9 --force)"
t_eq "as a mouse press at the box centre" 1 "$(n 'mousemove 926 78')"
t_eq "down" 1 "$(n '^mousedown')"
t_eq "and up" 1 "$(n '^mouseup')"
t_eq "never the daemon's click, which waits for 'stable'" 0 "$(n '^click e9')"
t_eq "a forced right click presses the right button" "exit 0" "$(mcp click e9 right --force)"
t_eq "on down" 1 "$(n '^mousedown right')"
: > "$CALLS"
t_eq "--force on a Delete button is still refused" "exit 1" "$(mcp click e4 --force)"
t_eq "--force onto a Delete button covering the target is refused" "exit 1" "$(mcp click e19 --force)"
t_has "naming what sits at the point" "$(txt)" "'button \"Delete\"' (e21)"
t_eq "--force on a zero-size box is refused" "exit 1" "$(mcp click e15 --force)"
t_eq "--force inside an iframe is refused (frame-relative box)" "exit 1" "$(mcp click f2e3 --force)"
t_eq "the box is the real e9's, not a spoofed one in page text" 0 "$(n 'mousemove 1 1')"
t_eq "no refused force-click pressed anything" 0 "$(n '^mousedown\|^mousemove')"

t_section "upload: from anywhere but ~/.claude"
UPF="$T_TMP/feed.csv"; printf 'id\n1\n' > "$UPF"
CD="$HOME/.claude"; mkdir -p "$CD/projects"; printf 'x\n' > "$CD/projects/notes.md"; printf 'x\n' > "$CD/creds"
ln -s "$CD/projects/notes.md" "$T_TMP/innocent.csv"; mkdir -p "$T_TMP/via"; ln -s "$CD" "$T_TMP/via/dir"
ln -s "$T_TMP/innocent.csv" "$T_TMP/chain.csv"; ln -s "$UPF" "$T_TMP/fine-link.csv"; mkdir -p "$T_TMP/pub"; ln "$CD/creds" "$T_TMP/pub/hard"
: > "$CALLS"
t_eq "an absolute file passes" "exit 0" "$(mcp upload "$UPF")"
t_has "and reaches the daemon as given" "$(cat "$CALLS")" "upload $UPF"
t_eq "two files pass" "exit 0" "$(mcp upload "$UPF" "$UPF")"
t_eq "a harmless symlink passes" "exit 0" "$(mcp upload "$T_TMP/fine-link.csv")"
: > "$CALLS"
t_eq "upload with no file is refused" "exit 1" "$(mcp upload)"
t_eq "a relative path is refused" "exit 1" "$(mcp upload feed.csv)"
t_eq "a directory is refused" "exit 1" "$(mcp upload "$T_TMP")"
t_eq "a missing file is refused" "exit 1" "$(mcp upload "$T_TMP/nope.csv")"
t_eq "a file under the home Claude dir is refused" "exit 1" "$(mcp upload "$CD/creds")"
t_has "naming the constitution" "$(txt)" "CONSTITUTION №3"
t_eq "a symlink into it is refused" "exit 1" "$(mcp upload "$T_TMP/innocent.csv")"
t_eq "a path through a symlinked dir into it is refused" "exit 1" "$(mcp upload "$T_TMP/via/dir/creds")"
t_eq "a chain of links into it is refused" "exit 1" "$(mcp upload "$T_TMP/chain.csv")"
t_eq "a hardlink to a file in it is refused" "exit 1" "$(mcp upload "$T_TMP/pub/hard")"
t_has "naming the hard links" "$(txt)" "hard links"
t_eq "one bad file refuses the whole upload" "exit 1" "$(mcp upload "$UPF" "$CD/creds")"
UCASE="$(printf '%s' "$CD" | sed 's/\.claude$/.CLAUDE/')"
if [ -f "$UCASE/creds" ]; then
  t_eq "the same dir in another case is refused (APFS ignores case)" "exit 1" "$(mcp upload "$UCASE/creds")"
else echo "  SKIP the case arm: this filesystem is case-sensitive"; fi
t_eq "none of them reached the daemon" 0 "$(grep -c . "$CALLS")"
: > "$CTL/upload_denied"
t_eq "Chrome refusing the file input is refused" "exit 1" "$(mcp upload "$UPF")"
t_has "naming the extension setting" "$(txt)" "Allow access to file URLs"
clean

t_section "the stops after a verb: state probe, lost tab, hidden tab"
: > "$CALLS"
t_eq "state passes" "exit 0" "$(mcp state)"
t_eq "it runs one fixed expression through --raw eval" 1 "$(n 'eval JSON.stringify({visibility: document.visibilityState.* \[raw\]')"
t_has "and prints the page's answer" "$(txt)" "business.facebook.com"
t_eq "state with an argument is refused" "exit 1" "$(mcp state 'document.cookie')"
t_eq "and eval itself is no tool" "exit 1" "$(mcp eval 'document.cookie')"
: > "$CALLS"
t_eq "a fill on a live page passes" "exit 0" "$(mcp fill e9 hello)"
t_eq "and is followed by one probe of the daemon's current tab" 1 "$(n '^tab-list')"
t_eq "which is not an eval (the daemon waits 500 ms after one)" 0 "$(n '^eval')"
: > "$CALLS"; mcp goto https://ads.reddit.com/x >/dev/null
t_eq "a goto is not probed" 0 "$(n '^tab-list')"
: > "$CTL/blank"
t_eq "a fill whose tab went blank is refused" "exit 1" "$(mcp fill e9 hello)"
t_has "naming the lost tab" "$(txt)" "the tab was lost"
t_has "and the way back" "$(txt)" "fix: harbor chrome goto"
t_eq "a click whose tab went blank is refused too" "exit 1" "$(mcp click e3)"
ERRX="$DD/0123/claude-abc123def456.err"
printf '%s\n' '2026-10-14T12:11:04.000Z pw:mcp:relay → Playwright: Target.detachedFromTarget' '2026-10-14T12:11:04.205Z pw:mcp:error Error: Cannot access a chrome-extension:// URL of different extension' > "$ERRX"
t_eq "a tab lost to another extension's frame is refused" "exit 1" "$(mcp fill e9 hello)"
t_has "naming the other extension" "$(txt)" "another extension put a frame in the page at 2026-10-14T12:11:04.000Z"
t_has "and the site-access fix" "$(txt)" "Site access"
rm -f "$ERRX"
t_eq "without that error the plain lost-tab refusal stands" "exit 1" "$(mcp fill e9 hello)"
t_hasnt "and blames no extension" "$(txt)" "another extension put a frame"
clean
: > "$CTL/tablist_fail"
t_eq "the probe's own failure gives no verdict: the verb's result stands" "exit 0" "$(mcp press Tab)"
clean
# the detach lands ~300 ms after the input: a settle of 0 misses it, the default 500 ms catches it
: > "$CTL/late_blank"
t_eq "CONTROL: with no settle a tab that goes blank 0.3 s after the fill is missed" "exit 0" "$(mcp fill e9 hello)"
rm -f "$CTL/late_blank_now"; seams 500
t_eq "with the settle a tab that goes blank 0.3 s after the fill is caught" "exit 1" "$(mcp fill e9 hello)"
clean; rm -f "$CTL/late_blank_now"
# the daemon's own post-action wait counts toward the settle: a daemon that took 0.6 s needs no sleep after it
seams 500; : > "$CTL/delay_ms"; printf 600 > "$CTL/delay_ms"
mcp press Tab >/dev/null; _row="$(tail -n 1 "$WD/.timings.tsv")"
t_eq "a verb the daemon took 0.6 s over is not slept on again (settle column under 100 ms)" yes "$(printf '%s' "$_row" | awk -F '\t' '$5 + 0 >= 600 && $6 + 0 < 100 { print "yes" }')"
rm -f "$CTL/delay_ms"; mcp press Tab >/dev/null; _row="$(tail -n 1 "$WD/.timings.tsv")"
t_eq "an instant daemon is waited out to the settle (500 ms)" yes "$(printf '%s' "$_row" | awk -F '\t' '$6 + 0 >= 450 { print "yes" }')"
seams 0
: > "$CTL/hidden"; : > "$CTL/fail"
t_eq "a failed click on a hidden tab is refused" "exit 1" "$(mcp click e3)"
t_has "naming the way back" "$(txt)" "fix: harbor chrome front"
t_has "and saying the tab is hidden" "$(txt)" "the tab is hidden"
clean; : > "$CTL/fail"
t_eq "a failed click on a visible tab keeps the daemon's own error" "exit 1" "$(mcp click e3)"
t_hasnt "without the hidden hint" "$(txt)" "the tab is hidden"
t_has "and its words" "$(txt)" "TimeoutError"
clean

t_section "the stops after a verb: signed out, the other extension's frame, a gone session"
printf '    account:  tools@example.lt | primary | Business Admin | ads.reddit.com in Chrome via harbor chrome\n' > "$ACC/reddit.md"
printf '    account:  me@example.lt | primary | admin | business.facebook.com in the browser\n' > "$ACC/meta.md"
printf 'https://www.reddit.com/login/?dest=x' > "$CTL/page_url"
t_eq "a goto that lands on sign-in is refused" "exit 1" "$(mcp goto https://ads.reddit.com/account/x)"
t_has "saying signed out, from the app's host" "$(txt)" "signed out: ads.reddit.com sent this session to a sign-in page (www.reddit.com)"
t_has "naming the primary account from the route card" "$(txt)" "sign in as tools@example.lt (reddit.md)"
t_has "and the wait that follows" "$(txt)" "then harbor chrome wait-signin"
t_has "as a hand-off" "$(txt)" "FAIL: hand-off: signed out"
t_has "saying harbor never fills a password" "$(txt)" "never fills a password or picks a password-manager entry"
printf 'https://www.facebook.com/login.php' > "$CTL/page_url"
t_eq "a subdomain finds its parent's card" "exit 1" "$(mcp goto https://eu.business.facebook.com/x)"
t_has "naming that card's account" "$(txt)" "sign in as me@example.lt (meta.md)"
printf 'https://accounts.shopify.com/lookup' > "$CTL/page_url"
t_eq "an accounts. host is sign-in" "exit 1" "$(mcp goto https://www.office.com/)"
t_has "and a host no card names gets no guessed account" "$(txt)" "fix: operator: sign in; then"
printf 'https://ads.example.com/i18n/login' > "$CTL/page_url"
t_eq "a login segment deeper in the path is sign-in" "exit 1" "$(mcp goto https://ads.reddit.com/a)"
printf 'https://ads.reddit.com/settings/login-history' > "$CTL/page_url"
t_eq "a login word inside a segment is not" "exit 0" "$(mcp goto https://ads.reddit.com/settings/login-history)"
printf 'https://ads.reddit.com/x?next=/login' > "$CTL/page_url"
t_eq "nor one in the query" "exit 0" "$(mcp goto https://ads.reddit.com/x)"
printf 'https://login.example.net/' > "$CTL/page_url"
t_eq "a click that lands on sign-in is refused too" "exit 1" "$(mcp click e3)"
clean
printf '601\n' > "$WD/.owned-tabs"; STUB_TABS="$T_TMP/tabs-out"
printf '= window 9 tab 1 active https://login.example.net/\n  window 7 tab 1 active https://accounts.google.com\n' > "$STUB_TABS"
: > "$CTL/fail"
t_eq "a failed goto whose tab Chrome shows on sign-in is refused as signed out" "exit 1" "$(mcp goto https://ads.reddit.com/x)"
t_has "naming the account" "$(txt)" "sign in as tools@example.lt (reddit.md)"
printf '= window 9 tab 1 active https://ads.reddit.com/x\n  window 7 tab 1 active https://accounts.google.com\n' > "$STUB_TABS"
t_eq "a failed goto with only someone else's tab on sign-in stays a plain failure" "exit 1" "$(mcp goto https://ads.reddit.com/x)"
t_hasnt "never blaming the operator's tab" "$(txt)" "signed out"
t_has "and keeps the daemon's own words" "$(txt)" "TimeoutError"
clean; rm -f "$WD/.owned-tabs" "$ACC"/*.md
XE="$T_TMP/xe.err"; : > "$XE"; printf '%s' "$XE" > "$CTL/xerr"; cp "$XE" "$DD/0123/claude-abc123def456.err"; printf '%s' "$DD/0123/claude-abc123def456.err" > "$CTL/xerr"
t_eq "a goto lost to another extension's frame is refused" "exit 1" "$(mcp goto https://ads.reddit.com/)"
t_has "naming the extension, not just a closed page" "$(txt)" "another extension put a frame in the page"
t_has "and the sign-in the operator does" "$(txt)" "operator: sign in to ads.reddit.com"
clean; : > "$CTL/fail"; : > "$DD/0123/claude-abc123def456.err"
t_eq "an old extension line in the log does not name a fresh failure" "exit 1" "$(mcp goto https://ads.reddit.com/)"
t_hasnt "so a plain failure stays plain" "$(txt)" "another extension"
clean; rm -f "$DD/0123/claude-abc123def456.err"
: > "$CTL/token_url"
t_eq "tab-list with the connect page passes" "exit 0" "$(mcp tab_list)"
t_hasnt "and hides the token" "$(txt)" "SEKRET99"
t_has "only that the query was cut" "$(txt)" "connect.html?<cut>"
clean
printf '%s\n' '2026-10-01T13:20:00.000Z pw:mcp:relay ws closed> Extension WebSocket closed: All controlled tabs detached' > "$DD/0123/claude-abc123def456.err"
mv "$DD/0123/claude-abc123def456.session" "$T_TMP/session.keep"
: > "$CALLS"
t_eq "a session with no daemon is refused" "exit 1" "$(mcp click e3)"
t_has "as a hand-off, so the failure ledger files it as the operator's (FC-10)" "$(txt)" "FAIL: hand-off: no Chrome is connected to session claude-abc123def456"
t_has "with the relay's recorded close" "$(txt)" "the relay last closed with Extension WebSocket closed: All controlled tabs detached"
t_has "and the attach that brings it back" "$(txt)" "fix: harbor chrome attach"
t_eq "and nothing reached the daemon" 0 "$(grep -c . "$CALLS")"
mv "$T_TMP/session.keep" "$DD/0123/claude-abc123def456.session"; rm -f "$DD/0123/claude-abc123def456.err"
t_eq "CONTROL: with the session file back the same call passes" "exit 0" "$(mcp click e3)"
printf '{"name":"x","timestamp":9,"socketPath":"%s/none.sock"}\n' "$T_TMP" > "$DD/0123/claude-abc123def456.session"
t_eq "a session whose daemon is not listening is the same hand-off" "exit 1" "$(mcp tab_list)"
t_has "naming it" "$(txt)" "no Chrome is connected"
sess 3

t_section "the verbs that are Chrome's own run in the shell agent, unchanged, with a scrubbed environment"
t_eq "attach is the shell agent's" "exit 0" "$(mcp attach)"
t_eq "...called with the verb" "arg=attach" "$(txt | sed -n 1p)"
t_eq "tab-new carries its url as one argument" "arg=https://example.com/a b; rm -rf /" "$(mcp tab_new 'https://example.com/a b; rm -rf /' >/dev/null; txt | sed -n 2p)"
t_has "no session id: one browser session per parent session" "$(printf '%s\n' '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"hosts","arguments":{}}}' | env -i HOME="$HOME" TMPDIR="$T_TMP" PATH="$PATH" bun "$SRV" | jq -r '.result.content[0].text')" "session=mcp-"
t_has "a repo's PATH does not reach it: it gets the fixed one" "$(mcpe PATH="$T_TMP/evil:$PATH" hosts >/dev/null; txt)" "path=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin private=none"
t_has "...nor its seam that widens the host list" "$(mcpe HARBOR_BROWSER_PRIVATE_HOSTS=/tmp/evil hosts >/dev/null; txt)" "private=none"
t_eq "a daemon the shell agent replaces (attach, detach) is not held on to" 1 "$(: > "$CTL/conns"; mcp tab_list >/dev/null; mcp detach >/dev/null; sess 4; mcp tab_list >/dev/null; mcp tab_list >/dev/null; grep -c . "$CTL/conns" | awk '{ print ($1 >= 2 ? 1 : 0) }')"

t_section "the launcher: access-chrome-mcp.py hands the session to this server, under its scrubbed environment"
if command -v python3 >/dev/null 2>&1; then
  cp "$T_ROOT/bin/access-chrome-mcp.py" "$X/bin/"
  L="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | envs python3 -I "$X/bin/access-chrome-mcp.py" | jq -r .result.serverInfo.version)"
  t_eq "with the .ts beside it the server that answers is the session server" 2 "$L"
  : > "$CALLS"
  R="$(printf '%s\n' "$(jq -cn '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"tab_list",arguments:{}}}')" | envs PLAYWRIGHT_MCP_CONFIG=/tmp/evil python3 -I "$X/bin/access-chrome-mcp.py" | jq -r .result.isError)"
  t_eq "a project's PLAYWRIGHT_* in the launcher's environment never reaches the server" false "$R"
  t_eq "...and the call went to the daemon" 1 "$(n tab-list)"
  mkdir -p "$T_TMP/legacy"; cp "$T_ROOT/bin/access-chrome-mcp.py" "$T_TMP/legacy/"
  t_eq "without the .ts beside it the launcher serves the shell-agent loop, as before" 1 \
    "$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | envs python3 -I "$T_TMP/legacy/access-chrome-mcp.py" | jq -r .result.serverInfo.version)"
else echo "  SKIP the launcher: no python3"; fi

t_done
