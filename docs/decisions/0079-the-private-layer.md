---
kind: decision-record
status: accepted
alias: D-79
date: 2026-10-10
source: standards/naming.md
---

# The private layer

Naming-standard decision D-79. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

named `harbor-private`, data only, fixed path `$PORT_ROOT/harbor-private`; fixed entries `harbor.toml`, `repos.tsv`, `terms.tsv`, `leaks.tsv`, `access/`, `checks.tsv`, `jobs/`, `CLAUDE.personal.md`. One variable, `HARBOR_SCOPE_PRIVATE`, overrides the root. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: §13.
