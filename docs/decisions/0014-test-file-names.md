---
kind: decision-record
status: accepted
alias: D-14
date: 2026-10-04
source: research/09b-implementation-traceability.md
---

# Test file names

Naming-standard decision D-14. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/09b-implementation-traceability.md
- Also cited in: research/11b-tests-lint-ci.md

## Decision

**one folder per subject**: `tests/<family>/<subject>/<aspect>.test.<ext>`; Python keeps `test_<aspect>.py`; no dots or `--` inside names

## Consequences

- Applied in standard-draft.md: §0, §4.
