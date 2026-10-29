# Subagent contract: roles, stop rules, the stop check

*harbor#445 item E, 2026-10-10. Files: `contracts/agents.tsv`, `context-rules/user/subagent-contract.md`, `hooks/session-subagent-check/session-subagent-check.sh`.*

## What the hooks receive

Source: <https://code.claude.com/docs/en/hooks>, sections SubagentStart and SubagentStop (read 2026-10-10).

| Event | Payload beyond the common fields | Output that works |
|---|---|---|
| SubagentStart | `agent_id`, `agent_type`. The doc's example has nothing else. **No prompt, no brief.** | `hookSpecificOutput.additionalContext`, added to the subagent's context before its first prompt |
| SubagentStop | `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `session_crons` | `systemMessage`; `decision:"block"` or `additionalContext` keep the subagent running |

`background_tasks` and `session_crons` are "scoped to the parent session, not the subagent". Each task has `id`, `type`, `status`, `description`, and per type `command`, `agent_type`, `server`, `tool`, `name`.

## Role injection: not built, by finding

A `ROLE: <role>` first line lives in the brief. SubagentStart does not receive the brief, so no hook can read the line and inject that role's contract. Every subagent gets the universal stop rules only. `agent_type` names the Claude Code agent type (`Explore`, `general-purpose`), not a Harbor role, so it cannot stand in. If the harness ever adds the prompt to the SubagentStart payload, selection becomes a lookup of `role` in `agents.tsv`.

Until then `agents.tsv` is the table a parent copies a role's row from when it writes a brief.

## agents.tsv

Tab-separated, header row first: `role model effort tools input output done_when must_not stop_rule`. Seed roles: build, review, audit, cold-read, consolidate, docs, explore. Model tiers follow the `agent-routing` skill; this table restates none of its text. Shape is held by `tests/session/agents/registry.test.sh`.

## Universal stop rules

Injected to every subagent by the `subagent-contract` pack: report once; a message saying the work is closed ends the role; stop own background work before reporting; no push, PR or merge unless the brief allows it; deliverables to the given path. The pack loads into every subagent, so the byte budget is held by the same test.

## The stop check

`hooks/session-subagent-check/session-subagent-check.sh`, CHECKS id `subagent-stop`, advisory, exit 0 on every path. It warns the operator through `systemMessage` (no non-blocking channel reaches the parent model) when:

- the agent's final message hashes the same as its previous stop (state: `$HARBOR_SESSION_STATE_DIR/agent-stop/<agent_id>`, default `~/.local/state/harbor`);
- a `background_tasks` entry with `status` "running" or "pending" has its launch receipt (`with ID: <id>`) in this agent's own transcript and is not the agent itself (a background agent's task id is its agent id, and fills its transcript). Because the array is parent-scoped, a task with no receipt, or no readable transcript, stays silent.

State files older than 7 days are removed on each stop. `log-exempt.tsv` keeps its `protocol` row for the script: stdout is hook JSON (channel 3), the permanent kind in `contracts/logging.md`, same as `reply-shape.sh`.

Falsifier: `sh tests/session/subagent/check.test.sh`.
