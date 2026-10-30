#!/usr/bin/env sh
# The approval gate's merges (harbor#1018): gate-merge.sh merges an unprotected green PR at its exact head and queues a
# protected one; gate-approve.sh merge merges what the operator clicked, at the sha clicked, only when green. Hermetic:
# stub gh, sandbox config dir. Each refusal has a mutant that must go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/gate/approval/fixture.sh"

t_section "an unprotected PR, green on its head: merged by gate-merge.sh, bound to that head"
ag_world
ag_run gate-merge.sh "$AG_R" 7
t_eq "exit 0" 0 "$RC"
t_eq "one squash, bound to the head by --match-head-commit" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
t_has "merge-stack judged the head's runs on the manifest's workflow" "$(cat "$GF/calls.log")" "run list -R $AG_R --workflow ci.yml --commit $SHA_A"
t_eq "the ledger row: action, args, outcome" "merge-auto	$AG_R 7 $SHA_A	merged" "$(ag_ledger)"
t_eq "the ledger row carries the args hash" "$(printf '%s' "$AG_R 7 $SHA_A" | shasum -a 256 | cut -c1-64)" "$(cut -f4 "$CFG/.helm-approvals/ledger.tsv")"

t_section "a protected PR: refused by gate-merge.sh, queued, and the approve command printed"
ag_world; ag_files "$SHA_A" docs/a.md bin/admission-bash.sh
ag_run gate-merge.sh "$AG_R" 7
t_eq "exit 1" 1 "$RC"
t_eq "nothing merged" "" "$(ag_merged)"
t_has "the refusal prints the exact approve command" "$OUT" "$GB/gate-approve.sh merge $AG_R 7 $SHA_A"
t_has "...and names the protected path" "$OUT" "protected: bin/admission-bash.sh (guard)"
t_eq "the FAIL's next line is its fix (contracts/logging.md)" "  fix: $GB/gate-approve.sh merge $AG_R 7 $SHA_A" \
  "$(printf '%s\n' "$OUT" | awk '/^  FAIL:/ { f = 1; next } f { print; exit }')"
t_hasnt "...so the log never flags itself" "$OUT" "no fix line followed the FAIL"
t_eq "one queue row" 1 "$(grep -c . "$HOME/.local/state/harbor/approvals/queue.jsonl")"
t_eq "...with the command" "$GB/gate-approve.sh merge $AG_R 7 $SHA_A" "$(jq -r .command "$HOME/.local/state/harbor/approvals/queue.jsonl")"
t_has "an approval.open on the bus, subject = the queue id" "$(cat "$T_TMP"/bus/*.jsonl)" '"kind":"approval.open","subject":"merge-acme_widgets-7-aaaaaaaaaaaa"'
t_eq "ledger: queued-protected" "merge-auto	$AG_R 7 $SHA_A	queued-protected" "$(ag_ledger)"
ag_run gate-merge.sh "$AG_R" 7
t_eq "a second refusal does not queue twice" 1 "$(grep -c . "$HOME/.local/state/harbor/approvals/queue.jsonl")"

t_section "renames and deletions: both paths are judged"
ag_world; ag_files "$SHA_A" "docs/x.sh=>bin/admission-x.sh"
ag_run gate-merge.sh "$AG_R" 7
t_eq "a rename INTO a protected path is refused" 1 "$RC"
ag_world; ag_files "$SHA_A" "bin/admission-x.sh=>docs/x.sh"
ag_run gate-merge.sh "$AG_R" 7
t_eq "a rename OUT of a protected path is refused" 1 "$RC"
ag_world; ag_files "$SHA_A" -CONSTITUTION.md
ag_run gate-merge.sh "$AG_R" 7
t_eq "a deletion of a protected path is refused" 1 "$RC"
ag_world; ag_files "$SHA_A" .agents/ship.conf
ag_run gate-merge.sh "$AG_R" 7
t_eq "the manifest is protected whatever the register says" 1 "$RC"
ag_world; ag_files "$SHA_A" .github/workflows/ci.yml
ag_run gate-merge.sh "$AG_R" 7
t_eq ".github/ is protected whatever the register says" 1 "$RC"
ag_mutant "M1 the rename's old path is not judged" library-gate.sh 's/jq -r .\.files\[\] | \.filename, (\.previous_filename \/\/ empty)./jq -r ".files[] | .filename"/'
ag_files "$SHA_A" "bin/admission-x.sh=>docs/x.sh"; ag_run gate-merge.sh "$AG_R" 7
t_eq "M1: the mutant merges a rename out of the floor" 0 "$RC"

t_section "red is refused on both routes, approved or not"
ag_world; echo 1 > "$GF/watch/900"; echo failure > "$GF/view/900"
ag_run gate-merge.sh "$AG_R" 7
t_eq "gate-merge.sh: a red run, exit 1" 1 "$RC"
t_has "...naming the run" "$OUT" "CI run 900 is red"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "gate-approve.sh: a red run, approved, exit 1" 1 "$RC"
t_eq "nothing merged on either route" "" "$(ag_merged)"
ag_world; printf 'CI gate\tfail\t1m\thttps://example.invalid/run/2\n' > "$GF/checks/7"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "gate-approve.sh: a failing check (merge-check) refuses" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
t_eq "...ledger: refused-red" "approve-merge	$AG_R 7 $SHA_A	refused-red" "$(ag_ledger)"
ag_mutant "M2 the merge skips merge-stack" library-gate.sh 's|sh "\$GATE_BIN/gate-merge-stack.sh" merge "\$GATE_TMP/plan"|gh pr merge "$1" -R "$R" --squash|'
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "M2: without merge-stack a red PR merges" 0 "$RC"

t_section "the repo's own .agents/required-checks.tsv, as merged on GitHub, is the gate (contract 5a.6)"
ag_world; printf '%s\tlint\n' "$AG_R" > "$GF/contents/.agents/required-checks.tsv"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a required check that never reported refuses, approved or not" 1 "$RC"
t_has "...naming it" "$OUT" "lint"
t_eq "...nothing merged" "" "$(ag_merged)"
rm "$GF/contents/.agents/required-checks.tsv"; ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "without one, and with no branch protection, nothing gates the merge, so it is refused" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"

t_section "an approval covers one PR at one sha"
ag_world; echo "$SHA_B" > "$GF/pr/7.head"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "approved for A, head now B: exit 1" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
t_has "...and the new approve command names B" "$OUT" "gate-approve.sh merge $AG_R 7 $SHA_B"
t_eq "...ledger: refused-stale" "approve-merge	$AG_R 7 $SHA_A	refused-stale head=$SHA_B" "$(ag_ledger)"
ag_mutant "M3 approve does not compare the head" gate-approve.sh 's/if \[ "\$H" != "\$A" \]; then/if false; then/'
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "M3: the second wall, merge-stack's pin, still refuses (needs-rebase)" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
ag_mutant "M3b ...nor is the plan pinned" library-gate.sh "s/'repo %s\\\\ncheckout %s\\\\npr %s head %s\\\\n' \"\\\$R\" \"\\\$GATE_ROOT\" \"\\\$1\" \"\\\$2\"/'repo %s\\\\ncheckout %s\\\\npr %s\\\\n' \"\\\$R\" \"\\\$GATE_ROOT\" \"\\\$1\"/"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "M3b: with both walls gone the mutant merges the head nobody clicked" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_B" "$(ag_merged)"

t_section "an approval for one PR is not an approval for another (harbor#1018)"
ag_world; echo OPEN > "$GF/pr/8.state"; echo "$SHA_B" > "$GF/pr/8.head"; ag_files "$SHA_B" docs/b.md
ag_run gate-approve.sh merge "$AG_R" 8 "$SHA_A"
t_eq "PR 8 approved with PR 7's sha: exit 1" 1 "$RC"
t_eq "...nothing merged, neither PR" "" "$(ag_merged)"
t_eq "...ledger: refused-stale against PR 8's own head" "approve-merge	$AG_R 8 $SHA_A	refused-stale head=$SHA_B" "$(ag_ledger)"
ag_run gate-approve.sh merge "$AG_R" 9 "$SHA_A"
t_eq "a PR that does not exist: exit 1, nothing merged" "1:" "$RC:$(ag_merged)"

t_section "each answer appends exactly one ledger row (action, target, sha, result)"
ag_world; ag_files "$SHA_A" bin/admission-bash.sh
ag_run gate-merge.sh "$AG_R" 7
_n0="$(grep -c . "$CFG/.helm-approvals/ledger.tsv")"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a merging approval adds one row" 1 "$(( $(grep -c . "$CFG/.helm-approvals/ledger.tsv") - _n0 ))"
t_eq "...whose result is merged" "approve-merge	$AG_R 7 $SHA_A	merged" "$(ag_ledger | tail -1)"
ag_world; echo "$SHA_B" > "$GF/pr/7.head"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a refused approval adds one row, not zero and not two" 1 "$(grep -c . "$CFG/.helm-approvals/ledger.tsv")"
ag_world; printf 'CI gate\tfail\t1m\thttps://example.invalid/run/1\n' > "$GF/checks/7"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a red-refused approval adds one row" 1 "$(grep -c . "$CFG/.helm-approvals/ledger.tsv")"
ag_world; ag_mutant "M6 the stale refusal writes no row" gate-approve.sh 's/gate_ledger approve-merge "\$R \$N \$A" "refused-stale head=\$H"/:/'
echo "$SHA_B" > "$GF/pr/7.head"; ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "M6: the mutant leaves no row" 0 "$(grep -c . "$CFG/.helm-approvals/ledger.tsv" 2>/dev/null || echo 0)"
ag_restore gate-approve.sh

t_section "an approved protected PR merges, and its queue row closes"
ag_world; ag_files "$SHA_A" bin/admission-bash.sh
ag_run gate-merge.sh "$AG_R" 7
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "exit 0" 0 "$RC"
t_eq "merged at A" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
t_eq "the queue row is closed" true "$(tail -1 "$HOME/.local/state/harbor/approvals/queue.jsonl" | jq .closed)"
t_has "an approval.close on the bus" "$(cat "$T_TMP"/bus/*.jsonl)" '"kind":"approval.close","subject":"merge-acme_widgets-7-aaaaaaaaaaaa"'

t_section "only the installed copy runs, and only on a trusted click"
ag_world; mkdir -p "$T_TMP/elsewhere"; cp "$GB/gate-approve.sh" "$GB/library-gate.sh" "$GB/library-log.sh" "$GB/library-fs.sh" "$T_TMP/elsewhere/"
RC=0; sh "$T_TMP/elsewhere/gate-approve.sh" merge "$AG_R" 7 "$SHA_A" >"$T_TMP/out" 2>&1 || RC=$?
t_eq "a copy elsewhere refuses" 1 "$RC"
t_has "...naming the installed path" "$(cat "$T_TMP/out")" "the gate runs only as $GB/gate-approve.sh"
ln -s "$GB/gate-approve.sh" "$T_TMP/elsewhere/link.sh"
RC=0; sh "$T_TMP/elsewhere/link.sh" merge "$AG_R" 7 "$SHA_A" >"$T_TMP/out" 2>&1 || RC=$?
t_eq "a symlink to the installed copy refuses" 1 "$RC"
t_has "...as not the installed tool" "$(cat "$T_TMP/out")" "is not the installed gate-approve.sh"
t_eq "...nothing merged" "" "$(ag_merged)"
jq '.permissions.ask = []' "$CFG/settings.json" > "$T_TMP/s" && mv "$T_TMP/s" "$CFG/settings.json"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "no ask rule: nothing asked anyone, so refused" 1 "$RC"
t_has "...saying so" "$OUT" "is not in $CFG/settings.json, so nothing asked the operator"
ag_world
jq --arg c "/bin/sh /tmp/yes.sh" '.hooks.PermissionRequest = [{matcher: "", hooks: [{type: "command", command: $c}]}]' "$CFG/settings.json" > "$T_TMP/s" && mv "$T_TMP/s" "$CFG/settings.json"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a foreign PermissionRequest hook: the click is not trusted" 1 "$RC"
mkdir -p "$T_TMP/proj/.claude"; printf '{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"echo allow"}]}]}}\n' > "$T_TMP/proj/.claude/settings.local.json"
ag_world
RC=0; ( cd "$T_TMP" && CLAUDE_PROJECT_DIR="$T_TMP/proj" "$GB/gate-approve.sh" merge "$AG_R" 7 "$SHA_A" ) >/dev/null 2>&1 </dev/null || RC=$?
t_eq "...also when a project's settings.local.json carries it" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
ag_mutant "M4 the trust check is skipped" gate-approve.sh 's/^gate_trust$/: gate_trust/'
jq '.permissions.ask = []' "$CFG/settings.json" > "$T_TMP/s" && mv "$T_TMP/s" "$CFG/settings.json"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "M4: the mutant merges with no ask rule" 0 "$RC"

t_section "the kill switch, and a repo that never opted in"
ag_world; : > "$CFG/.harbor-autoship.off"
ag_run gate-merge.sh "$AG_R" 7
t_eq "while .harbor-autoship.off exists, no unattended merge" 1 "$RC"
t_has "...saying so" "$OUT" "the kill switch"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "...the operator's approval is not unattended, so it still merges" 0 "$RC"
ag_world; rm "$GF/contents/.agents/ship.conf"
ag_run gate-merge.sh "$AG_R" 7
t_eq "no .agents/ship.conf on main: nothing is unattended" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
ag_world; : > "$CFG/.harbor-autoship.off"
ag_mutant "M5 the kill switch is not read" library-gate.sh 's|gate_killed() { \[ -e "\$GATE_CFG/.harbor-autoship.off" \]; }|gate_killed() { false; }|'
ag_run gate-merge.sh "$AG_R" 7
t_eq "M5: the mutant merges under the kill switch" 0 "$RC"
t_done
