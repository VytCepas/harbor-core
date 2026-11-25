#!/usr/bin/env sh
# access get (harbor#1617): `harbor access get` refuses an unlisted vendor, a path outside the allowed prefixes, each
# forbidden character, a '?' in the path and any method/header/body/URL argument, before any request; sends exactly one
# GET with the token on curl's stdin only; and redacts the body. curl is a stub (no network); the Keychain is a stub.
# access-get.sh reads no seam from the environment, so the cases drive a copy of bin/ with its GET_PATH and GET_HOME lines
# rewritten (the access-confinement pattern); the review cases are in review.test.sh, setup in lib.sh.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/lib.sh"
t_section "a listed vendor: exactly one GET, the token on stdin only, the body redacted"
[ "$(uname -s)" != Linux ] || t_eq "ps lists processes on Linux, so no ps check is deferred there" 1 "$PS_OK"
run "$TB" tok user/info/
t_eq "exit 0" 0 "$RC"
t_eq "curl ran once" 1 "$(calls)"
t_has "the URL is the row's base plus the path" "$(cat "$CS/argv.log")" "--url|https://api.example.com/v1/user/info/|"
t_eq "curl's first argument is -q (no ~/.curlrc)" '-q' "$(cut -d'|' -f1 "$CS/argv.log")"
t_eq "no method, data or header flag reaches curl" 0 "$(tr '|' '\n' < "$CS/argv.log" | grep -cE '^(-X|--request|-d|--data.*|-H|--header|-F|--form|-T|--upload-file|-L|--location)$')"
t_has "CONTROL: the token reached curl, as the row's header on stdin" "$(cat "$CS/config.1")" "header = \"Access-Token: $TOK\""
t_eq "the token is in no curl argv" 0 "$(grep -cF "$TOK" "$CS/argv.log")"
pscheck t_has "CONTROL: ps saw the calling access-get.sh while curl ran" "$(cat "$CS/ps.1")" "access-get.sh"
pscheck t_eq "the token is in no argv ps shows" 0 "$(grep -cF "$TOK" "$CS/ps.1")"
t_hasnt "the token is not on stdout" "$(cat "$W/o")" "$TOK"
t_hasnt "nor on stderr" "$(cat "$W/e")" "$TOK"
t_has "stderr carries the status" "$(cat "$W/e")" "http=200"
t_has "the body is printed" "$(cat "$W/o")" '"message": "OK"'
t_hasnt "the floor withholds access_token" "$(cat "$W/o")" "LEAKED-IN-BODY"
t_hasnt "the row's redact regex withholds email" "$(cat "$W/o")" "person@example.com"
t_has "...replaced by a length" "$(cat "$W/o")" '"email": "[withheld 18 chars]"'
t_has "a key no regex names is kept" "$(cat "$W/o")" '"display_name": "Example"'
t_eq "the token is in no file left under HOME or TMPDIR" 0 "$(grep -rlF "$TOK" "$HOME" "$TMPDIR" 2>/dev/null | wc -l | tr -d ' ')"
t_eq "the temp dir is gone" 0 "$(find "$TMPDIR" -name 'access-get.*' | wc -l | tr -d ' ')"
red token-argv "$CURL_LINE" "$(printf %s "$CURL_LINE" | sed 's/curl -q -sS/curl -q -sS -H "X-Leak: $TOKEN"/')" 'never-printed' tok user/info/
t_eq "red token-argv: with the token on argv, the curl argv log holds it" 1 "$(grep -cF "$TOK" "$CS/argv.log" | sed 's/^[1-9][0-9]*$/1/')"
pscheck t_eq "red token-argv: with the token on argv, ps sees it" 1 "$(grep -cF "$TOK" "$CS/ps.1" | sed 's/^[1-9][0-9]*$/1/')"
red redact-floor "$FLOOR_LINE" "FLOOR='zzzz'" 'never-printed' tok user/info/
t_has "red redact-floor: with no floor the body's access_token prints" "$(cat "$W/o")" "LEAKED-IN-BODY"
run "$TB" tok /user/info/
t_eq "a leading / is the same path" 0 "$RC"

t_section "--query: validated, encoded, and the only argument after the path"
run "$TB" tok report/x --query 'fields=["a","b"]' --query page=2
t_eq "exit 0" 0 "$RC"
t_has "values are percent-encoded" "$(cat "$CS/argv.log")" '--url|https://api.example.com/v1/report/x?fields=%5B%22a%22%2C%22b%22%5D&page=2|'
refused "a space in a query value" "whitespace" tok report/x --query 'a=b c'
refused "a line break in a query value" "whitespace" tok report/x --query "a=b
X-Evil: 1"
refused "a query key naming a credential" "names a credential" tok report/x --query access_token=x
refused "a query key outside the class" "is not [A-Za-z0-9_.-]" tok report/x --query 'a&b=1'
refused "a query that is not k=v" "is not k=v" tok report/x --query novalue

t_section "an unlisted vendor, and a path outside the allowed prefixes, are refused"
refused "an unlisted vendor" "is not in the table" nope user/info/
red unlisted-vendor '[ "$_n" -gt 0 ] || refuse "vendor '"'"'$VENDOR'"'"' is not in the table ($TBL)" "harbor access get --list"' ':' \
  'is not in the table' nope user/info/
refused "a vendor name outside [a-z0-9-]" "is not [a-z0-9-]" 'Tok' user/info/
refused "a path under no allowed prefix" "starts with none of the tok row's allowed prefixes" tok admin/users
refused "a prefix match is literal: userx/ is not user/" "starts with none" tok userx/info
red allowed-prefix '[ "$_ok" = 1 ] || refuse "path '"'"'$RP'"'"' starts with none of the $VENDOR row'"'"'s allowed prefixes ($ALLOW)" "harbor access get --list"' ':' \
  'starts with none' tok admin/users
refused "a path matching a denied glob" "denied glob 'user/token*'" tok user/token/rotate
refused "a denied glob anywhere" "denied glob '*/secret*'" tok report/secret-keys

t_section "each forbidden character in the path is refused"
refused "'..'" "'..' in the path" tok user/../admin
refused "a space" "whitespace" tok 'user/a b'
refused "a tab" "whitespace" tok "user/a	b"
refused "a double quote" "a quote" tok 'user/a"b'
refused "a single quote" "a quote" tok "user/a'b"
refused "a backtick" "a backtick" tok 'user/a`id`'
for _c in '$' ';' '|' '<' '>' '&'; do refused "'$_c'" "a shell metacharacter" tok "user/a${_c}b"; done
refused "'#'" "'#' in the path" tok 'user/a#b'
refused "'?' in the path" "a query goes only through --query" tok 'user/info/?x=1'
refused "'//' in the path" "'//'" tok 'user//info'
refused "a percent escape" "a character outside" tok 'user/%2e%2e/admin'
refused "a full URL as the path" "'//'" tok 'https://evil.example.org/user/'
refused "an empty path" "an empty path" tok ''
red dotdot "  *..*) refuse \"'..' in the path\" ;;" '' "'..' in the path" tok user/../admin
red question "  *'?'*) refuse \"'?' in the path: a query goes only through --query k=v\" ;;" '' 'a query goes only through --query' tok 'user/info/?x=1'
red metachar "  *'\$'*|*';'*|*'|'*|*'<'*|*'>'*|*'&'*) refuse \"a shell metacharacter (\\\$ ; | < > &) in the path\" ;;" '' 'a shell metacharacter' tok 'user/a;b'
red hash "  *'#'*) refuse \"'#' in the path\" ;;" '' "'#' in the path" tok 'user/a#b'

t_section "no method, header, body or URL can be injected"
refused "-X before the vendor" "the vendor comes first" -X POST tok user/info/
refused "-X after the path" "there is no method, header, body or URL argument" tok user/info/ -X POST
refused "--request" "there is no method" tok user/info/ --request DELETE
refused "-H" "there is no method" tok user/info/ -H 'X-HTTP-Method-Override: DELETE'
refused "--header" "there is no method" tok user/info/ --header 'Authorization: Bearer x'
refused "--data" "there is no method" tok user/info/ --data a=b
refused "a second path" "there is no method" tok user/info/ report/x
red method-arg "    *) refuse \"'\$1': only --query k=v may follow the path; there is no method, header, body or URL argument\" ;;" '    *) shift; continue ;;' \
  'there is no method' tok user/info/ -X POST
t_eq "red method-arg: the mutant sent a request" 1 "$(calls)"

t_section "a refresh-token row: one exchange through access-oauth.sh, then one GET, no secret on argv"
BODY='{"id":"123","username":"someone","account_type":"BUSINESS"}' run "$TB" bear user_account
t_eq "exit 0" 0 "$RC"
t_eq "curl ran twice: the exchange, then the GET" 2 "$(calls)"
t_has "CONTROL: the exchange sent the refresh grant" "$(cat "$CS/config.1")" 'grant_type=refresh_token'
t_has "CONTROL: ...with the refresh token" "$(cat "$CS/config.1")" "refresh_token=$RT"
t_has "CONTROL: ...and basic client auth" "$(cat "$CS/config.1")" "user = \"client-1:$CSEC\""
t_has "CONTROL: ...to the row's token URL" "$(cat "$CS/config.1")" 'url = "https://auth.example.com/oauth/token"'
t_has "CONTROL: the GET carried the exchanged bearer" "$(cat "$CS/config.2")" "header = \"Authorization: Bearer $ACC\""
t_has "the GET went to the row's base" "$(sed -n 2p "$CS/argv.log")" '--url|https://bearer.example.com/v5/user_account|'
for _p in "refresh token:$RT" "client secret:$CSEC" "access token:$ACC"; do _l="${_p%%:*}"; _s="${_p#*:}"
  t_eq "$_l: in no curl argv" 0 "$(grep -cF "$_s" "$CS/argv.log")"
  pscheck t_eq "$_l: in no argv ps shows" 0 "$(cat "$CS/ps.1" "$CS/ps.2" | grep -cF "$_s")"
  t_eq "$_l: in no file left under HOME or TMPDIR" 0 "$(grep -rlF "$_s" "$HOME" "$TMPDIR" 2>/dev/null | wc -l | tr -d ' ')"
  t_hasnt "$_l: not on stdout or stderr" "$(cat "$W/o" "$W/e")" "$_s"
done
pscheck t_has "CONTROL: ps saw access-oauth.sh during the exchange" "$(cat "$CS/ps.1")" "access-oauth.sh --exchange"
t_hasnt "the row's redact regex withholds username" "$(cat "$W/o")" '"someone"'
t_has "...and keeps the rest" "$(cat "$W/o")" '"account_type": "BUSINESS"'

t_section "the answer: non-2xx, not JSON, a token shape in a value"
CODE=401 BODY='{"message":"unauthorized"}' run "$TB" tok user/info/
t_eq "a 401 exits 1" 1 "$RC"; t_has "...naming the refusal" "$(cat "$W/e")" "401"
t_has "...and still prints the vendor's reason" "$(cat "$W/o")" "unauthorized"
BODY='<html>not json</html>' run "$TB" tok user/info/
t_eq "a body that is not JSON exits 1" 1 "$RC"; t_eq "...and is not printed" '' "$(cat "$W/o")"
_shape="gh""p_$(printf 'a%.0s' $(seq 1 30))"   # assembled, so no token shape sits in this file
BODY="{\"note\":\"$_shape\"}" run "$TB" tok user/info/
t_hasnt "a provider token shape under an innocent key is masked" "$(cat "$W/o")" "$_shape"
t_has "...by the shared redactor" "$(cat "$W/o")" "[REDACTED]"

t_section "the table is checked before it is trusted"
cp "$CT/get.tsv" "$W/good.tsv"
tbl() { cp "$W/good.tsv" "$CT/get.tsv"; printf '%s\n' "$1" >> "$CT/get.tsv"; }
tbl "$(printf 'tok\texample-other\thttps://api.example.com/v1/\tbearer\tuser/\t-\t-\t-\t-\t-')"
refused "a vendor with two rows" "has 2 rows" tok user/info/
tbl "$(printf 'dup\texample-tok-read\thttps://evil.example.org/\tbearer\tuser/\t-\t-\t-\t-\t-')"
refused "a ref bound to a second vendor" "is named 2 times" dup user/x
refused "...from either row" "is named 2 times" tok user/info/
tbl "$(printf 'plain\texample-plain\thttp://api.example.com/v1/\tbearer\tuser/\t-\t-\t-\t-\t-')"
refused "an http base" "is not https" plain user/x
tbl "$(printf 'port\texample-port\thttps://api.example.com:8443/v1/\tbearer\tuser/\t-\t-\t-\t-\t-')"
refused "a base with a port" "is not a DNS name" port user/x
tbl "$(printf 'hdr\texample-hdr\thttps://api.example.com/v1/\theader:Host\tuser/\t-\t-\t-\t-\t-')"
refused "a Host header as the auth header" "is not an auth header" hdr user/x
tbl "$(printf 'empty\texample-empty\thttps://api.example.com/v1/\tbearer\tuser/\t\t-\t-\t-\t-')"
refused "an empty column" "10 non-empty" empty user/x
cp "$W/good.tsv" "$CT/get.tsv"
t_has "--list prints vendor, base and prefixes" "$(sh "$TB/access-get.sh" --list 2>&1)" "$(printf 'tok\thttps://api.example.com/v1/\tuser/,report/')"
t_hasnt "...and no ref" "$(sh "$TB/access-get.sh" --list 2>&1)" "example-tok-read"

t_section "the front door: harbor access get"
stub; RC=0; sh "$TB/access.sh" get tok user/info/ > "$W/o" 2> "$W/e" || RC=$?
t_eq "harbor access get dispatches to access-get.sh" 0 "$RC"; t_eq "...one GET" 1 "$(calls)"
t_exit "harbor access get --json is refused (status alone takes it)" 2 sh "$TB/access.sh" get --json tok user/info/

t_done
