#!/usr/bin/env sh
# access-mint.sh (harbor#978) - `harbor access mint <provider> <code|->`: one OAuth code-for-credential exchange for every vendor.
#
#   harbor access mint <provider> <code>   exchange the one-time code, store what comes back through the access register
#   harbor access mint <provider> -        the same, the code read from stdin (so it is never an argument at all)
#   harbor access mint --list              the vendors this box knows, and whether each has an app row
#
# THE TWO ROWS, both in the access register's folder (scope-roots.sh --access); contracts/access-mint.md is their format.
# A row of mint-vendors.tsv is the vendor's protocol: its token endpoint, how the app authenticates, the body, which response
# field is the credential and what may print. A row of mint.tsv is the company's app: its id, the secret ref holding its
# secret, the redirect URI, and the register entry the credential becomes. Core names no vendor and no company value.
#
# NEVER PRINTED, NEVER AN ARGUMENT. The app secret comes from bin/secret as a 0600 file (`withfile`), the code and the
# body sit in 0600 files in a 0700 folder, and curl reads its header and body from those files (-H @file, --data-binary
# @file): no secret, code or credential is on any argv or in a URL. The credential goes from the response file to
# `harbor access add|rotate --value-stdin` on a pipe. The report line is the provider's jq of counts and expiries, and it is
# refused when it contains the stored value. The response body is never printed.
#
# STORED THROUGH THE REGISTER. A new entry is `harbor access add` with the app row's register fields; an entry that exists
# is `harbor access rotate`, which keeps the new value only when the entry's check passes on it.
#
# exit 0 stored · 1 the vendor refused or the store failed · 2 usage, a missing or malformed row
set -eu
LC_ALL=C; export LC_ALL

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init access-mint
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
TAB="$(printf '\t')"

fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

command -v jq > /dev/null 2>&1 || fail "jq is not on PATH, and every row here is a jq expression" "$(pkg_hint jq)" 2
command -v curl > /dev/null 2>&1 || fail "curl is not on PATH" "$(pkg_hint curl)" 2

ACCESS_DIR="$(sh "$SRC/scope-roots.sh" --access 2>/dev/null)" || ACCESS_DIR=""
APPS="${ACCESS_DIR:+$ACCESS_DIR/mint.tsv}"
# Which vendors exist is workload knowledge (harbor#1273, lint.domain): core carries the exchange and the format, never a vendor.
PROVIDERS="${ACCESS_DIR:+$ACCESS_DIR/mint-vendors.tsv}"

# row <file> <id> → the row whose first column is id, `#` lines and the header skipped
row() { awk -F'\t' -v i="$2" '/^#/ || $1 == "id" || $1 == "provider" { next } $1 == i { print; exit }' "$1"; }

[ $# -ge 1 ] || usage
if [ "$1" = --list ]; then
  [ -n "$PROVIDERS" ] && [ -f "$PROVIDERS" ] || fail "no mint-vendors.tsv in the access register's folder" "add one: contracts/access-mint.md" 2
  awk -F'\t' -v apps="${APPS:-/dev/null}" 'BEGIN { while ((getline l < apps) > 0) { split(l, a, "\t"); if (l !~ /^#/ && a[1] != "provider") have[a[1]] = 1 } }
    /^#/ || $1 == "id" { next } { printf "%s\t%s\n", $1, (($1 in have) ? "app row: yes" : "app row: none on this box") }' "$PROVIDERS"
  exit 0
fi
case "$1" in -h|--help|help) usage ;; esac
[ $# -eq 2 ] || usage
P="$1"; CODE_ARG="$2"
case "$P" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) fail "provider '$P' is not a lowercase kebab id" "harbor access mint --list" 2 ;; esac

[ -n "$PROVIDERS" ] && [ -f "$PROVIDERS" ] || fail "no mint-vendors.tsv in the access register's folder" "add one: contracts/access-mint.md" 2
PROW="$(row "$PROVIDERS" "$P")"
[ -n "$PROW" ] || fail "mint-vendors.tsv has no provider '$P'" "harbor access mint --list" 2
[ -n "$APPS" ] && [ -f "$APPS" ] || fail "no app row: $([ -n "$ACCESS_DIR" ] && printf '%s/mint.tsv does not exist' "$ACCESS_DIR" || printf 'there is no access register folder')" \
  "add a '$P' row to mint.tsv in the access register's folder (contracts/access-mint.md)" 2
AROW="$(row "$APPS" "$P")"
[ -n "$AROW" ] || fail "$APPS has no row for '$P'" "add one (contracts/access-mint.md)" 2

col() { printf '%s\n' "$1" | cut -f"$2"; }
URL="$(col "$PROW" 2)"; AUTH="$(col "$PROW" 3)"; BODY="$(col "$PROW" 4)"; IDF="$(col "$PROW" 5)"; SECF="$(col "$PROW" 6)"
CODEF="$(col "$PROW" 7)"; FIELDS="$(col "$PROW" 8)"; STORE="$(col "$PROW" 9)"; OK="$(col "$PROW" 10)"; REPORT="$(col "$PROW" 11)"; LIST="$(col "$PROW" 12)"
CID="$(col "$AROW" 2)"; SREF="$(col "$AROW" 3)"; REDIR="$(col "$AROW" 4)"; ENTRY="$(col "$AROW" 5)"; KIND="$(col "$AROW" 6)"; REF="$(col "$AROW" 7)"
VNAME="$(col "$AROW" 8)"; WHAT="$(col "$AROW" 9)"; USEW="$(col "$AROW" 10)"; REACH="$(col "$AROW" 11)"; CANNOT="$(col "$AROW" 12)"; GRANT="$(col "$AROW" 13)"

# The rows are data a person wrote: each value is checked before it reaches a URL, a header or the register.
case "$URL" in https://*) ;; *) fail "provider '$P': token_url '$URL' is not https" "fix its row in $PROVIDERS" 2 ;; esac
case "$URL" in *[!A-Za-z0-9._~:/?\&=%-]*) fail "provider '$P': token_url holds a character a URL here may not" "fix its row in $PROVIDERS" 2 ;; esac
case "$AUTH" in basic|body) ;; *) fail "provider '$P': client_auth is '$AUTH', not basic or body" "fix its row in $PROVIDERS" 2 ;; esac
case "$BODY" in json|form) ;; *) fail "provider '$P': body is '$BODY', not json or form" "fix its row in $PROVIDERS" 2 ;; esac
case "$CID" in ''|-|*[!A-Za-z0-9._-]*) fail "the '$P' app row's client_id '$CID' is not [A-Za-z0-9._-]" "fix it in $APPS" 2 ;; esac
case "$SREF" in ''|-|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*) fail "the '$P' app row's secret_ref '$SREF' is not a secret ref" "fix it in $APPS" 2 ;; esac
case "$ENTRY" in ''|-|*[!abcdefghijklmnopqrstuvwxyz0-9._-]*) fail "the '$P' app row's entry '$ENTRY' is not an entry id" "fix it in $APPS" 2 ;; esac
case "$REF" in ''|-|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*) fail "the '$P' app row's secret '$REF' is not a secret ref" "fix it in $APPS" 2 ;; esac
case "$REDIR" in -|https://*|http://localhost[:/]*|http://127.0.0.1[:/]*) ;; *) fail "the '$P' app row's redirect '$REDIR' is not https, a loopback http URL or -" "fix it in $APPS" 2 ;; esac
case "$FIELDS" in *'{redirect}'*) [ "$REDIR" != - ] || fail "provider '$P' sends a redirect URI and the app row has none" "set redirect in $APPS to the one registered on the vendor's app" 2 ;; esac

W="$(mktemp -d "${TMPDIR:-/tmp}/access-mint.XXXXXX")" || exit 2
chmod 700 "$W"
trap 'rm -rf "$W"' EXIT
trap 'rm -rf "$W"; trap - EXIT; exit 130' INT TERM HUP
umask 077

# The code: one line, from the argument or from stdin, into a file.
if [ "$CODE_ARG" = - ]; then cat > "$W/code.raw"; else printf '%s' "$CODE_ARG" > "$W/code.raw"; fi
CODE_ARG=''
tr -d ' \t\r\n' < "$W/code.raw" > "$W/code"; rm -f "$W/code.raw"
[ -s "$W/code" ] || fail "the code is empty" "pass the code the vendor's redirect gave you, or - and pipe it in" 2

# The app secret: bin/secret materialises it to a 0600 path for one cp, as every reader of a file-shaped secret does.
sh "$SRC/secret" withfile "$SREF" -- cp '{}' "$W/secret.raw" > /dev/null 2> "$W/secret.err" \
  || fail "the app secret '$SREF' could not be read: $(head -n 1 "$W/secret.err")" "harbor access status; store it with harbor access add" 1
tr -d '\r\n' < "$W/secret.raw" > "$W/secret"; rm -f "$W/secret.raw"
[ -s "$W/secret" ] || fail "the app secret '$SREF' is empty" "harbor access rotate <its entry> --value-stdin" 1

# The body as one JSON object: the fixed fields, the code, and for client_auth body the app id and secret.
printf '%s' "$FIELDS" | awk -v r="$REDIR" 'BEGIN { RS = "&" } $0 != "" && $0 != "-" { k = $0; sub(/=.*/, "", k); v = $0; sub(/^[^=]*=/, "", v); gsub(/\{redirect\}/, r, v); printf "%s\t%s\n", k, v }' > "$W/fields"
jq -n --rawfile code "$W/code" --rawfile sec "$W/secret" --rawfile fx "$W/fields" --arg cf "$CODEF" --arg auth "$AUTH" --arg idf "$IDF" --arg sf "$SECF" --arg cid "$CID" '
  ($fx | split("\n") | map(select(. != "") | split("\t") | {(.[0]): .[1]}) | add // {})
  + {($cf): $code}
  + (if $auth == "body" then {($idf): $cid, ($sf): $sec} else {} end)' > "$W/body.json" \
  || fail "the body for '$P' could not be built" "check the provider row's fields, id_field and secret_field" 2
: > "$W/hdr"
if [ "$BODY" = json ]; then
  jq -c . "$W/body.json" > "$W/body"; printf 'Content-Type: application/json\n' >> "$W/hdr"
else
  jq -r 'to_entries | map("\(.key)=\(.value | @uri)") | join("&")' "$W/body.json" > "$W/body"
  printf 'Content-Type: application/x-www-form-urlencoded\n' >> "$W/hdr"
fi
rm -f "$W/body.json"
if [ "$AUTH" = basic ]; then
  { printf 'Authorization: Basic '; { printf '%s:' "$CID"; cat "$W/secret"; } | base64 | tr -d '\n'; printf '\n'; } >> "$W/hdr"
fi
rm -f "$W/secret" "$W/code"

HTTP="$(curl -sS --max-time 30 -H @"$W/hdr" --data-binary @"$W/body" -o "$W/resp" -w '%{http_code}' "$URL" 2> "$W/curl.err")" || HTTP=000
rm -f "$W/hdr" "$W/body"
[ -s "$W/resp" ] && jq -e . "$W/resp" > /dev/null 2>&1 || fail "$P answered http $HTTP with no JSON body$( [ -s "$W/curl.err" ] && printf ' (curl: %s)' "$(head -n 1 "$W/curl.err")")" "check the network, then mint again with a fresh code" 1

# The credential, to a file; the report is checked against it before it prints.
jq -j "$STORE // empty" "$W/resp" > "$W/value" 2> /dev/null || : > "$W/value"
jq -r "$REPORT" "$W/resp" > "$W/report" 2> /dev/null || printf 'the report expression of %s did not read the response\n' "$P" > "$W/report"
if [ -s "$W/value" ] && awk 'FNR == NR { v = v $0; next } index($0, v) { bad = 1 } END { exit !bad }' "$W/value" "$W/report"; then
  log_warn "the report line of '$P' would have printed the credential, so it is withheld"
else log_note "$P http=$HTTP $(head -n 1 "$W/report")"; fi
jq -e "$OK" "$W/resp" > /dev/null 2>&1 || fail "$P refused the exchange (http $HTTP): nothing was stored" "a code is single use and short-lived: open the consent link again and mint with the new code" 1
[ -s "$W/value" ] || fail "$P answered ok but '$STORE' is empty: nothing was stored" "fix the provider row's store path in $PROVIDERS" 1
if [ "$LIST" != - ]; then
  jq -r "$LIST" "$W/resp" > "$W/list" 2> /dev/null || : > "$W/list"
  if awk 'FNR == NR { v = v $0; next } index($0, v) { bad = 1 } END { exit !bad }' "$W/value" "$W/list"; then log_warn "the reach list of '$P' would have printed the credential, so it is withheld"
  else while IFS= read -r _l; do log_note "reaches: $_l"; done < "$W/list"; fi
fi

# Stored through the register: rotate an entry that exists, add one that does not.
if sh "$SRC/access.sh" list 2>/dev/null | awk -F'\t' -v i="$ENTRY" '$1 == i { f = 1 } END { exit !f }'; then
  sh "$SRC/access.sh" rotate "$ENTRY" --value-stdin < "$W/value" || fail "the new value for '$ENTRY' was not kept" "harbor access status $ENTRY" 1
else
  set -- add "$ENTRY" --kind "$KIND" --what "$WHAT" --use-when "$USEW" --reaches "$REACH" --cannot "$CANNOT" --grant "$GRANT" --secret "$REF" --value-stdin
  [ "$VNAME" = - ] || [ -z "$VNAME" ] || set -- "$@" --vendor-name "$VNAME"
  sh "$SRC/access.sh" "$@" < "$W/value" || fail "'$ENTRY' was not stored" "harbor access check" 1
fi
rm -f "$W/value"
log_ok "minted '$P' into the register entry '$ENTRY' (secret $REF); the value was never printed"
log_end || :
