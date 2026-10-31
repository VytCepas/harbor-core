#!/usr/bin/env sh
# session-workflow-progress.sh's output follows contracts/logging.md (harbor#771): a finished or active agent is an ok line, a slow
# one a note, a stalled one a WARN with its fix, and the run ends with the summary. A stall exits 3, the tool's own
# contract, with 0 failed. HOME is a fixture, so no real transcript is read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/session-workflow-progress.sh"
H="$T_TMP/home"; W="$H/.claude/projects/p/wf_fixture"; mkdir -p "$W"
printf '%s\n' '{"type":"started","agentId":"aaa"}' '{"type":"started","agentId":"bbb"}' '{"type":"started","agentId":"ccc"}' \
  '{"type":"result","agentId":"aaa"}' > "$W/journal.jsonl"
printf '{"type":"tool_use","name":"Bash"}\n' > "$W/agent-aaa.jsonl"
printf '{"type":"tool_use","name":"Read"}\n' > "$W/agent-bbb.jsonl"
printf '{"type":"tool_use","name":"Bash"}\n' > "$W/agent-ccc.jsonl"
touch -t 202001010000 "$W/agent-aaa.jsonl" "$W/agent-ccc.jsonl"   # aaa is finished; ccc has not written since 2020
run() { HOME="$H" sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after() { awk -v p="$1" '$0 ~ p { f = 1; next } f { print; exit }' "$T_TMP/out"; }

t_section "a run with a finished, an active and a stalled agent"
t_eq "a stall exits 3" "exit 3" "$(run)"
t_eq "the header names the run" "── wf-progress · wf_fixture" "$(OUT | head -1)"
t_has "the counts are a note" "$(OUT)" "  note: started 3 · finished 1 · outstanding 2"
t_has "a finished agent is an ok line" "$(OUT)" "  ok: DONE aaa  1 calls"
t_has "a live agent is an ok line" "$(OUT)" "  ok: ACTIVE bbb  1 calls"
t_has "a stalled agent is a WARN" "$(OUT)" "  WARN: STALLED ccc  1 calls"
t_has "with its fix" "$(after '^  WARN: STALLED ccc')" "  fix: tail -c 2000 $W/agent-ccc.jsonl  # then TaskStop ccc"
t_eq "the summary counts 0 failed" "wf-progress: 2 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(ERR)"
t_eq "no legacy glyph is left" 0 "$(OUT | grep -c '^══\|^   [A-Z]')"

t_section "nothing stalled: exit 0 and the summary"
rm "$W/agent-ccc.jsonl"
t_eq "exit 0" "exit 0" "$(run)"
t_eq "the summary" "wf-progress: 2 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"

t_section "no runs: a note, exit 0"
rm -r "$W"
t_eq "exit 0" "exit 0" "$(run)"
t_has "the note" "$(OUT)" "  note: no workflow runs found under $H/.claude/projects"
t_eq "the summary" "wf-progress: 0 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"

t_section "no projects dir: FAIL, a no-fix line, exit 1"
t_eq "exit 1" "exit 1" "$(HOME="$T_TMP/empty" sh "$TOOL" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "the FAIL" "$(OUT)" "  FAIL: no $T_TMP/empty/.claude/projects"
t_has "its fix line" "$(after '^  FAIL: no ')" "  fix: none automatic — see"

t_section "an unknown option: FAIL, its fix, exit 1"
t_eq "exit 1" "exit 1" "$(run --bogus)"
t_has "the FAIL" "$(OUT)" "  FAIL: unknown option --bogus"
t_eq "its fix" "  fix: sh $TOOL --help" "$(after '^  FAIL: unknown')"
t_done
