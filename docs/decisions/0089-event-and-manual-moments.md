---
kind: decision-record
status: accepted
alias: D-89
date: 2026-10-24
source: harbor#950
---

# Two more moments: event and manual

Naming-standard decision D-89. Extends the `moment` class of `standards/naming/terms.tsv`.

## Context

- Operator decision, 2026-10-24 (harbor#950, the research note of 2026-10-14).
- 50 of the 52 `check` rows in `controls.tsv` said `moment=schedule`, while `CHECKS.md` called 23 of them
  "not scheduled". The share of checks started by events could not be derived from the register.

## Decision

**The `moment` class gains `event` and `manual`.** `event` (also a family, D-77): started by an event it
receives — a bus line, a host notification, an incoming signal — not by a timer or a harness hook. `manual`: a
person or a session runs it on demand. Each `check` row carries the moment its own trigger matches: a harness
hook is `runtime`, a check inside a timed run is `schedule`, and a row in `floor-verify --live` is `deploy`.

## Consequences

- `awk -F'\t' '!/^#/ && $3=="check"{m[$6]++} END{for(k in m)print m[k],k}' standards/naming/controls.tsv`
  derives the split; on the day of the decision it printed 21 schedule, 11 event, 8 runtime, 7 manual, 3 ci,
  2 deploy.
- `check.memory-route` is `ci` like every lint row, although lint IJ6 runs it only on a local push.
