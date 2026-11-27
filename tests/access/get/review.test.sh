#!/usr/bin/env sh
# access get (harbor#1617), the review cases: each confirmed defect from the reviews of #1620, its case, and a
# mutant that brings it back. Setup is shared with get.test.sh through lib.sh.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/lib.sh"
# ── The review of #1620: each confirmed or plausible defect, its case, and a mutant that brings it back ──
EVIL="$W/evil"; mkdir -p "$EVIL"
printf '\n## example-tok-read\n\n    secret: example-tok-read\n' > "$EVIL/register.md"
printf 'evil\texample-tok-read\thttps://evil.example.org/\tbearer\tx/\t-\t-\t-\t-\t-\n' > "$EVIL/get.tsv"
printf "SECRET='zzzz-no-shape'\n" > "$W/egress-empty.sh"

t_section "review 1: no caller variable moves the table, the register or the redactor"
# A subshell each, so no override outlives its case.
_ev() ( export ACCESS_DIR="$EVIL" HARBOR_SCOPE_ROOT="$T_ROOT" HARBOR_SCOPE_PRIVATE="$W" PORT_ROOT="$W" HARBOR_ACCESS_REDACT_EGRESS="$W/egress-empty.sh"; "$@" )
stub; RC=0; _ev sh "$TB/access-get.sh" evil x/y > "$W/o" 2> "$W/e" || RC=$?
t_eq "ACCESS_DIR naming a caller's table: refused" 2 "$RC"
t_has "...as a vendor the canonical table lacks" "$(cat "$W/e")" "is not in the table ($CT/get.tsv)"
t_eq "...and nothing was sent" 0 "$(calls)"
stub; RC=0; _ev sh "$TB/access.sh" get evil x/y > "$W/o" 2> "$W/e" || RC=$?
t_eq "the same through harbor access get" 2 "$RC"; t_eq "...nothing sent" 0 "$(calls)"
stub; RC=0; _ev sh "$TB/access-get.sh" tok user/info/ > "$W/o" 2> "$W/e" || RC=$?
t_eq "a listed vendor still works under those variables" 0 "$RC"
t_has "...against the canonical row's host" "$(cat "$CS/argv.log")" "--url|https://api.example.com/v1/user/info/|"
_shape="gh""p_$(printf 'b%.0s' $(seq 1 30))"
BODY="{\"note\":\"$_shape\"}" _ev run "$TB" tok user/info/
t_hasnt "HARBOR_ACCESS_REDACT_EGRESS cannot switch the token-shape redactor off" "$(cat "$W/o")" "$_shape"
# The mutant: the unset becomes a no-op and the table follows ACCESS_DIR, as it did before the fix.
_m1="$(mutant 'unset ACCESS_DIR HARBOR_SCOPE_ROOT HARBOR_SCOPE_PRIVATE HARBOR_SCOPE_ROOTS_TABLE PORT_ROOT HARBOR_ACCESS_REDACT_EGRESS \' ': \')"
t_has "red acdir: the mutant applied" "$_m1" "/"
_m1b="$W/mut.acdir"; rm -rf "$_m1b"; cp -R "${_m1%/bin}" "$_m1b"
M='  __t="$GET_HOME/.claude/access/get.tsv"' \
R='  __t="${ACCESS_DIR:-$GET_HOME/.claude/access}/get.tsv"' awk '$0 == ENVIRON["M"] { print ENVIRON["R"]; next } { print }' "$_m1/access-get.sh" > "$_m1b/bin/access-get.sh"
t_eq "red acdir: the table line was replaced" 1 "$(grep -c 'ACCESS_DIR:-' "$_m1b/bin/access-get.sh")"
stub; RC=0; _ev sh "$_m1b/bin/access-get.sh" evil x/y > "$W/o" 2> "$W/e" || RC=$?
if grep -qF 'https://evil.example.org/x/y' "$CS/argv.log" 2>/dev/null && grep -qF "$TOK" "$CS/config.1" 2>/dev/null; then t_pass; t_red get.acdir
else t_fail "red acdir: with the overrides honoured the token should reach the caller's host (rc $RC: $(head -c 200 "$W/e"))"; fi
# The real file, no seam rewritten: the account's own home decides, so the caller's table is never read.
stub; RC=0; _ev sh "$BIN/access-get.sh" evil-acdir-probe x/y > "$W/o" 2> "$W/e" || RC=$?
t_eq "the shipped access-get.sh under ACCESS_DIR: refused before any request" 2 "$RC"
t_hasnt "...and it never read the caller's dir" "$(cat "$W/e")" "$EVIL"

t_section "review 2 and 5: curl reads no curlrc, proxy, CA or key-log setting from the caller, on either leg"
_cv() ( export CURL_HOME="$W/ch" HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 \
  CURL_CA_BUNDLE="$W/ca.pem" SSL_CERT_FILE="$W/ca.pem" SSLKEYLOGFILE="$W/keys"; "$@" )
mkdir -p "$W/ch"; printf 'libcurl = "%s/leak.c"\n' "$W/ch" > "$W/ch/.curlrc"
BODY='{"id":"1"}' _cv run "$TB" bear user_account
t_eq "the refresh row ran both legs" 2 "$(calls)"
for _n in 1 2; do
  t_eq "leg $_n: curl's first argument is -q" '-q' "$(sed -n "${_n}p" "$CS/argv.log" | cut -d'|' -f1)"
  t_has "leg $_n: --noproxy '*'" "$(sed -n "${_n}p" "$CS/argv.log")" "|--noproxy|*|"
  t_eq "leg $_n: no proxy, CA, curl-home or key-log variable reaches curl" 0 "$(grep -ciE '^(https?_proxy|all_proxy|curl_home|curl_ca_bundle|ssl_cert_file|sslkeylogfile)=' "$CS/env.$_n")"
  t_hasnt "leg $_n: HOME is not the caller's" "$(grep '^HOME=' "$CS/env.$_n")" "$HOME"
done
_om="$(mutant "$EXCH_LINE" "$(printf '%s' "$EXCH_LINE" | sed 's|env -i PATH="$PATH" HOME=/ LC_ALL=C curl -q -sS --noproxy .\*. |curl -sS |')" access-oauth.sh)"
t_has "red exchange-env: the mutant applied" "$_om" "/"
remut "$_om" access-get.sh "$UNSET_LINE" ': \'   # the unset is a second layer; both go, or the mutant proves nothing
BODY='{"id":"1"}' _cv run "$_om" bear user_account
t_eq "red exchange-env: the old exchange curl inherits CURL_HOME" 1 "$(grep -c '^CURL_HOME=' "$CS/env.1")"; t_red get.exchange-env
_gm="$(mutant "$CURL_LINE" "$(printf '%s' "$CURL_LINE" | sed 's|env -i PATH="$GET_PATH" HOME=/ LC_ALL=C curl -q -sS --noproxy .\*. |curl -q -sS |')")"
t_has "red get-env: the mutant applied" "$_gm" "/"
remut "$_gm" access-get.sh "$UNSET_LINE" ': \'
_cv run "$_gm" tok user/info/
t_eq "red get-env: the old GET curl inherits HTTPS_PROXY" 1 "$(grep -c '^HTTPS_PROXY=' "$CS/env.1")"; t_red get.get-env
# The real curl, once: a curlrc in CURL_HOME with a libcurl line wrote the secrets to a file before the fix.
REAL="$W/realcurl"; mkdir -p "$REAL"; ln -s /usr/bin/curl "$REAL/curl"
RT2="$W/tree-real"; mktree "$RT2" "$REAL:$T_BIN:/usr/bin:/bin"
printf 'loop\texample-loop-refresh\thttps://api.example.com/v5/\tbearer\tme\t-\t-\thttps://localhost/oauth/token\tclient-9\texample-loop-client\n' >> "$CT/get.tsv"
for _r in example-loop-refresh example-loop-client; do printf '\n## %s\n\n    secret: %s\n' "$_r" "$_r" >> "$AD/register.md"; done
printf '%s' "$RT" | "$BIN/secret" put example-loop-refresh >/dev/null 2>&1
printf '%s' "$CSEC" | "$BIN/secret" put example-loop-client >/dev/null 2>&1
rm -f "$W/ch/leak.c"; CURL_HOME="$W/ch" sh "$RT2/bin/access-get.sh" loop me > "$W/o" 2> "$W/e" || :
t_eq "real curl, CURL_HOME with a libcurl line: no file is written" no "$([ -e "$W/ch/leak.c" ] && echo yes || echo no)"
_rq="$W/tree-real-noq"; rm -rf "$_rq"; cp -R "$RT2" "$_rq"
sed 's/ LC_ALL=C curl -q -sS --noproxy/ CURL_HOME="$CURL_HOME_X" LC_ALL=C curl -sS --noproxy/' "$RT2/bin/access-oauth.sh" > "$_rq/bin/access-oauth.sh"
rm -f "$W/ch/leak.c"; CURL_HOME_X="$W/ch" sh "$_rq/bin/access-get.sh" loop me > "$W/o" 2> "$W/e" || :
t_eq "red curlrc: without -q, that line writes the client secret to the caller's file" 1 "$(grep -cF "$CSEC" "$W/ch/leak.c" 2>/dev/null | sed 's/^[1-9][0-9]*$/1/')"; t_red get.curlrc

t_section "review 3: a '.' segment is refused, and the path goes on the wire as checked"
refused "user/./token/rotate (past the user/token* glob)" "a '.' segment" tok user/./token/rotate
refused "a leading ./" "a '.' segment" tok ./user/info/
refused "a trailing /." "a '.' segment" tok user/info/.
run "$TB" tok user/info/
t_has "curl gets --path-as-is" "$(cat "$CS/argv.log")" "|--path-as-is|"
red dot-segment "  .|./*|*/.|*/./*) refuse \"a '.' segment in the path\" ;;" '' "a '.' segment" tok user/./token/rotate
t_has "red dot-segment: without it the denied path is requested" "$(cat "$CS/argv.log")" "user/./token/rotate"

t_section "review 4: a ref is named once in the whole table, whichever column names it"
cp "$CT/get.tsv" "$W/good2.tsv"
printf "\n## other-rt\n\n    secret: other-rt\n" >> "$AD/register.md"; printf '%s' "RT2-VALUE" | "$BIN/secret" put other-rt >/dev/null 2>&1
printf 'other\tother-rt\thttps://api.other.example.net/\tbearer\tx/\t-\t-\thttps://auth.other.example.net/t\tcid\texample-tok-read\n' >> "$CT/get.tsv"
refused "a row naming another vendor's token as its client secret" "is named 2 times" other x/y
refused "...and the vendor whose token it is" "is named 2 times" tok user/info/
red cref-unique 'for _r in "$REF" "$CREF"; do' 'for _r in "$REF"; do' "is named 2 times" other x/y
t_has "red cref-unique: without it tok's token goes to the other row's token host" "$(cat "$CS/config.1" 2>/dev/null)" "cid:$TOK"
cp "$W/good2.tsv" "$CT/get.tsv"

t_section "review low: a caller's HARBOR_ACCESS_GET_TOKEN is never used; the token always comes through secret run"
: > "$KC_STUB/argv.log"
( export HARBOR_ACCESS_GET_TOKEN=CALLERVALUE; run "$TB" tok user/info/; echo "$RC" > "$W/rc" )
t_eq "exit 0" 0 "$(cat "$W/rc")"
t_has "the stored token was sent" "$(cat "$CS/config.1")" "Access-Token: $TOK"
t_hasnt "...not the caller's value" "$(cat "$CS/config.1")" "CALLERVALUE"
t_has "...read from the store" "$(cat "$KC_STUB/argv.log")" "find-generic-password"

t_section "review 6: hyphenated and bare secret keys, name/value pairs and JWT-shaped values are withheld"
_jwt="eyJ$(printf 'h%.0s' $(seq 1 12)).eyJ$(printf 'p%.0s' $(seq 1 12)).$(printf 's%.0s' $(seq 1 12))"
BODY="{\"x-api-key\":\"V1\",\"Access-Key\":\"V2\",\"key\":\"V3\",\"pwd\":\"V4\",\"pass\":\"V5\",\"note\":\"$_jwt\",\"fields\":[{\"name\":\"access_token\",\"value\":\"V6\"},{\"key\":\"client-secret\",\"value\":\"V7\"},{\"name\":\"campaign\",\"value\":\"KEPT\"}],\"passenger\":\"KEPT2\",\"keyword\":\"KEPT3\"}" run "$TB" tok user/info/
for _v in V1 V2 V3 V4 V5 V6 V7 "$_jwt"; do t_hasnt "withheld: $_v" "$(cat "$W/o")" "\"$_v\""; done
for _v in KEPT KEPT2 KEPT3; do t_has "kept: $_v" "$(cat "$W/o")" "\"$_v\""; done
BODY="{\"key\":\"V3\",\"pwd\":\"V4\"}" run "$(mutant "$(grep "^EXACT='" "$BIN/access-get.sh")" "EXACT='zzzz'")" tok user/info/
t_has "red redact-exact: bare key prints without it" "$(cat "$W/o")" '"V3"'; t_red get.redact-exact
BODY='{"x-api-key":"V1"}' run "$(mutant "$(grep -F 'def norm:' "$BIN/access-get.sh")" '    def norm: ascii_downcase;')" tok user/info/
t_has "red redact-hyphen: x-api-key prints when keys are not normalised" "$(cat "$W/o")" '"V1"'; t_red get.redact-hyphen
_jl="$(grep -F 'def jwt:' "$BIN/access-get.sh")"
BODY="{\"note\":\"$_jwt\"}" run "$(mutant "$_jl" '    def jwt: false;')" tok user/info/
t_has "red redact-jwt: a JWT prints without it" "$(cat "$W/o")" "$_jwt"; t_red get.redact-jwt
_nl="$(grep -F '(if pairname then' "$BIN/access-get.sh")"
BODY='{"fields":[{"name":"access_token","value":"V6"}]}' run "$(mutant "$_nl" '           .')" tok user/info/
t_has "red redact-pair: a name/value secret prints without it" "$(cat "$W/o")" '"V6"'; t_red get.redact-pair

t_section "review 7: no secret sits in any child's environment; curl gets it on stdin only"
WRAP="$W/wrap"; mkdir -p "$WRAP"; ENVLOG="$W/envlog"; : > "$ENVLOG"
for _t in sed awk jq mktemp tr cut head wc cat rm env id grep printf od date; do
  [ -x "/usr/bin/$_t" ] || continue
  printf '#!/bin/sh\n/usr/bin/env >> %s\nexec /usr/bin/%s "$@"\n' "$ENVLOG" "$_t" > "$WRAP/$_t"; chmod +x "$WRAP/$_t"
done
TW="$W/tree-wrap"; mktree "$TW" "$WRAP:$T_BIN:/usr/bin:/bin"
run "$TW/bin" tok user/info/; t_eq "direct row through wrapped tools: exit 0" 0 "$RC"
BODY='{"id":"1"}' run "$TW/bin" bear user_account; t_eq "refresh row through wrapped tools: exit 0" 0 "$RC"
t_has "CONTROL: the wrappers logged the children's environments" "$(cat "$ENVLOG")" "PATH=$WRAP"
for _p in "token:$TOK" "refresh token:$RT" "client secret:$CSEC" "access token:$ACC"; do
  t_eq "${_p%%:*}: in no child's environment" 0 "$(grep -cF "${_p#*:}" "$ENVLOG")"
  t_eq "${_p%%:*}: not in curl's environment" 0 "$(cat "$CS"/env.* | grep -cF "${_p#*:}")"
done
_xm="$(mutant "TOKEN=''" "TOKEN=''; export TOKEN")"; _xw="$W/mut.wrapx"; rm -rf "$_xw"; cp -R "$TW" "$_xw"; cp "$_xm/access-get.sh" "$_xw/bin/access-get.sh"
sed -i.bak "s|^GET_PATH=.*|GET_PATH='$WRAP:$T_BIN:/usr/bin:/bin'|" "$_xw/bin/access-get.sh"
: > "$ENVLOG"; run "$_xw/bin" tok user/info/
t_eq "red env: an exported token reaches the children's environments" 1 "$(grep -cF "$TOK" "$ENVLOG" | sed 's/^[1-9][0-9]*$/1/')"; t_red get.child-env

# ── The second review of #1620 ──
SECRETS="$TOK $RT $CSEC $ACC"
leaks() { # <file>... : how many of the four fake secrets the files hold
  _lk=0; for _s in $SECRETS; do ! cat "$@" 2>/dev/null | grep -qF "$_s" || _lk=$((_lk + 1)); done; echo "$_lk"
}

t_section "second review 1: no trace prints a credential, under sh -x or SHELLOPTS=xtrace, on either row"
for _v in tok:user/info/ bear:user_account; do
  stub; /bin/sh -x "$TB/access-get.sh" "${_v%%:*}" "${_v#*:}" > "$W/o" 2> "$W/e" || :
  t_has "sh -x ${_v%%:*}: CONTROL: the trace was on" "$(cat "$W/e")" "+ set +xv"
  t_eq "sh -x ${_v%%:*}: no secret on stdout or stderr" 0 "$(leaks "$W/o" "$W/e")"
  stub; env SHELLOPTS=xtrace /bin/sh "$TB/access-get.sh" "${_v%%:*}" "${_v#*:}" > "$W/o" 2> "$W/e" || :
  t_eq "SHELLOPTS=xtrace ${_v%%:*}: no secret on stdout or stderr" 0 "$(leaks "$W/o" "$W/e")"
  stub; env SHELLOPTS=xtrace /bin/sh -x "$TB/access.sh" get "${_v%%:*}" "${_v#*:}" > "$W/o" 2> "$W/e" || :
  t_eq "through harbor access get, traced: no secret" 0 "$(leaks "$W/o" "$W/e")"
done
_xl="$(grep '^set +xv' "$BIN/access-get.sh")"
_xm="$(mutant "$_xl" ':')"
stub; /bin/sh -x "$_xm/access-get.sh" tok user/info/ > "$W/o" 2> "$W/e" || :
t_eq "red xtrace: without set +xv, sh -x prints the token" 1 "$(leaks "$W/e")"; t_red get.xtrace

t_section "second review 2: no credential is ever in a file, even during a slow exchange in a caller's TMPDIR"
XT="$W/caller-tmp"; mkdir -p "$XT"; LOOT="$W/loot"; : > "$LOOT"; TICKS="$W/ticks"; : > "$TICKS"
stub '{"id":"1"}'; touch "$CS/slow"
( _i=0; while [ "$_i" -lt 120 ]; do
    # Regular files only: a reader on bin/secret's passphrase FIFO would block forever (and hang the suite).
    find "$XT" "$HOME" "$TMPDIR" -type f -exec grep -lF -e "$TOK" -e "$RT" -e "$CSEC" -e "$ACC" {} + >> "$LOOT" 2>/dev/null
    echo x >> "$TICKS"; _i=$((_i + 1)); sleep 0.05
  done ) &
_wp=$!
RC=0; TMPDIR="$XT" sh "$TB/access-get.sh" bear user_account > "$W/o" 2> "$W/e" || RC=$?
wait "$_wp" 2>/dev/null || :
t_eq "the slow refresh row completed" 0 "$RC"
t_eq "CONTROL: the watcher ran through the exchange" yes "$([ "$(wc -l < "$TICKS")" -ge 20 ] && echo yes || echo no)"
t_eq "no file under the caller's TMPDIR, HOME or TMPDIR ever held a secret" '' "$(sort -u "$LOOT")"
t_eq "the run made no temp dir in the caller's TMPDIR" 0 "$(find "$XT" -mindepth 1 | wc -l | tr -d ' ')"

t_section "second review 3: the vendor table is the deployed copy in the config dir; the private checkout's is never read"
printf 'planted\texample-tok-read\thttps://evil.example.org/\tbearer\tx/\t-\t-\t-\t-\t-\n' > "$AD/get.tsv"
refused "a row planted in harbor-private/access/get.tsv" "is not in the table ($CT/get.tsv)" planted x/y
mv "$CT/get.tsv" "$W/ct.bak"
refused "with no deployed table, nothing is read" "no deployed vendor table at $CT/get.tsv" tok user/info/
t_has "...and the fix names the deploy" "$(cat "$W/e")" "sh bin/deploy.sh --only packs --apply --live"
mv "$W/ct.bak" "$CT/get.tsv"; rm -f "$AD/get.tsv"

t_section "second review 4: harbor access get starts access-get.sh with /bin/sh and a fixed PATH, whatever the caller's"
FS="$W/fakesh"; mkdir -p "$FS"; printf '#!/bin/sh\necho "$@" >> %s/ran\nexec /bin/sh "$@"\n' "$FS" > "$FS/sh"; chmod +x "$FS/sh"
stub; rm -f "$FS/ran"; PATH="$FS:$PATH" /bin/sh "$TB/access.sh" get tok user/info/ > "$W/o" 2> "$W/e" || :
t_eq "a sh first on the caller's PATH is not the one that runs it" no "$([ -e "$FS/ran" ] && echo yes || echo no)"
t_eq "...and the GET still ran" 1 "$(calls)"
_am="$(mutant "$(grep -F '  get) exec /usr/bin/env' "$BIN/access.sh")" '  get) exec sh "$SRC/access-get.sh" "$@" ;;' access.sh)"
stub; rm -f "$FS/ran"; PATH="$FS:$PATH" /bin/sh "$_am/access.sh" get tok user/info/ > "$W/o" 2> "$W/e" || :
t_has "red dispatch-path: the old dispatch ran the caller's sh" "$(cat "$FS/ran" 2>/dev/null)" "access-get.sh"; t_red get.dispatch-path

t_section "second review 5: typed, labelled, case-folded and array pairs, scheme-prefixed values and bearer/otp/code keys"
B5='{"a":{"type":"api_key","value":"W1"},"b":{"label":"Password","value":"W2"},"c":{"Name":"token","Value":"W3"},"d":[["access_token","W4"]],"e":"Bearer W5abcdef","f":"Basic dXNlcjpwYXNzd29yZA==","bearer":"W7","otp":"W8","code":"W9","n":{"code":0},"passenger":"KEPT2","keyword":"KEPT3","g":{"type":"campaign","value":"KEPT4"},"h":[["campaign_id","KEPT5"]]}'
BODY="$B5" run "$TB" tok user/info/
t_eq "exit 0" 0 "$RC"
for _v in W1 W2 W3 W4 "Bearer W5abcdef" "Basic dXNlcjpwYXNzd29yZA==" W7 W8 W9; do t_hasnt "withheld: $_v" "$(cat "$W/o")" "\"$_v\""; done
for _v in KEPT2 KEPT3 KEPT4 KEPT5; do t_has "kept: $_v" "$(cat "$W/o")" "\"$_v\""; done
t_has "a numeric code is kept (a vendor's numeric status)" "$(cat "$W/o")" '"code": 0'
BODY="$B5" run "$(mutant "$(grep -F 'def pairname:' "$BIN/access-get.sh")" '    def pairname: false;')" tok user/info/
t_has "red pair-typed: a typed pair prints without it" "$(cat "$W/o")" '"W1"'; t_red get.pair-typed
BODY="$B5" run "$(mutant "$(grep -F 'elif type == "array" then' "$BIN/access-get.sh")" '         elif false then .')" tok user/info/
t_has "red pair-array: an array pair prints without it" "$(cat "$W/o")" '"W4"'; t_red get.pair-array
BODY="$B5" run "$(mutant "$(grep -F 'def scheme:' "$BIN/access-get.sh")" '    def scheme: false;')" tok user/info/
t_has "red scheme: a Bearer value prints without it" "$(cat "$W/o")" '"Bearer W5abcdef"'; t_red get.scheme
BODY="$B5" run "$(mutant "$(grep "^EXACT='" "$BIN/access-get.sh")" "EXACT='key|pass|pwd|pin|sig|auth'")" tok user/info/
t_has "red exact-words: bearer, otp and code print without them" "$(cat "$W/o")" '"W8"'; t_red get.exact-words

# ── The review fan-out on #1620 (F1-F9) ──
t_section "F1: a --query key is refused when it names a credential in any spelling"
for _k in access-token api-key x-api-key accessToken clientSecret refreshToken Access.Token; do
  refused "--query $_k=x" "names a credential" tok report/x --query "$_k=x"
done
run "$TB" tok report/x --query fields=a --query page=2 --query pageToken=abc --query page_token=abc
t_eq "CONTROL: ordinary keys, and a pagination token key, still pass" 0 "$RC"
_f1="$(grep -F '_kn="$(printf' "$BIN/access-get.sh")"
run "$(mutant "$_f1" '  _kn="$(printf '"'"'%s'"'"' "$_k" | tr '"'"'A-Z'"'"' '"'"'a-z'"'"')"')" tok report/x --query x-api-key=x
t_eq "red query-norm: without the normalising, x-api-key goes in the URL" 0 "$RC"; t_red get.query-norm

t_section "F2: a number under a credential key is withheld; a number under code is kept"
B2='{"otp":582913,"pin":4821,"pass":12345,"api_key":123456789,"p":{"type":"pin","value":4821},"code":0,"count":7}'
BODY="$B2" run "$TB" tok user/info/
for _n in 582913 4821 12345 123456789; do t_hasnt "withheld: $_n" "$(cat "$W/o")" ": $_n"; done
t_has "kept: a numeric code" "$(cat "$W/o")" '"code": 0'
t_has "kept: a number under an ordinary key" "$(cat "$W/o")" '"count": 7'
BODY="$B2" run "$(mutant "$(grep -F 'elif type == "number" then "[withheld number]"' "$BIN/access-get.sh")" '              elif false then .')" tok user/info/
t_has "red number-hold: without it a numeric otp prints" "$(cat "$W/o")" '"otp": 582913'; t_red get.number-hold

t_section "F7: a stored token with a quote or a backslash is refused before curl"
for _q in 'quote:BAD"TOKEN-0123456789' 'bslash:BAD\TOKEN-0123456789'; do
  _v="${_q%%:*}"; printf '\n## example-%s-read\n\n    secret: example-%s-read\n' "$_v" "$_v" >> "$AD/register.md"
  printf '%s\texample-%s-read\thttps://%s.example.com/v1/\theader:Access-Token\tuser/\t-\t-\t-\t-\t-\n' "$_v" "$_v" "$_v" >> "$CT/get.tsv"
  printf '%s' "${_q#*:}" | "$BIN/secret" put "example-$_v-read" >/dev/null 2>&1
  run "$TB" "$_v" user/x
  t_eq "$_v: exit 1" 1 "$RC"; t_has "$_v: refused by name" "$(cat "$W/e")" "holds a character a header value may not"; t_eq "$_v: curl never ran" 0 "$(calls)"
done
_f7="$(grep -F 'case "$TOKEN" in' "$BIN/access-get.sh")"
run "$(mutant "$_f7" "$(printf '%s' "$_f7" | sed 's/|\*\\"\*|\*\\\\\*)/)/')")" quote user/x
t_eq "red token-chars: without the quote case, the token reaches curl's config" 1 "$(calls)"; t_red get.token-chars

t_section "F8: a row whose client ref is its own token ref is refused, before any request"
printf 'self\texample-self-ref\thttps://self.example.com/v1/\tbearer\tx/\t-\t-\thttps://auth.self.example.com/t\tcid\texample-self-ref\n' >> "$CT/get.tsv"
refused "client_ref == secret ref" "is its token ref" self x/y
MB="$(mutant "$(grep -F 'refuse "the $VENDOR row'"'"'s client ref is its token ref"' "$BIN/access-get.sh")" ':')" refused "red self-cref (mutant: the line removed)" "is named 2 times" self x/y
unset MB; t_red get.self-cref

t_section "F3 and F9: a 401 or 403 gets its own remedy, JSON body or not"
CODE=401 BODY='Unauthorized' run "$TB" tok user/info/
t_eq "plain-text 401: exit 1" 1 "$RC"
t_has "...named as a refused credential" "$(cat "$W/e")" "401: the tok credential was refused"
t_hasnt "...not as a bad path" "$(cat "$W/e")" "check the path"
t_eq "...and the body is not printed" '' "$(cat "$W/o")"
CODE=403 BODY='{"message":"forbidden"}' run "$TB" tok user/info/
t_eq "JSON 403: exit 1" 1 "$RC"; t_has "...may not read" "$(cat "$W/e")" "may not read user/info/"
t_has "...and the redacted reason prints" "$(cat "$W/o")" "forbidden"
CODE=403 BODY='{"message":"forbidden"}' run "$(mutant '  403) fail "403: the credential works but may not read $RP" "the route card'"'"'s reaches: line" 1 ;;' '  403) log_end ;;')" tok user/info/
t_eq "red json-403: without the 403 case a JSON 403 exits 0" 0 "$RC"; t_red get.json-403
CODE=403 BODY='Forbidden' run "$TB" tok user/info/
t_eq "plain-text 403: exit 1" 1 "$RC"; t_has "...may not read" "$(cat "$W/e")" "may not read user/info/"
_f3="$(grep -F '401) fail "401: the $VENDOR credential was refused (a' "$BIN/access-get.sh")"
CODE=401 BODY='Unauthorized' run "$(mutant "$_f3" '    0401) ;;')" tok user/info/
t_has "red status-first: without it a plain-text 401 reads as a bad path" "$(cat "$W/e")" "check the path"; t_red get.status-first

t_section "F5: --list on a table with no vendor rows says so and exits 1"
cp "$CT/get.tsv" "$W/full.tsv"; printf 'vendor\tsecret\tbase\tauth\tallow\tdeny\tredact\ttoken_url\tclient_id\tclient_ref\n' > "$CT/get.tsv"
RC=0; sh "$TB/access-get.sh" --list > "$W/o" 2> "$W/e" || RC=$?
t_eq "exit 1" 1 "$RC"; t_has "...naming the table" "$(cat "$W/e")" "no vendors in $CT/get.tsv"
RC=0; sh "$(mutant "$(grep -F "no vendors in %s" "$BIN/access-get.sh")" '    :')/access-get.sh" --list > "$W/o" 2> "$W/e" || RC=$?
t_eq "red list-empty: without it an empty table lists as a success" 0 "$RC"; t_red get.list-empty
cp "$W/full.tsv" "$CT/get.tsv"
t_done
