#!/usr/bin/env sh
# eval-replay-corpus.sh, eval-replay.sh and eval-replay-worker.sh follow contracts/logging.md (harbor#771): every line is the
# log's shape, a FAIL is followed by its fix, the run ends with the summary, and the exit codes are the ones
# the tools always had. The worker's stdout is a verdict row eval-replay.sh reads as data, so its log is on stderr.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SRC="$T_ROOT/bin"; TMP="$T_TMP"; CFG="$T_TMP/cfg"; TAB="$(printf '\t')"
TR="$TMP/projects/p"; mkdir -p "$TR"
rec() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1"; }
{ rec 'ls -la /tmp'; rec 'echo hello world'; rec 'rm -rf /'; rec 'git status --short'; } > "$TR/s.jsonl"
export HARBOR_SESSION_TRANSCRIPTS="$TMP/projects"
corpus() { CLAUDE_CONFIG_DIR="$CFG" sh "$SRC/eval-replay-corpus.sh" "$@" >"$TMP/out" 2>"$TMP/err"; echo "exit $?"; }
replay() { CLAUDE_CONFIG_DIR="$CFG" sh "$SRC/eval-replay.sh" "$@" >"$TMP/out" 2>"$TMP/err"; echo "exit $?"; }
OUT() { cat "$TMP/out"; }; ERR() { cat "$TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$TMP/out"; }
shaped() { OUT | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |[a-z-]+: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "replay-corpus: a dry run is a log, ends with the summary, exit 0"
t_eq "it exits 0" "exit 0" "$(corpus)"
t_eq "the header" "── replay-corpus · corpus" "$(OUT | head -1)"
t_has "the corpus size is an ok line" "$(OUT)" "  ok: corpus size     4 records"
t_has "a dry run says so as a note" "$(OUT)" "  note: DRY RUN — nothing written"
t_eq "the summary ends it" "replay-corpus: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"

t_section "replay-corpus: a refusal is FAIL, its fix, the summary, exit 1"
t_eq "a path in the config dir" "exit 1" "$(corpus --to "$CFG/x.jsonl")"
t_has "the FAIL names the refusal" "$(OUT)" "  FAIL: refusing to write inside the config dir"
t_has "its fix writes elsewhere" "$(after_fail)" "  fix: sh $SRC/eval-replay-corpus.sh --to"
t_eq "the summary counts it" "replay-corpus: 1 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "an unknown option" "exit 1" "$(corpus --bogus)"
t_has "the FAIL names the option" "$(OUT)" "  FAIL: unknown option --bogus"
t_has "its fix reads the help" "$(after_fail)" "  fix: sh $SRC/eval-replay-corpus.sh --help"
t_eq "nothing is left on stderr" 0 "$(ERR | wc -l | tr -d ' ')"

t_section "replay: a report is a log with one summary, exit 0"
t_eq "it exits 0" "exit 0" "$(replay --report --limit 4 --jobs 4)"
t_has "the header names the records" "$(OUT)" "── replay · 4 records"
t_has "the builder's header is carried" "$(OUT)" "── replay-corpus · corpus"
t_eq "the builder's summary is not repeated" 0 "$(OUT | grep -c '^replay-corpus: ')"
t_eq "the last line is replay's summary" 1 "$(OUT | tail -1 | grep -c '^replay: [0-9][0-9]* ok, 0 failed, [0-9][0-9]* warnings$')"
t_eq "every line is the log's shape" 0 "$(shaped)"
t_eq "no !! glyph is left" 0 "$(OUT | grep -c '!!')"

t_section "replay: no baseline is FAIL, its fix, the summary, exit 1"
t_eq "a diff with no baseline" "exit 1" "$(replay --limit 4 --jobs 4)"
t_has "the FAIL says there is none" "$(OUT)" "  FAIL: no baseline at"
t_has "its fix writes one" "$(after_fail)" "  fix: sh $SRC/eval-replay.sh --baseline"
t_eq "the summary ends it" 1 "$(OUT | tail -1 | grep -c '^replay: [0-9][0-9]* ok, 1 failed, 0 warnings$')"

t_section "replay: a delta that finds a newly blocked command fails with its fix, exit 3"
replay --baseline --limit 4 --jobs 4 >/dev/null
# Forge the baseline: every record was ALLOW then, so today's blocks are newly blocked.
awk -F'\t' 'BEGIN { OFS = "\t" } { $2 = "ALLOW"; $3 = "-"; print }' "$CFG/.helm-replay/baseline.tsv" > "$TMP/b.tsv"
cp "$TMP/b.tsv" "$CFG/.helm-replay/baseline.tsv"
t_eq "exit 3, as it always was" "exit 3" "$(replay --limit 4 --jobs 4)"
t_has "the FAIL counts them" "$(OUT)" "  FAIL: newly BLOCKED  1"
t_has "its fix opens the queue" "$(after_fail)" "  fix: sh $SRC/eval-replay.sh --labels"
t_eq "the summary ends it" 1 "$(OUT | tail -1 | grep -c '^replay: [0-9][0-9]* ok, 1 failed, [0-9][0-9]* warnings$')"

t_section "replay-worker: the verdict is data on stdout, the log is on stderr"
W="$TMP/w"; mkdir -p "$W/bin"; printf 'not json at all\n' > "$TMP/bad.rec"
sh "$SRC/eval-replay-worker.sh" "$W" < "$TMP/bad.rec" >"$TMP/out" 2>"$TMP/err"; _rc=$?
t_eq "it exits 0 even for an ERROR verdict" 0 "$_rc"
t_eq "stdout is exactly one verdict row" 1 "$(OUT | grep -c "^unparseable-[0-9]*${TAB}ERROR${TAB}no-id\$")"
t_eq "stdout carries nothing else" 1 "$(OUT | wc -l | tr -d ' ')"
t_has "the log says what was wrong" "$(ERR)" "  WARN: a record has no extractable id"
t_eq "a WARN is followed by its fix" "  fix: sh bin/eval-replay-corpus.sh --to \"\${TMPDIR:-/tmp}/corpus.jsonl\"" "$(awk '/^  WARN:/ { f = 1; next } f { print; exit }' "$TMP/err")"
t_eq "the summary ends stderr" "replay-worker: 0 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"
t_done
