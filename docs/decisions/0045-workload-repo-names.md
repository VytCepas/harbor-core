---
kind: decision-record
status: accepted
alias: D-45
date: 2026-10-04
source: research/08-gap-review.md
---

# Workload repo names

Naming-standard decision D-45, from standard-draft.md §12. Core keeps the rule; the per-repo renames are private data.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/08-gap-review.md
- Moved (harbor#1273): the original text lists which workload repo takes which name, which is this operator's data. It is
  in the private layer's `notes/repo-names.md` (`sh bin/scope-roots.sh --private`), byte for byte. This stub keeps D-45 citable.

## Decision

**`<domain>-<name>`** (#948): a workload repo is named for its domain, then itself. Which repo takes which name is in the private layer.

## Consequences

- Cited by standards/modularity.md, standards/naming/surfaces.tsv and repo-kinds.tsv for the rule alone.
