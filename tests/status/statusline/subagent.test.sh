#!/usr/bin/env sh
# L0-5 (harbor#59): bin/status-subagent-glyph.sh, the subagentStatusLine body: one row per live subagent,
# and the only surface that shows two agents sharing one working directory. `--dash`: under dash.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../hooks/statusline-fixture.sh"
sub() { printf '%s' "$1" | HARBOR_NOW=1787514000 "$SH" "$SRC/status-subagent-glyph.sh" 2>/dev/null; }
# The row's text with its colours decoded: jq writes ESC as a literal \u001b, which plain() cannot see.
row() { sub "$1" | jq -r '.content' | plain; }

t_section "subagent rows: a shared working directory is the point of the file"
SHAREPL='{"columns":100,"tasks":[{"id":"t1","name":"explore","status":"running","cwd":"/tmp/wf/sp"},{"id":"t2","name":"verify","status":"running","cwd":"/tmp/wf/sp"}]}'
t_has "two agents in one cwd are marked SHARED" "$(sub "$SHAREPL" | plain)" "sp SHARED"
t_eq "BOTH colliding rows are marked" 2 "$(sub "$SHAREPL" | grep -c SHARED)"
O="$(sub '{"columns":100,"tasks":[{"id":"t1","name":"explore","cwd":"/tmp/a"},{"id":"t2","name":"verify","cwd":"/tmp/b"}]}' | plain)"
t_hasnt "agents in DIFFERENT directories are not marked" "$O" 'SHARED'
t_hasnt "the full path does not render, only its tail" "$O" '/tmp/a'

t_section "subagent rows: the SAME grammar as the main row (one mark, two renderers)"
# The two renderers are compared to EACH OTHER, so a change to one side alone goes red.
OS="$(sub '{"columns":140,"tasks":[{"id":"g1","name":"reviewer","status":"running","model":"Opus 5","effort":"high","tokenCount":42000,"contextWindowSize":200000,"startTime":1787510400,"cwd":"/tmp/solo"}]}' | plain)"
t_has "the subagent row uses the boundary mark" "$OS" ' │ '
t_hasnt "the subagent row joins with no SPACED middot" "$OS" ' · '
t_hasnt "no double space in the subagent row" "$OS" '  '
# A run of non-alphanumeric bytes, not one character: U+2502 is three bytes to a byte-wise awk.
_mark_of() { printf '%s' "$1" | awk '{ if (match($0, / [^[:alnum:] ]+ /)) print substr($0, RSTART, RLENGTH); }' | head -1; }
OG="$(gram)"
t_eq "the main row has a boundary mark to compare" yes "$(yn [ -n "$(_mark_of "$OG")" ])"
t_eq "the subagent row has a boundary mark to compare" yes "$(yn [ -n "$(_mark_of "$OS")" ])"
t_eq "the two renderers agree on the boundary mark" "$(_mark_of "$OG")" "$(_mark_of "$OS")"

t_section "subagent rows: the context percentage is PER MODEL, or absent"
# contextWindowSize is omitted until the model resolves: 186k is 93% of 200k and 19% of 1M.
t_has "a 200k window renders 93%" "$(sub '{"tasks":[{"id":"t1","name":"a","contextWindowSize":200000,"tokenCount":186000}]}' | plain)" "93%"
t_has "the same count on a 1M window renders 19%" "$(sub '{"tasks":[{"id":"t1","name":"a","contextWindowSize":1000000,"tokenCount":186000}]}' | plain)" "19%"
O="$(sub '{"tasks":[{"id":"t1","name":"a","tokenCount":186000}]}' | plain)"
t_hasnt "no window size, no percentage" "$O" '%'
t_eq "the row still renders its name first" 'a' "$(row '{"tasks":[{"id":"t1","name":"a","tokenCount":186000}]}')"
t_has "a zero window size does not kill the render" "$(sub '{"tasks":[{"id":"t1","name":"zed","contextWindowSize":0,"tokenCount":5}]}' | plain)" 'zed'

t_section "subagent rows: absent fields, hostile fields, malformed payloads"
t_has "an explicit max effort renders upper-cased" "$(sub '{"tasks":[{"id":"t1","name":"a","effort":"max"}]}' | plain)" 'MAX'
O="$(sub '{"tasks":[{"id":"t1","name":"a"}]}' | plain)"
t_hasnt "an inherited effort renders no max" "$O" 'max'
t_hasnt "an inherited effort renders no medium" "$O" 'medium'
t_hasnt "an inherited effort renders no low" "$O" 'low'
t_eq "an inherited effort renders nothing (2026-10-16: the word sat on every row)" 'a' "$(row '{"tasks":[{"id":"t1","name":"a"}]}')"

t_eq "a task with no id emits no override" "" "$(sub '{"tasks":[{"name":"a","cwd":"/tmp/x"}]}' | plain)"
t_hasnt "the ordinary status renders nothing" "$(sub '{"tasks":[{"id":"t1","name":"a","status":"running"}]}' | plain)" 'running'
t_has "a non-ordinary status renders" "$(sub '{"tasks":[{"id":"t1","name":"a","status":"queued"}]}' | plain)" 'queued'
t_exit "a malformed payload still exits 0" 0 sh -c 'printf "not json at all" | "$1" "$2"' _ "$SH" "$SRC/status-subagent-glyph.sh"
t_eq "a malformed payload emits nothing" "" "$(printf 'not json at all' | "$SH" "$SRC/status-subagent-glyph.sh" 2>/dev/null)"
t_eq "an empty payload emits nothing" "" "$(printf '' | "$SH" "$SRC/status-subagent-glyph.sh" 2>/dev/null)"
t_eq "no tasks emit no rows" "" "$(sub '{"tasks":[]}')"
_valid="$(sub "$SHAREPL" | while IFS= read -r _l; do printf '%s' "$_l" | jq -e 'has("id") and has("content")' >/dev/null 2>&1 && echo ok; done | grep -c ok)"
t_eq "every emitted line is an object with id and content" "2/2" "$_valid/$(sub "$SHAREPL" | grep -c .)"

t_section "subagent rows: model and effort on every row (operator ask, 2026-10-09)"
t_has "a model id renders as its family" "$(row '{"tasks":[{"id":"t1","name":"a","model":"claude-sonnet-5-5"}]}')" 'a │ sonnet'
t_has "a dated model id renders its family only" "$(row '{"tasks":[{"id":"t1","name":"a","model":"claude-haiku-5-5-20260601"}]}')" 'a │ haiku'
t_has "a display name renders its family only" "$(row '{"tasks":[{"id":"t1","name":"a","model":"Opus 5"}]}')" 'a │ opus'
t_has "an object model renders its family" "$(row '{"tasks":[{"id":"t1","name":"a","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"}}]}')" 'a │ opus'
t_has "an alias renders as itself" "$(row '{"tasks":[{"id":"t1","name":"a","model":"haiku"}]}')" 'a │ haiku'
t_has "an unknown family renders its first word" "$(row '{"tasks":[{"id":"t1","name":"a","model":"mystery-7-1"}]}')" 'a │ mystery'
t_hasnt "no version digits render" "$(row '{"tasks":[{"id":"t1","name":"a","model":"claude-sonnet-5-5"}]}')" '5'
O="$(row '{"tasks":[{"id":"t1","name":"a","model":"claude-sonnet-5-5","effort":"high"}]}')"
t_has "an explicit effort renders after the model" "$O" 'sonnet │ high'
t_hasnt "an explicit effort is not called inherited" "$O" 'inherit'
t_hasnt "an unresolved model renders no empty field" "$(row '{"tasks":[{"id":"t1","name":"a","model":""}]}')" '│  │'

t_section "subagent rows: startTime has no documented unit, so all three are read"
# A fabricated age is worse than a missing one: "0m" on a wedged agent reads as "just started".
t_has "epoch MILLIseconds read as 10m" "$(sub '{"tasks":[{"id":"t1","name":"a","startTime":1787513400000}]}' | plain)" "10m"
t_has "epoch SECONDS read as 10m" "$(sub '{"tasks":[{"id":"t1","name":"a","startTime":1787513400}]}' | plain)" "10m"
t_has "an ISO startTime reads as 1h0m" "$(sub '{"tasks":[{"id":"t1","name":"a","startTime":"2026-08-23T18:40:00Z"}]}' | plain)" "1h0m"
t_eq "an unparseable startTime renders NO age" 0 "$(row '{"tasks":[{"id":"t1","name":"a","startTime":"banana"}]}' | grep -cE '[0-9][ms]')"

t_section "subagent rows: status icons, agent type, activity trace (2026-10-16)"
t_eq "completed is a dim word before the name" 'completed a' "$(row '{"tasks":[{"id":"t1","name":"a","status":"completed"}]}')"
t_has "failed is a red word" "$(sub '{"tasks":[{"id":"t1","name":"a","status":"failed"}]}' | jq -r .content)" "${ESC}[31mfailed${ESC}[0m a"
t_eq "killed is a red word too" 'killed a' "$(row '{"tasks":[{"id":"t1","name":"a","status":"killed"}]}')"
t_eq "any other status is a dim word, never red" 'queued a' "$(row '{"tasks":[{"id":"t1","name":"a","status":"queued"}]}')"
DONE='{"tasks":[{"id":"t1","name":"a","status":"running","cwd":"/tmp/wf/sp"},{"id":"t2","name":"b","status":"completed","cwd":"/tmp/wf/sp"}]}'
t_hasnt "a finished agent is no collision: one runner is not SHARED" "$(sub "$DONE" | plain)" 'SHARED'
DONE2='{"tasks":[{"id":"t1","name":"a","status":"running","cwd":"/tmp/wf/sp"},{"id":"t2","name":"b","status":"running","cwd":"/tmp/wf/sp"},{"id":"t3","name":"c","status":"completed","cwd":"/tmp/wf/sp"}]}'
t_eq "two runners are SHARED, the finished one beside them is not" 2 "$(sub "$DONE2" | grep -c SHARED)"
t_eq "the agent type follows the name, shortened" 'a general' "$(row '{"tasks":[{"id":"t1","name":"a","agentType":"general-purpose"}]}')"
t_eq "a plugin prefix is dropped" 'a code-reviewer' "$(row '{"tasks":[{"id":"t1","name":"a","agentType":"pr-review-toolkit:code-reviewer"}]}')"
t_eq "no agentType, no tag" 'a' "$(row '{"tasks":[{"id":"t1","name":"a"}]}')"
t_eq "rising readings draw the activity of each step" 'a │ ▁█▁' "$(row '{"tasks":[{"id":"t1","name":"a","tokenSamples":[0,10,100,110]}]}')"
t_eq "readings as objects work the same" 'a │ ▁█▁' "$(row '{"tasks":[{"id":"t1","name":"a","tokenSamples":[{"tokenCount":0},{"tokenCount":10},{"tokenCount":100},{"tokenCount":110}]}]}')"
t_eq "three flat steps on a running agent read idle" 'a │ █▁▁▁ idle' "$(row '{"tasks":[{"id":"t1","name":"a","status":"running","tokenSamples":[0,50,50,50,50]}]}')"
t_hasnt "a finished agent is never idle" "$(row '{"tasks":[{"id":"t1","name":"a","status":"completed","tokenSamples":[0,50,50,50,50]}]}')" 'idle'
t_eq "fewer than four readings draw nothing" 'a' "$(row '{"tasks":[{"id":"t1","name":"a","tokenSamples":[1,2,3]}]}')"
t_eq "garbage readings draw nothing" 'a' "$(row '{"tasks":[{"id":"t1","name":"a","tokenSamples":["x",null,{},[]]}]}')"
t_eq "an all-flat trace draws nothing but still says idle" 'a │ idle' "$(row '{"tasks":[{"id":"t1","name":"a","status":"running","tokenSamples":[5,5,5,5]}]}')"

t_done
