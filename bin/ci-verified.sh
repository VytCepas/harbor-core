#!/usr/bin/env sh
# ci-verified.sh (harbor#679) — is this push to main a tree CI already passed on its PR? Then do not run it twice.
#
#   sh ci-verified.sh <sha> <before>   prints verified=true|false and base=<sha>|"" and why; appends both to $GITHUB_OUTPUT
#
# THE RULE. A squash merge's tree is the PR head's tree when the head already held `before` (main's previous tip).
# The PR's own run tested refs/pull/N/merge, and with `before` in the head that merge IS the head tree. So the push
# is verified when ALL hold: <sha> is the merge commit of a PR; that PR's head has the same tree as <sha>; `before`
# is an ancestor of (or equal to) the head; and governance passed on the head as a pull_request run.
# ANYTHING ELSE IS false, and false runs the suites as before: a stale base, a direct push, an unreadable API,
# a missing run. Only ever skips work; never turns a red into a green (the relays still read a real verdict).
#
# `base` (harbor#1289) is for the push that is NOT verified. On a push to main HARBOR_BASE (origin/main) is the pushed commit
# itself, so bin/suite-select.sh sees an empty changeset and runs every suite. When this script identifies the merged PR, base is
# merge-base(the PR's head, <before>), the commit the PR branched from as far as main was concerned: diffing base..<sha> covers
# the PR's changes AND everything main gained since it branched, the cross-PR interaction set the selector should judge. It is
# EMPTY (the full pool, as before) when there is no PR, the API does not answer, the answer is not a full sha, or anything is
# doubtful. Like verified, it only ever narrows work the selector would still be asked to justify.
#
# POSIX sh, git, jq, curl (HARBOR_CURL swaps in a fake). Token from GH_TOKEN, sent as a header, never in a URL.
set -eu
. "$(dirname -- "$0")/log-lib.sh"
log_init ci-verified

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
esac
[ $# -eq 2 ] || { log_fail "want <sha> <before>, got $# argument(s)"; log_fix "sh $0 --help"; exit 2; }
SHA="$1"; BEFORE="$2"
REPO="${GITHUB_REPOSITORY:-$(repo_slug)}"   # Actions always sets it; a hand run names this checkout's origin (harbor#1149)
API="${GITHUB_API_URL:-https://api.github.com}/repos/$REPO"
CURL="${HARBOR_CURL:-curl}"

BASE=""   # set once the merged PR is identified and the API names a merge-base; every verdict prints it, empty or not
verdict() { # <true|false> <why>
  printf 'verified=%s\nbase=%s\n' "$1" "$BASE"
  [ -z "${GITHUB_OUTPUT:-}" ] || printf 'verified=%s\nbase=%s\n' "$1" "$BASE" >> "$GITHUB_OUTPUT"
  if [ "$1" = true ]; then log_ok "$2"; else log_note "not verified, the suites run: $2"; fi
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '### already verified? %s\n%s\n' "$1" "$2" >> "$GITHUB_STEP_SUMMARY"
  log_end || :; exit 0
}
api() { # <path> — the JSON, or nothing on any failure
  "$CURL" -fsS -H "Authorization: Bearer ${GH_TOKEN:-}" -H 'Accept: application/vnd.github+json' "$API/$1" 2>/dev/null || :  # secret-seam: Actions GITHUB_TOKEN (entry github-actions-token)
}

[ -n "$REPO" ] || verdict false "no repository is named (GITHUB_REPOSITORY is unset and this checkout has no github.com origin)"
case "$BEFORE" in ''|*[!0-9abcdef]*|0000000000000000000000000000000000000000) verdict false "no previous tip ($BEFORE)" ;; esac
TREE="$(git rev-parse "$SHA^{tree}" 2>/dev/null || :)"
[ -n "$TREE" ] || verdict false "cannot read the tree of $SHA"

PR="$(api "commits/$SHA/pulls" | jq -r --arg s "$SHA" '[.[] | select(.merge_commit_sha == $s)][0].number // empty' 2>/dev/null || :)"
[ -n "$PR" ] || verdict false "$SHA is not the merge commit of a PR (a direct push, or the API did not answer)"
HEAD="$(api "pulls/$PR" | jq -r '.head.sha // empty' 2>/dev/null || :)"
[ -n "$HEAD" ] || verdict false "cannot read PR #$PR's head"
# One compare serves both answers: `status` (did the head hold main's previous tip?) and the merge-base (harbor#1289).
CMPJ="$(api "compare/$BEFORE...$HEAD")"
CMP="$(printf '%s' "$CMPJ" | jq -r '.status // empty' 2>/dev/null || :)"
_mb="$(printf '%s' "$CMPJ" | jq -r '.merge_base_commit.sha // empty' 2>/dev/null || :)"
case "$CMP" in ahead|identical|diverged|behind)
  case "$_mb" in
    *[!0-9abcdef]*|'') ;;
    *) if [ "${#_mb}" -eq 40 ]; then BASE="$_mb"; fi ;;
  esac ;;
esac
HTREE="$(api "git/commits/$HEAD" | jq -r '.tree.sha // empty' 2>/dev/null || :)"
[ "$HTREE" = "$TREE" ] || verdict false "PR #$PR's head tree ${HTREE:-unread} is not main's $TREE"
case "$CMP" in ahead|identical) ;; *) verdict false "PR #$PR's head does not contain main's previous tip $BEFORE (${CMP:-unread}): its run tested another merge" ;; esac
RUN="$(api "actions/workflows/governance.yml/runs?head_sha=$HEAD&event=pull_request&status=success&per_page=1" \
  | jq -r '.workflow_runs[0].html_url // empty' 2>/dev/null || :)"
[ -n "$RUN" ] || verdict false "no passing pull_request run of governance on PR #$PR's head $HEAD"
verdict true "same tree as PR #$PR's head $HEAD, which passed: $RUN"
