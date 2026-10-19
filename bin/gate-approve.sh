#!/usr/bin/env sh
# gate-approve.sh (harbor#1018) — the operator's approval, given by a click on this command's permission prompt.
#
#   <cfg>/bin/gate-approve.sh merge <owner/repo> <pr> <head-sha>
#   <cfg>/bin/gate-approve.sh deploy <owner/repo> <default-branch-sha>
#
# An `ask` rule names this installed copy, so every call shows Claude Code's own dialog, which the agent cannot
# answer; the floor guard refuses every other spelling. merge: the PR's head must still be <head-sha>, CI on it
# green and merge-check clean, then a squash bound to that sha. deploy: the default branch must still be <sha>,
# then the runner deploys it (deploy-fleet.sh deploy <repo> --sha <sha> --approved, under a one-shot token), which
# verifies and restores.
# Red is refused even when approved: there is no override. Every answer is a ledger row; success closes the queue
# row. Exit 0 done, 1 refused, 2 usage. Refuses outright when the click cannot be trusted (gate_trust).
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -P -- "$HERE" && pwd -P)"
. "$HERE/log-lib.sh"
. "$HERE/gate-lib.sh"
log_init gate-approve
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
_hex40() { case "$1" in *[!0-9abcdef]*) return 1 ;; esac; [ "${#1}" -eq 40 ]; }
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  merge)  [ $# -eq 4 ] && gate_repo_ok "$2" && _hex40 "$4" && case "$3" in ''|*[!0-9]*) false ;; esac || { usage >&2; exit 2; } ;;
  deploy) [ $# -eq 3 ] && gate_repo_ok "$2" && _hex40 "$3" || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac
gate_init gate-approve.sh
gate_ancestry "$GATE_BIN/gate-approve.sh $*"
gate_trust
ACT="$1"; R="$2"
gate_fetch_conf "$R"
if [ "$ACT" = merge ]; then
  N="$3"; A="$4"; QID="$(gate_qid merge "$R" "$N" "$A")"
  log_head "approved: merge $R#$N at $A"
  H="$(gate_pr_head "$N")"
  if [ "$H" != "$A" ]; then
    gate_ledger approve-merge "$R $N $A" "refused-stale head=$H"
    die "$R#$N is now at $H, not the approved $A: an approval covers one exact head" "$GATE_BIN/gate-approve.sh merge $R $N $H"
  fi
  gate_merge_pr "$N" "$A" approve-merge
  gate_queue_close "$QID" merged
  log_end; exit $?
fi
S="$3"; QID="$(gate_qid deploy "$R" "$S")"
log_head "approved: deploy $R at $S"
M="$(gh api "repos/$R/commits/$GATE_MAIN" --jq .sha 2>/dev/null)" || die "could not read $R $GATE_MAIN" "gh api repos/$R/commits/$GATE_MAIN"
if [ "$M" != "$S" ]; then
  gate_ledger approve-deploy "$R $S" "refused-stale main=$M"
  die "$R $GATE_MAIN is now at $M, not the approved $S: an approval covers one exact commit" "$GATE_BIN/gate-approve.sh deploy $R $M"
fi
[ -n "$(gate_conf "$GATE_ROOT" apply)" ] || die "$R has no apply line in .agents/ship.conf on $GATE_MAIN: nothing to deploy" "gh api repos/$R/contents/.agents/ship.conf"
[ -f "$GATE_BIN/deploy-fleet.sh" ] || die "the runner $GATE_BIN/deploy-fleet.sh is not installed" "harbor deploy --apply --live   # from a terminal"
# The one-shot token (contract §5a.4): the runner takes --approved only while it exists, and consumes it. A session
# cannot write <cfg>/.helm-approvals, and guard-bash refuses --approved typed in a session, so only this click makes one.
TOK="$GATE_STATE/approved/$QID"
mkdir -p "$GATE_STATE/approved" && chmod 700 "$GATE_STATE/approved" && date -u +%Y-%m-%dT%H:%M:%SZ >"$TOK" \
  || die "could not write the approval token $TOK" "ls -ld $GATE_STATE"
rc=0; sh "$GATE_BIN/deploy-fleet.sh" deploy "$R" --sha "$S" --approved || rc=$?
rm -f "$TOK"   # one shot: whether or not the runner consumed it
if [ "$rc" -eq 0 ]; then
  gate_ledger approve-deploy "$R $S" deployed; gate_queue_close "$QID" deployed; log_ok "$R deployed at $S"
else
  gate_ledger approve-deploy "$R $S" "runner-failed rc=$rc"
  log_fail "the runner did not deploy $R at $S (exit $rc): its lines above say why"; log_nofix "docs/design/approval-gate.md"
fi
log_end
