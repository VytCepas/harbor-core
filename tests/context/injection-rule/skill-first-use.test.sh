#!/usr/bin/env sh
# The skill-on-first-use pack through the real engine: the first use of a CLI or tool a skill owns names
# that skill once per session, and stays silent on a mention, a repeat, or a transcript that shows it read.
# Fixture skills carry the ownership keys; agent-routing is the real one, so its table is read live.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"; SK="$CFG/skills"; N=0
mkdir -p "$CFG/inject.d" "$CFG/bin" "$REPO" "$SK/alpha" "$SK/beta" "$SK/agent-routing"
cp "$T_ROOT/context-rules/user/skill-on-first-use.md" "$T_ROOT/context-rules/user/skill-first-use.sh" "$CFG/inject.d/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$T_ROOT/bin/floor-normalize.awk" "$CFG/bin/"
cp "$T_ROOT/skills/agent-routing/SKILL.md" "$SK/agent-routing/SKILL.md"
printf -- '---\nname: alpha\ndescription: "Alpha things. USE WHEN alpha work, the alpha tool. NOT FOR beta."\nowns-commands: alphacli alphatool\n---\n# alpha\n' > "$SK/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: "Beta things. USE WHEN beta work."\nowns-commands: betacli\n---\n# beta\n' > "$SK/beta/SKILL.md"
printf '{"type":"user","message":"nothing relevant"}\n' > "$T/empty.jsonl"

call() { # <tool> <command> [session] [transcript] -> note in $NOTE
  N=$((N + 1))
  jq -nc --arg t "$1" --arg c "$2" --arg s "${3-s1}" --arg p "${4-$T/empty.jsonl}" \
    '{hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,transcript_path:$p,
      tool_input:(if $t == "Bash" then {command:$c} else {description:"d",prompt:"p",subagent_type:"general-purpose",model:"haiku"} end)}' > "$T/in.json"
  NOTE="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
}

t_section "a CLI a skill owns draws one note naming the skill"
call Bash 'alphacli list --all'
t_has "names the skill" "$NOTE" 'Skill `alpha`'
t_has "gives the installed SKILL.md path" "$NOTE" "$SK/alpha/SKILL.md"
t_has "carries the USE WHEN triggers" "$NOTE" 'USE WHEN: alpha work, the alpha tool'
t_has "control: the fixture description does carry NOT FOR" "$(cat "$SK/alpha/SKILL.md")" 'NOT FOR'
t_hasnt "stops before NOT FOR" "$NOTE" 'NOT FOR'
call Bash 'cd /x && betacli new "a | b"' s2
t_has "fires after a leading cd" "$NOTE" 'Skill `beta`'
call Bash 'FOO=1 env BAR=2 /opt/bin/alphatool go' s3
t_has "fires through assignments and a path" "$NOTE" 'Skill `alpha`'

t_section "a mention of the CLI is silent"
call Bash 'grep alphacli notes.md' s4
t_eq "grep" "" "$NOTE"
call Bash 'git commit -m "alphacli is documented (betacli too)"' s4
t_eq "a commit message" "" "$NOTE"
call Bash 'echo alphacli > f; cat alphacli.log | head' s4
t_eq "echo, cat and a file name" "" "$NOTE"
call Bash "$(printf 'cat <<EOF\nalphacli list\nbetacli x\nEOF')" s4
t_eq "a heredoc body" "" "$NOTE"
call Bash 'command -v alphacli betacli; f=$(command -v alphacli)' s4
t_eq "a command -v lookup" "" "$NOTE"
call Bash 'command alphacli list' s18
t_has "while command <cli> really runs it" "$NOTE" 'Skill `alpha`'
call Bash 'ls /Users/x/skills/alpha' s4
t_eq "a path" "" "$NOTE"
call Bash 'alphacli list' s4
t_has "the real command in the same session still fires, the mentions spent nothing" "$NOTE" 'Skill `alpha`'

t_section "once per skill per session"
call Bash 'alphacli again' s4
t_eq "the second call is silent" "" "$NOTE"
call Bash 'alphatool other' s4
t_eq "another CLI of the same skill is silent" "" "$NOTE"
call Bash 'betacli x' s4
t_has "another skill still fires" "$NOTE" 'Skill `beta`'
call Bash 'alphacli list' s5
t_has "a new session fires again" "$NOTE" 'Skill `alpha`'

t_section "a transcript that shows the skill was read is silent"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/alpha/SKILL.md"}}]}}\n' "$SK" > "$T/read.jsonl"
call Bash 'alphacli list' s6 "$T/read.jsonl"
t_eq "a Read of the SKILL.md" "" "$NOTE"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"beta"}}]}}\n' > "$T/skill.jsonl"
call Bash 'betacli x' s7 "$T/skill.jsonl"
t_eq "a Skill tool call" "" "$NOTE"
call Bash 'alphacli list' s7 "$T/skill.jsonl"
t_has "a Skill call for another skill does not count" "$NOTE" 'Skill `alpha`'
printf '{"attachment":{"content":"read %s/alpha/SKILL.md and \\"file_path\\":\\"%s/alpha/SKILL.md\\""}}\n' "$SK" "$SK" > "$T/echo.jsonl"
call Bash 'alphacli list' s8 "$T/echo.jsonl"
t_has "the path quoted in a note is not a read" "$NOTE" 'Skill `alpha`'
call Bash 'alphacli list' s9 /nonexistent.jsonl
t_eq "an unreadable transcript is silent" "" "$NOTE"
call Bash 'alphacli list' s10 ''
t_eq "no transcript path is silent" "" "$NOTE"

t_section "the Agent tool, and the section inlined live"
call Agent '' s11
t_has "an Agent call names agent-routing" "$NOTE" 'Skill `agent-routing`'
t_has "with its installed path" "$NOTE" "$SK/agent-routing/SKILL.md"
t_has "the table rows are inlined" "$NOTE" '`haiku` | `medium` | Read-only work'
t_has "all of them" "$NOTE" '`opus` | default | Coordination'
t_has "control: the next section exists in the skill" "$(cat "$SK/agent-routing/SKILL.md")" 'Rules that are not obvious'
t_hasnt "and stops at the next section" "$NOTE" 'Rules that are not obvious'
call Agent '' s11
t_eq "a second Agent call is silent" "" "$NOTE"
call Task '' s12
t_has "the Task tool name counts as Agent" "$NOTE" 'Skill `agent-routing`'
sed 's/| `opus` | default |/| `opus` | max |/' "$SK/agent-routing/SKILL.md" > "$T/ar" && cp "$T/ar" "$SK/agent-routing/SKILL.md"
call Agent '' s13
t_has "an edit to the skill reaches the next note" "$NOTE" '`opus` | max |'

t_section "the cached index follows an edit to a skill"
call Bash 'gammacli go' s16
t_eq "an unowned CLI is silent" "" "$NOTE"
sleep 1   # [ -nt ] compares whole seconds
sed 's/^owns-commands: betacli/owns-commands: betacli gammacli/' "$SK/beta/SKILL.md" > "$T/b" && cp "$T/b" "$SK/beta/SKILL.md"
call Bash 'gammacli go' s17
t_has "a CLI added to owns-commands fires on the next call" "$NOTE" 'Skill `beta`'

t_section "fail open"
call Bash 'alphacli list' s14
mv "$SK" "$T/skills-gone"
call Bash 'alphacli list' s15
t_eq "no skills dir is silent" "" "$NOTE"
mv "$T/skills-gone" "$SK"
t_eq "garbage payload: exit 0" 0 "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" /bin/sh "$CFG/bin/injection-rule.sh" >/dev/null 2>&1; echo $?)"
t_eq "a note never denies" 0 "$(CLAUDE_CONFIG_DIR="$CFG" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>/dev/null | grep -c permissionDecision)"
t_done
