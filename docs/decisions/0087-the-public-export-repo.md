---
kind: decision-record
status: accepted
alias: D-87
date: 2026-10-15
source: standards/naming.md
---

# The public export repo

Naming-standard decision D-87.

## Context

- harbor#1149: the public core is a snapshot export to a new repo; the private development repo stays as is.
- Decided by the operator, 2026-10-15.

## Decision

The public core export is `harbor-core` (the codename `harbor` plus the share term `core`, D-83); the private development repo keeps `harbor`. Known collision with the CNCF Harbor registry and its `harbor` CLI (goharbor/harbor-cli): accepted for a quiet repo, to revisit before any announcement.

## Consequences

- Revisit the collision before any public announcement.
