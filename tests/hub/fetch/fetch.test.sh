#!/bin/sh
# fetch.test.sh (harbor#1278) — bin/hub-fetch.sh against a gh stub: it reads only the heartbeat issues (closed ones too, never a pull
# request or a request issue), flattens their comments for hub-digest.sh, and prints nothing when GitHub does not answer.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/stub-gh.sh"
F="$T_ROOT/bin/hub-fetch.sh"; FX="$T_TMP/fx"; mkdir -p "$FX"
cat > "$FX/issues.json" <<'JSON'
[{"number":1,"title":"heartbeat alice","state":"open","user":{"login":"alice"},"created_at":"2026-11-01T00:00:00Z"},
 {"number":2,"title":"heartbeat bob","state":"closed","user":{"login":"bob"},"created_at":"2026-11-01T00:00:00Z"},
 {"number":3,"title":"heartbeat mallory","state":"open","user":{"login":"mallory"},"pull_request":{"url":"x"},"created_at":"2026-11-01T00:00:00Z"},
 {"number":4,"title":"request r-0123456789abcdef","state":"open","user":{"login":"alice"},"created_at":"2026-11-01T00:00:00Z"}]
JSON
printf '[{"user":{"login":"alice"},"created_at":"2026-11-07T08:00:00Z","body":"hello"}]' > "$FX/comments-1.json"
printf '[]' > "$FX/comments-2.json"
stub_gh "$FX"

t_section "1 - heartbeat issues only, flattened"
OUT="$(sh "$F" fixture-org/fixture-hub 2>/dev/null)"; RC=$?
t_eq "exit 0" 0 "$RC"
t_eq "two issues: the heartbeats, not the pull request or the request" "heartbeat alice,heartbeat bob" "$(printf '%s' "$OUT" | jq -r 'map(.title) | join(",")')"
t_eq "the issue author and the comment author are kept" "alice:alice" "$(printf '%s' "$OUT" | jq -r '.[0] | .author + ":" + .comments[0].author')"
t_eq "a comment keeps its server time and its body" "2026-11-07T08:00:00Z:hello" "$(printf '%s' "$OUT" | jq -r '.[0].comments[0] | .created_at + ":" + .body')"
t_eq "a closed issue with no comments is still listed" "0" "$(printf '%s' "$OUT" | jq '.[1].comments | length')"
t_has "the comments are asked for from a date, not all of history" "$(cat "$GH_LOG")" "since="
t_hasnt "the token is never on a command line" "$(cat "$GH_LOG")" "token"

t_section "2 - the digest reads what the fetch printed"
printf '%s' "$OUT" > "$T_TMP/issues.json"
D="$(sh "$T_ROOT/bin/hub-digest.sh" --issues "$T_TMP/issues.json" --policy "$T_ROOT/tests/hub/fixtures/policy.json" --now 2026-11-12T09:00:00Z 2>/dev/null)"
t_has "alice's comment was not an event, so she shows as never seen, not as alive" "$D" "| alice | - |"
t_has "the digest still has its header" "$D" "harbor-digest: 1"

t_section "3 - GitHub down prints nothing and exits 3"
OUT="$(GH_FAIL=1 sh "$F" fixture-org/fixture-hub 2>/dev/null)"; RC=$?
t_eq "exit 3" 3 "$RC"
t_eq "and nothing on stdout" "" "$OUT"

t_section "4 - usage"
t_exit "a repo that is not owner/name" 2 sh "$F" 'not a repo'
t_exit "no repo" 2 sh "$F"
t_exit "--since-days that is not a number" 2 sh "$F" fixture-org/fixture-hub --since-days soon
t_exit "--help" 0 sh "$F" --help
t_done
