---
kind: decision-record
status: accepted
alias: D-81
date: 2026-10-10
source: standards/naming.md
---

# The config format

Naming-standard decision D-81. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

`harbor.toml`, not `harbor.conf` (this revises the wording of DESIGN.md, which said `harbor.conf`); `pack.toml` and `harbor.toml` share one flat TOML subset that POSIX awk reads. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: §13.
