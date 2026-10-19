---
kind: decision-record
status: accepted
alias: D-85
date: 2026-10-10
source: standards/naming.md
---

# Client terms leave core

Naming-standard decision D-85. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

core `terms.tsv` carries no `client` row. The lint also reads `harbor-private/terms.tsv` as an overlay of lowercase `client` and `system` TERMS only, same columns. Absent: no error. Malformed (header, column count), a class other than `client` or `system`, a repeated id, or an id that is a core term or a core alias: a block finding, shown by `--check` too. CRLF and a BOM are stripped with a warning. Leak-gate patterns (domains, email domains, account ids, regexes) are not terms: they go in `harbor-private/leaks.tsv`, which the future leak gate reads (#1149 lane 5). `--self-test` ignores the overlay. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: header, §10, §13.
