---
kind: decision-record
status: accepted
alias: D-58
date: 2026-10-04
source: research/10-hierarchy-modularity.md
---

# Where a level shows; what `system` means

Naming-standard decision D-58. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Taken after reviews 09a, 09b, 10 and 11 (§12 header).
- Source: research/10-hierarchy-modularity.md
- Also cited in: research/12a-reviewer.md, research/12d-restructurer.md

## Decision

**Flat-surface rule:** a flat namespace carries the grouping it flattens as a prefix, a nested one as a folder, never both. The system term is the short name (`<name>`), used in references, env prefixes and dialect owners; the repo name renders it with its domain (`<domain>-<name>`)

## Consequences

- Applied in standard-draft.md: §2.
