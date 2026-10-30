#!/usr/bin/env sh
# status-console.sh (harbor#738) — `harbor ui`: Harbor's live state as read-only panels on a localhost page.
#
#   sh bin/status-console.sh [--port N] [--idle SECS] [--wait SECS] [--min-age SECS] [--timeout SECS] [--open]
#   --port N     listen on 127.0.0.1:N (default: a free port)
#   --idle SECS  stop after this many seconds with no request (default 1800)
#   --wait SECS  how long a page load waits for the panels before showing "running" for the rest (default 3)
#   --min-age SECS  a page load re-runs a source only when none is stored or it is this old (default 300)
#   --timeout SECS  cap on any one source, which is killed with everything it forked (default: its own)
#   --open       open the URL in the default browser
#
# Prints one URL whose launch code opens the console once, then is swapped for a session cookie. The server is tools/ui/server.ts on Bun: no framework, no
# dependencies, bound to 127.0.0.1, and it runs only the commands in tools/ui/sources.ts. Needs bun.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2
. "$HERE/library-log.sh"
log_init status-console

case "${1:-}" in -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
_refuse() { log_fail "$1"; log_fix "$2"; log_end || :; exit 2; }

# The server lives in the checkout; an installed copy of this script finds it at the conventional path.
SERVER="${HERE%/bin}/tools/ui/server.ts"
_pr="${PORT_ROOT:-$HOME/port}"
[ -f "$SERVER" ] || SERVER="$_pr/harbor/tools/ui/server.ts"
[ -f "$SERVER" ] || _refuse "tools/ui/server.ts is not beside ${HERE%/bin} or in $_pr/harbor" "sh $_pr/harbor/bin/status-console.sh"

BUN="${HARBOR_STATUS_CONSOLE_BUN:-}"
[ -n "$BUN" ] || BUN="$(command -v bun 2>/dev/null || true)"
[ -n "$BUN" ] || { [ ! -x "$HOME/.bun/bin/bun" ] || BUN="$HOME/.bun/bin/bun"; }
[ -n "$BUN" ] && [ -x "$BUN" ] || _refuse "bun is not installed, and the console runs on it" "$(pkg_hint bun)"

exec "$BUN" "$SERVER" "$@"
