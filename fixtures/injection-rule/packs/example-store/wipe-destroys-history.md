---
id: example-wipe-destroys-history
event: PreToolUse
tool: Bash
when: cmd-contains example-tool
when: cmd-contains --wipe
once: match
---

Fixture pack, never installed (harbor#1149). It gives the default inject-notes run a pack that stacks two
`cmd-contains` predicates, the shape the private layer's repo packs depend on and no shipped pack uses.
