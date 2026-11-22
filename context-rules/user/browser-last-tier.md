---
order: 68
description: Opening a vendor UI in harbor chrome names the cli or api route its card ranks above the browser
event: PreToolUse
tool: mcp__harbor_chrome__goto|mcp__harbor_chrome__tab_new|mcp__harbor_chrome__steps
when: always
run: browser-last-tier.sh
once: never
---

<!--
harbor#1507. access/ROUTING.md ranks the tiers cli > api > mcp > browser, and nothing applied it at the moment a session
opens a vendor UI (measured 2026-10-18..11-14: the most-opened hosts were vendor UIs whose card has a cli or api route).
Prose in a policy file does not bind; a note at the call does (docs/reports/evals.md E6: 0/4 as prose, 4/4 injected).

INFORM HERE; THE CHROME SERVERS DENY. The operator approved the refusal on 2026-11-20 ("api access as priority", enforced): both
harbor_chrome servers call browser-last-tier.sh --check and refuse a mapped vendor UI unless the call carries --ui=<why>
(contracts/browser-routing.md, "enforced for agents"). This note still speaks once per system for every other route.

ONE SOURCE. The host-to-system mapping is each card's `ui-hosts:` field (contracts/access-card.md, checked by
skills/access-ledger/bin/check-routes.sh), read from the private register at the call; core names no vendor and no client host.
`steps` is matched and only its goto steps are read (the pack's tool: is the installer's matcher).

`once: never` because the script keeps its own ledger, one line per system per session; the engine's per-pack `once` cannot
say "per system". A register with cards and no `ui-hosts:` at all is a broken mapping and says so once a session
(the alarm), where no register at all is silent like its siblings browser-route.sh and access-route.sh.

Disable: delete this file and browser-last-tier.sh, then `harbor inject --live --apply`; the control row is
context.browser-last-tier.
-->
