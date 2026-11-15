#!/bin/sh
# workflows.test.sh (harbor#1278) — patches/hub/*.patch.md: each carries one workflow that parses, pins every action, passes no
# expression into a shell, and enables nothing here. Then the steps that hold logic run against a gh stub: the digest posts once a
# day, the silent job opens one issue and closes it on return, and the watchdog notices a digest that stopped (R19).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/stub-gh.sh"; . "$T_ROOT/tests/hub/fixtures/make-hub.sh"
P="$T_ROOT/patches/hub"; X="$T_TMP/wf"; mkdir -p "$X"
if ! command -v ruby >/dev/null 2>&1; then
  echo "workflows-test: SKIPPED (no ruby on PATH to parse the YAML)"
  t_section "skipped"; t_pass; t_done
fi
# yaml_of <patch>: the one yaml fence, as JSON. Ruby reads `on:` as the key true, so it is renamed back.
yaml_of() {
  awk '/^```yaml$/ { on = 1; next } /^```$/ && on { exit } on { print }' "$P/$1.patch.md" > "$X/$1.yml"
  ruby -ryaml -rjson -e 'y = YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], aliases: false); y["on"] = y.delete(true) if y.key?(true); puts JSON.generate(y)' "$X/$1.yml" > "$X/$1.json"
}
# step <workflow> <step name>: its run script
step() { jq -r --arg n "$2" '[.jobs[].steps[] | select(.name == $n) | .run][0]' "$X/$1.json"; }

t_section "1 - each patch: one workflow, parsed, pinned, nothing enabled"
for n in hub-gates hub-digest hub-silent hub-watchdog hub-bq-load; do
  yaml_of "$n"
  t_eq "$n parses and has jobs" "true" "$(jq '.jobs | length > 0' "$X/$n.json")"
  t_eq "$n is not applied" "1" "$(grep -c '^\*\*STATUS: NOT APPLIED' "$P/$n.patch.md")"
  t_eq "$n pins every action to a full commit" "0" "$(jq -r '[.jobs[].steps[] | .uses // empty | select(test("@[0-9a-f]{40}$") | not)] | length' "$X/$n.json")"
  t_eq "$n declares its permissions" "true" "$(jq '.permissions != null' "$X/$n.json")"
  t_eq "$n never runs on a pull_request_target" "false" "$(jq '.on | has("pull_request_target")' "$X/$n.json")"
  t_eq "$n puts no expression inside a shell script" "0" "$(jq -r '[.jobs[].steps[] | .run // empty | select(contains("${{"))] | length' "$X/$n.json")"
done
t_eq "no hub workflow was written into this repo" "0" "$(find "$T_ROOT/.github/workflows" -name 'hub-*' 2>/dev/null | grep -c . || true)"
t_eq "the watchdog also runs on member activity" "true" "$(jq '.on | has("issue_comment") and has("schedule")' "$X/hub-watchdog.json")"
t_eq "the loader runs only by hand until J1 has its yes" "[\"workflow_dispatch\"]" "$(jq -c '.on | keys' "$X/hub-bq-load.json")"
t_eq "the loader asks for an OIDC token and nothing it does not use" '{"contents":"read","id-token":"write","issues":"read"}' "$(jq -S -c .permissions "$X/hub-bq-load.json")"
t_eq "its identity file is removed in the step that made it" 1 "$(step hub-bq-load 'Build the rows' | grep -c 'rm -f "$RUNNER_TEMP/identity"')"
if command -v actionlint >/dev/null 2>&1; then
  if actionlint -shellcheck= "$X"/hub-gates.yml "$X"/hub-digest.yml "$X"/hub-silent.yml "$X"/hub-watchdog.yml "$X"/hub-bq-load.yml > "$X/actionlint.out" 2>&1; then t_pass; else t_fail "actionlint: $(head -n 5 "$X/actionlint.out")"; fi
else echo "workflows-test: SKIPPED actionlint (not installed); the parse checks above ran"; fi

# a workspace as the runner has it: hub/ (made), core/ (this checkout's bin), RUNNER_TEMP
W="$T_TMP/ws"; mkdir -p "$W" "$W/rt"; make_hub "$W/hub"; ln -s "$T_ROOT" "$W/core"
NOW="$(jq -n -r 'now | todate')"; AGO() { jq -n -r --argjson h "$1" '(now - $h * 3600) | todate'; }
FX="$T_TMP/fx"; mkdir -p "$FX"
printf '{"created_at":"%s"}' "$(AGO 2000)" > "$FX/repo.json"
RC=0
runstep() { # <workflow> <step> <env...>: the step's script, as the runner would, in the workspace; its exit code in RC
  _w="$1"; _s="$2"; shift 2
  _lit="$(jq -r '.jobs[].env // {} | to_entries[] | select(.value | contains("${{") | not) | "\(.key)=\(.value)"' "$X/$_w.json")"
  # shellcheck disable=SC2086 # the job's literal env entries hold no space
  ( cd "$W" && env GH_TOKEN=x REPO=fixture-org/fixture-hub RUNNER_TEMP="$W/rt" $_lit "$@" sh -c "$(step "$_w" "$_s")" ) > "$W/out" 2> "$W/err" && RC=0 || RC=$?
}

t_section "2 - the digest: built, posted once a day, closed"
printf '[{"number":1,"title":"heartbeat alice","state":"open","user":{"login":"alice"},"created_at":"%s"}]' "$(AGO 100)" > "$FX/issues.json"
printf '[]' > "$FX/comments-1.json"
stub_gh "$FX"
runstep hub-digest "Build the digest" MEMBERS="alice bob"; t_eq "the build step succeeds" 0 "$RC"
t_has "the digest header is written" "$(cat "$W/rt/digest.md")" "harbor-digest: 1"
t_has "a member from HUB_MEMBERS who never wrote is listed" "$(cat "$W/rt/digest.md")" "| bob | - |"
runstep hub-digest "Post it once for the day"; t_eq "the post step succeeds" 0 "$RC"
t_has "it creates today's issue" "$(cat "$GH_LOG")" "issue create --repo fixture-org/fixture-hub --title digest $(date -u +%F)"
t_has "carrying the digest body" "$(cat "$GH_LOG")" "BODY: harbor-digest: 1"
t_has "and closes it" "$(cat "$GH_LOG")" "gh issue close https://example.invalid/fixture/issues/900"
printf '[{"number":7,"title":"digest %s","state":"closed","user":{"login":"bot"},"created_at":"%s"}]' "$(date -u +%F)" "$NOW" > "$FX/issues.json"
: > "$GH_LOG"; runstep hub-digest "Post it once for the day"
t_hasnt "a second run the same day posts nothing" "$(cat "$GH_LOG")" "issue create"
t_has "and says so" "$(cat "$W/out")" "already exists"
printf '[]' > "$FX/issues.json"; stub_gh "$FX"
runstep hub-digest "Build the digest" MEMBERS=""; t_has "an empty hub still builds a digest" "$(cat "$W/rt/digest.md")" "no member has sent a heartbeat"

t_section "3 - silent members: one issue each, closed on return"
printf '[{"number":1,"title":"heartbeat bob","state":"open","user":{"login":"bob"},"created_at":"%s"}]' "$(AGO 900)" > "$FX/issues.json"
jq -n --arg t "$(AGO 240)" '[{user:{login:"bob"}, created_at:$t, body:("```json\n[{\"v\":1,\"kind\":\"heartbeat\",\"ts\":\"2026-11-01T08:00:00Z\",\"member\":\"bob\",\"core\":\"0123456789ab\",\"contract\":1,\"floor\":\"0123456789abcdef\",\"serial\":1,\"mode\":\"shadow\",\"refusals\":0,\"asks\":0,\"requests\":0,\"packs\":[]}]\n```")}]' > "$FX/comments-1.json"
stub_gh "$FX"
runstep hub-silent "Find the silent members" MEMBERS=""; t_eq "the find step succeeds" 0 "$RC"
t_eq "bob, ten days quiet, is silent" "bob" "$(cat "$W/rt/silent.txt")"
runstep hub-silent "Open and close the issues"; t_eq "the issue step succeeds" 0 "$RC"
t_has "one issue is opened for bob" "$(cat "$GH_LOG")" "issue create --repo fixture-org/fixture-hub --title silent bob"
t_has "naming the admins" "$(cat "$GH_LOG")" "BODY: cc: @fixture-admin"
printf '[{"number":1,"title":"heartbeat bob","state":"open","user":{"login":"bob"},"created_at":"%s"},{"number":8,"title":"silent bob","state":"open","user":{"login":"bot"},"created_at":"%s"}]' "$(AGO 900)" "$NOW" > "$FX/issues.json"
: > "$GH_LOG"; runstep hub-silent "Open and close the issues"
t_hasnt "with the issue open, no second one" "$(cat "$GH_LOG")" "issue create"
: > "$W/rt/silent.txt"; runstep hub-silent "Open and close the issues"
t_has "bob is back: the issue is commented" "$(cat "$GH_LOG")" "issue comment 8"
t_has "and closed" "$(cat "$GH_LOG")" "issue close 8"

t_section "4 - the watchdog notices a digest that stopped (R19)"
printf '[{"number":9,"title":"digest 2026-11-01","state":"closed","user":{"login":"bot"},"created_at":"%s"}]' "$(AGO 30)" > "$FX/issues.json"
stub_gh "$FX"; cp -R "$W/hub/policy.json" "$W/policy.json"
runstep hub-watchdog "Is there a digest from the last day"; t_eq "the step succeeds ($(head -n 3 "$W/err"))" 0 "$RC"
t_has "a digest 30 hours old: digest missing is opened" "$(cat "$GH_LOG")" "issue create --repo fixture-org/fixture-hub --title digest missing"
t_has "naming the admins" "$(cat "$GH_LOG")" "BODY: cc: @fixture-admin"
printf '[{"number":9,"title":"digest 2026-11-01","state":"closed","user":{"login":"bot"},"created_at":"%s"},{"number":10,"title":"digest missing","state":"open","user":{"login":"bot"},"created_at":"%s"}]' "$(AGO 30)" "$NOW" > "$FX/issues.json"
: > "$GH_LOG"; runstep hub-watchdog "Is there a digest from the last day"
t_hasnt "already open: not opened twice" "$(cat "$GH_LOG")" "issue create"
printf '[{"number":11,"title":"digest 2026-11-07","state":"closed","user":{"login":"bot"},"created_at":"%s"},{"number":10,"title":"digest missing","state":"open","user":{"login":"bot"},"created_at":"%s"}]' "$(AGO 3)" "$NOW" > "$FX/issues.json"
: > "$GH_LOG"; runstep hub-watchdog "Is there a digest from the last day"
t_has "a fresh digest closes the alarm" "$(cat "$GH_LOG")" "issue close 10"
printf '[]' > "$FX/issues.json"; : > "$GH_LOG"
runstep hub-watchdog "Is there a digest from the last day"
t_has "no digest ever, repo older than a day: missing" "$(cat "$GH_LOG")" "--title digest missing"
printf '{"created_at":"%s"}' "$(AGO 5)" > "$FX/repo.json"; : > "$GH_LOG"
runstep hub-watchdog "Is there a digest from the last day"
t_hasnt "a new hub gets its grace" "$(cat "$GH_LOG")" "issue create"
t_done
