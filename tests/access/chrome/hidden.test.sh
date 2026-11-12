#!/usr/bin/env sh
# access-chrome-mcp.ts (harbor#1507): a click that timed out on a hidden tab runs front in the session's own lane and retries
# once; where front refuses, its reason is the answer. Through the server, against the fake daemon (server-env.sh).
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/server-env.sh"

t_section "a hidden tab: front in the session's own lane, then one retry"
: > "$CTL/hidden"; : > "$CTL/fail"
: > "$CALLS"
t_eq "a click that timed out on a hidden tab shows it with front and passes" "exit 0" "$(mcp click e3)"
t_has "saying front showed it and the click was retried" "$(txt)" "front showed it, focus untouched; click retried once"
t_eq "the daemon got the click twice: the timed-out one and the retry" 2 "$(n '^click')"
t_eq "front through the server passes" "exit 0" "$(mcp front)"
t_has "and carries the agent's own report, which it writes to stderr" "$(txt)" "ok: front: window 9 tab 2 is the tab Chrome shows"
clean; : > "$CTL/hidden"; : > "$CTL/fail"; : > "$CTL/front_refuses"; : > "$CALLS"
t_eq "where front refuses (a window holding the operator's tabs) the click is refused" "exit 1" "$(mcp click e3)"
t_has "with front's own reason" "$(txt)" "front could not show it:"; t_has "in its words" "$(txt)" "window 9 holds 1 tab(s) that are not this session's"
t_has "front ran for this session, not a lane" "$(txt)" "lane= path"
t_eq "and the click is not retried" 1 "$(n '^click')"
sed 's/claude-abc123def456/claude-abc123def456-ta/' "$DD/0123/claude-abc123def456.session" > "$DD/0123/claude-abc123def456-ta.session"
_r="$(printf '%s\n' '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"click","arguments":{"args":["e3"],"lane":"ta"}}}' | envs bun "$SRV" 2>&1)"
t_has "a lane's click runs front in that lane" "$(printf '%s' "$_r" | jq -r '.result.content[0].text')" "lane=ta path"
rm -f "$DD/0123/claude-abc123def456-ta.session"
clean; : > "$CTL/hidden"; : > "$CTL/fail"; : > "$CALLS"
t_eq "a press that failed on a hidden tab is refused, not retried (a key press does not wait to be shown)" "exit 1" "$(mcp press Tab)"
t_has "naming the way back" "$(txt)" "fix: harbor chrome front"
t_has "and saying the tab is hidden" "$(txt)" "the tab is hidden"
t_eq "with one press" 1 "$(n '^press')"
clean; : > "$CTL/fail"
t_eq "a failed click on a visible tab keeps the daemon's own error" "exit 1" "$(mcp click e3)"
t_hasnt "without the hidden hint" "$(txt)" "the tab is hidden"
t_has "and its words" "$(txt)" "TimeoutError"
clean

t_done
