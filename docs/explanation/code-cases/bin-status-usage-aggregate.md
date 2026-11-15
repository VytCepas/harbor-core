---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/status-usage-aggregate.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/status-usage-aggregate.sh, lines 9-80 (before this edit)

```text
WHAT IT IS FOR. Claude Code records per-message token usage in the session
transcript, and the transcript store is garbage-collected at 30 days. So the
only durable record of what this machine spent is the one somebody writes
before the transcript disappears. This writes it.

DELIBERATELY ONE FILE (docs/explanation/modularity.md): one parse of one record shape
feeding one aggregation. Splitting the reader from the writer would put two
spellings of the transcript's field layout in two files, and the field layout
is the part that changes when the harness changes.

── THE HALF THAT IS NOT HERE, AND WHY (read this before adding it) ──────────

The ticket pairs `UsageAggregator` with `CostTracker`, whose stated origin is
an invoice "dominated by upstream-local processes that billed API instead of
subscription". Turning tokens into money is NOT implemented, and it is absent
by decision rather than oversight:

  1. NOTHING IN THE TRANSCRIPT SAYS HOW A REQUEST WAS BILLED. The only
     tier-shaped field is `.message.usage.service_tier`, and on this machine it
     reads `standard` for essentially every usage-bearing entry sampled on
     2026-08-05 — it discriminates nothing. A tool that mapped it to a billing
     mode would be inventing the mapping.
  2. A PRICE TABLE IN THIS REPO WOULD BE A COPY THAT ROTS. Per-model prices
     live at the vendor and change without notice; committing them here is
     exactly the restated-fact class lint T2 exists to catch, and a stale price
     silently produces a wrong number that reads as authoritative.

What IS delivered is the honest discriminator the origin invoice actually
needed: `.entrypoint`, which separates an interactive `cli` session from a
programmatic one (`sdk-cli` and friends). That is the axis "a local process
billed differently from my subscription" falls along, so usage is attributed
by it. Read it as a PROXY and not as a billing field, because that is what it
is — the transcript carries no billing field at all.

── READ-ONLY UNLESS ASKED ───────────────────────────────────────────────────
Default is a report on stdout and no write anywhere. `--apply` is the only
mode that touches disk, and it writes exactly one file: the ledger below.

IT NEVER RECORDS PAYLOAD TEXT. Every value it keeps is an integer, a date, a
model id or an entrypoint label. docs/reports/rejected-approaches.md DE-16 refused a durable corpus
built out of transcript CONTENT, and that refusal is why this reads usage
counters and nothing else: the class is unreachable rather than mitigated,
so there is no scrubber here and none is needed. harbor#185 adds BYTE COUNTS
over that content, which is the same discipline one step further: a length is
not a payload, and `utf8bytelength` is the only thing this file ever asks of a
text block.

── ONE ROW PER REQUEST, NOT PER RECORD (harbor#185) ─────────────────────────
A streaming API call writes SEVERAL usage-bearing records to the transcript
under one `requestId`, and every one of them carries a usage block. Summing
records rather than requests therefore counts the same call repeatedly.
Measured over the 25 most recent transcripts on 2026-08-22:

  usage-bearing records          11,594
  distinct requestIds             6,049   (3,887 of them appear 2-5 times)
  output tokens, summed naively   12,207,585
  output tokens, one per request   5,351,231     -> 2.28x over-count
  cache reads, summed naively      3,461,269,590
  cache reads, one per request     1,830,273,639 -> 1.89x over-count

So the durable ledger — the ONLY surviving record of what this machine spent,
because the transcripts are garbage-collected at 30 days — read roughly double
for every day it has ever covered. The rule is the ticket's: keep the record
with the LARGEST output_tokens per requestId, which is the completed one, and
take its whole usage block rather than a per-field maximum across records. A
per-field max would blend two views of one call, and a blend is a number with
no request behind it.

THE HISTORICAL LEDGER IS NOT REPAIRED BY THIS, and it cannot be: the merge
below never decreases a stored counter (see APPLY), so re-running writes the
corrected, smaller numbers nowhere. Deleting the affected rows is a deliberate
operator act and is named in the report rather than done here.
```

## bin/status-usage-aggregate.sh, lines 105-107 (before this edit)

```text
INTENT, NOT ARGUMENT INDEX (harbor#52). The four gates that came before this
one all tested `${1:-}` while their own loops accepted --live anywhere, so
`--apply --live` passed the gate and `--live --apply` did not.
```

## bin/status-usage-aggregate.sh, lines 127-135 (before this edit)

```text
── --apply MAY NOT REACH THE LIVE DIR WITHOUT BEING TOLD TO (lint D2) ───────
The default target is the active config dir, which on the operator's machine IS
the live one — so a bare `--apply` would write a ledger into ~/.claude because
nobody named another directory, which is the accident this gate exists for.
Reading is unrestricted; only the write is gated.

RESOLVED PATHS, NOT STRINGS. A trailing slash, a `//`, or a symlinked route
spells the same directory differently, and pass 11 used exactly that to strip
every hook from a live config whose --live gate was a string compare (P11-01).
```

## bin/status-usage-aggregate.sh, lines 140-140 (before this edit)

```text
--apply creates a durable record under the config dir.
```

## bin/status-usage-aggregate.sh, lines 144-147 (before this edit)

```text
The same env seam eval-replay-corpus.sh uses (bin/eval-replay-corpus.sh:52), so the suite
can point this at a synthetic tree and never read a real transcript. Sharing the
name matters: two spellings of "where the transcripts are" is two things to
redirect, and a suite that redirects one of them reads the operator's store.
```

## bin/status-usage-aggregate.sh, lines 152-155 (before this edit)

```text
The host partition key. NEVER `hostname` — on this machine `hostname` answers
the literal `Mac` while scutil answers the configured LocalHostName, and the
flip silently FORKED every host-sharded ledger in ~/.claude (harbor#119). One
canonical answer, from guard-lib, or the fork happens again here.
```

## bin/status-usage-aggregate.sh, lines 167-169 (before this edit)

```text
A SECOND FILE, NOT A `kind` FIELD IN THE FIRST. The daily rows have readers
already and their shape is the contract; a per-session row shares no key with
them, so mixing the two would make every reader filter before it could sum.
```

## bin/status-usage-aggregate.sh, lines 172-181 (before this edit)

```text
── AGGREGATE ────────────────────────────────────────────────────────────────
One jq pass per transcript, summed in jq rather than in the shell: a shell loop
over ~20k records forks per record and takes minutes, and the numbers are the
whole product here.

The key is (date, model, entrypoint). Date comes from `.timestamp`, truncated
at the `T` — the field is ISO-8601 UTC, so no date arithmetic is needed and
none is done. A record without a usage block is not a request and is skipped;
`<synthetic>` models are harness-generated and are kept, labelled as they come,
because dropping them would make the totals disagree with the transcript.
```

## bin/status-usage-aggregate.sh, lines 191-215 (before this edit)

```text
ONE LINE AT A TIME, AS A RAW STRING, and this is the whole reason `-R` is here.

The first cut fed the file to jq directly and swallowed errors with
`2>/dev/null || :`. jq parses a JSONL file as a STREAM, so it aborts at the
first malformed line — and every record AFTER that line was silently dropped
while the tool reported a clean total. Measured on a fixture whose 5th line was
junk: a 1000-token record appended after it never appeared, and the ledger read
as correct. That is the exact "a clean result indistinguishable from nothing to
report" shape M8's REF-6 was added for.

A half-written last line is the NORMAL state of the session currently running,
so this is the common case and not an edge case. `fromjson?` confines a parse
failure to the line that caused it, and one jq process still covers the file —
forking per line would fork ~20k times over the real store.

`-R -n '[inputs]'` RATHER THAN `-R` PER LINE, because the dedup below needs to
see a whole file at once: the records sharing a requestId are adjacent but the
grouping is not expressible one line at a time. Still one jq process per file,
and `fromjson?` still confines a parse failure to its own line.

THE KEY FALLS BACK TO THE RECORD INDEX, never to a shared constant. Grouping a
batch of requestId-less records under one literal would collapse them into a
single row and UNDER-count — the opposite defect, introduced by the fix for the
first one. `idx-N` is unique per record, so a record with no requestId is its
own call, which is the conservative reading.
```

## bin/status-usage-aggregate.sh, lines 254-277 (before this edit)

```text
── PER-SESSION ROWS (harbor#185) ────────────────────────────────────────────
WHY THE DAILY ROWS ARE NOT ENOUGH, in the ticket's words: they record what was
spent and not WHERE, so no context-economy change can be tested. Cost here is
dominated by cache reads, which are context size MULTIPLIED BY call count —
both per-session properties, and neither is in a (day, model, entrypoint) row.

BYTES, NOT TEXT. Every field below is an integer or a tool name. The categories
are the ones harbor#184 measured by hand across 40 transcripts (tool results
34%, tool inputs 27%, assistant text 29%, user 10%) — doing that by hand is how
the finding was made, and a finding you cannot re-measure is not a mechanism.
`thinking` is broken out as its own category because it is neither of those and
it is not free.

PER-TOOL RESULT BYTES ARE THE POINT OF THE JOIN. A `tool_result` block names
only its `tool_use_id`, so attributing 13.1 KB per call to `Read` requires the
id -> name map from the assistant records. Without the join the top offender is
invisible, which is exactly the state harbor#184 describes.

GAPS SETTLE THE TTL QUESTION WITH DATA. The distance between consecutive calls
decides whether a 5-minute or 1-hour prompt cache is the right assumption, and
the transcripts already carry it — this only counts it.

ONLY WHEN ASKED: this is a second pass over every file, so it runs under
--sessions and not otherwise.
```

## bin/status-usage-aggregate.sh, lines 304-308 (before this edit)

```text
`.timestamp // empty`, NOT `// ""`. An empty string splits to an EMPTY
ARRAY in jq, so `[0]` is null, and `select(. != "")` lets null through —
which sorted to the front and made day_first read "" on every row while
day_last was correct. A filter that admits the value it exists to
exclude is worse than none.
```

## bin/status-usage-aggregate.sh, lines 312-316 (before this edit)

```text
THE FIRST NON-NULL, NOT WHATEVER RECORD ZERO HAS. A transcript opens with
harness bookkeeping (`leafUuid`, `mode`, `permission-mode`) that
carries no cwd, so reading `$R[0].cwd` reported every session as
"unknown" — measured, and the reason attribution existed but did not
attribute.
```

## bin/status-usage-aggregate.sh, lines 334-341 (before this edit)

```text
MEASURED AT ZERO, AND THE BLOCK COUNT IS WHY THAT IS NOT A BUG. The
transcript stores thinking blocks with a `signature` and an EMPTY
`thinking` string: 548 blocks, 0 bytes, 0 non-empty, on the newest
transcript on 2026-08-22. So reasoning cost is structurally invisible
to any transcript-based context accounting on this harness — a fact
harbor#184 needs, since it is a whole category its byte split cannot
see. The field stays because it would light up if that changed, and
the count ships beside it so a zero cannot be read two ways.
```

## bin/status-usage-aggregate.sh, lines 354-373 (before this edit)

```text
── THE DENOMINATOR harbor#184 LEVER 1 IS TESTED AGAINST ──────────
"Batch independent tool calls" has a stated test — "calls per
session, and mean tool-calls per assistant message" — and the second
half was not recorded anywhere, so the lever could be applied and
not measured. Both halves ship as counts rather than as a ratio:
a stored mean cannot be re-aggregated across sessions and a count
can, which is the T2 argument applied to arithmetic.

The reason this is the right denominator: every call re-reads the
whole prefix, so four independent commands in ONE assistant message
removes three full context reads of identical content. Turn count is
the multiplier on context size, and `Bash` is the proof it matters
here — 4,055 calls at a 1 KB mean result, where the cost is entirely
in how many times it was called.
NO SEPARATE MESSAGE COUNT: `calls` already IS it. One API request is
one assistant message, and `calls` is the deduped requestId count, so
a second field would be a copy — and the first draft got it wrong in
exactly the way that copy invites, counting raw RECORDS (6,155) where
the messages were 3,369, and reporting 0.52 calls per message for a
session whose real figure is 0.97.
```

## bin/status-usage-aggregate.sh, lines 375-389 (before this edit)

```text
── CARRIED RAW, BECAUSE A SESSION IS NOT A FILE ──────────────────
A session that spawns subagents writes <session>/subagents/agent-*.jsonl
beside its own transcript, and those records carry the PARENT
sessionId — measured 2026-08-22: 97 records, all under
79e64eec-…, the id of the session above them. So one row per FILE
is several rows under one key: the report showed duplicates and the
ledger merge then compared each duplicate against the same stored
row independently, cross-contaminating counters across runs.
Reported by review on PR #263.

Timestamps and prefix sizes therefore travel as ARRAYS and are folded
after the group-by. Wall time and the inter-call gaps are properties
of the whole call sequence for a session, and computing them per file
would bucket a gap that never existed: the last call in the parent and
the first in a subagent are not consecutive in either file alone.
```

## bin/status-usage-aggregate.sh, lines 392-396 (before this edit)

```text
WHICH SIDE OF THE DELEGATION a file is, kept because the third lever in
harbor#184 is exactly this ratio: 39 Agent calls returned 0.04 MB
into a parent context while one workflow burned 2.06M subagent
tokens. Merging subagent cost into the session total is right, and
losing the split would erase the measurement that justifies it.
```

## bin/status-usage-aggregate.sh, lines 403-406 (before this edit)

```text
── ONE ROW PER SESSION ────────────────────────────────────────────────────
The fold that makes the key true. Counters sum; the timestamp and prefix
arrays concatenate and are re-derived from the merged sequence; `project`
takes the first non-empty; the day range widens; tool rows merge by name.
```

## bin/status-usage-aggregate.sh, lines 449-478 (before this edit)

```text
── APPLY: merge into the durable ledger ─────────────────────────────────────
IDEMPOTENT BY KEY, AND MONOTONIC PER FIELD. A transcript is appended to while its
session runs, so the same day gets aggregated repeatedly with a growing total;
appending would make the ledger sum to several multiples of the truth. Days the
current run did not cover are left untouched, which is what makes `--since` safe.

A PLAIN REPLACE WAS WRONG, AND IT DEFEATED THE WHOLE POINT (PR #120 review). The
transcript store is garbage-collected at 30 days, so the source window SHRINKS
over time. Once one transcript for a day has been aggregated and another for the
same `(day, model, entry)` is later GC'd, a plain `--apply` overwrote the durable
full total with the smaller partial one — destroying exactly the history this
ledger exists to outlive, silently, while reporting success.

So a stored counter is never DECREASED: each numeric field takes the maximum of
stored and freshly-measured. Rationale for max rather than "skip if smaller": the
fields move independently, and a day can legitimately gain output tokens while a
cache counter is missing from the narrower window.

The cost of this choice, stated rather than hidden: a genuine correction DOWNWARD
cannot be applied through `--apply`. That is the right trade — the only way a
count legitimately falls is if it was over-counted, which no observed path
produces, whereas GC shrinking the window is the normal case. Deleting a row by
hand remains available and is a deliberate act.

THE CORRECTION THIS COMMIT MAKES IS THEREFORE NOT RETROACTIVE (harbor#185). The
requestId dedup makes every fresh number SMALLER than the double-counted one
already stored, and "never decrease" means `--apply` will not write it. That is
the right precedence — a rule that let a narrower window overwrite a wider one
is the defect above — but it means the stored rows for days already aggregated
stay ~2x high until an operator deletes them, and the report says so.
```

## bin/status-usage-aggregate.sh, lines 480-485 (before this edit)

```text
── THE SESSION LEDGER ─────────────────────────────────────────────────────
Same discipline, keyed on the session id, and monotonic for the same reason:
a live session's transcript grows under us, so re-running must not append a
second row and must not shrink one. The non-numeric fields (project, days,
the tool list) take the FRESH value, because they describe the session rather
than accumulate over it, and the freshest read is the most complete one.
```

## bin/status-usage-aggregate.sh, lines 517-519 (before this edit)

```text
A TEMP FILE, NOT `<(…)`. Process substitution is a bashism; this repo's
security floor is pure POSIX sh and CI checks the suites under dash, so a
`<(…)` here would run on the operator's Mac and die on a portable shell.
```

## bin/status-usage-aggregate.sh, lines 550-550 (before this edit)

```text
── OUTPUT · sessions ────────────────────────────────────────────────────────
```

## bin/status-usage-aggregate.sh, lines 585-587 (before this edit)

```text
THE TWO NUMBERS harbor#184 IS ABOUT, derived here rather than left to the
reader: context re-read per call is the whole cost driver, and the byte split
says which part of the context to attack first.
```

## bin/status-usage-aggregate.sh, lines 589-592 (before this edit)

```text
LEVER 1's MEASURE, derived at print time rather than stored. Every call
re-reads the whole prefix, so four independent commands in ONE assistant
message removes three full context reads of identical content — turn count is
the multiplier on context size, and this is the number that moves.
```

## bin/status-usage-aggregate.sh, lines 623-624 (before this edit)

```text
The top offender by RESULT bytes, which needs the tool_use_id -> name join
and is the number harbor#184 named `Read` on.
```

## bin/status-usage-aggregate.sh, lines 641-642 (before this edit)

```text
THE DEDUP, STATED. `records` above `calls` is the over-count the daily ledger
carried, and naming it is how a reader knows an old stored row is too high.
```

## bin/status-usage-aggregate.sh, lines 654-654 (before this edit)

```text
── OUTPUT ───────────────────────────────────────────────────────────────────
```

## bin/status-usage-aggregate.sh, lines 679-682 (before this edit)

```text
The entrypoint split is the reason this tool attributes at all, so it is
reported rather than left for the reader to sum. Non-`cli` usage is the class
the CostTracker origin invoice was about — stated as a proxy, which is what it
is, because no billing field exists to state anything stronger.
```
