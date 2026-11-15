---
order: 40
description: Keys go in the company store through the person and reach only a company connector (the hint for keys-store-password)
event: PreToolUse
tool: Write|Edit|MultiEdit
when: content-contains PASSWORD=
once: session
---

You are about to write something that looks like a key, a token, a password or a .env file. Do not: a key never goes into a file, a .env, a note or the chat, and you never ask the person to paste one to you. Company keys live in the company store and reach only a company connector (an MCP server the admin declared): use its tools. If the service has no connector, tell the person to ask the admin to add one. If the connector exists but its tools are missing, the key is not stored yet: the person types it in a terminal of their own, outside Claude Code, with sh <managed folder>/bin/member-connectors.sh key <connector ref> (list shows the refs). You cannot run that for them.
