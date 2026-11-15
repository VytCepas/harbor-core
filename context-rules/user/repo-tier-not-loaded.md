---
order: 95
description: Reports the repo rules a session started elsewhere is not loading
event: PreToolUse
tool: Bash|Read|Write|Edit|MultiEdit|NotebookEdit|Grep|Glob
when: always
once: session
run: repo-tier.sh
---

<!-- tool: lists the calls that carry a path, a command or a cwd: with none, every MCP call (harbor chrome above all) woke the engine for nothing (harbor#1507). -->
