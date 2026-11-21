#!/usr/bin/env sh
# admission-ask.sh (harbor#1545): a call matching a permissions.ask rule gets a PreToolUse ask (a deny in auto mode or with no human); anything else gets no output.
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

t_section "auto mode: the operator's yes to a question quoting this exact call lets it through once"
_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
NOW="$(_iso "$(date +%s)")"; OLD="$(_iso $(( $(date +%s) - 7200 )))"
TP="$T_TMP/t.jsonl"
use() { jq -cn --arg i "$1" --arg n "$2" --argjson in "$3" '{type:"assistant",message:{content:[{type:"tool_use",id:$i,name:$n,input:$in}]}}' >> "$TP"; }
res() { jq -cn --arg i "$1" --arg c "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$i,content:[{type:"text",text:$c}]}]}}' >> "$TP"; }
ans() { # <id> <question> <answer> [timestamp] [sidechain]
  jq -cn --arg i "$1" --arg q "$2" --arg a "$3" --arg ts "${4:-$NOW}" --argjson sc "${5:-false}" \
    '{type:"user",isSidechain:$sc,timestamp:$ts,message:{content:[{type:"tool_result",tool_use_id:$i,content:"answered"}]},toolUseResult:{questions:[{question:$q}],answers:{($q):$a}}}' >> "$TP"; }
refusal() { use c1 mcp__harbor_chrome__click '{"args":["e4"]}'; res c1 "  FAIL: hand-off: destructive click refused: 'button \"Delete campaign\"' (e4) matches 'delete' — the operator confirms one call"; }
ASKQ='Click e4, button "Delete campaign", in the ads console?'
cc() { verdict mcp__harbor_chrome__confirm_click '' "$(jq -cn --arg tp "$TP" --argjson a "${1:-[\"e4\"]}" '{permission_mode:"auto",transcript_path:$tp,tool_input:{args:$a}}')"; }
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'Yes, click it'
t_eq "a yes quoting the ref and the refused label allows confirm_click" allow "$(cc)"
_ry="$(jq -cn --arg tp "$TP" '{tool_name:"mcp__harbor_chrome__confirm_click",tool_input:{args:["e4"]},permission_mode:"auto",transcript_path:$tp}' | sh "$G")"
t_has "...saying it runs once" "$_ry" 'runs once'
t_eq "...for that ref only" deny "$(cc '["e5"]')"
use k1 mcp__harbor_chrome__confirm_click '{"args":["e4"]}'; res k1 'clicked button by script'
t_eq "a completed confirm_click spends the yes" deny "$(cc)"
use q2 AskUserQuestion '{}'; ans q2 "$ASKQ" 'yes'
t_eq "a new yes after it allows the next one" allow "$(cc)"
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 'Click e4?' 'Yes'
t_eq "a yes that names the ref but not the label is not enough" deny "$(cc)"
: > "$TP"; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'Yes'
t_eq "a yes with no refusal on record has no label to check" deny "$(cc)"
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'No, leave it'
t_eq "a no denies" deny "$(cc)"
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'Yes' "$OLD"
t_eq "a yes older than 30 min has lapsed" deny "$(cc)"
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'Yes' "$NOW" true
t_eq "a subagent's record is not the operator's yes" deny "$(cc)"
: > "$TP"; refusal; use q1 Bash '{"command":"true"}'; ans q1 "$ASKQ" 'Yes'
t_eq "answers on another tool's result are not an AskUserQuestion" deny "$(cc)"
printf 'not json at all\n' > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 "$ASKQ" 'Yes'
t_eq "a broken transcript line is skipped, not fatal" allow "$(cc)"
t_eq "no transcript: the deny stands" deny "$(verdict mcp__harbor_chrome__confirm_click '' '{"permission_mode":"auto","transcript_path":"/nonexistent/t.jsonl","tool_input":{"args":["e4"]}}')"
: > "$TP"; use q1 AskUserQuestion '{}'; ans q1 'Run `acme --write x` now?' 'Yes, run it'
bv() { verdict Bash "$1" "$(jq -cn --arg tp "$TP" --arg c "$1" '{permission_mode:"auto",transcript_path:$tp,tool_input:{command:$c}}')"; }
t_eq "a command quoted whole in the question is allowed" allow "$(bv 'acme --write x')"
t_eq "...not a longer one" deny "$(bv 'acme --write x --all')"
_cfg3="$(cat "$CLAUDE_CONFIG_DIR/settings.json")"
printf '%s' '{"permissions":{"ask":["Bash(/cfg/bin/gate-approve.sh *)"]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
: > "$TP"; use q1 AskUserQuestion '{}'; ans q1 'Run `/cfg/bin/gate-approve.sh merge 12` now?' 'Yes'
t_eq "the merge/deploy approval gate is never approved by a question" deny "$(bv '/cfg/bin/gate-approve.sh merge 12')"
printf '%s' "$_cfg3" > "$CLAUDE_CONFIG_DIR/settings.json"
_rd="$(jq -cn --arg tp "$TP" '{tool_name:"mcp__harbor_chrome__confirm_click",tool_input:{args:["e9"]},permission_mode:"auto",transcript_path:$tp}' | sh "$G")"
t_has "the auto-mode deny names the AskUserQuestion way" "$_rd" 'Ask the operator with AskUserQuestion'
t_has "...and what confirm_click must quote" "$_rd" 'the ref and the label'
t_eq "default mode still shows the dialog, yes or not" ask "$(verdict Bash 'acme --write x' "$(jq -cn --arg tp "$TP" '{permission_mode:"default",transcript_path:$tp}')")"
# The label requirement removed, a yes naming only the ref passes: the "not enough" arm above can fail.
MU="$T_TMP/mut-bin"; mkdir -p "$MU"; cp "$T_ROOT/bin/library-admission.sh" "$MU/"
sed 's/and ((\$labels\[\$call.ref\] \/\/ "") as \$l | \$l != "" and (\$qq | contains(\$l | norm)))//' "$G" > "$MU/admission-ask.sh"
t_eq "the label mutant differs from the guard" yes "$(cmp -s "$G" "$MU/admission-ask.sh" || echo yes)"
: > "$TP"; refusal; use q1 AskUserQuestion '{}'; ans q1 'Click e4?' 'Yes'
_G="$G"; G="$MU/admission-ask.sh"
t_eq "and without the label check a ref-only yes is allowed" allow "$(cc)"
G="$_G"

t_section "a bare entry matches every call of that tool"
_cfg="$(cat "$CLAUDE_CONFIG_DIR/settings.json")"
printf '%s' '{"permissions":{"ask":["Bash"]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "bare Bash, any command" ask  "$(verdict Bash 'ls -la')"
t_eq "bare Bash, an MCP call" none "$(verdict mcp__harbor_chrome__click)"
printf '%s' "$_cfg" > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "bare Monitor"          ask  "$(verdict Monitor 'tail -f x')"

t_section "metered network (status.network, 2026-11-19): bulk downloads ask while status-network.sh says so"
NR="$HOME/.local/state/harbor/net"; mkdir -p "$NR"
printf '%s\n' 'Bash(docker pull *)' 'Bash(npm install*)' > "$NR/ask-rules"
t_eq "docker pull asks on mobile data"      ask  "$(verdict Bash 'docker pull ubuntu')"
t_eq "after cd && too"                       ask  "$(verdict Bash 'cd /x && npm install')"
t_eq "auto mode denies it"                   deny "$(verdict Bash 'docker pull ubuntu' '{"permission_mode":"auto"}')"
_rm="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"docker pull ubuntu"},"permission_mode":"auto"}' | sh "$G")"
t_has "the reason says metered, not a live system" "$_rm" 'the network is metered'
t_has "and names the operator's way through" "$_rm" '! <command>'
t_eq "a small command is not held"           none "$(verdict Bash 'git status')"
t_eq "a settings rule still says live system" ask "$(verdict Bash 'acme --write x')"
_rs="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"acme --write x"}}' | sh "$G")"
t_hasnt "and its reason is not the metered one" "$_rs" 'metered'
_cfg2="$(cat "$CLAUDE_CONFIG_DIR/settings.json")"; printf '{}' > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "no ask rules in settings at all: metered rules still hold" ask "$(verdict Bash 'docker pull ubuntu')"
printf '%s' "$_cfg2" > "$CLAUDE_CONFIG_DIR/settings.json"
touch -t "$(date -r $(( $(date +%s) - 600 )) +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$(( $(date +%s) - 600 ))" +%Y%m%d%H%M.%S)" "$NR/ask-rules"
t_eq "rules older than 5 min (the tick stopped) are not trusted" none "$(verdict Bash 'docker pull ubuntu')"
rm -rf "$NR"
t_eq "no rules file: unmetered, nothing held" none "$(verdict Bash 'docker pull ubuntu')"

t_section "on a member box the dispatcher decides, so no verdict is printed"
M="$T_TMP/member-bin"; mkdir -p "$M"
cp "$T_ROOT/bin/admission-ask.sh" "$T_ROOT/bin/library-admission.sh" "$M/"; : > "$M/harbor-member-mode"
_mo="$(jq -cn --arg d "$HOME/proj" '{tool_name:"Bash",tool_input:{command:"acme --write x"},cwd:$d}' | sh "$M/admission-ask.sh" 2>/dev/null)"
t_hasnt "member mode prints no ask" "x$_mo" 'permissionDecision'

t_section "the reason names the rule; faults stay silent"
_r="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"acme --write x"}}' | sh "$G")"
t_has "reason names the rule" "$_r" 'Bash(acme --write *)'
t_has "an ask's reason waits for a yes" "$_r" 'waits for your yes'
_ra="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"acme --write x"},"permission_mode":"auto"}' | sh "$G")"
t_has "an auto-mode deny tells the model the operator can run it" "$_ra" 'they run it as `! <command>`'
t_hasnt "an auto-mode deny never says it waits for a yes" "$_ra" 'waits for your yes'
t_eq "malformed stdin"       ""   "$(printf 'not json' | sh "$G")"
printf 'broken' > "$CLAUDE_CONFIG_DIR/settings.json"
t_eq "broken settings"       none "$(verdict Bash 'acme --write x')"
t_done
