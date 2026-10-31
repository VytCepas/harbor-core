#!/usr/bin/env sh
# gate-pr-wait.sh (harbor#552) — wait on a pull request until the FIRST thing that
# needs a person or an agent: a review thread, a failed check, or a green finish.
#
#   sh gate-pr-wait.sh <owner/repo> <pr> [--timeout SEC] [--interval SEC]
#
# WHY. Measured on #547 and #551 (2026-09-18): a review bot posts its findings a
# few minutes after a push, while the long CI jobs run for 11–14 minutes on top of
# queueing. Waiting for CI and only then reading the review cost a full second CI
# cycle per finding round (~27 min each). This returns the moment a thread opens,
# so the fix is pushed while the first run is still going; a newer push cancels
# the superseded run (governance.yml sets cancel-in-progress off main).
#
# EXIT CODES
#   0  every check passed or was skipped, every required context of the base
#      branch is among them, the set was the same on two polls in a row, and
#      no review thread is open
#   1  a check failed (its names are printed)
#   3  an unresolved review thread is open (path and opening line are printed)
#   4  the deadline passed; the last observed state is printed
#   5  every red check is a job NO RUNNER EVER TOOK (harbor#675) or one GitHub
#      REFUSED FOR BILLING (harbor#1060): nothing failed. The re-run command, or
#      the action for a refusal, is printed.
#   2  usage error, or gh cannot read the PR, or the private layer's required-checks.tsv
#      does not compose with core's (harbor#1149): the required set is then unknown
#
# WHAT IT DOES NOT CLAIM. A reviewer slower than CI is not waited for: exit 0
# means "green, and nothing open NOW". Merging stays a separate, deliberate act.
set -u
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$DIR/library-log.sh"

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 2 ] || { usage >&2; exit 2; }
REPO="$1"; PR="$2"; shift 2
TIMEOUT=3600; INTERVAL=30
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)  [ $# -ge 2 ] || { usage >&2; exit 2; }; TIMEOUT="$2"; shift ;;
    --interval) [ $# -ge 2 ] || { usage >&2; exit 2; }; INTERVAL="$2"; shift ;;
    *) printf 'pr-wait: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
case "$REPO" in */*) ;; *) printf 'pr-wait: repo must be owner/name, got %s\n' "$REPO" >&2; exit 2 ;; esac
case "$PR$TIMEOUT$INTERVAL" in *[!0-9]*) printf 'pr-wait: pr, --timeout and --interval must be integers\n' >&2; exit 2 ;; esac
[ "$TIMEOUT" -le 7200 ] || TIMEOUT=7200
[ "$INTERVAL" -ge 10 ] || INTERVAL=10
command -v gh >/dev/null 2>&1 || { printf 'pr-wait: gh is required\n' >&2; exit 2; }

OWNER="${REPO%%/*}"; NAME="${REPO#*/}"
Q='query($o:String!,$n:String!,$p:Int!,$c:String){repository(owner:$o,name:$n){pullRequest(number:$p){
  reviewThreads(first:100,after:$c){pageInfo{hasNextPage endCursor}
    nodes{isResolved path comments(first:1){nodes{author{login} body}}}}}}}'

# one note per non-empty line of a multi-line block
log_lines() { while IFS= read -r _ll; do [ -n "$_ll" ] && log_note "$_ll"; done <<EOF_LL
$1
EOF_LL
  return 0
}

# open_threads — every unresolved thread, across ALL pages (Codex on #553: a PR
# with 100 resolved threads and a new open one read as clean on page one alone).
open_threads() {
  _cur=""; _all=""
  while :; do
    if [ -n "$_cur" ]; then
      _pg="$(gh api graphql -f query="$Q" -f o="$OWNER" -f n="$NAME" -F p="$PR" -f c="$_cur")" || return 1
    else
      _pg="$(gh api graphql -f query="$Q" -f o="$OWNER" -f n="$NAME" -F p="$PR")" || return 1
    fi
    _all="$_all$(printf '%s' "$_pg" | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved | not)
      | "  \(.path): \(.comments.nodes[0].author.login): \(.comments.nodes[0].body | gsub("[\r\n]+"; " ") | .[0:160])\n"')"
    [ "$(printf '%s' "$_pg" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')" = true ] || break
    _cur="$(printf '%s' "$_pg" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')"
  done
  printf '%s' "$_all"
}

# GREEN NEEDS A COMPLETE SET (Codex on #553): check producers register
# asynchronously, so "nothing pending" over the rows seen so far can be one fast
# check with the slow ones not yet created. Green therefore requires every
# REQUIRED context of the base branch to be present, and the same set of check
# names on two polls in a row. Protection that cannot be read leaves the second.
BASE="$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName 2>/dev/null)"
REQUIRED="$(gh api "repos/$REPO/branches/$BASE/protection" --jq '.required_status_checks.contexts[]?' 2>/dev/null || true)"
# Protection unreadable or requiring nothing (free-plan 403): the tracked declaration
# merge-check gates on is the required set, or green would pass a partial set (harbor#1073).
if [ -z "$REQUIRED" ]; then
  RCFILE="${HARBOR_GATE_REQUIRED_CHECKS:-${HARBOR_REQUIRED_CHECKS:-$DIR/../contracts/required-checks.tsv}}"
  if [ -r "$RCFILE" ]; then
    # Run from a checkout with no list handed in, the rows are core's then the private layer's (gate-required-generate.sh, harbor#1149).
    # One that does not compose is a stop, not a smaller list: green on a partial set is what this declaration exists to prevent.
    _rcrows=""
    if [ -z "${HARBOR_GATE_REQUIRED_CHECKS:-${HARBOR_REQUIRED_CHECKS:-}}" ] && [ -f "$DIR/gate-required-generate.sh" ]; then
      _rcrows="$(sh "$DIR/gate-required-generate.sh" --core "$RCFILE" 2>/dev/null)" || {
        log_fail "the private layer's required-checks.tsv does not compose with core's (or cannot be read), so the required set of $REPO is unknown"
        log_fix "sh $DIR/gate-required-generate.sh   # names the line"; log_end || :; exit 2; }
    fi
    [ -n "$_rcrows" ] || _rcrows="$(cat "$RCFILE")"
    REQUIRED="$(printf '%s\n' "$_rcrows" | awk -F'\t' -v r="$REPO" '$1 == r && $2 != "" { print $2 }')"
  fi
fi

start="$(date +%s)"; last=""; prev_names=""
while :; do
  open="$(open_threads)" || { printf 'pr-wait: cannot read %s#%s\n' "$REPO" "$PR" >&2; exit 2; }
  if [ -n "$open" ]; then
    log_fail "$REPO#$PR has an open review thread — act on it now"
    log_fix "answer or resolve the thread, then: sh bin/gate-pr-wait.sh $REPO $PR"
    log_lines "$open"; log_end || :
    exit 3
  fi
  buckets="$(gh pr checks "$PR" --repo "$REPO" --json bucket,name,link \
    --jq '.[] | "\(.bucket)\t\(.name)\t\(.link)"' 2>/dev/null || true)"
  red="$(printf '%s\n' "$buckets" | awk -F'\t' '$1=="fail" || $1=="cancel"')"
  if [ -n "$red" ]; then
    # A RED CHECK IS NOT ALWAYS A FAILURE (harbor#675). A job GitHub never
    # dispatched is cancelled with no runner, no steps and no log, and scores
    # exactly like a failing suite. Each red row is asked, and a lost one is
    # printed with its re-run — so the reader re-runs it instead of debugging a
    # suite that never started. One real failure keeps the exit at 1.
    failed=""; lost=""
    _t="$(printf '\t')"
    while IFS="$_t" read -r _b _n _l; do
      [ -n "$_n" ] || continue
      _lrc=0; _re="$(sh "$DIR/ci-lost-job.sh" "$REPO" "$_l" 2>/dev/null)" || _lrc=$?
      case "$_lrc" in
        0) lost="$lost  $_n — never started: no runner acquired it. Re-run: $_re
" ;;
        3) lost="$lost  $_n — refused for billing, not a failure: $_re
" ;;
        *) failed="$failed  $_n
" ;;
      esac
    done <<EOF_RED
$red
EOF_RED
    if [ -n "$failed" ]; then
      log_fail "$REPO#$PR has a failed check"
      log_fix "gh pr checks $PR --repo $REPO; gh run view <run> --log-failed"
      log_lines "$failed"
      [ -z "$lost" ] || { log_note "and a job GitHub lost in dispatch (not a failure):"; log_lines "$lost"; }
      log_end || :
      exit 1
    fi
    log_warn "$REPO#$PR has no failed check — GitHub lost a job in dispatch, or refused it for billing:"
    log_lines "$lost"; log_end || :
    exit 5
  fi
  last="$(printf '%s\n' "$buckets" | awk -F'\t' 'NF {n[$1]++} END {for (b in n) printf "%s=%d ", b, n[b]}')"
  names="$(printf '%s\n' "$buckets" | awk -F'\t' 'NF {print $2}' | sort -u)"
  missing=""
  if [ -n "$REQUIRED" ]; then
    missing="$(printf '%s\n' "$REQUIRED" | while IFS= read -r _r; do
      [ -n "$_r" ] || continue
      printf '%s\n' "$buckets" | awk -F'\t' -v r="$_r" '$2==r && ($1=="pass" || $1=="skipping") {f=1} END {exit !f}' || printf '%s ' "$_r"
    done)"
  fi
  if [ -n "$buckets" ] && ! printf '%s\n' "$buckets" | grep -q '^pending' \
     && [ -z "$missing" ] && [ "$names" = "$prev_names" ]; then
    log_ok "$REPO#$PR is green ($last) and no review thread is open"; log_end || :
    exit 0
  fi
  prev_names="$names"
  if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
    log_fail "gave up after ${TIMEOUT}s; last seen: ${last:-no checks yet}"
    log_fix "sh bin/gate-pr-wait.sh $REPO $PR --timeout 3600"; log_end || :
    exit 4
  fi
  sleep "$INTERVAL"
done
