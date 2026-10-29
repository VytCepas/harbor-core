---
kind: decision-record
status: accepted
alias: D-55
date: 2026-10-04
source: research/12a-reviewer.md
---

# flow repos

Naming-standard decision D-55, from standard-draft.md §12. Its whole subject is one workload's repos, so its text is private data.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/12a-reviewer.md
- Moved (harbor#1273): the text is in the private layer's `notes/repo-names.md` (`sh bin/scope-roots.sh --private`), byte for
  byte. This stub keeps D-55 citable from the registers.

## Decision

The repos under one workload root take `<domain>-<root>-<part>` names, per D-45. The names themselves are in the private layer.

## Consequences

- No other section of the standard cites it.
