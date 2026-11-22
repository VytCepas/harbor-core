#!/usr/bin/env sh
# harbor access add|rotate --value-oauth (contracts/secret-intake.md, harbor#1597): the code arrives on loopback, is checked
# against state, is exchanged with the client secret off argv, and the token lands in the store and nowhere else.
# A temp HOME and private layer, the file-backed keychain stub, a fake token endpoint and curl as the browser.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
readv() { sh "$T_ROOT/bin/secret" run "$1" V -- sh -c 'printf %s "$V"' 2>/dev/null; }
freeport() { /usr/bin/python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])' 2>/dev/null || python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
PYT=/usr/bin/python3; [ -x "$PYT" ] || PYT=python3

CS="fake-client-secret-$(printf '%s' 4242)"; CID=example-client-id
CODE="fake-auth-code-$(printf '%s' 777123)"; RT="fake-refresh-token-$(printf '%s' 9988)"
printf '%s' "$CS" | AX add github-oauth-app --kind app --what w --use-when u --reaches r --cannot c --grant g \
  --secret harbor-github-tools-oauthapp --vendor-name 'EXAMPLECO API GitHub' --value-stdin >/dev/null 2>&1
t_eq "control: the client secret is stored" "$CS" "$(readv harbor-github-tools-oauthapp)"

# The fake token endpoint: records the request (headers and form) and answers per $T_TMP/mode.
TP="$(freeport)"
"$PYT" -I - "$TP" "$T_TMP" > /dev/null 2>&1 <<'PYEOF' &
import http.server, json, sys, urllib.parse
port, d = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode()
        with open(d + '/seen', 'w') as f:
            f.write('auth=' + (self.headers.get('Authorization') or '') + '\n')
            for k, v in urllib.parse.parse_qsl(body): f.write(k + '=' + v + '\n')
        mode = open(d + '/mode').read().strip()
        out = {'ok': {'refresh_token': open(d + '/rt').read(), 'access_token': 'AT-unused'},
               'nofield': {'access_token': 'AT-should-never-print'}}[mode]
        b = json.dumps(out).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PYEOF
TPID=$!
trap 'kill $TPID 2>/dev/null' EXIT
printf '%s' "$RT" > "$T_TMP/rt"
sleep 1

# One OAuth run: <verb> <id> <browser: ok|forged|denied> [bin]; flags after the id come from $A (add's entry fields) and $XF.
# The browser first asks /done (a stray request), then, for forged, sends a redirect with another state and another
# code, then the real one. Leaves out/err/rc/early/forged/redir/done in $T_TMP.
RUN() {
  _verb="$1"; _id="$2"; _br="$3"; _bin="${4:-$T_ROOT/bin}"
  LP="$(freeport)"; rm -f "$T_TMP/seen" "$T_TMP/early" "$T_TMP/forged"
  _vn=''; [ "$_verb" != add ] || _vn="$VN"
  # shellcheck disable=SC2086 # A and XF are flag lists
  sh "$_bin/access.sh" "$_verb" "$_id" $A ${_vn:+--vendor-name "$_vn"} --value-oauth --oauth-authorize "https://vendor.example/authorize?client_id=$CID&scope=read" \
    --oauth-token "http://127.0.0.1:$TP/token" --oauth-client-id "$CID" --oauth-client-ref harbor-github-tools-oauthapp \
    --oauth-redirect "http://127.0.0.1:$LP/callback" --oauth-timeout 90 $XF \
    > "$T_TMP/out" 2> "$T_TMP/err" < /dev/null &
  _p=$!
  _i=0; while ! grep -q '^authorize: ' "$T_TMP/out" 2>/dev/null && [ "$_i" -lt 240 ]; do sleep 0.25; _i=$((_i + 1)); done
  _st="$(sed -n 's/^authorize: .*[?&]state=\([0-9a-f]*\).*/\1/p' "$T_TMP/out")"
  curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$LP/done" > "$T_TMP/early" 2>/dev/null || :
  [ "$_br" != forged ] || curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$LP/callback?code=FORGED-CODE&state=0000" > "$T_TMP/forged" 2>/dev/null || :
  case "$_br" in ok|forged) _q="code=$CODE&state=$_st" ;; denied) _q="error=access_denied&error_description=user+said+no&state=$_st" ;; esac
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$LP/callback?$_q" > "$T_TMP/redir" 2>/dev/null || :
  curl -s "http://127.0.0.1:$LP/done" > "$T_TMP/done" 2>/dev/null || :
  _rc=0; wait "$_p" || _rc=$?; printf '%s' "$_rc" > "$T_TMP/rc"
}
noleak() { cat "$T_TMP/out" "$T_TMP/err" | grep -cE "$CODE|$RT|$CS|AT-should-never-print|FORGED-CODE"; }
VN='EXAMPLECO API GitHub'

t_section "add --value-oauth, basic auth: the refresh token is stored, nothing secret is shown"
echo ok > "$T_TMP/mode"
RUNA() { # <id> <ref> <auth> <browser> [extra --oauth flags] [bin]
  _ri="$1"; _rr="$2"; _ra="$3"; _rb="$4"; _rx="${5:-}"; _rbin="${6:-$T_ROOT/bin}"
  A="--kind token --what w --use-when u --reaches r --cannot c --grant g --secret $_rr"; XF="--oauth-auth $_ra $_rx"
  RUN add "$_ri" "$_rb" "$_rbin"
}
RUNA github-oauth-one harbor-github-tools-oauthone basic ok
t_eq "it passes" 0 "$(cat "$T_TMP/rc")"
t_eq "the store holds the refresh token" "$RT" "$(readv harbor-github-tools-oauthone)"
t_eq "a /done before any redirect is a stray request: 404, and the run goes on" 404 "$(cat "$T_TMP/early")"
t_eq "the redirect answers 303 to /done, so the page the agent sees carries no code" "303 http://127.0.0.1:$LP/done" "$(cat "$T_TMP/redir")"
t_has "/done says the consent arrived" "$(cat "$T_TMP/done")" "Consent received"
t_eq "neither code, token nor client secret is on stdout or stderr" 0 "$(noleak)"
t_has "the authorize URL carries the vendor's params" "$(cat "$T_TMP/out")" "client_id=$CID&scope=read&response_type=code"
t_eq "the token endpoint got the code" "code=$CODE" "$(grep '^code=' "$T_TMP/seen")"
t_eq "and grant_type" "grant_type=authorization_code" "$(grep '^grant_type=' "$T_TMP/seen")"
t_eq "and the redirect_uri" "redirect_uri=http://127.0.0.1:$LP/callback" "$(grep '^redirect_uri=' "$T_TMP/seen")"
t_eq "and basic auth of id:secret" "auth=Basic $(printf '%s:%s' "$CID" "$CS" | base64)" "$(grep '^auth=' "$T_TMP/seen")"
t_eq "and no client_secret in the body" 0 "$(grep -c '^client_secret=' "$T_TMP/seen")"

t_section "--oauth-auth body: the secret goes in the form"
RUNA github-oauth-two harbor-github-tools-oauthtwo body ok
t_eq "it passes" 0 "$(cat "$T_TMP/rc")"
t_eq "client_secret in the body" "client_secret=$CS" "$(grep '^client_secret=' "$T_TMP/seen")"
t_eq "no Authorization header" "auth=" "$(grep '^auth=' "$T_TMP/seen")"

t_section "a redirect with another state is ignored; the real consent still lands"
RUNA github-oauth-three harbor-github-tools-oauththree basic forged
t_eq "the forged redirect is answered 400" 400 "$(cat "$T_TMP/forged")"
t_eq "the run still passes on the real one" 0 "$(cat "$T_TMP/rc")"
t_eq "only the real code reached the token endpoint" "code=$CODE" "$(grep '^code=' "$T_TMP/seen")"
t_eq "nothing of the forged code is shown" 0 "$(noleak)"

t_section "the vendor's refusal is reported, not swallowed, and /done says so"
RUNA github-oauth-four harbor-github-tools-oauthfour basic denied
t_eq "exit 1" 1 "$(cat "$T_TMP/rc")"
t_has "with the vendor's error" "$(cat "$T_TMP/err")" "access_denied"
t_has "/done does not claim success" "$(cat "$T_TMP/done")" "did not complete"

t_section "a response without the field names its keys, never its values"
echo nofield > "$T_TMP/mode"
RUNA github-oauth-five harbor-github-tools-oauthfive basic ok
t_eq "exit 1" 1 "$(cat "$T_TMP/rc")"
t_has "the keys are named" "$(cat "$T_TMP/err")" "response keys: access_token"
t_eq "the token value is not" 0 "$(noleak)"
t_section "--oauth-field picks the field"
RUNA github-oauth-six harbor-github-tools-oauthsix basic ok "--oauth-field access_token"
t_eq "it passes" 0 "$(cat "$T_TMP/rc")"
t_eq "the access_token is what is stored" AT-should-never-print "$(readv harbor-github-tools-oauthsix)"
echo ok > "$T_TMP/mode"

t_section "rotate --value-oauth: a new token, kept because the entry's check passes on it"
printf 'fake-refresh-token-0000' | AX add github-oauth-rot --kind token --what w --use-when u --reaches r --cannot c --grant g \
  --secret harbor-github-tools-oauthrot --vendor-name "$VN" --value-stdin \
  --check "sh $T_ROOT/bin/secret run harbor-github-tools-oauthrot V -- sh -c 'printf \"len=%s\" \"\${#V}\"'" --expect '`len=23`' >/dev/null 2>&1
t_eq "control: the old value is stored" fake-refresh-token-0000 "$(readv harbor-github-tools-oauthrot)"
A=''; XF='--oauth-auth basic'; RUN rotate github-oauth-rot ok
t_eq "it passes" 0 "$(cat "$T_TMP/rc")"
t_eq "the store holds the new token" "$RT" "$(readv harbor-github-tools-oauthrot)"
t_eq "nothing secret is shown" 0 "$(noleak)"

t_section "usage"
U() { AX add github-oauth-u --kind token --what w --use-when u --reaches r --cannot c --grant g --secret harbor-github-tools-oauthu \
  --vendor-name "$VN" --value-oauth "$@" >/dev/null 2>&1 < /dev/null; echo $?; }
OK="--oauth-authorize https://v.example/a --oauth-token https://v.example/t --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp"
t_eq "no --oauth-token: exit 2" 2 "$(U --oauth-authorize https://v.example/a --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp)"
t_eq "an http authorize URL: exit 2" 2 "$(U --oauth-authorize http://v.example/a --oauth-token https://v.example/t --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp)"
# shellcheck disable=SC2086 # OK is the flag list
t_eq "--value-oauth with --value-stdin: exit 2" 2 "$(U $OK --value-stdin)"
# shellcheck disable=SC2086
t_eq "--value-oauth with --value-clipboard: exit 2" 2 "$(U $OK --value-clipboard)"
# shellcheck disable=SC2086
t_eq "a redirect that is not loopback: exit 2" 2 "$(U $OK --oauth-redirect https://example.com/cb)"
t_eq "a token URL with userinfo (http://localhost:@host) is not loopback: exit 2" 2 "$(U --oauth-authorize https://v.example/a --oauth-token 'http://localhost:@evil.example/t' --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp)"
t_eq "an https token URL with userinfo: exit 2" 2 "$(U --oauth-authorize https://v.example/a --oauth-token 'https://u:p@v.example/t' --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp)"
t_eq "a line break in the token URL: exit 2" 2 "$(U --oauth-authorize https://v.example/a --oauth-token "$(printf 'https://v.example/t\nproxy = x')" --oauth-client-id x --oauth-client-ref harbor-github-tools-oauthapp)"
t_eq "an unregistered client ref: exit 1" 1 "$(U --oauth-authorize https://v.example/a --oauth-token https://v.example/t --oauth-client-id x --oauth-client-ref harbor-github-tools-nosuch)"

t_section "mutant: with the state check removed, a forged redirect is exchanged"
M="$T_TMP/m"; mkdir -p "$M/bin"; cp -R "$T_ROOT/bin/." "$M/bin/" 2>/dev/null
for _d in "$T_ROOT"/*; do [ "${_d##*/}" = bin ] || ln -s "$_d" "$M/${_d##*/}"; done
sed "s/^        if q.get('state', \[''\])\[0\] != state: return /        if False: return /" "$T_ROOT/bin/access-oauth.sh" > "$M/bin/access-oauth.sh"
t_eq "the mutant differs" yes "$(cmp -s "$T_ROOT/bin/access-oauth.sh" "$M/bin/access-oauth.sh" || echo yes)"
RUNA github-oauth-seven harbor-github-tools-oauthseven basic forged "" "$M/bin"
t_eq "the mutant exchanges the forged code" "code=FORGED-CODE" "$(grep '^code=' "$T_TMP/seen")"
t_done
