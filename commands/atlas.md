---
description: Build or update an architecture atlas from archify specs, into a dated deliverable folder
argument-hint: [system to draw, or the deliverable folder to update]
---

Build an architecture atlas for: **$ARGUMENTS**

Load the `doc-atlas` skill and follow it. The short form:

1. **Find the specs.** archify `.json` specs with their rendered `.html` beside them —
   usually `docs/reference/diagrams/`. If the specs do not exist yet, they come from a
   TOPOLOGY.md via `topology/bin/topology-diagram.sh`, not from here.

2. **The folder is the deliverable.** `~/Deliverables/<YYYY-MM-DD>-<slug>/`, holding
   `atlas.config.json`, `components.json` and the built page together. **Updating an
   existing atlas means rebuilding in its existing folder** — a second folder is a second
   answer to the same question.

3. **Describe every component** in `components.json`, under the enforced ceilings —
   `kind` 4 words, `role` 12, facts 3/8 words over at most 4 rows, `why` 26, `sources` at
   most 6 real repo paths. The build refuses otherwise, and it refuses a component the
   spec has but the descriptions do not.

4. **Build and prove it in one command:**

   ```sh
   python3 ~/.claude/skills/doc-atlas/build/build.py atlas.config.json --check
   ```

   Exit 0 is green. **Exit 127 means node or playwright is missing — a deferral, not a
   pass**, and must be reported as one.

5. **Hand it over as a `file://` link**, after `open`-ing it. Never publish it to a host.

Report the link and one line per diagram — parts and connections. Not a description of
the page; the person is about to look at it.
