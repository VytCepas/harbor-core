#!/usr/bin/env sh
# eval-tally.sh's output follows contracts/logging.md (harbor#771): stdout carries only the report and its data (the
# table, --json, the open list) and the log is on stderr; a FAIL is followed by its fix, the run ends with the
# summary, and the exit codes (0, 1 environment, 2 refused) are the ones it always had.
. "$(dirname "$0")/../../lib/core.sh"; t_init
AB="$T_ROOT/bin/eval-tally.sh"; B="$T_TMP"
ab() { sh "$AB" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }; ERR() { cat "$B/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$B/err"; }
shaped() { ERR | grep -vcE '^(  (ok|FAIL|WARN|note|skip|fix): |ab-tally: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "record: the confirmation is a log on stderr, stdout stays empty"
t_eq "it exits 0" "exit 0" "$(ab record --task T1 --varied cap --winner A)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the row is an ok line" "$(ERR)" "  ok: recorded: T1  cap  winner=A"
t_has "the ledger is a note" "$(ERR)" "  note: ledger:   "
t_eq "the summary ends it" "ab-tally: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "report: the table stays on stdout byte for byte, the summary is on stderr"
for w in A A B B; do sh "$AB" record --task "N-$w" --varied floor --winner "$w" >/dev/null 2>&1; done
t_eq "it exits 0" "exit 0" "$(ab report)"
t_eq "the row keeps its two-space indent and verdict" 1 "$(OUT | grep -cE '^  floor +n=4 .*too few to read)$')"
t_has "the legend is still there" "$(OUT)" "  A = control (the harness as it was)"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -cE '^  (ok|FAIL|WARN|note|skip|fix): |^ab-tally: ')"
t_eq "the summary is on stderr" "ab-tally: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "--json: stdout is the array and only that" array "$(ab report --json >/dev/null; OUT | jq -r type)"
t_eq "--json: the summary is on stderr" "ab-tally: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "an empty ledger is a note, not a failure"
EMPTY="$B/empty"; mkdir -p "$EMPTY"
t_eq "it exits 0" "exit 0" "$(CLAUDE_CONFIG_DIR="$EMPTY" ab report)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the note says so" "$(ERR)" "  note: no ledger yet at"
t_eq "the summary ends it" "ab-tally: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "refusals: FAIL, its fix, the summary, exit 2, nothing on stdout, no row written"
ROWS="$(wc -l < "$CLAUDE_CONFIG_DIR/MEMORY/AB/verdicts.jsonl" | tr -d ' ')"
t_eq "no winner exits 2" "exit 2" "$(ab record --task T2 --varied cap)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL says it never infers one" "$(ERR)" "  FAIL: record needs --winner A, B or tie. This tool never infers one."
t_eq "its fix is the full command" "  fix: sh $AB record --task T2 --varied cap --winner A|B|tie" "$(after_fail)"
t_eq "the summary ends it" "ab-tally: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "a 49-char label exits 2" "exit 2" "$(ab record --task T3 --varied "$(printf 'y%.0s' $(seq 49))" --winner A)"
t_has "the FAIL names the cap" "$(ERR)" "  FAIL: --varied is a label, max 48 chars (got 49)"
t_has "its fix is on the next line" "$(after_fail)" "  fix: sh $AB record --task T3"
t_eq "--note exits 2" "exit 2" "$(ab record --task T4 --varied cap --winner A --note hi)"
t_has "the FAIL says it was removed" "$(ERR)" "  FAIL: --note was removed"
t_eq "an unknown flag exits 2" "exit 2" "$(ab record --grade 9)"
t_eq "its fix reads the help" "  fix: sh $AB --help" "$(after_fail)"
t_eq "refused records wrote no row" "$ROWS" "$(wc -l < "$CLAUDE_CONFIG_DIR/MEMORY/AB/verdicts.jsonl" | tr -d ' ')"
t_eq "no verb is a usage error: exit 2, no summary" "exit 2" "$(ab)"
t_eq "and prints no log line" 0 "$(ERR | grep -c '^ab-tally: [0-9]')"
t_done
