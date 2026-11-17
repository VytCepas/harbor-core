#!/usr/bin/env sh
# admission-ask.sh (harbor#1545): a call matching a permissions.ask rule gets a PreToolUse ask; anything else gets no output.
set -u
. "$(dirname "$0")/../../lib/core.sh"
t_init

G="$T_ROOT/bin/admission-ask.sh"
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(acme-write mutate *)"],"ask":["Bash(acme-write mutate *--apply*)","Bash(acme --write *)","Bash(git push:*)","mcp__harbor_chrome__confirm_click","mcp__danger","mcp__glob_*","Monitor"]}}
JSON
mkdir -p "$HOME/proj/.claude"
printf '%s' '{"permissions":{"ask":["Bash(acme-sync set *--yes*)"]}}' > "$HOME/proj/.claude/settings.local.json"

verdict() { # <tool> [command] [extra json] — the decision the guard prints, "none" for a clean silence, "rc=N" for a crash
  _x="${3:-}"; [ -n "$_x" ] || _x='{}'
  _p="$(jq -cn --arg t "$1" --arg c "${2:-}" --arg d "$HOME/proj" --argjson x "$_x" '{tool_name:$t,tool_input:{command:$c},cwd:$d} + $x')" || { printf 'bad-payload'; return 0; }
  _o="$(printf '%s' "$_p" | sh "$G")"; _rc=$?
  [ "$_rc" = 0 ] || { printf 'rc=%s' "$_rc"; return 0; }
  _v="$(printf '%s' "$_o" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  printf '%s' "${_v:-none}"
}

t_section "a Bash command that matches an ask rule asks"
t_eq "apply flag"            ask  "$(verdict Bash 'acme-write mutate 1 campaigns ops.json --apply')"
t_eq "after cd &&"           ask  "$(verdict Bash 'cd /x && acme --write foo')"
t_eq "after a pipe"          ask  "$(verdict Bash 'echo hi | acme-write mutate 1 c x --apply')"
t_eq "after a semicolon"     ask  "$(verdict Bash 'echo hi; acme --write x')"
t_eq "bare prefix of ' *'"   ask  "$(verdict Bash 'acme --write')"
t_eq "legacy :* form"        ask  "$(verdict Bash 'git push origin main')"
t_eq "Monitor runs it too"   ask  "$(verdict Monitor 'acme-write mutate 1 c x --apply')"
t_eq "project-local rule"    ask  "$(verdict Bash 'acme-sync set w1 tag.json --yes')"

t_section "a near miss does not ask"
t_eq "validate-only"         none "$(verdict Bash 'acme-write mutate 1 campaigns ops.json')"
t_eq "longer word"           none "$(verdict Bash 'acme --writex')"
t_eq "longer verb"           none "$(verdict Bash 'git pushy')"
t_eq "not at segment start"  none "$(verdict Bash 'echo acme --write x')"

t_section "a tool call matches by name"
t_eq "listed tool"           ask  "$(verdict mcp__harbor_chrome__confirm_click)"
t_eq "sibling tool"          none "$(verdict mcp__harbor_chrome__click)"
t_eq "server entry"          ask  "$(verdict mcp__danger__drop)"
t_eq "server name prefix"    none "$(verdict mcp__dangerous__x)"
t_eq "glob tool rule"        ask  "$(verdict mcp__glob_x__y)"
t_eq "glob tool near miss"   none "$(verdict mcp__glo__y)"

t_section "where no human can answer, the ask becomes a deny"
t_eq "bypass mode"           deny "$(verdict Bash 'acme --write x' '{"permission_mode":"bypassPermissions"}')"
t_eq "subagent transcript"   deny "$(verdict mcp__harbor_chrome__confirm_click '' '{"transcript_path":"/x/subagents/a.jsonl"}')"
t_eq "auto mode denies (its asks reach the classifier, harbor#1545)" deny "$(verdict Bash 'acme --write x' '{"permission_mode":"auto"}')"
t_eq "auto mode denies an MCP click too" deny "$(verdict mcp__harbor_chrome__confirm_click '' '{"permission_mode":"auto"}')"
t_eq "default mode still asks" ask  "$(verdict Bash 'acme --write x' '{"permission_mode":"default"}')"
t_eq "acceptEdits still asks"  ask  "$(verdict Bash 'acme --write x' '{"permission_mode":"acceptEdits"}')"

t_section "a bare entry matches every call of that tool"
_cfg="$(cat "$CLAUDE_CONFIG_DIR/settings.json")"
printf '%s' '{"permissions":{"ask":["Bash"]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "bare Bash, any command" ask  "$(verdict Bash 'ls -la')"
t_eq "bare Bash, an MCP call" none "$(verdict mcp__harbor_chrome__click)"
printf '%s' "$_cfg" > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "bare Monitor"          ask  "$(verdict Monitor 'tail -f x')"

t_section "on a member box the dispatcher decides, so no verdict is printed"
M="$T_TMP/member-bin"; mkdir -p "$M"
cp "$T_ROOT/bin/admission-ask.sh" "$T_ROOT/bin/library-admission.sh" "$M/"; : > "$M/harbor-member-mode"
_mo="$(jq -cn --arg d "$HOME/proj" '{tool_name:"Bash",tool_input:{command:"acme --write x"},cwd:$d}' | sh "$M/admission-ask.sh" 2>/dev/null)"
t_hasnt "member mode prints no ask" "x$_mo" 'permissionDecision'

t_section "the reason names the rule; faults stay silent"
_r="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"acme --write x"}}' | sh "$G")"
t_has "reason names the rule" "$_r" 'Bash(acme --write *)'
t_eq "malformed stdin"       ""   "$(printf 'not json' | sh "$G")"
printf 'broken' > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "broken settings"       none "$(verdict Bash 'acme --write x')"
t_done
