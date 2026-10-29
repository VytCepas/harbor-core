# PROVENANCE — vendor/archify (harbor#392)

**Upstream:** [tt-a1i/archify](https://github.com/tt-a1i/archify) tag **v2.16.0**,
released 2026-08-30. MIT. Vendored 2026-09-01.

**Why it is here and not in `vendor/skills/`.** Archify ships upstream as an agent
skill. It is vendored here as a **CLI only** — `node bin/archify.mjs` — and the
directory is deliberately outside `vendor/skills/` so that nothing reads it as a
skill and installs it. See the exclusions.

## What was excluded, and why

| excluded | reason |
|---|---|
| `SKILL.md` | Its `## Update awareness` section directs the agent, on every use, to run `scripts/check-update.mjs`, render a notice built from a **remote manifest on a server the author controls**, then acknowledge an `eventKey` back via `--ack`. The prose around it is careful — "the notice is information, not permission", "silence is never consent" — and it is still a phone-home with an ack handshake reaching the agent's context on every invocation, over a channel a third party controls (CONSTITUTION No.4). The renderers need none of it. |
| `scripts/check-update.mjs` | the phone-home itself |
| `examples/*.html` | ~715 KB apiece of rendered output; the `.json` specs are kept because `doctor` requires them |
| `archify.zip`, `CHANGELOG.md`, `ROADMAP.md`, `README*.md`, `.github/` | distribution and project furniture, not runtime |

`grep -rl -e check-update -e eventKey vendor/archify` returns nothing, and that is
the check to re-run after any re-pin.

## What is here

`bin/ renderers/ schemas/ assets/ references/ migrations/ recipes/ delta/
brand-marks/ scripts/ examples/*.json package.json LICENSE` — 2.3 MB.

`node bin/archify.mjs doctor` reports **Archify is ready**, which is the
acceptance test for a re-pin. Runtime dependencies: **none** — `package.json`
lists only devDependencies (ajv, parse5, saxes, simple-icons) and requires Node
>= 18. Nothing here reaches the network.

## How Harbor uses it

Three consumers, in the order the data moves:

| consumer | what it takes |
|---|---|
| `skills/topology/bin/topology-to-archify.mjs` | the **dataflow schema** — a `TOPOLOGY.md` Flow table becomes a spec |
| `skills/topology/bin/topology-diagram.sh` | `validate` and `render` |
| `skills/topology/bin/archify-embed.mjs` | the **rendered page**, taken apart: 16.7 KB of SVG and a scoped subset of the 186 KB stylesheet, so `report-gen.sh` carries the diagram instead of linking 710 KB beside it |
| `bin/doc-visual-check.sh` | `visual-check`, as a SECOND verifier — it reads geometry and greps zero times for contrast, ours reads contrast and nothing about geometry |

`HARBOR_ARCHIFY` overrides the path everywhere. Harbor uses **only the CLI, the
schema and the rendered output**; it does not load archify's prompts, and no
archify code was copied into Harbor's own tree.

**What upstream's own gate cannot pass, and what that costs us.**
`viewer/viewport-overflow` fires 6/6 on `examples/event-stream.dataflow.json`
rendered by this copy — upstream's own example, upstream's own checker. It is
therefore exempted in `bin/doc-visual-check.sh`, and the exemption is held honest by
a `--self-test` arm that renders that example and goes **red** the moment a
re-pin makes it pass. Everything else archify reports is taken, and it earns its
keep: `viewer/projected-text-readability` found 7px node text projecting to
5.09px under archify's own 6px floor, which `archify validate` passes cleanly and
our contrast probe cannot see.

**Two things that only look like defaults.** Archify's dataflow layout is
hard-coded — `leftX 100, colGap 215, stageW 168, rowYs [128,242,356,470,584]` —
so content never exceeds 638x716 whatever the spec says, and the viewer scales
the DECLARED viewBox into a 930px reader. A generous viewBox is therefore not
slack, it is shrinkage. And `visual_preset` never reaches geometry (four
references upstream, all stamping an attribute), so one render carries all four
looks and a report switches them with `data-preset`.

## Re-pin

The decision to keep or drop this dependency is reviewed on **2026-12-01** under
harbor#392, because upstream shipped 12 minor releases in the 11 weeks to
2026-08-30 from essentially one maintainer (164 commits to the next contributor's
24), and the comparison case — `archivy`, 3,270 stars, one maintainer, no commit
since 2023-07-25 — is what a stall looks like. To re-pin: clone the new tag, apply
the exclusion table above, run `doctor`, run
`sh skills/topology/bin/topology-diagram.sh --self-test`, and re-run the grep.

**A pin is why a stall costs nothing.** If upstream stops, this copy keeps
working; nothing here auto-updates, and that is the point.

## Local modification — the dataflow grid, 2026-09-04

**Upstream caps a dataflow at five rows. This copy allows six.** Two lines in
`renderers/dataflow/render-dataflow.mjs`:

- `rowYs` gains a sixth stop at `698`, on the same 114px pitch as the other five
- the default `viewBox` is derived from the grid a spec actually uses instead of the
  constant `[940, 720]`, and only ever GROWS — `Math.max(940, …)`, `Math.max(720, …)`

**Why.** A whole-estate map is the diagram this repo most wants and the one the cap
refuses. Measured on a client estate: 23 systems fitted only after merging two of them
and moving a third to a stage it did not belong in, and a larger client will not fit at
all. The cost is measured too — a sixth row takes the fitted scale from **0.921 to
0.843** on a 1180×700 stage, about 8% smaller nodes for 20% more capacity.

The derived box is the half that matters for correctness: without it a six-row diagram
that declared no `viewBox` would draw its last row 110px below the bottom edge, clipped,
with nothing reported.

**Verified:** all six client diagrams re-render **byte-identical** under the change, and a
30-node 5×6 probe validates clean (9 artifact checks, 0 errors) with a derived box of
`1104×830` holding the last row at 698–756.

**Not changed: the five-STAGE cap.** `schemas/dataflow.schema.json` is raised to 6 here,
but the runtime reads `renderers/shared/generated-validators.mjs`, a COMPILED artefact,
and `scripts/generate-validators.mjs` needs **ajv 8** (`ajv/dist/2020.js`). This box has
only ajv 6.15.0, in a workload repo. Regenerating means installing a dependency into a tree that
deliberately vendors no dependencies — an operator decision, not a silent one. Hand-
editing the generated file is refused: `npm run check:validators` exists to catch exactly
that drift.

**On the next re-vendor**, re-apply both renderer lines and re-check this section.

## Local modification — the checker's exit, 2026-10-19

`scripts/check-render-output.mjs` printed its JSON report and then called
`process.exit()`. On a pipe, which is how `archify validate` reads it, that cut the
report at exactly 65,536 bytes, so `validate` died on `JSON.parse` for any drawing
whose report is larger: measured on an 18-part, 27-edge atlas drawing with 144
composition warnings. One line now sets `process.exitCode` instead, letting stdout
drain. `tests/skill/archify/report-pipe.test.sh` renders
`fixtures/archify/fanout-architecture.json`, asserts its report is over 64 KB, and
asserts `validate` passes; on the unpatched line it reads 65536 bytes and goes red.
**On the next re-vendor**, re-apply that line unless upstream has fixed it.

**Licence (harbor#1149):** MIT, `LICENSE` beside this file, upstream https://github.com/tt-a1i/archify (tag v2.16.0); listed in the root `NOTICE`.
