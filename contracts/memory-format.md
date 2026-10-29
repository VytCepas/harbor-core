# Memory format (shared canonical)

**`schema_version: 1`.** The seam's shared fixtures live at
[`../fixtures/memory/`](../fixtures/memory/): a golden corpus plus
[`expected.json`](../fixtures/memory/expected.json), which pins the answers every
consumer of this contract must reproduce. `contracts/README.md` requires a seam
to ship fixtures both sides run; until 2026-08-02 this one did not have any, so
"shared canonical" was a claim no producer and no consumer was ever measured
against.

**The L0 reader that implements it** is [`../bin/memory.sh`](../bin/memory.sh)
(front door and grep degradation) over [`../tools/memory/`](../tools/memory/)
(BM25 + entity graph), with [`../bin/memory-lint.sh`](../bin/memory-lint.sh) as
the deterministic anti-rot gate. Two independent implementations of the
dangling-reference rule exist on purpose — one TypeScript, one POSIX sh, because
CI has no Bun — and both are asserted against `expected.json` rather than
against each other.

- **Canonical (source of truth):** markdown + YAML frontmatter + `[[wikilinks]]`, at every scope. Git-diffable, greppable, survives any tool being deleted.
- **Derived (rebuildable, gitignored, never canonical):** the entity graph (KnowledgeGraph), the BM25 index, an optional keyless vector. Rebuilt in-memory at query time. **No DB is the source of truth.**
- **Scopes:** L0 global (`~/.claude/MEMORY`, Helm) · L3 per-repo (`.agents/memory`, Yard) · L2 fleet aggregation (orchestrator, read-only). Degrade-by-tier: `grep → graph → BM25/rag`.
- **Work-log:** `WORK/sessions/<host>/<date>-<id>.md` — append-only, write-once, host-partitioned (conflict-free across devices).
- **Standalone guarantee:** works with no Yard, no Helm, or grep-only — each layer degrades to the one below.

## What kind of record goes where — settled 2026-07-26

The "library of issues and solutions" is **more than one artefact**, and
conflating them is how a knowledge base becomes a diary nobody queries. Each has
a different lifetime, a different writer, and a different failure mode.

*Amended 2026-07-29 (CU-1): a fourth row was added for reachable-from-a-phone
notes. It is listed here rather than left implicit because an undocumented
fourth home is exactly how "which one is canonical" becomes unanswerable.*

| Record | Home | Writer | Why it is separate |
|---|---|---|---|
| **An approach tried and rejected** | `docs/decisions/rejected-approaches.md` — append-only, in-repo | a human, at the moment of rejection | Must survive any tool being deleted, and must be readable by someone with nothing but `git`. It is the only one that is *in the repo rather than in memory* on purpose. |
| **What actually happened, per decision** | `MEMORY/OBSERVABILITY/<host>/guard-decisions.jsonl` — append-only, host-partitioned, size-rotated; closed generations move to `archive/` (never overwritten) | a hook (harbor#41) | Machine-written, high-volume, redacted **by construction** (rule id, verdict, shape class, truncated hash — never the command text). Nothing else can answer "did this rule fire, and was it right?" |
| **A durable lesson** | `MEMORY/KNOWLEDGE/<Type>/` (workstream **D**) | a human or a gated synthesis step | Typed, cross-linked, queryable. This is the layer that is *worth* reading a year later. |
| **A note the operator must reach from a phone** | a tracker Doc, via `bin/cu.sh` (`cu note`) — **CU-1** | the operator, or an agent on their behalf | The only row that is deliberately **outside** this repo and outside `MEMORY`. The other three are canonical-because-git-diffable; this one exists because git is not reachable from a phone at a client meeting. It is a **convenience surface, never a source of truth**: anything that matters is written to one of the rows above as well. Egress applies — a tracker Doc leaves the machine, so `~/.claude` content must never be written to one ([policy/constitution.md](../policy/constitution.md) §3). |

**The per-decision row was the one that did not exist, and the others depend on
it.** Without a record of what happened, both `docs/decisions/rejected-approaches.md` and
`MEMORY/KNOWLEDGE/` are written from recollection — which is the failure the
whole doc-truth mechanism exists to prevent, relocated one level up.

**It exists now, and this paragraph was wrong about that for a week** — corrected
2026-08-04, when M5 was built as the ledger's second consumer and read its own
contract. L1 shipped 2026-07-28 (`docs/reports/platform-build-tickets.md` § L1), the writer is
`floor_log_decision` in `bin/guard-lib.sh`, and the reader is
`bin/admission-observe-report.sh` — ask it for the count rather than trusting a number here.
The row's `Home` column was wrong in the same direction and more quietly: it read
`MEMORY/OBSERVABILITY/*.jsonl`, a glob that matches **zero files**, because the
sink is one directory deeper and rotates. A consumer written against that glob
would have found nothing and reported a clean ledger — the failure mode this file
exists to prevent, aimed at this file. *(This paragraph also said "the middle row"
and "the other two" while the table has carried four rows since the 2026-07-29
CU-1 amendment thirty lines above it.)*

**Synthesis into `KNOWLEDGE/` is gated, never automatic.** See
[policy/constitution.md](../policy/constitution.md) § *Fix the system, not your notes*: a
system that promotes unreviewed signal into durable policy converts noise into
doctrine at machine speed. Upstream reached the same conclusion — its
`ProposeCurrentStateEntry` writes to an approval queue because *"every entity
requires explicit approval before landing"*.

## Cost, because canonical does not mean free

Anything loaded **every session** is paid for in every session, forever.
`bin/context-budget.sh` measures the always-on surface against a ceiling and
lint rule **X3** surfaces it. Two consequences that are easy to get wrong:

- **An ambient skill costs context; an invoked-only one does not.** The tier is
  set by `disable-model-invocation: true` in frontmatter, and it — not restraint
  — is what lets the skill library grow without bound.
- **Memory injection is an always-on cost too.** D's retrieval must be
  on-demand or bounded; "inject the hot layer every turn" is a decision with a
  measurable price, not a free convenience.
