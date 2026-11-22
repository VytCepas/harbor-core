#!/usr/bin/env sh
# access-desktop.sh — harbor desktop: general controllers for Mac apps, in the background (harbor/D-95, harbor#1440).
#
#   sh bin/access-desktop.sh <verb> ['<json args>'] [--confirm]
#
#   reads     doctor · apps · windows · tree · shot · shortcuts      (shortcuts with no name lists them)
#   inputs    action · set-value · menu · type · key                 (a live-change label, Enter, asks: --confirm)
#   always    script · shortcuts {"name":…}                          (every run is the operator's: --confirm)
#   setup     ensure · request-access · reload · stop
#
#   e.g.  sh bin/access-desktop.sh tree '{"bundle":"com.apple.TextEdit"}'
#
# The helper (HarborDesktop.app, built by access-desktop-build.sh) holds the macOS grants and enforces the policy: the
# app allow-list (contracts/desktop-agent-bundles.txt, then the private layer's desktop-bundles.txt), a hard deny list
# in code, harbor chrome's host list for browsers, and contracts/live-change-words.txt. This script only launches it
# through LaunchServices (so macOS attributes the grants to the app, not the terminal) and relays one JSON line.
# --confirm is the operator's: the MCP server passes it only from tools behind a permissions.ask rule.
set -eu
LOG_FD=2
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
_app_default="$HOME/.local/lib/harbor/HarborDesktop.app"
app="${HARBOR_ACCESS_DESKTOP_APP:-$_app_default}"
dir="${HARBOR_ACCESS_DESKTOP_STATE:-$HOME/.local/state/harbor/desktop}"
sock="$dir/helper.sock"
priv=$(sh "$here/scope-roots.sh" --private 2>/dev/null || true)
. "$here/library-log.sh"
log_init access-desktop

ask() {  # $1 = one JSON line; prints the helper's one-line reply
  printf '%s\n' "$1" | nc -U -w 30 "$sock"
}
alive() { ask '{"verb":"doctor"}' 2>/dev/null | grep -q '"ok":true'; }
ensure() {
  alive && return 0
  [ -d "$app" ] || { log_fail "helper not built: $app"; log_fix "sh bin/access-desktop-build.sh"; log_end || :; exit 3; }
  mkdir -p "$dir"; chmod 700 "$dir"
  bundles="$root/contracts/desktop-agent-bundles.txt"
  hosts="$root/contracts/browser-agent-hosts.txt"
  [ -n "$priv" ] && bundles="$bundles:$priv/desktop-bundles.txt" && hosts="$hosts:$priv/browser-hosts.txt"
  # -g: never brought forward; -j: launched hidden; LaunchServices makes the app its own responsible process.
  open -g -j -a "$app" --args serve "$sock" "bundles=$bundles" "words=$root/contracts/live-change-words.txt" \
    "hosts=$hosts" "idle=${HARBOR_ACCESS_DESKTOP_IDLE:-900}" ||
    { log_fail "LaunchServices could not open $app"; log_fix "sh bin/access-desktop-build.sh"; log_end || :; exit 3; }
  i=0; while [ $i -lt 50 ]; do alive && return 0; i=$((i + 1)); sleep 0.1; done
  log_fail "helper did not answer on $sock within 5 s"; log_nofix "harbor#1440"; log_end || :; exit 3
}

verb="${1:-}"
case "$verb" in -h|--help) sed -n 2,19p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; '') sed -n 4,12p "$0" >&2; exit 64 ;; esac
shift
args='{}'; confirm=false
for a in "$@"; do case "$a" in --confirm) confirm=true ;; *) args="$a" ;; esac; done
case "$verb" in
  ensure) ensure; ask '{"verb":"doctor"}'; exit 0 ;;
  stop)
    if pkill -f "HarborDesktop.app/Contents/MacOS/HarborDesktop serve $sock"; then log_ok stopped; else log_ok "not running"; fi
    rm -f "$sock"; log_end; exit $? ;;
  doctor|request-access|reload|apps|windows|tree|shot|action|set-value|menu|type|key|script|shortcuts) ;;
  *) log_fail "unknown verb '$verb'"; log_fix "sh bin/access-desktop.sh --help"; log_end || :; exit 64 ;;
esac
ensure
# The verb and the confirm flag are set here, after the caller's object, so a caller cannot smuggle either.
body=$(printf '%s' "$args" | /usr/bin/python3 -I -c '
import json, sys
a = json.loads(sys.stdin.read() or "{}")
if not isinstance(a, dict): sys.exit("args must be a JSON object")
a.pop("confirmed", None); a["verb"] = sys.argv[1]
if sys.argv[2] == "true": a["confirmed"] = True
print(json.dumps(a))' "$verb" "$confirm")
reply=$(ask "$body")
printf '%s\n' "$reply"
printf '%s' "$reply" | grep -q '"ok":true'
