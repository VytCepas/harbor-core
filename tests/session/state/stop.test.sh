#!/usr/bin/env sh
# bin/session-state.sh, the Stop hook (harbor#1043, #1044): the five states in rule order, one test per waiting
# pattern in CONTRACTS/session-waiting.tsv, SG-2 parity with guard-stop.sh, an event only on a change, the record's
# fields, the save-now continuation (once, off without its rule, off under stop_hook_active), and a speed bound.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/session-state.sh"; GSTOP="$T_ROOT/bin/guard-stop.sh"; TABLE="$T_ROOT/CONTRACTS/session-waiting.tsv"
T="$T_TMP"; ST="$T/state"; REPO="$T/repo"; CFG="$T/cfg"
export HARBOR_STATUS_DIR="$ST" HARBOR_EVENT_DIR="$T/bus"
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
gs() { printf '{"session_id":"g-%s","transcript_path":"%s/%s.jsonl","cwd":"%s"}' "$1" "$T" "$1" "$REPO" | CLAUDE_CONFIG_DIR="$CFG" sh "$GSTOP" 2>/dev/null; }
for c in red healed readonly; do
  run "s-$c" "$c" 'ok'
  g="$(gs "$c")"; gb=no; case "$g" in *'"decision":"block"'*) gb=yes ;; esac
  sb=no; [ "$(rec "s-$c" state)" = blocked ] && sb=yes
  t_eq "$c: guard-stop blocks exactly when session-state says blocked" "$gb" "$sb"
done
t_eq "a red suite run in the session is blocked" blocked "$(rec s-red state)"
t_has "...and the reason is the verdict line" "$(rec s-red reason)" "3 passed, 1 failed"
t_eq "a later green run of it clears the block" idle "$(rec s-healed state)"
t_eq "a verdict only READ (cat) is not a run" idle "$(rec s-readonly state)"
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
