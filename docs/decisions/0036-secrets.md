---
kind: decision-record
status: accepted
alias: D-36
date: 2026-10-04
source: research/08-gap-review.md
---

# Secrets

Naming-standard decision D-36. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/08-gap-review.md
- Also cited in: research/09a-holistic-review.md, research/09b-implementation-traceability.md, research/12d-restructurer.md

## Decision

**`<system>-<service>-<identity>-<purpose>`** in stores, `<REPO>_<SERVICE>_<PURPOSE>` for env vars; never a value, client data or email in the name

## Consequences

- Applied in standard-draft.md: §4.
