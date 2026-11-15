#!/usr/bin/env sh
# bin/gate-pr-plan.sh against a stubbed gh (harbor#1413): each case is a repo shape measured on 2026-11-01, and the
# command the planner prints is the one GitHub accepts there. The stub fails on any call it was not told about.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; mkdir -p "$FX"
cat > "$GH" <<'STUB'
#!/bin/sh
case "$*" in
  "pr view "*) [ -f "$FX/pr.fail" ] && { echo "gh: HTTP 502" >&2; exit 1; }; cat "$FX/pr.json" ;;
  "api repos/"*"/compare/main...feat/x --jq .behind_by") cat "$FX/behind" 2>/dev/null || echo 0 ;;
  "api repos/o/r") cat "$FX/repo.json" ;;
  "api repos/o/r/rules/branches/main") cat "$FX/rules.json" ;;
  "api repos/o/r/contents/.agents/ship.config?ref=main -H Accept: application/vnd.github.raw")
    [ -f "$FX/ship" ] && { cat "$FX/ship"; exit 0; }; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "api repos/o/r/contents/.agents/ship.conf?ref=main -H Accept: application/vnd.github.raw")
    [ -f "$FX/ship-old" ] && { cat "$FX/ship-old"; exit 0; }; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "pr list -R o/r --base feat/x --state open --json number --jq .[].number") cat "$FX/kids" 2>/dev/null || : ;;
  *) echo "UNEXPECTED gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH"
OWNSLUG="$T_TMP/own"; mkdir -p "$OWNSLUG"
run() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_OPERATOR_GH=OG sh "$T_ROOT/bin/gate-pr-plan.sh" "$@" 2>&1; }
rc() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_OPERATOR_GH=OG sh "$T_ROOT/bin/gate-pr-plan.sh" "$@" >/dev/null 2>&1; echo $?; }
# pr <mergeState> <reviewDecision> [rollup-json] [author-is-bot] [reviews-json] [state] [commits-json]
pr() {
  jq -n --arg ms "$1" --arg rd "$2" --argjson roll "${3:-[]}" --argjson bot "${4:-true}" --argjson rev "${5:-[]}" --arg st "${6:-OPEN}" \
    --argjson com "${7:-[]}" \
    '{state: $st, isDraft: false, mergeStateStatus: $ms, reviewDecision: $rd, headRefOid: "abc123", headRefName: "feat/x",
      baseRefName: "main", author: {login: (if $bot then "app/harbor" else "alice" end), is_bot: $bot},
      statusCheckRollup: $roll, reviews: $rev, commits: $com}' > "$FX/pr.json"
}
# repo <S|-><M|-><R|-> <delete_branch_on_merge>
repo() {
  jq -n --arg m "$1" --argjson d "$2" '{allow_squash_merge: ($m[0:1] == "S"), allow_merge_commit: ($m[1:2] == "M"),
    allow_rebase_merge: ($m[2:3] == "R"), delete_branch_on_merge: $d}' > "$FX/repo.json"
}
rules() { printf '%s\n' "${1:-[]}" > "$FX/rules.json"; }
ship() { if [ -n "${1:-}" ]; then printf 'repo o/r\nmethod %s\n' "$1" > "$FX/ship"; else rm -f "$FX/ship"; fi; }
reset() { rm -f "$FX/ship-old" "$FX/pr.fail" "$FX/kids" "$FX/behind"; pr CLEAN ""; repo S-- true; rules; ship; }
GREEN='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]'
CO='[{"type":"pull_request","parameters":{"require_code_owner_review":true,"required_approving_review_count":0,"allowed_merge_methods":["merge","squash","rebase"]}}]'

t_section "harbor#1097: a repo that still has the old .agents/ship.conf is read as before, until 2026-11-15"
reset; pr BLOCKED "" "$GREEN"; repo SM- true; rules "$CO"; printf 'repo o/r\nmethod merge-commit\n' > "$FX/ship-old"
OUT="$(run o/r#7)"
t_has "the method is the old file's, not squash" "$OUT" "OG pr merge 7 -R o/r --merge --match-head-commit abc123"
printf 'repo o/r\nmethod squash\n' > "$FX/ship"
t_hasnt "ship.config wins over ship.conf when both exist" "$(run o/r#7)" "pr merge 7 -R o/r --merge"

t_section "harbor#1412: a code-owner rule blocks a green PR while reviewDecision reads empty; ship.config says merge-commit"
reset; pr BLOCKED "" "$GREEN"; repo SM- true; rules "$CO"; ship merge-commit
OUT="$(run o/r#7)"
t_has "the operator approves, because GitHub blocks and nobody approved" "$OUT" "OG pr review 7 -R o/r --approve"
t_has "...naming the rule it read" "$OUT" "code-owner review"
t_has "the method is ship.config's, not squash" "$OUT" "OG pr merge 7 -R o/r --merge --match-head-commit abc123"
t_hasnt "GitHub deletes the head itself, so no --delete-branch" "$OUT" "--delete-branch"
t_eq "it lands: exit 0" 0 "$(rc o/r#7)"

# harbor#1418 follow-up, measured 2026-11-02 on two live PRs GitHub refused ("the base branch policy prohibits the merge"):
# the live JSON shapes. A review-gate StatusContext, two pull_request rules, the unattributed-changes flag, a bot-opened PR.
GATE='{"__typename":"StatusContext","context":"review/decision","state":"PENDING","targetUrl":""}'
SETTER='{"__typename":"CheckRun","name":"Set review/decision status","status":"COMPLETED","conclusion":"SUCCESS"}'
HUMAN_COMMIT='[{"oid":"f69b921","authors":[{"login":"VytCepas"}]}]'
BOT_COMMIT='[{"oid":"f69b921","authors":[{"login":"harbor"}]}]'
PR_RULE() { # <code-owner> <count> <unattributed> -> one live-shaped pull_request rule
  printf '{"type":"pull_request","parameters":{"required_approving_review_count":%s,"dismiss_stale_reviews_on_push":true,"required_reviewers":[],"require_code_owner_review":%s,"require_last_push_approval":false,"required_review_thread_resolution":false,"require_extra_approval_for_unattributed_changes":%s,"allowed_merge_methods":["merge","squash","rebase"]},"ruleset_source_type":"Repository","ruleset_id":1}' "$2" "$1" "$3"
}

t_section "a pending review-gate status is a missing approval, not CI still running (orchestrator#357)"
reset; repo SM- true; rules "[$(PR_RULE true 0 true)]"
pr BLOCKED "" "[$SETTER,$GATE]" true "[]" OPEN "$HUMAN_COMMIT"
OUT="$(run o/r#7)"
t_has "the operator approves before the merge" "$OUT" "OG pr review 7 -R o/r --approve"
t_has "...naming the gate that holds it" "$OUT" "review/decision"
t_hasnt "the gate is not reported as a check to wait on" "$OUT" "waiting on"
t_eq "approve comes first, then merge" "approve|merge" "$(run --json o/r#7 2>/dev/null | jq -r '.[0].steps | map(.what) | join("|")')"
pr BLOCKED "" "[$SETTER,$GATE]" true '[{"state":"APPROVED","author":{"login":"alice","is_bot":false}}]' OPEN "$HUMAN_COMMIT"
OUT="$(run o/r#7)"
t_hasnt "control: already approved, the status only lags: no second approve" "$OUT" "--approve"
t_has "...and it is still waited on" "$OUT" "waiting on: review/decision"
pr BLOCKED "" "[$SETTER,{\"name\":\"ci\",\"status\":\"IN_PROGRESS\"}]" true "[]" OPEN "$HUMAN_COMMIT"
OUT="$(run o/r#7)"
t_has "control: a real running check is still waited on" "$OUT" "waiting on: ci"
pr BLOCKED "" "[$SETTER]" true "[]" OPEN "[]"
t_hasnt "control: a finished CheckRun merely NAMED review/decision is no gate and no wait" "$(run o/r#7)" "waiting on"

t_section "several pull_request rules: any code-owner wins, the largest count wins (project-init#1120 has two)"
reset; pr BLOCKED "" "$GREEN" true "[]" OPEN "[]"; repo SM- true
rules "[$(PR_RULE false 0 false),$(PR_RULE true 0 false)]"
t_has "the second rule's code-owner review is read, not just the first" "$(run o/r#7)" "the base rules require a code-owner review"
rules "[$(PR_RULE false 1 false),$(PR_RULE false 2 false)]"
t_has "the largest approving count" "$(run o/r#7)" "require 2 approval(s)"

t_section "require_extra_approval_for_unattributed_changes: the App pushed a human's commits, so an approval is required"
reset; repo SM- true; rules "[$(PR_RULE false 0 true)]"
pr BLOCKED "" "$GREEN" true "[]" OPEN "$HUMAN_COMMIT"
OUT="$(run o/r#7)"
t_has "the operator approves" "$OUT" "OG pr review 7 -R o/r --approve"
t_has "...for the unattributed change" "$OUT" "unattributed"
pr BLOCKED "" "[{\"name\":\"ci\",\"status\":\"IN_PROGRESS\"}]" true "[]" OPEN "$HUMAN_COMMIT"
t_has "the rule is explicit, so it asks even while CI runs" "$(run o/r#7)" "OG pr review 7 -R o/r --approve"
pr BLOCKED "" "$GREEN" true "[]" OPEN "$BOT_COMMIT"
t_hasnt "control: commits the App itself authored are attributed" "$(run o/r#7)" "unattributed"
reset; repo SM- true; rules "[$(PR_RULE false 0 false)]"
pr BLOCKED "" "$GREEN" true "[]" OPEN "$HUMAN_COMMIT"
t_hasnt "control: the flag off, no unattributed reason" "$(run o/r#7)" "unattributed"
reset; repo SM- true; rules "[$(PR_RULE false 0 true)]"
pr CLEAN "" "$GREEN" true "[]" OPEN "$HUMAN_COMMIT"
t_hasnt "control: GitHub says CLEAN, nothing to approve" "$(run o/r#7)" "--approve"

t_section "a squash-only repo: REVIEW_REQUIRED from classic protection, squash the only method, no ship.config"
reset; pr BLOCKED REVIEW_REQUIRED "$GREEN"; repo S-- true
OUT="$(run o/r#7)"
t_has "GitHub's own word asks for the approval" "$OUT" "OG pr review 7 -R o/r --approve"
t_has "the one method the repo allows" "$OUT" "--squash --match-head-commit abc123"
t_has "...and says where it came from" "$OUT" "the only method o/r allows"

t_section "a green PR nothing blocks: just the merge"
reset; repo S-- false
OUT="$(run o/r#7)"
t_hasnt "no approval asked for" "$OUT" "review 7"
t_has "GitHub keeps the head, so the merge deletes it" "$OUT" "--squash --match-head-commit abc123 --delete-branch"

t_section "drift: ship.config says merge-commit, the live repo allows squash only"
reset; repo S-- true; ship merge-commit
OUT="$(run o/r#7)"
t_has "refused and named, never swapped for squash" "$OUT" "drift: ship.config says method merge"
t_hasnt "no merge command is printed" "$OUT" "pr merge"
t_eq "exit 1" 1 "$(rc o/r#7)"

t_section "undeclared with several methods: squash; a rule narrows what the repo allows"
reset; repo SMR true
t_has "squash among several" "$(run o/r#7)" "--squash"
rules '[{"type":"pull_request","parameters":{"allowed_merge_methods":["rebase"]}}]'
t_has "the rule leaves only rebase" "$(run o/r#7)" "--rebase"

t_section "a red required check stops the plan at the re-run"
reset; pr BLOCKED "" '[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/123/job/9"}]'
OUT="$(run o/r#7)"
t_has "the re-run is the operator's, for that run" "$OUT" "OG run rerun 123 -R o/r --failed"
t_hasnt "nothing is merged on red" "$OUT" "pr merge"
t_eq "exit 1" 1 "$(rc o/r#7)"
pr UNSTABLE "" '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]'
OUT="$(run o/r#7)"
t_has "control: an optional red (UNSTABLE) is noted" "$OUT" "optional checks red: lint"
t_has "...and still lands" "$OUT" "pr merge 7"

t_section "a check re-run on the same head: only the newest run of a name is judged (project-init#1121)"
OLDF='{"name":"Check PR title format","workflowName":"Validate PR","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-11-02T07:55:29Z","completedAt":"2026-11-02T07:55:32Z","detailsUrl":"https://github.com/o/r/actions/runs/123/job/9"}'
NEWS='{"name":"Check PR title format","workflowName":"Validate PR","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-11-02T08:03:36Z","completedAt":"2026-11-02T08:03:39Z","detailsUrl":"https://github.com/o/r/actions/runs/456/job/9"}'
reset; pr BLOCKED "" "[$OLDF,$NEWS]"
OUT="$(run o/r#7)"
t_hasnt "an older FAILURE superseded by a newer SUCCESS gets no re-run" "$OUT" "run rerun"
t_hasnt "...and is not called red" "$OUT" "red:"
t_has "...so the plan reaches the merge" "$OUT" "pr merge 7"
t_eq "...and lands: exit 0" 0 "$(rc o/r#7)"
pr BLOCKED "" "[$NEWS,$OLDF]"
t_hasnt "the order of the rollup does not matter" "$(run o/r#7)" "run rerun"
OLDS="$(printf '%s' "$NEWS" | jq -c '.startedAt = "2026-11-02T07:00:00Z" | .completedAt = "2026-11-02T07:00:03Z"')"
NEWF="$(printf '%s' "$OLDF" | jq -c '.startedAt = "2026-11-02T08:30:00Z" | .completedAt = "2026-11-02T08:30:03Z"')"
pr BLOCKED "" "[$OLDS,$NEWF]"
OUT="$(run o/r#7)"
t_has "control: a newer FAILURE after an older SUCCESS is still red" "$OUT" "OG run rerun 123 -R o/r --failed"
OTHER="$(printf '%s' "$OLDF" | jq -c '.workflowName = "CI"')"
pr BLOCKED "" "[$OTHER,$NEWS]"
t_has "control: the same name in another workflow is a different check" "$(run o/r#7)" "OG run rerun 123 -R o/r --failed"

t_section "behind: update-branch and a re-plan, nothing pinned to a head that will move"
reset; pr BEHIND ""
OUT="$(run o/r#7)"
t_has "update-branch, then re-plan" "$OUT" "re-plan"
t_hasnt "no merge pinned to the old head" "$OUT" "pr merge"
t_hasnt "no approval that the update would dismiss" "$OUT" "--approve"

t_section "harbor#1418: red AND behind its base: the red may already be fixed on the base, so update the branch, not re-run"
RED1='[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/123/job/9"}]'
reset; pr BLOCKED "" "$RED1"; printf '10\n' > "$FX/behind"
OUT="$(run o/r#7)"
t_has "another org's repo: update-branch is the operator's" "$OUT" "OG pr update-branch 7 -R o/r"
t_has "...then a re-plan on the new head" "$OUT" "re-plan"
t_hasnt "no re-run of a run that may already be fixed on the base" "$OUT" "run rerun"
t_has "the verdict says why" "$OUT" "behind main"
t_eq "still not landing: exit 1" 1 "$(rc o/r#7)"
OUT="$(run VytCepas/other#7)"
t_has "harbor's own owner: update-branch is the App's" "$OUT" "gh pr update-branch 7 -R VytCepas/other"
t_hasnt "...not spelled with the operator's gh" "$OUT" "OG pr update-branch"
t_hasnt "and no re-run there either" "$OUT" "run rerun"
reset; pr BLOCKED "" "$RED1"; printf '0\n' > "$FX/behind"
OUT="$(run o/r#7)"
t_has "control: up to date with its base, the re-run stays the step" "$OUT" "OG run rerun 123 -R o/r --failed"
t_hasnt "...and no update-branch" "$OUT" "update-branch"
reset; pr BLOCKED "" "$RED1"; printf 'x\n' > "$FX/behind"
t_eq "a compare that cannot be read is exit 3, never a re-run guess" 3 "$(rc o/r#7)"

t_section "harbor#1418: ship.config review and delete-branch are checked against the live facts, which win"
reset; pr BLOCKED "" "$GREEN"; repo SM- true; rules "$CO"
printf 'repo o/r\nmethod merge-commit\nreview 0 code-owner\ndelete-branch yes\n' > "$FX/ship"
OUT="$(run o/r#7)"
t_hasnt "control: a declaration that matches the live rules is no drift" "$OUT" "drift"
printf 'repo o/r\nmethod merge-commit\nreview 1\ndelete-branch yes\n' > "$FX/ship"
OUT="$(run o/r#7)"
t_has "a review the rules do not require is named as drift" "$OUT" "drift: ship.config says review 1, the live rules require 0 code-owner"
t_has "...and the plan still lands: live wins" "$OUT" "OG pr merge 7 -R o/r --merge"
printf 'repo o/r\nmethod merge-commit\nreview 0 code-owner\ndelete-branch no\n' > "$FX/ship"
OUT="$(run o/r#7)"
t_has "delete-branch declared no, live deletes the head" "$OUT" "drift: ship.config says delete-branch no, the live repo's delete_branch_on_merge is true"
t_hasnt "...and live wins: no --delete-branch" "$OUT" "--delete-branch"
rules
printf 'repo o/r\nmethod merge-commit\nreview 0 code-owner\ndelete-branch yes\n' > "$FX/ship"
t_has "no readable review rule is said, not read as none" "$(run o/r#7)" "cannot read a review rule"
printf 'repo o/r\nmethod merge-commit\nreview wat\n' > "$FX/ship"
t_has "an unparseable review line is named" "$(run o/r#7)" "review wat is not"

t_section "a PR stacked on the head is retargeted before the merge deletes it"
reset; repo S-- false; printf '9\n' > "$FX/kids"
OUT="$(run o/r#7)"
t_has "the App retargets #9 to the base" "$OUT" "gh pr edit 9 -R o/r --base main"
t_eq "...before the merge" "retarget" "$(printf '%s\n' "$OUT" | grep -oE 'retarget|  merge' | head -n 1)"

t_section "a person authored it: they cannot approve their own"
reset; pr BLOCKED REVIEW_REQUIRED "$GREEN" false
OUT="$(run o/r#7)"
t_has "a second person is asked for" "$OUT" "alice authored it"
t_hasnt "no self-approval command" "$OUT" "--approve"

t_section "states that do not land, and reads that fail"
reset; pr BLOCKED CHANGES_REQUESTED "$GREEN"
t_eq "changes requested: exit 1" 1 "$(rc o/r#7)"
reset; pr CLEAN "" "[]" true "[]" MERGED
t_eq "already merged: exit 0" 0 "$(rc o/r#7)"
reset; pr UNKNOWN ""
t_eq "mergeability not computed: exit 3, not a plan" 3 "$(rc o/r#7)"
reset; touch "$FX/pr.fail"
t_eq "an unreadable PR: exit 3" 3 "$(rc o/r#7)"

t_section "the repo is named or it is the cwd's origin, never guessed"
reset
t_eq "a bare number outside a checkout is a usage error" 2 "$(cd "$T_TMP" && rc 7)"
git -C "$OWNSLUG" init -q && git -C "$OWNSLUG" remote add origin https://github.com/o/r.git
t_has "a bare number in a checkout is its origin's PR" "$(cd "$OWNSLUG" && run 7)" "o/r#7"
t_has "a pull URL" "$(run https://github.com/o/r/pull/7)" "o/r#7"

t_section "--handover: only runnable lines on stdout"
reset; pr BLOCKED "" "$GREEN"; repo SM- true; rules "$CO"; ship merge-commit
OUT="$(FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_OPERATOR_GH=OG sh "$T_ROOT/bin/gate-pr-plan.sh" --handover o/r#7 2>/dev/null)"
t_eq "approve, then merge" "OG pr review 7 -R o/r --approve|OG pr merge 7 -R o/r --merge --match-head-commit abc123" "$(printf '%s\n' "$OUT" | paste -sd'|' -)"
t_hasnt "no # anywhere: zsh without interactivecomments would run it" "$OUT" "#"
t_done
