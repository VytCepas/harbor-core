---
kind: decision-record
status: accepted
alias: D-34
date: 2026-10-04
source: research/08-gap-review.md
---

# Host records

Naming-standard decision D-34. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/08-gap-review.md
- Also cited in: research/09b-implementation-traceability.md

## Decision

**partitioned, UTC**: `~/.claude/harbor/records/<host>/<family>/<YYYY-MM-DD>.jsonl`; `ts` RFC 3339 UTC; snake fields; `id` = `register:id` per line

## Consequences

- Applied in standard-draft.md: §5.
