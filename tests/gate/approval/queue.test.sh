#!/usr/bin/env sh
# gate-queue.sh (harbor#1018, ship contract §4 and §5a.2-3): unattended code queues an approval instead of asking for
# it; each row is an approval.open on the bus, kind approval in the obligations ledger (⧗N); a close, or the queue
# file itself on reconcile, closes it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/gate/approval/fixture.sh"
Q() { cat "$HOME/.local/state/harbor/approvals/queue.jsonl"; }
ob() { # <fold|reconcile> [register] → the ledger's rows as {id, kind, state, title}
  rm -f "$T_TMP/obl/.fold.lock"
  HARBOR_OBLIGATION_DIR="$T_TMP/obl" HARBOR_SCOPE_CACHE_DIR="$T_TMP/cache" HARBOR_STATUS_OBLIGATION_KINDS="${2:-$T_ROOT/contracts/obligation-kinds.tsv}" \
    CLAUDE_BIN=/nonexistent sh "$T_ROOT/bin/status-obligations.sh" "$1" >"$T_TMP/ob.out" 2>&1
  jq -c '[.obligations[] | {id, kind, state, title}]' "$T_TMP/obl/current.json" 2>/dev/null || echo '[]'
}
MID="merge-acme_widgets-7-aaaaaaaaaaaa"; DID="deploy-acme_widgets-cccccccccccc"

t_section "add: one row in the contract's shape and id, the exact approve command, an approval.open"
ag_world
ag_run gate-queue.sh add merge "$AG_R" "$SHA_A" 7 --reason "protected: bin/guard-bash.sh (guard)"
t_eq "exit 0" 0 "$RC"
t_eq "stdout is the id" "$MID" "$(grep -v '^  note:' "$T_TMP/out")"
t_eq "the row carries the exact approve command" "$GB/gate-approve.sh merge $AG_R 7 $SHA_A" "$(Q | jq -r .command)"
t_eq "the row's keys are the contract's" '["command","id","kind","pr","reason","repo","sha","ts"]' "$(Q | jq -c 'keys')"
t_eq "the id is <kind>-<owner>_<name>-<pr>-<sha12>" "$MID" "$(Q | jq -r .id)"
ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M" --reason "protected: policy/constitution.md"
t_eq "a deploy id has no pr" "$DID" "$(Q | tail -1 | jq -r .id)"
t_eq "...and its command is approve deploy" "$GB/gate-approve.sh deploy $AG_R $SHA_M" "$(Q | tail -1 | jq -r .command)"
ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M" --reason "again"
t_eq "the same approval twice is one row" 2 "$(Q | grep -c .)"
t_eq "two approval.open events, subject = id, each with a deadline and a title" "$MID $DID" \
  "$(cat "$T_TMP"/bus/*.jsonl | jq -r -s '[.[] | select(.kind == "approval.open" and .data.deadline_ts != null and .data.title != null) | .subject] | join(" ")')"

t_section "list: the open rows, each with what to run"
t_has "the merge row" "$(sh "$GB/gate-queue.sh" list 2>/dev/null)" "run: $GB/gate-approve.sh merge $AG_R 7 $SHA_A"
t_eq "--json: two open rows" 2 "$(sh "$GB/gate-queue.sh" list --json 2>/dev/null | jq length)"

t_section "the obligations ledger folds them as kind approval"
t_eq "two approval rows, open" "[\"approval:$DID open\",\"approval:$MID open\"]" "$(ob fold | jq -c 'map("\(.id) \(.state)") | sort')"
t_has "...titled for the operator" "$(ob fold)" "approve $MID: protected"
grep -v '^approval	' "$T_ROOT/contracts/obligation-kinds.tsv" > "$T_TMP/kinds-noapproval.tsv"; rm -rf "$T_TMP/obl"
t_eq "RED-PROOF: without the register row they open nothing" '[]' "$(ob fold "$T_TMP/kinds-noapproval.tsv")"
rm -rf "$T_TMP/obl"; ob fold >/dev/null

t_section "close: by the tool, or by the queue file on reconcile"
ag_run gate-queue.sh close "$MID" refused
t_eq "exit 0" 0 "$RC"
t_eq "one open row left" 1 "$(sh "$GB/gate-queue.sh" list --json 2>/dev/null | jq length)"
t_eq "the approval.close folds it closed" closed "$(ob fold | jq -r --arg i "approval:$MID" '.[] | select(.id == $i) | .state')"
ag_run gate-queue.sh close "$MID" refused
t_eq "closing a closed row: exit 1" 1 "$RC"
jq -cn --arg i "$DID" '{id: $i, ts: "2026-10-07T00:00:00Z", closed: true, outcome: "closed elsewhere"}' >> "$HOME/.local/state/harbor/approvals/queue.jsonl"
t_eq "a row closed only in the queue file is still open after a fold" open "$(ob fold | jq -r --arg i "approval:$DID" '.[] | select(.id == $i) | .state')"
t_eq "...and closed by the reconciler, from the queue (source approval-queue)" closed "$(ob reconcile | jq -r --arg i "approval:$DID" '.[] | select(.id == $i) | .state')"
t_has "...which says so" "$(grep -h approval-queue "$T_TMP/obl/ledger.jsonl")" '"source":"approval-queue"'
ag_run gate-queue.sh add merge "$AG_R" short 7 --reason x
t_eq "a malformed sha is a usage error" 2 "$RC"
ag_run gate-queue.sh add merge "$AG_R" "$SHA_A" --reason x
t_eq "a merge with no pr is a usage error" 2 "$RC"
ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M" 7 --reason x
t_eq "a deploy with a pr is a usage error" 2 "$RC"
ag_run gate-queue.sh add deploy "$AG_R" "$SHA_M"
t_eq "no --reason is a usage error" 2 "$RC"
t_done
