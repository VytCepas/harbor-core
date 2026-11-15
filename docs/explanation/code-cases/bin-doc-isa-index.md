---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/doc-isa-index.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/doc-isa-index.sh, lines 7-38 (before this edit)

```text
WHAT F1 OWES, AFTER THE 2026-07-26 REWRITE. Not a new ISA format: the full
fourteen-section skill is vendored and installed, and the original F1 proposed
replacing it with a four-section version — a downgrade caught only because
three documents disagreed about one live asset. What is left is the part
upstream has no equivalent of: an index of ISA runs that points AT repo-local
sources instead of copying them, and the decision about where a run's ledger
lives now that the Log is the storage layer. That decision is
contracts/isa-ledger.md; this is its mechanism.

THE OUTPUT IS NOT COMMITTED, AND THAT IS THE WHOLE DESIGN. Its input is
~/.claude/MEMORY/WORK — machine state. A generated file in git whose content
depends on the box reddens its own staleness lint on every clone, and this
repo has already paid for that shape once: docs/generated/plan.md's first L2 declaration
pointed under the live config dir and would have read DONE here and OPEN on a
fresh checkout. status-generate.sh settled the pattern — docs/generated/status.md is committed and
repo-derived, build/observed.md is machine state and gitignored. An ISA index
is entirely machine state, so all of it goes to build/.

BY REFERENCE, NEVER BY COPY. Every cell is a slug, a path or an id. Copying an
ISA's content here would make this a second store that drifts against the
first, which is the defect docs/explanation/doc-truth.md exists to prevent — and an ISA
is a living document whose whole value is that one copy moves.

LC_ALL=C ON EVERY SORT. A generated file whose row order depends on the
operator's locale diffs against itself between machines, and BSD sort aborts
outright on an illegal byte sequence in the default locale — both already
measured on this box.

EMPTY IS A RESULT, NOT A FAILURE. Zero ISA runs exist on this box (measured
2026-08-22). An index that refused to run until it had rows would be one
nobody could test before the first run, and the first run is exactly when a
silent bug costs something.
```

## bin/doc-isa-index.sh, lines 74-79 (before this edit)

```text
THE LOG IS A SIBLING, NOT A PARENT. Harbor's G2 work-log owns
MEMORY/WORK/sessions/<host>/, and the ISA skill's unmodified contract puts a
run at MEMORY/WORK/<slug>/ISA.md. They share a directory and are disjoint
because one reserves `sessions` — contracts/isa-ledger.md is where that is
decided rather than assumed. Requiring ISA.md is what enforces it: a session
directory has none.
```

## bin/doc-isa-index.sh, lines 89-93 (before this edit)

```text
REPO-LOCAL REFERENCES, EXTRACTED FROM THE ISA'S OWN BODY. An issue or PR
is `<repo>#<n>` or `<org>/<repo>#<n>`; an ADR is the `adr-NNN-*` filename
convention this fleet
already uses. Nothing is inferred from the slug — a reference the ISA does
not make is not one this index may invent.
```
