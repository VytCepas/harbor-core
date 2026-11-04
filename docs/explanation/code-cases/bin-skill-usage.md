---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/skill-usage.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/skill-usage.sh, lines 9-39 (before this edit)

```text
THE NUMBER EVERY COST ARGUMENT IN THIS REPO NEEDED AND NOBODY HAD. Context cost
is size x frequency. `bin/context-budget.sh` measures size exactly and frequency
not at all, so every trim decision on this branch — which skills to keep
ambient, whether the book earns its description, whether a hook's per-fire cost
beats a prefix's one-time cost — was priced with one factor missing.

READ FROM TRANSCRIPTS, NEVER WRITTEN TO A LEDGER, and that is a rule rather than
a convenience. A PostToolUse counter was the obvious build and it is the wrong
one: it would persist a distilled second copy of something the transcripts
already record perfectly, and a distilled copy drifts while reading correctly.
The transcripts are the source; this is a query over them.

IT PRINTS COUNTS AND NAMES, NEVER CONTENT (CONSTITUTION §3). Session transcripts
hold work-log material, absolute paths and identity. Nothing here emits a line
of one — the output is a skill name, an integer and a date.

TWO CLOCKS, AND CONFLATING THEM IS THE BUG THIS AVOIDS (harbor#518). File mtime
answers "what window does the store still hold" — a property of the GC, used for
the CEILING statement below and nothing else. The `.timestamp` ON THE RECORD
answers "when did this skill last fire", which is a property of the work. #518
proposed deriving last-seen from mtime and that would have been wrong in the
lenient direction: a long session that invokes a skill in its first minute and
is touched hours later would report the skill as far fresher than it was. The
record carries the exact moment, so nothing here reads an mtime for last-seen.

WHY NOT `bytes x invocations`, WHICH IS WHAT #518 ASKED FOR. That product rises
with use, so it ranks the most-used skill as the most expensive and inverts the
decision it exists to inform. An ambient description is charged in EVERY session
whether or not anything invokes it; the invocations are the RETURN, not the cost.
So the join is charged-bytes DIVIDED BY uses — bytes paid per invocation earned,
which is the number a trim decision actually needs and the one #492 can cite.
```

## bin/skill-usage.sh, lines 69-72 (before this edit)

```text
THE FILE LIST IS BUILT BY find, NOT BY A GLOB. This estate's `grep` is a ugrep
wrapper carrying `-I --ignore-files`, which silently skips gitignored files —
and the whole session store is gitignored. A negative rested on that grep would
read as "this skill was never used" when it means "grep declined to look".
```

## bin/skill-usage.sh, lines 82-104 (before this edit)

```text
── THE WINDOW THIS TOOL CAN SEE, WHICH IS NOT FOREVER (harbor#248) ─────────
This file's footer told the reader that "only a count over a LARGE window"
separates "nothing wanted it" from "the description never triggered" — while
having no idea how large its own window was, and printing `have NEVER been
invoked` about it. Measured 2026-08-21: the store held 498 session files whose
oldest mtime was 8 days old, and `bin/status-usage-aggregate.sh`'s header already
records why — *"the transcript store is garbage-collected"*. So "never" was a
claim about a rolling window, stated as a claim about all time, by the one tool
whose whole purpose is to price a permanent decision.

It matters beyond wording: harbor#178's "2,251 sessions" cannot be reproduced
from this store today, and A6 was refused on a frequency count this tool now
reads as zero. Neither can be re-argued without knowing the window each number
came from.

DERIVED FROM THE FILES, NEVER A CONSTANT. A documented GC horizon would be a
copy of a harness behaviour nobody here controls, and copies drift while
reading perfectly (T2). The span is whatever the store actually holds.

Verbatim from lint-conventions.sh:_x8_mtime, and verbatim ON PURPOSE — `-f`
means "file system" to GNU stat and "format" to BSD, so on Linux the first call
prints filesystem fields and then fails, and an `||` chain appends the second
call's answer to that garbage. Digits or nothing.
```

## bin/skill-usage.sh, lines 111-114 (before this edit)

```text

EXPLICIT `if`, NOT `[ … ] && …`. This file runs under `set -e`, and an AND-list
whose test fails is the last command of this loop body — the shape that aborts
a strict shell on the perfectly ordinary case of "this file is not the oldest".
```

## bin/skill-usage.sh, lines 125-127 (before this edit)

```text
The span is printed in DAYS and the phrasing is deliberately "no invocation in"
rather than "never": a reader deciding whether to make a skill permanently
unreachable needs to know they are looking at days, not history.
```

## bin/skill-usage.sh, lines 134-158 (before this edit)

```text
BOTH SHAPES OF AN INVOCATION. The Skill tool records the name in
`input.skill`, and a slash command the operator typed arrives as a
`<command-name>` marker in a user turn. Counting only the first would report
every operator-invoked skill — which on this box is most of them — as unused,
and "unused" is exactly the verdict this tool exists to make safe to act on.
ONE PASS, AND IT CARRIES THE CLOCK. This was two jq invocations per file, one
per shape, both emitting a bare name. Folding them into a single filter that
also picks up the record's own timestamp is faster than the pair it replaces
(measured 2026-09-16 over 51 files: 13s against 16s) and is the entire source
of the last-seen column. Each row is `epoch<TAB>date<TAB>name`.

`fromdateiso8601` REFUSES FRACTIONAL SECONDS, which these timestamps carry
(`2026-09-14T08:13:09.399Z`). Slicing to [0:19] and re-appending `Z` is the
whole fix, and doing the parse inside jq means this file calls `date` NOWHERE —
BSD `date -r` and GNU `date -d @` disagree exactly like the `stat` split that
F11 exists to catch, and the disagreement is silent.

THE `try` IS LOAD-BEARING, NOT DEFENSIVE NOISE. jq aborts the whole document on
a raise, and this call is wrapped in `2>/dev/null || true` — so one malformed
timestamp anywhere in a transcript would discard EVERY hit in that file and
report it as a quiet zero. A skill would read as unused because one line was
unparseable, which is precisely the verdict this tool exists to make safe.
Same reason nothing is dropped for a MISSING timestamp: the hit still counts,
it simply has no date, because losing a count to protect a column would trade
the answer for the decoration.
```

## bin/skill-usage.sh, lines 181-185 (before this edit)

```text
THE NAME-ONLY PROJECTION EXISTS BECAUSE TWO CONSUMERS MATCH WHOLE LINES.
`grep -Fxq` below and the `uniq -c` table at the foot both assumed one bare
name per line; against a three-column row the first silently never matches and
the second counts date+name pairs as distinct skills. Deriving the old shape
here keeps both correct without either having to know about the new columns.
```

## bin/skill-usage.sh, lines 190-191 (before this edit)

```text
LAST SEEN, PER SKILL: the largest epoch each name ever appears with, and the
date that goes with it. One pass, no sort, no second read of the store.
```

## bin/skill-usage.sh, lines 196-200 (before this edit)

```text
THE RECENCY LINE IS DERIVED FROM THE STORE, NEVER A CONSTANT — same argument as
the window above. Half the measured span, floored at a day so a store holding a
single day cannot classify everything in it as stale. "Now" is the newest event
on record rather than the wall clock, so the verdict is reproducible: re-running
this tomorrow over an unchanged store returns the same answer it did today.
```

## bin/skill-usage.sh, lines 204-218 (before this edit)

```text
THE ANCHOR IS CLAMPED TO THE STORE'S OWN UPPER BOUND, AND THIS IS NOT THEORY —
an adversarial run on 2026-09-16 put ONE record dated 2099 in a two-file store
and every other skill in it flipped to STALE. The recency axis is measured from
the newest event on record, so a single impossible stamp moves the cutoff years
forward and takes the whole report with it, silently and in the direction that
invents work. §2.11: a false positive is a defect, and one that fires on every
row is the kind that gets the instrument switched off.

The bound is free and already computed. A record is written to a file BEFORE
that file's mtime settles, so no honest event can postdate the newest mtime in
the store. Clamping to `_newest` costs nothing when the data is sane and
contains the blast radius when it is not — clock skew, a restored backup, a
half-written line. The offending ROW still prints its own date rather than a
laundered one, because hiding the bad datum would remove the only evidence that
anything is wrong; it simply stops setting the threshold for everyone else.
```

## bin/skill-usage.sh, lines 227-230 (before this edit)

```text
Tier and description size, needed by BOTH modes now. The size is `length($0)`
of the description LINE and that is deliberate — `context-budget.sh:126` uses
the identical expression, so the two tools stay join-compatible by construction
rather than by anyone remembering to keep them in step.
```

## bin/skill-usage.sh, lines 256-261 (before this edit)

```text
THE TWO ZERO-INVOCATION STATES ARE NOT THE SAME FINDING (harbor#518). This
list reported them as one undifferentiated "unused" set, and only one half
is actionable: an AMBIENT skill that never fires pays for its description in
every session and returns nothing, while an invoked-only one that never
fires costs zero and is merely dormant. SILENT is a bill; DORMANT is an
option nobody exercised, and acting on the second buys exactly nothing.
```

## bin/skill-usage.sh, lines 266-272 (before this edit)

```text
THE BYTES, NOT JUST THE TIER (harbor#178). "AMBIENT and never invoked" is
the finding; what a trim decision needs on top of it is HOW MUCH, and
without that this report sent the reader to context-budget.sh, which knows
the ambient total and not which rows earned it. Neither tool could answer
the question on its own, and the answer is a join of the two — so the
frequency report carries the size, measured the same way context-budget
measures it (the description LINE, which is what the harness lists).
```

## bin/skill-usage.sh, lines 285-286 (before this edit)

```text
THE ONLY LINE THAT IS ACTIONABLE. Everything above it is inventory; this is
the number a ceiling decision is made against, and it did not exist before.
```

## bin/skill-usage.sh, lines 312-313 (before this edit)

```text
SAY SO WHEN THE DATA IS IMPOSSIBLE. A clamp that repaired the report silently
would leave the reader trusting a store that has a clock problem in it.
```

## bin/skill-usage.sh, lines 323-332 (before this edit)

```text
NOT EVERY NAME HERE IS AN INSTALLED SKILL. `compact`, `clear` and `resume`
are harness commands that arrive through the same `<command-name>` marker,
and they have no SKILL.md and therefore no description to charge. A dash is
the honest answer for them; a zero would read as "free", which is a claim
about a cost this tool never measured.
ASCII IN THE COLUMNS, AND THAT IS AN ALIGNMENT RULE RATHER THAN A STYLE ONE.
`printf %-12s` pads to a BYTE count, and an em-dash is three bytes in UTF-8,
so a `—` placeholder silently shortens its own column by two and skews every
row that uses it. Measured here on the first run. The prose above may keep
its dashes; the table may not.
```

## bin/skill-usage.sh, lines 340-343 (before this edit)

```text
An epoch of 0 means the hit carried no parseable timestamp. It still counts —
see the extraction above — but it cannot be placed on the recency axis, and
guessing a state for it would be the fabrication the whole column exists to
avoid. It gets a dash, and the uses column still tells the truth.
```
