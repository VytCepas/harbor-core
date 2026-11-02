---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/standard-issue-label.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/standard-issue-label.sh, lines 17-49 (before this edit)

```text
IT SUGGESTS A THEME AND NEVER A TYPE, and the asymmetry is the design. A theme is
a claim about which part of the tree an issue is about, so it can be derived from
the paths the issue names against the globs contracts/issue-taxonomy.tsv declares.
A type is a claim about the system's STATE — whether something is wrong now (bug)
or right and unenforced (tech-debt) — and no content predicate can settle that.
Guessing it would produce a plausible label nobody chose, which is the failure this
repo files tickets about. So --check reports a missing type and stops.

IT NEVER APPLIES WHAT IT SUGGESTS. --suggest prints; --apply takes labels from the
caller and refuses any the taxonomy does not carry. Two verbs, because a connector
that labels on its own authority is an unreviewed classifier writing into the
backlog at machine speed — CONSTITUTION's "encoding a fix is a human-gated act".

A PROVENANCE EPIC IS THEME-EXEMPT, and that is a rule rather than a tolerance. An
`epic:provenance` is the origin record of an audit pass: its children span several
themes by nature, so forcing one on it would file a true finding under a false
heading. Every other kind must carry both axes. Without this the audit's "none" line
could never appear, and a checker that can never come back clean is one nobody reads.

A FALSIFIER IS THE CHEAPEST TRIAGE STEP THERE IS, and it is reported rather than
required. On 2026-09-16 FOUR tickets closed on nothing but a re-read of their own
stated refutation condition — it had already fired, weeks earlier, and nobody had
looked. That is the highest-yield paragraph in a ticket and it costs one read.

It is not part of --check, deliberately: most of the backlog predates the
convention, so making it fatal would redden 122 issues and teach the reader to
ignore the checker (§2.11). `--falsifiers` names them, and the count is the thing
to watch trend down.

THE SIBLING HALF IS WHY THIS EXISTS AT ALL. Twelve themes carry 122 open issues, and
before this, finding an issue's family meant knowing the backlog by heart. On
2026-09-16 three sibling epics from ONE audit pass were found referencing each other
nowhere, across three repos, six weeks after they were filed.
```

## bin/standard-issue-label.sh, lines 68-70 (before this edit)

```text
THE REPO IS DERIVED, NOT TYPED. A constant here would be a second copy of a fact
`git remote` already holds, and this script runs from worktrees whose origin is
the same repo.
```

## bin/standard-issue-label.sh, lines 77-82 (before this edit)

```text
labels_all -> EVERY declared label, whatever its kind (harbor#609). The apply
gate is where this contract is enforced, so it has to read all of it: the gate
used to test `type` and `theme` alone, which meant `--apply P1-high` was refused
as "not in the taxonomy" while P1-high sat on 58 open issues. A validation
narrower than the contract it cites teaches the caller to set labels by hand
instead, which is exactly how 23 labels came to be applied against no list.
```

## bin/standard-issue-label.sh, lines 105-108 (before this edit)

```text
A THEME IS SUGGESTED FROM THE INTERSECTION, not from a keyword. Every tracked path
a theme's globs cover is compared against the paths the issue body names, and the
theme with the most hits wins. A tie prints both rather than picking, because a
coin-flip label reads exactly like a considered one.
```

## bin/standard-issue-label.sh, lines 206-208 (before this edit)

```text
AN EPIC IS EXEMPT, and for the same reason a provenance epic is theme-exempt:
an epic's falsifier is its children's. Requiring one of the container would
file a true finding under a false heading.
```

## bin/standard-issue-label.sh, lines 229-233 (before this edit)

```text
THE READ'S STATUS IS THE GATE. Before this, a failed `gh` either aborted the run silently
under `set -e` (exit 1, no line printed) or, when it succeeded with no rows, produced an
empty $ALLOPEN that every section below read as "nothing open": cardinality said "none",
and the closed-parent join swallowed the whole graph (harbor#626, DE-15). Nothing audited
is not a clean audit, so the run stops here and says so.
```

## bin/standard-issue-label.sh, lines 247-251 (before this edit)

```text
── 1 · CARDINALITY, read from the #AXIS rows rather than hard-coded ────────
The seven-axis table this replaced was PROSE. A human read "layer exactly
one" and no checker did, so 32 issues violated it while every gate stayed
green (harbor#612). Parsing the declaration is the only thing that keeps
the rule and the mechanism from drifting apart.
```

## bin/standard-issue-label.sh, lines 269-271 (before this edit)

```text
A PROVENANCE EPIC IS THEME-EXEMPT and that is a rule, not a tolerance:
its children span themes by nature, so requiring one files a true
finding under a false heading.
```

## bin/standard-issue-label.sh, lines 292-295 (before this edit)

```text
harbor#609 declared `theme:security` and `theme:testing`; NEITHER EXISTED on
the tracker, while bare `security` and `testing` sat on 20 issues the apply
gate then refused. A contract checked in one direction only is how that
shipped green.
```

## bin/standard-issue-label.sh, lines 320-322 (before this edit)

```text
PAGINATED, because the first cut asked for `first:100` against 135 open
issues and silently reported 24 orphans instead of 34 — a truncated page
reads exactly like a smaller problem.
```

## bin/standard-issue-label.sh, lines 387-394 (before this edit)

```text
`|| true` IS LOAD-BEARING AND IS NOT COSMETIC. This pipeline is the last
command in the --audit arm, and `set -e` is on (line 50). Its status is the
loop body's final `[ -n "$lonely" ] && printf`, which is FALSE whenever the
LAST theme happens to have no lonely issue. The script then died HERE with
status 1, and everything below — including the whole --strict gate — never
ran. Measured 2026-09-21 on live harbor: `--audit` and `--audit --strict`
both exited 1, the second one not because it was strict. An AND-OR list
exempts every command but the last from `set -e`, which is the whole fix.
```

## bin/standard-issue-label.sh, lines 398-401 (before this edit)

```text
REPORTING IS THE DEFAULT AND FAILING IS OPT-IN. Turning 67 standing
violations into a red exit on day one is the false positive CONSTITUTION
No.2 clause 11 names: a checker that blocks ordinary work gets switched off.
--strict is what CI uses once the count is zero.
```
