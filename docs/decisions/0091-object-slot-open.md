---
kind: decision-record
status: accepted
alias: D-91
date: 2026-10-27
source: harbor#1259
---

# The object slot stays open

Naming-standard decision D-91. Settles whether the allowlist validators close the object slot.

## Context

- Operator decision, 2026-10-27 (harbor#1259, the per-surface validators under the naming epic #949).
- The grammar leaves the object slot free (D-38: free, but checked for aliases and abbreviations), so a validator derived
  from the grammar checks shape and family but not vocabulary: a client name in the object slot passes it.

## Decision

**The object slot stays open.** The validators in `build/validators.txt` and the `name-check` helper check shape and
family only. The object slot is not closed through `standards/naming/terms.tsv` rows. No leak consumer may claim
object-slot coverage from a validator; the denylists (`lint-leaks.sh`) and the lint's alias rules keep that job.

## Consequences

- Closing the object slot through `terms.tsv` is deferred, not rejected: it is a later decision with its own list of
  object words, and it reopens this record rather than replacing it.
- A name that a validator accepts can still draw a vocabulary finding from `lint-name.sh`; the two are not the same answer.
