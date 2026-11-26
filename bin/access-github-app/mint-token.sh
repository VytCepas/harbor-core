#!/bin/sh
# mint-token.sh (harbor#1018) — a 1-hour installation token for the harbor-claude GitHub App, on stdout.
# Reuses the cached token while it has 10+ minutes left. The key and the cache stay 0600 in this directory.
#   sh mint-token.sh [<account>]     default account: VytCepas
set -eu
D="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ACCT="${1:-VytCepas}"
case "$ACCT" in *[!A-Za-z0-9-]*|'') echo "mint-token: bad account '$ACCT'" >&2; exit 2 ;; esac
CACHE="$D/token-$ACCT"; umask 077
now="$(date +%s)"
if [ -s "$CACHE" ]; then
  exp="$(sed -n 1p "$CACHE")"
  case "$exp" in ''|*[!0-9]*) ;; *) [ "$exp" -gt $((now + 600)) ] && { sed -n 2p "$CACHE"; exit 0; } ;; esac
fi
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
hdr="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
pay="$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' $((now - 60)) $((now + 540)) "$(cat "$D/app-id")" | b64url)"
sig="$(printf '%s.%s' "$hdr" "$pay" | openssl dgst -sha256 -sign "$D/app.pem" -binary | b64url)"
jwt="$hdr.$pay.$sig"
api() { curl -fsS -H "Authorization: Bearer $jwt" -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }
iid="$(api https://api.github.com/app/installations | jq -r --arg a "$ACCT" '.[] | select(.account.login == $a) | .id' | head -1)"
case "$iid" in ''|*[!0-9]*) echo "mint-token: the App is not installed on $ACCT" >&2; exit 1 ;; esac
resp="$(api -X POST "https://api.github.com/app/installations/$iid/access_tokens")"
tok="$(printf '%s' "$resp" | jq -r '.token // empty')"
[ -n "$tok" ] || { echo "mint-token: GitHub gave no token for installation $iid" >&2; exit 1; }
exp="$(printf '%s' "$resp" | jq -r '.expires_at' | { read -r t; date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$t" +%s 2>/dev/null || date -u -d "$t" +%s; })"
printf '%s\n%s\n' "$exp" "$tok" > "$CACHE"
printf '%s\n' "$tok"
