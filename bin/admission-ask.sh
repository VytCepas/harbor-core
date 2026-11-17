#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# guard-ask (harbor#1545) - PreToolUse: a call matching a `permissions.ask` rule gets a PreToolUse `ask`, so the operator's dialog holds in auto mode,
# where Claude Code was measured running ask-matched calls with no prompt, a Bash apply flag and an MCP click alike (2026-11-16).
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
DECISION=ask; NOTE=""
if floor_no_human; then DECISION=deny; NOTE=" [no-human context: an ask would auto-approve here, so escalated to deny]"
elif [ "$(floor_field '.permission_mode')" = auto ]; then DECISION=deny; NOTE=" [auto mode: an ask goes to the classifier, not to you, so it is denied; run it yourself as \`! <command>\`]"; fi
"$FLOOR_JQ" -cn --arg d "$DECISION" --arg r "ask rule \`$HIT\` matched: this changes a live system, so it waits for your yes (harbor#1545).$NOTE" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' || exit 0
{ floor_log_decision ask "$DECISION" "ask-rule.argv" 2>/dev/null || :; } 2>/dev/null || :
exit 0
