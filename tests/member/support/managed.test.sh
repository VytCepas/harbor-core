#!/usr/bin/env sh
# managed.test.sh (harbor#1278) — the relay is closed to the agent's shell: denied in the composed managed settings, and never an allowed host.
. "$(dirname "$0")/../../lib/core.sh"; t_init
M="$T_ROOT/bin/member-managed.sh"
compose() { HARBOR_MEMBER_OS=Linux sh "$M" --hub fixture-org/fixture-hub --login alice --root /r "$@" 2>/dev/null; }
denied() { jq -r '.sandbox.network.deniedDomains[]' | tr '\n' ' '; }
RELAY="$(awk -F'\t' '$1 == "public-relay" { print $2 }' "$T_ROOT/contracts/support-upterm.tsv")"

t_section "1 - the public relay, never used and always denied"
t_eq "the pin names the public one" uptermd.upterm.dev "$RELAY"
t_eq "and no relay to use: there is no default (contracts/hub.md)" 0 "$(grep -cE '^(relay|relay-key)	' "$T_ROOT/contracts/support-upterm.tsv" || :)"
t_eq "it is in deniedDomains in what the install writes" "$RELAY " "$(compose | denied)"
t_eq "and the allow list is the confinement's own, with no relay in it" 0 "$(compose | jq --arg h "$RELAY" '[.sandbox.network.allowedDomains[] | . as $a | select($a == $h or (($a | startswith("*.")) and ($h | endswith($a[1:]))))] | length')"
t_eq "the core host list never names it" 0 "$(grep -c "$RELAY" "$T_ROOT/contracts/confinement-hosts.txt" || :)"
t_eq "it isn't reached by a wildcard row either" 0 "$(grep -c 'upterm' "$T_ROOT/contracts/confinement-hosts.txt" || :)"
t_eq "nor by the member host list" 0 "$(sed 's/#.*//' "$T_ROOT/contracts/member-hosts.txt" | grep -c 'upterm' || :)"

t_section "2 - the hub's own relay, written at install"
t_eq "--deny-host adds it, and the public one stays" "relay.example $RELAY " "$(compose --deny-host relay.example | denied)"
t_eq "the same host twice is one row" "$RELAY " "$(compose --deny-host "$RELAY" | denied)"
_rc=0; compose --deny-host 'x y' >/dev/null || _rc=$?
t_eq "a host with a space is refused" 2 "$_rc"
_rc=0; compose --deny-host 'X";' >/dev/null || _rc=$?
t_eq "and anything that isn't a host name" 2 "$_rc"

t_section "3 - the agent has no unsandboxed way round"
t_eq "the retry stays closed for a member" false "$(compose | jq .sandbox.allowUnsandboxedCommands)"
t_done
