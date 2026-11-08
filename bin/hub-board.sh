#!/usr/bin/env sh
# hub-board.sh (harbor#1278) — the one GitHub client for the hub board. Format: contracts/hub.md.
#   sh hub-board.sh call <out-dir> <GET|POST|PATCH> <path> [body-file]
# Writes <out-dir>/status, date, expires, limited and body: the HTTP status, the response's own Date header, the token's
# expiry header, 1 when GitHub rate-limited the call, and the response. <path> starts with /.
# Exit 0 a response came back, whatever its status; 3 none did; 4 no usable token; 2 usage.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-hub.sh"
. "$HERE/library-log.sh"
LOG_FD=2
log_init hub-board

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "${1:-}" in --help|-h) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
# --child is this script re-entered by `secret run`, which holds the credential in the environment for this one process.
CHILD=0
if [ "${1:-}" = --child ]; then CHILD=1; shift; fi

API=https://api.github.com
PROTO='=https'
# Honoured only with no member marker beside this file, and only for loopback, so it can't redirect a real member's approvals.
if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_HUB_API_BASE:-}" ]; then
  case "${HARBOR_HUB_API_BASE#http://127.0.0.1:}" in
    "$HARBOR_HUB_API_BASE"|''|*[!0-9]*) ;;
    *) API="$HARBOR_HUB_API_BASE"; PROTO='=http' ;;
  esac
fi

# One word for the session note and the sender: ok, unreachable, token-expired, rate-limited. A token dying is told to the
# board once, on the change, so it can be told apart from a member going silent (R20).
board_state() {
  _bs="$(hub_state_dir)"
  mkdir -p "$_bs" 2>/dev/null || return 0
  _was="$(cat "$_bs/board-state" 2>/dev/null)" || _was=''
  printf '%s\n' "$1" > "$_bs/board-state" 2>/dev/null || :
  if [ "$1" = token-expired ] && [ "$_was" != token-expired ]; then
    sh "$HERE/hub-events.sh" record token days_left=0 outcome=expired-token >/dev/null 2>&1 || :
  fi
}

[ "${1:-}" = call ] || usage
[ $# -ge 4 ] && [ $# -le 5 ] || usage
OUT="$2"; METHOD="$3"; URLPATH="$4"; BODY="${5:-}"
[ -d "$OUT" ] || usage
case "$METHOD" in GET|POST|PATCH) ;; *) usage ;; esac
# The path reaches a curl config line, so nothing that could close the quote or add a line may pass.
case "$URLPATH" in /*) ;; *) usage ;; esac
case "$URLPATH" in *[!A-Za-z0-9/_.?=\&-]*|*..*) usage ;; esac
[ -z "$BODY" ] || [ -r "$BODY" ] || usage

no_token() { log_fail "no usable board token"; log_nofix "contracts/hub.md: IT issues it with the member"; log_end || :; exit 4; }
# W7: the one token read. The request runs as the child of `secret run`, because bin/secret has no verb that prints a value:
# printing one here would rebuild the `get` it refuses. #618 decides whether WSL2 has a store behind it.
if [ "$CHILD" = 0 ]; then
  unset HUB_BOARD_CREDENTIAL
  _sb="$HERE/secret"
  if [ ! -e "$HERE/harbor-member-mode" ] && [ -n "${HARBOR_ACCESS_SECRET_BIN:-}" ]; then _sb="$HARBOR_ACCESS_SECRET_BIN"; fi
  [ -x "$_sb" ] || no_token
  RC=0
  "$_sb" run hub-token HUB_BOARD_CREDENTIAL -- sh "$0" --child call "$OUT" "$METHOD" "$URLPATH" "$BODY" 2>/dev/null || RC=$?
  case "$RC" in 0|3|4) exit "$RC" ;; *) no_token ;; esac
fi
case "${HUB_BOARD_CREDENTIAL:-}" in
  ''|*[!A-Za-z0-9_]*) no_token ;;
esac

HDR="$OUT/.headers"
: > "$OUT/body"; : > "$OUT/date"; : > "$OUT/expires"; printf '0\n' > "$OUT/limited"; printf '000\n' > "$OUT/status"
# A planted CA with a planted proxy could forge an approval, so only the system store decides. -q skips any ~/.curlrc. Beside the marker
# hub_net_env already left only what the managed settings name, so a corporate CA there stands (contracts/hub.md, harbor#1278).
unset CURL_HOME
[ -e "$HERE/harbor-member-mode" ] || unset CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR

set --
[ -z "$BODY" ] || set -- --data-binary "@$BODY" --header 'Content-Type: application/json'
# The token reaches curl on stdin only. Short timeouts: this runs inside a hook. No -L: a redirect is a failure.
RC=0
STATUS="$(printf 'url = "%s%s"\nheader = "Authorization: Bearer %s"\n' "$API" "$URLPATH" "$HUB_BOARD_CREDENTIAL" \
  | curl -q --silent --proto "$PROTO" --connect-timeout 3 --max-time 6 --request "$METHOD" \
      --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
      --user-agent harbor-hub --dump-header "$HDR" --output "$OUT/body" --write-out '%{http_code}' \
      "$@" --config -)" || RC=$?
unset HUB_BOARD_CREDENTIAL
if [ "$RC" != 0 ] || [ "$STATUS" = 000 ] || [ -z "$STATUS" ]; then
  board_state unreachable
  exit 3
fi
printf '%s\n' "$STATUS" > "$OUT/status"

# The last header block is GitHub's: a proxy's CONNECT reply comes first.
awk -v out="$OUT" '
  /^HTTP\// { d = ""; e = ""; rem = ""; ra = "" }
  { line = $0; sub(/\r$/, "", line); i = index(line, ":"); if (!i) next
    k = tolower(substr(line, 1, i - 1)); v = substr(line, i + 1); sub(/^[ \t]+/, "", v)
    if (k == "date") d = v
    else if (k == "github-authentication-token-expiration") e = v
    else if (k == "x-ratelimit-remaining") rem = v
    else if (k == "retry-after") ra = v }
  END { print d > (out "/date"); print e > (out "/expires"); print ((rem == "0" || ra != "") ? 1 : 0) > (out "/limited") }' "$HDR"
rm -f "$HDR"

# Only a refusal is a rate limit: a 200 on the last call of the hour also says remaining 0.
LIMITED="$(cat "$OUT/limited")"
case "$STATUS" in
  429) LIMITED=1 ;;
  403) if grep -qi 'rate limit' "$OUT/body"; then LIMITED=1; fi ;;
  *) LIMITED=0 ;;
esac
printf '%s\n' "$LIMITED" > "$OUT/limited"
case "$STATUS" in
  401) board_state token-expired ;;
  5??) board_state unreachable ;;
  *) if [ "$LIMITED" = 1 ]; then board_state rate-limited; else board_state ok; fi ;;
esac
exit 0
