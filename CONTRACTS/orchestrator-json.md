# `--json` output seam (L2 Fleet → L0 Helm) — FREEZE before Helm consumes it

Helm's statusline (**L0-5**), OBSERVABILITY FLEET section (**L0-6**), WORK log (**L0-7**), and the Pulse fleet tile (**E2**) all consume orchestrator `--json`. Today these surfaces have **no schema, no version, no fixture** — a field rename silently breaks Helm at runtime, in a different repo, with no failing test. Freeze them.

## Consumed verbs (each needs a versioned JSON Schema + golden fixture)
- `projects-orchestrator snapshot --json` → the fleet board (health / branch / ci / tests / drift / cost / running). **Consumers read this via an interval-written cache file, never live per statusline tick** — `_cmd_snapshot` fans out a full-fleet scan per invocation (REVIEW F6).
- `projects-orchestrator events --json --since <cursor>` → guard/usage events
- `projects-orchestrator audit --json --digest` → governance deltas (new / resolved)
- **Cost** → sourced from `snapshot --json`'s existing cost field (**unmetered ≠ 0**). `[!]` Corrected 2026-07-23 (REVIEW F4): **no `cost` subcommand exists** (`__main__.py` specs list has no entry; `cost.py` is an internal render helper) **and `work --list --json` is explicitly disabled** (`json_flag=False`). A standalone `cost --json` is NET-NEW scope in OC-1 — build it only if the snapshot field proves insufficient, and freeze it here first.

## Contract rules
- Every envelope carries **`schema_version`**.
- **Producer** (orchestrator repo) ships the schema + golden fixtures + a producer-side test that the emitted JSON validates.
- **Helm vendors** the schemas and runs a freshness check exactly like the descriptor seam.
- **Exit codes are part of the contract** (never-raise; nonzero-without-json ⇒ Helm degrades to `fleet: unknown`).
- **Additive-only** within a version; a breaking change bumps the version and lands lock-step.

_Owner: **OC-1** (projects-orchestrator). Consumers: L0-5 / L0-6 / L0-7 / E2 (helm)._

## Measured state — 2026-08-13

This section exists because the four rules above are written in the present tense
and **none of them holds yet**, which is the one thing a frozen-seam document must
never let a reader believe. Everything here was measured, not recalled.

**Producer side (projects-orchestrator): none of the four rules.**

| Rule | Measured |
|---|---|
| every envelope carries `schema_version` | `git grep -n schema_version -- src/` → **empty** |
| producer ships schema + golden fixtures + a validating test | `ls schemas` → **No such file or directory**; no golden snapshot fixture, no producer-side validation test |
| Helm vendors the schemas + freshness check | **cannot** — there is nothing to vendor |
| additive-only within a version | unenforced; no version exists to be additive within |

**Consumer side is nevertheless LIVE, on a timer.** `com.harbor.fleet-snapshot`
(launchd, 5 min) writes `$CFG/cache/fleet-snapshot.json` — an unversioned bare
array — and `fleet-glyph.sh` reads it on **every statusline tick**. So harbor
consumes another repo's unschema'd output continuously while the seam that is
supposed to make that safe is unbuilt.

**What actually protects harbor is one property, and it is now tested.**
`fleet-glyph.sh:43` promises "absent/stale/invalid cache degrades to
`fleet: unknown`". Until 2026-08-13 only *absent* and *stale* were pinned;
*invalid* — the case this seam makes likely — was documented and untested.
`tests/hooks/statusline.fleet-test.sh` now pins all of it: an empty file, non-JSON bytes, an
object where an array belongs, a bare `null`, and 200 nested arrays each render
`fleet: unknown` and exit 0. Verified to discriminate by mutating the fallback to
a plausible `fleet: 0` — all five assertions go red.

**The limit of that protection, pinned in the same suite so it is not mistaken
for more.** Degradation triggers on *shape*, not on *types*: a well-formed array
whose fields carry `"yes"` / `"many"` / `"lots"` renders glyphs, because jq reads
a non-empty string as truthy. That is the correct trade — tightening it would let
an **additive** producer change, the one kind this seam calls safe, blank the
whole tile, which is the §2.11 false positive that gets a control switched off.
The blast radius is one wrong glyph in a statusline.

**What is still owed, and by whom.** The producer-side work is OC-1's, in
`projects-orchestrator`, and harbor cannot do it from here. Harbor's own half —
vendoring the schema and running a freshness check — is blocked on it. Until then
this document describes an intent, and the sentence above about the consumer's
degradation is the only load-bearing guarantee in it.
