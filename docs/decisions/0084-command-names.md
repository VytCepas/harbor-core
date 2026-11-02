---
kind: decision-record
status: accepted
alias: D-84
date: 2026-10-10
source: standards/naming.md
---

# Command names

Naming-standard decision D-84. The decision text is imported unchanged from standards/naming.md §12.

## Context

- Decided by the orchestrator under operator delegation, 2026-10-10 (source row).
- Source: standards/naming.md

## Decision

D-13 holds: `harbor <family> [<object>] [<verb>]`, registered words only. `pack` is a new family (`terms.tsv`), the 25th after D-77's `event`. `harbor pack install <id>` and `harbor pack remove <id>`; `harbor scope install` creates the workspace skeleton and an empty `harbor-private` (replaces the draft's `harbor init`); `harbor deploy push` will publish the core snapshot to `harbor-core` (replaces `export-core.sh` and the draft's `harbor export`); it is not `harbor scope push`, because `scope` is the private configuration placement while publishing core is shipping Harbor, which is the `deploy` family. `scope` is the family for where configuration applies, which is what the share axis is; `deploy` is an existing family, and `install`, `remove` and `push` are registered verbs, so `pack` is the only family added and no verb or exception to D-13 is. `harbor scope install` is built (`bin/scope.sh`, with an amendment row in `contracts/cli.md` that CLI1 holds to existing scripts); `harbor pack install|remove` and `harbor deploy push` are reserved names, unbuilt. §13; decided by the orchestrator under operator delegation, 2026-10-10

## Consequences

- Applied in standards/naming.md: §13.
