#!/usr/bin/env sh
# admission-bash.sh (harbor#1018): the approval gate's rules. A gate tool runs only as the exact text its ask or allow
# rule names, never wrapped, copied or linked; the raw merge and live-deploy routes are refused. Then floor-install's
# side: the tools installed and pinned, and the rules written into settings.json naming those installed copies.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"
# The rules name the config dir PHYSICALLY (install-lib resolves it), so {cfg} is spelled that way too.
CLAUDE_CONFIG_DIR="$(CDPATH='' cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)"; export CLAUDE_CONFIG_DIR

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/gate.jsonl"

t_section "floor-install: the gate's tools installed beside the floor and named by the rules"
for _g in library-gate.sh gate-classify.sh gate-merge.sh gate-approve.sh gate-queue.sh gate-merge-check.sh deploy-fleet.sh; do
  t_eq "$_g installed" yes "$([ -s "$CLAUDE_CONFIG_DIR/bin/$_g" ] && echo yes || echo no)"
  # B6 blocks every session over a pinned file with no kill-switch line, so a pin here would lock the box out
  t_eq "$_g NOT content-pinned" no "$([ -e "$CLAUDE_CONFIG_DIR/.helm-pins/$_g.sha256" ] && echo yes || echo no)"
done
_b6="$(printf '{"hook_event_name":"SessionStart"}' | sh "$CLAUDE_CONFIG_DIR/bin/admission-integrity.sh" 2>/dev/null)"
t_eq "B6 names no gate file" 0 "$(printf '%s' "$_b6" | grep -c 'gate-')"
_s="$CLAUDE_CONFIG_DIR/settings.json"
t_eq "the ask rule names the installed gate-approve.sh" true \
  "$(jq --arg a "Bash($CLAUDE_CONFIG_DIR/bin/gate-approve.sh *)" '.permissions.ask | index($a) != null' "$_s")"
t_eq "the allow rules name the installed gate-merge.sh and gate-queue.sh" true \
  "$(jq --arg m "Bash($CLAUDE_CONFIG_DIR/bin/gate-merge.sh *)" --arg q "Bash($CLAUDE_CONFIG_DIR/bin/gate-queue.sh *)" \
     '(.permissions.allow | index($m) != null) and (.permissions.allow | index($q) != null)' "$_s")"
ship_rules() { jq -r '[.permissions.ask[], .permissions.allow[]] | .[] | select(test("deploy-fleet"))' "$1"; }
t_eq "the ship runner is allowed for night only (harbor#1060)" "Bash($CLAUDE_CONFIG_DIR/bin/deploy-fleet.sh night*)" "$(ship_rules "$_s")"
jq '.permissions.allow += ["Bash('"$CLAUDE_CONFIG_DIR"'/bin/deploy-fleet.sh *)"]' "$_s" > "$T_TMP/wide"
t_eq "RED-PROOF: a rule that would also allow deploy is seen" 2 "$(ship_rules "$T_TMP/wide" | grep -c .)"
t_eq "no rule names a checkout or ~/.local/bin" 0 \
  "$(jq -r '[.permissions.ask[], .permissions.allow[]] | .[] | select(test("gate-"))' "$_s" | grep -vc "^Bash($CLAUDE_CONFIG_DIR/bin/")"
t_eq "the B1 deny covers the ledger" true "$(jq '.permissions.deny | index("Edit(~/.claude/.helm-approvals/**)") != null' "$_s")"
t_eq "the B1 deny covers the ship runner's state" true "$(jq '.permissions.deny | index("Edit(~/.claude/.helm-ship/**)") != null' "$_s")"
_fv="$(sh "$T_ROOT/bin/admission-verify.sh" --dir "$CLAUDE_CONFIG_DIR" 2>&1)"
t_has "floor-verify reports the ask rule" "$_fv" "approval gate: the ask rule"
jq --arg c "/bin/sh /tmp/yes.sh" '.hooks.PermissionRequest = [{matcher: "", hooks: [{type: "command", command: $c}]}]' "$_s" > "$T_TMP/s"
cp "$_s" "$T_TMP/s.orig"; cp "$T_TMP/s" "$_s"
t_has "RED-PROOF: floor-verify fails a foreign PermissionRequest hook" "$(sh "$T_ROOT/bin/admission-verify.sh" --dir "$CLAUDE_CONFIG_DIR" 2>&1)" \
  "FAIL: approval gate: a PermissionRequest hook Harbor does not own"
jq '.permissions.ask = []' "$T_TMP/s.orig" > "$_s"
t_has "RED-PROOF: floor-verify fails a missing ask rule" "$(sh "$T_ROOT/bin/admission-verify.sh" --dir "$CLAUDE_CONFIG_DIR" 2>&1)" \
  "FAIL: approval gate: no ask rule"
cp "$T_TMP/s.orig" "$_s"
t_done
