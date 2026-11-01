# atlas — human-readable visual deliverables

> **Path root:** `~/port/harbor` — every `./`-prefixed path below resolves there, not
> against the directory this skill is installed into. Checked by
> `bin/drift-reference-check.sh` REF-9 **where the skill is READ**: the `../../` form
> this replaced was green in the repo and dead from `~/.claude/skills/atlas/`,
> which is the same defect harbor#462 fixed for `dev-tracking` and this file
> reintroduced when atlas moved out of `plugins/` (found by REF-9 on the install,
> 2026-09-07).

**Status:** created 2026-09-02 as a plugin · moved to `skills/` 2026-09-06 · owner: operator

One skill for the thing this box kept rebuilding by hand: a page whose subject is a
**drawing**, handed to a person as a local file.

```
skills/doc-atlas/SKILL.md        the ideal state, the gotchas, the contracts
skills/doc-atlas/build/          the generator, and its acceptance suite
commands/atlas.md            /atlas — build or update one
```

## It was a plugin for four days, and the premise was false

The original argument, from `UNIFICATION.md` §2: *"A plugin is loaded when its repo is
entered; `~/.claude/skills` is loaded always. The unit of control we want already exists
one layer down."*

Measured 2026-09-06: `claude plugin list` reported this plugin at **Scope: user** —
active in every session on the machine — and `claude plugin details atlas` put it at
**~398 tokens always-on**. Meanwhile a skill carrying `disable-model-invocation: true`
costs **zero**. The tier was buying nothing and cost real governance: seven of eight
Harbor gates greped `plugins/` zero times, so this tree was invisible to the context
budget, absent from the generated skill-catalog, and shipping a `check.mjs` registered in no
suite while its manifest advertised one. Retired: `./docs/explanation/no-authored-plugins.md`,
enforced by lint **X10**.

**The §2 argument still stands** — a session not building an atlas should not carry it.
The frontmatter flag is what delivers that, not the directory. Whether to set it here is
open; today this skill is still model-invocable and still spends its description bytes,
the difference being that `context-budget.sh` can now see them.

## What it owns, and what it does not

Four tools on this box produce human-readable output. The seams are real; read this
before writing a fifth.

| tool | input | output | owner |
|---|---|---|---|
| `topology/bin/topology-diagram.sh` | TOPOLOGY.md Flow table | archify **specs** | `topology` |
| **`atlas/build/build.py`** | **archify specs** | **an interactive atlas** | **here** |
| `topology/bin/report-gen.sh` | TOPOLOGY.md | a tabbed **projection of a map** | `topology` |
| `topology/bin/archify-embed.mjs` | rendered archify pages | an embeddable fragment | `topology` |

**The chain composes:** a map becomes specs becomes an atlas. Nothing here replaces
`topology`; it consumes what `topology` produces.

**`archify-embed.mjs` overlaps this skill's extraction and carries a live defect** — it
returns each `<svg>` verbatim with no ID rewriting, and its self-test passes a single
file, so the multi-diagram arrowhead collision cannot be caught by it. Any report it
builds with more than one diagram loses its arrowheads. The fix is the rewrite in
`build/namespace.py`. Not applied there; it is a tracked file in a governed tree and
belongs on its own branch.

## Adding a second kind of deliverable

A slide deck, a printed brief, a poster — those are **sibling skills in `skills/`**,
not options on the atlas. They share the deliverable rules (dated folder, `file://`
handover, never a host) and nothing else: an atlas is navigated, a deck is advanced, and
the moment one renderer tries to be both, neither is good. The shared half is small
enough to restate; the renderers are not.

## Install

Operator-gated, like every install on this box — the tracked route, byte-verified,
dry-run unless `--apply`.

```sh
sh bin/deploy.sh --only skills --apply --live   # installs every tracked skill, atlas included, into ~/.claude/skills
```

The generator needs `python3` for the build and, for `--check`, `node` with `playwright`
(this box keeps it at `~/.local/lib/browser-probes`). Without them `--check` exits **127**
— a deferral, and it says so rather than reporting a pass.
