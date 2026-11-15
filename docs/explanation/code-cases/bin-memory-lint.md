---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/memory-lint.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/memory-lint.sh, lines 6-27 (before this edit)

```text
FOUR CHECKS, and they are not the same kind of thing:

  dangling    a note links to a slug no note carries. HARD under --strict:
              the link is wrong now, and it will not fix itself.
  dead-path   a note cites ](.\/relative) that does not resolve. HARD too.
  collision   two notes share a slug, so every link to it is ambiguous and
              whichever one a reader gets is filesystem order. HARD.
  stale       a note has not been touched in a long time. REPORT-ONLY, always
              — age is not a defect. A note written once and correct forever
              is the GOAL, and a gate that fails on it would teach the
              operator to touch files to silence a linter, which is how a
              store fills with meaningless commits. policy/constitution.md §2.11: a
              false positive is a defect, not safety.

WHY THIS IS SH AND NOT PART OF THE ENGINE. It has to run where the engine
cannot: CI preflights a fixed binary list that does not include bun, and D2 is
a gate. That means the dangling-reference definition now exists in two
languages, which is a drift risk and is handled the way policy/constitution.md's
cross-repo-seam row says to handle it — a shared fixture both sides run.
fixtures/memory/expected.json pins the answer; tests/memory/memory/memory.test.sh asserts THIS
script and tools/memory/graph.ts each reproduce it, so the two cannot drift
apart without a test going red.
```

## bin/memory-lint.sh, lines 30-35 (before this edit)

```text
NOGLOB. Every list here is split by setting IFS and expanding unquoted, which
governs FIELD splitting only — pathname expansion still applies to the same
word. A note filename or a [[link target]] containing *, ? or [ ] would be
expanded against the working directory before it was ever compared to a slug,
so a store could report dangling references that depend on where the lint was
run from. Nothing here needs globbing.
```

## bin/memory-lint.sh, lines 88-92 (before this edit)

```text
VALIDATED HERE, not left to the arithmetic below. Under dash
— the canonical /bin/sh this file is written for — a non-
numeric operand makes $((…)) abort the interpreter with
"Illegal number", so a typo killed the gate instead of
printing a usage error.
```

## bin/memory-lint.sh, lines 110-123 (before this edit)

```text
The same scope the engine walks (tools/memory/store.ts): dot-directories are
either history (.git) or another scope (.agents — an L3 repo store), and
indexes/ is the derived tier. -print0 is not portable, so the file list is
newline-delimited and every consumer sets IFS accordingly; a note filename
containing a space is in the fixture corpus precisely to keep that honest.
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

## bin/memory-lint.sh, lines 139-143 (before this edit)

```text
── link extraction ─────────────────────────────────────────────────────────
One awk pass per file emitting `line<TAB>dialect<TAB>target`. awk is on CI's
preflight list; a sed/grep pipeline could not track frontmatter state, and the
`related:` block is exactly where state is needed — the same key name means a
list, a scalar or a block of objects depending on what follows it.
```

## bin/memory-lint.sh, lines 145-155 (before this edit)

```text
AN UNCLOSED FRONTMATTER BLOCK IS NOT FRONTMATTER. A note that opens with
`---` and never closes it is a typo, and the two readers disagreed about it:
tools/memory/store.ts falls back to "no frontmatter, all body" (it searches
for the closing fence and gives up if there is none), while this awk had no
such lookahead — `infm` never reset, so the ENTIRE file was parsed as
frontmatter and ordinary body prose under a `related:` line became fabricated
dangling references, failing --strict on a missing dash.

Two implementations of one definition may not disagree; that is the whole
reason expected.json is the arbiter. So the closing fence is established
first, in its own pass, and passed in.
```

## bin/memory-lint.sh, lines 183-186 (before this edit)

```text
CODE IS NOT PROSE, and this must agree with tools/memory/store.ts line for
line — the two readers are held to one pinned answer. `[[ $? == 1 ]]` is a
shell test; without this a note documenting a bash fix reports two dangling
wikilinks, which is what the real store did.
```

## bin/memory-lint.sh, lines 288-291 (before this edit)

```text
git log, not mtime: a fresh clone rewrites every mtime, so an mtime-based age
would call an entire store stale the day it is checked out. A store that is
not a git repo simply has no age, which is reported as such rather than
guessed at.
```

## bin/memory-lint.sh, lines 296-326 (before this edit)

```text
ONE `git log` PER NOTE, AND IT IS SLOW ON PURPOSE — 24 s on the live L0 store
(308 notes, 1567 commits). harbor#216 replaced this with a single
`--name-only` pass at 113 ms and the replacement was WRONG IN FOUR WAYS, all
reproduced, all silent, all reporting success. Reverted; the speed is not
worth a gate that lies. Every one of the four is now an assertion in
tests/memory/memory/memory.test.sh, so a future fast path has to earn its way past them:

 1 NESTED STORE. `git log --name-only` emits paths relative to the REPO ROOT,
   not to the store. On this repo`s own fixtures/memory/corpus the join
   matched nothing and 17 stale notes reported as 0. `git log -1 -- "$rel"`
   resolves the pathspec against `-C "$STORE"`, so this loop is correct for a
   store at any depth. A fast path needs `--relative -- .`.
 2 core.quotePath. git C-quotes a non-ASCII name in --name-only output
   ("caf\303\251.md"), which can never equal the raw path from `find`, so
   every such note vanished from the report. A bare space does NOT trigger it,
   which is why the fixture corpus`s `spaced name.md` was no control at all.
   A fast path needs `-c core.quotePath=false`.
 3 A FILENAME THAT LOOKS LIKE THE HEADER. The one-pass parser marked a
   commit by a `C<digits>` prefix; a tracked file literally named
   `C1700000000` is indistinguishable from it and re-dates every path after
   it. Any interleaved format has this hazard, because a git path can be
   almost any byte string.
 4 MERGE COMMITS DIVERGE IN BOTH DIRECTIONS. The replacement`s own comment
   claimed it "can only UNDER-report" and that was false: --name-only prints
   nothing for a merge, so a note whose newest touch is a conflict resolution
   reads OLDER than it is (over-report), while a merge pruned by history
   simplification makes it read NEWER (under-report). `git log -1 -- <path>`
   applies the same simplification the operator sees.

STILL git log AND NOT mtime: a fresh clone rewrites every mtime, so an
mtime age would call an entire store stale the day it is checked out.
```
