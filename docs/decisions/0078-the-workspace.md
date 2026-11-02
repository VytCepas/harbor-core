---
kind: decision-record
status: accepted
alias: D-78
date: 2026-10-10
source: standards/naming.md
---

# The workspace

Naming-standard decision D-78. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

`$PORT_ROOT` (default `~/port`); its top level is the closed set `harbor`, `harbor-private`, `.worktrees`, `.scratch`, `history` and the repos in `harbor-private/repos.tsv`; worktrees live at `.worktrees/<repo>/<branch>/`. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: header, §13.
