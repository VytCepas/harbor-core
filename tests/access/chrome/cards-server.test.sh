#!/usr/bin/env sh
# harbor#1617 in the MCP server (access-chrome-mcp.ts), beside cards.test.sh's shell agent: the sign-in account from the card that
# lists the host, `session: show-only` on goto, and the tool texts. Invented hosts only (example.com).
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/server-env.sh"
printf 'example.com\n' > "$PH"

t_section "the tool texts say what attach is, and verify is a tool"
TL="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
_d="$(printf '%s\n' "$TL" | jq -r '.result.tools[] | select(.name == "attach") | .description')"
t_has "attach: plain attach is the signed-in profile, already without a window" "$_d" "plain attach = the signed-in agent profile, already without a window"
t_has "attach: --blank is no profile, never signed in" "$_d" "--blank = no profile, never signed in"
t_hasnt "attach: no 'throwaway' behind --headless as the way to a profile-less Chrome" "$(printf '%s' "$_d" | sed 's/\["--headless"\] is the old name of --blank[^.]*//')" '["--headless"]: a throwaway'
t_has "signin: several cards" "$(printf '%s\n' "$TL" | jq -r '.result.tools[] | select(.name == "signin") | .description')" '["--cards", "a,b,c"]'
t_has "verify is a tool, read-only" "$(printf '%s\n' "$TL" | jq -r '.result.tools[] | select(.name == "verify") | .description')" "Read-only"
: > "$CALLS"
t_eq "verify runs in the shell agent, with the card" "exit 0" "$(mcp verify somecard)"
t_has "...as the verb and its one argument" "$(txt)" "arg=verify"
t_has "...and its card" "$(txt)" "arg=somecard"
t_eq "the daemon was not asked: verify navigates through the shell agent's own verbs" 0 "$(grep -c . "$CALLS")"

t_section "the sign-in account is the card that lists the host (harbor#1617)"
rm -f "$ACC"/*.md
printf '    identity: prose via a test\n    ui-hosts: other.example.com\n    account:  wrong@example.com | primary | Admin | also uses app.example.com in the browser\n' > "$ACC/aaa.md"
printf '    identity: listed via a test\n    ui-hosts: app.example.com\n    account:  right@example.com | primary | Admin | the app\n' > "$ACC/bbb.md"
printf 'https://login.example.com/' > "$CTL/page_url"
t_eq "a goto that lands on sign-in is refused" "exit 1" "$(mcp goto https://app.example.com/home)"
t_has "naming the account of the card whose ui-hosts lists the host" "$(txt)" "sign in as right@example.com (bbb.md)"
t_hasnt "never the card that only mentions it" "$(txt)" "wrong@example.com"
t_eq "a subdomain of a listed host takes that card" "exit 1" "$(mcp goto https://eu.app.example.com/x)"
t_has "its account" "$(txt)" "sign in as right@example.com (bbb.md)"
rm -f "$ACC/bbb.md"
t_eq "with no card listing the host, the prose reading stays" "exit 1" "$(mcp goto https://app.example.com/home)"
t_has "naming the card that mentions it" "$(txt)" "sign in as wrong@example.com (aaa.md)"
printf '    identity: no primary\n    ui-hosts: app.example.com\n    account:  spare@example.com | fallback | Admin | x\n' > "$ACC/ccc.md"
t_eq "a card that lists the host but holds no primary" "exit 1" "$(mcp goto https://app.example.com/home)"
t_hasnt "names no account and does not fall back to prose" "$(txt)" "wrong@example.com"
rm -f "$ACC"/*.md "$CTL/page_url"

t_section "session: show-only on goto: a headless copy of the agent profile refuses, a window does not (harbor#1617)"
printf '    identity: x\n    ui-hosts: app.example.com\n    session:  show-only - a session cookie\n' > "$ACC/app.md"
printf '    identity: x\n    ui-hosts: plain.example.com\n    session:  persistent\n' > "$ACC/plain.md"
: > "$CALLS"; mkdir -p "$WD"; : > "$WD/.agent"; rm -f "$WD/.shown"
t_eq "goto a show-only host in a headless copy is refused" "exit 1" "$(mcp goto https://app.example.com/home)"
t_has "saying the login does not survive the copy" "$(txt)" "app.md says the login does not survive a headless profile copy (session: show-only - a session cookie)"
t_has "with the one-line fix" "$(txt)" "fix: harbor chrome attach --show --ui='<why>'"
t_eq "and the daemon never ran" 0 "$(grep -c . "$CALLS")"
_stj="$(jq -cn '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"steps",arguments:{steps:[{verb:"goto",args:["https://app.example.com/home"]}]}}}')"
_str="$(printf '%s\n' "$_stj" | envs bun "$SRV" 2>&1)"
t_eq "a goto inside steps is held the same way" true "$(printf '%s' "$_str" | jq -r .result.isError)"
t_has "...with the same line" "$(printf '%s' "$_str" | jq -r '.result.content[0].text')" "does not survive a headless profile copy"
t_eq "session: persistent opens" "exit 0" "$(mcp goto https://plain.example.com/home)"
: > "$WD/.shown"
t_eq "in a window (attach --show) the show-only host opens" "exit 0" "$(mcp goto https://app.example.com/home)"
rm -f "$WD/.agent" "$WD/.shown"
t_eq "a session that is not the agent profile copy is not held" "exit 0" "$(mcp goto https://app.example.com/home)"
rm -f "$ACC"/*.md

t_done
