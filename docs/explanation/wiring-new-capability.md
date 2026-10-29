# Wiring — a capability that does not reach the moment of use is not built

**On-demand.** The rules are in [policy/constitution.md](../../policy/constitution.md) § *Fix the
system, not your notes* and § *Context sufficiency*. This is the delivery half of
both, and the checklist for adding anything new.

**Load when:** registering a repo, writing a skill, adding a client, adding a
check, or explaining why a correct rule was ignored anyway.

## The finding this exists for

An estate-wide audit on 2026-09-16 asked how bad the agent-instruction layer was.
The answer was not what the question expected:

| Layer | Verdict |
|---|---|
| Security floor | `floor-verify --live` — present, wired, blocking |
| Dependencies | `doctor` — every probed dependency present |
| Conventions | `lint-conventions` — clean; it prints the rule count, so this table does not carry a copy of it |
| Reference integrity | `reference-check` — every hook, pin and citation resolves |
| Routing content | every tracked skill carries `USE WHEN` triggers — lint **T11**, so this table does not carry a count of them either (it read *50 skills*, undated, harbor#490) |

Nothing was wrong with the rules. What failed was **delivery**: four places where
correct, well-written content never reached the turn that needed it.

1. **Memory was keyed to the working directory**, so a session started in a
   governed repo loaded none of it. Measured: **291 notes** under the `$HOME`
   key, **10 of 10 governed repos** starting blind, the measurement repo among them. The
   inversion is the cruel part — the notes most worth having in a repo are the
   ones written while working in it, and every one had been filed from a `$HOME`
   session and was therefore invisible exactly where it applied.
   `memory-store-topology.md` had recorded the mechanism since **2026-08-02** and
   nothing acted on it, because a note about a routing defect is itself subject
   to the routing defect.
2. **The pack that routes to the measurement skills fired on `cmd-prefix <tool>`** —
   a container CLI — while the design happens earlier, in `Write`/`Edit` under
   `CLIENTS/`. A note that waits for the CLI arrives after the choice it was
   meant to inform.
3. **The workspace-and-container pin was enforced for Python and not for
   TypeScript**, and the repo's only TypeScript write path served the client with
   no manifest.
4. **The registry counted seams in prose.** `check-seams.sh` printed a hardcoded
   `6 seams intact` and would have gone on printing it after a seventh was added.

## The principle

> **Content is not delivery.** A rule, a note or a skill is finished when
> something puts it in front of the turn that needs it — not when it is written
> and correct.
>
> Every claim of the form *"but it is documented"* is a claim about a file. The
> question is always which mechanism carries it, and at what moment.

The corollary is the one that costs: **a routing defect hides itself.** A missing
guard produces a visible failure; a note that never loads produces *ordinary work
done slightly worse*, forever, with nothing to notice.

## The checklist — what wiring each new thing needs

| You are adding | It is not wired until |
|---|---|
| **A repo** | it has a row in the private layer's `projects.tsv` (`bin/scope-roots.sh --projects`; lint IJ3 walks the other way), a memory route (`bin/memory-route.sh --live --apply`, lint **IJ6**), and a `context-rules/<name>/` directory, its own or seeded from the private layer's, if it has rules of its own (lint IJ2) |
| **A skill** | its description carries `USE WHEN` **trigger phrases** (lint **T11**) — `repo-skills.sh` emits the triggers, not the prose, and a skill without them is installed, invisible and unreachable. Plus a row in `skills/README.md` (T10) |
| **A hidden skill** (`disable-model-invocation: true`) | `skill-catalog` indexes it, and something names its **path** — a hidden skill cannot be invoked, but its `SKILL.md` can always be read |
| **A client** | a `client.toml` if anything in the directory can write to a vendor API (`check-seams.sh` seam 5b). A directory holding only documents needs none, and demanding one would be the false positive §2.11 forbids |
| **A check** | a row in [docs/reference/checks.md](../reference/checks.md), a `[check:<id>]` stamp on every line, a caller that is not a test (lint **C8**), a suite in `contracts/suites.txt` (C3) with paths in `contracts/suite-paths.txt` (C5), and a row in `contracts/cli.md` (CLI1) |
| **An inject pack** | a moment, a citation to where the rule already lives, and a falsifier — plus a fire row **and** a silent row in `fixtures/injection-rule/notes.tsv` |
| **A count** | it is derived at runtime, never typed. See [doc-truth.md](./doc-truth.md) |

## Why `memory-route` is one store with many doors

A store per repo would re-create the same invisibility one level down and
multiply the index nobody reads. Instead every governed repo's key gets its
`memory` directory symlinked at the `$HOME` silo: one set of notes, one
`MEMORY.md`, and a note written from any repo visible from all of them.

**What it costs, stated because it is real.** The `$HOME` index is ~40 KB and
already marginally over `context-budget.sh`'s ceiling. Before this, repo sessions
paid nothing and got nothing; now they pay it. That is the intended trade — an
index that is loaded and slightly over budget beats one that is under budget
because nothing reads it — but it makes trimming `MEMORY.md` a real task rather
than a tidy one.

## What a routing fix must prove

Config, compiled and behavioural are the tiers a workload skill names, and they
apply here unchanged. `memory-route` was closed at all three, and the third is
the only one that settles it:

```
config       the symlink exists and resolves
compiled     bin/memory-route.sh --live reports green
behavioural  a real session started in the measurement repo (resolved through the repo registry) quotes a note from the store
```

The behavioural probe is `claude -p` in the target directory, asking for
something answerable **only** from loaded context. Run it **both ways** — with
the route and with it removed — because a green with no matching red proves the
session had the note, not that the route is why. Measured 2026-09-16: unrouted
returned `NONE - no memory index loaded`; routed quoted the `ugrep` note.

## The failure mode this document is itself exposed to

This file is content. It is delivered by being cited from `policy/constitution.md` and
by `reference-check` REF-5 asserting that citation resolves. If that citation is
ever dropped, this becomes another correct document nobody reads — which is the
entire subject of the document.
