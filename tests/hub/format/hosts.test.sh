#!/usr/bin/env sh
# hosts.test.sh (harbor#1278) — policy `hosts`, the hosts a hub adds to its members' sandbox allowlist: one host each, never wider than one
# `*.` prefix, never a bare `*`, and never a row that admits a support relay. Checked by bin/hub-format.sh against contracts/hub.md.
. "$(dirname "$0")/../../lib/core.sh"; t_init
F="$T_ROOT/bin/hub-format.sh"; P="$T_ROOT/tests/hub/fixtures/policy.json"
K='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICiecex8Dq718eSe1CCLgLvDmI7AagvCtax7brPFWkh4'
pol() { # <jq edit>: exit of the validator
  jq --arg k "$K" "$1" "$P" > "$T_TMP/p.json"
  sh "$F" policy "$T_TMP/p.json" >/dev/null 2>"$T_TMP/err"; echo $?
}
accepts() { t_eq "$1" 0 "$(pol "$2")"; }
rejects() { t_eq "$1" 1 "$(pol "$2")"; }

t_section "1 - optional, and a closed key"
accepts "absent is fine: the core and member lists alone" '.'
accepts "a host" '.hosts = ["pypi.example-company.com"]'
accepts "a host with one *. prefix" '.hosts = ["*.internal.example-company.com"]'
accepts "an empty list" '.hosts = []'
accepts "200 hosts" '.hosts = [range(200) | "h\(.).example.com"]'
rejects "201 hosts" '.hosts = [range(201) | "h\(.).example.com"]'
rejects "not a list" '.hosts = "pkg.example.com"'

t_section "2 - never wider than one *. prefix"
for _h in '*' '*.*' '*.com' '*.*.example.com' 'a.*.example.com' 'example' 'Example.com' 'a b.com' 'a.com/x' 'https://a.com' 'a.com:443' '' '.a.com' 'a.com.'; do
  rejects "refused: '$_h'" ".hosts = [\"$_h\"]"
done
rejects "a second line smuggled in" '.hosts = ["a.com\n*"]'
rejects "a number" '.hosts = [1]'
rejects "the same host twice" '.hosts = ["a.example.com", "a.example.com"]'
t_has "and it names the rule" "$(pol '.hosts = ["*"]' >/dev/null; cat "$T_TMP/err")" 'never a bare *'

t_section "3 - never a row that admits a support relay"
rejects "the public relay" '.hosts = ["uptermd.upterm.dev"]'
rejects "a wildcard over the public relay" '.hosts = ["*.upterm.dev"]'
rejects "the hub relay" '.support = {keys: [$k], relay: "wss://relay.example.com", relay_key: $k} | .hosts = ["relay.example.com"]'
rejects "a wildcard over the hub relay, its port aside" '.support = {keys: [$k], relay: "wss://relay.example.com:8443", relay_key: $k} | .hosts = ["*.example.com"]'
accepts "CONTROL: a neighbour of the hub relay" '.support = {keys: [$k], relay: "wss://relay.example.com", relay_key: $k} | .hosts = ["pkg.example.com", "*.pkg.example.com"]'
t_done
