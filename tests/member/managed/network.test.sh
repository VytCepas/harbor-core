#!/usr/bin/env sh
# network.test.sh (harbor#1278) — the member network is an allowlist widened on demand: no composed output opens it, policy hosts are
# checked one by one, no allowed row admits a support relay, and every row of contracts/member-hosts.txt says why it is there.
. "$(dirname "$0")/../../lib/core.sh"; t_init
M="$T_ROOT/bin/member-managed.sh"; H="$T_ROOT/contracts/member-hosts.txt"
compose() { HARBOR_MEMBER_OS="${OSX:-WSL}" sh "$M" --hub fixture-org/fixture-hub --login alice --root /r "$@" 2>"$T_TMP/err"; }
# open_rows: every allow rule or host in the composed output that opens the network wide, one per line.
open_rows() { jq -r '[(.permissions.allow // [])[] | select(test("^WebFetch\\(domain:\\*\\)$"))] + [.sandbox.network.allowedDomains[] | select(. == "*" or test("^\\*\\.?[^.]*$"))] | .[]'; }
PUB="$(awk -F'\t' '$1 == "public-relay" { print $2 }' "$T_ROOT/contracts/support-upterm.tsv")"

t_section "1 - nothing composed in the default mode opens the network"
for OSX in WSL Linux Darwin; do
  for _args in '' '--deny-host relay.example.com' '--allow-host pkg.example.com --allow-host *.corp.example --deny-host relay.example.com'; do
    # shellcheck disable=SC2086 # the arguments are a word list by design; the *. row is quoted by set -f
    set -f; compose $_args > "$T_TMP/m.json"; _rc=$?; set +f
    t_eq "$OSX [$_args] composes" 0 "$_rc"
    t_eq "$OSX [$_args]: no WebFetch(domain:*), no bare or top-level * host" '' "$(open_rows < "$T_TMP/m.json")"
    t_has "$OSX [$_args]: the public relay is denied" "$(jq -r '.sandbox.network.deniedDomains[]' "$T_TMP/m.json")" "$PUB"
    t_eq "$OSX [$_args]: and no allowed row admits it" 0 "$(jq --arg h "$PUB" '[.sandbox.network.allowedDomains[] | . as $r | select($r == $h or (($r | startswith("*.")) and ($h | endswith($r[1:]))))] | length' "$T_TMP/m.json")"
  done
done
OSX=WSL
compose > "$T_TMP/m.json"
t_eq "CONTROL: the open mode is caught by the same check" 'WebFetch(domain:*)' \
  "$(env HARBOR_DEPLOY_CONFINEMENT_OS=Linux MEMBER_MANAGED_LIB=1 sh -c '. "$0"; MEMBER_NETWORK=open; member_compose WSL /r o/n alice "" "[]"' "$M" 2>/dev/null | open_rows)"
t_eq "CONTROL: so is a bare * host" '*' "$(jq '.sandbox.network.allowedDomains += ["*"]' "$T_TMP/m.json" | open_rows)"

t_section "2 - the member list lands, after core's"
_core="$(HARBOR_DEPLOY_CONFINEMENT_OS=Linux sh "$T_ROOT/bin/deploy-confinement.sh" --compose --member | jq -c .network.allowedDomains)"
t_eq "core's rows come first and unchanged" "$_core" "$(jq -c --argjson c "$_core" '.sandbox.network.allowedDomains[0:($c | length)]' "$T_TMP/m.json")"
for _h in registry.npmjs.org nodejs.org archive.ubuntu.com security.ubuntu.com release-assets.githubusercontent.com; do
  t_has "member host $_h" "$(jq -r '.sandbox.network.allowedDomains[]' "$T_TMP/m.json")" "$_h"
done
t_eq "no host twice" "$(jq '.sandbox.network.allowedDomains | length' "$T_TMP/m.json")" "$(jq '.sandbox.network.allowedDomains | unique | length' "$T_TMP/m.json")"
compose --allow-host pkg.example.com > "$T_TMP/p.json"
t_has "a policy host lands" "$(jq -r '.sandbox.network.allowedDomains[]' "$T_TMP/p.json")" pkg.example.com
t_eq "and nothing but the allowlist changes" "$(jq -S 'del(.sandbox.network.allowedDomains)' "$T_TMP/m.json")" "$(jq -S 'del(.sandbox.network.allowedDomains)' "$T_TMP/p.json")"

t_section "3 - a policy host is one host, never wider than one *. prefix"
for _h in '*' '*.*.example.com' '*.com' 'example' 'Example.com' 'a b.com' 'a.com/x' '' "$(printf 'a.com\n*')" 'https://a.com'; do
  _rc=0; compose --allow-host "$_h" > /dev/null || _rc=$?
  t_eq "refused: '$_h'" 2 "$_rc"
done
for _h in '*.upterm.dev' "$PUB"; do
  _rc=0; compose --allow-host "$_h" > /dev/null || _rc=$?
  t_eq "refused, it admits the public relay: '$_h'" 1 "$_rc"
done
for _h in '*' '*.com'; do
  t_exit "the composer checks a host too, not only the flag parser: '$_h'" 1 env HARBOR_DEPLOY_CONFINEMENT_OS=Linux MEMBER_MANAGED_LIB=1 \
    sh -c '. "$0"; member_compose WSL /r o/n alice "" "[]" "" "$1"' "$M" "$_h"
done
t_exit "CONTROL: the same call with a good host composes" 0 env HARBOR_DEPLOY_CONFINEMENT_OS=Linux MEMBER_MANAGED_LIB=1 \
  sh -c '. "$0"; member_compose WSL /r o/n alice "" "[]" "" pkg.example.com >/dev/null' "$M"
_rc=0; compose --deny-host relay.example.com --allow-host '*.example.com' > /dev/null || _rc=$?
t_eq "refused, it admits the hub's own relay" 1 "$_rc"
t_has "and it says which row" "$(cat "$T_TMP/err")" '*.example.com'
_rc=0; compose --deny-host relay.example.com --allow-host '*.example.org' > /dev/null || _rc=$?
t_eq "CONTROL: a wildcard beside the relay, not over it, composes" 0 "$_rc"

t_section "4 - contracts/member-hosts.txt: every row a host, and every row under a comment"
_rows="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$H")"
t_eq "every row has the allowedDomains shape" '' "$(printf '%s\n' "$_rows" | awk 'length($0) > 253 || $0 !~ /^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$/')"
t_eq "no row says why on no line above it" '' "$(awk '/^#/ { c = 1; next } /^[[:space:]]*$/ { c = 0; next } { if (!c) print; }' "$H")"
t_eq "no row repeats core's list" '' "$(printf '%s\n' "$_rows" | while IFS= read -r _r; do grep -qxF "$_r" "$T_ROOT/contracts/confinement-hosts.txt" && printf '%s\n' "$_r"; done)"
for _h in raw.githubusercontent.com gist.githubusercontent.com '*.githubusercontent.com'; do
  t_eq "arbitrary-content host left out: $_h" 0 "$(printf '%s\n' "$_rows" | grep -cxF "$_h" || :)"
done
t_done
