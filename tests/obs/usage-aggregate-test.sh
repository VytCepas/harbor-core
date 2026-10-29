#!/usr/bin/env sh
# usage-aggregate.sh, M9 (harbor#44, #119, #185). Every run reads a synthetic transcript
# tree (HARBOR_TRANSCRIPTS) into a throwaway config dir: never the operator's store.
# The ledger is idempotent and monotonic, because transcripts are garbage-collected.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/usage-aggregate.sh"; TMP="$T_TMP/ua"
PROJ="$TMP/projects"; CFG="$TMP/cfg"; mkdir -p "$PROJ/p1" "$CFG"
export HARBOR_TRANSCRIPTS="$PROJ"
# Line 4 is a user turn with no usage block; line 5 is junk (U-1).
cat > "$PROJ/p1/s1.jsonl" <<'EOJ'
{"type":"assistant","timestamp":"2026-08-01T10:00:00.000Z","entrypoint":"cli","message":{"model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2,"cache_read_input_tokens":3}}}
{"type":"assistant","timestamp":"2026-08-01T11:00:00.000Z","entrypoint":"cli","message":{"model":"claude-opus-5","usage":{"input_tokens":7,"output_tokens":1}}}
{"type":"assistant","timestamp":"2026-08-02T09:00:00.000Z","entrypoint":"sdk-cli","message":{"model":"claude-fable-5","usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"user","timestamp":"2026-08-02T09:00:01.000Z","message":{"role":"user"}}
{ this line is not json
EOJ
run() { HARBOR_TRANSCRIPTS="$PROJ" sh "$TOOL" "$@" 2>/dev/null; }
ua() { _t="$1"; shift; HARBOR_TRANSCRIPTS="$_t" sh "$TOOL" "$@" 2>/dev/null; }  # <transcripts> <args…>
ux() { _l="$1"; _w="$2"; _t="$3"; shift 3; t_exit "$_l" "$_w" env HARBOR_TRANSCRIPTS="$_t" sh "$TOOL" "$@"; }
field() { run --json "$CFG" | jq -r --arg d "$1" ".rows[] | select(.day==\$d) | .$2" | head -1; }  # <day> <field>
day_inp() { jq -r "select(.day==\"$2\").inp" "$1" 2>/dev/null; }  # <ledger> <day>
rows_of() { wc -l < "$1" 2>/dev/null | tr -d ' '; }

t_section "U-1: a malformed line must not swallow the records after it"
# jq aborts a JSONL stream at the first bad line; a half-written last line is the normal case.
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-01T12:00:00.000Z","entrypoint":"cli","message":{"model":"claude-opus-5","usage":{"input_tokens":1000,"output_tokens":1}}}' >> "$PROJ/p1/s1.jsonl"
t_eq "U-1 input after the malformed line" 1017 "$(field 2026-08-01 inp)"
t_eq "U-1 message count after the malformed line" 3 "$(field 2026-08-01 msgs)"

t_section "U-2: aggregation keys on (day, model, entrypoint)"
t_eq "U-2 output summed within a key" 7 "$(field 2026-08-01 out)"
t_eq "U-2 an absent cache field defaults to 0" 3 "$(field 2026-08-01 cr)"
t_eq "U-2 a second day is its own row" 100 "$(field 2026-08-02 inp)"
t_eq "U-2 row count" 2 "$(run --json "$CFG" | jq -r '.rows | length')"

t_section "U-3: a turn with no usage block is not a request"
t_eq "U-3 msgs" 4 "$(run --json "$CFG" | jq -r '.totals.msgs')"

t_section "U-4: no write at all without --apply"
rm -rf "$CFG/MEMORY"; run "$CFG" >/dev/null
t_eq "U-4 the report mode created no MEMORY dir" no "$([ -d "$CFG/MEMORY" ] && echo yes || echo no)"
t_has "U-4 the report says the ledger was left alone" "$(run "$CFG")" "not written"

t_section "U-5: --apply is idempotent, because a live transcript keeps growing"
HOST="$(run --json "$CFG" | jq -r .host)"
LED="$CFG/MEMORY/USAGE/$HOST/usage.jsonl"
run --apply "$CFG" >/dev/null; run --apply "$CFG" >/dev/null; run --apply "$CFG" >/dev/null
t_eq "U-5 three applies, two rows" 2 "$(rows_of "$LED")"
t_eq "U-5 no double count across applies" 1017 "$(day_inp "$LED" 2026-08-01)"

t_section "U-6: a row the current run did not cover survives"
run --apply --since 2026-08-02 "$CFG" >/dev/null
t_eq "U-6 --since kept the 2026-08-01 row" 1017 "$(day_inp "$LED" 2026-08-01)"
t_eq "U-6 row count unchanged" 2 "$(rows_of "$LED")"

t_section "U-7: --since filters what it reports"
t_eq "U-7 no earlier day in the report" 0 "$(run --json --since 2026-08-02 "$CFG" | jq '[.rows[] | select(.day=="2026-08-01")] | length')"

t_section "U-8: bad usage exits 2, distinct from an empty store"
ux "U-8 a malformed --since" 2 "$PROJ" --since notadate "$CFG"
ux "U-8 an unknown option" 2 "$PROJ" --nonsuch "$CFG"
ux "U-8 an absent transcript store" 2 "$TMP/absent" "$CFG"

t_section "U-9: the host key is guard-lib's canonical token, never hostname (harbor#119)"
t_eq "U-9 host key is floor_host_token" "$(. "$T_ROOT/bin/guard-lib.sh"; floor_host_token)" "$HOST"
t_eq "U-9 host key is a safe path segment" safe "$(case "$HOST" in (''|*[!A-Za-z0-9_-]*) echo unsafe ;; (*) echo safe ;; esac)"

t_section "U-10: the ledger carries integers and labels, never payload text"
t_eq "U-10 no field that is neither a count nor a label" 0 "$(jq -s '[.[] | to_entries[] | select((.value|type) != "number" and (.key|test("^(day|model|entry)$")|not))] | length' "$LED")"
t_eq "U-10 no whitespace in a label" 0 "$(jq -r '.model, .entry' "$LED" | grep -cE '[[:space:]]')"

t_section "U-11: --json and the table agree"
t_eq "U-11 the table total is the --json total" "$(run --json "$CFG" | jq -r '.totals.input')" "$(run "$CFG" | awk '/^2026-/ { s += $5 } END { print s+0 }')"

t_section "U-12: an empty-but-present store reports nothing and does not fail"
mkdir -p "$TMP/empty"
t_eq "U-12 zero rows" 0 "$(ua "$TMP/empty" --json "$CFG" | jq -r '.rows | length')"
ux "U-12 exit 0" 0 "$TMP/empty" "$CFG"

t_section "U-13: this suite is not pointed at the tool's default store"
LIVE_DIR="$HOME/.claude"  # named only to refuse it (lint D1)
t_eq "U-13 transcripts are not the default store" yes "$([ "$HARBOR_TRANSCRIPTS" != "$LIVE_DIR/projects" ] && echo yes || echo no)"
t_eq "U-13 the config dir is not the live dir" outside "$(case "$CFG" in ("$LIVE_DIR"|"$LIVE_DIR"/*) echo inside ;; (*) echo outside ;; esac)"

t_section "U-14: --apply refuses the live dir without --live (lint D2), however spelled"
mkdir -p "$LIVE_DIR"; ln -s "$LIVE_DIR" "$TMP/live-link"
ux "U-14 the live dir" 1 "$PROJ" --apply "$LIVE_DIR"
ux "U-14 a symlinked spelling of it" 1 "$PROJ" --apply "$TMP/live-link"
t_has "U-14 the refusal names the gate" "$(HARBOR_TRANSCRIPTS="$PROJ" sh "$TOOL" --apply "$TMP/live-link" 2>&1)" "refusing to write the LIVE ledger"
t_eq "U-14 nothing reached the live dir" no "$([ -d "$LIVE_DIR/MEMORY" ] && echo yes || echo no)"

t_section "U-15: a shrinking source window must not destroy a durable total"
GC="$TMP/gc"; mkdir -p "$GC/projects/p" "$GC/cfg"
printf '%s\n' '{"type":"a","timestamp":"2026-07-01T10:00:00Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":600,"output_tokens":6}}}' > "$GC/projects/p/one.jsonl"
printf '%s\n' '{"type":"a","timestamp":"2026-07-01T11:00:00Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":400,"output_tokens":4}}}' > "$GC/projects/p/two.jsonl"
ua "$GC/projects" --apply "$GC/cfg" >/dev/null
_gcl="$(find "$GC/cfg" -name usage.jsonl 2>/dev/null | head -1)"
t_eq "U-15 the full day before GC" 1000 "$(day_inp "$_gcl" 2026-07-01)"
rm -f "$GC/projects/p/two.jsonl"; ua "$GC/projects" --apply "$GC/cfg" >/dev/null
t_eq "U-15 GC of one transcript keeps the total" 1000 "$(day_inp "$_gcl" 2026-07-01)"
t_eq "U-15 the message count keeps too" 2 "$(jq -r 'select(.day=="2026-07-01").msgs' "$_gcl" 2>/dev/null)"
printf '%s\n' '{"type":"a","timestamp":"2026-07-01T12:00:00Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":5000,"output_tokens":1}}}' > "$GC/projects/p/three.jsonl"
ua "$GC/projects" --apply "$GC/cfg" >/dev/null
t_eq "U-15 a growing window still raises it" 5600 "$(day_inp "$_gcl" 2026-07-01)"

t_section "U-16..U-18: the scheduled jobs stay pointed at a shipped script and real flags"
_payload=" $(sed -n 's/^FILES="\(.*\)"$/\1/p' "$T_ROOT/bin/runtime-install.sh" | head -1) "
for _pl in "$T_ROOT/launchd/com.harbor.usage.plist" "$T_ROOT/launchd/com.harbor.usage-sessions.plist"; do
  _b="$(basename "$_pl")"
  t_eq "U-16 $_b exists" yes "$([ -f "$_pl" ] && echo yes || echo no)"
  if command -v plutil >/dev/null 2>&1; then t_exit "U-17 $_b is valid XML" 0 plutil -lint "$_pl"
  else echo "  (skipped U-17 for $_b: no plutil on this host)"; fi
  # The plist is a template (harbor#630: @HOME@, not a home); what launchd runs is what it renders to, so that is read.
  _rendered="$(sh "$T_ROOT/bin/launchd-render.sh" "$_pl" 2>/dev/null || true)"
  _prog="$(printf '%s\n' "$_rendered" | sed -n 's|.*<string>[^<]*/\.claude/bin/\([a-z0-9-]*\.sh\)</string>.*|\1|p' | head -1)"
  t_has "U-18 $_b runs a script runtime-install ships" "$_payload" " ${_prog:-NONE} "
  _flags="$(sed -n 's|.*<string>\(--[a-z-]*\)</string>.*|\1|p' "$_pl" | tr '\n' ' ')"
  t_has "U-18b $_b passes --apply" "$_flags" "--apply"
  for _f in $_flags; do t_has "U-18b $_b's $_f is a flag the tool parses" "$(cat "$TOOL")" "$_f)"; done
done

t_section "U-19..U-22: one row per requestId, keeping the completed record (harbor#185)"
DUP="$TMP/dup"; mkdir -p "$DUP/projects/p" "$DUP/cfg"
cat > "$DUP/projects/p/dup.jsonl" <<'EOJ'
{"type":"assistant","sessionId":"sess-dup","cwd":"/tmp/proj","requestId":"req_A","timestamp":"2026-08-03T10:00:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":100}}}
{"type":"assistant","sessionId":"sess-dup","cwd":"/tmp/proj","requestId":"req_A","timestamp":"2026-08-03T10:00:01.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":3,"cache_read_input_tokens":100}}}
{"type":"assistant","sessionId":"sess-dup","cwd":"/tmp/proj","requestId":"req_A","timestamp":"2026-08-03T10:00:02.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":40,"cache_read_input_tokens":100}}}
{"type":"assistant","sessionId":"sess-dup","cwd":"/tmp/proj","requestId":"req_B","timestamp":"2026-08-03T10:30:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":7,"cache_read_input_tokens":200}}}
EOJ
_du() { ua "$DUP/projects" --json "$DUP/cfg" | jq -r "$1"; }
t_eq "U-19 two requests are two calls" 2 "$(_du '.totals.msgs')"
t_eq "U-20 output is 40+7, not the partials summed" 47 "$(_du '.totals.output')"
t_eq "U-21 cache reads are 100+200" 300 "$(_du '.totals.cache_read')"
_nourid="$(cat "$PROJ"/*/*.jsonl 2>/dev/null | jq -R -n '[inputs | (fromjson? // empty) | select(type == "object") | select(.message.usage != null)] | length')"
t_eq "U-22 records with no requestId do not collapse" "$_nourid" "$(run --json "$CFG" | jq -r '.totals.msgs')"

t_section "U-23..U-30: per-session rows, byte split, tool join, gaps"
SES="$TMP/ses"; mkdir -p "$SES/projects/p" "$SES/cfg"
cat > "$SES/projects/p/s.jsonl" <<'EOJ'
{"type":"mode","sessionId":"sess-1"}
{"type":"assistant","sessionId":"sess-1","cwd":"/tmp/where","requestId":"r1","timestamp":"2026-08-04T10:00:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":1000},"content":[{"type":"text","text":"abcde"},{"type":"thinking","thinking":"","signature":"s"},{"type":"tool_use","id":"tu1","name":"Read","input":{"file_path":"/x"}}]}}
{"type":"user","sessionId":"sess-1","cwd":"/tmp/where","timestamp":"2026-08-04T10:00:05.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"0123456789"}]}}
{"type":"assistant","sessionId":"sess-1","cwd":"/tmp/where","requestId":"r2","timestamp":"2026-08-04T10:30:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":3000},"content":[{"type":"tool_use","id":"tu2","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","sessionId":"sess-1","cwd":"/tmp/where","timestamp":"2026-08-04T10:30:02.000Z","message":{"role":"user","content":"hi"}}
EOJ
_se() { ua "$SES/projects" --sessions --json "$SES/cfg" | jq -r "$1"; }
t_eq "U-23 the session id is read off the record" sess-1 "$(_se '.sessions[0].session')"
t_eq "U-24 the project dir skips the cwd-less first record" /tmp/where "$(_se '.sessions[0].project')"
t_eq "U-25 calls" 2 "$(_se '.sessions[0].calls')"
t_eq "U-26 prefix_max (r2: 10+0+3000)" 3010 "$(_se '.sessions[0].prefix_max')"
t_eq "U-27 prefix_mean ((1030+3010)/2)" 2020 "$(_se '.sessions[0].prefix_mean')"
t_eq "U-28 tool_result bytes join to Read via tool_use_id" 10 "$(_se '.sessions[0].tools[] | select(.name=="Read") | .bytes')"
t_eq "U-29 a string user turn is measured" 2 "$(_se '.sessions[0].b_user')"
t_eq "U-30 the 30-minute gap lands in 5-60m" 1 "$(_se '.sessions[0].gaps.m5_60')"

t_section "U-31..U-33: the session ledger is idempotent, monotonic and gated"
ua "$SES/projects" --sessions --apply "$SES/cfg" >/dev/null; ua "$SES/projects" --sessions --apply "$SES/cfg" >/dev/null
_slf="$(find "$SES/cfg/MEMORY/USAGE" -name 'sessions.jsonl' 2>/dev/null | head -1)"
t_eq "U-31 two applies, one row" 1 "$(rows_of "${_slf:-/nonexistent}")"
printf '%s\n' '{"session":"sess-1","calls":999,"records":999,"wall_s":9,"inp":9,"out":9,"cc":9,"cr":9999,"prefix_max":9,"b_tool_result":9,"b_tool_input":9,"b_assistant":9,"b_thinking":0,"b_user":9}' > "$_slf"
ua "$SES/projects" --sessions --apply "$SES/cfg" >/dev/null
t_eq "U-32 a narrower window does not lower a stored session" 9999 "$(jq -r 'select(.session=="sess-1").cr' "$_slf" 2>/dev/null)"
# No target given: the default is the active config dir, which on the operator's box is live.
t_exit "U-33 --sessions --apply refuses the default live dir" 1 env -u CLAUDE_CONFIG_DIR HARBOR_TRANSCRIPTS="$SES/projects" sh "$TOOL" --sessions --apply

t_section "U-34..U-39: one row per session, across parent and subagent files"
SUB="$TMP/sub"; mkdir -p "$SUB/projects/p/sess/subagents" "$SUB/cfg"
printf '%s\n' '{"type":"assistant","sessionId":"sess-x","cwd":"/tmp/deleg","requestId":"ra","timestamp":"2026-08-05T10:00:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":1000}}}' > "$SUB/projects/p/sess.jsonl"
printf '%s\n' '{"type":"assistant","sessionId":"sess-x","cwd":"/tmp/deleg","requestId":"rb","timestamp":"2026-08-05T10:10:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":1,"output_tokens":5,"cache_read_input_tokens":2000}}}' > "$SUB/projects/p/sess/subagents/agent-1.jsonl"
_sb() { ua "$SUB/projects" --sessions --json "$SUB/cfg" | jq -r "$1"; }
t_eq "U-34 two files under one sessionId are one row" 1 "$(_sb '.sessions | length')"
t_eq "U-35 calls sum across the files" 2 "$(_sb '.sessions[0].calls')"
t_eq "U-35 cache reads sum across the files" 3000 "$(_sb '.sessions[0].cr')"
t_eq "U-36 the subagent file is counted" 1 "$(_sb '.sessions[0].agents')"
t_eq "U-36 agent_calls" 1 "$(_sb '.sessions[0].agent_calls')"
t_eq "U-36 agent_cr" 2000 "$(_sb '.sessions[0].agent_cr')"
t_eq "U-37 the cross-file gap is seen" 1 "$(_sb '.sessions[0].gaps.m5_60')"
t_eq "U-37 wall time spans the files" 600 "$(_sb '.sessions[0].wall_s')"
ua "$SUB/projects" --sessions --apply "$SUB/cfg" >/dev/null; ua "$SUB/projects" --sessions --apply "$SUB/cfg" >/dev/null
_sbl="$(find "$SUB/cfg/MEMORY/USAGE" -name 'sessions.jsonl' 2>/dev/null | head -1)"
t_eq "U-38 the ledger holds one row for one session" 1 "$(rows_of "${_sbl:-/nonexistent}")"
t_eq "U-39 the stored row is the merged total" 3000 "$(jq -r 'select(.session=="sess-x").cr' "$_sbl" 2>/dev/null)"

t_section "U-40..U-41: tool_uses, and the message count it is divided by"
t_eq "U-40 tool_uses" 2 "$(_se '.sessions[0].tool_uses')"
t_eq "U-41 calls is the denominator, not records" 2 "$(_se '.sessions[0].calls')"
t_done
