---
kind: decision-record
status: accepted
alias: D-56
date: 2026-10-04
source: research/09a-holistic-review.md
---

# Remaining gap-review rules

Naming-standard decision D-56. The decision text is imported unchanged from standard-draft.md §12.

## Context

- Operator decision, 2026-10-04 (standard draft 4, §12 header).
- Scope as titled in §12: research/08 gaps 4, 9, 11, 13–16, 19–24.
- Source: research/09a-holistic-review.md
- Also cited in: research/09b-implementation-traceability.md, research/11b-tests-lint-ci.md, research/12b-critic.md, research/12d-restructurer.md, research/12e-engineer.md

## Decision

**defaults, no exception named yet**: yard's `.agents/` holds config and harness files only, scripts kebab in `bin/`; CLI options `--apply` (dry run by default), `--live`/`--dir`, `--json`, `--self-test`; PATH commands `<vendor>[-<verb>]`, no test helpers on PATH; tags `v<semver>`, release title = tag, Keep a Changelog; `system` short codes + `max_len` per surface; warehouse columns snake with `_at` (UTC), `_date`, `_id`, `is_`/`has_`, `<metric>_<iso4217>`; workflow file = purpose, job id = check name, required checks registered; host segment = lowercase alias from a host-local file; evals `evals/<family>/<experiment>/<arm>/r<N>.json`; `<name>.schema.json` with `schema_version` field, `.yaml` unless a tool needs `.yml`; exported vars follow D-15, locals snake, constants `readonly` SCREAMING, tool-owned names exempt; `dot_` template prefix tool-required; status-line tokens registered as renderings of D-29 words

## Consequences

- No other section of the standard cites it; the decision text above is its only statement.
