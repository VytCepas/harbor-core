---
kind: decision-record
status: accepted
alias: D-69
date: 2026-10-04
source: research/12a-reviewer.md
---

# Remaining repo names

Naming-standard decision D-69, from standard-draft.md §12. Core keeps the two domains it adds; the per-repo names are private data.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Taken after reviews 09a, 09b, 10 and 11 (§12 header).
- Source: research/12a-reviewer.md
- Moved (harbor#1273): the original text names which workload repo takes which name. It is in the private layer's
  `notes/repo-names.md` (`sh bin/roots.sh --private`), byte for byte. This stub keeps D-69 citable.

## Decision

New domains **`ops`** and **`product`**, for workload repos named under D-45. Which repo joins which domain is in the private layer.

## Consequences

- standards/naming/terms.tsv cites it for the `ops` and `product` domain rows.
