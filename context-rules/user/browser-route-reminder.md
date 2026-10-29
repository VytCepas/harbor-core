---
order: 66
description: Logged-in browser work goes through harbor chrome first
event: PreToolUse
tool: mcp__claude-in-chrome__.*
when: always
once: session
---
Logged-in browser work on this box goes through `harbor chrome` first — Playwright
in the operator's own Chrome profile (CONTRACTS/browser-routing.md, row 4) — and
Claude in Chrome is only its fallback. `harbor chrome` is a CLI, not an MCP, so
ToolSearch will never show it. If the site you are opening is a vendor or ad
platform UI that is not yet in `CONTRACTS/browser-agent-hosts.txt`, the fix is to
add the host there in a reviewed PR, not to switch tools; a site Claude in Chrome
refuses (ads.reddit.com) is not "blocked" until `harbor chrome` has been tried.
