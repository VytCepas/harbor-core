#!/usr/bin/env sh
# status-usage-aggregate.sh's output follows contracts/logging.md (harbor#771): stdout carries only the report and its
# data (the tables, --json) and the log is on stderr; a FAIL is followed by its fix, the run ends with the
# summary, and the exit codes (0, 1 the live gate, 2 refused) are the ones it always had. The transcript tree
# is a fixture and the config dir a throwaway.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/status-usage-aggregate.sh"; B="$T_TMP/ua"
PROJ="$B/projects"; CFG="$B/cfg"; mkdir -p "$PROJ/p" "$CFG"
cat > "$PROJ/p/s.jsonl" <<'EOJ'
{"type":"assistant","sessionId":"sess-1","cwd":"/tmp/w","requestId":"r1","timestamp":"2026-08-01T10:00:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":3},"content":[{"type":"text","text":"abc"}]}}
{"type":"assistant","sessionId":"sess-1","cwd":"/tmp/w","requestId":"r2","timestamp":"2026-08-01T10:01:00.000Z","entrypoint":"cli","message":{"model":"m","usage":{"input_tokens":7,"output_tokens":1},"content":[{"type":"text","text":"de"}]}}
EOJ
export HARBOR_SESSION_TRANSCRIPTS="$PROJ"
ua() { sh "$TOOL" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }; ERR() { cat "$B/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$B/err"; }
shaped() { ERR | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |usage-aggregate: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "the report: the table on stdout unchanged, the log on stderr, exit 0"
t_eq "it exits 0" "exit 0" "$(ua "$CFG")"
t_eq "the report header is the first line of stdout" 1 "$(OUT | head -1 | grep -c '^usage-aggregate — host ')"
t_eq "the day row is byte-identical to the old table" "$(printf '%-10s  %-18s  %-8s  %7s  %10s  %10s  %10s  %10s' 2026-08-01 m cli 2 17 6 0 3)" "$(OUT | grep '^2026-08-01 ')"
t_has "it says the ledger was left alone" "$(OUT)" "(not written; pass --apply)"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -cE '^  (ok|FAIL|WARN|note|skip|fix): |^usage-aggregate: [0-9]')"
t_eq "the header on stderr" "── usage-aggregate · daily" "$(ERR | head -1)"
t_has "what ran is an ok line" "$(ERR)" "  ok: aggregated 1 transcript file(s) from $PROJ"
t_has "the unwritten ledger is a note" "$(ERR)" "  note: ledger not written; pass --apply"
t_eq "the summary ends stderr" "usage-aggregate: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "--json and --sessions keep stdout as data"
t_eq "--json exits 0" "exit 0" "$(ua --json "$CFG")"
t_eq "stdout is one JSON document" 17 "$(OUT | jq -r '.totals.input' 2>/dev/null)"
t_eq "the summary is on stderr" "usage-aggregate: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "--sessions exits 0" "exit 0" "$(ua --sessions "$CFG")"
t_eq "its report header" 1 "$(OUT | head -1 | grep -c '^usage-aggregate --sessions — host ')"
t_eq "its header on stderr" "── usage-aggregate · sessions" "$(ERR | head -1)"

t_section "--apply on a throwaway dir: the write is an ok line"
t_eq "it exits 0" "exit 0" "$(ua --apply "$CFG")"
t_has "the ledger is updated" "$(ERR)" "  ok: ledger updated: $CFG/MEMORY/USAGE/"
t_eq "the summary counts both ok lines" "usage-aggregate: 2 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "refusals: FAIL, its fix, the summary, nothing on stdout, the exit code the tool always had"
LIVE="$HOME/.claude"; mkdir -p "$LIVE"
t_eq "--apply on the live dir exits 1" "exit 1" "$(ua --apply "$LIVE")"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL is the live gate" "$(ERR)" "  FAIL: refusing to write the LIVE ledger without an explicit --live"
t_eq "its fix names --live" "  fix: sh $TOOL --apply --live" "$(after_fail)"
t_eq "the summary ends it" "usage-aggregate: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "an unknown option exits 2" "exit 2" "$(ua --nonsuch)"
t_has "its FAIL names it" "$(ERR)" "  FAIL: unknown option --nonsuch: nothing was aggregated"
t_eq "its fix reads the help" "  fix: sh $TOOL --help" "$(after_fail)"
t_eq "a bad --since exits 2" "exit 2" "$(ua --since yesterday "$CFG")"
t_has "its FAIL names the value" "$(ERR)" "  FAIL: --since wants YYYY-MM-DD, got yesterday"
t_eq "no transcript store exits 2" "exit 2" "$(HARBOR_SESSION_TRANSCRIPTS="$B/none" ua "$CFG")"
t_has "its FAIL names the path" "$(ERR)" "  FAIL: no transcript store at $B/none"
t_has "its fix names the variable" "$(after_fail)" "  fix: HARBOR_SESSION_TRANSCRIPTS=<projects dir> sh $TOOL"
t_done
