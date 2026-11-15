# server-env.sh — sourced by the access-chrome-mcp.ts suites (session, hidden): the server copied beside a stub shell agent,
# a fake daemon (fake-daemon.ts) on a unix socket, and the mcp/n/txt helpers. Split out when session.test.sh reached its
# 500-line budget (harbor#1507); a suite sets REQ_BUN and runs core.sh's t_init itself, then sources this.
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"
# Where bun is absent (the hosted runner image) the suite skips loudly with one assertion, as panels.test.sh does (harbor#738).
if ! command -v bun >/dev/null 2>&1; then
  echo "  SKIP session: bun is not installed (the server's interpreter)"
  t_section "bun is absent: only an image that does not promise it may skip"
  t_eq "HARBOR_TEST_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
  t_done; exit 0
fi
SRVSRC="$T_ROOT/bin/access-chrome-mcp.ts"; AG="$T_ROOT/bin/access-browser-agent.sh"
X="$T_TMP/x"; mkdir -p "$X/bin" "$X/contracts"; cp "$SRVSRC" "$X/bin/"; cp "$T_ROOT/contracts/browser-agent-hosts.txt" "$T_ROOT/contracts/browser-script.tsv" "$X/contracts/"
cp "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$X/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$X/contracts/"
SRV="$X/bin/access-chrome-mcp.ts"
CTL="$T_TMP/ctl"; mkdir -p "$CTL"; SOCK="$T_TMP/d.sock"; PH="$T_TMP/priv-hosts.txt"; : > "$PH"
DD="$T_TMP/daemons"; mkdir -p "$DD/0123"; WD="$T_TMP/harbor-browser/claude-abc123def456"
sess() { printf '{"name":"claude-abc123def456","version":"1.64.0","timestamp":%s,"socketPath":"%s"}\n' "$1" "$SOCK" > "$DD/0123/claude-abc123def456.session"; }
SETF="$T_TMP/settings.json"
seams() { printf '{"daemonDir":"%s","settingsFile":"'"$SETF"'","settleMs":%s,"privHosts":"%s","accessDir":"%s","scopeEnv":{"HARBOR_SCOPE_PRIVATE":"%s","PORT_ROOT":"%s"},"agentEnv":{"STUB_TABS":"%s","STUB_CTL":"%s"}}\n' \
  "$DD" "$1" "$PH" "$ACC" "${PRIV:-$T_TMP/nopriv}" "$T_TMP/pr" "$T_TMP/tabs-out" "$CTL" > "$X/bin/access-chrome-mcp.seams.json"; }
PRIV="$T_TMP/nopriv"; mkdir -p "$PRIV"; seams 0; sess 1
# the stub shell agent: what the verbs that are Chrome's own run (attach, tabs, ...), and the tab list the sign-in stop reads
cat > "$X/bin/access-browser-agent.sh" <<'EOF'
for a in "$@"; do printf 'arg=%s\n' "$a"; done
printf 'session=%s lane=%s path=%s private=%s\n' "${HARBOR_ACCESS_BROWSER_SESSION:-}" "${HARBOR_ACCESS_BROWSER_LANE:-${HARBOR_BROWSER_LANE:-}}" "$PATH" "${HARBOR_ACCESS_BROWSER_PRIVATE_HOSTS:-${HARBOR_BROWSER_PRIVATE_HOSTS:-none}}"
# front: shows the tab (the daemon stops reading hidden and failing), or refuses as for a window holding the operator's tabs
case "$1" in front) [ ! -e "$STUB_CTL/front_refuses" ] || { echo "FAIL: front: window 9 holds 1 tab(s) that are not this session's"; exit 1; }; rm -f "$STUB_CTL/hidden" "$STUB_CTL/fail"; echo "  ok: front: window 9 tab 2 is the tab Chrome shows; focus left where it was" >&2 ;; esac
case "$1" in tabs) cat "$STUB_TABS" 2>/dev/null || : ;; attach) [ -z "${STUB_REATTACH:-}" ] || cp "$STUB_REATTACH.keep" "$STUB_REATTACH" ;; esac
EOF
bun "$T_ROOT/tests/access/chrome/fake-daemon.ts" "$SOCK" "$CTL" "$SNAP" & DPID=$!
trap 'kill $DPID 2>/dev/null; chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT
_i=0; while [ ! -e "$CTL/ready" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
[ -e "$CTL/ready" ] || { t_fail "the fake daemon did not start"; t_done; exit 1; }
CALLS="$CTL/calls"; : > "$CALLS"
clean() { rm -f "$CTL"/fail_script "$CTL"/script_result "$CTL"/download "$CTL"/blank "$CTL"/hidden "$CTL"/eval_fail "$CTL"/tablist_fail "$CTL"/fail "$CTL"/upload_denied "$CTL"/late_blank* "$CTL"/xerr "$CTL"/page_url "$CTL"/delay_ms "$CTL"/token_url "$CTL"/front_refuses; }

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
