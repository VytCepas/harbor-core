#!/usr/bin/env sh
# relay.test.sh (harbor#1278) — relay/install.sh against a temp root: uptermd by digest only, one host key kept for good, settings on loopback,
# and a unit that runs it as nobody in particular. The real binary on loopback, and systemd-analyze, are in tests/member/support/real-upterm.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; *) ARCH=arm64 ;; esac
# A copy of relay/ with a pin beside it whose digest is a stand-in archive's, so nothing is downloaded.
R="$T_TMP/relay"; mkdir -p "$R" "$T_TMP/rel" "$T_TMP/from"
cp "$T_ROOT/relay/install.sh" "$T_ROOT/relay/relay.service" "$T_ROOT/relay/relay-settings.txt" "$T_ROOT/relay/proxy.txt" "$R/"
printf '#!/bin/sh\necho stand-in uptermd\n' > "$T_TMP/rel/uptermd"; chmod +x "$T_TMP/rel/uptermd"
tar -czf "$T_TMP/from/uptermd_linux_$ARCH.tar.gz" -C "$T_TMP/rel" uptermd
_d="$( { sha256sum "$T_TMP/from/uptermd_linux_$ARCH.tar.gz" 2>/dev/null || shasum -a 256 "$T_TMP/from/uptermd_linux_$ARCH.tar.gz"; } | cut -d' ' -f1)"
sed -e "s/^uptermd-linux-$ARCH\t.*/uptermd-linux-$ARCH\t$_d/" "$T_ROOT/contracts/support-upterm.tsv" > "$R/support-upterm.tsv"
V="$T_TMP/vm"
inst() { RC=0; sh "$R/install.sh" --root "$V" --from "$T_TMP/from" "$@" > "$T_TMP/out" 2>&1 || RC=$?; }
mode() { ls -l "$1" | cut -c1-10; }
E="$V/etc/harbor-relay"

t_section "1 - the files land, from the pinned archive"
inst --host relay.example.com
t_eq "it installs" 0 "$RC"
t_eq "the binary is the archive's" 'stand-in uptermd' "$("$V/usr/local/bin/uptermd")"
t_eq "and runs for anyone" '-rwxr-xr-x' "$(mode "$V/usr/local/bin/uptermd")"
t_eq "the unit lands under its harbor name" yes "$([ -f "$V/etc/systemd/system/harbor-relay.service" ] && echo yes || echo no)"
t_eq "the private host key is the owner's alone" '-rw-------' "$(mode "$E/host_key")"
t_has "the settings name the relay" "$(cat "$E/relay.env")" 'UPTERMD_HOSTNAME=relay.example.com'
t_has "and so does Caddy's site" "$(cat "$V/etc/caddy/Caddyfile")" 'relay.example.com {'
t_eq "no placeholder is left" 0 "$(grep -c '@RELAY_HOST@' "$E/relay.env" "$V/etc/caddy/Caddyfile" | awk -F: '{ s += $2 } END { print s }')"
t_has "it prints the policy lines" "$(cat "$T_TMP/out")" 'relay: wss://relay.example.com'

t_section "2 - the key the laptops pin, and that it stays"
KEY="$(sh "$R/install.sh" --root "$V" --key | head -n 1)"
jq --arg k "$KEY" '.support = {keys: [$k], relay: "wss://relay.example.com", relay_key: $k}' "$T_ROOT/tests/hub/fixtures/policy.json" > "$T_TMP/policy.json"
t_exit "--key prints what policy relay_key takes" 0 sh "$T_ROOT/bin/hub-format.sh" policy "$T_TMP/policy.json"
t_has "and its fingerprint, to compare by eye" "$(sh "$R/install.sh" --root "$V" --key)" 'SHA256:'
inst --host relay.example.com
t_eq "a second install keeps the same key: a new one would mean a policy re-sign" "$KEY" "$(sh "$R/install.sh" --root "$V" --key | head -n 1)"

t_section "3 - refusals, before anything is written"
V="$T_TMP/vm2"
# With the good archive, so each refusal is its own and not the digest's.
for _h in uptermd.upterm.dev eu.uptermd.upterm.dev; do
  inst --host "$_h"; t_eq "the public relay is never installed as ours: $_h" 1 "$RC"
  t_has "and it says so" "$(cat "$T_TMP/out")" "public relay"
done
for _h in '' Relay.example.com relay -relay.example.com relay..example.com '*.example.com' 'relay.example.com;x' .example.com; do
  inst --host "$_h"; t_eq "not a host name: '$_h'" 2 "$RC"
done
if [ "$(id -u)" -ne 0 ]; then
  _rc=0; sh "$R/install.sh" --host relay.example.com --from "$T_TMP/from" > "$T_TMP/out" 2>&1 || _rc=$?
  t_eq "a real install needs root" 1 "$_rc"
  t_has "and says so" "$(cat "$T_TMP/out")" 'as root'
fi
printf 'not the release\n' > "$T_TMP/rel/uptermd"; tar -czf "$T_TMP/from/uptermd_linux_$ARCH.tar.gz" -C "$T_TMP/rel" uptermd
inst --host relay.example.com
t_eq "an archive that isn't the pinned one is refused" 1 "$RC"
t_has "and it says why" "$(cat "$T_TMP/out")" 'not the pinned one'
t_eq "none of them wrote anything" no "$([ -e "$V" ] && echo yes || echo no)"
# install.sh pins its own PATH, so no stub reaches its download: the time limit is read from the call itself.
t_has "the download has a time limit, so a stalled release host can't hang the install" "$(grep -n 'curl -q' "$R/install.sh")" '--max-time'

t_section "4 - what the unit and its settings allow"
U="$T_ROOT/relay/relay.service"; S="$T_ROOT/relay/relay-settings.txt"
t_eq "a dynamic user, never a named or root one" 'DynamicUser=yes' "$(grep -E '^(DynamicUser|User)=' "$U")"
t_has "it reaches loopback only" "$(grep '^IPAddress' "$U")" 'IPAddressDeny=any'
t_eq "and nothing else is allowed" 'IPAddressAllow=localhost' "$(grep '^IPAddressAllow=' "$U")"
t_eq "no capability at all" 'CapabilityBoundingSet=' "$(grep '^CapabilityBoundingSet' "$U")"
t_has "the key comes in as a credential, so the file stays root's" "$(grep '^ExecStart=' "$U")" '--private-key %d/host_key'
t_has "from the file the install writes" "$(grep '^LoadCredential=' "$U")" '/etc/harbor-relay/host_key'
t_has "and the settings from the env it writes" "$(grep '^EnvironmentFile=' "$U")" '/etc/harbor-relay/relay.env'
t_eq "every listener is on loopback" 0 "$(grep -E '^UPTERMD_[A-Z_]*ADDR=' "$S" | grep -vc '=127\.0\.0\.1:')"
t_eq "there are three" 3 "$(grep -cE '^UPTERMD_[A-Z_]*ADDR=' "$S")"
_ws="$(sed -n 's/^UPTERMD_WS_ADDR=//p' "$S")"
t_has "Caddy passes to the websocket listener, not elsewhere" "$(grep reverse_proxy "$T_ROOT/relay/proxy.txt")" "reverse_proxy $_ws"
t_eq "the public relay is named nowhere in relay/" 0 "$(cat "$T_ROOT"/relay/* | grep -c 'upterm.dev' || :)"
t_done
