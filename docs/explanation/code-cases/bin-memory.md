---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/memory.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/memory.sh, lines 2-18 (before this edit)

```text
memory (harbor#6 — workstream D, D1/D7) — the L0 memory front door.

One door, two rungs. `memory <query>` runs the Bun engine when Bun is present;
when it is not, the SAME command still answers, over the same markdown, using
nothing but grep. That is D7's third standalone degradation, and it is why
this file is POSIX sh rather than part of the engine: a ladder whose bottom
rung needs the runtime that is missing is not a ladder.

WHY THE FRONT DOOR IS NOT THE ENGINE. bin/deploy-doctor.sh classifies bun as
OPTIONAL — "the floor is deliberately zero-Bun" — and CI preflights a fixed
list of binaries that does not include it. Anything Harbor must be able to run
on any machine lives in bin/ and is sh; the retrieval algorithms live in
tools/memory/ and are TypeScript, which is the language-by-layer rule from
policy/constitution.md applied rather than restated.

Writes nothing. Reads markdown. Every index is rebuilt per invocation by the
engine and discarded (contracts/memory-format.md).
```

## bin/memory.sh, lines 21-28 (before this edit)

```text
NOGLOB, AND IT IS LOAD-BEARING. Splitting a list by setting IFS and expanding
unquoted — `set -- $_new`, `for f in $HITS` — controls FIELD splitting but does
nothing about PATHNAME expansion, which happens on the same unquoted word. So
`memory '*.md'` had its query term expanded against the caller's working
directory: measured before this line existed, the identical query returned 7
results run from a directory holding .md files and 1 from a directory without.
A search tool whose answer depends on where you were standing is worse than one
that errors. Nothing here needs globbing; `case` patterns are unaffected by -f.
```

## bin/memory.sh, lines 31-35 (before this edit)

```text
── resolve self through symlinks ───────────────────────────────────────────
The installed entry point is a symlink (~/.local/bin/memory), so $0's dirname
is the symlink's directory, not the repo's. Without this the engine is
unreachable from exactly the place an operator actually types the command, and
the tool silently drops to the grep rung while reporting nothing unusual.
```

## bin/memory.sh, lines 52-53 (before this edit)

```text
Status lines are log-lib's, on stderr: stdout is the answer (contracts/logging.md). A clean search logs
nothing; a refusal ends with the summary after its fix line. Found beside the file the link resolves to.
```

## bin/memory.sh, lines 63-66 (before this edit)

```text
THE DEFAULT IS THE NOTES STORE (harbor#1010 PR 4, D-68): the $HOME silo, projects/<home-key>/memory, which is where
the notes and their index live and where every governed repo's silo is routed (memory-route.sh). The old
$CFG/MEMORY tree is the fallback only when that silo does not exist, so a box without notes still answers.
Same key rule as memory-route.sh: the physical $HOME with every `/` turned into `-`.
```

## bin/memory.sh, lines 73-79 (before this edit)

```text
PIN grep, for the same reason bin/library-admission.sh pins $FLOOR_GREP. On this
machine the `grep` first in PATH is a ugrep wrapper carrying `-I
--ignore-files`, so it silently skips binary AND gitignored files. The grep
rung's entire job is to find every note that mentions a word; a wrapper that
quietly omits some of them returns a SHORTER list with a zero exit status,
which reads exactly like a correct answer. Absolute path first, PATH second so
this still runs on a box without /usr/bin/grep.
```

## bin/memory.sh, lines 104-119 (before this edit)

```text
── split off --root, keep everything else for the engine ───────────────────
ROTATION, not a delimited string. The first cut joined the remaining arguments
with newlines and re-split them with IFS, which loses any argument that
CONTAINS the delimiter: a single term `foo<newline>bar` came back as two terms.
`set -- "$@" "$1"; shift` walks the list exactly once and pushes each argument
onto the end unchanged, so every byte of every argument survives — spaces,
newlines, quotes and glob characters alike — with no IFS games and nothing for
`set -f` to have to protect.

FLAGS ARE SEPARATED FROM TERMS HERE, not passed through. The engine gets its
options BEFORE a `--` and the query terms after it, so a term that looks like
a flag stays a term. Passing "$@" wholesale after `--` was tried and broke the
opposite way: `--json` became a search word and the JSON output vanished.
Every flag value is validated here rather than in the engine, so the message
names `memory`, and $FLAGS can be expanded unquoted safely — it only ever
holds literals this loop wrote.
```

## bin/memory.sh, lines 141-143 (before this edit)

```text
End of options. Everything after it is a query term, including anything
that looks like a flag — the standard escape hatch, and the one an
operator reaches for when a search word starts with a dash.
```

## bin/memory.sh, lines 160-160 (before this edit)

```text
── rung 1: the engine ──────────────────────────────────────────────────────
```

## bin/memory.sh, lines 164-174 (before this edit)

```text
SAY SO WHEN THE RUNTIME IS PRESENT BUT THE ENGINE IS NOT. Dropping to the grep
rung is the correct answer on a machine with no runtime; it is the WRONG answer
on a machine that has one and simply cannot see tools/memory/, and the two are
indistinguishable in the output — both say "tier grep".

The reachable way to land here: this script COPIED out of the repo rather than
symlinked to it. It resolves the engine relative to itself, so a copy at
~/.claude/bin/memory.sh looks for ~/.claude/tools/memory/ and finds nothing.
That is why `memory` installs as a symlink while `harbor` installs as a copy —
`harbor restore` must survive the checkout disappearing, and this must reach
into it.
```

## bin/memory.sh, lines 182-187 (before this edit)

```text
`--` BEFORE the query terms, and --root BEFORE that. The engine parses argv
with node:util parseArgs in strict mode, so an unseparated term beginning
with a dash — a version string, a negative number, anything flag-shaped —
was read as an unknown option and killed the process with exit 2. The grep
rung handled the same query fine, so the PRIMARY tier failed on input its
own fallback survived.
```

## bin/memory.sh, lines 192-199 (before this edit)

```text
── rung 2: grep ────────────────────────────────────────────────────────────
Deliberately NOT a reimplementation of the ranker. It answers the question the
markdown can answer without a runtime — "which notes mention every one of
these words" — and says which rung produced it, so a degraded answer is never
mistaken for a ranked one.
EXIT 2, not 0. The requested operation did not run, and a caller that checks
only the status must not be told it succeeded. Distinct from a search that
finds nothing, which IS a successful answer and exits 0.
```

## bin/memory.sh, lines 211-212 (before this edit)

```text
Progressive narrowing: start from every markdown file, then keep only the ones
matching each term in turn. -F because a query is words, not a regex — an
```

## bin/memory.sh, lines 216-219 (before this edit)

```text
Terms are read straight from "$@" rather than re-collected into a string, for
the same reason the argument loop rotates: a term is whatever the caller typed.
Only the FILE list is newline-delimited, and `find -print` cannot emit a path
containing a newline in a form this loop could misread anyway.
```

## bin/memory.sh, lines 244-250 (before this edit)

```text
THE TWO RUNGS EMIT THE SAME SHAPE. A consumer must not have to know which rung
answered in order to read the reply, so the grep tier carries `query` too. It
was missing, which meant a caller could read `.query` from a ranked answer and
get null from a degraded one — a difference that only shows up on the machine
without the runtime, which is the machine nobody tests on.
awk, not sed: escaping a newline portably across BSD and GNU sed is a trap, and
awk is on CI's preflight list.
```
