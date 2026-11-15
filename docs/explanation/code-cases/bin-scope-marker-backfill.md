---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/scope-marker-backfill.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/scope-marker-backfill.sh, lines 66-71 (before this edit)

```text
The contract's permissive spellings (contracts/marker.md): `context : repo`,
`"context": repo`, `context: "repo"`. Anchored at column 0 — a `context:`
indented under another block is a different key that shares a name. Matching
the KEY, not a value, because any declared value means "already declared".
Either key declares it (harbor#963): `scope:` is the standard's spelling, `context:` the legacy one, and a
repo already on `scope: project` must not gain a `context: repo` beside it.
```

## bin/scope-marker-backfill.sh, lines 78-78 (before this edit)

```text
The rows go through a file, not a pipe, so the loop runs in this shell and its counts reach the summary.
```

## bin/scope-marker-backfill.sh, lines 93-95 (before this edit)

```text
An indented `context:` is a DIFFERENT key, but writing a top-level one
beside it produces a file with two keys a reader could confuse. Report and
leave it: this tool does not resolve ambiguity it did not create.
```

## bin/scope-marker-backfill.sh, lines 110-114 (before this edit)

```text
This tool must never be able to rewrite the LIVE config. It is not a
settings.json mutator and carries no `--live` gate (lint D2 exempts it for
that reason), so the refusal below is what makes the exemption true rather
than a claim: resolved with `cd -P`, because `~/.claude/../.claude` and a
symlinked route name the same directory a string compare would miss.
```

## bin/scope-marker-backfill.sh, lines 127-134 (before this edit)

```text
PREPENDING IS NOT ALWAYS THE TOP (PR #96 review). A descriptor may open with
`%YAML`/`%TAG` directives and/or a `---` document-start marker. Writing above
those makes `scope: project` a SEPARATE first document — a single-document
loader then reads `{scope: project}` and loses the whole descriptor — or puts
a key illegally before a directive. So find the document start and insert
after it. Comments and blank lines may precede the marker and are skipped;
the first line that is real content ends the search, because a `---` after
content is a second document and not this one's header.
```
