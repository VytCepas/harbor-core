#!/usr/bin/env sh
# failure-observe.sh is Claude Code PostToolUseFailure hook output (channel 3 of contracts/logging.md, a `protocol`
# row in contracts/log-exempt.tsv): its stdout would be session context, so it prints NOTHING on any path, stdout or
# stderr, and exits 0 on every one (harbor#771). A log line here would corrupt the protocol. Fixtures only.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
SRC="$T_ROOT/bin"; D="$T_TMP/fo"; mkdir -p "$D/bin" "$D/MEMORY/OBSERVABILITY/h1"
cp "$SRC/guard-lib.sh" "$T_ROOT/hooks/failure-observe/failure-observe.sh" "$D/bin/"
printf 'h1\n' > "$D/.helm-obs-host"; printf '0123456789abcdef0123456789abcdef\n' > "$D/.helm-obs-salt"
SINK="$D/MEMORY/OBSERVABILITY/h1/tool-failures.jsonl"; : > "$SINK"; chmod 0600 "$SINK"; chmod 0500 "$D/MEMORY/OBSERVABILITY/h1"
GOOD='{"session_id":"s1","hook_event_name":"PostToolUseFailure","tool_name":"Read","tool_input":{"file_path":"/nowhere/x.md"},"error":"File does not exist.","is_interrupt":false,"duration_ms":7}'
fire() { printf '%s' "$1" | sh "$D/bin/failure-observe.sh" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }

t_section "a recorded failure: exit 0 and not a byte on stdout or stderr"
t_eq "exit 0" "exit 0" "$(fire "$GOOD")"
t_eq "one record was written" 1 "$(awk 'END{print NR+0}' "$SINK")"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "stderr is empty" "" "$(ERR)"

t_section "every refusing path is just as silent"
t_eq "an empty payload exits 0" "exit 0" "$(fire "")"
t_eq "...with no output" "" "$(OUT)$(ERR)"
t_eq "garbage exits 0" "exit 0" "$(fire 'not json {')"
t_eq "...with no output" "" "$(OUT)$(ERR)"
t_eq "an interrupt exits 0" "exit 0" "$(fire '{"tool_name":"Bash","is_interrupt":true,"tool_input":{"command":"sleep 9"}}')"
t_eq "...with no output" "" "$(OUT)$(ERR)"
t_eq "none of the refusals wrote a record" 1 "$(awk 'END{print NR+0}' "$SINK")"
rm -f "$D/bin/guard-lib.sh"
t_eq "a missing library exits 0" "exit 0" "$(fire "$GOOD")"
t_eq "...with no output" "" "$(OUT)$(ERR)"
t_done
