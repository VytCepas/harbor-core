---
kind: decision-record
status: accepted
alias: D-93
date: 2026-11-10
supersedes: -
superseded_by: -
source: harbor#1501
owner: harbor#1501
---

# External knowledge bases follow one standard, navigated without RAG

Settles where the knowledge-base standard lives, what it governs, how its skill is reached and where its checks run.

## Context

- Operator decision, 2026-11-10 (harbor#1501), after a research run on how people and agents find organisational
  knowledge without vector retrieval (`docs/explanation/knowledge-base/`) and an independent critique of the first draft.
- The first base it was written for is a company wiki. Harbor already had D-90 (four doc kinds after Diátaxis), D-22
  (the doc header) and `contracts/memory-format.md`, none of which covers a base held in a platform's database.

## Decision

1. **Home.** The standard is `standards/knowledge-base.md` and the method is the skill `skills/doc-knowledge-base/`.
   Platform facts live in a profile beside each base's own tooling (standard §13), not in Harbor.
2. **Scope: external bases only.** A company wiki, a document base, a shared agent memory store. Harbor's own docs and
   agent memory keep D-90, D-22, naming §15 and `contracts/memory-format.md` unchanged; standard §12 is the bridge.
3. **The skill is hidden** (`disable-model-invocation: true`) and reached by name or through `skill-catalog`:
   restructuring a base is planned work, not something that must fire unprompted.
4. **Checks live with the base**, in the tool that already reads it, run on demand. No generic Harbor checker until a
   second base exists. A schedule needs its own yes.
5. **The first base's own rule changes are held** until its pilot re-measure (standard §14 step 5). Its structure
   spec, loader and importers stay as they are until then.

## Consequences

- Two kind lists coexist: Harbor's four (D-90) and a base's seven core kinds (standard §5). Unifying them is a later
  decision with its own rename cost.
- Decision 5 means the first base's checks stay unbuilt until the pilot: built now, they would report against rules
  its structure spec still contradicts. Against the recommendation (accept the rule changes now); recorded as decided.
- The standard's judgment numbers (80%, 5 calls, the budgets) are untested; the first base's findability set tunes them.

## Alternatives rejected

- **Standard and skill in the first base's repo only**: the next base would start from scratch, and sessions outside
  that repo would never see the skill.
- **Unify with D-90 now**: supersedes D-90 and re-kinds Harbor docs, a rename series with no measured gain yet.
- **A visible skill**: an always-on listing cost on a box already over its context ceiling, for rare work.
- **A generic Harbor checker**: a seam with one adapter, which the modularity standard calls premature.
