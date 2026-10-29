#!/usr/bin/env sh
# M9 · UsageAggregator (harbor#44) — durable per-day token usage, attributed.
#
#   sh usage-aggregate.sh [--json] [--apply] [--since YYYY-MM-DD] [--live | <config-dir>]
#   sh usage-aggregate.sh --sessions [--json] [--apply] …
#                               per-SESSION rows: where the cost went, not just
#                               what it was (harbor#185)
#
# WHAT IT IS FOR. Claude Code records per-message token usage in the session
# transcript, and the transcript store is garbage-collected at 30 days. So the
# only durable record of what this machine spent is the one somebody writes
# before the transcript disappears. This writes it.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md): one parse of one record shape
# feeding one aggregation. Splitting the reader from the writer would put two
# spellings of the transcript's field layout in two files, and the field layout
# is the part that changes when the harness changes.
#
# ── THE HALF THAT IS NOT HERE, AND WHY (read this before adding it) ──────────
#
# The ticket pairs `UsageAggregator` with `CostTracker`, whose stated origin is
# an invoice "dominated by upstream-local processes that billed API instead of
# subscription". Turning tokens into money is NOT implemented, and it is absent
# by decision rather than oversight:
#
#   1. NOTHING IN THE TRANSCRIPT SAYS HOW A REQUEST WAS BILLED. The only
#      tier-shaped field is `.message.usage.service_tier`, and on this machine it
#      reads `standard` for essentially every usage-bearing entry sampled on
#      2026-08-05 — it discriminates nothing. A tool that mapped it to a billing
#      mode would be inventing the mapping.
#   2. A PRICE TABLE IN THIS REPO WOULD BE A COPY THAT ROTS. Per-model prices
#      live at the vendor and change without notice; committing them here is
#      exactly the restated-fact class lint T2 exists to catch, and a stale price
#      silently produces a wrong number that reads as authoritative.
#
# What IS delivered is the honest discriminator the origin invoice actually
# needed: `.entrypoint`, which separates an interactive `cli` session from a
# programmatic one (`sdk-cli` and friends). That is the axis "a local process
# billed differently from my subscription" falls along, so usage is attributed
# by it. Read it as a PROXY and not as a billing field, because that is what it
# is — the transcript carries no billing field at all.
#
# ── READ-ONLY UNLESS ASKED ───────────────────────────────────────────────────
# Default is a report on stdout and no write anywhere. `--apply` is the only
# mode that touches disk, and it writes exactly one file: the ledger below.
#
# IT NEVER RECORDS PAYLOAD TEXT. Every value it keeps is an integer, a date, a
# model id or an entrypoint label. DEAD-ENDS.md DE-16 refused a durable corpus
# built out of transcript CONTENT, and that refusal is why this reads usage
# counters and nothing else: the class is unreachable rather than mitigated,
# so there is no scrubber here and none is needed. harbor#185 adds BYTE COUNTS
# over that content, which is the same discipline one step further: a length is
# not a payload, and `utf8bytelength` is the only thing this file ever asks of a
# text block.
#
# ── ONE ROW PER REQUEST, NOT PER RECORD (harbor#185) ─────────────────────────
# A streaming API call writes SEVERAL usage-bearing records to the transcript
# under one `requestId`, and every one of them carries a usage block. Summing
# records rather than requests therefore counts the same call repeatedly.
# Measured over the 25 most recent transcripts on 2026-08-22:
#
#   usage-bearing records          11,594
#   distinct requestIds             6,049   (3,887 of them appear 2-5 times)
#   output tokens, summed naively   12,207,585
#   output tokens, one per request   5,351,231     -> 2.28x over-count
#   cache reads, summed naively      3,461,269,590
#   cache reads, one per request     1,830,273,639 -> 1.89x over-count
#
# So the durable ledger — the ONLY surviving record of what this machine spent,
# because the transcripts are garbage-collected at 30 days — read roughly double
# for every day it has ever covered. The rule is the ticket's: keep the record
# with the LARGEST output_tokens per requestId, which is the completed one, and
# take its whole usage block rather than a per-field maximum across records. A
# per-field max would blend two views of one call, and a blend is a number with
# no request behind it.
#
# THE HISTORICAL LEDGER IS NOT REPAIRED BY THIS, and it cannot be: the merge
# below never decreases a stored counter (see APPLY), so re-running writes the
# corrected, smaller numbers nowhere. Deleting the affected rows is a deliberate
# operator act and is named in the report rather than done here.
set -eu

# stdout is the report and its data (the tables, --json), so the log is on stderr (LOG_FD=2,
# CONTRACTS/logging.md, harbor#771).
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
log_init usage-aggregate; LOG_FD=2
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
    # INTENT, NOT ARGUMENT INDEX (harbor#52). The four gates that came before this
    # one all tested `${1:-}` while their own loops accepted --live anywhere, so
    # `--apply --live` passed the gate and `--live --apply` did not.
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

# ── --apply MAY NOT REACH THE LIVE DIR WITHOUT BEING TOLD TO (lint D2) ───────
# The default target is the active config dir, which on the operator's machine IS
# the live one — so a bare `--apply` would write a ledger into ~/.claude because
# nobody named another directory, which is the accident this gate exists for.
# Reading is unrestricted; only the write is gated.
#
# RESOLVED PATHS, NOT STRINGS. A trailing slash, a `//`, or a symlinked route
# spells the same directory differently, and pass 11 used exactly that to strip
# every hook from a live config whose --live gate was a string compare (P11-01).
if [ "$MODE" = "apply" ] && [ "$LIVE_OK" -eq 0 ]; then
  _phys="$(CDPATH= cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"
  _live="$(CDPATH= cd -P -- "$LIVE_DIR" 2>/dev/null && pwd -P || printf '%s' "$LIVE_DIR")"
  if [ "$_phys" = "$_live" ]; then
    # --apply creates a durable record under the config dir.
    die "refusing to write the LIVE ledger without an explicit --live" "sh $0 --apply --live" 1
  fi
fi
# The same env seam replay-corpus.sh uses (bin/replay-corpus.sh:52), so the suite
# can point this at a synthetic tree and never read a real transcript. Sharing the
# name matters: two spellings of "where the transcripts are" is two things to
# redirect, and a suite that redirects one of them reads the operator's store.
SRC_DIR="${HARBOR_TRANSCRIPTS:-$CFG/projects}"

command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

# The host partition key. NEVER `hostname` — on this machine `hostname` answers
# the literal `Mac` while scutil answers the configured LocalHostName, and the
# flip silently FORKED every host-sharded ledger in ~/.claude (harbor#119). One
# canonical answer, from guard-lib, or the fork happens again here.
LIB="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/guard-lib.sh"
if [ -r "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
  HOST="$(floor_host_token)"
else
  die "guard-lib.sh is not readable at $LIB" "git checkout -- bin/guard-lib.sh"
fi

LEDGER_DIR="$CFG/MEMORY/USAGE/$HOST"
LEDGER="$LEDGER_DIR/usage.jsonl"
# A SECOND FILE, NOT A `kind` FIELD IN THE FIRST. The daily rows have readers
# already and their shape is the contract; a per-session row shares no key with
# them, so mixing the two would make every reader filter before it could sum.
SLEDGER="$LEDGER_DIR/sessions.jsonl"

# ── AGGREGATE ────────────────────────────────────────────────────────────────
# One jq pass per transcript, summed in jq rather than in the shell: a shell loop
# over ~20k records forks per record and takes minutes, and the numbers are the
# whole product here.
#
# The key is (date, model, entrypoint). Date comes from `.timestamp`, truncated
# at the `T` — the field is ISO-8601 UTC, so no date arithmetic is needed and
# none is done. A record without a usage block is not a request and is skipped;
# `<synthetic>` models are harness-generated and are kept, labelled as they come,
# because dropping them would make the totals disagree with the transcript.
if [ ! -d "$SRC_DIR" ]; then
  die "no transcript store at $SRC_DIR" "HARBOR_TRANSCRIPTS=<projects dir> sh $0"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

find "$SRC_DIR" -type f -name '*.jsonl' 2>/dev/null > "$TMP/files" || :

# ONE LINE AT A TIME, AS A RAW STRING, and this is the whole reason `-R` is here.
#
# The first cut fed the file to jq directly and swallowed errors with
# `2>/dev/null || :`. jq parses a JSONL file as a STREAM, so it aborts at the
# first malformed line — and every record AFTER that line was silently dropped
# while the tool reported a clean total. Measured on a fixture whose 5th line was
# junk: a 1000-token record appended after it never appeared, and the ledger read
# as correct. That is the exact "a clean result indistinguishable from nothing to
# report" shape M8's REF-6 was added for.
#
# A half-written last line is the NORMAL state of the session currently running,
# so this is the common case and not an edge case. `fromjson?` confines a parse
# failure to the line that caused it, and one jq process still covers the file —
# forking per line would fork ~20k times over the real store.
#
# `-R -n '[inputs]'` RATHER THAN `-R` PER LINE, because the dedup below needs to
# see a whole file at once: the records sharing a requestId are adjacent but the
# grouping is not expressible one line at a time. Still one jq process per file,
# and `fromjson?` still confines a parse failure to its own line.
#
# THE KEY FALLS BACK TO THE RECORD INDEX, never to a shared constant. Grouping a
# batch of requestId-less records under one literal would collapse them into a
# single row and UNDER-count — the opposite defect, introduced by the fix for the
# first one. `idx-N` is unique per record, so a record with no requestId is its
# own call, which is the conservative reading.
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

# ── PER-SESSION ROWS (harbor#185) ────────────────────────────────────────────
# WHY THE DAILY ROWS ARE NOT ENOUGH, in the ticket's words: they record what was
# spent and not WHERE, so no context-economy change can be tested. Cost here is
# dominated by cache reads, which are context size MULTIPLIED BY call count —
# both per-session properties, and neither is in a (day, model, entrypoint) row.
#
# BYTES, NOT TEXT. Every field below is an integer or a tool name. The categories
# are the ones harbor#184 measured by hand across 40 transcripts (tool results
# 34%, tool inputs 27%, assistant text 29%, user 10%) — doing that by hand is how
# the finding was made, and a finding you cannot re-measure is not a mechanism.
# `thinking` is broken out as its own category because it is neither of those and
# it is not free.
#
# PER-TOOL RESULT BYTES ARE THE POINT OF THE JOIN. A `tool_result` block names
# only its `tool_use_id`, so attributing 13.1 KB per call to `Read` requires the
# id -> name map from the assistant records. Without the join the top offender is
# invisible, which is exactly the state harbor#184 describes.
#
# GAPS SETTLE THE TTL QUESTION WITH DATA. The distance between consecutive calls
# decides whether a 5-minute or 1-hour prompt cache is the right assumption, and
# the transcripts already carry it — this only counts it.
#
# ONLY WHEN ASKED: this is a second pass over every file, so it runs under
# --sessions and not otherwise.
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
        # `.timestamp // empty`, NOT `// ""`. An empty string splits to an EMPTY
        # ARRAY in jq, so `[0]` is null, and `select(. != "")` lets null through —
        # which sorted to the front and made day_first read "" on every row while
        # day_last was correct. A filter that admits the value it exists to
        # exclude is worse than none.
      | ( [ $R[] | (.timestamp // empty) | split("T")[0] ]
          | map(select(. != null and . != "")) | sort ) as $D
      | { session: ($R[0].sessionId // ($file | split("/") | last | sub("\\.jsonl$"; ""))),
          # THE FIRST NON-NULL, NOT WHATEVER RECORD ZERO HAS. A transcript opens with
          # harness bookkeeping (`leafUuid`, `mode`, `permission-mode`) that
          # carries no cwd, so reading `$R[0].cwd` reported every session as
          # "unknown" — measured, and the reason attribution existed but did not
          # attribute.
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
          # MEASURED AT ZERO, AND THE BLOCK COUNT IS WHY THAT IS NOT A BUG. The
          # transcript stores thinking blocks with a `signature` and an EMPTY
          # `thinking` string: 548 blocks, 0 bytes, 0 non-empty, on the newest
          # transcript on 2026-08-22. So reasoning cost is structurally invisible
          # to any transcript-based context accounting on this harness — a fact
          # harbor#184 needs, since it is a whole category its byte split cannot
          # see. The field stays because it would light up if that changed, and
          # the count ships beside it so a zero cannot be read two ways.
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
          # ── THE DENOMINATOR harbor#184 LEVER 1 IS TESTED AGAINST ──────────
          # "Batch independent tool calls" has a stated test — "calls per
          # session, and mean tool-calls per assistant message" — and the second
          # half was not recorded anywhere, so the lever could be applied and
          # not measured. Both halves ship as counts rather than as a ratio:
          # a stored mean cannot be re-aggregated across sessions and a count
          # can, which is the T2 argument applied to arithmetic.
          #
          # The reason this is the right denominator: every call re-reads the
          # whole prefix, so four independent commands in ONE assistant message
          # removes three full context reads of identical content. Turn count is
          # the multiplier on context size, and `Bash` is the proof it matters
          # here — 4,055 calls at a 1 KB mean result, where the cost is entirely
          # in how many times it was called.
          # NO SEPARATE MESSAGE COUNT: `calls` already IS it. One API request is
          # one assistant message, and `calls` is the deduped requestId count, so
          # a second field would be a copy — and the first draft got it wrong in
          # exactly the way that copy invites, counting raw RECORDS (6,155) where
          # the messages were 3,369, and reporting 0.52 calls per message for a
          # session whose real figure is 0.97.
          tool_uses: ($TU | length),
          # ── CARRIED RAW, BECAUSE A SESSION IS NOT A FILE ──────────────────
          # A session that spawns subagents writes <session>/subagents/agent-*.jsonl
          # beside its own transcript, and those records carry the PARENT
          # sessionId — measured 2026-08-22: 97 records, all under
          # 79e64eec-…, the id of the session above them. So one row per FILE
          # is several rows under one key: the report showed duplicates and the
          # ledger merge then compared each duplicate against the same stored
          # row independently, cross-contaminating counters across runs.
          # Reported by review on PR #263.
          #
          # Timestamps and prefix sizes therefore travel as ARRAYS and are folded
          # after the group-by. Wall time and the inter-call gaps are properties
          # of the whole call sequence for a session, and computing them per file
          # would bucket a gap that never existed: the last call in the parent and
          # the first in a subagent are not consecutive in either file alone.
          ts: $T, pfx: $P,
          files: 1,
          # WHICH SIDE OF THE DELEGATION a file is, kept because the third lever in
          # harbor#184 is exactly this ratio: 39 Agent calls returned 0.04 MB
          # into a parent context while one workflow burned 2.06M subagent
          # tokens. Merging subagent cost into the session total is right, and
          # losing the split would erase the measurement that justifies it.
          agent: (if ($file | test("/subagents/")) then 1 else 0 end),
          gaps_raw: $G }
      | select(.calls > 0)
      end
    ' "$_f" 2>/dev/null >> "$TMP/srows" || :
  done < "$TMP/files"
  # ── ONE ROW PER SESSION ────────────────────────────────────────────────────
  # The fold that makes the key true. Counters sum; the timestamp and prefix
  # arrays concatenate and are re-derived from the merged sequence; `project`
  # takes the first non-empty; the day range widens; tool rows merge by name.
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

# ── APPLY: merge into the durable ledger ─────────────────────────────────────
# IDEMPOTENT BY KEY, AND MONOTONIC PER FIELD. A transcript is appended to while its
# session runs, so the same day gets aggregated repeatedly with a growing total;
# appending would make the ledger sum to several multiples of the truth. Days the
# current run did not cover are left untouched, which is what makes `--since` safe.
#
# A PLAIN REPLACE WAS WRONG, AND IT DEFEATED THE WHOLE POINT (PR #120 review). The
# transcript store is garbage-collected at 30 days, so the source window SHRINKS
# over time. Once one transcript for a day has been aggregated and another for the
# same `(day, model, entry)` is later GC'd, a plain `--apply` overwrote the durable
# full total with the smaller partial one — destroying exactly the history this
# ledger exists to outlive, silently, while reporting success.
#
# So a stored counter is never DECREASED: each numeric field takes the maximum of
# stored and freshly-measured. Rationale for max rather than "skip if smaller": the
# fields move independently, and a day can legitimately gain output tokens while a
# cache counter is missing from the narrower window.
#
# The cost of this choice, stated rather than hidden: a genuine correction DOWNWARD
# cannot be applied through `--apply`. That is the right trade — the only way a
# count legitimately falls is if it was over-counted, which no observed path
# produces, whereas GC shrinking the window is the normal case. Deleting a row by
# hand remains available and is a deliberate act.
#
# THE CORRECTION THIS COMMIT MAKES IS THEREFORE NOT RETROACTIVE (harbor#185). The
# requestId dedup makes every fresh number SMALLER than the double-counted one
# already stored, and "never decrease" means `--apply` will not write it. That is
# the right precedence — a rule that let a narrower window overwrite a wider one
# is the defect above — but it means the stored rows for days already aggregated
# stay ~2x high until an operator deletes them, and the report says so.
if [ "$MODE" = "apply" ] && [ "$SESSIONS" = 1 ]; then
  # ── THE SESSION LEDGER ─────────────────────────────────────────────────────
  # Same discipline, keyed on the session id, and monotonic for the same reason:
  # a live session's transcript grows under us, so re-running must not append a
  # second row and must not shrink one. The non-numeric fields (project, days,
  # the tool list) take the FRESH value, because they describe the session rather
  # than accumulate over it, and the freshest read is the most complete one.
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
  # A TEMP FILE, NOT `<(…)`. Process substitution is a bashism; this repo's
  # security floor is pure POSIX sh and CI checks the suites under dash, so a
  # `<(…)` here would run on the operator's Mac and die on a portable shell.
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

# ── OUTPUT · sessions ────────────────────────────────────────────────────────
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

  # THE TWO NUMBERS harbor#184 IS ABOUT, derived here rather than left to the
  # reader: context re-read per call is the whole cost driver, and the byte split
  # says which part of the context to attack first.
  printf '\n'
  # LEVER 1's MEASURE, derived at print time rather than stored. Every call
  # re-reads the whole prefix, so four independent commands in ONE assistant
  # message removes three full context reads of identical content — turn count is
  # the multiplier on context size, and this is the number that moves.
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
  # The top offender by RESULT bytes, which needs the tool_use_id -> name join
  # and is the number harbor#184 named `Read` on.
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
  # THE DEDUP, STATED. `records` above `calls` is the over-count the daily ledger
  # carried, and naming it is how a reader knows an old stored row is too high.
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

# ── OUTPUT ───────────────────────────────────────────────────────────────────
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

# The entrypoint split is the reason this tool attributes at all, so it is
# reported rather than left for the reader to sum. Non-`cli` usage is the class
# the CostTracker origin invoice was about — stated as a proxy, which is what it
# is, because no billing field exists to state anything stronger.
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
