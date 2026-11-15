---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/memory-store-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/memory-store-check.sh, lines 5-77 (before this edit)

```text
WHY THIS EXISTS, AND WHY IT IS NOT bin/memory-lint.sh. memory-lint is the
anti-ROT gate: dangling wikilinks, dead relative paths, slug collisions. It has
no size dimension at all, and size is the thing that costs something every
session. Measured on this box 2026-08-20, with the cwd at $HOME:

  the store               85 file(s), 457,140 B
  MEMORY.md, the index    22,234 B, 84 pointer line(s)
  ~/.claude/CLAUDE.md     14,576 B
  context-budget total    44,078 B against a 24,000 B ceiling — 183%

The INDEX alone is larger than the constitution, it is charged in FULL in every
session, and it grows by one line per memory written, forever. Nothing bounded
it. That is CX1's "nothing bounds the store behind it", and harbor#183's
always-on overage is now mostly this one file.

THE ALLOWANCE IS THE INDEX'S OWN SHAPE (harbor#316, from 2026-09-20):

  allowance = always-on pointers x 150 B + 600 B of section structure

so the bound depends on the file being measured and on nothing else. The number
is policy/constitution.md's own arithmetic — "Allowing 150 B a pointer ... plus ~600 B
of section structure" — applied to the file that sentence was about.

IT USED TO BE `ceiling - (spent - index)`, DERIVED FROM context-budget.sh, and
the reasoning for that is worth keeping because it was good and still lost. The
argument was: a second constant that must agree with HARBOR_CONTEXT_CEILING is a
copy, and copies drift while reading perfectly (T1/T2). True of a second
CEILING. Not true of 150 B, which is not a copy of anything — it is the cost of
one routing-table line, a fact about this file's shape and about no other
surface in the system.

WHAT KILLED THE OLD FORMULA WAS THE OTHER TOOL GETTING BETTER. #316 taught
context-budget.sh to count plugin agent descriptions, slash-command
descriptions and the SessionStart injection — 19,494 B that every session was
always paying and nothing had ever counted. Nothing about the memory store
changed. The allowance fell from 9,477 B to 799 B and this tool began demanding
a five-pointer index: §2.11's false positive, arrived at by measuring something
else more honestly. A bound that moves for that reason is pointed at the wrong
thing.

WHEN THE ALLOWANCE CANNOT BE DERIVED, THERE IS STILL NO VERDICT, and the
trigger has simply moved: an index with bytes and no parsed pointer means either
"not a routing table" or "the extractor stopped matching", and nothing here can
tell which. It never falls back to an invented number, because a bound nobody
chose is the arguable threshold that gets a check switched off (§2.11), and
because substituting weaker evidence under a stronger name is §2.7.

THE SUBJECT IS THE cwd-KEYED AUTO-MEMORY STORE, not $CFG/MEMORY. That is the
store the harness actually loads into every session, and it is keyed by the
working directory with `/` -> `-` and NO WALK-UP — a fact context-budget.sh
establishes behaviourally rather than from docs, and gets its own comment
there. This file resolves it the same way ON PURPOSE and the duplication is
noted rather than hidden: two tools must agree about which file loads, and the
alternative — this one asking context-budget where to look — makes the size
report depend on a tool whose failure mode is printing no rows at all.

INDEX PARITY IS A DIFFERENT SURFACE FROM memory-lint's DANGLING CHECK. That one
reads [[wikilinks]] BETWEEN notes. This one reads the index's `](file.md)`
pointers, in both directions:

  dangling  the index points at a note that is not there — a recall that will
            never resolve, paid for in every session's prefix.
  orphan    a note no index line names. It cost bytes to write and it is
            invisible at recall time, which is the worse of the two failures
            because nothing about it looks wrong.

AGE IS REPORT-ONLY, ALWAYS — memory-lint's doctrine, and the argument is
unchanged: a note written once and correct forever is the GOAL. A gate that
failed on age would teach the operator to touch files to silence a linter.
Age here comes from mtime, not git, because this store is not a git repo
(memory-lint reports 0 stale on it for exactly that reason). mtime is weaker
evidence — a copy or a restore resets it — and that is disclosed in the output
rather than papered over.
```

## bin/memory-store-check.sh, lines 80-82 (before this edit)

```text
NOGLOB, memory-lint's reason: lists below are split by setting IFS and
expanding unquoted, which governs field splitting only. A note filename holding
*, ? or [ ] would still be pathname-expanded against the working directory.
```

## bin/memory-store-check.sh, lines 135-138 (before this edit)

```text
VALIDATED, NOT LEFT TO THE ARITHMETIC. memory-lint carries the same guard
and the same reason: under dash a non-numeric operand makes $((…)) abort
the interpreter, so a typo kills the gate instead of printing a usage
error.
```

## bin/memory-store-check.sh, lines 158-193 (before this edit)

```text
── THE ALLOWANCE BASIS IS THE CWD'S, SO A --root ELSEWHERE HAS NO VERDICT ──
harbor#317. The allowance is `CEIL - (SPENT - IDX_BYTES)`, and `SPENT` is the
`SPENT EVERY SESSION` line parsed out of context-budget.sh — which is computed
for THIS cwd. The subtraction is only sound when the index being measured is
the one already inside that number. Point `--root` at another store and the
tool subtracts an index that was never in `SPENT`, inflating the allowance by
exactly that index's size.

Measured 2026-09-16 from ~/harbor, and it is the whole bug:

  store-check --root <the -Users-someone store>
      index 10479, allowance 20369 = 40000 - 19631   -> "9890 B of headroom"
  context-budget.sh, same box, same minute
      WORST CASE 40589 = 30110 + 10479               -> "OVER by 589 bytes"

  19631 = 30110 - 10479. One tool subtracts the index from the basis, the
  other adds it to the basis. Same file, same minute, opposite verdicts.

So the verdict is refused rather than repaired: re-deriving `SPENT` for an
arbitrary store means re-implementing context-budget's surface accounting, and
§2.7 forbids substituting a weaker computation under the stronger one's name.
The size facts are still printed; only the VERDICT is withheld.

THAT REFUSAL IS LIFTED AS OF harbor#316, AND ONLY BECAUSE ITS CAUSE IS GONE.
Every line above is an argument about ONE formula: `CEIL - (SPENT - IDX_BYTES)`
mixes a number computed for this cwd with an index belonging to another store,
so the subtraction was unsound off-cwd and the verdict was correctly withheld.
The allowance is now `always-on pointers x 150 + 600`, computed entirely from
the index being measured — it reads nothing about this cwd, this box's
constitution or any other surface. There is no longer a mismatch to protect
against, so `--root` gets a real verdict, and the ability to judge the OTHER
nine stores on this box is the point rather than a by-product. The text above
is kept whole because it is the record of why the refusal existed; deleting it
would leave the next reader to rediscover the unsound subtraction. The variable
it used to set is gone rather than pinned to 1: a flag that cannot be false is a
branch no test can reach, which is CONSTITUTION §2.10 in a different costume.
```

## bin/memory-store-check.sh, lines 198-200 (before this edit)

```text
NO STORE IS NOT AN ERROR. Most working directories have none, and this tool
runs from lint and from `harbor`. Exiting 2 here would make the common case
noisy, which is how a check gets dropped from the caller.
```

## bin/memory-store-check.sh, lines 217-227 (before this edit)

```text
memory-lint's walk, for the same reasons: dot-directories are history or
another scope, indexes/ is the derived tier, and -print0 is not portable.
-L, AND IT IS NOT COSMETIC (harbor#608). docs/reference/checks.md's `memory.route` row
routes a governed repo's silo to the one $HOME store BY SYMLINK, so $STORE is
a LINK and not a directory for 25 of this box's 200 silos — harbor's own and
all three trio repos among them. `find` does not follow a symlinked START
path without -L, while the index is read straight THROUGH it by path
traversal. So this walk returned nothing while the index was real, and every
pointer in it was reported as dangling. Measured 2026-09-21 with cwd ~/harbor:
`notes 0`, `store bytes 0`, 299 phantom dangles, against a store holding 301
that `ls` and `stat` both see. `find -L` returns the 301.
```

## bin/memory-store-check.sh, lines 232-236 (before this edit)

```text
THE OVERFLOW INDEX IS AN INDEX, NOT A NOTE. It lives inside the store, so the
walk finds it, and nothing points at an index — it would be reported as an
orphan on every tiered store. Caught by store-check-test 12a before this
shipped; without the exclusion, tiering makes the parity check cry wolf on the
very file that implements it.
```

## bin/memory-store-check.sh, lines 267-278 (before this edit)

```text
harbor#317. `bytes()` answers 0 for a file that is not there, and 0 is under
every allowance, so a store directory with no MEMORY.md printed the same
confident "Index within allowance — N B of headroom" as a healthy one. The
`! -d "$STORE"` guard above catches a missing DIRECTORY and was doing the work
this case needed; a directory that exists and holds no index walked straight
past it. Measured 2026-09-16 on an empty `mkdir`: "9890 B of headroom", exit 0,
and the same under --strict.

The distinction is not pedantry. "Within allowance" is a claim that something
was measured and found small; 0 bytes of nothing is the absence of a
measurement, and reporting it as a pass is the §2 failure this tool exists to
prevent in the memory store.
```

## bin/memory-store-check.sh, lines 283-294 (before this edit)

```text
`](target)` is the pointer shape policy/constitution.md's memory section specifies:
`- [Title](file.md) — hook`. Targets carrying a scheme or an anchor are not
store pointers and are skipped rather than reported — an index may legitimately
link out, and reporting those as dangling is the false positive that gets the
parity check ignored.
A TIERED INDEX IS TWO FILES AND ONE PARITY SET. The always-on index may be
PARTIAL — it is the file charged to every session, so it is the one bounded by
bytes — while the overflow index carries the rest and is never loaded, only
searched. Parity must therefore be computed over the UNION: a note pointed at
by the overflow index is not an orphan, and reporting it as one is the false
positive that would make an operator delete a live note (Helm No.2.11).
Bytes stay measured on $INDEX alone; that asymmetry IS the design.
```

## bin/memory-store-check.sh, lines 304-308 (before this edit)

```text
AN INDEX IS NOT A NOTE, in either direction. The two tiers cross-link so a
reader can walk between them, and those links target index files that the
corpus walk deliberately excludes — so without this they are reported as
dangling on every tiered store, which is the same cry-wolf as counting the
overflow index as an orphan. Basenames, because a pointer is relative.
```

## bin/memory-store-check.sh, lines 337-375 (before this edit)

```text
THIS USED TO BE `ceiling - (spent - index)`, AND THAT FORMULA HAD A FAULT THAT
ONLY SHOWED WHEN THE OTHER TOOL GOT BETTER. It bound the index to surfaces that
have nothing to do with the index: the constitution, the ambient skill
descriptions, and — once #316 taught context-budget.sh to see them — plugin
agent descriptions, slash-command descriptions and the SessionStart injection.
Measured 2026-09-20, the hour that landed: the allowance fell from 9,477 B to
799 B and this tool began demanding a five-pointer index. Nothing about the
store had changed. A gate whose verdict moves because a DIFFERENT surface was
measured more honestly is a gate pointed at the wrong thing, and a permanently
red one is CONSTITUTION §2.11's false positive, which gets switched off.

THE OLD HEADER'S OBJECTION, ANSWERED RATHER THAN IGNORED. It said a second
constant "must agree with HARBOR_CONTEXT_CEILING, and copies drift". True of a
second CEILING; not true of this. 150 B is not a copy of anything — it is the
cost of ONE ROUTING-TABLE LINE, `- [Title](file.md) — hook`, which is a fact
about the index's shape and about nothing else in the system. The number is not
invented here either: policy/constitution.md's own arithmetic for the 40,000 B figure
reads "Allowing 150 B a pointer ... plus ~600 B of section structure". This
takes that sentence at its word and applies it to the file it was about.

WHAT IT BOUNDS IS PROSE CREEP, WHICH IS THE FAILURE THAT ACTUALLY HAPPENS. An
index does not get big by gaining pointers — it is tiered, and the overflow
file is free. It gets big when a pointer grows into a paragraph. Bytes per
always-on pointer is exactly that quantity, it is indifferent to how many notes
the box holds, and so it does not rot in either direction.

AND IT SEVERS THE CIRCULARITY. store-check no longer runs context-budget at
all, so improving one instrument can never again move the other's verdict —
which is the structural bug this whole comment is about, not a side effect.
THE 600 IS NOT TUNED TO THIS BOX, DELIBERATELY. Measured 2026-09-20 on the
$HOME silo: the non-pointer lines come to 840 B, not 600, so the default
undercounts the structure term by 240 B and 240 B of that store's 3,724 B
overage is this constant rather than the index. Raising it to 840 would make
today's measurement pass its own test, which is fitting the bound to the data
and leaves nothing that could have come out red. The number stays where
policy/constitution.md's arithmetic put it, the discrepancy is recorded here, and the
knob exists for a box whose index legitimately carries more structure. What the
overage is actually made of, same measurement: 34 of 52 pointer lines exceed
150 B, median 200, longest 576 — so ~94% of it is pointers, not preamble.
```

## bin/memory-store-check.sh, lines 380-387 (before this edit)

```text
ZERO POINTERS IS NOT A ZERO ALLOWANCE — IT IS A PARSE THAT RETURNED NOTHING.
An index with bytes and no `](file.md)` line is either genuinely not a routing
table or a `harvest_pointers` that stopped matching, and this tool cannot tell
which from here. Reporting a confident OVER built on a possibly-broken extractor
is the same error as reporting green on an empty store (harbor#317) with the
sign flipped, and REF-10 already settled the general case for this repo: an
extractor that returned nothing from a document that plainly cites is a finding,
never a pass. So the verdict is withheld and the facts are still printed.
```

## bin/memory-store-check.sh, lines 392-393 (before this edit)

```text
BSD and GNU stat take different flags and this box is BSD. `find -mtime` is
POSIX, takes neither, and answers the only question asked here.
```

## bin/memory-store-check.sh, lines 395-397 (before this edit)

```text
-L for the same reason as the corpus walk above (harbor#608). Without it a
symlinked store reports 0 stale notes forever, and zero stale reads as a clean
bill of health rather than as nothing having been looked at.
```

## bin/memory-store-check.sh, lines 403-406 (before this edit)

```text
A SIZE VERDICT NEEDS ALL THREE, NOT JUST THE NUMBERS (harbor#317). The
allowance must have been derived, the basis must belong to the store being
measured, and there must BE an index to measure. Any one missing and the facts
are still printed while the verdict is withheld — never substituted.
```

## bin/memory-store-check.sh, lines 416-420 (before this edit)

```text
SCHEMA 2 (harbor#316): `ceiling` and `spent` are gone because the allowance no
longer comes from them, and `basis_applies` is gone because it can no longer
be false — a key that is always true is a field a reader learns to skip.
`bytes_per_pointer` and `structure_bytes` replace them, so a consumer can
re-derive the allowance from the same row rather than trusting it.
```

## bin/memory-store-check.sh, lines 423-426 (before this edit)

```text
`present` and `basis_applies` are additive (harbor#317). A consumer that
reads only `over` must not be able to mistake "nothing measured" for "fine",
which is why `allowance` and `over` are emitted ONLY with a real verdict --
an absent key is a question a reader has to notice, a `false` is not.
```

## bin/memory-store-check.sh, lines 452-453 (before this edit)

```text
GUARDED, BECAUSE AN INDEX FILE CAN EXIST AND BE EMPTY. 0 bytes and 0 pointers
passes BUDGET_OK (there is no parse to doubt) and would divide by zero here.
```
