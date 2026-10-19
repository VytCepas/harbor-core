# harbor

This box's own governance floor, guards, lint, context architecture and the access-card checker; the register itself is private.

Canonical instructions for **all** coding agents (and humans pairing with
them). Claude Code reads [CLAUDE.md](CLAUDE.md), which imports this file.

## Start here

- [CONSTITUTION.md](CONSTITUTION.md) — the five rules that never yield; read it before anything else.
- [README.md](README.md) — what this repo is and how it is laid out.
- [CONTRACTS/README.md](CONTRACTS/README.md) — the contracts index. [CONTRACTS/marker.md](CONTRACTS/marker.md) is the scope marker and the stand-down table.
- `HANDOFF.md` — current state; `STATUS.md` is generated. Both stay in the development checkout (`CONTRACTS/layers.tsv`), so the exported core has neither.
- [standards/naming.md](standards/naming.md) — naming and conventions; the registers live in `standards/naming/`.
- [CONTRACTS/access-card.md](CONTRACTS/access-card.md) — how to reach each system, and as whom: the card format. The cards are private data, in `harbor-private/access/`.

## Key rules for agents

- **Precedence — `context: repo`** in [`.agents/config.yaml`](.agents/config.yaml). Scoped, not total: the five constitutional rules never yield. A stand-down happens only where [CONTRACTS/marker.md](CONTRACTS/marker.md) lists it, and a guard stands down only to a repo guard that is actually wired.
- **Verify the premise before you plan against it**, and show tool evidence before claiming done (CONSTITUTION №2).
- **Lint and suites** — run `sh bin/lint-conventions.sh` and the suite for each file you touch, and name each one you ran.
- **Commits** — `type(family): …` with a `Refs:` trailer. No AI or Co-Authored-By trailers (lint C2).

## Claude Code specifics

This section applies only when the agent is Claude Code. The floor's hooks are
installed on the box, not wired in this repo (see [CONTRACTS/hooks.md](CONTRACTS/hooks.md)).
