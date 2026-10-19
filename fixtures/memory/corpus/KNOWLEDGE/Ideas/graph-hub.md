---
title: Graph hub
type: Idea
tags: [graph]
related:
  - alan-turing
  - nope-either
---

A fixture hub with outbound links: [[ada-lovelace]] and [[acme-corp]] both
resolve; [[does-not-exist]] does not, and neither does the frontmatter entry
`nope-either`. Two dangling references, one from each dialect.

It also links to [[graph-hub]] — itself. A self-link is not an edge and must not
appear in the edge count; without this line the guard that drops it is never
exercised by any test.
