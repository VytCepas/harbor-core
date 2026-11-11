---
order: 67
description: Google Sheets writes go through the Sheets connector, not a browser
event: PreToolUse
tool: mcp__harbor_chrome__goto|mcp__harbor_chrome__tab_new|mcp__harbor_chrome__steps
when: always
run: sheets-write-route.sh
once: session
---

<!--
harbor#1507, decided 2026-11-11: Sheets writes take the claude.ai Google Sheets connector. Google
Sheets was harbor chrome's largest use (2,853 calls in 45 sessions, 2026-09-30..11-11) and every
recorded wrong-cell write (#1117, 2026-10-06 and 2026-11-11): a canvas grid gives no focus a
browser verb can read. The note rides the call that OPENS a sheet, because that is the moment the
route is chosen; reading a sheet in harbor chrome stays allowed. Inform, not deny: the connector
needs the operator's one-time /mcp authorisation, and until it exists the browser recipe is the
only write path. `steps` is matched too, and its steps' args are read: a goto-and-type inside one steps call is the
very write this names (review, 2026-11-11).
-->
