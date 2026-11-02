---
kind: decision-record
status: accepted
alias: D-46
date: 2026-10-04
source: research/09b-implementation-traceability.md
---

# Stand-down fix

Naming-standard decision D-46. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/09b-implementation-traceability.md
- Also cited in: research/12a-reviewer.md

## Decision

**hand off only to a present guard**: `guard-bash` force-push rules stand down only when the repo wires `github_command_guard`; work-log and memory-harvest stand down only on an explicit `worklog: off` in the marker

## Consequences

- No other section of the standard cites it; the decision text above is its only statement.
