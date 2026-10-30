---
kind: decision-record
status: accepted
alias: D-54
date: 2026-10-04
source: research/09b-implementation-traceability.md
---

# Domain abbreviations

Naming-standard decision D-54. The decision text is imported unchanged from standard-draft.md §12. The registered terms themselves are workload vocabulary: the record that lists them lives in the measurement workload repo, at `STANDARD/harbor-registers/0054-domain-abbreviations.md` (repo path: `sh bin/scope-roots.sh --repo <id>`, the id is in the private layer's `repos.tsv`). This stub keeps D-54 citable from core.

## Decision

**industry terms are registered as terms.tsv abbreviations; new names use the current vendor name; old tokens stay valid inside a registered dialect until touched; product CLIs keep their names**

## Consequences

- Core's terms.tsv carries no industry term; those rows are the measurement workload's.
- No other section of the standard cites it; the decision text above is its only statement.
