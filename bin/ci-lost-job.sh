#!/usr/bin/env sh
# ci-lost-job.sh (harbor#675) — was this red check a job no runner ever took?
#
#   sh ci-lost-job.sh <owner/repo> <check-link>
#
#   <check-link> is what `gh pr checks --json link` prints for an Actions job:
#   https://github.com/<owner>/<repo>/actions/runs/<run>/job/<job>
#
# EXIT CODES
#   0  lost by dispatch: every annotation on the check run says no runner
#      acquired it. Prints the command that re-runs THAT job.
#   1  not lost: a real failure, a cancel with some other reason, or no
#      annotation at all
#   2  usage error, a link that is not an Actions job, or unreadable annotations
#   3  refused for billing (harbor#1060): every annotation says the account's
#      payments failed or its spending limit is reached. Nothing failed. Prints
#      the action: the run is re-run locally once the runner switch flips
#
#   sh ci-lost-job.sh --billing-pattern   print the billing phrase (an ERE);
#      bin/ci-runners.sh matches with it, so there is one phrase, not two
#   sh ci-lost-job.sh --runner-pattern    print the phrases GitHub's own runner annotates a job with when it lost its
#      connection mid-job (an ERE); `ci-runners.sh rerun-lost` matches with it (harbor#1060). Exit codes above are unchanged.
#
# WHY. GitHub cancels a queued job it could not dispatch and annotates the check
# run "The job was not acquired by Runner of type self-hosted even after multiple
# attempts". The job has no runner, no steps and no log, so `gh pr checks` scores
# it like any other red check. Measured 2026-09-17..24: 8 such jobs in 1,257,
# spread over every kind of job, each read as a failing suite until somebody
# opened the annotation. Re-running it is a repair with no judgment in it; the
# read that tells the two apart is this one, and it lives in one place so
# gate-pr-wait.sh and gate-merge-check.sh cannot drift apart on the phrase.
#
# EVERY ANNOTATION, NOT ANY. A job that ran, failed and was ALSO annotated is a
# failure first; calling it lost would send someone to re-run a real red. Zero
# annotations is not lost either — that is the ordinary shape of a failed step.
set -eu
LOG_FD=2   # stdout is this tool's answer (the re-run command), so the log goes to stderr
. "$(dirname -- "$0")/library-log.sh"
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 2; }

# GitHub's refusal text for an unpaid account; the operator rule is NEVER to raise the limit.
BILLING_PATTERN='spending limit|payments have failed'
# GitHub's text when the runner itself lost the server mid-job (2026-10-06: BrokerServer TaskCanceledException on harbor-linux).
# Two phrases and no more: "The operation was canceled." is a person's cancel or a timeout, and is never matched.
RUNNER_PATTERN='lost communication with the server|received a shutdown signal'
case "${1:-}" in --billing-pattern) printf '%s\n' "$BILLING_PATTERN"; exit 0 ;; esac
case "${1:-}" in --runner-pattern) printf '%s\n' "$RUNNER_PATTERN"; exit 0 ;; esac
case "${1:-}" in -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ $# -eq 2 ] || { printf 'usage: sh ci-lost-job.sh <owner/repo> <check-link>\n' >&2; exit 2; }
REPO="$1"; LINK="$2"
case "$REPO" in */*) ;; *) die "repo must be owner/name, got $REPO" "sh bin/ci-lost-job.sh owner/name <check-link>" ;; esac

# The run and job ids come out of the link's path, and nothing else from it is
# trusted: both must be all digits before either reaches an API path.
RUN="$(printf '%s' "$LINK" | sed -n 's#.*/actions/runs/\([0-9][0-9]*\)/job/[0-9][0-9]*.*#\1#p')"
JOB="$(printf '%s' "$LINK" | sed -n 's#.*/actions/runs/[0-9][0-9]*/job/\([0-9][0-9]*\).*#\1#p')"
[ -n "$RUN" ] && [ -n "$JOB" ] || die "not an Actions job link: $LINK" "pass the link gh pr checks --json link prints for an Actions job"

LOST_PHRASE='was not acquired by Runner'
GH="${HARBOR_GH:-gh}"   # a test swaps in a fake
msgs="$($GH api "repos/$REPO/check-runs/$JOB/annotations" --jq '.[].message' 2>/dev/null)" \
  || die "cannot read the annotations of check run $JOB" "gh auth status"
[ -n "$msgs" ] || exit 1
if printf '%s\n' "$msgs" | grep -vqF "$LOST_PHRASE"; then
  if ! printf '%s\n' "$msgs" | grep -Evqi "$BILLING_PATTERN"; then
    printf 'refused for billing, not a failure: do not raise the spending limit; it is re-run locally once the runner switch flips (sh bin/ci-runners.sh tick, harbor#1060)\n'
    exit 3
  fi
  exit 1
fi
# `--job`, NOT `--failed` (Codex on #692): gh defines --failed as "only failed
# jobs", and a lost job is CANCELLED — so --failed could leave it untouched and
# re-run an unrelated real failure instead. The link's /job/<id> is the job's
# databaseId, which is what --job takes; gh's warning is about the /jobs/<n>
# step URL, which the parser above never accepts.
printf 'gh run rerun --job %s --repo %s   # run %s\n' "$JOB" "$REPO" "$RUN"
exit 0
