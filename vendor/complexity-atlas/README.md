# complexity-atlas

A single-file React artifact mapping complexity science as a navigable atlas:
**57 concepts, 23 frameworks** (2 anchors, 12 productive, 9 metaphysical),
15 examples, 10 methodology pages, and an Agentic Systems tab. Anchored on
Structural Realism × Information Theory.

Frameworks covered include Algorithmic Information Theory, Computational
Mechanics, Causal Inference (Pearl), Causal Emergence (Hoel), Active Inference
(Friston), Evolutionary Dynamics, Network Science, Stochastic Thermodynamics and
Assembly Theory, alongside the metaphysical systems (Powers/Dispositionalism,
Process Philosophy, New Mechanism).

## Why it is HERE and not in a skill

It is reference material for the reasoning skills — `systems-thinking`,
`first-principles`, `science`, `iterative-depth`, `aperture-oscillation` — and
the obvious home was `vendor/skills/systems-thinking/references/`.

**It is 840 KB, and that is the reason it is not there.** Nothing under
`vendor/skills/` exceeds 200 KB today and the largest whole skill is 128 KB, so
placing it inside one would make that skill roughly seven times the size of the
biggest, and `bin/skill-install.sh` copies skill directories into
`~/.claude/skills` on every install — the weight would land in the live tree for
every session, to serve a file read on demand by a few.

So it sits beside `vendor/archify/`, which is the existing pattern for a large
vendored asset that is **not** installed as a skill. The cost of that choice is
discoverability, and this README plus the cross-reference below is what pays it.

## Reading it

It is a `.jsx` module (React, `useState`/`useMemo`, no external deps beyond
React) — a source artifact, not a built page.

## Provenance

Authored as a Claude artifact; merged revision dated 2026-08-29. Filed here
2026-09-02 from `~/Downloads`.
