---
kind: decision-record
status: accepted
alias: D-59
date: 2026-10-04
source: research/10-hierarchy-modularity.md
---

# Families across systems

Naming-standard decision D-59. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Taken after reviews 09a, 09b, 10 and 11 (§12 header).
- Source: research/10-hierarchy-modularity.md
- Also cited in: research/12a-reviewer.md, research/12e-engineer.md

## Decision

**One global family set** for every platform system; a module that fits none gets a new family only via a registry PR with depth evidence (M5); workloads fill the slot with a registered `area`; the fleet/yard mapping table is reviewed by the operator before any move

## Consequences

- No other section of the standard cites it; the decision text above is its only statement.
