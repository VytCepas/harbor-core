---
kind: decision-record
status: accepted
alias: D-90
date: 2026-10-24
source: harbor#950
---

# Human doc kinds follow Diátaxis

Naming-standard decision D-90. Settles the four `kind` rows `tutorial`, `how-to`, `reference` and `explanation` in
`standards/naming/terms.tsv`, which D-4's `docs/<kind>/` folders are named after.

## Context

- Operator decision, 2026-10-24 (harbor#950, sitting B; the #949 composition review of 2026-10-04 proposed it).
- The four rows were registered `experimental` with no recorded yes, so `docs/<kind>/` had no settled set of kinds.

## Decision

**A human-read doc is one of four kinds, after Diátaxis (Procida):** `tutorial` (learning: one lesson to a working
result), `how-to` (a task: the steps to one goal the reader already has), `reference` (information: the machinery,
generated from the registers where it can be) and `explanation` (understanding: the why, where doctrine lives).
Records keep their own kinds (`decision-record`, `report`). The four rows are `stable`.

## Consequences

- #961's W1 docs PR moves human docs into `docs/<kind>/` by these four kinds.
- `explanation` holding doctrine differs from the 2026-10-05 #961 mapping, which sends `DOCTRINE/` to
  `policy/rationale/`. That row becomes a question for the #961 sitting.
