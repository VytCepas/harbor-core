#!/usr/bin/env sh
# access-chrome-mcp.py (harbor#1301): `harbor chrome` as the MCP server harbor_chrome. A copy of the server beside a
# stub browser-agent.sh proves the mapping (one verb per tool, arguments as a list, the session it names); the real
# server beside the real CLI proves the CLI's own host allowlist still decides, with nothing reaching Chrome.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SRV="$T_ROOT/bin/access-chrome-mcp.py"; AG="$T_ROOT/bin/browser-agent.sh"
command -v python3 >/dev/null 2>&1 || { t_fail "python3 is required (the server's interpreter)"; t_done; }
X="$T_TMP/x"; mkdir -p "$X"; cp "$SRV" "$X/access-chrome-mcp.py"
cat > "$X/browser-agent.sh" <<'EOF'
for a in "$@"; do printf 'arg=%s\n' "$a"; done
printf 'session=%s lane=%s\n' "${HARBOR_BROWSER_SESSION:-}" "${HARBOR_BROWSER_LANE:-}"
printf 'path=%s private=%s\n' "$PATH" "${HARBOR_BROWSER_PRIVATE_HOSTS:-none}"
case "$1" in fail) echo 'FAIL: refused by the stub' >&2; exit 1 ;; esac
EOF
# rpc <server> <line>... -> the server's replies, one JSON object per line
rpc() { _s="$1"; shift; printf '%s\n' "$@" | env -u CLAUDE_CODE_SESSION_ID python3 -I "$_s" 2>&1; }
callj() { printf '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
text() { printf '%s' "$1" | jq -r '.result.content[0].text' 2>/dev/null; }
iserr() { printf '%s' "$1" | jq -r '.result.isError' 2>/dev/null; }

t_section "the protocol"
OUT="$(rpc "$X/access-chrome-mcp.py" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"ping"}')"
t_eq "initialize echoes a version it speaks" 2025-03-26 "$(printf '%s\n' "$OUT" | head -1 | jq -r .result.protocolVersion)"
t_eq "...names the server harbor_chrome" harbor_chrome "$(printf '%s\n' "$OUT" | head -1 | jq -r .result.serverInfo.name)"
t_eq "a notification gets no reply (two requests, two replies)" 2 "$(printf '%s\n' "$OUT" | grep -c .)"
t_eq "an unknown version gets the newest it speaks" 2025-06-18 \
  "$(rpc "$X/access-chrome-mcp.py" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}' | jq -r .result.protocolVersion)"
t_eq "an unknown method is -32601" -32601 "$(rpc "$X/access-chrome-mcp.py" '{"jsonrpc":"2.0","id":1,"method":"resources/list"}' | jq -r .error.code)"
t_eq "a line that is not JSON is -32700, and the server keeps serving" "-32700 {}" \
  "$(rpc "$X/access-chrome-mcp.py" 'not json' '{"jsonrpc":"2.0","id":2,"method":"ping"}' | jq -rc '.error.code // .result' | tr '\n' ' ' | sed 's/ $//')"

t_section "one tool per harbor chrome verb, and none the CLI refuses"
TL="$(rpc "$X/access-chrome-mcp.py" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[].name' | sort)"
ALLOWED="$(awk '/^_allowed\(\) \{/ { f = 1; next } f && /case "\$1" in/ { next } f && /return 0/ { sub(/\).*/, ""); gsub(/[ \t\\]/, ""); print; exit } f { gsub(/[ \t\\]/, ""); printf "%s", $0 }' "$AG" | tr '|' '\n' | sed '/^$/d')"
SESSION_VERBS='attach status state doctor detach tabs front wait-signin hosts'
WANT="$(printf '%s\n' $ALLOWED $SESSION_VERBS | tr '-' '_' | sort -u)"
t_eq "CONTROL: the CLI's allowlist parses" yes "$([ "$(printf '%s\n' "$ALLOWED" | grep -c .)" -ge 20 ] && echo yes || echo no)"
t_eq "the tools are exactly the CLI's allowed verbs and its session verbs" "$WANT" "$TL"
t_hasnt "no tool runs code in a logged-in page" "$TL" "eval"
_bad=""; for _n in $TL; do sh "$T_ROOT/bin/lint-name.sh" --check mcp-tool "mcp__harbor_chrome__$_n" 2>&1 | grep -q 'no finding' || _bad="$_bad $_n"; done
t_eq "every tool name passes the mcp-tool surface (surfaces.tsv)" "" "$_bad"

t_section "a call is the verb and its arguments as a list, never a shell string"
R="$(rpc "$X/access-chrome-mcp.py" "$(callj tab_new '{"args":["https://example.com/a b; rm -rf /"]}')")"
t_eq "the tool's hyphenated verb" "arg=tab-new" "$(text "$R" | sed -n 1p)"
t_eq "an argument with spaces and a ; arrives as one argument" 'arg=https://example.com/a b; rm -rf /' "$(text "$R" | sed -n 2p)"
t_eq "...and the call succeeded" false "$(iserr "$R")"
R2="$(rpc "$X/access-chrome-mcp.py" "$(callj fill '{"args":["e12","hello world"]}')")"
t_eq "two arguments arrive as two, the second keeping its space" "arg=fill|arg=e12|arg=hello world" "$(text "$R2" | grep '^arg=' | tr '\n' '|' | sed 's/|$//')"
t_has "no session id: one browser session per parent session" "$(text "$R")" "session=mcp-"
R="$(printf '%s\n' "$(callj snapshot '{}')" | CLAUDE_CODE_SESSION_ID=abc123 python3 -I "$X/access-chrome-mcp.py")"
t_has "with a session id the CLI names the session itself" "$(text "$R")" "session= lane="
R="$(rpc "$X/access-chrome-mcp.py" "$(callj snapshot '{"lane":"two"}')")"
t_has "a lane reaches the CLI, which validates it" "$(text "$R")" "lane=two"
cp "$X/browser-agent.sh" "$X/ba.keep"; printf 'echo "FAIL: refused by the stub" >&2; exit 1\n' > "$X/browser-agent.sh"
R="$(rpc "$X/access-chrome-mcp.py" "$(callj goto '{"args":["https://x.example/"]}')")"
t_eq "a refusal by the CLI is an error result" true "$(iserr "$R")"
t_has "...carrying the CLI's own words" "$(text "$R")" "FAIL: refused by the stub"
cp "$X/ba.keep" "$X/browser-agent.sh"
t_eq "an unknown tool is an error result" true "$(iserr "$(rpc "$X/access-chrome-mcp.py" "$(callj run_code '{}')")")"
t_eq "args that are not strings are an error result" true "$(iserr "$(rpc "$X/access-chrome-mcp.py" "$(callj goto '{"args":[1]}')")")"
t_eq "HARBOR_BROWSER_AGENT in the environment names no other CLI" "arg=hosts" \
  "$(text "$(printf '%s\n' "$(callj hosts '{}')" | HARBOR_BROWSER_AGENT=/bin/false python3 -I "$X/access-chrome-mcp.py")" | sed -n 1p)"

R="$(printf '%s\n' "$(callj hosts '{}')" | env -u CLAUDE_CODE_SESSION_ID PATH="$T_TMP/evil:$PATH" HARBOR_BROWSER_PRIVATE_HOSTS=/tmp/evil-hosts python3 -I "$X/access-chrome-mcp.py")"
t_has "a repo's PATH does not reach the CLI: it gets the fixed one" "$(text "$R")" "path=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin private="
t_has "...nor its seam that widens the host list" "$(text "$R")" "private=none"
t_section "a malformed request is an error reply, and the server keeps serving"
OUT="$(rpc "$X/access-chrome-mcp.py" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":["goto"]}}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":[1]}' '{"jsonrpc":"2.0","id":3}' '{"jsonrpc":"2.0","id":4,"method":"ping"}')"
t_eq "a list for a tool name, a list for params, no method; then a ping" "-32602 -32602 -32600 {}" \
  "$(printf '%s\n' "$OUT" | jq -rc '.error.code // .result' | tr '\n' ' ' | sed 's/ $//')"

t_section "the real CLI decides: its host allowlist, through the server"
R="$(rpc "$SRV" "$(callj goto '{"args":["https://evil.example/"]}')")"
t_eq "a host off the allowlist is refused" true "$(iserr "$R")"
t_has "...by the CLI's host check" "$(text "$R")" "host refused: 'https://evil.example/'"
R="$(rpc "$SRV" "$(callj hosts '{}')")"
t_has "CONTROL: the allowlist the refusal read" "$(text "$R")" "CONTRACTS/browser-agent-hosts.txt"
t_done
