---
id: repo-skills-pointer
description: Names the repo-scoped skills the session cannot see, with the path to read each
event: SessionStart
when: repo-has .claude/skills
once: never
run: repo-skills.sh
---
