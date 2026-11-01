---
kind: decision-record
status: accepted
alias: D-37
date: 2026-10-04
source: research/09a-holistic-review.md
---

# Harbor's own scope

Naming-standard decision D-37. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Source: research/09a-holistic-review.md
- Also cited in: research/12d-restructurer.md

## Decision

**`scope: project` like any repo** (operator chose this over the recommended `platform` value). Consequence to handle: inside harbor, `guard-bash` force-push rules stand down to a repo-owned `github_command_guard` that harbor doesn't have yet, and work-log push/pull and memory harvest stop for harbor sessions (`contracts/marker.md` stand-down table)

## Consequences

- Applied in standard-draft.md: §0, §2, §8, §11.
