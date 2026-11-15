#!/usr/bin/env sh
# hooks.test.sh (harbor#1278, F14, F22) — hub hooks run inside the dispatcher, last, and can only add: a deny or an ask. An allow or a rewrite is logged and has no effect.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
DD='dd if=/dev/zero of=/dev/sda'
P="$HOME/.local/state/harbor/hub/hooks/fixture-pack"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
hook() { # <shell body>: one hub hook, its digest in the policy, in enforce
  m_reset; mkdir -p "$P"
  printf '#!/bin/sh\n%s\n' "$1" > "$P/check.sh"
  m_enforce ".hooks = [{pack:\"fixture-pack\",path:\"check.sh\",sha256:\"$(sha "$P/check.sh")\"}]"
}
said() { printf "printf '%%s' '%s'" "$1"; }
ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no"}}'
ASK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}'
REWRITE='{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"true"}}}'

t_section "1 - allow is logged and ignored (F22)"
hook "$(said "$ALLOW")"
m_call "$(m_bash 'ls')"
t_eq "nothing fired: silence, not an allow" "" "$M_OUT"
t_has "logged" "$(m_events)" "check check=hub-hook-allow outcome=failed"
hook "$(said "$ALLOW")"
m_call "$(m_bash "$DD")"
t_eq "an allow doesn't answer a very-high row" deny "$M_DEC"
hook "$(said "$ALLOW")"
m_call "$(m_bash 'git reset --hard')"
t_eq "an allow doesn't answer the person's ask" ask "$M_DEC"

t_section "2 - updatedInput is dropped and logged (F14)"
hook "$(said "$REWRITE")"
m_call "$(m_bash 'ls')"
t_eq "never passed on" "" "$M_OUT"
t_has "logged" "$(m_events)" "check check=hub-hook-rewrite outcome=failed"
hook "$(said "$REWRITE")"
m_call "$(m_bash "$DD")"
t_hasnt "and a denial carries no rewrite" "$M_OUT" "updatedInput"
t_eq "the call judged is the call denied" deny "$M_DEC"

t_section "3 - a hook can add a deny or an ask"
hook "$(said "$DENY")"
m_call "$(m_bash 'ls')"
t_eq "deny" deny "$M_DEC"
t_hasnt "its own words aren't shown" "$M_WHY" '"no"'
hook 'exit 2'
m_call "$(m_bash 'ls')"
t_eq "exit 2 is a deny" deny "$M_DEC"
hook "$(said "$ASK")"
m_call "$(m_bash 'ls')"
t_eq "ask" ask "$M_DEC"
hook "$(said "$ASK")"
m_call "$(m_bash 'ls' '.agent_type = "general-subagent"')"
t_eq "an ask with no human is a deny" deny "$M_DEC"
hook "$(said "$DENY")"; echo 0 > "$MB/stub-status"
m_call "$(m_bash "$DD")"
t_eq "a hook deny isn't answered by an approval" deny "$M_DEC"
t_eq "...and no approval was consulted for it" "" "$(m_approvals)"
hook "$(said "$ASK")"; echo 0 > "$MB/stub-status"
m_call "$(m_bash "$DD")"
t_eq "approved, and the hook still asks" ask "$M_DEC"
t_has "...and the approval is spent if the person says yes" "$(cat "$HOME/.local/state/harbor/hub/open/toolu_1")" "r-"

t_section "4 - a hook that isn't the one the hub signed, or dies, is a deny"
hook 'exit 0'
printf '# changed\n' >> "$P/check.sh"
m_call "$(m_bash 'ls')"
t_eq "digest mismatch" deny "$M_DEC"
t_has "logged" "$(m_events)" "check check=hub-hook-digest outcome=failed"
hook 'exit 0'; rm -f "$P/check.sh"
m_call "$(m_bash 'ls')"
t_eq "missing" deny "$M_DEC"
hook 'exit 0'; mv "$P/check.sh" "$P/real.sh"; ln -s "$P/real.sh" "$P/check.sh"
m_call "$(m_bash 'ls')"
t_eq "a symlink" deny "$M_DEC"
hook 'exit 7'
m_call "$(m_bash 'ls')"
t_eq "a crash" deny "$M_DEC"
t_has "logged" "$(m_events)" "check check=hub-hook-run outcome=failed"
hook "printf 'not json'"
m_call "$(m_bash 'ls')"
t_eq "text with exit 0 says nothing" "" "$M_OUT"
hook "$(said '{"hookSpecificOutput":{"permissionDecision":"de')"
m_call "$(m_bash 'ls')"
t_eq "JSON cut short with exit 0 is a deny" deny "$M_DEC"
t_has "logged" "$(m_events)" "check check=hub-hook-run outcome=failed"
hook "$(said '   {"a":')"
m_call "$(m_bash 'ls')"
t_eq "with blanks before it too" deny "$M_DEC"
hook "$(said '{"hookSpecificOutput":{"permissionDecision":"allow"}} and more')"
m_call "$(m_bash 'ls')"
t_eq "good JSON with a tail is not one value" deny "$M_DEC"
hook "$(said '{"a":1}{"b":2}')"
m_call "$(m_bash 'ls')"
t_eq "two documents are not one value" deny "$M_DEC"
hook "$(said '{"a":1}')"
m_call "$(m_bash 'ls')"
t_eq "CONTROL: whole JSON with no decision says nothing" "" "$M_OUT"

t_section "5 - where they run"
hook "printf 'hook\\n' >> '$T_TMP/order'"
sed "2a\\
printf 'guard\\\\n' >> '$T_TMP/order'" "$T_ROOT/bin/admission-bash.sh" > "$MB/admission-bash.sh"
m_call "$(m_bash 'ls')"
t_eq "after the guards" "guard hook " "$(tr '\n' ' ' < "$T_TMP/order")"
: > "$T_TMP/order"
hook "printf 'hook\\n' >> '$T_TMP/order'"
m_call "$(m_tool Edit "$(jq -cn --arg p "$CLAUDE_CONFIG_DIR/settings.json" '{file_path:$p,old_string:"a",new_string:"b"}')")"
t_eq "an integrity deny doesn't run them" "" "$(cat "$T_TMP/order")"
hook "env > '$T_TMP/hook.env'"
m_call "$(m_bash 'ls')"
t_hasnt "the record file isn't handed to a hook" "$(cut -d= -f1 "$T_TMP/hook.env" | tr '\n' ' ')" "HARBOR_ADMISSION_MEMBER_RECORDS"
hook "$(said "$DENY")"
jq '.rollout.mode = "shadow"' "$T_TMP/policy.json" > "$T_TMP/p2.json"; mv "$T_TMP/p2.json" "$T_TMP/policy.json"
m_call "$(m_bash 'ls')"
t_eq "in shadow a hook deny is recorded, not enforced" silent "$M_DEC"
t_has "...recorded" "$(m_events)" "refusal rule=hub-hook"
t_done
