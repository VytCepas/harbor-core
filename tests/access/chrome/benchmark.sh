#!/usr/bin/env sh
# benchmark.sh (harbor#1421) — what one harbor_chrome click costs, before and after the session server, on a local data: page.
#   sh tests/access/chrome/benchmark.sh [N]   N timed clicks on the new server (default 20); the old chain runs fewer
# HEADLESS, in a throwaway HOME: the operator's Chrome and profile are never touched. before = the launcher's per-call bunx chain;
# after = access-chrome-mcp.py as shipped. Exit 0 ok · 1 median not under 1000 ms or a guard did not refuse · 3 skipped.
# Live check (operator's Chrome, after deploy): run ~6 harbor_chrome calls, then read the click rows of
#   "${TMPDIR:-/tmp}/harbor-browser/claude-<session id>/.timings.tsv" (time, verb, total, guards, daemon, settle ms); compare with 7-12 s.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"; ROOT="${HERE%/tests/access/chrome}"
N="${1:-20}"; OLD_N=$((N < 4 ? N : 4)); SPLIT_N=$((N < 3 ? N : 3))   # the old chain is seconds a click: a few are enough to see its shape
RH="$(eval echo "~$(id -un)")"
skip() { echo "benchmark: SKIP — $1"; exit 3; }
for t in bun python3 perl jq; do command -v "$t" >/dev/null 2>&1 || skip "$t is not installed"; done
CH="$(find "$RH/Library/Caches/ms-playwright" "$RH/.cache/ms-playwright" -type f \( -name chrome-headless-shell -o -name headless_shell \) -perm -u+x 2>/dev/null | sort | tail -1 || :)"
[ -n "$CH" ] || skip "no headless Chromium under ms-playwright's cache"
[ -d "$RH/.bun/install/cache/@playwright" ] || skip "the pinned @playwright/cli is not in bun's cache (run harbor chrome doctor once)"
PIN="$(sed -n "s/^PW_CLI_PIN='\\([0-9.]*\\)'.*/\\1/p" "$ROOT/bin/access-browser-agent.sh")"
[ -n "$PIN" ] || skip "no PW_CLI_PIN in access-browser-agent.sh"

BH="$(mktemp -d /tmp/hbench.XXXXXX)"   # short: a unix socket path is limited to ~100 bytes
S=benchharbor1; SESSION="claude-$S"
pw() { bunx "@playwright/cli@$PIN" "$@"; }   # the pinned CLI, only to start and stop the headless daemon of THIS script
cleanup() { HOME="$BH/home" TMPDIR="$BH/tmp" PWTEST_SOCKETS_DIR="$BH/s" pw "-s=$SESSION" close >/dev/null 2>&1 || :; rm -rf "$BH"; }
trap cleanup EXIT INT TERM HUP
mkdir -p "$BH/home/.claude" "$BH/tmp" "$BH/s" "$BH/legacy/bin" "$BH/legacy/contracts"
ln -s "$RH/.bun" "$BH/home/.bun"
printf 'x\n' > "$BH/home/.claude/creds"
export HOME="$BH/home" TMPDIR="$BH/tmp" PWTEST_SOCKETS_DIR="$BH/s" CLAUDE_CODE_SESSION_ID="$S"
printf '{"browser":{"browserName":"chromium","launchOptions":{"executablePath":"%s","headless":true}}}\n' "$CH" > "$BH/cfg.json"
URL="$(python3 -c 'import sys, urllib.parse; print("data:text/html," + urllib.parse.quote(sys.argv[1]))' \
  "<html><head><title>start</title></head><body><button onclick=\"document.title='clicked-'+(window.k=(window.k||0)+1)\">Go</button><button>Delete</button></body></html>")"
cd "$BH"
pw "-s=$SESSION" open "$URL" "--config=$BH/cfg.json" >"$BH/open.out" 2>&1 || { cat "$BH/open.out"; echo "benchmark: FAIL — the headless daemon did not start"; exit 1; }

# before: the launcher's loop and the shell agent, copied without the .ts so the loop is what serves
cp "$ROOT/bin/access-chrome-mcp.py" "$ROOT/bin/access-browser-agent.sh" "$ROOT/bin/library-log.sh" "$ROOT/bin/scope-roots.sh" "$BH/legacy/bin/"
cp "$ROOT/contracts/browser-agent-hosts.txt" "$ROOT/contracts/browser-script.tsv" "$ROOT/contracts/roots.tsv" "$BH/legacy/contracts/"
DRV="$HERE/benchmark-driver.ts"
OLD="$(bun "$DRV" before "$OLD_N" click REF -- python3 -I "$BH/legacy/bin/access-chrome-mcp.py")"
NEW="$(bun "$DRV" after "$N" click REF -- python3 -I "$ROOT/bin/access-chrome-mcp.py")"

# where the before-time goes: the shell agent itself, its CLI calls timed one by one
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'; }
cat > "$BH/cli-timer.sh" <<EOF
#!/bin/sh
a=\$(perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000')
bunx @playwright/cli@$PIN "\$@"; rc=\$?
b=\$(perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000')
v=other; for x in "\$@"; do case "\$x" in snapshot|click|eval|tab-list) v=\$x ;; esac; done
case "\$*" in *"- Page URL: "*) v=script ;; esac   # a click runs as a script through eval (harbor#1507)
printf '%s %s\n' "\$v" \$((b - a)) >> "$BH/cli.log"
exit \$rc
EOF
chmod +x "$BH/cli-timer.sh"
REF="$(printf '%s' "$OLD" | jq -r .ref)"
: > "$BH/cli.log"; : > "$BH/agent.log"; i=0
while [ "$i" -lt "$SPLIT_N" ]; do
  a="$(now)"
  HARBOR_ACCESS_PLAYWRIGHT_CLI="$BH/cli-timer.sh" sh "$ROOT/bin/access-browser-agent.sh" click "$REF" >/dev/null 2>&1 || echo "benchmark: the instrumented click failed" >&2
  b="$(now)"; echo $((b - a)) >> "$BH/agent.log"; i=$((i + 1))
done
i=0; while [ "$i" -lt "$SPLIT_N" ]; do HARBOR_ACCESS_PLAYWRIGHT_CLI="$BH/cli-timer.sh" sh "$ROOT/bin/access-browser-agent.sh" tab-list >/dev/null 2>&1 || :; i=$((i + 1)); done
med() { sort -n | awk '{ a[NR] = $1 } END { if (NR) print a[int((NR + 1) / 2)]; else print 0 }'; }
cli() { awk -v v="$1" '$1 == v { print $2 }' "$BH/cli.log" | med; }
# tab-list is the last SPLIT_N rows; click's own snapshot/click/eval rows are the first ones
SNAP_MS="$(cli snapshot)"; CLICK_MS="$(cli script)"; EVAL_MS="$(cli eval)"; AGENT_MS="$(med < "$BH/agent.log")"
TABLIST_CLI_MS="$(cli tab-list)"
TABLIST_SOCK_MS="$(bun "$DRV" tab-list-after "$N" tab_list -- python3 -I "$ROOT/bin/access-chrome-mcp.py" | jq -r .median)"
TIMINGS="$BH/tmp/harbor-browser/$SESSION/.timings.tsv"
col() { awk -F '\t' -v c="$1" '$2 == "click" { print $c }' "$TIMINGS" | med; }

B_MED="$(printf '%s' "$OLD" | jq -r .median)"; A_MED="$(printf '%s' "$NEW" | jq -r .median)"
A_P90="$(printf '%s' "$NEW" | jq -r .p90)"; A_FIRST="$(printf '%s' "$NEW" | jq -r .first)"
echo "benchmark: one click on a local page, headless Chromium, pinned @playwright/cli@$PIN"
echo
printf '  %-52s %8s\n' "BEFORE  per call, through the MCP launcher + shell agent (n=$OLD_N)" "${B_MED} ms"
printf '    %-50s %8s\n' "guard snapshot, its bunx + node CLI call" "${SNAP_MS} ms"
printf '    %-50s %8s\n' "the click (a script via eval), its CLI call" "${CLICK_MS} ms"
printf '    %-50s %8s\n' "settle (fixed sleep before the lost-tab probe)" "1000 ms"
printf '    %-50s %8s\n' "lost-tab probe, its bunx + node CLI call" "${EVAL_MS} ms"
printf '    %-50s %8s\n' "shell, awk, mktemp, python (the rest)" "$((AGENT_MS - SNAP_MS - CLICK_MS - EVAL_MS - 1000)) ms"
printf '    %-50s %8s\n' "(the agent alone, n=$SPLIT_N)" "${AGENT_MS} ms"
echo
printf '  %-52s %8s\n' "AFTER   per call, through the session server (n=$N)" "${A_MED} ms"
printf '    %-50s %8s\n' "first call, connect included" "${A_FIRST} ms"
printf '    %-50s %8s\n' "p90" "${A_P90} ms"
printf '    %-50s %8s\n' "guards: argument checks, connect, guard snapshot" "$(col 4) ms"
printf '    %-50s %8s\n' "the click itself, one socket round trip" "$(col 5) ms"
printf '    %-50s %8s\n' "settle and lost-tab probe" "$(col 6) ms"
echo
printf '  %-52s %8s\n' "tab-list through a CLI process (spawn + connect to socket)" "${TABLIST_CLI_MS} ms"
printf '  %-52s %8s\n' "tab-list through the held socket (reconnect: none)" "${TABLIST_SOCK_MS} ms"
echo

# the click really reached the page, and each guard refuses its case against the real daemon
FAIL=0
bad() { echo "benchmark: FAIL — $1"; FAIL=1; }
_tb="$(printf '%s' "$NEW" | jq -r .titleBefore | sed 's/^clicked-//')"; _ta="$(printf '%s' "$NEW" | jq -r .titleAfter | sed 's/^clicked-//')"
case "$_tb$_ta" in *[!0-9]*) bad "the page title does not count clicks (before '$_tb', after '$_ta')" ;; *)
  [ $((_ta - _tb)) -eq $((N + 1)) ] || bad "the page saw $((_ta - _tb)) clicks, not $((N + 1))" ;; esac
[ "$(printf '%s' "$NEW" | jq -r .error)" = false ] || bad "the last click returned an error: $(printf '%s' "$NEW" | jq -r .last)"
g() { # <label> <expected text> <tool> <arg>...
  _l="$1"; _w="$2"; shift 2
  _o="$(bun "$DRV" guard 0 "$@" -- python3 -I "$ROOT/bin/access-chrome-mcp.py")"
  if [ "$(printf '%s' "$_o" | jq -r .error)" = true ] && printf '%s' "$_o" | jq -r .last | grep -q -- "$_w"; then echo "  refused: $_l"; else bad "$_l was not refused ($_o)"; fi
}
g "a destructive label (Delete)" "destructive click refused" click REF:Delete
g "a host off the allowlist" "host refused" goto https://evil.example/
g "a path under ~/.claude" "CONSTITUTION" upload "$HOME/.claude/creds"
g "an absolute --filename" "filename refused" screenshot --filename=/tmp/x.png
g "an option the allowlist lacks" "option refused" click REF --config=/tmp/c.json
if [ "$A_MED" -lt 1000 ]; then echo "  median ${A_MED} ms < 1000 ms"; else bad "the median click is ${A_MED} ms, not under 1000 ms"; fi
[ "$A_MED" -lt "$B_MED" ] || bad "the session server is not faster than the process chain"

# detach releases the connection: with the daemon closed the server answers with the hand-off, not a stale socket
pw "-s=$SESSION" close >/dev/null 2>&1 || :
G="$(bun "$DRV" closed 0 tab_list -- python3 -I "$ROOT/bin/access-chrome-mcp.py")"
printf '%s' "$G" | jq -r .last | grep -q 'no Chrome is connected' && echo "  a closed daemon: hand-off, no stale connection" || bad "a closed daemon was not reported as a hand-off ($G)"
[ "$FAIL" -eq 0 ] || exit 1
echo "benchmark: ok"
