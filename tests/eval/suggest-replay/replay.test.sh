#!/usr/bin/env sh
# eval-suggest-replay.sh (harbor#1485): per-row counts and payload hashes over a synthetic transcript store, never the operator's. The
# report holds no sample, the run leaves no file, and samples reach only a terminal with no agent on it, through the scrub controls.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$T_TMP"; TOOL="$T_ROOT/bin/eval-suggest-replay.sh"; TABLE="$T_ROOT/fixtures/injection-rule/suggest-tool.tsv"
STORE="$B/store"; mkdir -p "$STORE/proj-a/sess-1/subagents"
HARBOR_SESSION_TRANSCRIPTS="$STORE"; export HARBOR_SESSION_TRANSCRIPTS
unset CLAUDECODE
NOW="$(jq -nr 'now | todate')"; OLD="$(jq -nr '(now - 40 * 86400) | todate')"
rec() { # <tool> <input json> [timestamp] [extra json fields]
  _x="${4:-}"; [ -n "$_x" ] || _x='{}'
  jq -nc --arg n "$1" --argjson i "$2" --arg t "${3:-$NOW}" --argjson x "$_x" \
    '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",name:$n,input:$i}]}} + $x'
}
# A live-secret SHAPE, not a key: the family replay.test.sh uses, clean under both gitleaks pins.
SECRET='sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
{ rec Bash '{"command":"fixturectl report --token SAMPLETEXT"}'
  rec Bash '{"command":"fixturectl report --token SAMPLETEXT"}'
  rec Bash '{"command":"fixturectl report --other OTHERTEXT"}'
  rec Bash '{"command":"fixturectl report --dry-run"}'
  rec Bash '{"command":"grep fixturectl notes.txt"}'
  rec Bash '{"command":"git commit -m '"'"'fixturectl report'"'"'"}'
  rec Bash '{"command":"ls -la"}'
  rec mcp__fixture__export '{"query":"QUERYTEXT"}'
  rec Write '{"file_path":"'"$HOME"'/Deliverables/x/secretclient.csv","content":"x"}'
  rec Write '{"file_path":"'"$TMPDIR"'/a.csv","content":"x"}'
  rec WebSearch '{"query":"anything"}'
} > "$STORE/proj-a/sess-1.jsonl"
{ rec Bash '{"command":"fixturectl report 2"}'
  rec Bash '{"command":"fixturectl report --old OLDTEXT"}' "$OLD"
  rec Bash '{"command":"fixturectl report --side SIDETEXT"}' "$NOW" '{"isSidechain":true}'
  rec Bash '{"command":"fixturectl report --key '"$SECRET"'"}'
  printf 'not json at all\n'
} > "$STORE/proj-a/sess-2.jsonl"
rec Bash '{"command":"fixturectl report --subagent SUBTEXT"}' > "$STORE/proj-a/sess-1/subagents/agent-1.jsonl"

rp() { sh "$TOOL" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }
shaped() { OUT | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |suggest-replay: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "the report: per-row counts and payload hashes"
tree() { find "$HOME" "$CLAUDE_CONFIG_DIR" "$TMPDIR" "$STORE" -type f | sort | cksum; }
before="$(tree)"
t_eq "it exits 0" "exit 0" "$(rp --table "$TABLE")"
t_has "the store's size" "$(OUT)" '  ok: 13 tool call(s) in 2 session(s).'
t_has "a Bash row: quiet, mentions and old calls are out" "$(OUT)" 'fixture-verb: 5 match(es) in 2 session(s), 4 payload(s), 0 stood down'
t_has "a connector row, on a call with no Bash at all" "$(OUT)" 'fixture-connector: 1 match(es) in 1 session(s), 1 payload(s)'
t_has "a file row, its place computed" "$(OUT)" 'fixture-file: 1 match(es) in 1 session(s), 1 payload(s)'
t_has "a row with no match says 0" "$(OUT)" 'fixture-skill: 0 match(es)'
_h="$(printf '%s' '"fixturectl report --token SAMPLETEXT"' | shasum -a 256 | cut -c1-16)"
t_has "the repeated payload's hash, with its count" "$(OUT)" "$_h  x2"
t_hasnt "the intro is left out" "$(OUT)" 'fixture-intro'
t_eq "every line is the log's shape" 0 "$(shaped)"
t_eq "the summary ends it" 'suggest-replay: 1 ok, 0 failed, 0 warnings' "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(cat "$B/err")"

t_section "the report holds no sample, and the run leaves no file"
for _w in SAMPLETEXT OTHERTEXT QUERYTEXT secretclient 'fixturectl' "$SECRET" sk-or-v1 notes.txt; do
  t_hasnt "no $_w in the report" "$(OUT | sed 's/fixture-[a-z]*/row/g')" "$_w"
done
t_eq "nothing new in the home, config, temp or store" "$before" "$(tree)"
t_eq "the temp folder went on exit" "" "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -name 'harbor.*')"
t_eq "the transcript's own bytes are unchanged by the run" yes "$(grep -q SAMPLETEXT "$STORE/proj-a/sess-1.jsonl" && echo yes)"

t_section "the window and the population"
_hs="$(printf '%s' '"fixturectl report --side SIDETEXT"' | shasum -a 256 | cut -c1-16)"
t_hasnt "a side-chain call is not replayed" "$(OUT)" "$_hs"
_h3="$(printf '%s' '"fixturectl report 2"' | shasum -a 256 | cut -c1-16)"
t_has "...while a main-thread call of that file is (the arm above can fail)" "$(OUT)" "$_h3"
t_eq "a one-day window runs" "exit 0" "$(rp --table "$TABLE" --days 1)"
t_has "a call older than the window is cut by its own time" "$(OUT)" 'fixture-verb: 5 match(es)'
D3="$(jq -nr '(now - 3 * 86400) | todate')"
rec Bash '{"command":"fixturectl report --recent RECENTTEXT"}' "$D3" > "$STORE/proj-a/sess-5.jsonl"
rp --table "$TABLE" --days 7 >/dev/null
t_has "a 3-day-old call is inside a 7-day window" "$(OUT)" 'fixture-verb: 6 match(es)'
rp --table "$TABLE" --days 1 >/dev/null
t_has "...and outside a 1-day window, by its own time" "$(OUT)" 'fixture-verb: 5 match(es)'
rec Bash '{"command":"fixturectl report --undated"}' | jq -c 'del(.timestamp)' > "$STORE/proj-a/sess-5.jsonl"
touch -t "$(jq -nr '(now - 3 * 86400) | strftime("%Y%m%d%H%M")')" "$STORE/proj-a/sess-5.jsonl"
rp --table "$TABLE" --days 7 >/dev/null
t_has "a 3-day-old file with no time in it is inside a 7-day window" "$(OUT)" 'fixture-verb: 6 match(es)'
rp --table "$TABLE" --days 1 >/dev/null
t_has "...and outside a 1-day window, by the file's age" "$(OUT)" 'fixture-verb: 5 match(es)'
rm -f "$STORE/proj-a/sess-5.jsonl"
rec Bash '{"command":"fixturectl report --ancient"}' > "$STORE/proj-a/sess-3.jsonl"
touch -t 202001010000 "$STORE/proj-a/sess-3.jsonl"
t_eq "an old file runs" "exit 0" "$(rp --table "$TABLE")"
t_has "an old file is out by its age" "$(OUT)" 'in 2 session(s).'
rm -f "$STORE/proj-a/sess-3.jsonl"

t_section "a stand-down is counted; a refused row is said"
printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\nci-read\tverb\tBash\tgh\t^gh pr checks\t-\tA plain line for a test.\t-\tno\t-\t-\tcore\nbad-ere\tverb\tBash\tgh\t^gh (\t-\tA plain line for a test.\t-\tno\t-\t-\tcore\nshort\tverb\tBash\n' > "$B/t.tsv"
rec Bash '{"command":"until gh pr checks 1; do sleep 5; done"}' > "$STORE/proj-a/sess-4.jsonl"
rec Bash '{"command":"gh pr checks 1"}' >> "$STORE/proj-a/sess-4.jsonl"
t_eq "it exits 0" "exit 0" "$(rp --table "$B/t.tsv")"
t_has "both match and one stands down" "$(OUT)" 'ci-read: 2 match(es) in 1 session(s), 2 payload(s), 1 stood down'
t_has "the short row is reported, not hidden" "$(OUT)" 'WARN: 1 row(s) the rule would refuse'
t_has "a bad ERE matches nothing and silences nothing" "$(OUT)" 'bad-ere: 0 match(es)'
rm -f "$STORE/proj-a/sess-4.jsonl"

t_section "the shipped table, and what stops a run"
t_eq "the shipped empty table exits 0" "exit 0" "$(rp)"
t_has "it says there is nothing to replay" "$(OUT)" 'skip: the table has no rows'
t_eq "an unknown flag exits 2" "exit 2" "$(rp --nope)"
t_eq "--days must be a number" "exit 2" "$(rp --days x)"
t_eq "--days must be above 0" "exit 2" "$(rp --days 0)"
for _sh in sh dash; do
  command -v "$_sh" >/dev/null 2>&1 || continue
  for _f in --days --table --samples; do
    "$_sh" "$TOOL" "$_f" >"$B/out" 2>"$B/err"; _rc=$?
    t_eq "$_sh: a trailing $_f with no value exits 2" 2 "$_rc"
    t_has "...and says what it takes, in the log's shape" "$(OUT)" "FAIL: $_f takes"
    t_has "...with a fix line" "$(OUT)" 'fix: '
    t_eq "...and no shell error" "" "$(cat "$B/err")"
  done
done

t_section "a signal ends the run: the trap does not carry on over a deleted temp folder"
_rj="$(command -v jq)"
# The first jq after the trap sends the script TERM, then runs: the script must stop there, not resume over its deleted folder.
printf '#!/bin/sh\nn=0; until [ -s "%s" ] || [ "$n" -gt 200 ]; do sleep 0.01; n=$((n + 1)); done\nkill -TERM "$(cat "%s")"\nexec "%s" "$@"\n' "$B/pid" "$B/pid" "$_rj" > "$T_BIN/jq"; chmod +x "$T_BIN/jq"
: > "$B/pid"
sh "$TOOL" --table "$TABLE" >"$B/out" 2>"$B/err" & _p=$!
echo "$_p" > "$B/pid"
wait "$_p"; _rc=$?
rm -f "$T_BIN/jq"
t_eq "TERM exits 130, it does not finish" 130 "$_rc"
t_hasnt "...and there is no summary" "run: $(OUT)" 'suggest-replay: '
t_eq "...and the temp folder went" "" "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -name 'harbor.*')"
t_eq "an absent table exits 2" "exit 2" "$(rp --table "$B/absent.tsv")"
t_eq "--help works" "exit 0" "$(rp --help)"
t_has "--help is the header" "$(OUT)" 'per-row counts and payload hashes'
t_eq "an absent store exits 0" "exit 0" "$(HARBOR_SESSION_TRANSCRIPTS="$B/none" rp --table "$TABLE")"
t_has "its absence is a skip" "$(OUT)" 'skip: no transcript store'

t_section "samples reach only a person's terminal"
t_eq "piped output is refused" "exit 2" "$(rp --table "$TABLE" --samples fixture-verb)"
t_has "the refusal says why" "$(OUT)" "samples print only to a person's terminal"
t_hasnt "and read nothing" "$(OUT)" SAMPLETEXT
# A real terminal, for the two arms a pipe cannot reach. BSD and util-linux `script` differ.
pty() { # <cmd...> -> the terminal's output
  case "$(uname -s)" in
    Darwin) script -q /dev/null "$@" 2>&1 </dev/null ;;
    *) script -qec "$*" /dev/null 2>&1 </dev/null ;;
  esac
}
# script echoes the EOF of its stdin first, so the probe looks inside the output. A sandbox refuses openpty: then the arms below are skipped, and say so.
t_skip_pty=1
if command -v script >/dev/null 2>&1; then case "$(pty sh -c 'test -t 1 && echo on-a-tty')" in *on-a-tty*) t_skip_pty=0 ;; esac; fi
if [ "$t_skip_pty" = 1 ]; then
  printf '  skip: no pty here, the terminal arms did not run\n'
elif ! command -v gitleaks >/dev/null 2>&1; then
  _o="$(pty sh "$TOOL" --table "$TABLE" --samples fixture-verb)"
  t_has "no gitleaks: the scrub controls refuse and no sample is shown" "$_o" 'the scrub controls refused the corpus'
else
  _o="$(pty sh "$TOOL" --table "$TABLE" --samples fixture-verb | tr -d '\r')"
  t_has "a person sees a sample" "$_o" 'fixturectl report --token SAMPLETEXT'
  t_hasnt "quiet holds in samples" "$_o" 'dry-run'
  t_hasnt "a mention is not a sample" "$_o" 'notes.txt'
  t_hasnt "the secret's value is scrubbed" "$_o" "$SECRET"
  t_has "its shape survives" "$_o" 'sk-or-v1-aaaa'
  t_has "the sample carries the report's hash" "$_o" "$_h"
  t_eq "the corpus went with the run" "" "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -name 'harbor.*')"
  # A short path: the scrub takes any long run of path characters for a PEM body, so a path in this test's temp tree would not survive it.
  rec Write '{"file_path":"/srv/x/sheet.csv","content":"x"}' > "$STORE/proj-a/sess-5.jsonl"
  printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\nsheet\ttool\tWrite\t-\t^Write csv project$\t-\tA plain line for a test.\t-\tno\t-\t-\tcore\n' > "$B/t2.tsv"
  _o="$(pty sh "$TOOL" --table "$B/t2.tsv" --samples sheet | tr -d '\r')"
  t_has "a file row's sample is its scrubbed path" "$_o" '/srv/x/sheet.csv'
  rm -f "$STORE/proj-a/sess-5.jsonl"
  _o="$(pty sh "$TOOL" --table "$TABLE" --samples fixture-connector | tr -d '\r')"
  t_has "a connector row says it has no sample" "$_o" 'no argument to sample'
  t_hasnt "and shows none" "$_o" QUERYTEXT
  _o="$(pty env CLAUDECODE=1 sh "$TOOL" --table "$TABLE" --samples fixture-verb | tr -d '\r')"
  t_has "a terminal with an agent on it is refused" "$_o" "samples print only to a person's terminal"
  t_hasnt "and shows none" "$_o" SAMPLETEXT
fi
t_done
