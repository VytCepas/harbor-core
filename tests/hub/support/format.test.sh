#!/usr/bin/env sh
# format.test.sh (harbor#1278) — the `support` key of policy.json and the `support` event, against contracts/hub.md.
. "$(dirname "$0")/../../lib/core.sh"; t_init
F="$T_ROOT/bin/hub-format.sh"; P="$T_ROOT/tests/hub/fixtures/policy.json"
K='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICiecex8Dq718eSe1CCLgLvDmI7AagvCtax7brPFWkh4'
pol() { # <jq edit>: exit of the validator
  jq --arg k "$K" "$1" "$P" > "$T_TMP/p.json"
  sh "$F" policy "$T_TMP/p.json" >/dev/null 2>&1; echo $?
}
accepts() { t_eq "$1" 0 "$(pol "$2")"; }
rejects() { t_eq "$1" 1 "$(pol "$2")"; }

t_section "1 - optional, closed"
accepts "absent is fine: support is off" '.'
accepts "keys alone are valid, and support stays off: there is no default relay" '.support = {keys: [$k]}'
accepts "with a comment" '.support = {keys: [$k + " fixture-admin@box"]}'
accepts "every field" '.support = {keys: [$k], relay: "wss://relay.example", relay_key: $k, max_minutes: 60}'
rejects "not an object" '.support = []'
rejects "no keys" '.support = {max_minutes: 60}'
rejects "an unknown key" '.support = {keys: [$k], accept: true}'

t_section "2 - keys, strictly"
rejects "empty" '.support = {keys: []}'
rejects "more than 20" '.support = {keys: [range(21) | $k + " c\(.)"]}'
rejects "the same key twice" '.support = {keys: [$k, $k]}'
rejects "not a string" '.support = {keys: [1]}'
rejects "an options prefix" '.support = {keys: ["command=\"sh\" " + $k]}'
rejects "a second line smuggled in" '.support = {keys: [$k + "\ncommand=\"sh\" " + $k]}'
rejects "a trailing newline" '.support = {keys: [$k + "\n"]}'
rejects "a comment with a space" '.support = {keys: [$k + " two words"]}'
rejects "an unknown type" '.support = {keys: ["ssh-dss AAAAB3NzaC1kc3M="]}'
rejects "not base64" '.support = {keys: ["ssh-ed25519 AAAA$$$$"]}'

t_section "3 - the relay"
accepts "another relay with its key" '.support = {keys: [$k], relay: "wss://relay.example:8443", relay_key: $k}'
accepts "over ssh" '.support = {keys: [$k], relay: "ssh://relay.example", relay_key: $k}'
rejects "a relay with no key to pin" '.support = {keys: [$k], relay: "wss://relay.example"}'
rejects "a key with no relay" '.support = {keys: [$k], relay_key: $k}'
rejects "the public relay, even with a key" '.support = {keys: [$k], relay: "wss://uptermd.upterm.dev", relay_key: $k}'
rejects "a name under the public relay" '.support = {keys: [$k], relay: "ssh://eu.uptermd.upterm.dev:22", relay_key: $k}'
accepts "CONTROL: a name that only ends the same way" '.support = {keys: [$k], relay: "wss://notuptermd.upterm.dev.example", relay_key: $k}'
rejects "plain ws" '.support = {keys: [$k], relay: "ws://relay.example", relay_key: $k}'
rejects "https" '.support = {keys: [$k], relay: "https://relay.example", relay_key: $k}'
rejects "a user in the url" '.support = {keys: [$k], relay: "wss://a@relay.example", relay_key: $k}'
rejects "a path" '.support = {keys: [$k], relay: "wss://relay.example/x", relay_key: $k}'
rejects "a newline" '.support = {keys: [$k], relay: "wss://relay.example\n", relay_key: $k}'
rejects "a relay key with a comment" '.support = {keys: [$k], relay: "wss://relay.example", relay_key: ($k + " c")}'

t_section "3b - support_relay, the reader behind member-support.sh and hub-support.sh, refuses on its own"
sr() { # <jq edit> [nopin]: the exit of support_relay on that policy, with the installed layout's pin beside the library, or none
  jq --arg k "$K" "$1" "$P" > "$T_TMP/sr.json"
  rm -rf "$T_TMP/srbin"; mkdir -p "$T_TMP/srbin"; [ -n "${2:-}" ] || cp "$T_ROOT/contracts/support-upterm.tsv" "$T_TMP/srbin/"
  ( HERE="$T_TMP/srbin"; . "$T_ROOT/bin/library-board.sh"; support_relay "$T_TMP/sr.json" ) >/dev/null 2>&1; echo $?
}
t_eq "the hub relay with its key reads" 0 "$(sr '.support = {keys: [$k], relay: "wss://relay.example", relay_key: $k}')"
t_eq "no relay: off, never a default" 1 "$(sr '.support = {keys: [$k]}')"
t_eq "a relay with no key: off" 1 "$(sr '.support = {keys: [$k], relay: "wss://relay.example"}')"
t_eq "the public relay: refused" 2 "$(sr '.support = {keys: [$k], relay: "wss://uptermd.upterm.dev", relay_key: $k}')"
t_eq "a name under it: refused" 2 "$(sr '.support = {keys: [$k], relay: "ssh://eu.uptermd.upterm.dev:22", relay_key: $k}')"
t_eq "with no pin to name the public relay, nothing reads" 2 "$(sr '.support = {keys: [$k], relay: "wss://relay.example", relay_key: $k}' nopin)"

t_section "4 - max_minutes"
accepts "5" '.support = {keys: [$k], max_minutes: 5}'
accepts "240" '.support = {keys: [$k], max_minutes: 240}'
rejects "4" '.support = {keys: [$k], max_minutes: 4}'
rejects "241" '.support = {keys: [$k], max_minutes: 241}'
rejects "a fraction" '.support = {keys: [$k], max_minutes: 5.5}'
rejects "text" '.support = {keys: [$k], max_minutes: "60"}'

t_section "5 - the tier reader takes a policy that has it"
jq --arg k "$K" '.support = {keys: [$k]}' "$P" > "$T_TMP/with.json"
mkdir -p "$T_TMP/x"; printf '#!/bin/sh\n[ "$1" = path ] && printf "%%s\\n" "%s"; exit 0\n' "$T_TMP/with.json" > "$T_TMP/x/hub-sync.sh"
cp "$T_ROOT/bin/hub-tier.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/library-hub.sh" "$T_ROOT/bin/library-admission.sh" "$T_ROOT/bin/admission-normalize.awk" \
   "$T_ROOT/contracts/risk-tiers.tsv" "$T_ROOT/contracts/hub-vocabulary.tsv" "$T_ROOT/standards/naming/controls.tsv" "$T_TMP/x/"
t_eq "a policy with support still reads" shadow "$(sh "$T_TMP/x/hub-tier.sh" mode 2>/dev/null)"

t_section "6 - the event"
ev() { # <jq edit>: exit of the validator
  jq -n '{v: 1, kind: "support", ts: "2026-11-07T10:00:00Z", member: "alice", id: "s-0123456789abcdef", reason: "fix", outcome: "requested"}' | jq "$1" > "$T_TMP/e.json"
  sh "$F" event "$T_TMP/e.json" >/dev/null 2>&1; echo $?
}
t_eq "a good one" 0 "$(ev '.')"
for _o in requested accepted declined unanswered started ended timed-out; do t_eq "outcome $_o" 0 "$(ev ".outcome = \"$_o\"")"; done
for _r in update fix question; do t_eq "reason $_r" 0 "$(ev ".reason = \"$_r\"")"; done
t_eq "a reason off the list" 1 "$(ev '.reason = "my disk is full"')"
t_eq "an outcome off the list" 1 "$(ev '.outcome = "whatever"')"
t_eq "an r- id" 1 "$(ev '.id = "r-0123456789abcdef"')"
t_eq "a free-text key" 1 "$(ev '.note = "hello"')"
t_eq "terminal text has nowhere to go" 1 "$(ev '.output = "ls -la"')"
t_eq "a request event still wants an r- id" 1 "$(jq -n '{v: 1, kind: "request", ts: "2026-11-07T10:00:00Z", member: "alice", id: "s-0123456789abcdef", rule: "x", tier: "low", target: "other", outcome: "opened"}' > "$T_TMP/e.json"; sh "$F" event "$T_TMP/e.json" >/dev/null 2>&1; echo $?)"
t_done
