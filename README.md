# Harbor

**One terminal → Claude → full control of host, projects, and cloud** — an agentic developer environment that composes three decoupled layers without one bleeding into another.

## New here?

Harbor is a governance layer for [Claude Code](https://code.claude.com). It installs hooks that refuse dangerous commands
before they run (the *floor*), a lint for the repos you govern, and a context architecture: what loads into every
session, and what loads only when it is needed.

- **Install:** the steps in [A fresh machine](#a-fresh-machine). They are the steps a clean-Ubuntu test runs. macOS and
  Linux; on Windows, inside WSL2.
- **What it changes:** it writes into `~/.claude` (hooks, settings, skills) and `~/.local/bin`, and one root-owned
  lockdown file through `sudo`. `deploy.sh` takes a snapshot first.
- **Is it on?** `harbor verify` fires known-blocked commands at your config dir and reports which were refused.
- **Undo:** `harbor uninstall` removes the floor, and `harbor restore` puts `~/.claude` back from a deploy snapshot.
- **Limits:** the floor is a net, not a wall. [docs/explanation/admission-baseline.md](./docs/explanation/admission-baseline.md) lists the bypasses that have been measured.
  Report a new one through [SECURITY.md](./SECURITY.md). A text guard cannot see operands that arrive on stdin
  (`xargs`), the contents of a script file when it is run, or code inside an inline interpreter; the defence for
  those is the OS sandbox and the permission layer, not the floor. `harbor#N` references point to the private
  development tracker: provenance, not links.
- **Status:** pre-release. The rest of this page is the design as its author uses it.

## What Harbor is — the thesis

**Upstream moves a person from current state to ideal state. Harbor moves a
codebase estate from current state to governed state.** Same epistemology,
different subject: Harbor is a life OS whose *life* is the agency itself.

That is why the take/leave split falls where it does ([docs/reference/coverage.md](./docs/reference/coverage.md),
[docs/reference/provenance.md](./docs/reference/provenance.md)). Contacts, health, finances, a public profile,
a daily briefing — not worse than what was kept, just **about a different
subject**. Everything Harbor took is about how the work is done, checked, and
remembered.

Four properties define it. Two are real today; two are the plan, and saying
which is which is itself rule №2.

| | |
|---|---|
| **Governed by mechanism, not by prose** | **Real.** Rules that cannot fail the build are documentation. Lint rules, frozen contracts, mutation-checked suites, a POSIX floor under everything. |
| **Scales by skills** | **Real, with a price.** 28 vendored. But an *ambient* skill costs context in every session forever — the invoked-only tier (`disable-model-invocation: true`) is what makes scaling free, and `bin/context-budget.sh` is what keeps it honest. |
| **Observes itself** | **Real, and now producing.** `floor_log_decision()` in `bin/guard-lib.sh` is called by every floor guard — harbor#41 — and the guards are installed, so the ledger is being written. This row said "producing nothing" until 2026-08-03 and was wrong on the machine it described; ask `harbor observe` for what is in it rather than believing any prose about it, including this. Built and running stay different facts — the row states which it means. |
| **Improves from what it observed** | **Not yet, and deliberately gated.** See below. harbor#744 is the workstream that builds it: capture, propose, build to standard, approve, retire. |

### Self-improvement is a proposal loop, not an autonomous one

A harness that rewrites its own guards mid-session, from a week of unreviewed
signal, is worse than one that does nothing — it converts noise into policy at
machine speed, in the layer that is supposed to be the last line of defence.
Harbor's own record argues the point: pass 9's fixes were applied confidently
and pass 10 found ~24 defects **caused by them**, with a green suite throughout.

So the loop is **observe continuously → synthesise in batch → apply behind a
human gate**, and auto-application is explicitly out of scope in harbor#41.
Upstream reached the same conclusion independently: its
`ProposeCurrentStateEntry` writes to an approval queue because *"every entity
requires explicit approval before landing"*.

The self-heal that IS legitimate without a gate is the narrow, deterministic
kind — upstream's `HookHealer` repairs one failure class (a lost exec bit) and
warns about the rest. Not "the system rewrites itself."

### The library of issues and solutions

Already three separate things, deliberately:

- **`docs/reports/rejected-approaches.md`** — approaches tried and *rejected*, append-only.
  In-repo and git-diffable because it must survive any tool being deleted.
- **`~/.claude/MEMORY/KNOWLEDGE/`** — the durable library (workstream **D**).
- **The missing middle** — what actually happened, per decision (harbor#41).
  Without it the other two are written from memory.

The format question is settled and is Obsidian-shaped **without depending on
Obsidian**: [contracts/memory-format.md](./contracts/memory-format.md) makes
markdown + YAML frontmatter + `[[wikilinks]]` canonical at every scope, and every
index — entity graph, BM25, vectors — *derived, rebuildable and gitignored*. **No
database is ever the source of truth.** Obsidian can read it; nothing breaks if
Obsidian goes away.

> *You take the **Helm** to command the **Fleet**, build each repo in the **Yard**, and it's recorded in the **Log** — all in the **Harbor**.*

## The names

| Name | What | Repo |
|---|---|---|
| **Harbor** | the whole system (this repo = planning) | `VytCepas/harbor` |
| **Helm** | **L0** — the environment you steer from; the assistant + the `harbor` command (the CLI is `harbor`, not `helm` — see [standards/naming.md](./standards/naming.md) §6.4). **Not a fork** — Harbor adopts and vendors from an upstream project at a pinned SHA (decision 2026-07-25, [docs/reference/provenance.md](./docs/reference/provenance.md)) | `VytCepas/harbor` — the L0 code lives here permanently; there is no separate repo |
| **Fleet** | **L2** — cross-repo fleet health/heal/deploy | `VytCepas/projects-orchestrator` |
| **Yard** | **L3** — per-repo scaffolder + lifecycle governance | `VytCepas/project-init` |
| **Log** | the git-backed cross-device work-log | your own private repo: the origin of `~/.claude/MEMORY` |

`Fleet` and `Yard` are **in-system call-signs** — `projects-orchestrator` and `project-init` keep their published names. Nothing is renamed on disk.

The metaphor is a working one, not decoration: a **Ship** is a governed project (it carries `.agents/` + `context: repo`), the **Yard** builds and refits ships, the **Fleet** commands them, you stand at the **Helm**, and the **Log** is the record. *Aboard a Ship vs ashore in the Harbor* is the detect-and-defer boundary ([contracts/marker.md](./contracts/marker.md)).

## A fresh machine

These are the steps `tests/install/stranger-ubuntu.sh` runs on a clean Ubuntu box, so the list is checked rather than remembered. The test's box has `git`, `jq`, `sudo` and `ca-certificates` and nothing else: no GitHub login, `gh`, `uv` or `just`, because a core install clones nothing beyond this repository. macOS and Linux; on Windows, inside WSL2 ([platforms.md](./contracts/platforms.md)).

```sh
git clone <this repository's URL> ~/port/harbor
sh ~/port/harbor/bin/harbor scope install             # the private layer, ~/port/harbor-private, with components = ["core"]
sh ~/port/harbor/bin/deploy-bootstrap.sh                     # clones what harbor.toml names (core: nothing), ends on deploy's dry run
sh ~/port/harbor/bin/deploy.sh --apply --live         # the install, from a terminal
sudo sh ~/port/harbor/bin/scope-managed-mods.sh             # the root-owned lockdown file
sh ~/.claude/bin/pin-instructions.sh --apply --live   # pin the instruction files: the owner's own act
sh ~/port/harbor/bin/harbor check --live
sh ~/port/harbor/bin/harbor verify
```

Start Claude Code once first, so that `~/.claude/settings.json` exists: deploy refuses without it (harbor#457).

`deploy-bootstrap.sh` clones only what `harbor.toml` names: `yard` and `prod-guard` need project-init, `fleet` needs projects-orchestrator, and each entry of `packs` brings its own repository. It installs `uv` and `just` into `~/.local/bin` for `yard` or `fleet` only. A clone uses `gh` when it is logged in, else plain `git` over https, which reaches public repositories only. On your own machine, clone your private layer into `~/port/harbor-private` instead of running `scope install`, then run `deploy-bootstrap.sh` (harbor#829).

## The architecture in one line

**Helm (L0)** consumes the trio, never absorbs it — dependency points **down**. Fleet governance lives in the orchestrator; per-repo governance lives in project-init; **detect-and-defer** fails toward the repo so inside a scaffolded repo the repo wins and Helm's global engine stands down. The security path is pure POSIX (zero Bun in the floor; Bun only for skill-tools). Helm is **adopted and vendored, not forked** — upstream is pinned at a SHA in `~/.harbor-upstream` and every divergence is recorded in [docs/reference/provenance.md](./docs/reference/provenance.md), because with no overlay branch there is no `git merge` to tell you what changed.

## Documents

The planning notes below, `docs/reports/rejected-approaches.md`, `docs/generated/status.md` and `docs/how-to/handover.md` are among the files `contracts/layers.tsv` marks `dev`: they stay in the development checkout and the exported core does not carry them, so a core document names them in code font and never links them.

`harbor#N` and `(#N)` throughout the tree cite the private development tracker. They record where a rule came from; they are not links you can open.

- **`docs/reports/platform-epic.md`** — the epic: rationale, the integrated 3-layer model, collision resolution, reductions, must-fixes, spikes.
- **`docs/reports/platform-build-tickets.md`** — the canonical build plan: workstreams **A–K**, each ticket with concrete *Build* steps + *Done-when* acceptance criteria.
- **`docs/reports/2026-07-23-review.md`** — the implementation-readiness review: 14 verified findings (F1–F14), what each changed, and the machine-state baseline the corrections were made against.
- **`trio-decoupling-epic.md`** — the original decoupling epic (background).
- **[`docs/reference/runtime.md`](./docs/reference/runtime.md)** — what to run containers and local Kubernetes with, and the four seams where local stops predicting GCP.

## Licence

Apache License 2.0 (see `LICENSE`), Copyright 2026 Vytautas Cepas. Vendored third-party code keeps its own MIT licence beside it; `NOTICE` lists each tree. Security reports: `SECURITY.md`.

## Status

**Implementation-ready — re-reconciled 2026-07-23 after a 22-agent multi-model implementation-readiness review** (unanimous **GO_WITH_CHANGES**; all 14 confirmed findings folded into the docs — `docs/reports/2026-07-23-review.md` is the ledger).

- **Phase 0 (start here, no fork):** the decoupled slice — `SEC-0` hand-harden (corrected script), `FLEET-0` orchestrator bootstrap, git-backed **Log**, vendored skills (tracked home: `vendor/skills/`), the statusline glyph over a **cached** snapshot, a contract-preserving **Yard** wizard tweak. ~80% value / ~10% risk / near-zero exit cost.
- **Gate (decision 2026-07-23):** step-by-step, completion-gated — **no timed probation window.** Each ticket's Done-when is verified before the next; **Phase 2 starts when Phase 0 is complete and stable.**
- **Phase 2:** the main build (`docs/reports/platform-build-tickets.md`, workstreams **A–K**), opened by the Pre-Phase-2 gate (SANDBOX + RECOVER). **Do NOT start with A1** — the security floor + sandbox come first. This line read "the fork build" until 2026-08-01, five days after the **NO-FORK** decision of 2026-07-25 (harbor#2) and four lines below the Phase 0 bullet that already said "no fork" — the same document disagreeing with itself.
- **Seams frozen first** in [`contracts/`](./contracts/) (descriptor · `--json` · marker · **box-profile** · memory-format) so the four repos can build in tandem without drift.
- **Development process:** GitHub-lifecycle throughout — every ticket = issue → branch → PR with its Done-when as the acceptance gate.

Tracked as GitHub Issues here (epic #1 + workstream tickets #2–#13; where an issue body conflicts with the docs at HEAD, the docs win). Cross-repo tickets are also filed in `project-init` and `projects-orchestrator`.
