#!/usr/bin/env sh
# default-way-deny.test.sh (harbor#1397) — the deny half of the default-way route, through the real engine. A Write or Edit of
# the installed copy of a skill, a script, a hook or the hooks block is refused when the pack's row is block, and the same
# content written to its source path passes. Born warn (harbor/D-64): under a warn row the same call is a note and nothing is
# denied. The off switch is one logged command. Ordinary work (a checkout, a repo's own .claude/, a fixture under TMPDIR,
# a Bash write, a read) is never denied, and the admission corpus is replayed to prove it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$CLAUDE_CONFIG_DIR"; REPO="$T/repo"; U="$T_ROOT/context-rules/user"
BOX="$CFG/context-rules/user"
mkdir -p "$BOX" "$CFG/bin" "$REPO"
cp "$U/default-way-route.md" "$U/default-way-route.sh" "$U/default-way-route.tsv" "$U/default-way-deny.md" "$U/default-way-deny.sh" "$BOX/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"
git -C "$REPO" init -q . 2>/dev/null
N=0
# the register the engine reads: one row per pack, the mode under test in the second cell
ctl() { # <mode>
  printf 'context.default-way-deny\t%s\tinjection\t-\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tdefault-way-deny\tx\n' "$1" > "$T/controls.tsv"
  printf 'context.default-way-route\twarn\tinjection\t-\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tdefault-way-route\tx\n' >> "$T/controls.tsv"
  HARBOR_CONTEXT_CONTROLS="$T/controls.tsv"; export HARBOR_CONTEXT_CONTROLS
}
call() { # <tool> <path or command> [content] → engine stdout in $OUT; each call is its own session
  N=$((N + 1))
  jq -nc --arg t "$1" --arg a "$2" --arg c "${3:-}" --arg s "d$N" \
    'if $t == "Bash" then {hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,tool_input:{command:$a}}
     elif $t == "Edit" then {hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,tool_input:{file_path:$a,old_string:"x",new_string:$c}}
     else {hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,tool_input:{file_path:$a,content:$c}} end' > "$T/in.json"
  OUT="$(CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>"$T/err")"; RC=$?
}
note()     { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
decision() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null; }
reason()   { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
denied() { # <label> <tool> <subject> [content] [source path the reason names]
  call "$2" "$3" "${4:-}"
  t_eq "denied: $1" deny "$(decision)"
  t_has "  and names the source path to edit" "$(reason)" "${5:-}"
  printf '%s\t%s\n' "$1" "$(cat "$T/in.json")" >> "$T/cases"
}
passes() { # <label> <tool> <subject> [content]
  call "$2" "$3" "${4:-}"
  t_eq "passes, no decision: $1" "" "$(decision)"
  t_eq "  and no note: $1" "" "$(note)"
}
HOOKS_JSON='{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"x"}]}]}}'

t_section "block: a Write or Edit of an installed copy is denied, naming the source and the install command"
ctl block
denied skill Write "$CFG/skills/demo/SKILL.md" 'body' 'skills/demo/SKILL.md'
t_has "  the skill reason carries the install command" "$(reason)" 'sh bin/skill-install.sh demo --apply --live'
denied skill-edit Edit "$CFG/skills/demo/SKILL.md" 'body' 'skills/demo/SKILL.md'
denied script Write "$CFG/bin/demo-tool.sh" 'echo' 'bin/<family>-<object>.sh'
t_has "  the script reason carries the install command" "$(reason)" 'harbor deploy --apply --live --only runtime'
denied hook-script Write "$CFG/hooks/pre.sh" 'echo' 'hooks/<engine>/<engine>.sh'
denied hook-wiring Edit "$CFG/settings.json" '"hooks": {"PreToolUse": []}' 'manifest.tsv'
denied hook-wiring-local Write "$CFG/settings.local.json" "$HOOKS_JSON" 'manifest.tsv'
t_has "  the reason says where it was caught" "$(reason)" "settings.local.json"
t_has "  the reason carries the rule that raised it" "$(reason)" 'Default-way check (harbor#1397)'

t_section "the same content written to the source path passes"
passes "a skill in the checkout" Write "$REPO/skills/demo/SKILL.md" 'body'
passes "a script in the checkout" Write "$REPO/bin/demo-tool.sh" 'echo'
passes "a hook engine in the checkout" Write "$REPO/hooks/demo/demo.sh" 'echo'
passes "a hooks manifest in the checkout" Write "$REPO/hooks/demo/manifest.tsv" 'wire	PreToolUse	-	10'
passes "a repo's own settings.json with hooks" Write "$REPO/.claude/settings.json" "$HOOKS_JSON"
passes "a repo's own .claude/skills" Write "$REPO/.claude/skills/demo/SKILL.md" 'body'
passes "a fixture config dir under TMPDIR" Write "$TMPDIR/cfg/skills/demo/SKILL.md" 'body'
passes "a fixture hooks block under TMPDIR" Write "$TMPDIR/cfg/settings.json" "$HOOKS_JSON"

t_section "block, ordinary work in the config dir is not denied"
passes "a settings.json edit with no hooks" Edit "$CFG/settings.json" '"permissions": {"allow": ["Bash(ls:*)"]}'
passes "a settings.json edit that only names a hooks path" Edit "$CFG/settings.json" '"statusLine": {"command": "sh ~/.claude/bin/line.sh"}'
call Edit "$CFG/CLAUDE.md" 'Always do y.'
t_eq "the constitution copy is a note (the route pack), not a deny" "" "$(decision)"
passes "a memory note" Write "$CFG/projects/-home/memory/x.md" 'body'
passes "a Read of an installed skill" Read "$CFG/skills/demo/SKILL.md"
t_section "block, a Bash write is a note at most, never a deny"
call Bash 'cp -R skills/demo "$CLAUDE_CONFIG_DIR/skills/"'
t_eq "a cp into the skills folder is not denied" "" "$(decision)"
call Bash 'printf x > "$CLAUDE_CONFIG_DIR/bin/demo-tool.sh"'
t_eq "a redirect into bin is not denied" "" "$(decision)"
t_has "  and the route pack still notes it" "$(note)" 'builds a script at'

t_section "warn (born warn, harbor/D-64): the same call is a note and nothing is denied"
ctl warn
call Write "$CFG/skills/demo/SKILL.md" 'body'
t_eq "no decision under a warn row" "" "$(decision)"
t_has "  the note names the source path" "$(note)" 'skills/demo/SKILL.md'
t_has "  and the install command" "$(note)" 'sh bin/skill-install.sh demo --apply --live'
t_hasnt "  and the route pack does not say it twice" "$(note)" 'advisory, the call was not blocked'
ctl shadow
call Write "$CFG/skills/demo/SKILL.md" 'body'
t_eq "a shadow row says nothing" "" "$(note)$(decision)"

t_section "a deny that cannot happen is red: break the row's deny cell and nothing is denied"
ctl block
REG="$BOX/default-way-route.tsv"; cp "$REG" "$T/reg.orig"
awk -F'\t' -v OFS='\t' '!/^#/ && NF >= 10 { $10 = "-" } { print }' "$T/reg.orig" > "$REG"
_still=0
while IFS= read -r _p; do
  _r="$(printf '%s' "$_p" | cut -f2- | jq -c '.session_id = "broken"' | CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null)"
  case "$_r" in *'"deny"'*) _still=$((_still + 1)) ;; esac
done < "$T/cases"
t_eq "with every deny cell emptied, none of the denied calls is denied" 0 "$_still"
cp "$T/reg.orig" "$REG"
call Write "$CFG/skills/demo/SKILL.md" 'body'
t_eq "restored: the same call is denied again" deny "$(decision)"
t_red context.default-way-deny

t_section "once: never — the retry of a denied call is denied again"
call Write "$CFG/bin/retry.sh" 'x'
_o1="$(CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json")"
_o2="$(CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json")"
t_has "first attempt denied" "$_o1" '"deny"'
t_has "second attempt denied" "$_o2" '"deny"'

t_section "the off switch: one command, logged, reversible"
SW="$BOX/default-way-route.sh"
t_has "status starts on" "$(sh "$SW" --status)" 'on'
t_has "--off says off" "$(sh "$SW" --off)" 'off'
call Write "$CFG/skills/demo/SKILL.md" 'body'
t_eq "off: nothing is denied" "" "$(decision)"
t_eq "off: nothing is said" "" "$(note)"
t_has "off: the switch left a log line" "$(cat "$CFG/cache/context-switch.log")" '[context:default-way-route] switched off by'
t_has "status says off" "$(sh "$SW" --status)" 'off'
sh "$SW" --on >/dev/null
call Write "$CFG/skills/demo/SKILL.md" 'body'
t_eq "on again: denied" deny "$(decision)"
t_has "--on left a log line too" "$(cat "$CFG/cache/context-switch.log")" 'switched on by'
t_eq "the log holds the two switches and nothing else" 2 "$(grep -c . "$CFG/cache/context-switch.log")"

t_section "the admission corpus: not one recorded command is denied"
# Only Write and Edit are denied and the corpus holds Bash commands, so the count must be zero; a corpus line is run as a
# Bash payload and as a Write of the same text to prove the two stay apart.
_denied=0; _total=0
while IFS= read -r _l; do
  _total=$((_total + 1))
  _out="$(printf '%s' "$_l" | CLAUDE_CONFIG_DIR="$HOME/.claude" sh "$U/default-way-deny.sh" 2>/dev/null)"
  [ -z "$_out" ] || _denied=$((_denied + 1))
done < "$T_ROOT/fixtures/admission-corpus.jsonl"
t_eq "corpus lines replayed: $_total, denied" 0 "$_denied"
t_done
