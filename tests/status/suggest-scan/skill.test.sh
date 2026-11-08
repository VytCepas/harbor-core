#!/bin/sh
# skill.test.sh (harbor#1278, step 10) — skills/status-suggest-scan: the command the skill tells the agent to run works with no mod loaded
# and no harbor checkout, from an installed folder, on sessions already on the machine; and says "not installed" when it is not.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SK="$T_ROOT/skills/status-suggest-scan/SKILL.md"; unset CLAUDE_CONFIG_DIR   # --live reads $HOME/.claude
t_section "1 - the skill file"
t_eq "the name is the folder's" "status-suggest-scan" "$(sed -n 's/^name: //p' "$SK" | head -n 1)"
t_has "the description says when" "$(sed -n 's/^description: //p' "$SK" | head -n 1)" "USE WHEN"
t_has "and when not" "$(sed -n 's/^description: //p' "$SK" | head -n 1)" "NOT FOR"
awk '/^```sh$/ { on = 1; next } /^```$/ && on { exit } on { print }' "$SK" > "$T_TMP/cmd.sh"
t_has "it carries one command block, the scan" "$(cat "$T_TMP/cmd.sh")" "status-suggest-scan.sh"
t_hasnt "that block names no mod or pane" "$(cat "$T_TMP/cmd.sh")" "status-pane"

t_section "2 - the command runs from an installed folder with no mod loaded"
B="$HOME/.claude/bin"; mkdir -p "$B" "$HOME/.claude/projects/-fx"
cp "$T_ROOT/bin/status-suggest-scan.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$T_ROOT/bin/library-log.sh" "$B/"
NOW="$(jq -n -r 'now | todate')"
n=0
for i in 1 2 3 4; do
  f="$HOME/.claude/projects/-fx/s$i.jsonl"
  for t in mcp__fx_Flow__get_ad_performance Read mcp__fx_Flow__get_attribution Write; do
    case "$t" in
      Write) in='{"file_path":"/w/report.md","content":"x"}' ;;
      Read) in='{"file_path":"/w/a.txt"}' ;;
      *) in='{"client":"fx"}' ;;
    esac
    n=$((n + 1))
    printf '{"type":"assistant","timestamp":"%s","isSidechain":false,"message":{"content":[{"type":"tool_use","id":"%s-%s-%s","name":"%s","input":%s}]}}\n' "$NOW" "$i" "$t" "$n" "$t" "$in" >> "$f"
  done
done
OUT="$(sh "$T_TMP/cmd.sh" 2>"$T_TMP/err")"; RC=$?
t_eq "exit 0" 0 "$RC"
t_eq "one JSON object, schema 1" "1" "$(printf '%s' "$OUT" | jq -r '.schema')"
t_eq "the repeated task is found: connector report, then write document" "connector report, then write document" "$(printf '%s' "$OUT" | jq -r '.candidates[0].shape')"
t_eq "in 4 sessions" "4" "$(printf '%s' "$OUT" | jq -r '.candidates[0].sessions')"
t_eq "no mod folder exists on this box" "no" "$([ -e "$HOME/.claude/mods" ] && echo yes || echo no)"

t_section "3 - when the script is not there, the agent is told so and no zero is invented"
rm -rf "$B"
OUT="$(sh "$T_TMP/cmd.sh" 2>"$T_TMP/err")"; RC=$?
t_eq "exit 1" 1 "$RC"
t_eq "nothing on stdout" "" "$OUT"
t_has "and the reason on stderr" "$(cat "$T_TMP/err")" "is not installed here"

t_section "4 - a member box: the managed root's bin is looked in too"
M="$T_TMP/managed"; mkdir -p "$M/bin"
cp "$T_ROOT/bin/status-suggest-scan.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$T_ROOT/bin/library-log.sh" "$M/bin/"
OUT="$(HARBOR_MEMBER_ROOT="$M" sh "$T_TMP/cmd.sh" 2>"$T_TMP/err")"; RC=$?
t_eq "exit 0 from HARBOR_MEMBER_ROOT/bin" 0 "$RC"
t_eq "and the same candidate" "connector report, then write document" "$(printf '%s' "$OUT" | jq -r '.candidates[0].shape')"
t_done
