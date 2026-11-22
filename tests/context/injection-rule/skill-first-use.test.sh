#!/usr/bin/env sh
# The skill-on-first-use pack through the real engine: the first use of a CLI or tool a skill owns names
# that skill once per session, and stays silent on a mention, a repeat, or a transcript that shows it read.
# Fixture skills carry the ownership keys; agent-routing is the real one, so its table is read live.
# harbor#1591: a still-unread skill gets a one-line reminder on every later owned call; owns-content matches the
# call's input; a gate CLI denies until the skill is read. Mutations seen red: the reminder branch removed (the
# reminder asserts fail), `del(.description)` dropped (the description assert fails), the gate's told-check removed
# (the never-named assert fails), the warn arm of the row ignored (the downgrade assert fails). The reminder runs
# on the next owned call and every 10th after, at most 5 per session; a gate entry may name `cli:subcommand`.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"; SK="$CFG/skills"; N=0
mkdir -p "$CFG/context-rules/user" "$CFG/bin" "$REPO" "$SK/alpha" "$SK/beta" "$SK/agent-routing" "$SK/delta" "$SK/epsilon"
cp "$T_ROOT/context-rules/user/skill-on-first-use.md" "$T_ROOT/context-rules/user/skill-first-use.sh" "$CFG/context-rules/user/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$T_ROOT/bin/admission-normalize.awk" "$CFG/bin/"
cp "$T_ROOT/skills/agent-routing/SKILL.md" "$SK/agent-routing/SKILL.md"
printf -- '---\nname: alpha\ndescription: "Alpha things. USE WHEN alpha work, the alpha tool. NOT FOR beta."\nowns-commands: alphacli alphatool\n---\n# alpha\n' > "$SK/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: "Beta things. USE WHEN beta work."\nowns-commands: betacli\n---\n# beta\n' > "$SK/beta/SKILL.md"
printf -- '---\nname: delta\ndescription: "Delta prose. USE WHEN writing delta text. NOT FOR code."\nowns-content: "(ž[^ž]*){3}"\ngate-commands: sendcli:new sendcli:reply\n---\n# delta\n' > "$SK/delta/SKILL.md"
printf -- '---\nname: epsilon\ndescription: "A broken regex. USE WHEN never."\nowns-content: "(["\n---\n# epsilon\n' > "$SK/epsilon/SKILL.md"
printf '{"type":"user","message":"nothing relevant"}\n' > "$T/empty.jsonl"

call() { # <tool> <command or content> [session] [transcript] [bash description] -> note in $NOTE, decision in $DEC
  N=$((N + 1))
  jq -nc --arg t "$1" --arg c "$2" --arg s "${3-s1}" --arg p "${4-$T/empty.jsonl}" --arg d "${5-run it}" \
    '{hook_event_name:"PreToolUse",tool_name:$t,session_id:$s,transcript_path:$p,
      tool_input:(if $t == "Bash" then {command:$c,description:$d} elif $t == "Write" then {file_path:"/x/note.txt",content:$c}
                  else {description:"d",prompt:"p",subagent_type:"general-purpose",model:"haiku"} end)}' > "$T/in.json"
  OUTJ="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>/dev/null)"
  NOTE="$(printf '%s' "$OUTJ" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
  DEC="$(printf '%s' "$OUTJ" | jq -r '[.hookSpecificOutput.permissionDecision // "", .hookSpecificOutput.permissionDecisionReason // ""] | join(" ") | gsub("^ +| +$"; "")' 2>/dev/null)"
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

t_section "the full note once per skill per session, then one line while it stays unread"
call Bash 'alphacli again' s4
t_has "the second call carries the reminder" "$NOTE" 'Skill `alpha` owns this call and is still unread'
t_hasnt "and not the full note again" "$NOTE" 'USE WHEN'
call Bash 'alphatool other' s4
t_eq "the owned call after a reminder is quiet" "" "$NOTE"
for _i in 3 4 5 6 7 8 9; do call Bash 'alphatool other' s4; done
t_eq "so is the 9th" "" "$NOTE"
call Bash 'alphatool other' s4
t_has "another CLI of the same skill reminds on the 10th" "$NOTE" 'still unread'
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat %s/alpha/SKILL.md"}}]}}\n' "$SK" > "$T/cat.jsonl"
call Bash 'alphacli again' s4 "$T/cat.jsonl"
t_eq "once the skill is read, silence" "" "$NOTE"
call Bash 'alphacli again' s4
t_eq "the read is remembered, even once the transcript no longer shows it" "" "$NOTE"
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
t_has "a second Agent call is the one-line reminder" "$NOTE" 'Skill `agent-routing` owns this call and is still unread'
t_hasnt "without the table again" "$NOTE" '`haiku` | `medium`'

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

t_section "owns-content: the call's input names the skill"
call Write 'Žinia: žinutė apie žąsį ir žolę.' c1
t_has "a Write whose content matches names the skill" "$NOTE" 'Skill `delta` owns this call'
t_has "with its USE WHEN" "$NOTE" 'USE WHEN: writing delta text'
call Write 'dar viena žinia, žąsis ir žolė' c1
t_has "the next matching call is the reminder" "$NOTE" 'Skill `delta` owns this call and is still unread'
call Write 'only one ž here' c2
t_eq "under the threshold is silent" "" "$NOTE"
call Bash 'ls -la' c2 "$T/empty.jsonl" 'žžž in the label only'
t_eq "Bash's description is the agent's label, never the content" "" "$NOTE"
call Bash "$(printf 'cat > f <<EOF\nžinia žąsis žolė\nEOF')" c3
t_has "a heredoc body is content" "$NOTE" 'Skill `delta`'
t_hasnt "a regex jq cannot compile matches nothing" "$NOTE" 'epsilon'

t_section "gate-commands: the CLI waits until the skill is read"
call Bash 'sendcli new --to x < body.txt' c1
t_has "a gate CLI in a session that named the skill is denied" "$DEC" 'deny'
t_has "the reason names the SKILL.md" "$DEC" "$SK/delta/SKILL.md"
t_has "and the CLI" "$DEC" 'sendcli new waits until'
call Bash 'sendcli new --to x < body.txt' c5
t_eq "a gate CLI in a session that never named the skill passes" "" "$DEC"
t_eq "silently" "" "$NOTE"
call Bash 'sendcli new --body "žinia žąsis žolė"' c6
t_has "content in the gated call itself names the skill and denies" "$DEC" 'deny'
call Bash 'sendcli drafts' c1
t_eq "a subcommand the gate does not name passes" "" "$DEC"
call Bash 'sendcli --help' c1
t_eq "so does a flag in its place" "" "$DEC"
call Bash 'sendcli reply abc < body.txt' c1
t_has "the other named subcommand is held" "$DEC" 'deny'
call Bash 'sendcli new --to x < body.txt' c1
t_has "every gated call is held, the reminder cap does not apply" "$DEC" 'deny'
call Bash 'grep sendcli notes.md' c1
t_eq "a mention never gates: grep" "" "$DEC"
call Bash 'git commit -m "sendcli is fine"' c1
t_eq "a mention never gates: a commit message" "" "$DEC"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/delta/SKILL.md"}}]}}\n' "$SK" > "$T/dread.jsonl"
call Bash 'sendcli new --to x < body.txt' c1 "$T/dread.jsonl"
t_eq "once the skill is read the gate opens" "" "$DEC"
printf 'id\tmode\ttype\tf4\tf5\tf6\tf7\tf8\tf9\tf10\tf11\temitted\tnote\ncontext.skill-on-first-use\twarn\tinjection\t-\t-\t-\t-\t-\t-\t-\t-\tskill-on-first-use\tfixture\n' > "$T/controls.tsv"
OLDC="${HARBOR_CONTEXT_CONTROLS-}"; export HARBOR_CONTEXT_CONTROLS="$T/controls.tsv"
call Bash 'sendcli new --body "žinia žąsis žolė"' c7
t_eq "a warn row turns the deny into a note: no decision" "" "$DEC"
t_has "the note carries the reason" "$NOTE" 'sendcli new waits until the skill that governs it is read'
export HARBOR_CONTEXT_CONTROLS="$OLDC"

t_section "the reminder is capped at 5 per session"
call Bash 'betacli x' s19
R=0
for _i in $(seq 1 60); do call Bash 'betacli x' s19; case "$NOTE" in *'still unread'*) R=$((R + 1)) ;; esac; done
t_eq "60 owned calls after the note give 5 reminders" 5 "$R"

t_section "fail open"
call Bash 'alphacli list' s14
mv "$SK" "$T/skills-gone"
call Bash 'alphacli list' s15
t_eq "no skills dir is silent" "" "$NOTE"
mv "$T/skills-gone" "$SK"
t_eq "garbage payload: exit 0" 0 "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" /bin/sh "$CFG/bin/injection-rule.sh" >/dev/null 2>&1; echo $?)"
t_eq "a note never denies" 0 "$(CLAUDE_CONFIG_DIR="$CFG" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>/dev/null | grep -c permissionDecision)"
t_done
