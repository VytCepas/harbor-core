# The estate boundary — who owns what, and what crosses

One page for the question "where does this belong?", written because on
2026-09-15 the answer was spread across four trees and two registries that
disagreed. Harbor holds it because harbor is L0: it is the only tier that sees
all of them, and it consumes the others rather than being consumed
([README.md](./README.md) — *dependency points down*).

**This page names directions and probes, never counts.** A tally of references
written here is a copy of the trees it describes and drifts silently while
reading correctly (`DOCTRINE/doc-truth.md`). Where a number matters, the command
that derives it is given instead.

## The trees

| Tree | Tier | Owns | Repo | Visibility |
|---|---|---|---|---|
| **harbor** | L0 Helm | the constitution, the security floor, guards, lint, the skill sources, the check registry, and the **access card format and checker** (the cards themselves are private data, `harbor-private/access/`) | `VytCepas/harbor` | private |
| **the workload trees** | work | the work this box governs: each workload repo owns its subject | the registry, `sh bin/roots.sh --repos` | private |
| **the trio** | L2/L3/Log | Fleet (`projects-orchestrator`), Yard (`project-init`), Log (`helm-log` = `~/.claude/MEMORY`) | see below | **two are PUBLIC** |

**Which workload tree owns what is private data.** The per-repo rows, the cautions about trees that are not repos, and
the crossings between them are the private layer's `notes/boundary.md` (`sh bin/roots.sh --private`, harbor#1273). Core
names no workload repo; with no private layer there is no such page, and this one is the whole of the rule.

**Two of the trio are PUBLIC** — `project-init` and `projects-orchestrator`
(`gh repo view --json visibility`, 2026-09-15). Every other tree here is private.
That is the sharpest boundary on this box, and each of those two carries a rule
pack saying so at the moment of a commit. `helm-log` is private, which is what
lets `~/.claude/MEMORY` have a remote at all under CONSTITUTION §3.

## The rule

**Ownership follows the SUBJECT, except where the subject is a mechanism.**

- A fact about a *client*, or about a *workload as a system* → the workload repo that owns that subject.
- A *mechanism* — a guard, a checker, a skill, a card — → harbor, whatever it is
  about. This is the exception that was got wrong once and reverted: the ACCESS
  cards were moved into a workload repo on the theory that access to a system
  is that workload's. It is not. A card is access
  *mechanics* — identity, grant, the command that proves the door opens —
  identical in shape whatever the door, and **the identities are
  shared across clients**, so ownership by subject cannot hold. They moved back
  the same day, and on 2026-10-11 into the private layer (`harbor-private/access/`, harbor#1149): a card names accounts, so core keeps the format only.

## What crosses, and what proves it still does

A workload repo declares its own crossings with runnable probes, in a manifest that repo checks itself; harbor's half is
the access cards client maps cite, `check-topology.sh` and the skills that cite a workload's paths. The map of who
crosses into whom is private, beside the trees (`notes/boundary.md`).

*A cross-repo citation is a home-rooted path or a registry lookup, never a `../<repo>/…`
link: a sibling repo is not in this checkout, so such a link resolves on the box,
where the trees sit side by side, and is dead on every runner — the same
green-here-dead-there failure the constitution's own path-root header records.*

**A one-way manifest cannot express an inbound crossing**, and inbound rows carry no probe. That
asymmetry is a real blind spot: an inbound row once claimed a directory that never existed,
and nothing caught it until it was read by a person.

## The two registries, and which answers what

They are not duplicates — they answer different questions — but they drifted
apart, so both are named here.

| Registry | Question | Owner |
|---|---|---|
| `harbor-private/context-rules/user/projects.tsv` (`inject.d/box/` until it moves) | *what should a session be told exists?* | harbor (private layer, harbor#1149) |
| `projects-orchestrator/fleet.yaml` | *what should the fleet report health for?* | Fleet (gitignored, machine-specific) |

Lint `IJ2` binds each registry row to a rule pack, `IJ3` walks the box for
governed repos with no row, `IJ4` asserts every pack is installed where the
engine reads it, and `IJ5` asserts every row still resolves to a directory.

**IJ5 exists because the first four did not.** All of them walked *repo → row*.
None walked *row → repo*, so a row pointing at a directory that no longer exists
was dropped by `project-pointer.sh` in silence — `[ -d "$path" ] || continue`. A
row survived a repo rename that way, and every session outside the
repo was told of fewer projects than existed, two of them absent.

Its discriminator is *does any row resolve*. On a bare CI checkout every row is
missing and that is a correct machine, not a stale registry, so the rule declines
explicitly rather than reporting all of them — the false positive §2.11 forbids.
It is advisory for IJ3's reason: whether to repair a path or retire a row is the
operator's call.

## The standing questions

The investigation that produced this page. Each is cheap, and each found
something the suites did not.

1. **Does every registry row still point at a directory?** Now `IJ5`. It was the
   one question nothing asked, and it is the one that found the dead row.
2. **Does every checker's DEFAULT path still exist?** `check-routes.sh` defaulted
   to a deleted directory and failed loudly; `check-topology.sh` derived the card
   store from `ESTATE_DIR` and went **quiet**. The quiet one is the dangerous one:
   a guard that stands down when its subject is absent reads identical to a guard
   that passed.
3. **Did a move leave the source and the deployed copy disagreeing?**
   `sh bin/skills-install.sh --live` and `sh bin/inject-install.sh --live` both print drift
   without writing.
4. **Is anything private about to become public?** `git grep` over TRACKED files
   in the two public repos — it asks what is *published*, not what is on disk.
5. **Does an unmerged branch resurrect something that was moved?** Worktrees of a
   workload repo still held the old `ACCESS/` at the old path.

`sh bin/reference-check.sh` answers a related question — hooks, pins, the
constitution's own citations, and skill citations — but its scope is the
installed surface, not the registries, which is why it was green throughout.
