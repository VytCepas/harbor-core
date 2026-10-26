#!/usr/bin/env sh
# ci-wait.sh (harbor#1367) — a PR's CI verdict, woken by the event bus: one GitHub read per finished job, never a poll loop.
#
#   sh ci-wait.sh <owner/repo>#<n> | <github.com pull URL> [--timeout S]
#   harbor event ci …                       the same: a sub-verb of `harbor event`, which hands it here
#
# It reads `gh pr checks` once, then sleeps on `event-bus.sh wait` for the next ci.job.done (CONTRACTS/event-kinds.tsv)
# and reads again, a few times over 30 s because GitHub posts a verdict after the job's own hook. A job on a runner
# this box does not host emits nothing, so each sleep is capped at HARBOR_CI_WAIT_BACKSTOP (300 s) and the read
# runs anyway: a slower answer, never a missed one.
#
# NOT CI: `review/decision` (project-init scaffolds' review-status.yml) stays pending until a person approves. A
# wait for "nothing pending" took it for CI and sat out its 40-minute deadline on 2026-10-25 with 18 checks green.
# The contexts in NOT_CI are named in the verdict and never waited on; HARBOR_CI_NOT_CHECKS replaces the list.
#
# Prints one line: `<owner/repo>#<n>: green|red|pending (<count> <bucket>, …; not CI: <name> <bucket>)`.
# Exit 0 green · 1 red · 3 deadline, still running (as `harbor event wait`) · 2 usage · 4 GitHub unreadable.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
usage() { awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
case "${1:-}" in -h|--help) usage; exit 0 ;; '') usage >&2; exit 2 ;; esac
# The verdict is the one line on stdout; every refusal goes through the house log on stderr.
. "$HERE/log-lib.sh"; LOG_FD=2; log_init ci-wait
die() { log_fail "$2"; log_nofix "sh $0 --help"; log_end >/dev/null 2>&1 || :; exit "$1"; }  # <exit code> <why>

NOT_CI="${HARBOR_CI_NOT_CHECKS-review/decision}"
BACKSTOP="${HARBOR_CI_WAIT_BACKSTOP:-300}"; case "$BACKSTOP" in ''|*[!0-9]*|0) BACKSTOP=300 ;; esac
SETTLE="${HARBOR_CI_WAIT_SETTLE:-2 5 10 15}"
TARGET="$1"; shift; TIMEOUT=1800
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) [ $# -ge 2 ] || die 2 "--timeout needs seconds"; TIMEOUT="$2"; shift 2 ;;
    *) die 2 "unknown argument $1" ;;
  esac
done
case "$TIMEOUT" in ''|*[!0-9]*|0) die 2 "--timeout needs seconds above 0" ;; esac

case "$TARGET" in
  https://github.com/*/*/pull/*) _p="${TARGET#https://github.com/}"; REPO="${_p%%/pull/*}"; N="${_p##*/pull/}"; N="${N%%[/?#]*}" ;;
  */*'#'*) REPO="${TARGET%%#*}"; N="${TARGET##*#}" ;;
  *) die 2 "give <owner/repo>#<n> or a github.com pull URL, not $TARGET" ;;
esac
case "$REPO" in ''|*[!A-Za-z0-9._/-]*|*/*/*) die 2 "$REPO is not owner/repo" ;; */*) ;; *) die 2 "$REPO is not owner/repo" ;; esac
case "$N" in ''|*[!0-9]*) die 2 "$N is not a PR number" ;; esac
command -v gh >/dev/null 2>&1 || die 4 "gh is not on PATH"
command -v jq >/dev/null 2>&1 || die 4 "jq is not on PATH"

now() { date +%s; }
# REQUIRED checks the base branch names (classic protection or a ruleset), read once: green waits until each has reported.
# On 2026-10-26 a mirror job passed before GitHub posted the required public-ci, and the wait said green (#1370).
required() {
  _b="$(gh pr view "$N" -R "$REPO" --json baseRefName --jq .baseRefName 2>/dev/null)" || _b=""
  case "$_b" in ''|*[!A-Za-z0-9._/-]*) return 0 ;; esac
  { gh api "repos/$REPO/branches/$_b" --jq '.protection.required_status_checks.contexts[]?' 2>/dev/null || :
    gh api "repos/$REPO/rules/branches/$_b" --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null || :
  } | sort -u | tr '\n' '\t'
}
REQ="$(required)"
# One read: sets V (green, red, pending, none or error) and LINE. `gh pr checks` exits 8 while anything is pending,
# so its output decides, not its exit code. A PR with no checks gets no JSON, only "no checks reported" on stderr:
# that is none, not an unreadable GitHub.
read_checks() {
  _j="$(gh pr checks "$N" -R "$REPO" --json name,bucket 2>&1)" || :
  case "$_j" in "no checks reported"*) _j='[]' ;; esac
  _r="$(printf '%s' "$_j" | jq -r --arg not "$NOT_CI" --arg req "$REQ" '
    ($not | split(" ")) as $n
    | ($req | split("\t") | map(select(length > 0))) as $rq
    | ([.[].name]) as $have | ($rq | map(select(. as $x | $have | index($x) | not))) as $miss
    | [.[] | select(.name as $x | $n | index($x) | not)] as $ci
    | [.[] | select(.name as $x | $n | index($x))] as $nc
    | ($ci | map(.bucket)) as $b
    | (if ($ci | length) == 0 then "none" elif ($b | index("pending")) then "pending"
       elif ($b | any(. == "fail" or . == "cancel")) then "red" else "green" end)
    | (if (. == "green" or . == "none") and ($miss | length) > 0 then "pending" else . end) as $v
    | "\($v)\t\($ci | group_by(.bucket) | map("\(length) \(.[0].bucket)") | join(", "))\t\($nc | map("\(.name) \(.bucket)") | join(", "))\t\($miss | join(", "))"
  ' 2>/dev/null)" || _r=""
  if [ -z "$_r" ]; then V=error; LINE="$REPO#$N: GitHub did not answer"; return; fi
  V="${_r%%	*}"; _r="${_r#*	}"; _counts="${_r%%	*}"; _r="${_r#*	}"; _nc="${_r%%	*}"; _miss="${_r#*	}"
  LINE="$REPO#$N: $V (${_counts:-no checks yet}${_nc:+; not CI: $_nc}${_miss:+; required, not reported yet: $_miss})"
}
verdict() { # exits on a settled read
  case "$V" in
    green) printf '%s\n' "$LINE"; exit 0 ;;
    red) printf '%s\n' "$LINE"; exit 1 ;;
    error) ERRORS=$((ERRORS + 1)); [ "$ERRORS" -lt 3 ] || die 4 "$LINE, three reads running" ;;
    *) ERRORS=0 ;;
  esac
}

DL=$(( $(now) + TIMEOUT )); ERRORS=0
read_checks; verdict
while :; do
  _left=$(( DL - $(now) ))
  [ "$_left" -gt 0 ] || { printf '%s\n' "${LINE% (*}: still running after ${TIMEOUT}s (${LINE#* (}"; exit 3; }
  _s="$BACKSTOP"; [ "$_left" -ge "$_s" ] || _s="$_left"
  # 0: a job finished somewhere on this box; 3: the backstop ran out. Either way the next step is a read.
  sh "$HERE/event-bus.sh" wait '"kind":"ci\.job\.done"' --timeout "$_s" >/dev/null 2>&1 || :
  for _d in $SETTLE; do
    [ $(( DL - $(now) )) -gt "$_d" ] || break
    sleep "$_d"; read_checks; verdict
    [ "$V" = pending ] || [ "$V" = none ] || break
  done
done
