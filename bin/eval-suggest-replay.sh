#!/usr/bin/env sh
# eval-suggest-replay.sh (harbor#1485) — replay a suggest-tool table over every tool call in the transcript store, extended from
# eval-hook-replay.sh. A row must have no false matches before it ships; the replay proves that, it does not choose the rows.
#
#   sh bin/eval-suggest-replay.sh [--days N] [--table FILE]                  per-row counts and payload hashes
#   sh bin/eval-suggest-replay.sh --samples <row> [--days N] [--table FILE]  scrubbed samples of one row, for a person at a terminal
#   HARBOR_SESSION_TRANSCRIPTS   override the transcript store (default: <config>/projects)
#
# THE REPORT HOLDS COUNTS AND HASHES, NEVER A COMMAND. A hash is the corpus id of eval-replay-corpus.sh, so a person can find a report
# line among the samples. Main-thread calls only, because a subagent's call never speaks. An intro row is left out: it answers to no
# call. A row is judged by the same functions the rule runs (context-rules/user/suggest-subject.sh); only matching is replayed, so the
# per-person gates (stopped, requires, a skill in use, the surface) are not. `stood down` counts matches another pack speaks on.
#
# SAMPLES GO THROUGH THE SCRUB CONTROLS: the corpus builder scrubs, verifies with gitleaks and drops, and refuses without gitleaks.
# They print only to a terminal with no agent on it, because an agent's tool output is itself a stored transcript. This is a guard
# against accident, not a wall: an agent that fakes both could still read them. Nothing is stored; the temp folder goes on exit.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the text is the header read from THIS file, so help cannot drift.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The report is the run's log (contracts/logging.md, harbor#771); there is no data on stdout.
. "$ROOT/bin/library-log.sh"
log_init suggest-replay
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "$3"; }
TAB='	'
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_DIR="${HARBOR_SESSION_TRANSCRIPTS:-$CFG/projects}"
DAYS=14; TABLE="$ROOT/context-rules/user/suggest-tool.tsv"; SAMPLE=''

while [ $# -gt 0 ]; do
  case "$1" in
    --days)    [ $# -ge 2 ] || die "--days takes a whole number of days: nothing was replayed" "sh $0 --days 14" 2; shift; DAYS="$1" ;;
    --table)   [ $# -ge 2 ] || die "--table takes a file: nothing was replayed" "sh $0 --table <file>" 2; shift; TABLE="$1" ;;
    --samples) shift; SAMPLE="${1:-}"; [ -n "$SAMPLE" ] || die "--samples takes a row id: nothing was replayed" "sh $0 --help" 2 ;;
    *) die "unknown flag $1: nothing was replayed" "sh $0 --help" 2 ;;
  esac
  shift
done
case "$DAYS" in ''|*[!0-9]*|0) die "--days takes a whole number of days above 0: $DAYS" "sh $0 --days 14" 2 ;; esac
[ -f "$TABLE" ] || die "no table at $TABLE: nothing was replayed" "sh $0 --table <file>" 2
if [ -n "$SAMPLE" ] && { [ ! -t 1 ] || [ -n "${CLAUDECODE:-}" ]; }; then
  die "samples print only to a person's terminal, and this run's output is not one: nothing was read" "run the same command yourself, in your own terminal" 2
fi
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)" 2

umask 077
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT; trap 'exit 130' INT HUP TERM
SUGGEST_HERE="$ROOT/context-rules/user"
. "$SUGGEST_HERE/suggest-subject.sh"
suggest_parser_load || die "the floor's parser is not beside this tool" "sh bin/admission-verify.sh --live" 2

hash16() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16; }
# The fields of a row, as suggest-tool.sh reads them. A cell is never empty, so tab as IFS loses nothing.
load() { IFS="$TAB" read -r ID KIND TOOLS WORD REC QUIET LINE SW SAFE INSTALL REQ SRC <<ROW
$1
ROW
}
suggest_rows '' "$TABLE" "$TABLE" > "$TMP/rows"
REFUSED="$(awk -F'\t' '/^#/ || NF == 0 || $1 == "id" { next } { n++ } END { print n + 0 }' "$TABLE")"
REFUSED=$(( REFUSED - $(wc -l < "$TMP/rows") ))

# A subject per candidate: the same word test and tools cell the rule applies, in one awk pass over the store per row. The word is
# limited to characters JSON does not escape, so it reads the same in the encoded command.
candidates() { # <calls file> -> the calls this row's tools and word let through
  LC_ALL=C SUGGEST_TOOLS="$TOOLS" SUGGEST_WORD="$WORD" awk -F'\t' '
    BEGIN { tools = "|" ENVIRON["SUGGEST_TOOLS"] "|"; w = ENVIRON["SUGGEST_WORD"] }
    index(tools, "|" $1 "|") == 0 { next }
    $1 == "Bash" && index($4, w) == 0 { next }
    { print }' "$1"
}

if [ -n "$SAMPLE" ]; then
  log_head "samples of $SAMPLE, scrubbed, for a person; nothing here is stored"
  ROW="$(awk -F'\t' -v i="$SAMPLE" '$1 == i && $2 != "intro" { print; exit }' "$TMP/rows")"
  [ -n "$ROW" ] || die "no replayable row $SAMPLE in the table" "sh $0" 2
  load "$ROW"
  HARBOR_SESSION_TRANSCRIPTS="$SRC_DIR" sh "$ROOT/bin/eval-replay-corpus.sh" --to "$TMP/corpus.jsonl" --since "$DAYS" >/dev/null 2>&1 \
    || die "the scrub controls refused the corpus, so no sample is shown" "sh bin/eval-replay-corpus.sh --since $DAYS" 1
  # The corpus labels every path Write, so a path is put to the row as the row's own file tool.
  n=0; FT=''
  for _t in Write Edit MultiEdit NotebookEdit; do case "|$TOOLS|" in *"|$_t|"*) FT="$_t"; break ;; esac; done
  jq -r --arg ft "$FT" 'if .kind == "payload" and .tool == "Bash" then ["Bash", .id, "-", (.payload | @json)]
         elif .kind == "file_path" and $ft != "" then [$ft, .id, "-", (.payload | @json)] else empty end | join("\t")' "$TMP/corpus.jsonl" > "$TMP/calls"
  candidates "$TMP/calls" > "$TMP/cand"
  while IFS="$TAB" read -r tool id _x pj; do
    p="$(printf '%s' "$pj" | jq -r .)"
    subj="$(suggest_subject "$tool" "$p")"
    suggest_row_hits "$tool" "$REC" "$QUIET" "$subj" || continue
    n=$(( n + 1 ))
    log_note "$id  $(printf '%s' "$p" | tr '\n' ' ' | cut -c1-88)"
    [ "$n" -lt 10 ] || break
  done < "$TMP/cand"
  case "$TOOLS" in Bash|*Write*|*Edit*) ;; *) log_note "a connector row has no argument to sample: its counts are the whole report" ;; esac
  log_ok "$n sample(s) shown."
  log_end; exit $?
fi

log_head "$(basename "$TABLE") vs every main-thread tool call of the last $DAYS day(s)"
[ -s "$TMP/rows" ] || [ "$REFUSED" -gt 0 ] || { log_skip "the table has no rows: nothing to replay."; log_end; exit $?; }
[ "$REFUSED" -eq 0 ] || log_warn "$REFUSED row(s) the rule would refuse are not replayed: sh bin/lint-suggest-table.sh $TABLE"
[ -d "$SRC_DIR" ] || { log_skip "no transcript store at ${SRC_DIR#"$HOME"/}: nothing to replay."; log_end; exit $?; }

# One call per line: tool, session number, the path as JSON, the command as JSON. jq's escapes keep a heredoc on ONE line. A record with
# no timestamp is kept, and the file age only narrows the walk: a long session's old calls are cut by the record's own time.
CUT="$(jq -nr --argjson d "$DAYS" '(now - $d * 86400) | todate')"
: > "$TMP/calls"; s=0
find "$SRC_DIR" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' -mtime "-$DAYS" 2>/dev/null > "$TMP/files"
while IFS= read -r f; do
  s=$(( s + 1 ))
  jq -Rr --arg cut "$CUT" --arg s "$s" '
    fromjson? // empty
    | select(type == "object" and .isSidechain != true and (.timestamp // $cut) >= $cut)
    | .message?.content? | select(type == "array") | .[]
    | select(type == "object" and .type == "tool_use")
    | [.name, $s, ((.input.file_path // .input.notebook_path // "") | tostring | @json), ((.input.command // "") | tostring | @json)]
    | join("\t")' "$f" 2>/dev/null >> "$TMP/calls" || :
done < "$TMP/files"
total="$(wc -l < "$TMP/calls" | tr -d ' ')"
sessions="$(cut -f2 "$TMP/calls" | sort -u | wc -l | tr -d ' ')"
log_ok "$total tool call(s) in $sessions session(s)."

while IFS= read -r row; do
  load "$row"
  [ "$KIND" != intro ] || continue
  : > "$TMP/hits"
  candidates "$TMP/calls" > "$TMP/cand"
  while IFS="$TAB" read -r tool sess pj cj; do
    if [ "$tool" = Bash ]; then a="$(printf '%s' "$cj" | jq -r .)"; pl="$cj"; p=''
    else p="$(printf '%s' "$pj" | jq -r .)"; a="$p"; pl="$pj"; fi
    subj="$(suggest_subject "$tool" "$a")"
    suggest_row_hits "$tool" "$REC" "$QUIET" "$subj" || continue
    if suggest_overlap "$tool" "$a" "$p"; then down=1; else down=0; fi
    printf '%s\t%s\t%s\n' "$sess" "$(printf '%s' "$pl" | hash16)" "$down" >> "$TMP/hits"
  done < "$TMP/cand"
  n="$(wc -l < "$TMP/hits" | tr -d ' ')"
  rs="$(cut -f1 "$TMP/hits" | sort -u | wc -l | tr -d ' ')"
  rp="$(cut -f2 "$TMP/hits" | sort -u | wc -l | tr -d ' ')"
  rd="$(awk -F'\t' '$3 == 1 { n++ } END { print n + 0 }' "$TMP/hits")"
  log_note "$ID: $n match(es) in $rs session(s), $rp payload(s), $rd stood down"
  # The twenty most repeated: a row that matches more than that has told the person what they need.
  cut -f2 "$TMP/hits" | sort | uniq -c | sort -rn | head -20 | while read -r c h; do log_note "  $h  x$c"; done
done < "$TMP/rows"

log_end; exit $?
