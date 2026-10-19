---
kind: decision-record
status: accepted
alias: D-83
date: 2026-10-10
source: standards/naming.md
---

# The share axis

Naming-standard decision D-83. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

closed values `core` (everyone who installs Harbor), `hub` (the members of one company layer), `workload` (whoever uses that workload repo or its pack), `personal` (the owner only); the terms are class `share`, and `workload` is the D-6 term. `kinds.tsv` column `share` is the SET of values a kind may take, comma-separated. An instance's share is derived from where it lives: under the harbor checkout `core`, under a workload repo (its `harbor-pack/` included) `workload`, under `harbor-private` `personal` (its `hub/` part `hub`); it must be in its kind's set. The lint requires the column; `bin/lint-share.sh` derives the share from the location and checks it against the set, in warn mode (harbor#1274). Amended by harbor#1149: `private` split into `hub` and `personal`. Revises the first draft, which gave each kind one value. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: §13.
