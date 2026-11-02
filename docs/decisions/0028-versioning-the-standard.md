---
kind: decision-record
status: accepted
alias: D-28
date: 2026-10-04
source: research/08-gap-review.md
---

# Versioning the standard

Naming-standard decision D-28. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/08-gap-review.md

## Decision

**SemVer** `standard_version`; add = minor, remove alias or change grammar = major; repos pin in `.agents/config.yaml`, `yard upgrade` moves them, fleet reports lag

## Consequences

- Applied in standard-draft.md: §8, §10.
