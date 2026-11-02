---
kind: decision-record
status: accepted
alias: D-65
date: 2026-10-04
source: research/12a-reviewer.md
---

# Repo root

Naming-standard decision D-65. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Taken after reviews 09a, 09b, 10 and 11 (§12 header).
- Source: research/12a-reviewer.md
- Also cited in: research/12b-critic.md, research/12c-organizer.md, research/12d-restructurer.md, research/13-consolidation.md

## Decision

**Kind folders + toolchain folders only** (`bin`, `src`, `vendor`, `githooks`); kind folder = kind plural; `context.d/` → `context-rules/<scope>/`, `ACCESS/` → `docs/access/`, `EVALS-DATA/` → `evals/` (eval becomes a kind)

## Consequences

- Applied in standard-draft.md: §8.
