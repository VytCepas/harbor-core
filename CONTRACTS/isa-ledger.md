# ISA ledger — where a run lives, and what indexes it

**Owner: harbor#117 · F1.** F1 was rewritten on 2026-07-26 after the original
version turned out to be a downgrade: it specified a four-section ISA while the
full fourteen-section skill was already vendored, installed and in use. What it
still owed was two things upstream has no equivalent of — a pointer table over
ISA runs, and **a decision about where a run's ledger lives now that the Log is
the storage layer.** This file is the decision. `bin/isa-index.sh` is the table.

## The collision, stated before it is settled

Two subsystems claim `~/.claude/MEMORY/WORK`:

| Writer | Path | Owner |
|---|---|---|
| The ISA skill | `MEMORY/WORK/<slug>/ISA.md` | vendored upstream, body unmodified |
| Harbor's Log (G2) | `MEMORY/WORK/sessions/<host>/<date>-<id>.md` | this repo |

Neither knew about the other. The ISA skill's `Scaffold` workflow writes to a
slug directory of the form `YYYYMMDD-HHMMSS_kebab-description`; Harbor's
work-log reserves `sessions/`. Nothing enforced the separation, and nothing
would have reported a breach.

## The decision

**They stay in one directory, and `sessions` is the reservation.** An ISA run is
`MEMORY/WORK/<slug>/ISA.md`; anything under `MEMORY/WORK/sessions/` is the Log
and is never an ISA run.

Rejected, and why:

- **Move ISA to its own root.** It would mean editing the vendored skill's
  storage path, which is the one thing F1's rewrite forbids — the body stays
  unmodified so a re-harvest is a diff and not a merge.
- **Move the Log.** The Log is the older resident, host-partitioned, and cited
  by `PROVENANCE.md` as the shape taken from upstream's observability pattern.
  Moving it to dodge a collision that has not yet happened costs more than the
  reservation.

**What enforces it** is the index's own predicate: a directory counts as a run
only when it contains `ISA.md`, and a session directory never does. That is not
a convention anybody has to remember — `tests/memory/isa-index-test.sh` puts a session
tree in the fixture store and fails if it is counted.

## The index is generated, machine state, and not committed

`sh bin/isa-index.sh` writes `build/isa-index.md`.

**Not committed, deliberately.** Its input is the operator's `MEMORY/WORK`. A
generated file in git whose content depends on the box reddens its own staleness
lint on every clone — this repo has already paid for that shape once, when
`PLAN.md`'s first `L2` declaration pointed under the live config dir and would
have read DONE on this machine and OPEN on a fresh checkout. `status-gen.sh`
settled the pattern: `STATUS.md` is committed and repo-derived, `build/observed.md`
is machine state and gitignored. An ISA index is entirely machine state.

**By reference, never by copy.** Every cell is a slug, a path or an id. Copying
ISA prose here would create a second store that drifts against the first, which
is [DOCTRINE/doc-truth.md](../DOCTRINE/doc-truth.md)'s whole argument — and an
ISA is a living document whose value is that exactly one copy moves.

Repo-local references are extracted from an ISA's **body**: `<repo>#<n>` or
`<org>/<repo>#<n>` for issues and PRs, and the `adr-NNN-*` filename convention
this fleet already uses. Nothing is inferred from the slug. **A reference the
ISA does not make is not one the index may invent.**

## What is true about the installed skill

Measured 2026-08-22, rather than restated:

- The skill is installed and its body is **unmodified** in the sense F1 requires
  — no four-section replacement was ever made. The repo and live copies differ
  only in the documented intake edits (`vendor/skills/PROVENANCE.md`) and the
  `name:` rename the installer performs.
- **Its tier is not stated here.** Lint **X4** derives ambient-vs-invoked from
  disk on every run, and `PROVENANCE.md`'s F1 row stated it by hand and was
  wrong for 22 days — written 2026-07-29 saying *"ambient every session"*, two
  days before the skill was flipped to `disable-model-invocation: true`. The
  correction that fixed one error introduced another, in the same sentence.
  Ask X4.
- **Zero ISA runs exist on this box.** The index is empty, and empty is a
  result: the skill is invoked-only, so a run happens when somebody asks for one.
