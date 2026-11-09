#!/usr/bin/env sh
# format.test.sh (harbor#1278) — bin/hub-format.sh against contracts/hub.md: good fixtures pass, and each closed field refuses
# the value it exists to keep out, above all an event carrying free text.
. "$(dirname "$0")/../../lib/core.sh"; t_init
F="$T_ROOT/bin/hub-format.sh"; FX="$T_ROOT/tests/hub/fixtures"; X="$T_TMP/x.json"
valid() { # <label> <verb> <file>
  if sh "$F" "$2" "$3" 2>/dev/null; then t_pass; else t_fail "$1"; fi
}
# refuse <label> <verb> <jq edit of the fixture> <fixture> <expected text>
refuse() {
  jq "$3" "$FX/$4" > "$X"
  _o="$(sh "$F" "$2" "$X" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" = 1 ] && printf '%s' "$_o" | grep -qF "$5"; then t_pass; else t_fail "$1 (rc $_rc: $_o)"; fi
}

t_section "1 - the fixtures pass"
valid "policy fixture" policy "$FX/policy.json"
valid "event fixtures, every kind" event "$FX/events.json"
valid "extension fixture" manifest "$FX/extension.json"
valid "core tier list" tiers "$T_ROOT/contracts/risk-tiers.tsv"

t_section "2 - an event cannot carry content"
refuse "a free-text field" event '.[1] + {note:"the client said"}' events.json "unknown key: note"
refuse "prose in a rule id" event '.[1] | .rule = "delete the Acme client bucket"' events.json "rule: not a kebab id"
refuse "a value outside the vocabulary" event '.[1] | .target = "client-list"' events.json "target: not in the vocabulary"
refuse "a kind outside the vocabulary" event '.[1] | .kind = "transcript"' events.json "kind: not in the vocabulary"
refuse "an exact timestamp" event '.[1] | .ts = "2026-11-07T10:13:22Z"' events.json "ts: not coarsened"
refuse "a chosen name in packs" event '.[0] | .packs = ["Acme Client Stuff"]' events.json "packs: not kebab ids"
refuse "a text count" event '.[1] | .count = "many"' events.json "a count is not a whole number"

t_section "3 - a policy is closed and bounded"
refuse "an unknown key" policy '. + {extra:1}' policy.json "unknown key: extra"
refuse "a newer schema" policy '.schema = 2' policy.json "schema: only 1"
refuse "no approvers" policy '.approval.approvers = []' policy.json "approval.approvers"
refuse "a ttl over a week" policy '.approval.ttl_hours = 169' policy.json "ttl_hours"
refuse "a short commit" policy '.core.commit = "abc"' policy.json "core.commit"
refuse "a regular expression op" policy '.rules[0].when[0].op = "regex"' policy.json "bad op"
refuse "an overlong value" policy '.rules[0].when[0].value = ("x" * 201)' policy.json "value not 1 to 200"
refuse "a duplicate rule id" policy '.rules += [.rules[0]]' policy.json "duplicate id"
refuse "a path out of the pack" policy '.hooks = [{pack:"a",path:"../x",sha256:("0"*64)}]' policy.json "bad path"

t_section "4 - a fixed row stays very-high"
printf 'admission.x\thigh\tfixed\tLabel\n' > "$T_TMP/t.tsv"
if sh "$F" tiers "$T_TMP/t.tsv" 2>/dev/null; then t_fail "a fixed row below very-high"; else t_pass; fi

t_section "5 - the canonical call"
. "$T_ROOT/bin/library-hub.sh"
A='{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"ls","description":"one"}}'
B='{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"ls","description":"two","timeout":5}}'
C='{"tool_name":"Bash","cwd":"/w","tool_input":{"command":"ls -a"}}'
ia="$(hub_request_id "$(hub_canon "$A" m)" s)"; ib="$(hub_request_id "$(hub_canon "$B" m)" s)"; ic="$(hub_request_id "$(hub_canon "$C" m)" s)"
t_eq "a re-emitted call keeps its id" "$ia" "$ib"
[ "$ia" != "$ic" ] && t_pass || t_fail "a changed command gets a new id"
id2="$(hub_request_id "$(hub_canon "$A" m)" other)"
[ "$ia" != "$id2" ] && t_pass || t_fail "the salt changes the id"
t_eq "id shape" 18 "${#ia}"
t_done
