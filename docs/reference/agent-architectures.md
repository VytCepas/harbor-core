---
kind: reference
owner: harbor#1278
status: unreviewed
---

# Agent architectures

Every case that uses subagents follows one written architecture. The table is `contracts/agent-architectures.tsv`, the second table of the role register: its roles are the rows of `contracts/agents.tsv`, and it adds how many, which tier, what each agent gets and returns, who verifies whom, and when to stop.

| Architecture | Roles (count, tier) | Verified by |
|---|---|---|
| `decision-check` | `verify` x1, opus/high | the parent's claims, by `verify` |
| `code-review` | `review` x1-9 haiku/medium, `audit` per finding sonnet/medium, `verify` x1 opus/high on disagreement | lens findings by `audit`, a split by `verify` |
| `analysis` | `explore` x1-3 haiku/medium, `verify` x1 | the report's claims, by `verify` |
| `test-writing-trivial` | `build` x1 haiku/high (under 20 changed lines, no new interface) | the parent re-runs the runner and the reverted run |
| `test-writing` | `build` x1, `audit` x1 sonnet/medium | the test, by an `audit` agent that breaks the guarded code and sees red |
| `research` | `explore` x2-4 haiku/medium, `verify` x1 | the claims, against the sources read for them |
| `fix` | `build` x1, `audit` x1 | the fix, by `audit` re-running the done-when; one escalation to sonnet/medium |

- **A verifier is never the agent that produced the claim.** Each row's `verified_by` is `producer>verifier` pairs; `parent` is the session that spawned the agents.
- **A tier in a row is an override.** A role with no `@model/effort` runs at its `contracts/agents.tsv` tier. `build` is haiku/high, as the `agent-routing` skill's scoped-change row says; multi-file work or a failed gate moves it to sonnet/medium there.
- **A skill that spawns agents names its architecture** in front matter (`architecture: <id>`, or `all` for the routing skill). Lint `skill.agent-architecture` is red for no name, an unknown name, a malformed row, a role `agents.tsv` lacks, or an agent verifying itself. The company law (`contracts/member-law.md` section 2) names `decision-check`.
- **No hook enforces it at run time.** SubagentStart does not receive the brief (`contracts/subagent.md`), so the architecture binds through the skill and the brief, and the lint holds the written side.
