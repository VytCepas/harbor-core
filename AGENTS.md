# harbor

This box's own governance floor, guards, lint, context architecture and the access-card checker; the register itself is private.

Canonical instructions for **all** coding agents (and humans pairing with
them). Claude Code reads [CLAUDE.md](CLAUDE.md), which imports this file.

## Start here

- [policy/constitution.md](policy/constitution.md) — the five rules that never yield; read it before anything else.
- [README.md](README.md) — what this repo is and how it is laid out.
- [contracts/README.md](contracts/README.md) — the contracts index. [contracts/marker.md](contracts/marker.md) is the scope marker and the stand-down table.
- `docs/how-to/handover.md` — current state; `docs/generated/status.md` is generated. Both stay in the development checkout (`contracts/layers.tsv`), so the exported core has neither.
- [standards/naming.md](standards/naming.md) — naming and conventions; the registers live in `standards/naming/`.
- [contracts/access-card.md](contracts/access-card.md) — how to reach each system, and as whom: the card format. The cards are private data, in `$PORT_ROOT/harbor-private/access/`.

## Key rules for agents

- **Precedence — `context: repo`** in [`.agents/config.yaml`](.agents/config.yaml). Scoped, not total: the five constitutional rules never yield. A stand-down happens only where [contracts/marker.md](contracts/marker.md) lists it, and a guard stands down only to a repo guard that is actually wired.
- **Verify the premise before you plan against it**, and show tool evidence before claiming done (CONSTITUTION №2).
- **Lint and suites** — run `sh bin/lint-conventions.sh` and the suite for each file you touch, and name each one you ran.
- **Commits** — `type(family): …` with a `Refs:` trailer. No AI or Co-Authored-By trailers (lint C2).

## Tests and CI

- **Suites:** `sh bin/test-suite-run.sh --select` runs the suites the changeset needs (flags: `sed -n 2,17p bin/test-suite-run.sh`). Never a hand-rolled `xargs` loop over `contracts/suites.txt`: one ran nothing and reported green.
- **Lint:** `sh bin/lint-conventions.sh`.
- **A test that cannot fail does not count:** break what it guards, watch it go red, restore it. [`skills/test-strength`](skills/test-strength/SKILL.md) is the method.
- **Where CI runs:** a harbor PR is mirrored (`.github/workflows/public-ci.yml`, `bin/ci-mirror.sh`) to the public `harbor-core` repo, where governance CI runs on GitHub-hosted `ubuntu-latest` runners (`governance.yml` takes them on any public repo). `public-ci` is the required check (`contracts/required-checks.tsv`).
- **Sandbox:** a suite that clones the repo can fail inside the Claude sandbox only; rerun outside it before believing a red.
- **Shared CPU, shared sessions:** waiting on `bin/ci-governor.sh` is expected, and another session's run is never yours to kill. The rest: [docs/design/ci-tests-on-this-host.md](docs/design/ci-tests-on-this-host.md).

## Claude Code specifics

This section applies only when the agent is Claude Code. The floor's hooks are
installed on the box, not wired in this repo (see [contracts/hooks.md](contracts/hooks.md)).
