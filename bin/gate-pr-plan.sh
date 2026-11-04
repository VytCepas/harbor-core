#!/usr/bin/env sh
# gate-pr-plan.sh (harbor#1413) — how a pull request lands, derived from the live repo, never typed from memory.
#
#   sh gate-pr-plan.sh [--handover | --json] <PR>...
#
# PR is owner/repo#n, a github.com pull URL, or a bare n, which means the cwd's origin and nothing else (no origin:
# usage error, so a number is never judged against the wrong repo). Reads the PR, its checks, the repo's merge
# settings, the base branch's rules and the repo's .agents/ship.conf, and prints the steps in run order, each marked
# app or operator with why. Read-only: it runs nothing it prints.
#
# WHY. 2026-11-01: two PRs were handed over as `gh pr merge --squash` and GitHub refused both.
# One needed a review its classic protection holds (403 to the App); the other needed a code-owner review while
# reviewDecision reads empty, and its ship.conf says merge-commit. Every one of those facts was readable.
#
# DERIVED, NEVER DEFAULTED
#   method   ship.conf `method` when the live repo allows it, refused when it does not (that is drift, not a choice);
#            undeclared: the one method allowed, else squash when allowed. Live = the repo's allow_* AND the rules'
#            allowed_merge_methods.
#   update   a BEHIND PR gets update-branch and a re-plan, nothing after: the update moves the head, and a push
#            dismisses a stale approval, so an approve or a pinned merge planned now would be wasted.
#   red      a red head BEHIND its base (compare behind_by > 0) gets update-branch and a re-plan, not a re-run: the red may
#            already be fixed on the base (harbor#1418). Up to date, the re-run stays the step.
#   declared ship.conf `review` and `delete-branch` are read when present; live wins and a mismatch is drift in the
#            note (harbor#1418). The two readers share bin/library-repo-rules.sh with bin/gate-repo-drift.sh.
#   approve  when GitHub says REVIEW_REQUIRED, or blocks a PR whose checks are green and which nobody approved
#            (a code-owner rule leaves reviewDecision empty; classic protection is 403 to the App, so it is inferred).
#   merge    --match-head-commit <the sha judged here>: a later push makes GitHub refuse it, never land it unjudged.
#            --delete-branch only when GitHub will not delete the head itself; a PR stacked on the head is
#            retargeted first (a deleted base closes it).
# The App is refused approvals, merges and re-runs, and update-branch in another org's repo: those are the
# operator's, spelled with the operator's own gh (the in-session gh is the App). Retargeting and ready are the App's.
#
#   --handover  stdout: only the operator's commands, in run order, runnable as pasted (no `#`: zsh without
#               interactivecomments runs it); stderr: what is not landing, and the App's steps to run first
#   --json      [{pr, repo, state, merge_state, verdict, lands, method, method_from, steps: [{who, what, why, cmd}]}]
#
# EXIT  0 every PR can land (or already has) · 1 at least one cannot: red, conflict, drift, closed, changes requested
#       2 usage · 3 could not read one (gh, auth, network, mergeability not computed yet) — never reported as a plan
# ENV   HARBOR_TEST_GH a fake gh · HARBOR_GATE_OPERATOR_GH the operator's gh (default: the REAL the gh shim execs)
set -u
. "$(dirname -- "$0")/library-log.sh"
. "$(dirname -- "$0")/library-repo-rules.sh"

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
esac
MODE=text
case "${1:-}" in --handover) MODE=handover; shift ;; --json) MODE=json; shift ;; esac
[ $# -gt 0 ] || { echo "usage: sh $0 [--handover | --json] <owner/repo#n | pull URL | n>..." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "gate-pr-plan: jq is required ($(pkg_hint jq))" >&2; exit 3; }
GH="${HARBOR_TEST_GH:-gh}"
OG="${HARBOR_GATE_OPERATOR_GH:-$(sed -n 's/^REAL=//p' "$(dirname -- "$0")/access-github-app/gh" 2>/dev/null)}"
OG="${OG:-gh}"
# whose repos the App may update: the owner of harbor's own slug; another org's is the operator's
OWN="$(repo_slug 2>/dev/null)"; OWN="${OWN%%/*}"
W="$(mktemp -d "${TMPDIR:-/tmp}/gate-pr-plan.XXXXXX")" || exit 3
trap 'rm -rf "$W"' EXIT INT TERM
: > "$W/plans"

# <arg> -> "owner/repo<TAB>n", or nothing
target() {
  case "$1" in
    https://github.com/*/pull/*|github.com/*/pull/*)
      _p="${1#*github.com/}"; _r="${_p%%/pull/*}"; _n="${_p#*/pull/}"; _n="${_n%%[/#?]*}" ;;
    */*'#'*) _r="${1%%#*}"; _n="${1#*#}" ;;
    *) _n="$1"; _r="$(slug_of_url "$(git config --get remote.origin.url 2>/dev/null)")" ;;
  esac
  case "$_n" in ''|*[!0-9]*) return 1 ;; esac
  slug_valid "$_r" || return 1
  printf '%s\t%s\n' "$_r" "$_n"
}

# the head is behind its base: update-branch (the App's in harbor's own owner's repos, else the operator's), then re-plan
update_steps() { # <why-the-head-moves>
  if [ "${R%%/*}" = "$OWN" ]; then
    step app update "the head is behind $BASE" "gh pr update-branch $N -R $R"
  else
    step operator update "the head is behind $BASE, and update-branch in another org's repo is refused to the App" "$OG pr update-branch $N -R $R"
  fi
  step app re-plan "$1" "sh $0 $R#$N"
}

step() { # <who> <what> <why> <cmd>
  jq -cn --arg w "$1" --arg a "$2" --arg y "$3" --arg c "$4" '{who: $w, what: $a, why: $y, cmd: $c}' >> "$W/steps"
}

plan() { # <repo> <n> — appends one plan object to $W/plans; returns 0 lands, 1 cannot, 3 unread
  R="$1"; N="$2"; : > "$W/steps"; NOTE=""
  finish() { # <verdict> <lands> [method] [from]
    jq -cn --arg pr "$R#$N" --arg repo "$R" --arg st "${STATE:-}" --arg ms "${MS:-}" --arg v "$1" \
      --argjson lands "$2" --arg m "${3:-}" --arg mf "${4:-}" --arg note "$NOTE" --slurpfile s "$W/steps" \
      '{pr: $pr, repo: $repo, state: $st, merge_state: $ms, verdict: $v, lands: $lands, method: $m,
        method_from: $mf, note: $note, steps: $s}' >> "$W/plans"
  }
  STATE=""; MS=""
  PRJ="$("$GH" pr view "$N" -R "$R" --json state,isDraft,mergeStateStatus,reviewDecision,headRefOid,headRefName,baseRefName,author,statusCheckRollup,reviews,commits 2>"$W/err")" \
    || { finish "could not read the PR: $(head -n 1 "$W/err")" false; return 3; }
  # a re-run on the same head leaves the old run in the rollup: judge only the newest of each workflow+name
  PRJ="$(printf '%s' "$PRJ" | jq -c '.statusCheckRollup |= ((. // []) | group_by([.workflowName // "", .name // .context // ""])
    | map(max_by(.startedAt // .completedAt // "")))')" || { finish "could not read the PR's checks" false; return 3; }
  g() { printf '%s' "$PRJ" | jq -r "$1"; }
  STATE="$(g .state)"; MS="$(g .mergeStateStatus)"; RD="$(g '.reviewDecision // ""')"
  SHA="$(g .headRefOid)"; HEAD="$(g .headRefName)"; BASE="$(g .baseRefName)"
  case "$STATE" in
    MERGED) finish "already merged" true; return 0 ;;
    OPEN) ;;
    *) finish "$STATE: nothing lands" false; return 1 ;;
  esac
  [ "$MS" != UNKNOWN ] || { finish "GitHub has not computed mergeability yet; re-run in a minute" false; return 3; }

  # checks: a red required check stops the plan; a red optional one (UNSTABLE) is only noted
  RED="$(g '[.statusCheckRollup[]? | select((.conclusion // .state // "") as $c | ["FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"] | index($c)) | (.name // .context)] | unique | join(", ")')"
  WAIT="$(g '[.statusCheckRollup[]? | select((.status // "COMPLETED") != "COMPLETED" or ((.state // "") | IN("PENDING","EXPECTED"))) | (.name // .context)] | unique | join(", ")')"
  # a pending review-gate status (a StatusContext `review/...`) waits on a person, not on CI (harbor#1418)
  WAIT_CI="$(g '[.statusCheckRollup[]? | select((.context // "") | test("^review(/|$)") | not) | select((.status // "COMPLETED") != "COMPLETED" or ((.state // "") | IN("PENDING","EXPECTED"))) | (.name // .context)] | unique | join(", ")')"
  GATE="$(g '[.statusCheckRollup[]? | select((.context // "") | test("^review(/|$)")) | select((.state // "") | IN("PENDING","EXPECTED")) | .context] | unique | join(", ")')"
  RUNS="$(g '[.statusCheckRollup[]? | select((.conclusion // "") | IN("FAILURE","TIMED_OUT","CANCELLED","STARTUP_FAILURE")) | (.detailsUrl // "") | (capture("/actions/runs/(?<id>[0-9]+)") | .id)?] | unique | .[]')"
  if [ "$MS" = DIRTY ]; then
    step app resolve "the head conflicts with $BASE" "merge origin/$BASE into $HEAD in a worktree, then push"
    finish "conflicts with $BASE" false; return 1
  fi
  if [ -n "$RED" ] && [ "$MS" != UNSTABLE ] && [ "$MS" != CLEAN ]; then
    # harbor#1418: a red head behind its base may be red from a defect the base already fixed; a re-run repeats it
    BEHIND_BY="$("$GH" api "repos/$R/compare/$BASE...$HEAD" --jq .behind_by 2>"$W/err")" \
      || { finish "could not compare $HEAD with $BASE: $(head -n 1 "$W/err")" false; return 3; }
    case "$BEHIND_BY" in ''|*[!0-9]*) finish "could not read how far $HEAD is behind $BASE" false; return 3 ;; esac
    if [ "$BEHIND_BY" -gt 0 ]; then
      update_steps "the red may already be fixed on $BASE ($BEHIND_BY commit(s) ahead of the head): update first, re-run only if it is still red"
      finish "red: $RED, and behind $BASE by $BEHIND_BY" false; return 1
    fi
    for _id in $RUNS; do step operator rerun "the App is refused re-runs" "$OG run rerun $_id -R $R --failed"; done
    finish "red: $RED" false; return 1
  fi
  [ -z "$RED" ] || NOTE="optional checks red: $RED"
  [ "$(g .isDraft)" != true ] || step app ready "a draft cannot merge" "gh pr ready $N -R $R"
  if [ "$MS" = BEHIND ]; then
    update_steps "the update moves the head and dismisses a stale approval; plan the rest on the new head once CI is green"
    finish "behind $BASE" true; return 0
  fi

  # method: ship.conf when the live repo allows it, else the one allowed, else squash
  RJ="$("$GH" api "repos/$R" 2>"$W/err")" || { finish "could not read the repo: $(head -n 1 "$W/err")" false; return 3; }
  RUL="$("$GH" api "repos/$R/rules/branches/$BASE" 2>"$W/err")" || { finish "could not read $BASE's rules: $(head -n 1 "$W/err")" false; return 3; }
  ALLOWED="$(rr_methods "$RJ" "$RUL")"
  SHIP="$("$GH" api "repos/$R/contents/.agents/ship.conf?ref=$BASE" -H "Accept: application/vnd.github.raw" 2>"$W/err")" || {
    grep -q 'HTTP 404' "$W/err" || { finish "could not read ship.conf: $(head -n 1 "$W/err")" false; return 3; }
    SHIP=""; }
  DECL="$(printf '%s\n' "$SHIP" | rr_conf method)"; DECL="$(rr_method_decl "${DECL%% *}")"
  # harbor#1418: ship.conf's review and delete-branch against the live facts; live wins, a mismatch is drift in the note
  DRIFT=""
  _d="$(printf '%s\n' "$SHIP" | rr_conf review)"
  if [ -n "$_d" ]; then
    _dn="$(rr_review_decl "$_d")"; _live="$(rr_review_live "$RUL")"
    if [ "$_dn" = invalid ]; then DRIFT="drift: ship.conf review $_d is not '<n> [code-owner]' or 'none'"
    elif [ -z "$_live" ]; then
      [ "$_dn" = 0 ] || DRIFT="ship.conf declares review $_dn but this cannot read a review rule (classic protection is 403 to the App)"
    elif [ "$_live" != "$_dn" ]; then DRIFT="drift: ship.conf says review $_dn, the live rules require $_live"; fi
  fi
  _d="$(printf '%s\n' "$SHIP" | rr_conf delete-branch)"
  if [ -n "$_d" ]; then
    _dn="$(rr_deletebranch_decl "$_d")"; _live="$(printf '%s' "$RJ" | jq -r '.delete_branch_on_merge // false')"
    if [ "$_dn" = invalid ]; then DRIFT="${DRIFT:+$DRIFT; }drift: ship.conf delete-branch $_d is not yes or no"
    elif [ "$_live" != "$_dn" ]; then DRIFT="${DRIFT:+$DRIFT; }drift: ship.conf says delete-branch $( [ "$_dn" = true ] && echo yes || echo no ), the live repo's delete_branch_on_merge is $_live"; fi
  fi
  [ -z "$DRIFT" ] || NOTE="${NOTE:+$NOTE; }$DRIFT"
  if [ -n "$DECL" ]; then
    case " $ALLOWED " in
      *" $DECL "*) M="$DECL"; MF="ship.conf" ;;
      *) finish "drift: ship.conf says method $DECL, the live repo allows only: ${ALLOWED:-nothing}" false; return 1 ;;
    esac
  else
    set -- $ALLOWED
    if [ $# -eq 1 ]; then M="$1"; MF="the only method $R allows"
    elif [ $# -eq 0 ]; then finish "the repo and its rules allow no merge method" false; return 1
    else case " $ALLOWED " in *" squash "*) M=squash ;; *) M="$1" ;; esac; MF="undeclared (no ship.conf method); allowed: $ALLOWED"; fi
  fi

  # approval: GitHub's own word, a pending review-gate status, the rules' unattributed-change flag, or a green PR that
  # GitHub still blocks and nobody approved. Every pull_request rule on the branch counts: any code-owner wins, the largest count.
  APPROVED="$(g '[.reviews[]? | select(.state == "APPROVED" and (.author.is_bot | not))] | length')"
  HUMAN_AUTHOR="$(g 'if .author.is_bot then "" else .author.login end')"
  # commits the App opened the PR for but a person authored: GitHub calls the push unattributed
  UNATTR="$(g 'if .author.is_bot then (.author.login | sub("^app/"; "")) as $a | [.commits[]? | select(([.authors[]?.login] | index($a)) | not)] | length else 0 end')"
  RULEP="$(jq -cn --argjson u "$RUL" '[$u[]? | select(.type == "pull_request") | .parameters] as $p
    | {co: any($p[]; .require_code_owner_review == true), n: ([$p[].required_approving_review_count // 0] | max // 0),
       un: any($p[]; .require_extra_approval_for_unattributed_changes == true)}')"
  rp() { printf '%s' "$RULEP" | jq -r "$1"; }
  UNATTR_RULE=""; [ "$UNATTR" -gt 0 ] && [ "$(rp .un)" = true ] && UNATTR_RULE="the base rules require an extra approval for changes the App pushed for someone else (unattributed)"
  NEED=""
  case "$RD" in
    CHANGES_REQUESTED) finish "changes requested: address the review first" false "$M" "$MF"; return 1 ;;
    REVIEW_REQUIRED) NEED="GitHub reports REVIEW_REQUIRED" ;;
  esac
  # a gate that lags an approval already given stays in WAIT; otherwise it is the missing approval, not CI
  if [ -n "$GATE" ] && [ "$APPROVED" -eq 0 ] && [ "$RD" != APPROVED ]; then
    NEED="${NEED:-$GATE is pending (awaiting review)}"; WAIT="$WAIT_CI"
  fi
  if [ -z "$NEED" ] && [ "$MS" = BLOCKED ] && [ -z "$WAIT" ] && [ "$RD" != APPROVED ]; then
    if [ "$APPROVED" -gt 0 ]; then
      finish "blocked by a rule this cannot read (approved, checks green; classic protection is 403 to the App)" false "$M" "$MF"; return 1
    fi
    if [ "$(rp .co)" = true ]; then NEED="the base rules require a code-owner review"
    elif [ "$(rp .n)" -gt 0 ]; then NEED="the base rules require $(rp .n) approval(s)"
    elif [ -n "$UNATTR_RULE" ]; then NEED="$UNATTR_RULE"
    else NEED="GitHub blocks a green PR and no rule is readable: a classic-protection review (403 to the App)"; fi
  fi
  # the rule is explicit, so it asks while CI still runs too
  if [ -z "$NEED" ] && [ "$MS" = BLOCKED ] && [ "$RD" != APPROVED ] && [ "$APPROVED" -eq 0 ]; then NEED="$UNATTR_RULE"; fi
  if [ -n "$NEED" ]; then
    if [ -n "$HUMAN_AUTHOR" ]; then
      step operator approve "$NEED, and $HUMAN_AUTHOR authored it: a second person must approve" "# ask a reviewer other than $HUMAN_AUTHOR"
    else
      step operator approve "$NEED; the App cannot approve" "$OG pr review $N -R $R --approve"
    fi
  fi
  [ -z "$WAIT" ] || NOTE="${NOTE:+$NOTE; }waiting on: $WAIT"

  # stacked PRs first, then the merge pinned to the judged head
  KIDS="$("$GH" pr list -R "$R" --base "$HEAD" --state open --json number --jq '.[].number' 2>"$W/err")" || { finish "could not list PRs stacked on $HEAD: $(head -n 1 "$W/err")" false "$M" "$MF"; return 3; }
  for _k in $KIDS; do step app retarget "#$_k is based on $HEAD; deleting it would close #$_k" "gh pr edit $_k -R $R --base $BASE"; done
  DEL=""; [ "$(printf '%s' "$RJ" | jq -r '.delete_branch_on_merge // false')" = true ] || DEL=" --delete-branch"
  step operator merge "merges are the operator's; pinned to the head judged here" "$OG pr merge $N -R $R --$M --match-head-commit $SHA$DEL"
  if [ -n "$WAIT" ]; then finish "waiting on checks, then lands" true "$M" "$MF"; else finish "ready" true "$M" "$MF"; fi
  return 0
}

RC=0
for a in "$@"; do
  t="$(target "$a")" || { echo "gate-pr-plan: '$a' is not owner/repo#n, a pull URL, or a number in a checkout with a github origin" >&2; exit 2; }
  plan "$(printf '%s' "$t" | cut -f1)" "$(printf '%s' "$t" | cut -f2)"; r=$?
  [ "$r" -le "$RC" ] || [ "$RC" -eq 3 ] || RC=$r
  [ "$r" -ne 3 ] || RC=3
done

case "$MODE" in
  json) jq -s . "$W/plans" ;;
  handover)
    # stdout is only runnable lines: an interactive zsh without interactivecomments runs a `#` as a command
    jq -r -s '.[] | select(.lands | not) | "not landing \(.pr): \(.verdict)"' "$W/plans" >&2
    jq -r -s '.[] | .steps[] | select(.who == "app") | "the App first: \(.cmd)"' "$W/plans" >&2
    jq -r -s '.[] | .steps[] | select(.who == "operator" and (.cmd | startswith("#"))) | "yours, not a command: \(.why)"' "$W/plans" >&2
    jq -r -s '.[] | .steps[] | select(.who == "operator" and (.cmd | startswith("#") | not)) | .cmd' "$W/plans" ;;
  *)
    jq -r -s '.[] |
      "── \(.pr)  \(.verdict)" + (if .method != "" then "  ·  method \(.method) (\(.method_from))" else "" end),
      (if .note != "" then "   note: \(.note)" else empty end),
      (.steps | to_entries[] | "   \(.key + 1). \(.value.who)  \(.value.what): \(.value.why)\n        \(.value.cmd)")' "$W/plans" ;;
esac
exit "$RC"
