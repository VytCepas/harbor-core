# No Harbor-authored plugins — the measurements that retired the tier

**On-demand.** The rule is enforced by lint **X10**. This is why it exists.
Written 2026-09-06, after the tier's founding premise was measured and failed.

**Load when:** deciding where a new capability lives, or wondering why
`plugins/` and `.claude-plugin/marketplace.json` are absent and a lint rule
objects when they come back.

## The rule

> **Capability goes in `skills/` + `bin/`.** A Harbor-authored plugin tier —
> `plugins/<name>/` plus a root `marketplace.json` — exists only when something
> must install on a box that does not have this repo. Nothing here is doing that.
>
> If a skill later needs plugin powers (bundling an MCP server, hooks, an agent),
> it gets a `.claude-plugin/plugin.json` **inside its own skill directory**. It
> then loads as `<name>@skills-dir` and stays under every gate that already
> watches `skills/`. It does not move to another tier.

## The premise that founded the tier, and why it is false

`plugins/atlas/` was created 2026-09-02. Its README stated the case:

> *"A plugin is loaded when its repo is entered; `~/.claude/skills` is loaded
> always. The unit of control we want already exists one layer down."*

`.claude-plugin/marketplace.json` said the same thing in its own description:
*"repo-shaped capability that should cost nothing in a session not doing that
work."* Both halves are false, measured 2026-09-06:

| Claim | Measurement |
|---|---|
| a plugin loads only when its repo is entered | `claude plugin list` → `atlas@harbor`, **Scope: user**. Active in every session on the machine |
| it costs nothing in a session not doing that work | `claude plugin details atlas` → **~398 tok always-on**, added to every session |
| `~/.claude/skills` is loaded always, so it always costs | A skill carrying `disable-model-invocation: true` costs **zero** — it is not in the listing at all |

That last row is the one the tier was built to avoid, and it is available for
free. Verified with three arms and a control, asking a session whether a skill
named `probe` was in its listing:

| arm | in listing |
|---|---|
| plugin skill, model-invocable | **YES** |
| same skill + `disable-model-invocation: true` | **NO** |
| no plugin at all (control) | **NO** |

The control is the half that matters: it rules out the reading where the answer
was NO for some reason unrelated to the flag.

## What the tier cost while it bought nothing

**Seven of eight gates could not see it.** `context-budget.sh`, `skill-book.sh`,
`doc-freshness.sh`, `deploy-doctor.sh`, `status-generate.sh`, `skill-install.sh` and
`skill-collision-verify.sh` each grep `plugins/` **zero** times. Only
`lint-conventions.sh` read it, and only because a patch on 2026-09-05 taught it
to — a patch whose own comment records the shape of the problem:

> *"Measured on a fixture before the change: moved to `skills/atlas/`, T10 fired
> immediately; left under `plugins/`, nothing did."*

That patch treated one symptom and left six holes open. Three consequences were
live when the tier was retired:

- **The budget instrument could not see the route it was being used to justify.**
  `docs/reports/platform-epic.md`'s browser epic (harbor#457) chose a plugin because
  `context-budget.sh` reported *"248 bytes of headroom, 99% of ceiling"* on
  2026-09-07 — from a script blind to plugins. Enabling a browser plugin would
  have added its always-on cost and the budget would still have said 248.
- **`skill-book` could not index it.** The book generates from
  `~/.claude/skills` and `$PWD/.claude/skills`; `atlas` appeared in it **0**
  times. A plugin skill marked `disable-model-invocation: true` would have been
  hidden from the listing *and* absent from the index — unreachable by both
  routes, which is the exact failure the book exists to prevent.
- **A check was registered nowhere.** `plugin.json` advertised *"Ships its own
  browser acceptance suite"*; `contracts/suite-paths.txt` recorded *"atlas ships
  no suite and has no prove target"*; `build/check.mjs` sat on disk in neither
  `contracts/suites.txt` nor `docs/reference/checks.md`. Two documents, one tree, opposite
  claims — and the constitution's *every check is registered or it is not built*
  broken inside the tier no gate was watching.

## What a plugin actually buys, and where each item lives

Verified 2026-09-06. A `.claude-plugin/plugin.json` placed inside
`~/.claude/skills/<name>/` loads as a full plugin — `claude plugin list` reported
`expdir@skills-dir · Status: loaded`, with the same component inventory (skills,
agents, hooks, MCP servers, LSP servers) and the same cost accounting.

| What a plugin buys | Needs `plugins/` + marketplace? |
|---|---|
| bundle skills + agents + hooks + MCP + LSP as one unit | no — skills-dir plugin |
| namespaced skills, no collision | no — same mechanism |
| enable/disable as one unit | no — same mechanism |
| zero ambient cost via `disable-model-invocation` | no — works in both |
| `claude plugin validate --strict` | no — runs on any directory |
| `claude plugin details` cost accounting | no — verified on a skills-dir plugin |
| root `bin/` joins the tool PATH | no — verified for a loaded plugin* |
| **install on a box without this repo** | **yes — only the marketplace does this** |

\* verified via `--plugin-dir`. The skills-dir discovery path was **not**
separately confirmed to wire `bin/`, because `CLAUDE_CONFIG_DIR` relocates auth
and the alternative was writing to the live instruction surface with other
sessions running. Unverified, and named rather than assumed (No.2.7). **Check it
before resting a design on plugin-`bin`-on-PATH from a skills-dir plugin.**

## What this rule does NOT touch

**The security floor watching the box's third-party plugin surface stays exactly
as it is.** `guard-lib.sh` (`floor_marketplace_sha`, the `installed_plugins.json`
and `known_marketplaces.json` projection), `deploy-harden.sh`, `guard-integrity.sh`
and the SEC-0 baseline all watch plugins *somebody else* wrote — `project-init`,
`pr-review-toolkit`, the official marketplace — reaching every session on this
machine. That is a defence, it is unrelated to whether Harbor authors plugins of
its own, and weakening it to satisfy this rule would be *fixing a failure by
weakening a gate*.

## What would reverse this

**Distribution.** The moment Harbor must install on a teammate's box or a second
machine, the marketplace is the format for it and this rule is what you delete —
deliberately, updating this file to say why, not by quietly re-adding a
directory. harbor#391 already recorded the constraints that gate publication
(`bin/` cannot travel through organisation-settings distribution; the de-persona
work gates it independently), so the decision has prerequisites that are written
down elsewhere and are not satisfied today.

## What it did not fix

Moving `atlas` to `skills/atlas/` fixed **governance**, not **cost**. It carries
no `disable-model-invocation`, so it remains a model-invocable ambient skill and
still spends its description bytes every session — the difference being that
`context-budget.sh` can now see them. Whether atlas should be invoked-only is a
behaviour change (it stops surfacing on its own when a session describes an
architecture task) and is the operator's call, open at time of writing.
