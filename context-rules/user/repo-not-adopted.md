---
order: 52
description: Names each repo under the workspace root with no registry row or a governed=no row, with the harbor repo adopt command for it
event: SessionStart
when: always
once: session
run: repo-not-adopted.sh
---

<!--
harbor#1278: every new project starts with yard and is integrated into fleet. A repo made by a bare `git init`,
a clone, or a terminal outside any session is in no registry, carries no kit and is judged by no gate, and no
guard sees it being made. This reads the disk instead: bin/scope-repo-sources.sh --not-adopted lists each git
checkout at depth 1 of PORT_ROOT with no registry row (unregistered) or a governed=no row (ungoverned), and the
note gives the `harbor repo adopt` command for each. The definition stays in that one script.

ADVISORY: a finding, never an order. Adopting writes into the repo and the registry, so the note tells the agent
to name the command to the operator, not to run it. Silent when the list is empty, when the script is absent or
fails, or when there is no registry (exit 3).

Falsifier: tests/context/injection-rule/repo-not-adopted.test.sh (fires on a fixture git dir with no row and on a
governed=no row, silent on a governed repo, a non-git dir and the private layer, and red when the .git test breaks).
Off: set the mode cell of context.repo-not-adopted in standards/naming/controls.tsv to shadow.
Retire: delete this file and repo-not-adopted.sh, then `harbor inject --live --apply`.
-->
