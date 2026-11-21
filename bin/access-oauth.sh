#!/usr/bin/env sh
# access-oauth.sh (harbor#1597, contracts/secret-intake.md) - `harbor access add|rotate … --value-oauth`: a token from an
# OAuth authorization-code grant, stored without the code or the token ever reaching the agent.
#
#   harbor access add|rotate <id> <access args…> --value-oauth
#       --oauth-authorize URL      the vendor's authorize URL with its own params (client_id, scope, duration, …);
#                                  response_type=code, redirect_uri and state are added here
#       --oauth-token URL          the token endpoint (https; http only on a loopback host)
#       --oauth-client-id ID       the app's client id (public)
#       --oauth-client-ref REF     the registered secret ref holding the app's client secret
#       [--oauth-redirect URL]     the redirect registered on the app: http://localhost:<port>/<path> or
#                                  http://127.0.0.1:<port>/<path> (default http://localhost:8765/callback)
#       [--oauth-auth basic|body]  client authentication at the token endpoint (default basic)
#       [--oauth-field F]          the token-response field to store (default refresh_token)
#       [--oauth-timeout S]        how long to wait for the consent (default 600)
#
# It prints the authorize URL (no secret in it), then waits. The agent opens that URL in the agent Chrome and clicks
# the vendor's consent. A one-shot listener on 127.0.0.1 takes the redirect, checks `state`, keeps the code in a 0600
# file and answers 303 to /done at once, so no page or URL the agent reads carries the code. curl exchanges it, the
# client secret and the code passed in a config on stdin (never argv, never a file the agent can name), and the
# chosen field is piped into `harbor access <verb> <id> … --value-stdin`, which checks and stores it.
# Exit: 0 stored; 1 the consent, exchange or store failed; 2 usage. Nothing of the code or token is printed on any path.
set -eu
LC_ALL=C; export LC_ALL

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init access-oauth
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
PY=/usr/bin/python3; [ -x "$PY" ] || PY=python3

# --exchange: internal, re-entered under `secret run <client-ref> HARBOR_ACCESS_OAUTH_CS`, so the client secret reaches this
# process by environment only. printf is a builtin: the secret is never in an exec'd argv.
if [ "${1:-}" = --exchange ]; then
  _esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  {
    printf 'url = "%s"\n' "$(_esc "$OA_TOKEN_URL")"
    printf 'user-agent = "harbor-access/1 (oauth intake)"\n'
    printf 'header = "Accept: application/json"\n'
    if [ "$OA_AUTH" = basic ]; then
      printf 'user = "%s:%s"\n' "$(_esc "$OA_CID")" "$(_esc "$HARBOR_ACCESS_OAUTH_CS")"
    else
      printf 'data-urlencode = "client_id=%s"\n' "$(_esc "$OA_CID")"
      printf 'data-urlencode = "client_secret=%s"\n' "$(_esc "$HARBOR_ACCESS_OAUTH_CS")"
    fi
    printf 'data-urlencode = "grant_type=authorization_code"\n'
    printf 'data-urlencode = "code@%s"\n' "$(_esc "$OA_CODEFILE")"
    printf 'data-urlencode = "redirect_uri=%s"\n' "$(_esc "$OA_REDIRECT")"
  } | curl -sS --max-time 30 -o "$OA_RESP" -w '%{http_code}' -K - 2>/dev/null
  exit 0
fi

case "${1:-}" in -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
VERB="${1:-}"; [ $# -eq 0 ] || shift
case "$VERB" in add|rotate) ;; *) fail "--value-oauth goes with add or rotate, not '$VERB'" "harbor access add <id> … --value-oauth --oauth-authorize URL …" 2 ;; esac
AUTHZ=''; TOKEN=''; CID=''; CREF=''; REDIRECT='http://localhost:8765/callback'; AUTH=basic; FIELD=refresh_token; TMO=600
_n=$#
while [ "$_n" -gt 0 ]; do
  _a="$1"; shift; _n=$((_n - 1))
  case "$_a" in
    --oauth-authorize|--oauth-token|--oauth-client-id|--oauth-client-ref|--oauth-redirect|--oauth-auth|--oauth-field|--oauth-timeout)
      [ "$_n" -gt 0 ] || fail "$_a needs a value" "harbor access --help" 2
      _v="$1"; shift; _n=$((_n - 1))
      case "$_a" in
        --oauth-authorize) AUTHZ="$_v" ;; --oauth-token) TOKEN="$_v" ;; --oauth-client-id) CID="$_v" ;;
        --oauth-client-ref) CREF="$_v" ;; --oauth-redirect) REDIRECT="$_v" ;; --oauth-auth) AUTH="$_v" ;;
        --oauth-field) FIELD="$_v" ;; --oauth-timeout) TMO="$_v" ;;
      esac ;;
    --value-oauth) ;;
    --value-stdin|--value-clipboard) fail "--value-oauth and $_a both name the value's source; give one" "harbor access $VERB … --value-oauth" 2 ;;
    *) set -- "$@" "$_a" ;;
  esac
done
for _p in "--oauth-authorize:$AUTHZ" "--oauth-token:$TOKEN" "--oauth-client-id:$CID" "--oauth-client-ref:$CREF"; do
  [ -n "${_p#*:}" ] || fail "--value-oauth needs ${_p%%:*}" "harbor access --help" 2
done
case "$AUTHZ" in https://*) ;; *) fail "--oauth-authorize must be https: $AUTHZ" "the vendor's documented authorize URL" 2 ;; esac
case "$TOKEN" in https://*|http://127.0.0.1:*|http://localhost:*) ;; *) fail "--oauth-token must be https (http only on loopback): $TOKEN" "the vendor's documented token URL" 2 ;; esac
case "$AUTH" in basic|body) ;; *) fail "--oauth-auth is basic or body, not '$AUTH'" "harbor access --help" 2 ;; esac
case "$TMO" in ''|*[!0-9]*) fail "--oauth-timeout takes seconds: $TMO" "--oauth-timeout 600" 2 ;; esac
case "$FIELD" in ''|*[!A-Za-z0-9_]*) fail "--oauth-field is a JSON key: $FIELD" "--oauth-field refresh_token" 2 ;; esac
case "$CID" in *[!A-Za-z0-9._~-]*) fail "--oauth-client-id has a character a client id never has" "the app page's client id" 2 ;; esac
_rest="${REDIRECT#http://localhost:}"; [ "$_rest" != "$REDIRECT" ] || _rest="${REDIRECT#http://127.0.0.1:}"
[ "$_rest" != "$REDIRECT" ] || fail "--oauth-redirect must be http://localhost:<port>/<path> or http://127.0.0.1:<port>/<path>" "--oauth-redirect http://localhost:8765/callback" 2
PORT="${_rest%%/*}"; RPATH="/${_rest#*/}"; [ "$RPATH" != "/$_rest" ] || RPATH=/
case "$PORT" in ''|*[!0-9]*) fail "--oauth-redirect has no port: $REDIRECT" "--oauth-redirect http://localhost:8765/callback" 2 ;; esac
case "$RPATH" in /done|*'?'*|*'#'*) fail "--oauth-redirect path must not be /done or carry a query: $RPATH" "--oauth-redirect http://localhost:8765/callback" 2 ;; esac
command -v curl >/dev/null 2>&1 || fail "curl is not installed" "$(pkg_hint curl)" 1
command -v jq >/dev/null 2>&1 || fail "jq is not installed" "$(pkg_hint jq)" 1
sh "$SRC/access.sh" has "$CREF" >/dev/null 2>&1 \
  || fail "--oauth-client-ref '$CREF' is not a registered secret ref" "harbor access add <app-id> --kind app … --secret $CREF --value-clipboard" 1

T="$(mktemp -d "${TMPDIR:-/tmp}/harbor-oauth.XXXXXX")"; chmod 700 "$T"
LPID=''
cleanup() { [ -z "$LPID" ] || kill "$LPID" 2>/dev/null || :; rm -rf "$T"; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
STATE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

# The listener: one consent, then /done, then it exits. The code goes to a 0600 file, never to stdout.
"$PY" -I - "$PORT" "$RPATH" "$STATE" "$T/code" "$TMO" > "$T/listener.log" 2>&1 <<'PYEOF' &
import http.server, os, sys, time, urllib.parse
port, rpath, state, out, tmo = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
def put(path, text):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as f: f.write(text)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body=b'', loc=None):
        self.send_response(code)
        self.send_header('Cache-Control', 'no-store'); self.send_header('Referrer-Policy', 'no-referrer')
        if loc: self.send_header('Location', loc)
        self.send_header('Content-Type', 'text/html; charset=utf-8'); self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        if u.path == '/done':
            self.reply(200, b'<!doctype html><title>harbor access</title><p>Consent received. harbor is storing the token; close this tab.</p>')
            self.server.done = True; return
        if u.path != rpath or self.server.got: return self.reply(404)
        q = urllib.parse.parse_qs(u.query)
        if q.get('state', [''])[0] != state: put(out + '.error', 'the redirect carried the wrong state')
        elif q.get('code', [''])[0]: put(out, q['code'][0])
        else: put(out + '.error', ('vendor said: ' + q.get('error', ['no code'])[0] + ' ' + q.get('error_description', [''])[0])[:200])
        self.server.got = True
        self.reply(303, loc='/done')
srv = http.server.HTTPServer(('127.0.0.1', port), H)
srv.got = srv.done = False; srv.timeout = 1
end = time.time() + tmo; grace = None
while time.time() < end and not srv.done:
    srv.handle_request()
    if srv.got and grace is None: grace = time.time() + 15
    if grace and time.time() > grace: break
PYEOF
LPID=$!
sleep 1
kill -0 "$LPID" 2>/dev/null || fail "the loopback listener did not start on 127.0.0.1:$PORT ($(tr '\n' ' ' < "$T/listener.log" | cut -c1-160))" "free the port, or register another redirect and pass --oauth-redirect" 1

_enc() { printf '%s' "$1" | jq -sRr @uri; }
case "$AUTHZ" in *'?'*) _sep='&' ;; *) _sep='?' ;; esac
URL="$AUTHZ${_sep}response_type=code&redirect_uri=$(_enc "$REDIRECT")&state=$STATE"
log_note "open this in the agent Chrome and consent (it carries no secret): $URL"
printf 'authorize: %s\n' "$URL"

_w=0
while [ ! -s "$T/code" ] && [ ! -e "$T/code.error" ] && kill -0 "$LPID" 2>/dev/null && [ "$_w" -lt "$TMO" ]; do
  sleep 1; _w=$((_w + 1))
done
[ ! -e "$T/code.error" ] || fail "the consent failed: $(cut -c1-200 "$T/code.error")" "open the authorize URL again in the agent Chrome; check the app's redirect is exactly $REDIRECT" 1
[ -s "$T/code" ] || fail "no consent arrived within ${TMO}s" "rerun, then open the printed URL in the agent Chrome and approve" 1
log_ok "consent received; exchanging the code"

_http="$(OA_TOKEN_URL="$TOKEN" OA_AUTH="$AUTH" OA_CID="$CID" OA_CODEFILE="$T/code" OA_REDIRECT="$REDIRECT" OA_RESP="$T/resp" \
  sh "$SRC/secret" run "$CREF" HARBOR_ACCESS_OAUTH_CS -- sh "$0" --exchange)" || _http=000
rm -f "$T/code"
if [ "$_http" != 200 ] || ! jq -e --arg f "$FIELD" '(.[$f] | type) == "string" and (.[$f] | length) > 0' "$T/resp" >/dev/null 2>&1; then
  _keys="$(jq -r 'if type == "object" then (keys | join(",")) else type end' "$T/resp" 2>/dev/null || printf 'not JSON')"
  _err="$(jq -r 'if type == "object" then ((.error // "") | tostring) else "" end' "$T/resp" 2>/dev/null | cut -c1-80 || :)"
  fail "the token exchange returned HTTP $_http without '$FIELD' (response keys: ${_keys:-none}${_err:+; error: $_err})" "check --oauth-token, --oauth-auth and that the app's client secret in $CREF is current" 1
fi
log_ok "the token endpoint returned '$FIELD'; storing it"
_rc=0
jq -j --arg f "$FIELD" '.[$f]' "$T/resp" | sh "$SRC/access.sh" "$VERB" "$@" --value-stdin || _rc=$?
log_end || :
exit "$_rc"
