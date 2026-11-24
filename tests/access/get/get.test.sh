#!/usr/bin/env sh
# access get (harbor#1617): `harbor access get` refuses an unlisted vendor, a path outside the allowed prefixes, each
# forbidden character, a '?' in the path and any method/header/body/URL argument, before any request; sends exactly one
# GET with the token on curl's stdin only; and redacts the body. curl is a stub (no network); the Keychain is a stub.
# access-get.sh reads no seam from the environment, so the cases drive a copy of bin/ with its GET_PATH and GET_HOME lines
# rewritten (the access-confinement pattern); the last section proves the real file ignores ACCESS_DIR and its kin.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
BIN="$T_ROOT/bin"; W="$T_TMP/work"; mkdir -p "$W"
# The fixture private layer sits where the default resolution looks: <home>/port/harbor-private/access.
AD="$HOME/port/harbor-private/access"; mkdir -p "$AD"
for _r in example-tok-read example-bear-refresh example-bear-client; do printf '\n## %s\n\n    secret: %s\n' "$_r" "$_r" >> "$AD/register.md"; done
# The table is read only from the deployed copy in the config dir (second review of #1620), never the private checkout.
CT="$HOME/.claude/access"; mkdir -p "$CT"; cp "$(dirname "$0")/get.tsv" "$CT/get.tsv"
TOK='FAKE-TT-TOKEN-0123456789abcdef'; RT='FAKE-REFRESH-9876543210fedcba'; CSEC='FAKE-CLIENT-SECRET-55aa55aa'; ACC='FAKE-ACCESS-TOKEN-77bb77bb'
printf '%s' "$TOK" | "$BIN/secret" put example-tok-read >/dev/null 2>&1
printf '%s' "$RT" | "$BIN/secret" put example-bear-refresh >/dev/null 2>&1
printf '%s' "$CSEC" | "$BIN/secret" put example-bear-client >/dev/null 2>&1

# The curl stub: logs argv (each argument closed by |), its stdin config, its environment and every argv `ps` shows. curl
# runs under env -i, so the stub's paths are written into it, not read from the environment.
CS="$T_TMP/curlstub"
cat > "$T_BIN/curl" <<STUB
#!/bin/sh
CS='$CS'; ACC='$ACC'
STUB
cat >> "$T_BIN/curl" <<'STUB'
n=$(($(cat "$CS/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$CS/n"
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$CS/argv.log"
cat > "$CS/config.$n"
env > "$CS/env.$n"
ps -A -o args= > "$CS/ps.$n" 2>/dev/null
out=''; prev=''
for a in "$@"; do [ "$prev" != -o ] || out="$a"; prev="$a"; done
# With -o the body goes to that file and -w's code to stdout; without it (curl's default) the body, a newline, the code.
if grep -q 'grant_type=refresh_token' "$CS/config.$n"; then
  [ ! -e "$CS/slow" ] || sleep 2
  printf '{"access_token":"%s","token_type":"bearer","expires_in":3600}' "$ACC" > "$CS/resp.$n"; printf 200 > "$CS/rc.$n"
else
  cat "$CS/body" > "$CS/resp.$n"; cat "$CS/code" > "$CS/rc.$n"
fi
if [ -n "$out" ]; then cat "$CS/resp.$n" > "$out"; cat "$CS/rc.$n"; else cat "$CS/resp.$n"; printf '\n'; cat "$CS/rc.$n"; fi
STUB
chmod +x "$T_BIN/curl"
DEFBODY='{"code":0,"message":"OK","data":{"email":"person@example.com","display_name":"Example","access_token":"LEAKED-IN-BODY"}}'
stub() { # [body] [code]
  rm -rf "$CS"; mkdir -p "$CS"
  _sb="${1:-}"; [ -n "$_sb" ] || _sb="$DEFBODY"
  printf '%s' "$_sb" > "$CS/body"; printf '%s' "${2:-200}" > "$CS/code"
}
calls() { cat "$CS/n" 2>/dev/null || echo 0; }
# ps is setuid and the macOS sandbox refuses it: there the ps checks are DEFERRED, never passed. On Linux (CI) they must run.
PS_OK=0; ps -A -o args= >/dev/null 2>&1 && PS_OK=1
pscheck() { if [ "$PS_OK" = 1 ]; then "$@"; else printf '  DEFERRED (ps is refused here; run outside the sandbox): %s\n' "$2" >&2; fi; }

# mktree <dir> <GET_PATH>: <dir>/bin, a copy of the scripts access-get.sh runs, with its two seam lines rewritten.
mktree() {
  rm -rf "$1"; mkdir -p "$1/bin"; ln -s "$T_ROOT/contracts" "$1/contracts"; ln -s "$T_ROOT/standards" "$1/standards"
  for _f in access.sh access-oauth.sh access-redact.sh admission-egress.sh library-log.sh scope-roots.sh secret lint-name.sh; do cp "$BIN/$_f" "$1/bin/"; done
  P="$2" H="$HOME" awk '$0 == "GET_PATH=/usr/bin:/bin" { print "GET_PATH='"'"'" ENVIRON["P"] "'"'"'"; n++; next }
    $0 == "GET_HOME='"''"'" { print "GET_HOME='"'"'" ENVIRON["H"] "'"'"'"; n++; next } { print } END { exit n != 2 }' \
    "$BIN/access-get.sh" > "$1/bin/access-get.sh" || { echo "mktree: the GET_PATH/GET_HOME lines moved"; return 1; }
}
TREE="$W/tree"; mktree "$TREE" "$T_BIN:/usr/bin:/bin"; TB="$TREE/bin"
RC=0
run() { # <bin dir> <args...>: stdout in $W/o, stderr in $W/e, exit in RC
  # A BODY= or CODE= prefix outlives a function call in bash's sh mode, so run consumes both.
  _b="$1"; shift; RC=0; stub "${BODY:-}" "${CODE:-}"; unset BODY CODE
  sh "$_b/access-get.sh" "$@" > "$W/o" 2> "$W/e" || RC=$?
}
# refused <label> <needle> <args...>: exit 2, the refusal names its class, and no request was made
refused() {
  _l="$1"; _n="$2"; shift 2; run "${MB:-$TB}" "$@"
  t_eq "$_l: exit 2" 2 "$RC"; t_has "$_l: the refusal names it" "$(cat "$W/e")" "$_n"; t_eq "$_l: curl never ran" 0 "$(calls)"
}
# mutant <exact line> <replacement> [file]: a copy of the tree with that line of bin/<file> (access-get.sh) replaced;
# prints its bin dir, or NOT-APPLIED when the line is absent.
mutant() {
  _f="${3:-access-get.sh}"; _d="$W/mut.$(printf '%s%s' "$1" "$_f" | cksum | cut -d' ' -f1)"; rm -rf "$_d"; cp -R "$TREE" "$_d"
  M="$1" R="$2" awk '$0 == ENVIRON["M"] { print ENVIRON["R"]; next } { print }' "$TB/$_f" > "$_d/bin/$_f"
  cmp -s "$TB/$_f" "$_d/bin/$_f" && { echo NOT-APPLIED; return; }
  echo "$_d/bin"
}
# red <control> <exact line> <replacement> <needle> <args...>: with the guard removed, the refusal is gone (seen red).
red() {
  _c="$1"; _m="$(mutant "$2" "$3")"; _nd="$4"; shift 4
  t_has "red $_c: the mutant applied" "$_m" "/"
  [ "$_m" != NOT-APPLIED ] || return 0
  run "$_m" "$@"
  if [ "$RC" = 2 ] && grep -qF -- "$_nd" "$W/e"; then t_fail "red $_c: the mutant still refused, so the assertion cannot fail"
  else t_pass; t_red "$_c"; fi
}
# The exact lines the mutants replace, read from the script so a quoting slip cannot make a mutant silently not apply.
CURL_LINE="$(grep -F '| env -i PATH="$GET_PATH" HOME=/ LC_ALL=C curl -q' "$BIN/access-get.sh")"
EXCH_LINE="$(grep -F 'then env -i PATH="$PATH" HOME=/ LC_ALL=C curl -q' "$BIN/access-oauth.sh")"
FLOOR_LINE="$(grep "^FLOOR='" "$BIN/access-get.sh")"
UNSET_LINE="$(grep '^unset ACCESS_DIR ' "$BIN/access-get.sh")"
# remut <bin dir> <file> <exact line> <replacement>: one more replacement inside a mutant, in place; a miss fails the case.
remut() {
  M="$3" R="$4" awk '$0 == ENVIRON["M"] { print ENVIRON["R"]; n++; next } { print } END { exit n == 0 }' "$1/$2" > "$1/$2.new" \
    && mv "$1/$2.new" "$1/$2" || t_fail "remut: the line is not in $1/$2: $3"
}

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
