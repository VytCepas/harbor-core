#!/usr/bin/env sh
# floor-equiv.sh's output follows contracts/logging.md (harbor#771): every line is the log's shape, each refusal
# is a FAIL followed by its fix, the run ends with the summary, and the exit codes (0 identical, 1 not
# equivalent, 2 refused) are the ones the tool always had. The guards are stubs, so this is fast and hermetic.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/floor-equiv.sh"; B="$T_TMP"
guard() { # <dir> <blocks yes|no>
  mkdir -p "$1"
  { printf '#!/bin/sh\n# floor_block bash "stub" rule-a.flat\n'
    if [ "$2" = yes ]; then printf 'grep -q bad && { echo "HELM FLOOR [bash:rule-a]: BLOCKED" >&2; exit 2; }\n'; fi
    printf 'exit 0\n'; } > "$1/guard-bash.sh"
}
mkdir -p "$B/eqcfg"; guard "$B/base" yes; guard "$B/same" yes; guard "$B/mut" no
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"bad thing"}}' '{"tool_name":"Bash","tool_input":{"command":"fine"}}' > "$B/c.jsonl"
printf '%s\n' '{"tool_name":"Bash","tool_input":{"command":"fine"}}' > "$B/inert.jsonl"; : > "$B/empty.jsonl"
fe() { sh "$TOOL" --config "$B/eqcfg" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }; ERR() { cat "$B/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$B/out"; }
shaped() { OUT | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |floor-equiv: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "identical trees: a log, the ok line, the summary, exit 0"
t_eq "it exits 0" "exit 0" "$(fe --baseline "$B/base" --candidate "$B/same" --corpus "$B/c.jsonl")"
t_eq "the header names the payloads and the guard" "── floor-equiv · 2 payload(s), guard guard-bash.sh" "$(OUT | head -1)"
t_has "the counts are a note" "$(OUT)" "  note: 2 identical, 0 DIFFERENT"
t_has "the verdict is an ok line" "$(OUT)" "  ok: every verdict identical, exit code and rule id alike"
t_eq "the summary ends it" "floor-equiv: 1 ok, 0 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"
t_eq "stderr is empty" "" "$(ERR)"

t_section "a deleted rule: DIFFER notes, the FAIL, its fix, the summary, exit 1"
t_eq "it exits 1" "exit 1" "$(fe --baseline "$B/base" --candidate "$B/mut" --corpus "$B/c.jsonl")"
t_has "a difference is a note" "$(OUT)" "  note: DIFFER  baseline=2|bash:rule-a  candidate=0|"
t_has "the FAIL says not equivalent" "$(OUT)" "  FAIL: the candidate is NOT equivalent to the baseline: 1 DIFFERENT"
t_has "its fix reruns with every difference" "$(after_fail)" "  fix: sh $TOOL --baseline $B/base --candidate $B/mut --guard guard-bash.sh --verbose"
t_eq "the summary counts the failure" "floor-equiv: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "every line is the log's shape" 0 "$(shaped)"

t_section "a corpus that triggers no rule is refused: FAIL, fix, summary, exit 2"
t_eq "it exits 2" "exit 2" "$(fe --baseline "$B/base" --candidate "$B/same" --corpus "$B/inert.jsonl")"
t_has "the FAIL says why" "$(OUT)" "  FAIL: REFUSING TO CALL THIS EQUIVALENT"
t_has "its fix names a corpus" "$(after_fail)" "  fix: sh $TOOL --baseline $B/base --candidate $B/same --corpus fixtures/admission-corpus.jsonl"
t_eq "the summary ends it" 1 "$(OUT | tail -1 | grep -c '^floor-equiv: [0-9]* ok, 1 failed, 0 warnings$')"

t_section "an empty corpus and a usage error are refused the same way"
t_eq "an empty corpus exits 2" "exit 2" "$(fe --baseline "$B/base" --candidate "$B/same" --corpus "$B/empty.jsonl")"
t_has "its FAIL" "$(OUT)" "  FAIL: the corpus is EMPTY"
t_has "its fix" "$(after_fail)" "  fix: sh $TOOL --baseline"
t_eq "an unknown argument exits 2" "exit 2" "$(fe --bogus)"
t_has "its FAIL names it" "$(OUT)" "  FAIL: unknown argument: --bogus"
t_has "its fix reads the help" "$(after_fail)" "  fix: sh $TOOL --help"
t_eq "and the summary ends it" "floor-equiv: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"
t_eq "a missing candidate exits 2" "exit 2" "$(fe --baseline "$B/base")"
t_has "its FAIL" "$(OUT)" "  FAIL: --baseline and --candidate are both required"
t_eq "nothing was left on stderr" "" "$(ERR)"
t_section "a --config that does not exist is not the live dir"
fe2() { CLAUDE_CONFIG_DIR="$B/no-live" sh "$TOOL" --config "$B/no-cfg" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
fe2 --baseline "$B/base" --candidate "$B/same" --corpus "$B/c.jsonl" >/dev/null
t_eq "neither dir exists: no live-dir warning" 0 "$(OUT | grep -c 'is the LIVE dir')"
CLAUDE_CONFIG_DIR="$B/eqcfg" sh "$TOOL" --config "$B/eqcfg" --baseline "$B/base" --candidate "$B/same" --corpus "$B/c.jsonl" >"$B/out" 2>"$B/err"
t_eq "control: the same existing dir still warns" 1 "$(OUT | grep -c 'is the LIVE dir')"

t_done
