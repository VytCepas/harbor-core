#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# guard-ask (harbor#1545) - PreToolUse: a call matching a `permissions.ask` rule gets a PreToolUse `ask` (the operator's dialog), and in auto
# mode a `deny` (below). Claude Code was measured running ask-matched calls with no prompt in auto mode, a Bash apply flag and an MCP click alike (2026-11-16).
# settings.json stays the one list: this guard keeps no copy and reads the same files Claude Code does (config dir, plus the session cwd's .claude).
# Matching: a bare `Bash` entry matches every shell call; `Bash(<glob>)` is matched against each command segment split on ; && || | and
# newlines (`*` is any run; a trailing ` *` or legacy `:*` also matches the bare prefix); a bare entry against the tool name, `mcp__<server>`
# covering that server's tools. NOT COVERED: a parenthesised rule for another tool (`Edit(...)`, `WebFetch(...)`), managed settings, and a
# command reworded past a literal prefix (env prefix, wrapper, subshell, `&`, quoting, extra spaces): harbor#1551.
# Where no human can answer, an ask auto-approves, so it is escalated to deny (floor_no_human), as guard-destroy does. On a member box the
# dispatcher decides (floor_member_stop).
# AUTO MODE DENIES (harbor#1545, operator 2026-11-17): measured after deploy, a hook `ask` in auto mode goes to the classifier, not the
# operator, so both probes ran unasked. A deny is the one verdict auto mode honours; the operator runs the call with `!`, which no hook sees.
# STANDALONE and fail-OPEN like guard-destroy: a fault exits 0 with no output.
set -u
trap 'exit 0' EXIT
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)" || exit 0
. "$DIR/library-admission.sh" || exit 0

floor_read_stdin || exit 0
TOOL="$(floor_field '.tool_name')"
[ -n "$TOOL" ] || exit 0
# shellcheck disable=SC2034 # FLOOR_TOOL: read by library-admission.sh
FLOOR_TOOL="$TOOL"
CMD=""
if floor_shell_tool "$TOOL"; then
  CMD="$(floor_field '.tool_input.command')"
  [ -n "$CMD" ] || exit 0
fi

RULES="$(floor_switch_settings_files "$(floor_field '.cwd')" | while IFS= read -r _f; do
  if [ -f "$_f" ]; then "$FLOOR_JQ" -r '.permissions.ask[]? | strings' "$_f" 2>/dev/null || :; fi
done)" || exit 0
# Metered network (status.network, operator request 2026-11-19): bin/status-network.sh writes these rules while on mobile data and
# removes them off it. Older than 5 min means its tick stopped, and a stale switch is not trusted, so they are ignored (fail-open).
METERED=""
_mr="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}/net/ask-rules"
if [ -f "$_mr" ] && [ -n "$(find "$_mr" -mmin -5 2>/dev/null)" ]; then
  METERED="$("$FLOOR_GREP" '^Bash(' "$_mr" 2>/dev/null)" || METERED=""
  [ -z "$METERED" ] || RULES="$RULES${RULES:+
}$METERED"
fi
[ -n "$RULES" ] || exit 0

HIT="$(printf '%s\n' "$RULES" | ASK_TOOL="$TOOL" ASK_CMD="$CMD" awk '
function gmatch(s, p,   n, parts, i, pos, k, last, rest) {
  n = split(p, parts, "*")
  if (n == 1) return s == p
  if (substr(s, 1, length(parts[1])) != parts[1]) return 0
  pos = length(parts[1]) + 1
  for (i = 2; i < n; i++) {
    if (parts[i] == "") continue
    k = index(substr(s, pos), parts[i]); if (!k) return 0
    pos += k - 1 + length(parts[i])
  }
  last = parts[n]; rest = length(s) - pos + 1
  if (last == "") return 1
  return rest >= length(last) && substr(s, length(s) - length(last) + 1) == last
}
function bashmatch(s, p,   bare) {
  if (p ~ /:\*$/) p = substr(p, 1, length(p) - 2) " *"
  if (gmatch(s, p)) return 1
  if (p ~ / \*$/) { bare = substr(p, 1, length(p) - 2); return s == bare }
  return 0
}
BEGIN {
  tool = ENVIRON["ASK_TOOL"]; cmd = ENVIRON["ASK_CMD"]; shell = (tool == "Bash" || tool == "Monitor")
  if (shell) {
    gsub(/&&|\|\||[;|\n]/, "\001", cmd)
    nseg = split(cmd, seg, "\001")
    for (i = 1; i <= nseg; i++) { sub(/^[ \t]+/, "", seg[i]); sub(/[ \t]+$/, "", seg[i]) }
  }
}
{
  r = $0
  if (shell) {
    if (r == "Bash" || r == tool) { print r; exit }
    if (r !~ /^Bash\(.*\)$/) next
    p = substr(r, 6, length(r) - 6)
    for (i = 1; i <= nseg; i++) if (seg[i] != "" && bashmatch(seg[i], p)) { print r; exit }
  } else if (r !~ /\(/) {
    if (tool == r || index(tool, r "__") == 1 || (r ~ /\*/ && gmatch(tool, r))) { print r; exit }
  }
}')" || exit 0
[ -n "$HIT" ] || exit 0

# shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
FLOOR_OBS_SUBJECT="${CMD:-$TOOL}"
# harbor#1278: on a member box the dispatcher decides. The fail-open trap is lifted so floor_member_stop's own refusal (exit 2) stands.
if floor_member_mode; then trap - EXIT; floor_member_stop ask "ask-rule.argv"; exit 0; fi
# THE OPERATOR'S YES IN AUTO MODE (operator 2026-11-20): pasting a `!` command for every live click was the cost of the deny (52 confirm_click
# denials 11-17..11-20). An AskUserQuestion answer is written by Claude Code from the operator's own pick, never by the model, so a
# "Yes..." to a question that quotes this exact call lets it through ONCE: any later completed run of the same call spends it, and it
# lapses after 30 min. A command must be quoted whole; confirm_click must quote its ref and the label from the server's own refusal of
# that ref, so the operator sees what the button is. Any fault reads as no yes, so the deny stands.
ask_approved() {
  _tp="$(floor_field '.transcript_path')"
  [ -n "$_tp" ] && [ -f "$_tp" ] || return 1
  if [ -n "$CMD" ]; then _call="$("$FLOOR_JQ" -cn --arg t "$TOOL" --arg c "$CMD" '{kind:"cmd",tool:$t,text:$c}')"
  else _call="$(printf '%s' "$FLOOR_IN" | "$FLOOR_JQ" -c --arg t "$TOOL" '(.tool_input.args // []) as $a
      | if $t == "mcp__harbor_chrome__confirm_click" then {kind:"click",tool:$t,args:$a,ref:([$a[] | select(startswith("-") | not)][0] // "" | if test("^(e[0-9]+|f[0-9]+e[0-9]+)$") then . else "" end)}
        else {kind:"tool",tool:$t,args:$a} end')"; fi
  [ -n "$_call" ] || return 1
  _ok="$("$FLOOR_JQ" -nR --argjson call "$_call" '
    def norm: tostring | gsub("\\s+"; " ");
    def fresh($ts): (($ts // "") | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0) as $t | (now - $t) < 1800;
    def same($u): $u.name == $call.tool and (if $call.kind == "cmd" then ($u.input.command // "") == $call.text else ($u.input.args // []) == $call.args end);
    def quoted($q; $labels): ($q | norm) as $qq |
      if $call.kind == "cmd" then $qq | contains($call.text | norm)
      elif $call.kind == "click" then $call.ref != "" and ($qq | test("(^|[^a-z0-9])" + $call.ref + "([^a-z0-9]|$)"))
        and (($labels[$call.ref] // "") as $l | $l != "" and ($qq | contains($l | norm)))
      else ($qq | contains($call.tool)) and all($call.args[]; . as $a | $qq | contains($a | norm)) end;
    reduce (inputs | fromjson? // empty | objects) as $r ({uses: {}, labels: {}, ok: false};
      if $r.type == "assistant" then
        reduce ($r.message.content[]? | objects | select(.type == "tool_use")) as $u (.; .uses[$u.id] = {name: $u.name, input: $u.input})
      elif $r.type == "user" and $r.isSidechain != true then
        reduce ($r.message.content[]? | objects | select(.type == "tool_result")) as $t (.;
          .uses[$t.tool_use_id // ""] as $u
          | if $u == null then .
            elif $u.name == "AskUserQuestion" then
              reduce (($r.toolUseResult.answers? // {}) | objects | to_entries[]) as $a (.;
                if ($a.value | norm | ascii_downcase | ltrimstr(" ") | startswith("yes")) and quoted($a.key; .labels) and fresh($r.timestamp) then .ok = true else . end)
            elif same($u) then .ok = false
            elif ($u.name | test("^mcp__harbor_chrome__(click|steps)$")) then
              reduce (($t | .content | if type == "array" then map(.text? // "") | join("\n") else tostring end)
                | scan("destructive click refused: \u0027(.+?)\u0027 \\(([a-z0-9]+)\\)")) as $m (.; .labels[$m[1]] = $m[0])
            else . end)
      else . end)
    | .ok' "$_tp" 2>/dev/null)" || return 1
  [ "$_ok" = true ]
}
DECISION=ask; WHY="so it waits for your yes"
if floor_no_human; then DECISION=deny; WHY="and no human can answer an ask here, so it is denied"
elif [ "$(floor_field '.permission_mode')" = auto ]; then
  # The merge/deploy approval gate stays the dialog alone (docs/design/approval-gate.md): a question never approves it.
  if ! printf '%s' "$HIT" | "$FLOOR_GREP" -qF gate-approve.sh && ask_approved; then DECISION=allow; WHY="and the operator answered yes to a question quoting this exact call, so it runs once"
  else
    _quote="the whole command"; [ "$TOOL" = mcp__harbor_chrome__confirm_click ] && _quote="the ref and the label from the click's refusal"
    DECISION=deny; WHY="and in auto mode an ask reaches the classifier, not the operator, so it is denied. Ask the operator with AskUserQuestion, quoting $_quote in the question; an answer starting \"Yes\" lets the next identical call through once (30 min). Or they run it as \`! <command>\` at their prompt"
  fi
fi
WHAT="this changes a live system"; REF="harbor#1545"
if [ -n "$METERED" ] && printf '%s\n' "$METERED" | "$FLOOR_GREP" -qxF "$HIT"; then
  WHAT="the network is metered (mobile data) and this downloads in bulk"; REF="status.network"
fi
"$FLOOR_JQ" -cn --arg d "$DECISION" --arg r "ask rule \`$HIT\` matched: $WHAT, $WHY ($REF)." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' || exit 0
{ floor_log_decision ask "$DECISION" "ask-rule.argv" 2>/dev/null || :; } 2>/dev/null || :
exit 0
