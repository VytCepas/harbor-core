# pilot — the practice layer, and where it should live

**Status:** decision brief, 2026-08-29 · ticket **R7** · **not executed — the
boundary is the operator's call and this is the argument, not the move.**

`contracts/naming.md` (deleted by harbor#950; `pilot` is now a legacy alias of `knowledge-base` in `standards/naming/aliases.tsv`) reserved `pilot` for the practice layer: the knowledge of
*how this work is done*, as distinct from *what the data repo contains*. The layer
exists; it currently lives inside the company's data repo, whose name is accurate for its
internal data assets and a wrong one for a rubric.

This is the same defect as `topology` one level up — an accurate name with an
accreted layer inside it — and R3 has just fixed the smaller instance by moving
the deliverable contract out into its own skill.

## The test, applied per directory

> **Would this still be true if the company's data assets were replaced tomorrow?**

Measured 2026-08-29:

| directory | files | size | still true? | verdict |
|---|---|---|---|---|
| `EVALS/` | 6 | 84K | yes — a rubric, a design, a contamination rule | **practice** |
| `PLAYBOOK/` | 3 | 24K | yes — job shapes, not this repo's jobs | **practice** |
| `bin/` | 9 | 168K | mixed — `eval-quarantine.sh` is practice; `check-volumes.sh` and `check-connections.sh` are wholly about this warehouse | **split** |
| `ACCESS/` | 11 | 136K | no — these are the company's accounts | stays |
| `SEAMS/` | 7 | 252K | no | stays |
| `LINEAGE/` | 4 | 1.6M | no | stays |
| `AUDITS/` | 26 | 632K | no | stays |
| `RUNBOOKS/` | 11 | 192K | no | stays |
| `probes/` | 26 | 148K | no — every query names this project's datasets | stays |

**The practice layer is small: roughly 108K across nine files, plus one script.**
That number is the whole argument below.

## The three options, and the cost of each

| option | cost | what it buys |
|---|---|---|
| **A · its own repo** | a fourth governed repo, its own CI, marker, `CLAUDE.md`, registry row; every cross-reference from the data repo becomes cross-repo | a name that matches its contents |
| **B · a directory inside `harbor`** | one move; harbor already owns the skills the evals evaluate, plus `bin/`, lint and CI | the same name-fit, and the evals land next to what they measure |
| **C · rename in place** | nothing moves | nothing — the mismatch is the point of the ticket |

## Recommendation — B

**Move the practice layer into `harbor`, do not create a fourth repo.**

Three reasons, in order of weight:

1. **The evals measure harbor's skills.** `DS-1`, `EV-1` and today's `R1`, `R2`,
   `R9` all score behaviour produced by skills that live in `harbor`. R2's
   fixtures already sit at `skills/*/EVALS/`. The layer is being pulled toward
   harbor by gravity; option A pulls against it.
2. **108K does not earn a repo.** `docs/explanation/modularity.md`: imagine the seam
   gone. If a separate `pilot` repo vanished and its contents landed in `harbor`,
   nothing about either would get harder. That is the definition of a
   pass-through seam.
3. **A fourth repo costs governance, permanently.** `IJ3` already reports four
   governed-but-unregistered repos on this box. Adding a fifth to house nine
   files makes the registry problem worse to fix a naming problem.

**What argues against B, honestly:** `harbor` is the governance repo, and putting
the thing that *evaluates* the governance inside the thing being governed removes
a boundary. That is a real objection. It is outweighed because the boundary was
never enforced anyway — the evals have always been read and written by the same
sessions that write the skills — and pretending otherwise is worse than
acknowledging it.

## What is NOT proposed

- **`ACCESS/`, `SEAMS/`, `LINEAGE/`, `AUDITS/`, `RUNBOOKS/`, `probes/` stay.**
  They are the data repo's own, they fail the test above, and R7's own ticket says so.
- **No prose is rewritten in the move.** Same rule as R3: every eval's text
  encodes which fixture retired which failure, and a rewrite destroys that trail.

## Falsifier

After the move, ask of each relocated directory whether its name still describes
its contents, and ask of the data repo whether its name still describes what remains.
If either answer is no, the boundary was drawn on convenience rather than on
subject and this brief was wrong.

## Why this is a brief and not a commit

The split relocates a directory between two governed repos and changes where a
future reader looks for the rubric that judges this work. `policy/constitution.md` puts
that class of change behind a person. **Nothing has moved. The recommendation is
B, and the decision is yours.**
