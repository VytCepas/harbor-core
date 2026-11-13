#!/usr/bin/env sh
# bin/access-mint.sh, `harbor access mint` (harbor#978): one OAuth code exchange driven by mint-vendors.tsv (contracts/access-mint.md).
# A temp HOME and private layer, the file-backed keychain stub and a curl stub first on PATH: no case reaches a vendor,
# the login Keychain or a real credential. The stub logs curl's argv and the header and body files it was handed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"; APPS="$PV/access/mint.tsv"; VEND="$PV/access/mint-vendors.tsv"
CS="$T_TMP/curl"; mkdir -p "$CS"; export CS
APPSECRET="appsecret-$(printf 'k%.0s' 1 2 3 4 5 6 7 8)"
CODE="code-$(printf 'c%.0s' 1 2 3 4 5 6)-one-time"
TOKEN="tok-$(printf 'z%.0s' 1 2 3 4 5 6 7 8 9)-longterm"
# a vendor-name flag only where the register asks for one (a later access.sh does, for kind token and app)
VN=''; grep -q -- '--vendor-name' "$T_ROOT/bin/access.sh" && VN=1
cat > "$T_BIN/curl" <<'STUB'
#!/bin/sh
d="${CS:?}"; : > "$d/argv"; out=''; prev=''
for a in "$@"; do
  printf '%s\n' "$a" >> "$d/argv"
  case "$prev" in -H) case "$a" in @*) cat "${a#@}" > "$d/hdr" ;; esac ;; --data-binary) cat "${a#@}" > "$d/body" ;; -o) out="$a" ;; esac
  prev="$a"
done
cp "$d/resp.json" "$out"; printf '%s' "$(cat "$d/code" 2>/dev/null || echo 200)"
STUB
chmod +x "$T_BIN/curl"
add_app() { # <entry> <ref> <vendor> — the app secret, registered and stored as any credential is
  set -- "$1" --kind app --what "a fixture app" --use-when "tests" --reaches "nothing" --cannot "anything" --grant "the suite" \
    --secret "$2" --value-stdin ${VN:+--vendor-name} ${VN:+"ACME API $3"}
  printf '%s' "$APPSECRET" | AX add "$@" > /dev/null 2>&1
}
stored() { sh "$T_ROOT/bin/secret" withfile "$1" -- cat '{}' 2>/dev/null; }
vendors() {
  { printf 'id\ttoken_url\tclient_auth\tbody\tid_field\tsecret_field\tcode_field\tfields\tstore\tok\treport\tlist\tnote\n'
    printf '%s\n' 'acme-json	https://api.example.com/open_api/v1/oauth2/access_token/	body	json	app_id	secret	auth_code	-	.data.access_token	.code == 0	"code=\(.code) message=\(.message) advertisers=\(.data.advertiser_ids // [] | length) scopes=\(.data.scope // [] | length)"	.data.advertiser_ids // [] | .[] | tostring	a JSON body carrying the app credentials'
    printf '%s\n' 'acme-form	https://api.example.org/v5/oauth/token	basic	form	-	-	code	grant_type=authorization_code&redirect_uri={redirect}	.refresh_token	(.refresh_token // "") != ""	"scope=\(.scope // .message) access_expires_s=\(.expires_in) refresh_expires_s=\(.refresh_token_expires_in)"	-	basic auth and a form body'
  } > "$VEND"
}
app_rows() {
  { printf 'provider\tclient_id\tsecret_ref\tredirect\tentry\tkind\tsecret\tvendor_name\twhat\tuse_when\treaches\tcannot\tgrant\n'
    printf 'acme-json\t7000000000000000001\tharbor-acmej-fixture-app\t-\tharbor-acmej-fixture-ads\ttoken\tharbor-acmej-fixture-ads\t%s\ta fixture token\ttests\tthe fixture advertisers\tanything else\tthe fixture consent\n' "${VN:+ACME API Acme}"
    printf 'acme-form\t1000001\tharbor-acmef-fixture-app\thttp://localhost:8000/callback\tharbor-acmef-fixture-ads\ttoken\tharbor-acmef-fixture-ads\t%s\ta fixture refresh token\ttests\tthe fixture accounts\tanything else\tthe fixture consent\n' "${VN:+ACME API Acme}"
  } | sed 's/\t\t/\t-\t/g' > "$APPS"
}
leaks() { # <where> — none of the three values is on curl's argv or in what the run printed
  for v in "$APPSECRET" "$CODE" "$TOKEN"; do case "$1" in *"$v"*) echo leaked; return; esac; done; echo clean
}
add_app harbor-acmej-fixture-app harbor-acmej-fixture-app Acme
add_app harbor-acmef-fixture-app harbor-acmef-fixture-app Acme
vendors; app_rows

t_section "a JSON-body vendor: the app secret and the code go in a JSON body file, the token is stored and never printed"
printf '{"code":0,"message":"OK","data":{"access_token":"%s","advertiser_ids":["111","222"],"scope":[1,2,3]}}' "$TOKEN" > "$CS/resp.json"
out="$(AX mint acme-json "$CODE" 2>&1)"; rc=$?
t_eq "the mint exits 0" 0 "$rc"
t_eq "the stored value is the token, byte for byte" "$TOKEN" "$(stored harbor-acmej-fixture-ads)"
t_has "the register has the entry" "$(cat "$REG")" '## harbor-acmej-fixture-ads'
t_has "the report line prints counts" "$out" 'acme-json http=200 code=0 message=OK advertisers=2 scopes=3'
t_has "the reach list prints the advertiser ids" "$out" 'reaches: 222'
t_eq "nothing printed carries the secret, the code or the token" clean "$(leaks "$out")"
t_eq "curl's argv carries none of them" clean "$(leaks "$(cat "$CS/argv")")"
t_has "the URL is the provider row's" "$(cat "$CS/argv")" 'https://api.example.com/open_api/v1/oauth2/access_token/'
t_eq "the body names the app, its secret and the code" "7000000000000000001|$APPSECRET|$CODE" "$(jq -r '"\(.app_id)|\(.secret)|\(.auth_code)"' "$CS/body")"
t_has "the body is sent as JSON" "$(cat "$CS/hdr")" 'Content-Type: application/json'
t_eq "no work file is left behind" 0 "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'access-mint.*' -newer "$CS/resp.json" 2>/dev/null | grep -c .)"

t_section "a basic-auth form vendor: basic auth in a header file, a form body, the refresh token stored"
printf '{"access_token":"short-lived","refresh_token":"%s","scope":"ads:read","expires_in":2592000,"refresh_token_expires_in":5184000}' "$TOKEN" > "$CS/resp.json"
out="$(printf '%s\n' "$CODE" | AX mint acme-form - 2>&1)"; rc=$?
t_eq "the mint with the code on stdin exits 0" 0 "$rc"
t_eq "the refresh token is what was stored" "$TOKEN" "$(stored harbor-acmef-fixture-ads)"
t_has "the header is Basic base64(app id:secret)" "$(cat "$CS/hdr")" "Authorization: Basic $(printf '1000001:%s' "$APPSECRET" | base64 | tr -d '\n')"
t_eq "the form body carries the grant, the code and the encoded redirect" "grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost%3A8000%2Fcallback&code=$CODE" "$(cat "$CS/body")"
t_has "the report prints scope and expiries" "$out" 'scope=ads:read access_expires_s=2592000 refresh_expires_s=5184000'
t_eq "nothing printed carries a value" clean "$(leaks "$out")"
t_eq "curl's argv carries none" clean "$(leaks "$(cat "$CS/argv")")"

t_section "a refused exchange stores nothing; an entry that exists goes through rotate, which needs a check to prove the value"
add_app harbor-acmej-other-app harbor-acmej-other-app Acme
sed -i.bak 's/^acme-json\t7000000000000000001\tharbor-acmej-fixture-app\t-\tharbor-acmej-fixture-ads\ttoken\tharbor-acmej-fixture-ads/acme-json\t7000000000000000001\tharbor-acmej-fixture-app\t-\tharbor-acmej-fresh-ads\ttoken\tharbor-acmej-fresh-ads/' "$APPS"
# a refusal that still carries a token field: only the provider's ok test can tell it from a success
printf '{"code":40001,"message":"auth_code expired","data":{"access_token":"not-a-grant"}}' > "$CS/resp.json"
out="$(AX mint acme-json "$CODE" 2>&1)"; rc=$?
t_eq "a vendor refusal exits 1" 1 "$rc"
t_has "...and says nothing was stored" "$out" 'nothing was stored'
t_hasnt "...and no entry was written" "$(cat "$REG")" 'harbor-acmej-fresh-ads'
mv -f "$APPS.bak" "$APPS"
printf '{"code":0,"message":"OK","data":{"access_token":"tok-second-%s","advertiser_ids":[]}}' "$APPSECRET" > "$CS/resp.json"
out="$(AX mint acme-json "$CODE" 2>&1)"; rc=$?
t_eq "a second mint into an entry with no check exits 1" 1 "$rc"
t_has "...because rotate cannot prove the new value" "$out" 'has no check:/expect:'
t_eq "...and the first token is still the stored one" "$TOKEN" "$(stored harbor-acmej-fixture-ads)"

t_section "a report line that would print the credential is withheld"
cp "$VEND" "$VEND.good"
awk -F'\t' -v OFS='\t' '$1 == "acme-json" { $11 = "\"leak=\\(.data.access_token)\"" } { print }' "$VEND.good" > "$VEND"
t_has "the fixture row really prints the token" "$(cat "$VEND")" 'leak=\(.data.access_token)'
sed -i.bak 's/harbor-acmej-fixture-ads/harbor-acmej-leak-ads/g' "$APPS"
printf '{"code":0,"message":"OK","data":{"access_token":"%s","advertiser_ids":[]}}' "$TOKEN" > "$CS/resp.json"
out="$(AX mint acme-json "$CODE" 2>&1)"
t_has "the line is withheld and the run says why" "$out" 'would have printed the credential, so it is withheld'
t_eq "and the token is not in the output" clean "$(leaks "$out")"
cp "$VEND.good" "$VEND"
mv -f "$APPS.bak" "$APPS"

t_section "rows are checked before they reach a URL, a header or the register"
t_exit "an unknown provider is a usage error" 2 sh "$T_ROOT/bin/access.sh" mint nosuch "$CODE"
sed 's#https://api.example.com#http://api.example.com#' "$VEND.good" > "$VEND"
t_exit "a token_url that is not https is refused" 2 sh "$T_ROOT/bin/access.sh" mint acme-json "$CODE"
cp "$VEND.good" "$VEND"
mv "$APPS" "$APPS.off"
t_exit "no app row on this box is refused" 2 sh "$T_ROOT/bin/access.sh" mint acme-json "$CODE"
mv "$APPS.off" "$APPS"
mv "$VEND" "$VEND.off"
t_exit "no vendor table on this box is refused" 2 sh "$T_ROOT/bin/access.sh" mint acme-json "$CODE"
mv "$VEND.off" "$VEND"
t_exit "an empty code is refused" 2 sh -c "printf '' | sh '$T_ROOT/bin/access.sh' mint acme-json -"
t_has "--list names each provider and whether this box has its app" "$(AX mint --list)" "acme-form$(printf '\t')app row: yes"

t_done
