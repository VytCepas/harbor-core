---
kind: decision-record
status: accepted
alias: D-3
date: 2026-10-04
source: research/08-gap-review.md
---

# Term for Helm / L0

Naming-standard decision D-3. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/08-gap-review.md
- Also cited in: research/12d-restructurer.md

## Decision

**`control plane`**. Verified: `lint-findings.sh reconcile` diffs lint output against the finding store and applies the difference, and Kubernetes' control plane includes admission.

## Consequences

- Applied in standard-draft.md: §1.2.
