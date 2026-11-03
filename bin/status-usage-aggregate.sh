#!/usr/bin/env sh
# M9 · UsageAggregator (harbor#44) — durable per-day token usage, attributed.
#
#   sh status-usage-aggregate.sh [--json] [--apply] [--since YYYY-MM-DD] [--live | <config-dir>]
#   sh status-usage-aggregate.sh --sessions [--json] [--apply] …
#                               per-SESSION rows: where the cost went, not just
#                               what it was (harbor#185)
#
# Claude Code records per-message usage in the session transcript and the store is garbage-collected at 30 days, so this writes the only durable record of what the machine spent.
# Deliberately one file (docs/explanation/modularity.md): one parse of one record shape feeding one aggregation; a split would put two spellings of the transcript field layout in two files.
# Tokens are NOT turned into money, by decision: nothing in the transcript says how a request was billed (.message.usage.service_tier reads `standard` on essentially every entry), and a price table here
# would be a copy that rots (lint T2). What is delivered is `.entrypoint`, which separates interactive `cli` from programmatic (`sdk-cli` and friends): a PROXY for billing mode, not a billing field.
# Read-only unless asked: the default is a report on stdout, and --apply writes exactly one file, the ledger below.
# It never records payload text, only integers, dates, model ids and entrypoint labels (DE-16, docs/reports/rejected-approaches.md); harbor#185 adds BYTE COUNTS, and `utf8bytelength` is all it asks of a text block.
# One row per REQUEST, not per record (harbor#185): a streaming call writes several usage-bearing records under one requestId, so summing records over-counted output tokens 2.28x and cache reads 1.89x
# (25 transcripts, 2026-08-22). Keep the record with the LARGEST output_tokens per requestId (the completed one) and take its whole usage block; a per-field max would blend two views of one call.
# The historical ledger is not repaired by this: the merge never decreases a stored counter (see APPLY), so deleting affected rows is a deliberate operator act, named in the report.
# Removed notes: docs/explanation/code-cases/bin-status-usage-aggregate.md
set -eu

# stdout is the report and its data (the tables, --json), so the log is on stderr (LOG_FD=2,
# contracts/logging.md, harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init usage-aggregate
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
# die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code (default 2).
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-2}"; }

MODE=report
JSON=0
SINCE=""
DIR=""
LIVE_OK=0
SESSIONS=0
LIVE_DIR="$HOME/.claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --json)    JSON=1 ;;
    --apply)   MODE=apply ;;
    --sessions) SESSIONS=1 ;;
    --since)   shift; SINCE="${1:-}" ;;
    # INTENT, NOT ARGUMENT INDEX (harbor#52): gates that tested `${1:-}` let `--apply --live` through and refused `--live --apply`.
    --live)    LIVE_OK=1 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) die "unknown option $1: nothing was aggregated" "sh $0 --help" ;;
    *)  DIR="$1" ;;
  esac
  shift
done

case "$SINCE" in
  '') ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) die "--since wants YYYY-MM-DD, got $SINCE" "sh $0 --since 2026-01-01" ;;
esac

[ -n "$DIR" ] || { [ "$LIVE_OK" -eq 1 ] && DIR="$LIVE_DIR"; }
CFG="${DIR:-${CLAUDE_CONFIG_DIR:-$LIVE_DIR}}"

# ── --apply MAY NOT REACH THE LIVE DIR WITHOUT BEING TOLD TO (lint D2) ──
# A bare --apply on the operator's machine would write into ~/.claude. Reading is unrestricted; only the write is gated, on RESOLVED paths (a trailing slash, `//` or a symlink spells one directory differently; P11-01).
if [ "$MODE" = "apply" ] && [ "$LIVE_OK" -eq 0 ]; then
  _phys="$(CDPATH= cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"
  _live="$(CDPATH= cd -P -- "$LIVE_DIR" 2>/dev/null && pwd -P || printf '%s' "$LIVE_DIR")"
  if [ "$_phys" = "$_live" ]; then
    die "refusing to write the LIVE ledger without an explicit --live" "sh $0 --apply --live" 1
  fi
fi
# The same env seam eval-replay-corpus.sh uses, so the suite can point this at a synthetic tree and never read a real transcript; two spellings of where transcripts are would be two things to redirect.
SRC_DIR="${HARBOR_SESSION_TRANSCRIPTS:-$CFG/projects}"

command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

# The host partition key: NEVER `hostname` (it answers the literal `Mac` while scutil answers LocalHostName; the flip forked every host-sharded ledger, harbor#119). One canonical answer, floor_host_token.
LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-admission.sh"
if [ -r "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
  HOST="$(floor_host_token)"
else
  die "library-admission.sh is not readable at $LIB" "git checkout -- bin/library-admission.sh"
fi

LEDGER_DIR="$CFG/MEMORY/USAGE/$HOST"
LEDGER="$LEDGER_DIR/usage.jsonl"
# A second file, not a `kind` field in the first: the daily rows have readers and their shape is the contract.
SLEDGER="$LEDGER_DIR/sessions.jsonl"

# ── AGGREGATE ──
# One jq pass per transcript, summed in jq (a shell loop over ~20k records forks per record). The key is (date, model, entrypoint); date is `.timestamp` truncated at the `T` (ISO-8601 UTC).
# A record without usage is not a request; `<synthetic>` models are kept, labelled as they come, so totals agree with the transcript.
if [ ! -d "$SRC_DIR" ]; then
  die "no transcript store at $SRC_DIR" "HARBOR_SESSION_TRANSCRIPTS=<projects dir> sh $0"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

find "$SRC_DIR" -type f -name '*.jsonl' 2>/dev/null > "$TMP/files" || :

# One line at a time as a raw string (`-R`, `fromjson?`): jq parses JSONL as a STREAM and aborts at the first malformed line, silently dropping every later record while the tool reports a clean total
# (a fixture with junk on line 5 lost a later 1000-token record). A half-written last line is the NORMAL state of the running session. `-R -n '[inputs]'` rather than per line, because the dedup needs a whole file at once; still one jq per file.
# The key falls back to the record index (`idx-N`), never a shared constant: a literal would collapse requestId-less records into one row and under-count.
: > "$TMP/rows"
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  jq -R -n -c --arg since "$SINCE" '
      [ inputs | (fromjson? // empty) | select(type == "object")
                | select(.message.usage != null) ]
    | to_entries
    | map(.value + { _k: (.value.requestId // .value.message.id // "idx-\(.key)") })
    | group_by(._k)
    | map(max_by(.message.usage.output_tokens // 0))
    | .[]
    | (.timestamp // "") as $ts
    | ($ts | split("T")[0]) as $day
    | select($day != "")
    | select($since == "" or $day >= $since)
    | { day: $day,
        model: (.message.model // "unknown"),
        entry: (.entrypoint // "unknown"),
        msgs: 1,
        inp:  (.message.usage.input_tokens // 0),
        out:  (.message.usage.output_tokens // 0),
        cc:   (.message.usage.cache_creation_input_tokens // 0),
        cr:   (.message.usage.cache_read_input_tokens // 0) }
  ' "$_f" 2>/dev/null >> "$TMP/rows" || :
done < "$TMP/files"

# Fold into one row per key.
jq -s '
    group_by([.day, .model, .entry])
  | map({ day: .[0].day, model: .[0].model, entry: .[0].entry,
          msgs: (map(.msgs) | add),
          inp:  (map(.inp)  | add),
          out:  (map(.out)  | add),
          cc:   (map(.cc)   | add),
          cr:   (map(.cr)   | add) })
  | sort_by([.day, .model, .entry])
' "$TMP/rows" > "$TMP/agg.json"

# ── PER-SESSION ROWS (harbor#185) ──
# Daily rows record what was spent, not WHERE; cost is dominated by cache reads (context size x call count), both per-session properties. Every field is an integer or a tool name (BYTES, NOT TEXT); the categories
# are the ones harbor#184 measured by hand (tool results 34%, tool inputs 27%, assistant text 29%, user 10%), and `thinking` is its own category. Per-tool result bytes need the tool_use_id -> name join, because a tool_result names only its id.
# Gaps between consecutive calls settle the 5-minute versus 1-hour cache TTL question. Runs only under --sessions: it is a second pass over every file.
if [ "$SESSIONS" = 1 ]; then
  : > "$TMP/srows"
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    jq -R -n -c --arg since "$SINCE" --arg file "$_f" '
        def ts: (. // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch null);
        def blocks: (.message.content // []) | if type == "array" then .[] else empty end;
        [ inputs | (fromjson? // empty) | select(type == "object") ] as $R
      | if ($R | length) == 0 then empty else
        ( [ $R[] | select(.message.usage != null) ] ) as $U
      | ( $U | to_entries
             | map(.value + { _k: (.value.requestId // .value.message.id // "idx-\(.key)") })
             | group_by(._k)
             | map(max_by(.message.usage.output_tokens // 0)) ) as $C
      | ( [ $C[] | (.timestamp | ts) ] | map(select(. != null)) | sort ) as $T
      | ( [ $R[] | select(.type == "assistant") | blocks
            | select(type == "object" and .type == "tool_use") ] ) as $TU
      | ( $TU | map({ key: (.id // ""), value: (.name // "unknown") }) | from_entries ) as $NAME
      | ( [ $R[] | select(.type == "user") | blocks
            | select(type == "object" and .type == "tool_result")
            | { name: ($NAME[.tool_use_id // ""] // "unknown"),
                b: (.content | tostring | utf8bytelength) } ] ) as $TR
      | ( [ $C[] | (.message.usage.input_tokens // 0)
                 + (.message.usage.cache_creation_input_tokens // 0)
                 + (.message.usage.cache_read_input_tokens // 0) ] ) as $P
      | ( [ range(1; ($T | length)) as $i | ($T[$i] - $T[$i - 1]) ] ) as $G
        # `.timestamp // empty`, NOT `// ""`: an empty string splits to an EMPTY ARRAY, so [0] is null and `select(. != "")` lets null through, which sorted first and made day_first read empty on every row.
      | ( [ $R[] | (.timestamp // empty) | split("T")[0] ]
          | map(select(. != null and . != "")) | sort ) as $D
      | { session: ($R[0].sessionId // ($file | split("/") | last | sub("\\.jsonl$"; ""))),
          # THE FIRST NON-NULL, NOT RECORD ZERO: a transcript opens with harness bookkeeping (leafUuid, mode, permission-mode) that carries no cwd, so reading the first record reported every session as unknown.
          project: ([ $R[] | .cwd // empty ] | first // "unknown"),
          day_first: ($D | first // ""),
          day_last:  ($D | last  // ""),
          calls:   ($C | length),
          records: ($U | length),
          wall_s: (if ($T | length) > 1 then (($T | last) - ($T | first)) else 0 end),
          inp: ([ $C[] | (.message.usage.input_tokens // 0) ] | add // 0),
          out: ([ $C[] | (.message.usage.output_tokens // 0) ] | add // 0),
          cc:  ([ $C[] | (.message.usage.cache_creation_input_tokens // 0) ] | add // 0),
          cr:  ([ $C[] | (.message.usage.cache_read_input_tokens // 0) ] | add // 0),
          prefix_mean: (if ($P | length) > 0 then (($P | add) / ($P | length) | floor) else 0 end),
          prefix_max:  ($P | max // 0),
          b_tool_result: ([ $TR[] | .b ] | add // 0),
          b_tool_input:  ([ $TU[] | (.input | tostring | utf8bytelength) ] | add // 0),
          b_assistant:   ([ $R[] | select(.type == "assistant") | blocks
                            | select(type == "object" and .type == "text")
                            | (.text // "" | utf8bytelength) ] | add // 0),
          # Measured at ZERO and that is not a bug: thinking blocks are stored with a signature and an EMPTY thinking string (548 blocks, 0 bytes on the newest transcript, 2026-08-22), so reasoning cost is invisible to
          # transcript-based accounting. The count ships beside the bytes so a zero cannot be read two ways.
          b_thinking:    ([ $R[] | select(.type == "assistant") | blocks
                            | select(type == "object" and .type == "thinking")
                            | ((.thinking // "") | utf8bytelength) ] | add // 0),
          thinking_blocks: ([ $R[] | select(.type == "assistant") | blocks
                              | select(type == "object" and .type == "thinking") ] | length),
          b_user:        ([ $R[] | select(.type == "user") | (.message.content // "")
                            | if type == "string" then utf8bytelength
                              else ([ .[]? | select(type == "object" and .type == "text")
                                      | (.text // "" | utf8bytelength) ] | add // 0) end ] | add // 0),
          tools: ($TR | group_by(.name)
                      | map({ name: .[0].name, calls: length, bytes: ([ .[] | .b ] | add) })
                      | sort_by(- .bytes) | .[0:5]),
          # ── THE DENOMINATOR harbor#184 LEVER 1 IS TESTED AGAINST ──
          # Calls per session and tool-calls per assistant message ship as COUNTS, not a ratio (a stored mean cannot be re-aggregated across sessions). Every call re-reads the whole prefix, so four independent commands in ONE message remove three context reads.
          # No separate message count: `calls` (the deduped requestId count) already IS it; counting raw records once reported 0.52 calls per message for a session whose real figure is 0.97.
          tool_uses: ($TU | length),
          # ── CARRIED RAW, BECAUSE A SESSION IS NOT A FILE ──
          # A session that spawns subagents writes <session>/subagents/agent-*.jsonl carrying the PARENT sessionId, so one row per FILE is several rows under one key and the ledger merge cross-contaminated counters (PR #263 review).
          # Timestamps and prefix sizes therefore travel as ARRAYS and are folded after the group-by: gaps and wall time belong to the whole call sequence, and per-file bucketing would invent gaps.
          ts: $T, pfx: $P,
          files: 1,
          # Which side of the delegation a file is, kept because harbor#184 lever 3 is this ratio (39 Agent calls returned 0.04 MB to a parent while one workflow burned 2.06M subagent tokens).
          agent: (if ($file | test("/subagents/")) then 1 else 0 end),
          gaps_raw: $G }
      | select(.calls > 0)
      end
    ' "$_f" 2>/dev/null >> "$TMP/srows" || :
  done < "$TMP/files"
  # ── ONE ROW PER SESSION ──
  # The fold that makes the key true: counters sum; timestamp and prefix arrays concatenate and are re-derived; `project` takes the first non-empty; the day range widens; tool rows merge by name.
  jq -s --arg since "$SINCE" '
      def bucket($g; $lo; $hi): [ $g[] | select(. >= $lo and . < $hi) ] | length;
      group_by(.session)
    | map(
        (map(.ts) | add | sort) as $T
      | (map(.pfx) | add) as $P
      | ([ range(1; ($T | length)) as $i | ($T[$i] - $T[$i - 1]) ]) as $G
      | { session: .[0].session,
          project: ([ .[] | select(.project != "unknown") | .project ] | first // "unknown"),
          day_first: ([ .[] | .day_first ] | map(select(. != "")) | sort | first // ""),
          day_last:  ([ .[] | .day_last  ] | map(select(. != "")) | sort | last  // ""),
          files:   (map(.files)   | add),
          agents:  (map(.agent)   | add),
          calls:   (map(.calls)   | add),
          records: (map(.records) | add),
          agent_calls: ([ .[] | select(.agent == 1) | .calls ] | add // 0),
          agent_cr:    ([ .[] | select(.agent == 1) | .cr    ] | add // 0),
          wall_s: (if ($T | length) > 1 then (($T | last) - ($T | first)) else 0 end),
          inp: (map(.inp) | add), out: (map(.out) | add),
          cc:  (map(.cc)  | add), cr:  (map(.cr)  | add),
          prefix_mean: (if ($P | length) > 0 then (($P | add) / ($P | length) | floor) else 0 end),
          prefix_max:  ($P | max // 0),
          b_tool_result: (map(.b_tool_result) | add),
          b_tool_input:  (map(.b_tool_input)  | add),
          b_assistant:   (map(.b_assistant)   | add),
          b_thinking:    (map(.b_thinking)    | add),
          thinking_blocks: (map(.thinking_blocks) | add),
          b_user:        (map(.b_user)        | add),
          tool_uses: (map(.tool_uses) | add),
          tools: ([ .[] | .tools[] ] | group_by(.name)
                  | map({ name: .[0].name, calls: (map(.calls) | add), bytes: (map(.bytes) | add) })
                  | sort_by(- .bytes) | .[0:5]),
          gaps: { lt1m:  bucket($G; -1;   60),
                  m1_5:  bucket($G; 60;   300),
                  m5_60: bucket($G; 300;  3600),
                  gt60m: ([ $G[] | select(. >= 3600) ] | length) } })
    | map(select($since == "" or .day_last >= $since))
    | sort_by(- .cr)
  ' "$TMP/srows" > "$TMP/sagg.json" 2>/dev/null \
    || printf '[]\n' > "$TMP/sagg.json"
fi

# ── APPLY: merge into the durable ledger ──
# Idempotent by key and MONOTONIC per field: a transcript grows while its session runs (appending would multiply the truth), and the source window SHRINKS as the store is GC'd at 30 days, so a plain replace overwrote full totals with partial ones (PR #120 review).
# Each numeric field takes the maximum of stored and fresh (fields move independently). Cost: a genuine correction DOWNWARD cannot go through --apply; deleting a row by hand is the deliberate act. Days the run did not cover are untouched, which makes --since safe.
# So the requestId dedup (harbor#185) is NOT retroactive: stored rows for days already aggregated stay ~2x high until an operator deletes them, and the report says so.
if [ "$MODE" = "apply" ] && [ "$SESSIONS" = 1 ]; then
  # ── THE SESSION LEDGER ──
  # Same discipline keyed on the session id. The non-numeric fields (project, days, the tool list) take the FRESH value: they describe the session rather than accumulate over it.
  mkdir -p "$LEDGER_DIR"
  [ -f "$SLEDGER" ] || : > "$SLEDGER"
  jq -s '.' "$SLEDGER" > "$TMP/sold.json" 2>/dev/null || printf '[]\n' > "$TMP/sold.json"
  [ -s "$TMP/sold.json" ] || printf '[]\n' > "$TMP/sold.json"
  jq -s -c '
      def maxrow($a; $b):
        $b + { calls:   ([$a.calls,   $b.calls]   | max),
               records: ([$a.records, $b.records] | max),
               wall_s:  ([$a.wall_s,  $b.wall_s]  | max),
               inp: ([$a.inp, $b.inp] | max), out: ([$a.out, $b.out] | max),
               cc:  ([$a.cc,  $b.cc]  | max), cr:  ([$a.cr,  $b.cr]  | max),
               prefix_max: ([$a.prefix_max, $b.prefix_max] | max),
               b_tool_result: ([$a.b_tool_result, $b.b_tool_result] | max),
               b_tool_input:  ([$a.b_tool_input,  $b.b_tool_input]  | max),
               b_assistant:   ([$a.b_assistant,   $b.b_assistant]   | max),
               b_thinking:    ([$a.b_thinking,    $b.b_thinking]    | max),
               b_user:        ([$a.b_user,        $b.b_user]        | max),
               tool_uses: ([($a.tool_uses // 0), ($b.tool_uses // 0)] | max) };
      (.[0] // []) as $old | (.[1] // []) as $new
    | (reduce $old[] as $o ({}; .[$o.session] = $o)) as $bykey
    | ($new | map(.session)) as $keys
    | ($old | map(select((.session | IN($keys[])) | not)))
      + ($new | map(. as $n | ($bykey[$n.session]) as $o
                    | if $o == null then $n else maxrow($o; $n) end))
    | sort_by(.session) | .[]
  ' "$TMP/sold.json" "$TMP/sagg.json" > "$TMP/sledger.new" 2>/dev/null || {
      die "could not merge the session ledger at $SLEDGER" "jq -s . $SLEDGER >/dev/null # a corrupt row is the usual cause"; }
  mv "$TMP/sledger.new" "$SLEDGER"
elif [ "$MODE" = "apply" ]; then
  mkdir -p "$LEDGER_DIR"
  [ -f "$LEDGER" ] || : > "$LEDGER"
  # A temp file, not `<(...)`: process substitution is a bashism and the security floor is pure POSIX sh, checked under dash in CI.
  jq -s '.' "$LEDGER" > "$TMP/old.json" 2>/dev/null || printf '[]\n' > "$TMP/old.json"
  [ -s "$TMP/old.json" ] || printf '[]\n' > "$TMP/old.json"
  jq -s -c '
      def key: [.day, .model, .entry];
      def maxrow($a; $b):
        { day: $b.day, model: $b.model, entry: $b.entry,
          msgs: ([$a.msgs, $b.msgs] | max),
          inp:  ([$a.inp,  $b.inp]  | max),
          out:  ([$a.out,  $b.out]  | max),
          cc:   ([$a.cc,   $b.cc]   | max),
          cr:   ([$a.cr,   $b.cr]   | max) };
      (.[0] // []) as $old | (.[1] // []) as $new
    | (reduce $old[] as $o ({}; .[$o | key | tostring] = $o)) as $bykey
    | ($new | map([.day, .model, .entry])) as $keys
    | ($old | map(select((key | IN($keys[])) | not)))
      + ($new | map(. as $n | ($bykey[$n | key | tostring]) as $o
                    | if $o == null then $n else maxrow($o; $n) end))
    | sort_by([.day, .model, .entry]) | .[]
  ' "$TMP/old.json" "$TMP/agg.json" \
    > "$TMP/ledger.new" 2>/dev/null || {
      die "could not merge the ledger at $LEDGER" "jq -s . $LEDGER >/dev/null # a corrupt row is the usual cause"; }
  mv "$TMP/ledger.new" "$LEDGER"
fi

# What the run did, on the log; the report below is on stdout.
log_head "$([ "$SESSIONS" = 1 ] && echo sessions || echo daily)"
log_ok "aggregated $(wc -l < "$TMP/files" | tr -d ' ') transcript file(s) from $SRC_DIR"
if [ "$MODE" = "apply" ]; then log_ok "ledger updated: $([ "$SESSIONS" = 1 ] && echo "$SLEDGER" || echo "$LEDGER")"
else log_note "ledger not written; pass --apply"; fi

if [ "$SESSIONS" = 1 ]; then
  if [ "$JSON" = "1" ]; then
    jq -n --slurpfile rows "$TMP/sagg.json" \
          --arg host "$HOST" --arg src "$SRC_DIR" --arg ledger "$SLEDGER" \
          --arg applied "$([ "$MODE" = apply ] && echo true || echo false)" '
      ($rows[0] // []) as $r
      | { host: $host, source: $src, ledger: $ledger, applied: ($applied == "true"),
          sessions: $r,
          totals: { sessions: ($r | length),
                    calls:      ($r | map(.calls) | add // 0),
                    records:    ($r | map(.records) | add // 0),
                    cache_read: ($r | map(.cr) | add // 0),
                    output:     ($r | map(.out) | add // 0),
                    bytes: { tool_result: ($r | map(.b_tool_result) | add // 0),
                             tool_input:  ($r | map(.b_tool_input)  | add // 0),
                             assistant:   ($r | map(.b_assistant)   | add // 0),
                             thinking:    ($r | map(.b_thinking)    | add // 0),
                             user:        ($r | map(.b_user)        | add // 0) },
                    gaps: { lt1m:  ($r | map(.gaps.lt1m)  | add // 0),
                            m1_5:  ($r | map(.gaps.m1_5)  | add // 0),
                            m5_60: ($r | map(.gaps.m5_60) | add // 0),
                            gt60m: ($r | map(.gaps.gt60m) | add // 0) } } }'
    log_end; exit $?
  fi
  printf 'usage-aggregate --sessions — host %s\n' "$HOST"
  printf 'source: %s\n' "$SRC_DIR"
  [ "$MODE" = "apply" ] && printf 'ledger: %s (updated)\n' "$SLEDGER" \
                        || printf 'ledger: %s (not written; pass --apply)\n' "$SLEDGER"
  printf '\n%-12s  %-22s  %6s  %10s  %10s  %9s  %s\n' \
    DAY SESSION CALLS CACHE-RD PREFIX-MAX WALL PROJECT
  jq -r '.[] | [ .day_last, (.session[0:8]), .calls, .cr, .prefix_max, .wall_s,
                 (.project | split("/") | last) ] | @tsv' "$TMP/sagg.json" \
    | awk -F'\t' '{ printf "%-12s  %-22s  %6s  %10s  %10s  %8ss  %s\n", $1,$2,$3,$4,$5,$6,$7 }'

  # The two numbers harbor#184 is about: context re-read per call is the cost driver, and the byte split says which part to attack first.
  printf '\n'
  # LEVER 1's measure, derived at print time rather than stored: turn count multiplies context size.
  jq -r '
      (map(.tool_uses // 0) | add) as $t | (map(.calls) | add // 0) as $m
    | if $m == 0 then "batching: no assistant messages measured"
      else "batching: \($t) tool use(s) over \($m) assistant message(s) — " +
           "\((($t * 100 / $m) | floor) / 100) per message. Above 1.0 means calls " +
           "are being batched; each extra message is one more full re-read of the " +
           "same prefix"
      end' "$TMP/sagg.json"
  jq -r '
      (map(.cr) | add // 0) as $cr | (map(.calls) | add // 0) as $n
    | "cache read: \($cr) over \($n) call(s)" +
      (if $n > 0 then " — \(($cr / $n) | floor) tokens re-read per call" else "" end)
  ' "$TMP/sagg.json"
  jq -r '
      (map(.thinking_blocks) | add // 0) as $tb
    | { tool_result: (map(.b_tool_result) | add // 0),
        tool_input:  (map(.b_tool_input)  | add // 0),
        assistant:   (map(.b_assistant)   | add // 0),
        thinking:    (map(.b_thinking)    | add // 0),
        user:        (map(.b_user)        | add // 0) }
    | (to_entries | map(.value) | add) as $t
    | "context bytes: " +
      (if $t == 0 then "none measured"
       else (to_entries | sort_by(- .value)
             | map("\(.key) \((.value * 100 / $t) | floor)%") | join(" · "))
       end)
      + (if $tb > 0 and .thinking == 0
         then "  (thinking: \($tb) block(s) carrying 0 bytes — the harness stores a signature and an empty string, so reasoning cost is not measurable from a transcript)"
         else "" end)
  ' "$TMP/sagg.json"
  # The top offender by RESULT bytes (needs the tool_use_id -> name join); harbor#184 named `Read`.
  jq -r '
      [ .[] | .tools[]? ] | group_by(.name)
    | map({ name: .[0].name, calls: (map(.calls) | add), bytes: (map(.bytes) | add) })
    | sort_by(- .bytes) | .[0:5]
    | if length == 0 then "tool results: none measured"
      else "tool results, biggest first: " +
           (map("\(.name) \((.bytes / 1024) | floor)KB over \(.calls) call(s)") | join(" · "))
      end' "$TMP/sagg.json"
  jq -r '
      { lt1m: (map(.gaps.lt1m) | add // 0), m1_5: (map(.gaps.m1_5) | add // 0),
        m5_60: (map(.gaps.m5_60) | add // 0), gt60m: (map(.gaps.gt60m) | add // 0) }
    | (.lt1m + .m1_5 + .m5_60 + .gt60m) as $g
    | if $g == 0 then "inter-call gaps: none measured (a session needs 2+ calls)"
      else "inter-call gaps: <1m \(.lt1m) · 1-5m \(.m1_5) · 5-60m \(.m5_60) · >60m \(.gt60m)" +
           " — \((( .m5_60 + .gt60m) * 100 / $g) | floor)% of calls land past a 5-minute cache TTL"
      end' "$TMP/sagg.json"
  # The dedup, stated: `records` above `calls` is the over-count the daily ledger carried, so a reader knows an old stored row is too high.
  jq -r '
      (map(.calls) | add // 0) as $c | (map(.records) | add // 0) as $r
    | if $c == 0 or $r == $c then empty
      else "\nrequestId dedup: \($r) usage-bearing record(s) for \($c) actual call(s)" +
           " — summing records over-counts by \((($r * 100 / $c) - 100) | floor)%." +
           " Rows already stored in \(env.HOME)/… /usage.jsonl were written that way" +
           " and --apply never lowers a stored counter, so they stay high until deleted."
      end' "$TMP/sagg.json"
  log_end; exit $?
fi

if [ "$JSON" = "1" ]; then
  jq -n --slurpfile rows "$TMP/agg.json" \
        --arg host "$HOST" --arg src "$SRC_DIR" --arg ledger "$LEDGER" \
        --arg applied "$([ "$MODE" = apply ] && echo true || echo false)" '
    { host: $host, source: $src, ledger: $ledger,
      applied: ($applied == "true"),
      rows: ($rows[0] // []),
      totals: (($rows[0] // []) | { msgs: (map(.msgs)|add // 0),
                                    input: (map(.inp)|add // 0),
                                    output: (map(.out)|add // 0),
                                    cache_creation: (map(.cc)|add // 0),
                                    cache_read: (map(.cr)|add // 0) }) }'
  log_end; exit $?
fi

printf 'usage-aggregate — host %s\n' "$HOST"
printf 'source: %s\n' "$SRC_DIR"
[ "$MODE" = "apply" ] && printf 'ledger: %s (updated)\n' "$LEDGER" \
                      || printf 'ledger: %s (not written; pass --apply)\n' "$LEDGER"
printf '\n%-10s  %-18s  %-8s  %7s  %10s  %10s  %10s  %10s\n' \
  DAY MODEL ENTRY MSGS INPUT OUTPUT CACHE-CR CACHE-RD
jq -r '.[] | [.day, .model, .entry, .msgs, .inp, .out, .cc, .cr] | @tsv' "$TMP/agg.json" \
  | awk -F'\t' '{ printf "%-10s  %-18s  %-8s  %7s  %10s  %10s  %10s  %10s\n", $1,$2,$3,$4,$5,$6,$7,$8 }'

# The entrypoint split is why this tool attributes at all: non-`cli` usage is the class the CostTracker origin invoice was about, stated as a proxy (no billing field exists).
printf '\n'
jq -r '
    (map(select(.entry != "cli")) | length) as $n
  | if $n == 0 then "entrypoints: cli only."
    else "entrypoints: \($n) non-cli row(s) — " +
         ((map(select(.entry != "cli")) | map(.entry) | unique | join(", "))) +
         ". A programmatic entrypoint is the PROXY for billing outside the " +
         "subscription; the transcript carries no billing field."
    end' "$TMP/agg.json"
log_end; exit $?
