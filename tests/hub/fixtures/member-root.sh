# tests/hub/fixtures/member-root.sh (harbor#1278) — a managed root with the real guards and the real member scripts, and the other lanes' three
# scripts stubbed per the interface table. Source after t_init. A copy, because the scripts find everything from their own path, never env.
MR="$T_TMP/managed/ClaudeCode/harbor"; MB="$MR/bin"; W="$T_TMP/work"; MIN="$T_TMP/in.json"
mkdir -p "$MB" "$W"
for _f in admission-hook.sh library-admission.sh admission-normalize.awk admission-self-edit.sh admission-bash.sh admission-egress.sh \
          admission-decide.sh admission-cloud.sh admission-destroy.sh admission-deliverables.sh govern-hook.sh \
          member-dispatch.sh member-post.sh member-integrity.sh member-support-guard.sh hub-tier.sh library-hub.sh library-log.sh; do
  cp "$T_ROOT/bin/$_f" "$MB/$_f"
done
cp "$T_ROOT/standards/naming/controls.tsv" "$T_ROOT/contracts/risk-tiers.tsv" "$T_ROOT/contracts/hub-vocabulary.tsv" "$MB/"
cp "$T_ROOT/tests/hub/fixtures/stubs/"*.sh "$MB/"
: > "$MB/harbor-member-mode"
printf 'hub=fixture-org/fixture-hub\nlogin=alice\nhome=%s\n' "$HOME" > "$MR/member.conf"
sh "$MB/member-dispatch.sh" --guard-table "$T_ROOT/bin/admission-install.sh" > "$MB/member-guards.tsv"
HARBOR_MEMBER_LOGIN=alice; HARBOR_MEMBER_ROLE=member; export HARBOR_MEMBER_LOGIN HARBOR_MEMBER_ROLE

m_policy() { # <jq edit of the fixture policy>: the policy hub-sync.sh will name
  jq "$1" "$T_ROOT/tests/hub/fixtures/policy.json" > "$T_TMP/policy.json"
  printf '%s\n' "$T_TMP/policy.json" > "$MB/stub-policy"
}
m_enforce() { m_policy "${1:-.} | .rollout.mode = \"enforce\" | .tiers = (.tiers // {})"; }
m_reset() { rm -f "$MB/stub-approval.log" "$MB/stub-events.log" "$MB/stub-status" "$MB/stub-file" "$MB/stub-policy" "$MB/stub-check"; rm -rf "$HOME/.local/state/harbor/hub"; }

# m_call <payload json>: M_RC, M_OUT, M_ERR, M_DEC (deny, ask, allow or silent) and M_WHY (the reason shown).
m_call() {
  printf '%s' "$1" > "$MIN"
  M_RC=0; (cd "$W" && sh "$MB/member-dispatch.sh" < "$MIN" > "$T_TMP/m.out" 2> "$T_TMP/m.err") || M_RC=$?
  M_OUT="$(cat "$T_TMP/m.out")"; M_ERR="$(cat "$T_TMP/m.err")"
  M_DEC=silent; M_WHY=""
  if [ -n "$M_OUT" ]; then
    M_DEC="$(printf '%s' "$M_OUT" | jq -r '.hookSpecificOutput.permissionDecision')"
    M_WHY="$(printf '%s' "$M_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  fi
}
m_tool() { # <tool> <tool_input json> [extra jq edit]
  jq -cn --arg t "$1" --arg w "$W" --argjson i "$2" \
    '{session_id:"s-1",transcript_path:"/t/main.jsonl",cwd:$w,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,tool_use_id:"toolu_1"}' \
    | jq -c "${3:-.}"
}
m_bash() { m_tool Bash "$(jq -cn --arg c "$1" '{command:$c,description:"a fixture"}')" "${2:-.}"; }
m_approvals() { cut -d' ' -f1 "$MB/stub-approval.log" 2>/dev/null | tr '\n' ' '; }
m_events() { cat "$MB/stub-events.log" 2>/dev/null; }
