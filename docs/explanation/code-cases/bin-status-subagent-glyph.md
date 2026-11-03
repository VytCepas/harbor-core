---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/status-subagent-glyph.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/status-subagent-glyph.sh, lines 6-42 (before this edit)

```text

WHY THIS EXISTS, AND IT IS NOT SYMMETRY WITH THE MAIN ROW. The default agent row
reads `name · description · token count`, which answers what an agent is called
and nothing about where it is standing. Two of this box's measured traps are
about exactly that:

  • WORKFLOW AGENTS SHARE ONE SCRATCHPAD — measured at 12 arms and 51 operations
    against a single filename, with one arm emitting rules only its siblings had
    written. Nothing on screen said two agents were in one directory.
  • CONCURRENT SESSIONS REVERT UNCOMMITTED WORK — three files reverted to HEAD
    mid-suite by another writer, `git status` clean, no stash.

Both are collisions in a shared working directory, and both were diagnosed AFTER
the damage from transcripts. `cwd` is in this payload per task, so the collision
is renderable WHILE IT HAPPENS. That is the entire justification for this file;
the tokens, the effort and the age are context, not the point.

CONTRACT (docs: subagentStatusLine). Stdin is ONE object with `columns` and a
`tasks` array; each task carries id, name, type, status, description, label,
startTime, model, effort, contextWindowSize, tokenCount, tokenSamples, cwd.
Stdout is one JSON line per row to OVERRIDE — `{"id": "...", "content": "..."}`.
Omitting a task keeps its default rendering; an empty content string HIDES it.

EVERY FIELD HERE IS OPTIONAL AND THE DOCS SAY SO. contextWindowSize and model
are omitted until the model resolves; effort is absent when the agent inherits
the session's. So each token is emitted only when its source is present, and a
row with nothing to add is left to the default renderer rather than replaced by
a worse copy of it.

NO FORKS AND NO FILES. This runs once per refresh tick beside the main row. It
reads its own stdin and nothing else — no git, no ps, no cache. If that ever
stops being true, the tick cost doubles for every visible agent.

FLAGS / ENV:
  --help                 this header
  HARBOR_STATUS_SUBAGENT_GLYPH_DUMP=<f>  append the raw payload to <f> (off unless set)
  HARBOR_TEST_NOW=<epoch>     freeze the clock (the suite pins this)
```

## bin/status-subagent-glyph.sh, lines 62-69 (before this edit)

```text
ONE jq PASS, AND ALL ARITHMETIC INSIDE IT — the same rule status-fleet-glyph.sh states
and for the same measured reason: `[ 41.7 -ge 85 ]` is not false in POSIX sh, it
is an ERROR that `2>/dev/null` swallows into a ramp that never fires.

EXIT 0 EVEN ON A MALFORMED PAYLOAD. Writing nothing leaves every row at its
default rendering, which is a worse row but a correct one. A non-zero exit or a
half-written line would degrade the agent panel itself, and a display helper must
never be able to damage the thing it decorates.
```

## bin/status-subagent-glyph.sh, lines 75-78 (before this edit)

```text
startTime IS NOT DOCUMENTED AS A UNIT, so all three plausible encodings are
accepted and an unparseable one yields NOTHING rather than a wrong age. A
fabricated "0m" on a long-running agent is worse than a missing age: it reads
as "just started" at the moment you are trying to work out what is stuck.
```

## bin/status-subagent-glyph.sh, lines 94-96 (before this edit)

```text
THE TAIL OF THE PATH, NOT THE PATH. A full cwd is 40+ columns of mostly shared
prefix in a row the docs warn is width-limited; the last segment is the part
that differs between agents, which is the only part this row exists to show.
```

## bin/status-subagent-glyph.sh, lines 99-101 (before this edit)

```text
A READING IS A NUMBER OR AN OBJECT CARRYING ONE; the docs name tokenSamples
("up to the last 16 readings") without a shape, so both are accepted and anything
else reads as absent.
```

## bin/status-subagent-glyph.sh, lines 104-108 (before this edit)

```text
ACTIVITY, NOT LEVEL. tokenCount only grows, so a sparkline of raw readings is a
ramp on every agent. The deltas between readings show work as it happens, and a
flat tail is an agent that has stopped growing (operator decision 2026-10-16).
Block elements are East-Asian-width A: one column unless a terminal is set to
draw ambiguous characters wide, which is off by default.
```

## bin/status-subagent-glyph.sh, lines 119-122 (before this edit)

```text
THE COLLISION SET. Any cwd claimed by more than one RUNNING agent — computed
across the whole array, which is why this cannot be a per-row transform. A
finished agent writes nothing more, so counting it made SHARED fire on every
agent that ever ran in the session directory (a false positive, 2026-10-16).
```

## bin/status-subagent-glyph.sh, lines 137-140 (before this edit)

```text
MODEL AND EFFORT ON EVERY ROW (operator ask, 2026-10-09). The model is
omitted until it resolves, so an unresolved one renders nothing. Only the
family renders (claude-sonnet-5-5, "Sonnet 5.5" → sonnet): the operator
always runs the latest of each, so the version is noise.
```

## bin/status-subagent-glyph.sh, lines 146-148 (before this edit)

```text
EFFORT IS ABSENT WHEN INHERITED, and an absent one now renders nothing: the
word `inherit` sat on almost every row and said only "same as the session"
(operator decision 2026-10-16).
```

## bin/status-subagent-glyph.sh, lines 153-156 (before this edit)

```text
A PERCENTAGE NEEDS BOTH FIELDS. contextWindowSize is documented omitted
until the model resolves, and tokenCount over an assumed 200k would be a
confident wrong number on a 1M model — off by 5x, in the direction that
reads as trouble when there is none.
```

## bin/status-subagent-glyph.sh, lines 162-163 (before this edit)

```text
THE ACTIVITY TRACE, and IDLE once the last three readings did not grow on a
running agent: the "is it stuck?" answer. Needs four readings to say either.
```

## bin/status-subagent-glyph.sh, lines 170-174 (before this edit)

```text
THE POINT OF THE FILE. A directory two agents share is rendered YELLOW and
marked; one agent alone in its directory is dim and unmarked. The mark is a
word, not a glyph: the operator reported that narrow text-presentation
symbols do not render at all in this terminal, which is how the main row
lost its pencil and its warning sign.
```

## bin/status-subagent-glyph.sh, lines 179-192 (before this edit)

```text
THE SAME BOUNDARY MARK AS THE MAIN ROW, and the reason is that they are read
in the same glance. status-fleet-glyph.sh defines the grammar: ` | ` separates
DIFFERENT facts, ` ·` means MORE ABOUT the fact on its left. Every field joined
here is a different fact — name, status, model, effort, context share, age,
directory — so this is the boundary case, and it was spelled with a SPACED
middot until 2026-08-24. That is the one form the main row removed, because
there the identical character also meant sub-fact two tokens away.

A DUPLICATED CONSTANT, GUARDED BY A TEST RATHER THAN A COMMENT. This file
cannot source status-fleet-glyph.sh — it is a sibling renderer, not a library, and it
redefines the colours for the same reason. So the suite asserts BOTH renderers
emit the same mark and that NEITHER emits a spaced middot; that assertion is
what makes the copy safe, and deleting it puts the two rows back on separate
grammars with nothing to notice.
```

## bin/status-subagent-glyph.sh, lines 56-56 (before this edit)

```text
A reading is a number or an object carrying one (the docs name tokenSamples without a shape); anything else reads as absent.
```

## bin/status-subagent-glyph.sh, lines 11-11 (before this edit)

```text
Removed notes: docs/explanation/code-cases/bin-status-subagent-glyph.md
```

## bin/status-subagent-glyph.sh, lines 56-56 (before this edit)

```text
Removed notes: docs/explanation/code-cases/bin-status-subagent-glyph.md
```

## bin/status-subagent-glyph.sh, lines 85-85 (before this edit)

```text
MODEL AND EFFORT ON EVERY ROW (operator, 2026-10-09): only the family renders (sonnet), since the operator always runs the latest of each; an unresolved model renders nothing.
```
