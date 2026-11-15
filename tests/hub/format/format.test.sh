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

t_section "6 - activity and session (D9): counts per day, closed values only"
valid "activity and session events" event "$FX/events-day.json"
refuse "an activity at hour grain (D4)" event '.[0] | .ts = "2026-11-07T10:00:00Z"' events-day.json "ts: not coarsened to the day"
refuse "a session at hour grain (D4)" event '.[2] | .ts = "2026-11-07T10:00:00Z"' events-day.json "ts: not coarsened to the day"
refuse "a raw MCP tool name" event '.[1] | .tool = "mcp__claude_ai_Acme_Client"' events-day.json "tool: not in the vocabulary"
refuse "a command as the verb class" event '.[0] | .verb_class = "cat clients.csv"' events-day.json "verb_class: not in the vocabulary"
refuse "a verdict off the list" event '.[0] | .verdict = "maybe"' events-day.json "verdict: not in the vocabulary"
refuse "a session outcome that is not a start or end" event '.[2] | .outcome = "approved"' events-day.json "a session is started or ended"
refuse "the command riding along" event '.[0] + {command: "cat ~/clients/acme.csv"}' events-day.json "unknown key: command"
refuse "an activity without its count" event '.[0] | del(.count)' events-day.json "missing key: count"

t_section "7 - the logs payload: a policy key, a sealed field, and the board verb (Log scope level 2)"
REC="age1$(printf '%058d' 0 | tr 0 q)"
SEAL="YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUx$(printf '%0120d' 0 | tr 0 A)"
valid "a policy naming the loader's recipient" policy "$(jq --arg r "$REC" '.logs = {recipient: $r}' "$FX/policy.json" > "$T_TMP/p.json"; echo "$T_TMP/p.json")"
refuse "a recipient that is not an age key" policy '.logs = {recipient: "ssh-ed25519 AAAA"}' policy.json "logs.recipient: not an age X25519 recipient"
refuse "a logs key beyond recipient" policy '.logs = {recipient: "x", note: "y"}' policy.json "unknown key: note"
valid "a heartbeat with a sealed field" event "$(jq --arg s "$SEAL" '.[0] + {sealed: $s}' "$FX/events.json" > "$T_TMP/h.json"; echo "$T_TMP/h.json")"
refuse "the id in clear where the seal goes" event '.[0] + {sealed: "0f1e2d3c4b5a69788796a5b4c3d2e1f0"}' events.json "the laptop id never travels in clear"
refuse "a seal on any other kind" event '.[1] + {sealed: "x"}' events.json "unknown key: sealed"
refuse "an activity count in clear on the board" board '[.[0], {v:1,kind:"activity",ts:"2026-11-07T00:00:00Z",member:"alice",tool:"Bash",verb_class:"readonly",verdict:"allow",count:3}]' events.json "never in clear on the board"
valid "a board batch of the release-1 kinds" board "$FX/events.json"
t_done
