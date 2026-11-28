#!/usr/bin/env sh
# suggest-tool (harbor#1485): the rule's own stdout, against fixtures/injection-rule/suggest-tool.tsv, in a throwaway box tier. The line
# and the note the engine must split come out here as the script prints them; the engine lane builds the split, and the two meet
# at consolidation. The stop tool is a stub that logs its arguments. notes.test.sh holds the same pack through the real engine.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; BOX="$T/cfg/context-rules/user"; STATE="$HOME/.local/state/harbor/suggest"; FIXT="$T_ROOT/fixtures/injection-rule/suggest-tool.tsv"
mkdir -p "$BOX" "$T/cfg/bin" "$T/cfg/skills/fixture-routine" "$STATE"
for _f in suggest-tool.sh suggest-subject.sh suggest-tool-spoke.sh suggest-start.sh ci-wait-on-the-bus.sh suite-run-through-runner.sh \
          unbounded-wait-loop.sh long-wait-process-exists.sh default-way-route.sh default-way-route.tsv; do cp "$T_ROOT/context-rules/user/$_f" "$BOX/"; done
cp "$FIXT" "$BOX/suggest-tool.tsv"; : > "$T/cfg/skills/fixture-routine/SKILL.md"
# The real parser with one line in front, so a test can see whether it was ever sourced.
MARK="$T/parser.loaded"
{ printf ': >> "%s"\n' "$MARK"; cat "$T_ROOT/bin/library-admission.sh"; } > "$T/cfg/bin/library-admission.sh"
cp "$T_ROOT/bin/admission-normalize.awk" "$T/cfg/bin/"
STOPLOG="$T/stop.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\ncase "$1" in status) if [ -e "%s" ]; then echo "{\\"intro_due\\":false}"; else echo "{\\"intro_due\\":true}"; fi ;; esac\n' "$STOPLOG" "$T/not-due" > "$T/cfg/bin/status-suggest.sh"
# Counting wrappers: `one jq` and `one awk` are the contract's words, so they are counted, not read.
CALLS="$T/calls.log"; _rj="$(command -v jq)"; _ra="$(command -v awk)"
printf '#!/bin/sh\necho jq >> "%s"\nexec "%s" "$@"\n' "$CALLS" "$_rj" > "$T_BIN/jq"
printf '#!/bin/sh\necho awk >> "%s"\nexec "%s" "$@"\n' "$CALLS" "$_ra" > "$T_BIN/awk"
chmod +x "$T_BIN/jq" "$T_BIN/awk"
printf '{}\n' > "$T/tr.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"fixture-routine"}}]}}\n' > "$T/tr-skill.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/skills/fixture-routine/SKILL.md"}}]}}\n' > "$T/tr-read.jsonl"

ENVV=''
# shellcheck disable=SC2086 # ENVV is a list of assignments
rule() { printf '%s' "$1" | env $ENVV sh "$BOX/suggest-tool.sh" 2>&1; }
pb() { "$_rj" -nc --arg c "$1" --arg t "${2:-$T/tr.jsonl}" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"s1",transcript_path:$t,tool_input:{command:$c}}'; }
pf() { "$_rj" -nc --arg n "$1" --arg f "$2" --arg t "$T/tr.jsonl" '{hook_event_name:"PreToolUse",tool_name:$n,session_id:"s1",transcript_path:$t,tool_input:{file_path:$f}}'; }
pm() { "$_rj" -nc --arg n "$1" --arg t "$T/tr.jsonl" '{hook_event_name:"PreToolUse",tool_name:$n,session_id:"s1",transcript_path:$t,tool_input:{}}'; }
sj() { ( SUGGEST_HERE="$BOX"; . "$BOX/suggest-subject.sh"; suggest_subject "$1" "$2" ); }
silent() { t_eq "$1" "" "$(rule "$2")"; }
table() { { printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n'; printf '%s\n' "$@"; } > "$BOX/suggest-tool.tsv"; }
fixture() { cp "$FIXT" "$BOX/suggest-tool.tsv"; }
LINE1='The agent can use a ready-made report for this job. Say stop suggesting this if you would rather not see it.'

t_section "the subject: one builder, the shapes the contract fixes"
t_eq "Bash: basename of the command, then its arguments, one space" 'gh pr checks 1' "$(sj Bash "/opt/homebrew/bin/gh  pr 'checks' 1 >out")"
t_eq "a wrapper is peeled" 'gh pr view' "$(sj Bash 'FOO=1 sudo gh pr view')"
t_eq "one subject per segment" 'ls
gh run list' "$(sj Bash 'ls; gh run list')"
t_eq "a heredoc body makes no subject" 'cat
ls' "$(sj Bash 'cat <<EOF
fixturectl report
EOF
ls')"
t_eq "a command -v lookup makes no subject" '' "$(sj Bash 'command -v fixturectl')"
t_eq "a file: tool, lowercase ext, place" 'Write csv project' "$(sj Write /srv/data/Y.CSV)"
t_eq "no extension" 'Edit - project' "$(sj Edit /srv/data/Makefile)"
t_eq "a dotfile has no extension" 'Edit - scratch' "$(sj Edit /tmp/.profile)"
t_eq "NotebookEdit reads the same way" 'NotebookEdit ipynb project' "$(sj NotebookEdit /srv/a.ipynb)"
t_eq "a connector has no path" 'mcp__x__y - project' "$(sj mcp__x__y '')"
t_eq "place: config" 'Write md config' "$(sj Write "$T/cfg/notes/a.md")"
t_eq "place: deliverables" 'Write xlsx deliverables' "$(sj Write "$HOME/Deliverables/2026/a.xlsx")"
t_eq "place: scratch under TMPDIR" 'Write md scratch' "$(sj Write "$TMPDIR/a.md")"
t_eq "place: scratch under /tmp" 'Write md scratch' "$(sj Write /tmp/a.md)"
t_eq "place: a repo under HOME" 'Write md project' "$(sj Write "$HOME/port/x/a.md")"
t_eq "no part of the path is shown" 'Write csv project' "$(sj Write /srv/secretclient/sheet.csv)"

t_section "the cost order: what never runs on a call no row can answer"
_p="$(pb 'fixturectl report')"; : > "$CALLS"; : > "$STATE/off"
t_eq "off: silent" "" "$(rule "$_p")"
rm -f "$STATE/off"
t_eq "off: jq and awk never ran" "" "$(cat "$CALLS")"
printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n' > "$BOX/suggest-tool.tsv"
_p="$(pb 'fixturectl report')"; : > "$CALLS"
t_eq "empty table: silent" "" "$(rule "$_p")"
t_eq "empty table: jq and awk never ran" "" "$(cat "$CALLS")"
cp "$T_ROOT/context-rules/user/suggest-tool.tsv" "$BOX/suggest-tool.tsv"
_p="$(pb 'fixturectl report')"; : > "$CALLS"
t_eq "the shipped table has no rows: silent" "" "$(rule "$_p")"
t_eq "the shipped table: jq and awk never ran" "" "$(cat "$CALLS")"
fixture
_p="$(pb 'ls -la')"; : > "$CALLS"; rm -f "$MARK"
t_eq "a Bash call with no row's word: silent" "" "$(rule "$_p")"
t_eq "it never sourced the floor's parser" no "$([ -e "$MARK" ] && echo yes || echo no)"
t_eq "it ran one jq and one awk" 'awk
jq' "$(sort "$CALLS")"
_p="$("$_rj" -nc --arg a x '{tool_name:"Bash",agent_id:$a,tool_input:{command:"fixturectl report"}}')"; : > "$CALLS"; rm -f "$MARK"
t_eq "a subagent: silent, even on a row's own command" "" "$(rule "$_p")"
t_eq "a subagent: one jq, no awk" jq "$(cat "$CALLS")"
_p="$(pb 'fixturectl report')"; rm -f "$MARK"
rule "$_p" >/dev/null
t_eq "a word hit does source the parser (the test above can fail)" yes "$([ -e "$MARK" ] && echo yes || echo no)"

t_section "a match: the sentinel, then a note that is never empty"
_o="$(rule "$(pb 'fixturectl report')")"
t_eq "the first line is the sentinel" "HARBOR-USER-LINE fixture-verb: $LINE1" "$(printf '%s\n' "$_o" | head -1)"
t_has "a safe row's note switches to the named tool" "$(printf '%s\n' "$_o" | sed 1d)" 'Switch to fixture-report for this job from here on'
t_has "the note names the stop route with the row id" "$_o" 'status-suggest.sh stop fixture-verb --origin agent'
_o="$(rule "$(pb 'fixturectl report --token PAYLOADTEXT')")"
t_hasnt "no payload text reaches either" "$_o" PAYLOADTEXT
_o="$(rule "$(pm mcp__fixture__export)")"
t_has "a connector row fires on its tool" "$_o" 'HARBOR-USER-LINE fixture-connector: '
t_hasnt "a safe=no row's note holds no switch sentence" "$_o" 'Switch to'
t_has "a safe=no row's note says carry on" "$(printf '%s\n' "$_o" | sed 1d)" 'Carry on with what you are doing'
t_has "a file row fires on tool, extension and place" "$(rule "$(pf Write "$HOME/Deliverables/x/a.CSV")")" 'HARBOR-USER-LINE fixture-file: '
silent "the same write to scratch stays silent" "$(pf Write "$TMPDIR/a.csv")"
silent "a tool no row names stays silent" "$(pm WebSearch)"

t_section "a mention is not a run; a run in a loop is"
for _c in 'grep fixturectl notes.txt' "git commit -m 'fixturectl report'" 'echo "fixturectl report"' 'cat <<EOF
fixturectl report
EOF' 'ls fixturectl'; do
  silent "silent on: $_c" "$(pb "$_c")"
done
t_has "fires inside an if" "$(rule "$(pb 'if fixturectl report; then ls; fi')")" HARBOR-USER-LINE
t_eq "an until loop reaches the subject" 'fixturectl report' "$(sj Bash 'until fixturectl report; do sleep 5; done' | head -1)"
silent "and unbounded-wait-loop speaks on that call, so this rule stands down" "$(pb 'until fixturectl report; do sleep 5; done')"
t_has "fires on a full path" "$(rule "$(pb '/opt/x/fixturectl report 1')")" HARBOR-USER-LINE
t_has "fires after another segment" "$(rule "$(pb 'cd /tmp && fixturectl report')")" HARBOR-USER-LINE
silent "quiet runs on the same subject" "$(pb 'fixturectl report --dry-run')"
table 'wide	verb	Bash	fixturectl	^nope|fixturectl report	-	A plain line for a test.	-	no	-	-	core'
silent "a second branch cannot match inside an argument" "$(pb 'echo fixturectl report')"
t_has "and still matches at the start" "$(rule "$(pb 'fixturectl report')")" HARBOR-USER-LINE
fixture

t_section "silent for the person's own record, an absent tool, a skill in use"
printf 'fixture-verb\t2026-11-06\tpanel\n' > "$STATE/stopped.tsv"
silent "a stopped row" "$(pb 'fixturectl report')"
rm -f "$STATE/stopped.tsv"
rm -f "$T/cfg/skills/fixture-routine/SKILL.md"
silent "an absent required file" "$(pb 'fixturetool audit')"
: > "$T/cfg/skills/fixture-routine/SKILL.md"
t_has "the skill row fires when the skill is not in use" "$(rule "$(pb 'fixturetool audit')")" 'HARBOR-USER-LINE fixture-skill: '
silent "a Skill call in the transcript" "$(pb 'fixturetool audit' "$T/tr-skill.jsonl")"
silent "a Read of its SKILL.md in the transcript" "$(pb 'fixturetool audit' "$T/tr-read.jsonl")"
silent "no transcript: it cannot tell" "$(pb 'fixturetool audit' "$T/absent.jsonl")"

t_section "trust comes from the file, never the cell"
mkdir -p "$T/cfg/suggest.d"
printf 'company-job\tverb\tBash\tcompanyctl\t^companyctl run\t-\tA plain company line for a test.\tcompany-tool\tyes\t-\t-\tcore\n' > "$T/cfg/suggest.d/company.tsv"
silent "a row under suggest.d is not read: its delivery is harbor#1278's" "$(pb 'companyctl run')"
printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n' > "$BOX/suggest-tool.tsv"
silent "...and it makes no empty table a live one" "$(pb 'companyctl run')"
fixture; cp "$T/cfg/suggest.d/company.tsv" "$T/other.tsv"; rm -rf "$T/cfg/suggest.d"
rows() { ( SUGGEST_HERE="$BOX"; . "$BOX/suggest-subject.sh"; suggest_rows '' "$1" "$2" ); }
t_eq "a row outside the core table leaves the reader safe=no, whatever its cells say" no "$(rows "$BOX/suggest-tool.tsv" "$T/other.tsv" | cut -f9)"
t_eq "...and the same row read as the core table keeps safe=yes" yes "$(rows "$T/other.tsv" "$T/other.tsv" | cut -f9)"
t_eq "...and its source cell stays a cell" core "$(rows "$BOX/suggest-tool.tsv" "$T/other.tsv" | cut -f12)"
table 'mod-yes	mod	mcp__fixture__panel	-	^mcp__fixture__panel 	-	A side panel for a test.	fixture-panel	yes	the admin setup	-	core'
ENVV='CLAUDE_CODE_ENTRYPOINT=claude-desktop'
t_hasnt "a mod row is never safe, whatever its cell says" "$(rule "$(pm mcp__fixture__panel)")" 'Switch to'
ENVV=''; fixture

t_section "one bad row never silences the table"
table 'bad-ere	verb	Bash	fixturectl	^fixturectl (	-	A plain line for a test.	-	no	-	-	core' \
      'short	verb	Bash' \
      'long	verb	Bash	fixturectl	^fixturectl	-	A plain line for a test.	-	no	-	-	core	extra' \
      'Bad_Id	verb	Bash	fixturectl	^fixturectl	-	A plain line for a test.	-	no	-	-	core' \
      'bad-word	verb	Bash	-	^fixturectl	-	A plain line for a test.	-	no	-	-	core' \
      'tick-line	verb	Bash	fixturectl	^fixturectl	-	A `tick` line.	-	no	-	-	core' \
      'bad-switch	verb	Bash	fixturectl	^fixturectl	-	A plain line for a test.	rm -rf; x	yes	-	-	core' \
      'good	verb	Bash	fixturectl	^fixturectl report	-	A plain line for a test.	-	no	-	-	core'
t_eq "the good row still speaks" 'HARBOR-USER-LINE good: A plain line for a test.' "$(rule "$(pb 'fixturectl report --loud')" | head -1)"
fixture

t_section "another pack speaks: this rule stands down"
table 'ci-read	verb	Bash	gh	^gh pr checks	-	A plain line for a test.	-	no	-	-	core'
silent "the hand-rolled CI wait stays with ci-wait-on-the-bus" "$(pb 'until gh pr checks 1; do sleep 5; done')"
t_has "a single read is this rule's" "$(rule "$(pb 'gh pr checks 1')")" 'HARBOR-USER-LINE ci-read: '
fixture

t_section "a mod row: only where it can load and is not loaded"
silent "unknown surface" "$(pm mcp__fixture__panel)"
ENVV='CLAUDE_CODE_ENTRYPOINT=cli'; silent "the terminal entry point" "$(pm mcp__fixture__panel)"
ENVV='CLAUDE_CODE_ENTRYPOINT=claude-desktop WSL_DISTRO_NAME=Ubuntu'; silent "WSL" "$(pm mcp__fixture__panel)"
ENVV='CLAUDE_CODE_ENTRYPOINT=claude-desktop'
t_has "the Desktop surface" "$(rule "$(pm mcp__fixture__panel)")" 'HARBOR-USER-LINE fixture-mod: '
printf '{"enabledPlugins":{"fixture-panel@harbor-mods":true}}\n' > "$T/cfg/settings.json"
silent "already loaded" "$(pm mcp__fixture__panel)"
printf '{"enabledPlugins":{"fixture-panel@harbor-mods":false}}\n' > "$T/cfg/settings.json"
t_has "switched off is not loaded: it speaks" "$(rule "$(pm mcp__fixture__panel)")" 'HARBOR-USER-LINE fixture-mod: '
printf '{"enabledPlugins":{"fixture-panelish@harbor-mods":true}}\n' > "$T/cfg/settings.json"
t_has "another mod's name is not this one" "$(rule "$(pm mcp__fixture__panel)")" 'HARBOR-USER-LINE fixture-mod: '
printf '{"enabledPlugins":{"fixture-panel@harbor-mods":true}}\n' > "$T/cfg/settings.json"
printf '{"enabledPlugins":{"fixture-panel@harbor-mods":false}}\n' > "$T/managed.json"
ENVV="CLAUDE_CODE_ENTRYPOINT=claude-desktop HARBOR_SCOPE_MANAGED_SETTINGS=$T/managed.json"
t_has "an admin's false outranks the person's true" "$(rule "$(pm mcp__fixture__panel)")" 'HARBOR-USER-LINE fixture-mod: '
printf '{"enabledPlugins":{"fixture-panel@harbor-mods":true}}\n' > "$T/managed.json"; rm -f "$T/cfg/settings.json"
silent "an admin's true is loaded" "$(pm mcp__fixture__panel)"
rm -f "$T/cfg/settings.json" "$T/managed.json"; ENVV=''

t_section "the intro: due, on a known surface, never in shadow, outranked by a real row"
ctl() { printf 'context.suggest-tool\t%s\tinjection\t-\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tsuggest-tool\tx\n' "$1" > "$T/controls.tsv"; }
ctl warn
D="CLAUDE_CODE_ENTRYPOINT=claude-desktop HARBOR_CONTEXT_CONTROLS=$T/controls.tsv"
printf '25\t3\t0\n' > "$STATE/sessions.tsv"
ENVV="$D"
t_has "due: it speaks on any tool call" "$(rule "$(pb 'ls')")" 'HARBOR-USER-LINE fixture-intro: '
t_hasnt "its note holds no switch sentence" "$(rule "$(pb 'ls')")" 'Switch to'
t_has "a real row outranks it" "$(rule "$(pb 'fixturectl report')")" 'HARBOR-USER-LINE fixture-verb: '
ctl shadow
silent "shadow skips it" "$(pb 'ls')"
ctl warn
ENVV="CLAUDE_CODE_ENTRYPOINT=cli HARBOR_CONTEXT_CONTROLS=$T/controls.tsv"; silent "a surface that cannot load the pane" "$(pb 'ls')"
ENVV="HARBOR_CONTEXT_CONTROLS=$T/controls.tsv"; silent "an unknown surface" "$(pb 'ls')"
ENVV="$D WSL_INTEROP=x"; silent "WSL" "$(pb 'ls')"
ENVV="$D"
: > "$T/not-due"; silent "the stop tool says it is not due" "$(pb 'ls')"; rm -f "$T/not-due"
printf '23\t3\t0\n' > "$STATE/sessions.tsv"
t_has "20 sessions since the last: due" "$(rule "$(pb 'ls')")" 'HARBOR-USER-LINE fixture-intro: '
printf '22\t3\t0\n' > "$STATE/sessions.tsv"; : > "$STOPLOG"
silent "19 sessions since the last: not yet" "$(pb 'ls')"
t_eq "and the cheap read never asked the stop tool" "" "$(cat "$STOPLOG")"
printf '25\t3\t0\n' > "$STATE/sessions.tsv"
printf 'fixture-intro\t2026-11-06\tpanel\n' > "$STATE/stopped.tsv"; silent "a stopped intro" "$(pb 'ls')"; rm -f "$STATE/stopped.tsv"
table 'intro-one	intro	-	-	-	-	The first intro line.	-	no	-	-	core' 'intro-two	intro	-	-	-	-	The second intro line.	-	no	-	-	core'
t_eq "two intro rows in the table: the first speaks" 'HARBOR-USER-LINE intro-one: The first intro line.' "$(rule "$(pb 'ls')" | head -1)"
fixture
rm -f "$STATE/sessions.tsv"; printf '25\t3\t0\n' > "$T/sessions.out"; ln -s "$T/sessions.out" "$STATE/sessions.tsv"
silent "sessions.tsv a link: not read, so no intro" "$(pb 'ls')"
rm -f "$STATE/sessions.tsv"; mkfifo "$STATE/sessions.tsv"
silent "sessions.tsv a FIFO: no hang, no intro" "$(pb 'ls')"
ENVV=''; rm -f "$STATE/sessions.tsv"

t_section "a hook outside the sandbox believes nothing planted in the state folder"
printf 'other-row\t2026-11-06\tpanel\n' > "$T/stop.out"
ln -s "$T/stop.out" "$STATE/stopped.tsv"
silent "stopped.tsv a link: it cannot tell, so it stays silent" "$(pb 'fixturectl report')"
rm -f "$STATE/stopped.tsv"; ln -s "$T/never" "$STATE/stopped.tsv"
silent "...a dangling link too" "$(pb 'fixturectl report')"
rm -f "$STATE/stopped.tsv"; mkfifo "$STATE/stopped.tsv"
silent "...and a FIFO: no hang" "$(pb 'fixturectl report')"
rm -f "$STATE/stopped.tsv"; ln -s "$T/never" "$STATE/off"
silent "off a dangling link is off" "$(pb 'fixturectl report')"
rm -f "$STATE/off"; mkdir -p "$T/elsewhere"; rmdir "$STATE"; ln -s "$T/elsewhere" "$STATE"
silent "the folder a link: nothing through it is believed" "$(pb 'fixturectl report')"
rm -f "$STATE"; mkdir -p "$STATE"
t_has "...and the plain folder speaks again (the arms above can fail)" "$(rule "$(pb 'fixturectl report')")" 'HARBOR-USER-LINE fixture-verb: '

t_section "the spoke script: the engine's one argument reaches the stop tool"
: > "$STOPLOG"; sh "$BOX/suggest-tool-spoke.sh" fixture-verb
t_eq "it runs shown with the row id" 'shown fixture-verb' "$(cat "$STOPLOG")"
: > "$STOPLOG"; sh "$BOX/suggest-tool-spoke.sh"; t_eq "no id: nothing" "" "$(cat "$STOPLOG")"
mv "$T/cfg/bin/status-suggest.sh" "$T/stop.aside"
t_exit "no stop tool: it fails silent" 0 sh "$BOX/suggest-tool-spoke.sh" fixture-verb
t_has "the note drops the route when there is no tool" "$(rule "$(pb 'fixturectl report')")" 'HARBOR-USER-LINE'
t_hasnt "and names no tool that is not there" "$(rule "$(pb 'fixturectl report')")" 'status-suggest.sh'
mv "$T/stop.aside" "$T/cfg/bin/status-suggest.sh"

t_section "suggest-start: one tick, off the tool path, and the route"
: > "$STOPLOG"; _o="$(sh "$BOX/suggest-start.sh")"
t_eq "it ticks once" tick "$(cat "$STOPLOG")"
t_has "the pointer names the stop route" "$_o" 'status-suggest.sh stop <id> --origin agent'
t_has "and off and on" "$_o" '`off` or `on`'
t_has "by a path that needs no PATH" "$_o" "$T/cfg/bin/status-suggest.sh"
_n="$(printf '%s' "$_o" | wc -c | tr -d ' ')"
t_eq "the pointer stays short, under 300 bytes beyond the path ($_n)" yes "$([ "$((_n - ${#T}))" -lt 300 ] && echo yes || echo no)"
: > "$STATE/off"; : > "$STOPLOG"; sh "$BOX/suggest-start.sh" >/dev/null; rm -f "$STATE/off"
t_eq "off does not stop the count" tick "$(cat "$STOPLOG")"
mv "$T/cfg/bin/status-suggest.sh" "$T/stop.aside"
t_eq "no stop tool: no pointer to a route that is not there" "" "$(sh "$BOX/suggest-start.sh")"
mv "$T/stop.aside" "$T/cfg/bin/status-suggest.sh"
t_done
