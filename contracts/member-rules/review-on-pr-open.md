---
order: 50
description: A pull request just opened draws one note to review it against the company rules before it merges (the member route of check session.review)
event: PostToolUse
tool: Bash
when: cmd-prefix gh pr create
when: content-contains /pull/
once: match
---

You just opened a pull request. Before it merges, review it with the audit-review-fanout skill: run the repository's own lint commands first, then its reviewers, one small model each, including the three standards reviewers, then have every finding checked by an agent that did not raise it. Report the confirmed findings to the person you work for, and change nothing they did not ask for. If you are a helper agent, say in your final report that the pull request still needs this review, so the agent that started you runs it.
