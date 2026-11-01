#!/usr/bin/env sh
# bin/gate-pr-plan.sh against a stubbed gh (harbor#1413): each case is a repo shape measured on 2026-11-01, and the
# command the planner prints is the one GitHub accepts there. The stub fails on any call it was not told about.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FX="$T_TMP/fx"; GH="$T_TMP/gh"; mkdir -p "$FX"
cat > "$GH" <<'STUB'
#!/bin/sh
case "$*" in
  "pr view "*) [ -f "$FX/pr.fail" ] && { echo "gh: HTTP 502" >&2; exit 1; }; cat "$FX/pr.json" ;;
  "api repos/o/r") cat "$FX/repo.json" ;;
  "api repos/o/r/rules/branches/main") cat "$FX/rules.json" ;;
  "api repos/o/r/contents/.agents/ship.conf?ref=main -H Accept: application/vnd.github.raw")
    [ -f "$FX/ship" ] && { cat "$FX/ship"; exit 0; }; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "pr list -R o/r --base feat/x --state open --json number --jq .[].number") cat "$FX/kids" 2>/dev/null || : ;;
  *) echo "UNEXPECTED gh call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$GH"
OWNSLUG="$T_TMP/own"; mkdir -p "$OWNSLUG"
run() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_OPERATOR_GH=OG sh "$T_ROOT/bin/gate-pr-plan.sh" "$@" 2>&1; }
rc() { FX="$FX" HARBOR_TEST_GH="$GH" HARBOR_GATE_OPERATOR_GH=OG sh "$T_ROOT/bin/gate-pr-plan.sh" "$@" >/dev/null 2>&1; echo $?; }
# pr <mergeState> <reviewDecision> [rollup-json] [author-is-bot] [reviews-json] [state]
pr() {
  jq -n --arg ms "$1" --arg rd "$2" --argjson roll "${3:-[]}" --argjson bot "${4:-true}" --argjson rev "${5:-[]}" --arg st "${6:-OPEN}" \
    '{state: $st, isDraft: false, mergeStateStatus: $ms, reviewDecision: $rd, headRefOid: "abc123", headRefName: "feat/x",
      baseRefName: "main", author: {login: (if $bot then "app/harbor" else "alice" end), is_bot: $bot},
      statusCheckRollup: $roll, reviews: $rev}' > "$FX/pr.json"
}
# repo <S|-><M|-><R|-> <delete_branch_on_merge>
repo() {
  jq -n --arg m "$1" --argjson d "$2" '{allow_squash_merge: ($m[0:1] == "S"), allow_merge_commit: ($m[1:2] == "M"),
    allow_rebase_merge: ($m[2:3] == "R"), delete_branch_on_merge: $d}' > "$FX/repo.json"
}
rules() { printf '%s\n' "${1:-[]}" > "$FX/rules.json"; }
ship() { if [ -n "${1:-}" ]; then printf 'repo o/r\nmethod %s\n' "$1" > "$FX/ship"; else rm -f "$FX/ship"; fi; }
reset() { rm -f "$FX/pr.fail" "$FX/kids"; pr CLEAN ""; repo S-- true; rules; ship; }
GREEN='[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]'
CO='[{"type":"pull_request","parameters":{"require_code_owner_review":true,"required_approving_review_count":0,"allowed_merge_methods":["merge","squash","rebase"]}}]'

t_section "harbor#1412: a code-owner rule blocks a green PR while reviewDecision reads empty; ship.conf says merge-commit"
reset; pr BLOCKED "" "$GREEN"; repo SM- true; rules "$CO"; ship merge-commit
OUT="$(run o/r#7)"
t_has "the operator approves, because GitHub blocks and nobody approved" "$OUT" "OG pr review 7 -R o/r --approve"
t_has "...naming the rule it read" "$OUT" "code-owner review"
t_has "the method is ship.conf's, not squash" "$OUT" "OG pr merge 7 -R o/r --merge --match-head-commit abc123"
t_hasnt "GitHub deletes the head itself, so no --delete-branch" "$OUT" "--delete-branch"
t_eq "it lands: exit 0" 0 "$(rc o/r#7)"

t_section "a squash-only repo: REVIEW_REQUIRED from classic protection, squash the only method, no ship.conf"
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

t_section "drift: ship.conf says merge-commit, the live repo allows squash only"
reset; repo S-- true; ship merge-commit
OUT="$(run o/r#7)"
t_has "refused and named, never swapped for squash" "$OUT" "drift: ship.conf says method merge"
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

t_section "behind: update-branch and a re-plan, nothing pinned to a head that will move"
reset; pr BEHIND ""
OUT="$(run o/r#7)"
t_has "update-branch, then re-plan" "$OUT" "re-plan"
t_hasnt "no merge pinned to the old head" "$OUT" "pr merge"
t_hasnt "no approval that the update would dismiss" "$OUT" "--approve"

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
