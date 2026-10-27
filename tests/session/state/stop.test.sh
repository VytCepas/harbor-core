#!/usr/bin/env sh
# hooks/session-state/session-state.sh, the Stop hook (harbor#1043, #1044): the five states in rule order, one test per waiting
# pattern in CONTRACTS/session-waiting.tsv, SG-2 parity with guard-stop.sh, an event only on a change, the record's
# fields, the save-now continuation (once, off without its rule, off under stop_hook_active), and a speed bound.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/hooks/session-state/session-state.sh"; GSTOP="$T_ROOT/bin/guard-stop.sh"; TABLE="$T_ROOT/CONTRACTS/session-waiting.tsv"
T="$T_TMP"; ST="$T/state"; REPO="$T/repo"; CFG="$T/cfg"
export HARBOR_STATUS_DIR="$ST" HARBOR_EVENT_DIR="$T/bus"
# Auto-compact off for every section but its own, and never a real osascript: a test must not type into a terminal.
export HARBOR_AUTOCOMPACT_PCT=101 HARBOR_AUTOCOMPACT_OSA=false
mkdir -p "$REPO" "$CFG"
git -C "$REPO" init -q && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
git -C "$REPO" checkout -q -b work; printf 'a\n' > "$REPO/f"; printf 'h\n' > "$REPO/HANDOFF.md"
git -C "$REPO" add . && git -C "$REPO" commit -q -m init
touch -t 201901010000 "$REPO/HANDOFF.md"  # older than every fixture transcript: the handoff is not this session's
git init -q --bare "$T/origin.git" && git -C "$REPO" remote add origin "$T/origin.git" && git -C "$REPO" push -q -u origin work 2>/dev/null
REPO2="$T/repo2"; git init -q "$REPO2" && git -C "$REPO2" config user.email t@t && git -C "$REPO2" config user.name t   # no HANDOFF.md at all
git -C "$REPO2" checkout -q -b work; printf 'a\n' > "$REPO2/f"; git -C "$REPO2" add . && git -C "$REPO2" commit -q -m init
git init -q --bare "$T/origin2.git" && git -C "$REPO2" remote add origin "$T/origin2.git" && git -C "$REPO2" push -q -u origin work 2>/dev/null
REPO2="$(CDPATH= cd -P -- "$REPO2" && pwd -P)"
REPO="$(CDPATH= cd -P -- "$REPO" && pwd -P)"

tu() { jq -nc --arg id "$1" --arg ts "$2" --arg c "$3" '{type:"assistant",timestamp:$ts,message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}'; }
tr_() { jq -nc --arg id "$1" --arg o "$2" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,content:$o}]}}'; }
ask() { jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"q1",name:"AskUserQuestion",input:{}}]}}'; }
tx() { n="$1"; shift; printf '%s\n' "$@" > "$T/$n.jsonl"; }  # <name> <records…>
payload() { # <sid> <transcript-name> <message> [tasks-json] [stop_hook_active] [cwd]
  jq -nc --arg s "$1" --arg t "$T/$2.jsonl" --arg m "$3" --argjson b "${4:-[]}" --argjson a "${5:-false}" --arg c "${6:-$REPO}" \
    '{session_id:$s,transcript_path:$t,cwd:$c,prompt_id:"p1",stop_hook_active:$a,last_assistant_message:$m,background_tasks:$b}'; }
run() { payload "$@" | CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2> "$T/err"; RC=$?; }
rec() { jq -r ".$2" "$ST/sessions/$1.json" 2>/dev/null; }  # <sid> <field>
events() { cat "$T"/bus/*.jsonl 2>/dev/null | grep "\"kind\":\"$1\"" | grep -c "\"subject\":\"$2\"" || :; }
settle() { sleep 1; }  # the bus append is detached from the hook

tx plain "$(tu c0 2020-01-01T00:00:00.000Z 'ls')" "$(tr_ c0 ok)"
RUN='[{"id":"b1","type":"subagent","status":"running","description":"scan"}]'

t_section "rule order: a running background task beats everything below it"
run s-agents plain 'Which one do you want?' "$RUN"
t_eq "running task + a question: waiting-agents" waiting-agents "$(rec s-agents state)"
t_eq "the reason counts them" "1 running" "$(rec s-agents reason)"
t_eq "the record keeps the task list" b1 "$(rec s-agents 'background_tasks[0].id')"
run s-agents2 plain 'Done.' '[{"id":"b1","type":"shell","status":"completed"}]'
t_eq "a task that is not running does not count" idle "$(rec s-agents2 state)"
t_eq "the hook exits 0 and prints nothing" "0:" "$RC:$(cat "$T/out")"

t_section "waiting-operator: every row of the table matches its positive and misses its negative"
n=0
while IFS="$(printf '\t')" read -r id _re pos neg; do
  case "$id" in ''|'#'*) continue ;; esac
  n=$((n + 1))
  run "s-p$n" plain "$(printf '%b' "$pos")"; t_eq "$id: its positive example is waiting-operator, reason $id" "waiting-operator $id" "$(rec "s-p$n" state) $(rec "s-p$n" reason)"
  run "s-n$n" plain "$(printf '%b' "$neg")"; t_eq "$id: its negative example is not waiting" idle "$(rec "s-n$n" state)"
done < "$TABLE"
t_eq "the table has at least three rows" yes "$([ "$n" -ge 3 ] && echo yes || echo no)"
t_eq "no row lacks a positive or a negative example" "" "$(awk -F'\t' '!/^#/ && NF && (NF < 4 || $3 == "" || $4 == "") { print $1 }' "$TABLE")"
tx asked "$(tu c1 2020-01-01T00:00:00.000Z 'ls')" "$(tr_ c1 ok)" "$(ask)"
run s-ask asked 'Pick one.'; t_eq "a turn ending on an AskUserQuestion is waiting-operator" "waiting-operator W-ask" "$(rec s-ask state) $(rec s-ask reason)"
tx answered "$(ask)" "$(tr_ q1 yes)"
run s-ans answered 'Thanks.'; t_eq "an answered AskUserQuestion is not" idle "$(rec s-ans state)"

t_section "blocked: SG-2, and it agrees with guard-stop.sh on the same transcript"
tx red "$(tu c2 2020-01-01T00:00:01.000Z 'sh tests/x-test.sh')" "$(tr_ c2 'x-test: 3 passed, 1 failed')"
tx healed "$(tu c2 2020-01-01T00:00:01.000Z 'sh tests/x-test.sh')" "$(tr_ c2 'x-test: 3 passed, 1 failed')" "$(tu c3 2020-01-01T00:00:02.000Z 'sh tests/x-test.sh')" "$(tr_ c3 'x-test: 4 passed, 0 failed')"
tx readonly "$(tu c4 2020-01-01T00:00:01.000Z 'cat build.log')" "$(tr_ c4 'x-test: 3 passed, 1 failed')"
tx dotted "$(tu c5 2020-01-01T00:00:01.000Z 'sh tests/x.test.sh')" "$(tr_ c5 'x.test: 3 passed, 1 failed')"
BG='Command running in background with ID: bq1. Output is being written to: /t/tasks/bq1.output. Notified.'
rd() { jq -nc --arg id "$1" --arg p "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Read",input:{file_path:$p}}]}}'; }
tx bgheal "$(tu c2 2020-01-01T00:00:01.000Z 'sh tests/x-test.sh')" "$(tr_ c2 'x-test: 3 passed, 1 failed')" "$(tu b3 2020-01-01T00:00:02.000Z 'sh tests/x-test.sh')" "$(tr_ b3 "$BG")" "$(tu c4 2020-01-01T00:00:03.000Z 'tail -1 /t/tasks/bq1.output')" "$(tr_ c4 'x-test: 4 passed, 0 failed')"
tx bgread "$(tu c2 2020-01-01T00:00:01.000Z 'sh tests/x-test.sh')" "$(tr_ c2 'x-test: 3 passed, 1 failed')" "$(tu b3 2020-01-01T00:00:02.000Z 'sh tests/x-test.sh')" "$(tr_ b3 "$BG")" "$(rd r4 /t/tasks/bq1.output)" "$(tr_ r4 "$(printf '1\tx-test: 4 passed, 0 failed')")"
tx bgcat "$(tu c6 2020-01-01T00:00:01.000Z 'cat /t/tasks/bq1.output')" "$(tr_ c6 'x-test: 3 passed, 1 failed')"
gs() { printf '{"session_id":"g-%s","transcript_path":"%s/%s.jsonl","cwd":"%s"}' "$1" "$T" "$1" "$REPO" | CLAUDE_CONFIG_DIR="$CFG" sh "$GSTOP" 2>/dev/null; }
for c in red healed readonly dotted bgheal bgread bgcat; do
  run "s-$c" "$c" 'ok'
  g="$(gs "$c")"; gb=no; case "$g" in *'"decision":"block"'*) gb=yes ;; esac
  sb=no; [ "$(rec "s-$c" state)" = blocked ] && sb=yes
  t_eq "$c: guard-stop blocks exactly when session-state says blocked" "$gb" "$sb"
done
t_eq "a red suite run in the session is blocked" blocked "$(rec s-red state)"
t_has "...and the reason is the verdict line" "$(rec s-red reason)" "3 passed, 1 failed"
t_eq "a later green run of it clears the block" idle "$(rec s-healed state)"
t_eq "a verdict only READ (cat) is not a run" idle "$(rec s-readonly state)"
t_eq "a dotted suite name (x.test.sh) pairs" blocked "$(rec s-dotted state)"
t_eq "a background green, read from its task file, clears the red" idle "$(rec s-bgheal state)"
t_eq "...and so does the same file read with the Read tool" idle "$(rec s-bgread state)"
t_eq "a cat of a task file no suite of this session wrote is not a run" idle "$(rec s-bgcat state)"
pair_of() { awk '/SG_PAIR=.$/ { on = 1; next } on { print } on && /}.$/ { exit }' "$1"; }
t_eq "SG_PAIR is byte-equal to guard-stop.sh's" "$(pair_of "$GSTOP")" "$(pair_of "$TOOL")"
t_has "...and the extraction found it" "$(pair_of "$TOOL")" 'BGT'
run s-redq red 'Which one?'; t_eq "a question outranks blocked" waiting-operator "$(rec s-redq state)"

t_section "done: committed or pushed this session, nothing edited since, clean tree, branch pushed; the handoff is no gate"
wr() { jq -nc --arg ts "$1" '{type:"assistant",timestamp:$ts,message:{content:[{type:"tool_use",id:"w1",name:"Write",input:{file_path:"/x/HANDOFF.md"}}]}}'; }
tx ms "$(tu c5 2020-01-01T00:00:00.000Z 'git commit -m x')" "$(tr_ c5 ok)" "$(tu c5b 2020-01-01T00:00:01.000Z 'git push')" "$(tr_ c5b ok)"
run s-done ms 'All set.'; t_eq "pushed, clean, nothing edited since, stale handoff: done" done "$(rec s-done state)"
t_eq "the record carries the branch" work "$(rec s-done branch)"
t_eq "...the change count" 0 "$(rec s-done dirty)"
t_eq "...a stale handoff as a field, not a gate" "yes" "$(rec s-done handover_stale)"
tx wc "$(tu c0 2020-01-01T00:00:00.000Z 'ls')" "$(wr 2020-01-01T00:00:01.000Z)" "$(tu c5 2020-01-01T00:00:02.000Z 'git commit -am handoff')" "$(tr_ c5 ok)" "$(tu c5b 2020-01-01T00:00:03.000Z 'git push')" "$(tr_ c5b ok)"
run s-wc wc 'Handoff committed.'; t_eq "write the handoff, THEN commit and push it: done" done "$(rec s-wc state)"
touch "$REPO/HANDOFF.md"
run s-fresh2 ms 'All set.'; t_eq "...and a handoff newer than the milestone reads fresh" no "$(rec s-fresh2 handover_stale)"
run s-touch plain 'All set.'; t_eq "touch on the handoff alone never fires done" idle "$(rec s-touch state)"
touch -t 201901010000 "$REPO/HANDOFF.md"
run s-nohand ms 'All set.' '[]' false "$REPO2"; t_eq "a repo with no HANDOFF.md reaches done" done "$(rec s-nohand state)"
t_eq "...handover_at 0 and stale" "0 yes" "$(rec s-nohand handover_at) $(rec s-nohand handover_stale)"
tx late "$(tu c0 2020-01-01T00:00:00.000Z 'ls')" "$(tu c6 2020-01-01T00:00:01.000Z 'git push')" "$(tr_ c6 ok)" "$(wr 2020-01-01T00:00:05.000Z)"
run s-late late 'All set.'; t_eq "an edit AFTER the push: idle" idle "$(rec s-late state)"
printf 'x\n' > "$REPO/untracked"
run s-dirty ms 'All set.'; t_eq "an untracked file: not done" idle "$(rec s-dirty state)"
t_eq "...and counted" 1 "$(rec s-dirty dirty)"
rm -f "$REPO/untracked"
printf 'b\n' >> "$REPO/f"; git -C "$REPO" commit -q -am ahead
run s-ahead ms 'All set.'; t_eq "committed but not pushed, no PR: idle" idle "$(rec s-ahead state)"
tx aheadpr "$(tu c5 2020-01-01T00:00:00.000Z 'gh pr create --fill')" "$(tr_ c5 'https://github.com/o/r/pull/9')"
run s-aheadpr aheadpr 'Opened.'; t_eq "...with a PR from this session: done" done "$(rec s-aheadpr state)"
git -C "$REPO" push -q 2>/dev/null
run s-pend plain 'x' '[{"id":"b1","type":"subagent","status":"pending"}]'; t_eq "a pending task is in flight: waiting-agents" waiting-agents "$(rec s-pend state)"
printf '#!/bin/sh\nsleep 6\n' > "$T_BIN/git"; chmod +x "$T_BIN/git"
a0="$(date +%s)"; run s-slow ms 'All set.'; a1="$(date +%s)"
t_eq "a git that hangs: bounded, exit 0, no record" "0 no" "$RC $([ -e "$ST/sessions/s-slow.json" ] && echo yes || echo no)"
t_eq "...within 4 s" yes "$([ $((a1 - a0)) -le 4 ] && echo yes || echo no)"
rm -f "$T_BIN/git"
tx pr "$(tu c7 2020-01-01T00:00:00.000Z 'gh pr create --fill')" "$(tr_ c7 'https://github.com/o/r/pull/9')"
run s-pr pr 'Opened.'; t_eq "a pull URL from gh pr create lands in the record" https://github.com/o/r/pull/9 "$(rec s-pr pr)"

t_section "the event: only on a change"
run s-ev plain 'Done.'; settle
t_eq "the first record emits session.state" 1 "$(events session.state s-ev | tr -d ' ')"
t_has "...subject the session, title the state" "$(grep '"subject":"s-ev"' "$T"/bus/*.jsonl)" "\"title\":\"$(rec s-ev state)\""
run s-ev plain 'Still done.'; settle
t_eq "the same state again emits nothing" 1 "$(grep -c '"subject":"s-ev"' "$T"/bus/*.jsonl | tr -d ' ')"
run s-ev plain 'Which one?'; settle
t_eq "a new state emits one more" 2 "$(grep -c '"subject":"s-ev"' "$T"/bus/*.jsonl | tr -d ' ')"
since1="$(rec s-ev since)"; run s-ev plain 'Which one again?'
t_eq "an unchanged state keeps its since" "$since1" "$(rec s-ev since)"

t_section "save-now: one continuation, only with its rule, never inside a stop-hook continuation"
mkdir -p "$ST/ctx"; printf '95\n' > "$ST/ctx/s-save"; touch -t 201901010000 "$REPO/HANDOFF.md"  # a year before the transcript, in any TZ
run s-save plain 'Done.'
t_eq "no rule installed: no continuation" "" "$(cat "$T/out")"
mkdir -p "$CFG/.helm-dispatch/rules"; : > "$CFG/.helm-dispatch/rules/event.session-save-now.rule"
run s-save plain 'Done.' '[]' true
t_eq "stop_hook_active true: no continuation" "" "$(cat "$T/out")"
run s-save plain 'Done.'
t_has "rule on, ctx 95, handoff old: one additionalContext" "$(cat "$T/out")" '"additionalContext"'
t_has "...for the Stop event" "$(cat "$T/out")" '"hookEventName":"Stop"'
t_eq "ctx_pct is read from the statusline bridge" 95 "$(rec s-save ctx_pct)"
run s-save plain 'Done.'
t_eq "the same trigger does not repeat" "" "$(cat "$T/out")"
settle; t_eq "the nudge is on the bus once" 1 "$(events session.save-now s-save | tr -d ' ')"
printf '80\n' > "$ST/ctx/s-80"; run s-80 plain 'Done.'
t_eq "80% with no new milestone: no continuation" "" "$(cat "$T/out")"
printf '95\n' > "$ST/ctx/s-fresh"; touch "$REPO/HANDOFF.md"; run s-fresh plain 'Done.'
t_eq "95% but the handoff is newer than the last milestone: no continuation" "" "$(cat "$T/out")"

t_section "compact: a finished turn asks the agent once; the agent's [compact-ok] as the last line types /compact"
rm -f "$CFG/.helm-dispatch/rules/event.session-save-now.rule"
printf '#!/bin/sh\ncat > /dev/null; printf "%%s\\n" "$*" >> "%s/osa.calls"; echo sent\n' "$T" > "$T/osa"; chmod +x "$T/osa"
export HARBOR_AUTOCOMPACT_PCT=35 HARBOR_AUTOCOMPACT_TTY=ttys999 HARBOR_AUTOCOMPACT_OSA="$T/osa" HARBOR_AUTOCOMPACT_DELAY=0
typed() { _n=0; until grep -q "$(printf %.8s "$1") typed" "$ST"/backups/session-autocompact/*/log 2>/dev/null || [ "$_n" -ge 20 ]; do sleep 0.25; _n=$((_n + 1)); done; sleep 0.2; }
: > "$T/osa.calls"
printf '20\n' > "$ST/ctx/ac-small"; run ac-small plain 'All set.'
t_eq "ctx under 35%: no question" "" "$(cat "$T/out")"
printf '50\n' > "$ST/ctx/ac-1"; run ac-1 plain 'All set.'
t_has "ctx 50% on an idle turn: one continuation asks the agent" "$(cat "$T/out")" '"additionalContext"'
t_has "...naming the line to answer with" "$(cat "$T/out")" '[compact-ok]'
t_eq "...and nothing is typed on a question" "" "$(cat "$T/osa.calls")"
run ac-1 plain 'not yet' '[]' true
t_eq "'not yet' inside the continuation: no second question, nothing typed" ":" "$(cat "$T/out"):$(cat "$T/osa.calls")"
run ac-1 plain 'All set.'
t_eq "the same growth step does not ask again" "" "$(cat "$T/out")"
printf '61\n' > "$ST/ctx/ac-1"; run ac-1 plain 'All set.'
t_has "ten points more asks again" "$(cat "$T/out")" '"additionalContext"'
run ac-1 plain 'Everything is merged and saved.
[compact-ok]' '[]' true
t_has "[compact-ok] as the last line: the operator is told" "$(cat "$T/out")" 'Compacting'
typed ac-1; t_has "...and /compact is typed into the tab of the session's tty" "$(cat "$T/osa.calls")" '/dev/ttys999'
t_has "...and logged" "$(cat "$ST"/backups/session-autocompact/*/log)" 'typed /compact on ttys999: sent'
: > "$T/osa.calls"
printf '10\n' > "$ST/ctx/ac-2"; run ac-2 plain 'Done.
[compact-ok]'
typed ac-2; t_has "the agent may say it unasked, at any context size" "$(cat "$T/osa.calls")" '/dev/ttys999'
: > "$T/osa.calls"
run ac-q plain 'When the task is done I end with [compact-ok] on its own line.'
run ac-q2 plain '[compact-ok]
and then more text'
sleep 0.5; t_eq "a marker quoted mid-message, or not on the last line: nothing typed" "" "$(cat "$T/osa.calls")"
run ac-run plain '[compact-ok]' "$RUN"
sleep 0.5; t_eq "a running background task: nothing typed" "" "$(cat "$T/osa.calls")"
printf '50\n' > "$ST/ctx/ac-r2"; run ac-r2 plain 'x' "$RUN"
t_eq "...and no question while one runs" "" "$(cat "$T/out")"
: > "$ST/compact-auto.off"; printf '50\n' > "$ST/ctx/ac-off"; run ac-off plain 'All set.'
t_eq "compact-auto.off: no question" "" "$(cat "$T/out")"
run ac-off plain '[compact-ok]'; sleep 0.5
t_eq "...and nothing typed" "" "$(cat "$T/osa.calls")"; rm -f "$ST/compact-auto.off"
sh "$T_ROOT/bin/session-autocompact.sh" '../x' ttys999
sh "$T_ROOT/bin/session-autocompact.sh" ac-bad 'ttys1;touch x'
t_eq "the helper: an unsafe session id or tty runs nothing" "" "$(cat "$T/osa.calls")"
unset HARBOR_AUTOCOMPACT_TTY HARBOR_AUTOCOMPACT_DELAY; export HARBOR_AUTOCOMPACT_PCT=101 HARBOR_AUTOCOMPACT_OSA=false

t_section "cleanup: a merged PR of this session asks once; [cleanup-ok] as the last line runs the sweep's RECLAIM rows"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/clean.calls"\ncase "$*" in *--apply*) echo "  RECLAIM  finished-worktrees  0B  wt-x" ;; esac\n' "$T" > "$T/clean"; chmod +x "$T/clean"
export HARBOR_CLEANUP_TOOL="$T/clean"
cleaned() { _n=0; until grep -q -- '--record' "$T/clean.calls" 2>/dev/null || [ "$_n" -ge 20 ]; do sleep 0.25; _n=$((_n + 1)); done; sleep 0.2; }
ev() { jq -nc --arg k "$1" --arg s "$2" --arg ts "$3" --arg sid "$4" '{id:"e",ts:$ts,kind:$k,subject:$s,src:"t",data:{session_id:$sid}}' >> "$T/bus/2020-01-01.jsonl"; }  # <kind> <subject> <ts> <sid>
mkdir -p "$T/bus"; : > "$T/clean.calls"
run cl-1 plain 'All set.'
t_eq "no PR of this session merged: no question" "" "$(cat "$T/out")"
ev pr.opened o/r#1 2020-01-01T00:00:01Z cl-1; ev pr.opened o/r#2 2020-01-01T00:00:01Z cl-other
ev pr.merged o/r#2 2020-01-01T00:00:02Z ""
run cl-1 plain 'All set.'
t_eq "another session's PR merged: no question" "" "$(cat "$T/out")"
ev pr.merged o/r#1 2020-01-01T00:00:05Z ""
run cl-1 plain 'All set.'
t_has "this session's PR merged: one continuation asks" "$(cat "$T/out")" '"additionalContext"'
t_has "...naming the PR and the line to answer with" "$(cat "$T/out")" 'o/r#1 merged'
t_has "...and the marker" "$(cat "$T/out")" '[cleanup-ok]'
run cl-1 plain 'All set.'
t_eq "the same merge does not ask again" "" "$(cat "$T/out")"
ev pr.opened o/r#3 2020-01-01T00:00:06Z cl-1; ev pr.merged o/r#3 2020-01-01T00:00:09Z ""
run cl-1 plain 'All set.'
t_has "a later merge of another of its PRs asks again" "$(cat "$T/out")" 'o/r#3 merged'
t_eq "...and nothing ran on a question" "" "$(cat "$T/clean.calls")"
run cl-q plain 'When it is merged I end with [cleanup-ok] on its own line.'
sleep 0.5; t_eq "a marker quoted mid-message: nothing runs" "" "$(cat "$T/clean.calls")"
run cl-run plain '[cleanup-ok]' "$RUN"
sleep 0.5; t_eq "a running background task: nothing runs" "" "$(cat "$T/clean.calls")"
: > "$ST/cleanup-auto.off"; run cl-off plain '[cleanup-ok]'; sleep 0.5
t_eq "cleanup-auto.off: nothing runs" "" "$(cat "$T/clean.calls")"; rm -f "$ST/cleanup-auto.off"
run cl-1 plain 'Merged, deployed, verified.
[cleanup-ok]'
t_has "[cleanup-ok] as the last line: the operator is told" "$(cat "$T/out")" 'Cleaning up'
cleaned; t_has "...the sweep applies on the live box" "$(cat "$T/clean.calls")" '--apply --live'
t_has "...then re-records the count" "$(cat "$T/clean.calls")" '--record --live'
t_has "...and logs what it reclaimed" "$(cat "$ST"/backups/session-cleanup/*/log)" 'reclaimed: finished-worktrees'
: > "$T/clean.calls"; : > "$T/osa.calls"
export HARBOR_AUTOCOMPACT_TTY=ttys999 HARBOR_AUTOCOMPACT_OSA="$T/osa" HARBOR_AUTOCOMPACT_DELAY=0
run cl-2 plain 'All done.
[cleanup-ok] [compact-ok]'
t_eq "both markers: ONE JSON object" 1 "$(grep -c . "$T/out")"
t_has "...telling of both" "$(cat "$T/out")" 'Cleaning up'
t_has "...both" "$(cat "$T/out")" 'Compacting'
cleaned; t_has "...the sweep ran" "$(cat "$T/clean.calls")" '--apply --live'
typed cl-2; t_has "...and /compact was typed" "$(cat "$T/osa.calls")" '/dev/ttys999'
sleep 0.5; : > "$T/clean.calls"; sh "$T_ROOT/bin/session-cleanup.sh" '../x'
t_eq "the helper: an unsafe session id runs nothing" "" "$(cat "$T/clean.calls")"
unset HARBOR_AUTOCOMPACT_TTY HARBOR_AUTOCOMPACT_DELAY HARBOR_CLEANUP_TOOL; export HARBOR_AUTOCOMPACT_OSA=false

t_section "fail-open, off switch, and speed"
printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2>&1; t_eq "garbage on stdin: exit 0, silent" "0:" "$?:$(cat "$T/out")"
printf '{"session_id":"../x","cwd":"/"}' | CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2>&1; t_eq "an unsafe session id writes nothing" "no" "$([ -e "$ST/x.json" ] && echo yes || echo no)"
: > "$ST/session-state.off"; run s-off plain 'Which one?'
t_eq "session-state.off: no record" no "$([ -e "$ST/sessions/s-off.json" ] && echo yes || echo no)"; rm -f "$ST/session-state.off"
tx early_red "$(tu c8 2020-01-01T00:00:01.000Z 'sh tests/x-test.sh')" "$(tr_ c8 'x-test: 3 passed, 1 failed')"
awk 'BEGIN { s = sprintf("%1000s", "x"); for (i = 0; i < 300; i++) printf "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}]}}\n", s }' >> "$T/early_red.jsonl"
run s-win1 early_red 'ok'; t_eq "a red run inside the default window is seen" blocked "$(rec s-win1 state)"
HARBOR_STATUS_WINDOW=100000 run s-win2 early_red 'ok'; t_eq "...and one older than the window is not (the stated trade)" no "$([ "$(rec s-win2 state)" = blocked ] && echo yes || echo no)"
awk 'BEGIN { s = sprintf("%1000s", "x"); for (i = 0; i < 20000; i++) printf "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}]}}\n", s }' > "$T/big.jsonl"
a="$(date +%s)"; run s-big big 'ok'; b="$(date +%s)"
t_eq "a 20 MB transcript is read through a window: still done within 2 s" yes "$([ $((b - a)) -le 2 ] && [ "$(rec s-big state)" = idle ] && echo yes || echo no)"
settle  # let the last detached bus append finish before the sandbox is removed
t_done
