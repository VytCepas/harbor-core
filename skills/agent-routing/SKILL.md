---
name: agent-routing
description: "Which model tier and effort each delegated agent runs on — Agent tool calls, headless `claude -p` runs, workflow agents and orchestrator launches — when to escalate, and what a brief must name so the run ends cleanly. The cheapest tier that passes the gate, chosen per call, never inherited. USE WHEN delegating to a subagent, choosing a model or effort for an agent, fanning out agents, writing a workflow or orchestrator launch, an Agent call was denied for a missing model, an agent failed and you are deciding whether to escalate. NOT FOR reviewing a diff (audit-review-fanout), or API code that calls Claude (claude-api)."
disable-model-invocation: true
owns-tools: Agent
inline-section: The table
---

# agent-routing — the cheapest tier that passes the gate

**Done looks like:** every agent you start names its `model` and, where the table says, its
`effort`. It runs on the lowest row that fits the work, and moves up a row only on evidence: a
failed gate or a refusal. The quality gates never change with the tier.

## The table

| Tier | Effort | Work |
|---|---|---|
| `haiku` | `medium` | Read-only work: search and inventory, CI and log triage, status polling, privacy and secret scans, one lens of a review, drafting from facts you supply |
| `haiku` | `high` | A scoped code change that a test or script checks: fixes with tests, debugging from a symptom plus a regression test, small features, refactors with an output-identity check, review-round fixes, doc updates, mutation runs |
| `sonnet` | `medium` | Escalation after Haiku fails a gate or refuses; work nothing can check mechanically; multi-file or cross-repo changes; merge conflicts |
| `opus` | default | Coordination, design decisions, floor and guard design, security review, final verification of a batch, and anything Sonnet failed |

**Fable is not a tier.** Anthropic's own launch table puts it below Opus 5.5 on every row, at
2.5× the price.

## Rules that are not obvious

- **Always pass `model`.** `context-rules/user/agent-model-required` denies an Agent call without one.
  It exempts a `fork`, and an agent whose definition pins a model. The pin is not a routing
  decision: `pr-review-toolkit:code-reviewer` pins `opus`. Passing `model` overrides the pin, so
  pass it.
- **Haiku defaults to `medium` effort.** A code-changing Haiku agent needs `effort: high`, where
  the trial measured it. `context-rules/user/agent-brief` names a missing effort. Never run an
  agentic task at `low`: at that level Haiku stops early and reports work as done without
  checking it.
- **A Haiku refusal is a failure, not an answer.** Haiku 5.5 has no server-side refusal
  fallback. Re-brief the same task on `sonnet` and include the refusal.
- **Escalate once, with the evidence.** The next tier gets the same brief, plus the failed gate's
  output. Never retry the same tier unchanged.
- **Concurrency is an operator decision:** no cap on agents running at once (2026-10-13; it was 5).
  Test suites still run at most 3 at a time, because suites share one machine and contention, not
  agent count, is what slows them.
- **The hook sees Agent tool calls only.** Anything else sets the tier itself: a headless
  `claude -p` (pass `--model` and `--effort`), a workflow script's `agent()`, and the orchestrator,
  whose table is `projects-orchestrator`'s `models.py` (overridable under `models:` in `fleet.yaml`).
- **A headless brief names the exact test command.** Without one, an agent runs the repository's
  full suite, often in the background, and the `claude -p` process outlives its own result. In
  the trial, 30 of 105 unscoped runs were still alive at the 15-minute kill after reporting.
  With the suite named in the prompt, 0 of 36 were.
- **Use aliases, never pinned ids.** An alias follows its tier's current model. To see what it
  means today, run `claude -p OK --model haiku --output-format json` and read the `modelUsage` key.

## The evidence, and its limits

harbor#818 carries the trial: 141 script-graded runs across 10 Harbor task types, 3 of them hard.
Haiku 5.5 at `high` passed 30 of 30. The one Haiku miss at `medium` was a harness timeout, not a
wrong answer. Sonnet 5.5 and Opus 5.5 passed every task. Cost per passed task: Haiku `medium`
$0.019, Haiku `high` $0.050, Sonnet $0.19, Opus $0.39.

**No task separated the tiers.** That shows Haiku is enough for this kind of work. It does not
show where Sonnet or Opus start to earn their price, so the Sonnet and Opus rows are judgment.
Three runs per cell cannot tell 95% reliability from 100%. Untested: open-ended design,
multi-repo coordination, ambiguous specs, runs over 15 minutes, and large diffs. Move a row when
measurement on real work says so, and record the measurement on #818.
