#!/usr/bin/env sh
# access-get.sh (harbor#1617) - `harbor access get`: one read-only HTTPS GET to a vendor API, with the one credential and
# the paths the private vendor table allows (contracts/access-get.md). No method, header, body or URL is ever an argument.
#
#   harbor access get <vendor> <path> [--query k=v ...]   the JSON body, redacted, on stdout; the status on stderr
#   harbor access get --list                              the table's vendors, base URLs and allowed prefixes
#
# The table is <access dir>/get.tsv (sh bin/scope-roots.sh --access). The token comes from bin/secret run, reaches curl on
# stdin (-K -) and is never in argv, a URL, stdout, stderr or a file but a 0600 temp removed on exit. A refresh-token row
# is exchanged first through access-oauth.sh --exchange, the same token-endpoint client the OAuth intake uses.
# Exit: 0 a 2xx; 1 the request failed or was not 2xx; 2 refused before any request; 3 the redactor withheld the body.
set -eu
LC_ALL=C; export LC_ALL   # the character classes below are ASCII

# --stash <file>: internal, the child of `secret run <ref> HARBOR_ACCESS_GET_STASH`. The value goes to a new 0600 file
# and out of the environment before anything else runs, so no other process ever holds it in env (review of #1620).
if [ "${1:-}" = --stash ]; then
  _v="${HARBOR_ACCESS_GET_STASH:-}"; unset HARBOR_ACCESS_GET_STASH
  [ $# -eq 2 ] && [ -n "$_v" ] || exit 1
  umask 077; set -C; printf '%s' "$_v" > "$2"; exit 0
fi

# NO SEAM IS READ FROM THE ENVIRONMENT (review of #1620: ACCESS_DIR sent a real token to a caller's host). The search path
# and the home are fixed on the next two lines, tests drive a copy with them rewritten, and every variable that moves the
# table, the register, the redactor or curl is dropped. An empty GET_HOME is the account's passwd home, never $HOME.
GET_PATH=/usr/bin:/bin
GET_HOME=''
if [ -z "$GET_HOME" ]; then
  _u="$(/usr/bin/id -un)"; case "$_u" in ''|*[!A-Za-z0-9._-]*) printf 'access-get: no account name\n' >&2; exit 2 ;; esac
  eval "GET_HOME=~$_u"
fi
case "$GET_HOME" in /*) ;; *) printf 'access-get: no passwd home for this account\n' >&2; exit 2 ;; esac
PATH="$GET_PATH"; HOME="$GET_HOME"; export PATH HOME
unset ACCESS_DIR HARBOR_SCOPE_ROOT HARBOR_SCOPE_PRIVATE HARBOR_SCOPE_ROOTS_TABLE PORT_ROOT HARBOR_ACCESS_REDACT_EGRESS \
  XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME CURL_HOME CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR SSLKEYLOGFILE \
  HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init access-get
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
TAB="$(printf '\t')"
TMO=30
# Keys whose value is withheld from every vendor's output, matched with - _ . and space removed, lower case: a substring
# of FLOOR, or exactly one of EXACT. A row's redact column adds to them; JWT-shaped values and name/value pairs are held too.
FLOOR='token|secret|password|passwd|privatekey|apikey|accesskey|secretkey|authorization|cookie|session|credential|signature'
EXACT='key|pass|pwd|pin|sig|auth'

fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
refuse() { fail "refused: $1" "${2:-harbor access get --help}" 2; }
usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# The access dir of the default private layer under GET_HOME, resolved with no caller environment at all.
table() {
  __ad="$(env -i HOME="$GET_HOME" PATH="$GET_PATH" LC_ALL=C sh "$SRC/scope-roots.sh" --access 2>/dev/null)" \
    || refuse "no access directory under $GET_HOME, so there is no vendor table" "sh bin/scope-roots.sh --access"
  [ -f "$__ad/get.tsv" ] || refuse "no vendor table at $__ad/get.tsv" "contracts/access-get.md has the schema"
  printf '%s/get.tsv' "$__ad"
}
rows() { awk -F'\t' '/^[[:space:]]*(#|$)/ || $1 == "vendor" { next } { print }' "$1"; }

[ $# -ge 1 ] || usage
case "$1" in
  -h|--help|help) usage ;;
  --list) TBL="$(table)"; rows "$TBL" | awk -F'\t' '{ printf "%s\t%s\t%s\n", $1, $3, $5 }'; exit 0 ;;
  -*) refuse "'$1': the vendor comes first, and the only option is --query k=v after the path" ;;
esac
# A function, so the script's own "$@" survives for the re-entry under secret run.
parse_args() {
VENDOR="$1"; shift
[ $# -ge 1 ] || refuse "no path: harbor access get <vendor> <path>"
ARGPATH="$1"; shift
case "$VENDOR" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*|-*) refuse "vendor '$VENDOR' is not [a-z0-9-]" ;; esac

# The query: k=v pairs, each validated, percent-encoded here; nothing else follows the path.
QS=''; NQ=0
while [ $# -gt 0 ]; do
  case "$1" in
    --query) [ $# -ge 2 ] || refuse "--query needs k=v"; _q="$2"; shift 2 ;;
    --query=*) _q="${1#--query=}"; shift ;;
    *) refuse "'$1': only --query k=v may follow the path; there is no method, header, body or URL argument" ;;
  esac
  NQ=$((NQ + 1)); [ "$NQ" -le 50 ] || refuse "more than 50 --query pairs"
  case "$_q" in *=*) ;; *) refuse "--query '$_q' is not k=v" ;; esac
  _k="${_q%%=*}"; _v="${_q#*=}"
  case "$_k" in ''|*[!A-Za-z0-9_.-]*) refuse "query key '$_k' is not [A-Za-z0-9_.-]" ;; esac
  # A credential never goes in a URL (constitution No.4), so a key that would carry one is refused by name.
  _kl="$(printf '%s' "$_k" | tr 'A-Z' 'a-z')"
  case "$_kl" in access_token|token|key|api_key|apikey|secret|client_secret|password|refresh_token|signature|sig|auth)
    refuse "query key '$_k' names a credential; the credential goes only in a header" ;; esac
  case "$_v" in *[![:graph:]]*) refuse "query value for '$_k' holds whitespace, a control or a non-ASCII byte" ;; esac
  [ "${#_v}" -le 1024 ] || refuse "query value for '$_k' is over 1024 characters"
  _ev="$(jq -rn --arg v "$_v" '$v | @uri')" || fail "jq could not encode a query value" "$(pkg_hint jq)" 2
  QS="$QS${QS:+&}$_k=$_ev"
done
}
parse_args "$@"

# The path: default-deny, relative to the base URL. Each refusal names the class it hit.
RP="${ARGPATH#/}"
case "$RP" in '') refuse "an empty path" ;; esac
case "$RP" in
  *..*) refuse "'..' in the path" ;;
  # curl folds a '.' segment away on the wire, so user/./token would slip past a glob anchored at user/token (review of #1620).
  .|./*|*/.|*/./*) refuse "a '.' segment in the path" ;;
  *[[:space:]]*) refuse "whitespace in the path" ;;
  *\"*|*\'*) refuse "a quote in the path" ;;
  *'`'*) refuse "a backtick in the path" ;;
  *'$'*|*';'*|*'|'*|*'<'*|*'>'*|*'&'*) refuse "a shell metacharacter (\$ ; | < > &) in the path" ;;
  *'#'*) refuse "'#' in the path" ;;
  *'?'*) refuse "'?' in the path: a query goes only through --query k=v" ;;
  *//*|/*) refuse "'//' in the path" ;;
  *[!A-Za-z0-9._~/:@=+,-]*) refuse "a character outside [A-Za-z0-9._~/:@=+,-] in the path" ;;
esac

TBL="$(table)"
# One row per vendor and one vendor per ref: a ref bound to two base URLs could be sent to either.
_n="$(rows "$TBL" | awk -F'\t' -v v="$VENDOR" '$1 == v { n++ } END { print n + 0 }')"
[ "$_n" -gt 0 ] || refuse "vendor '$VENDOR' is not in the table ($TBL)" "harbor access get --list"
[ "$_n" -eq 1 ] || refuse "vendor '$VENDOR' has $_n rows in $TBL; a vendor binds exactly one" "keep one row for $VENDOR"
ROW="$(rows "$TBL" | awk -F'\t' -v v="$VENDOR" '$1 == v')"
[ "$(printf '%s\n' "$ROW" | awk -F'\t' '{ e = 0; for (i = 1; i <= NF; i++) if ($i == "") e = 1; print (e ? 0 : NF) }')" -eq 10 ] \
  || refuse "the $VENDOR row does not have 10 non-empty tab-separated columns ('-' for none)" "contracts/access-get.md"
IFS="$TAB" read -r _ REF BASE AUTH ALLOW DENY REDACT TOKURL CID CREF <<EOF
$ROW
EOF
# Every ref, token or client secret, is named once in the whole table: a ref in two cells could reach either row's hosts.
for _r in "$REF" "$CREF"; do
  [ "$_r" != - ] || continue
  _c="$(rows "$TBL" | awk -F'\t' -v r="$_r" '{ c += ($2 == r) + ($10 == r) } END { print c + 0 }')"
  [ "$_c" -eq 1 ] || refuse "ref '$_r' is named $_c times in the table; each ref is bound to one row, once" "give each vendor its own refs"
done
case "$REF" in ''|-|*[!A-Za-z0-9._-]*) refuse "the $VENDOR row's secret ref '$REF' is not one ref" ;; esac
case "$BASE" in
  https://*/) ;;
  *) refuse "the $VENDOR row's base URL is not https://<host>/<path>/ ending in /" ;;
esac
_host="${BASE#https://}"; _host="${_host%%/*}"
case "$_host" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*|.*|*..*) refuse "the $VENDOR row's base host '$_host' is not a DNS name (no port, no userinfo)" ;; esac
case "${BASE#https://}" in *[!A-Za-z0-9._~/-]*|*//*) refuse "the $VENDOR row's base URL holds a character it may not" ;; esac
case "$AUTH" in
  bearer) HNAME=Authorization; HPRE='Bearer ' ;;
  header:*) HNAME="${AUTH#header:}"; HPRE=''
    case "$HNAME" in ''|*[!A-Za-z0-9-]*) refuse "the $VENDOR row's header name '$HNAME' is not [A-Za-z0-9-]" ;; esac
    _hl="$(printf '%s' "$HNAME" | tr 'A-Z' 'a-z')"
    case "$_hl" in host|cookie|content-length|transfer-encoding|content-type|x-http-method-override|x-http-method|x-method-override)
      refuse "the $VENDOR row's header '$HNAME' is not an auth header" ;; esac ;;
  *) refuse "the $VENDOR row's auth '$AUTH' is not bearer or header:<Name>" ;;
esac
case "$TOKURL$CID$CREF" in
  ---) EXCHANGE=0 ;;
  *) EXCHANGE=1
     case "$TOKURL" in https://*/*) ;; *) refuse "the $VENDOR row's token URL is not https" ;; esac
     _th="${TOKURL#https://}"; _th="${_th%%/*}"
     case "$_th" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) refuse "the $VENDOR row's token host is not a DNS name" ;; esac
     case "${TOKURL#https://}" in *[!A-Za-z0-9._~/-]*) refuse "the $VENDOR row's token URL holds a character it may not" ;; esac
     case "$CID" in ''|-|*[!A-Za-z0-9._~-]*) refuse "the $VENDOR row's client id is not [A-Za-z0-9._~-]" ;; esac
     case "$CREF" in ''|-|*[!A-Za-z0-9._-]*) refuse "the $VENDOR row's client ref is not one ref" ;; esac
     [ "$CREF" != "$REF" ] || refuse "the $VENDOR row's client ref is its token ref" ;;
esac
if [ "$REDACT" != - ]; then
  jq -n --arg r "$REDACT" '"x" | test($r; "i")' >/dev/null 2>&1 || refuse "the $VENDOR row's redact regex does not compile in jq"
fi

# Denied globs first, then the allowed prefixes; a prefix is literal, a glob is a shell pattern. set -f: no file expansion.
set -f
_oifs="$IFS"; IFS=,
if [ "$DENY" != - ]; then
  for _g in $DENY; do
    [ -n "$_g" ] || continue
    # shellcheck disable=SC2254 # the table's glob is the pattern, unquoted on purpose
    case "$RP" in $_g) IFS="$_oifs"; refuse "path '$RP' matches the $VENDOR row's denied glob '$_g'" ;; esac
  done
fi
_ok=0
for _p in $ALLOW; do
  [ -n "$_p" ] && [ "$_p" != - ] || continue
  case "$RP" in "$_p"*) _ok=1; break ;; esac
done
IFS="$_oifs"; set +f
[ "$_ok" = 1 ] || refuse "path '$RP' starts with none of the $VENDOR row's allowed prefixes ($ALLOW)" "harbor access get --list"

URL="$BASE$RP${QS:+?$QS}"
command -v curl >/dev/null 2>&1 || fail "curl is not installed" "$(pkg_hint curl)" 2
command -v jq >/dev/null 2>&1 || fail "jq is not installed" "$(pkg_hint jq)" 2

umask 077
T="$(mktemp -d "${TMPDIR:-/tmp}/access-get.XXXXXX")" || fail "mktemp failed" "check TMPDIR" 1
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT TERM HUP

# Every check is done: only now is a credential read, always through secret run, into a 0600 file this run removes.
# The token lives in an unexported shell variable after that, so no child but curl (on stdin) ever sees it.
stash() { # <ref> <file>
  sh "$SRC/secret" run "$1" HARBOR_ACCESS_GET_STASH -- sh "$0" --stash "$2" \
    || fail "secret run could not read $1" "harbor access status" 1
}
TOKEN=''
if [ "$EXCHANGE" = 1 ]; then
  # A refresh-token row: the client secret and the refresh token reach access-oauth.sh as two 0600 files.
  stash "$CREF" "$T/cs"; stash "$REF" "$T/rt"
  _th="$(OA_GRANT=refresh_token OA_TOKEN_URL="$TOKURL" OA_AUTH=basic OA_CID="$CID" OA_RESP="$T/tok" OA_CSFILE="$T/cs" OA_RTFILE="$T/rt" \
    sh "$SRC/access-oauth.sh" --exchange)" || _th=000
  rm -f "$T/cs" "$T/rt"
  case "$_th" in
    200) TOKEN="$(jq -r '.access_token // empty | strings' "$T/tok" 2>/dev/null)" || TOKEN='' ;;
    badsecret) fail "the client secret or refresh token of $VENDOR is empty or holds a line break" "harbor access status" 1 ;;
  esac
  _keys="$(jq -r 'if type == "object" then (keys | join(",")) else type end' "$T/tok" 2>/dev/null || printf 'not JSON')"
  rm -f "$T/tok" "$T/tok.err"
  [ -n "$TOKEN" ] || fail "the $VENDOR token exchange returned HTTP $_th with no access_token (keys: ${_keys:-none})" "harbor access status   # is the refresh token alive?" 1
else
  stash "$REF" "$T/tok"
  IFS= read -r TOKEN < "$T/tok" || :
  rm -f "$T/tok"
fi
# A quote, backslash or line break would end the curl config line and start another directive.
case "$TOKEN" in ''|*[![:graph:]]*|*\"*|*\\*) TOKEN=''; fail "the $VENDOR credential is empty or holds a character a header value may not" "harbor access status" 1 ;; esac

# The one GET. env -i and -q: no curlrc, proxy, CA or key-log setting from the caller; --noproxy '*' and the system CA
# store. No -X, no data, no -L; --path-as-is sends the path exactly as it was checked.
_code="$( { printf 'header = "%s: %s%s"\n' "$HNAME" "$HPRE" "$TOKEN"
            printf 'header = "Accept: application/json"\n'
            printf 'user-agent = "harbor-access/1"\n'; } \
  | env -i PATH="$GET_PATH" HOME="$T" LC_ALL=C curl -q -sS --noproxy '*' --path-as-is --max-time "$TMO" --proto =https --max-redirs 0 -K - -o "$T/body" -w '%{http_code}' --url "$URL" 2>"$T/err")" || _code=000
TOKEN=''
log_note "GET $VENDOR $RP${QS:+ (+$NQ query)} -> http=$_code"

if [ "$_code" = 000 ]; then
  fail "the request did not complete: $(head -1 "$T/err" 2>/dev/null | cut -c1-160)" "check the network to $_host (outside the sandbox, if it is refused)" 1
fi
# The body, JSON only: a key the floor or the row's regex names, the value of a {name|key|field: <such>, value: …} pair
# and any JWT-shaped string are withheld; then the token-shape redactor.
_row=''; [ "$REDACT" = - ] || _row="$REDACT"
if ! jq --arg floor "$FLOOR" --arg exact "^($EXACT)\$" --arg row "$_row" '
    def norm: ascii_downcase | gsub("[-_. ]"; "");
    def named: type == "string" and ((norm | test($floor)) or (norm | test($exact)) or ($row != "" and test($row; "i")));
    def hold: if type == "string" and length > 0 then "[withheld " + (length | tostring) + " chars]"
              elif type == "object" or type == "array" then "[withheld]" else . end;
    def jwt: type == "string" and test("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.");
    walk(if type == "object" then
           (if has("value") and ((.name // .key // .field) | named) then .value |= hold else . end)
           | with_entries(if (.key | named) then .value |= hold else . end)
         elif jwt then "[withheld JWT]" else . end)' \
    "$T/body" > "$T/out" 2>/dev/null; then
  fail "the $VENDOR answer (http=$_code, $(wc -c < "$T/body" | tr -d ' ') bytes) is not JSON, so it is not printed" "check the path against the vendor's API reference" 1
fi
_rr=0; sh "$SRC/access-redact.sh" < "$T/out" || _rr=$?
[ "$_rr" = 0 ] || exit 3
case "$_code" in
  2??) log_end ;;
  401) fail "401: the $VENDOR credential was refused" "harbor access status   # then the entry's renew: recipe" 1 ;;
  403) fail "403: the credential works but may not read $RP" "the route card's reaches: line" 1 ;;
  *) fail "http=$_code from $VENDOR" "the body above is the vendor's own reason" 1 ;;
esac
