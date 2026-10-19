#!/usr/bin/env sh
# The statusline's session-state bridge (harbor#1043, #1044): the state token golden rows, hidden once the payload's
# prompt_id moves past the record's; ctx_pct written to the bridge file, re-scaled to CLAUDE_CODE_AUTO_COMPACT_WINDOW.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/statusline-fixture.sh"
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW  # the operator's own window must not decide the "no window set" rows (harbor#1149)
SD="$TMP/state"; export HARBOR_STATUS_DIR="$SD"; mkdir -p "$SD/sessions"
pay() { # <session_id> <prompt_id> <used_pct> — prompt_id "-" omits the field
  p=""; [ "$2" = - ] || p='"prompt_id":"'"$2"'",'
  printf '{"session_id":"%s",%s"model":{"display_name":"M"},"context_window":{"context_window_size":1000000,"used_percentage":%s},%s}' "$1" "$p" "$3" "$WS"; }
recd() { printf '{"state":"%s","since":1,"agents":%s,"prompt_id":"%s"}\n' "$2" "${3:-0}" "${4:-p1}" > "$SD/sessions/$1.json"; }  # <sid> <state> [agents] [prompt]

t_section "the state token, golden"
recd s1 done;             t_eq "done"             "M 1M │ ctx 20% │ ✓ done"      "$(row1 "$(pay s1 p1 20)")"
recd s1 waiting-operator; t_eq "waiting-operator" "M 1M │ ctx 20% │ ? you"       "$(row1 "$(pay s1 p1 20)")"
recd s1 waiting-agents 2; t_eq "waiting-agents"   "M 1M │ ctx 20% │ ⧗ 2 agents"  "$(row1 "$(pay s1 p1 20)")"
recd s1 blocked;          t_eq "blocked"          "M 1M │ ctx 20% │ ✗ red"       "$(row1 "$(pay s1 p1 20)")"
recd s1 idle;             t_eq "idle shows nothing" "M 1M │ ctx 20%"             "$(row1 "$(pay s1 p1 20)")"
recd s1 done
t_eq "a newer prompt hides a stale record" "M 1M │ ctx 20%" "$(row1 "$(pay s1 p2 20)")"
t_eq "a payload with no prompt_id shows NO token: it cannot be told fresh from stale" "M 1M │ ctx 20%" "$(row1 "$(pay s1 - 20)")"
t_eq "another session's record is not shown" "M 1M │ ctx 20%" "$(row1 "$(pay s9 p1 20)")"
t_hasnt "the grammar: no two consecutive spaces" "$(row1 "$(pay s1 p1 20)")" "  "
printf 'red 2\n' > "$SD/sessions/s1.check"
t_eq "a lint verdict of red rides after the token and outlives the prompt" "M 1M │ ctx 20% │ ✓ done lint ✗" "$(row1 "$(pay s1 p1 20)")"
t_eq "...and shows with a stale record" "M 1M │ ctx 20% │ lint ✗" "$(row1 "$(pay s1 p2 20)")"
printf 'ok\n' > "$SD/sessions/s1.check"; t_eq "an ok verdict shows nothing" "M 1M │ ctx 20% │ ✓ done" "$(row1 "$(pay s1 p1 20)")"
rm -f "$SD/sessions/s1.check"
printf '{"state":"done"' > "$SD/sessions/s1.json"; t_eq "a torn record shows nothing and does not error" "M 1M │ ctx 20%" "$(row1 "$(pay s1 p1 20)")"

t_section "ctx_pct: written for the Stop hook, re-scaled to the auto-compact window"
cx() { cat "$SD/ctx/$1" 2>/dev/null; }
run "$(pay c1 p1 20)" >/dev/null;                          t_eq "no window set: the payload's own share" 20 "$(cx c1)"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 run "$(pay c2 p1 20)" >/dev/null; t_eq "400k window on a 1M model: 200k used is 50%" 50 "$(cx c2)"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 run "$(pay c3 p1 90)" >/dev/null; t_eq "...capped at 100" 100 "$(cx c3)"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=2000000 run "$(pay c4 p1 20)" >/dev/null; t_eq "a window above the model's is capped to it" 20 "$(cx c4)"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=50000 run "$(pay c5 p1 20)" >/dev/null;  t_eq "a window under the documented 100000 is ignored" 20 "$(cx c5)"
CLAUDE_CODE_AUTO_COMPACT_WINDOW=abc run "$(pay c6 p1 20)" >/dev/null;    t_eq "a non-numeric window is ignored" 20 "$(cx c6)"
t_eq "the row still shows the payload's own percentage under a window" "M 1M │ ctx 20%" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 row1 "$(pay c7 p1 20)")"
run "{$WS,\"session_id\":\"../x\",\"context_window\":{\"context_window_size\":1000000,\"used_percentage\":20}}" >/dev/null
t_eq "an unsafe session id writes nothing" no "$([ -e "$SD/x" ] || [ -e "$SD/ctx/../x" ] && echo yes || echo no)"
run "{$WS,\"session_id\":\"c8\"}" >/dev/null; t_eq "no used_percentage: no file (never a 0)" no "$([ -e "$SD/ctx/c8" ] && echo yes || echo no)"
t_done
