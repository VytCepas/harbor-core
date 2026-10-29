#!/usr/bin/env sh
# How the producers reach a box (harbor#1043 PR 2, harbor#1051 PR 1): floor-install.sh wires event-hook.sh at
# SessionStart, SessionEnd, SubagentStart, SubagentStop and PostToolUse (matcher limited to the tools
# that can open background work or a PR), copies it with the bus it calls, and floor-uninstall.sh
# takes both away again. The wired COMMAND, as written into the installed settings.json, is what
# the last section runs — the path the harness takes — against a payload on stdin.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SRC="$T_ROOT/bin"
fi_run() { _fr="$1"; _fd="$2"; shift 2; env -u CLAUDE_CONFIG_DIR sh "$SRC/$_fr" --dir "$_fd" "$@"; }  # <tool> <dir> [flags…]
cmds() { jq -r --arg e "$2" '[.hooks[$e][]?.hooks[]?.command // empty | select(test("event-hook\\.sh"))] | length' "$1/settings.json"; }  # <dir> <event>
D="$T_TMP/cfg-a"; mkdir -p "$D/bin"
FOREIGN='/bin/sh /somewhere/else/session-note.sh'
jq -n --arg c "$FOREIGN" '{hooks:{SessionStart:[{matcher:"",hooks:[{type:"command",command:$c}]}]}}' > "$D/settings.json"

t_section "the dry run names the producers and writes nothing"
out="$(fi_run floor-install.sh "$D" 2>&1)"
t_has "the plan wires SessionEnd" "$out" "hook to wire: SessionEnd (any): /bin/sh "
t_has "the plan names the producer files" "$out" "event producer to copy into"
t_has "the plan wires SubagentStart" "$out" "hook to wire: SubagentStart (any): /bin/sh "
t_has "the plan wires PostToolUse for the listed tools only" "$out" "hook to wire: PostToolUse Monitor|ScheduleWakeup|CronCreate|Workflow|Bash|Skill|Read: /bin/sh "
t_eq "...and nothing was written" "0 0 0 0 0" "$(cmds "$D" SessionStart) $(cmds "$D" SessionEnd) $(cmds "$D" SubagentStop) $(cmds "$D" SubagentStart) $(cmds "$D" PostToolUse)"

t_section "an apply wires each event exactly once, beside the foreign hook"
fi_run floor-install.sh "$D" --apply >/dev/null 2>&1; rc=$?
t_eq "the apply exits 0" 0 "$rc"
for e in SessionStart SessionEnd SubagentStart SubagentStop PostToolUse; do t_eq "$e: one event-hook.sh entry" 1 "$(cmds "$D" "$e")"; done
t_eq "PostToolUse: the matcher is exactly the seven tools (Skill and Read since harbor#1181), so the hook does not run on every call" "Bash CronCreate Monitor Read ScheduleWakeup Skill Workflow" \
  "$(jq -r '.hooks.PostToolUse[] | select(any(.hooks[]?; .command | test("event-hook\\.sh"))) | .matcher' "$D/settings.json" | tr '|' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "...and no event-hook.sh entry sits under another PostToolUse matcher" 1 \
  "$(jq -r '[.hooks.PostToolUse[] | select(any(.hooks[]?; .command | test("event-hook\\.sh")))] | length' "$D/settings.json")"
t_eq "the foreign SessionStart hook is still there" 1 "$(jq -r --arg c "$FOREIGN" '[.hooks.SessionStart[].hooks[].command | select(. == $c)] | length' "$D/settings.json")"
t_eq "no Stop hook was added (Stop is the end of a TURN)" 0 "$(jq -r '[.hooks.Stop[]?.hooks[]?.command // empty | select(test("event-hook"))] | length' "$D/settings.json")"
t_eq "the command is the installed copy, run by /bin/sh" "/bin/sh $(CDPATH= cd -P -- "$D" && pwd -P)/bin/event-hook.sh" \
  "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$D/settings.json")"
fi_run floor-install.sh "$D" --apply >/dev/null 2>&1
for e in SessionStart SessionEnd SubagentStart SubagentStop PostToolUse; do t_eq "$e: a re-apply keeps one entry" 1 "$(cmds "$D" "$e")"; done

t_section "the files land executable, with the library the bus needs, and are not pinned as guards"
for f in event-hook.sh event-bus.sh library-log.sh; do t_eq "$f is installed executable" yes "$([ -x "$D/bin/$f" ] && echo yes || echo no)"; done
t_eq "event-hook.sh is the repo's bytes" yes "$(cmp -s "$SRC/event-hook.sh" "$D/bin/event-hook.sh" && echo yes || echo no)"
t_eq "no content pin: the floor never depends on the bus" 0 "$(ls "$D/.helm-pins" | grep -c '^event-')"
t_eq "both files are in the install manifest" 2 "$(grep -c 'bin/event-' "$D/.harbor-manifest")"

t_section "the wired command, as the harness runs it, puts the event on the bus"
BUS="$T_TMP/bus"; export HARBOR_EVENT_DIR="$BUS"
fire() { # <event> <payload> — runs the first event-hook command wired for <event>, payload on stdin
  _c="$(jq -r --arg e "$1" '[.hooks[$e][].hooks[].command | select(test("event-hook\\.sh"))][0]' "$D/settings.json")"
  printf '%s' "$2" > "$T_TMP/in.json"; ( cd "$T_TMP" && $_c < "$T_TMP/in.json" ); }
fire SessionStart '{"session_id":"w-1","hook_event_name":"SessionStart","source":"startup"}'; rc=$?
t_eq "SessionStart command exits 0" 0 "$rc"
fire SubagentStop '{"session_id":"w-1","agent_id":"w-a","hook_event_name":"SubagentStop"}'
fire SessionEnd '{"session_id":"w-1","hook_event_name":"SessionEnd","reason":"other"}'
fire SubagentStart '{"session_id":"w-1","agent_id":"w-a","hook_event_name":"SubagentStart"}'
fire PostToolUse '{"session_id":"w-1","hook_event_name":"PostToolUse","tool_name":"Monitor","tool_input":{"command":"x"},"tool_response":"ok","tool_use_id":"w-tu"}'
t_eq "the five events, in order, from the installed copy" "session.start w-1;agent.done w-a;session.stop w-1;agent.spawn w-a;tool.background.start w-1:w-tu;" \
  "$(cat "$BUS"/*.jsonl | jq -r '"\(.kind) \(.subject)"' | tr '\n' ';')"

t_section "an uninstall takes the hooks and both files away, and keeps the foreign hook"
fi_run floor-uninstall.sh "$D" --apply >/dev/null 2>&1; rc=$?
t_eq "the uninstall exits 0" 0 "$rc"
for e in SessionStart SessionEnd SubagentStart SubagentStop PostToolUse; do t_eq "$e: no event-hook.sh entry left" 0 "$(cmds "$D" "$e")"; done
t_eq "the foreign SessionStart hook survived" 1 "$(jq -r --arg c "$FOREIGN" '[.hooks.SessionStart[]?.hooks[]?.command | select(. == $c)] | length' "$D/settings.json")"
t_eq "event-hook.sh and event-bus.sh are gone from bin/" "no no" \
  "$([ -e "$D/bin/event-hook.sh" ] && echo yes || echo no) $([ -e "$D/bin/event-bus.sh" ] && echo yes || echo no)"
t_done
