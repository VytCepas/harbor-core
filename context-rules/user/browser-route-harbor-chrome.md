---
order: 65
description: Refuses Claude in Chrome on a host that harbor chrome already covers
event: PreToolUse
tool: mcp__claude-in-chrome__navigate|mcp__claude-in-chrome__browser_batch
when: always
run: browser-route.sh
once: never
---

<!--
`once: never` because this is a refusal, not a reminder: a second Claude-in-Chrome
navigation to ads.reddit.com must be refused exactly like the first. The script is
silent for every host `harbor chrome` does not cover, so `never` costs nothing
there. See browser-route.sh for why the host list is read, not copied.
-->
