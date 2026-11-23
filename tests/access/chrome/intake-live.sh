#!/usr/bin/env sh
# intake-live.sh (contracts/secret-intake.md, 2026-11-23) — a LIVE probe of `harbor chrome intake`: does the pinned CLI's
# headless Chrome hand a page's Copy to navigator.clipboard.readText()? The suites stub the CLI, so only this answers it.
#   sh tests/access/chrome/intake-live.sh      outside the Claude sandbox: it binds 127.0.0.1 and starts a headless Chrome
# Not a suite. A throwaway headless-lane Chrome (no profile, never a window), the keychain stub and a temp private layer:
# the operator's Chrome, Keychain and macOS clipboard are never touched. Serves intake-live.html, clicks Create, then
# intake on its Copy & Close (the dialog closes, so only the clipboard can carry the key), and compares the store.
# Exit 0 the key reached the store unseen · 1 it did not · 3 skipped (no bunx, python3 or jq).
set -eu
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
for _t in bunx python3 jq; do command -v "$_t" >/dev/null 2>&1 || { echo "SKIP: no $_t"; exit 3; }; done
T="$(mktemp -d "${TMPDIR:-/tmp}/intake-live.XXXXXX")"
T_TMP="$T"; T_BIN="$T/bin"; mkdir -p "$T_BIN"; PATH="$T_BIN:$PATH"; export PATH
. "$ROOT/tests/cli/keychain-stub.sh"
XDG_DATA_HOME="$T/xdg"; HARBOR_SCOPE_PRIVATE="$T/pv"; PORT_ROOT="$T/port"; export XDG_DATA_HOME HARBOR_SCOPE_PRIVATE PORT_ROOT
printf '#!/bin/sh\necho "pbpaste ran" >&2; exit 1\n' > "$T_BIN/pbpaste"; printf '#!/bin/sh\necho "pbcopy ran" >&2; exit 1\n' > "$T_BIN/pbcopy"
chmod +x "$T_BIN/pbpaste" "$T_BIN/pbcopy"
sh "$ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
unset CLAUDE_CODE_SESSION_ID HARBOR_ACCESS_BROWSER_LANE
HARBOR_ACCESS_BROWSER_SESSION="intake-live-$$"; export HARBOR_ACCESS_BROWSER_SESSION
WD="${TMPDIR:-/tmp}"; WD="${WD%/}/harbor-browser/$HARBOR_ACCESS_BROWSER_SESSION"
PORT="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -I -m http.server --bind 127.0.0.1 --directory "$ROOT/tests/access/chrome" "$PORT" >/dev/null 2>&1 & SRV=$!
HC() { sh "$ROOT/bin/access-browser-agent.sh" "$@"; }
_done() { HC detach >/dev/null 2>&1 || :; kill "$SRV" 2>/dev/null || :; rm -rf "$T" "$WD"; }
trap _done EXIT INT TERM
ref() { HC snapshot --filename=live.yml >/dev/null && sed -n "s/.*button \"$1\".*\[ref=\(e[0-9]*\)\].*/\1/p" "$WD/live.yml" | head -1; }
KEY='fake-live-key-0123456789abcdef'
sleep 1
HC attach --headless
HC goto "http://127.0.0.1:$PORT/intake-live.html" >/dev/null
HC click "$(ref Create)" >/dev/null
R="$(ref 'Copy \& Close')"; [ -n "$R" ] || { echo "FAIL: no Copy & Close button in the snapshot"; exit 1; }
held() { /usr/bin/grep -rlF -- "$KEY" "$WD" 2>/dev/null | sort || :; }   # workdir files that hold the key
B4="$(held)"
OUT="$(HC intake "$R" add github-live-intake --kind token --what w --use-when u --reaches r --cannot c --grant g \
  --secret harbor-github-tools-liveintake --vendor-name 'EXAMPLECO API GitHub' 2>&1)" || :
printf '%s\n' "$OUT"
GOT="$(sh "$ROOT/bin/secret" run harbor-github-tools-liveintake V -- sh -c 'printf %s "$V"' 2>/dev/null || :)"
case "$OUT" in *"$KEY"*) echo "FAIL: the key was shown in the intake output"; exit 1 ;; esac
NEW="$(held | /usr/bin/grep -vxF -- "$B4" || :)"; [ -n "$B4" ] || NEW="$(held)"
[ -z "$NEW" ] || { echo "FAIL: intake left the key in a workdir file: $NEW"; exit 1; }
[ -z "$B4" ] || echo "note: before intake, the CLI's own snapshot of the open dialog already held the key in: $B4"
HC snapshot --filename=live.yml >/dev/null; printf 'page: %s\n' "$(sed -n 's/.*paragraph.*: \(copied by .*\)$/\1/p' "$WD/live.yml")"
[ "$GOT" = "$KEY" ] || { echo "FAIL: the store does not hold the page's key (clipboard.readText gave nothing usable headless)"; exit 1; }
echo "ok: the page's Copy & Close reached the store through this Chrome's own clipboard, unseen"
