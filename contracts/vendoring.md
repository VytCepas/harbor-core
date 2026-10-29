# Vendoring — refuse, depend, vendor, or take the idea (harbor#459)

**Status: written 2026-09-17, derived from the record, not yet mechanised.** Until
this file existed the same question was answered case by case, eleven times, each
on its own argument. The rule below is what those answers already had in common,
checked against what each ticket and the tree actually hold rather than against
the summary that proposed it. Nothing reads this file yet: #447 (a machine-readable
provenance record) and #448 (an intake audit) are where a check would live.

## The rule — first match wins

A candidate is an external repository, package, server or skill that someone
proposes to bring into this estate. It gets exactly one of four verdicts, and
**the verdict may differ for different parts of the same candidate**. Archify was
vendored with two of its files refused (#392).

### 1 · Refuse — any one of these is enough

| clause | refuse when | recorded on |
|---|---|---|
| **R1** | **Its own installer would write into this estate**: config, hooks, skills or the instruction surface. The install step is refused even when the content is taken. | `getagentseal/codeburn`: "a third-party installer writing into the session hook lifecycle" (#386). `garrytan/gstack`: its install "drops a whole cloned repository into the live instruction surface" (#446) |
| **R2** | **It puts a second decision-maker inside the loop**: the tool chooses actions the transcript cannot show, so the choice cannot be reviewed and injected content reaches every step it takes. | `browser-use/browser-use`, "an agent that navigates by goal" (#460, split into #473) |
| **R3** | **A channel a third party controls would reach an agent's context**: a phone-home, a remote update manifest, an acknowledgement handshake. | archify's `SKILL.md` and `scripts/check-update.mjs`, excluded from the vendored copy for exactly this (`vendor/archify/PROVENANCE.md`) |

### 2 · Depend — pin it and invoke it, when all four hold

| clause | the dependency is |
|---|---|
| **D1** | **pinnable to an exact version**, and pinned. `@latest` fails. |
| **D2** | **non-resident**: invoked per command and exits. A long-running server that holds state fails. |
| **D3** | **explicit about its credential or session boundary**: which profile, which session, and how its data is deleted |
| **D4** | **kept out of the instruction surface**: nothing it ships is loaded into a session's context |

Recorded: Playwright, installed pinned under a probe host (#459). `playwright-cli`,
pinned at `0.1.22` in `bin/access-browser-agent.sh` (`PW_CLI_PIN`), with an explicit
session per Claude session (#472, built 2026-09-30).

**The control, and why this is a rule rather than a list of past answers:** the
same vendor's `@playwright/mcp` fails D1 and D2. It is referenced `@latest`, runs
resident, and uses one implicit profile, and on 2026-09-16 the local package cache
held three versions of it (#472). Same vendor, same capability, opposite verdict,
decided by the clauses and not by the name.

**Corrected 2026-09-30, from the critic pass on #472.** D2 separates the two less
than this said: the CLI also keeps a daemon per named session, behind a unix
socket, until `detach` or its idle timeout. What holds is D1 (an exact pin) and
D3 (a named session), and in extension mode `delete-data` destroys nothing,
because the data is the operator's own profile. The browser agent bounds the
daemon with `--idle-timeout`; it does not make the CLI non-resident.

### 3 · Vendor — copy it under a provenance record, when all four hold

| clause | the copy |
|---|---|
| **V1** | is **needed at runtime or in context**, not just as an idea |
| **V2** | is **pinned to a tag or SHA**, and the pin is written where a re-harvest reads it |
| **V3** | **records what was excluded and why**, so a re-pin re-applies the exclusions instead of rediscovering them |
| **V4** | **names its acceptance test for a re-pin** |

Recorded:

- **Upstream skills.** `vendor/skills/`, pinned at tag `v7.1.1`, with each divergence in the *Changed on intake* column of `docs/reference/provenance.md`.
- **archify.** `vendor/archify/` as a CLI only, pinned at tag `v2.16.0`, MIT. It has zero runtime dependencies and no network access. The exclusions are recorded, and the re-pin test is `doctor` (#392).
- **complexity-atlas.** `vendor/complexity-atlas/`, an 840 KB reference artefact kept out of `vendor/skills/`, because the installer copies skill directories into the live tree and that weight would land there for every session.

### 4 · Take the idea — re-author it, cite the source, copy nothing

This is the verdict when none of the above applies, or when what is valuable is a
design decision or a small mechanism rather than the code.

Recorded: codeburn's realised-versus-estimated report exists in Harbor's own idiom
as `bin/context-budget.sh --record` and `--check` (#386). `research` and `triage`
are proposed as re-authored front doors to machinery Harbor already owns (#452,
open, nothing built). From `wshobson/agents`, the one-source, many-targets
generate step, not its catalogue (project-init#973, open). And from gstack, the
browser architecture only (#446), which is R1 and 4 applied to the parts of one
candidate.

## The licence axis — the verdict names its destination

A verdict is **for a destination tier**. Harbor is a private tree, while
`project-init` templates and the `projects-orchestrator` wheel are distributed
from public repositories. A licence that permits a private copy can bind a
distributed one. #459 records `trailofbits/skills` as CC-BY-SA-4.0, whose
share-alike terms reach anything derived from it that ships. The same class
failed without any licence involved: a private repository's name in the public
orchestrator's `src/`, which is its wheel (projects-orchestrator#248).

**Moving an artefact to a distributed tier re-opens its verdict.** A verdict that
does not name its tier is incomplete.

## Where a verdict is written

| verdict | written in |
|---|---|
| vendor | `docs/reference/provenance.md` for a skill; `vendor/<name>/docs/reference/provenance.md` for a tool: pin, exclusions, re-pin test |
| depend | beside the pin, and the ticket that chose it |
| take the idea | the authored file cites its source |
| refuse | the ticket, and `docs/decisions/rejected-approaches.md` when the refusal is a pattern |

When #447 makes the provenance record machine-readable, the verdict and its tier
become fields there. Until then this table is the convention and nothing checks it.

## Re-derived from the record

Every decision #459 counted, with the verdict the tree and the ticket actually
hold, and the clause that produces it.

| candidate | recorded verdict | clause | agrees |
|---|---|---|---|
| `tt-a1i/archify` (#392) | **vendored** as a CLI; `SKILL.md` and the update check refused | V + R3 on a part | yes |
| `garrytan/gstack` (#446) | architecture taken; install refused | 4 + R1 | yes |
| `getagentseal/codeburn` (#386) | concept re-authored; installer refused | 4 + R1 | yes |
| `browser-use/browser-use` (#460) | refused as an actor | R2 | yes |
| `browser-use/browser-harness` (#473) | no install; a suggester seam, left empty, gated on #472 | R2 as an actor | yes, open |
| Playwright | dependency, pinned under a probe host | D | yes |
| `playwright-cli` (#472) | depend on the pinned CLI — built as `harbor chrome` | D1, D3 | yes |
| `@playwright/mcp` (#472) | refused: `@latest`, resident — removed from `~/.claude.json` 2026-09-30 | fails D1, D2 | yes: **the control** |
| `research`, `triage` (#452) | re-author | 4 | yes, open |
| `wshobson/agents` (project-init#973) | take the generator | 4 | yes, open |
| Upstream skills | vendored, pinned | V | yes |
| complexity-atlas | vendored reference | V | yes |

**Corrected from the records this file was written from.** #459's own table
recorded archify as "take two ideas, vendor nothing". The tree holds
`vendor/archify/`, 2.3 MB, vendored 2026-09-01. #459's 2026-09-16 comment also
counted three closures as vendoring decisions that were closed on other grounds, so
they are neither evidence for this rule nor against it:

| ticket | closed because |
|---|---|
| caveman (#387) | the budget it cited is input bytes, while caveman cuts output tokens |
| design-extract (#388) | the table it would register in is generated, not typed; folded into #413 |
| impeccable (project-init#967) | there is no frontend scaffold to receive it |

## Falsifier

Apply the rule, cold, to a candidate it was not written from. If it cannot give a
verdict without an author interpreting it, it is prose. The sharpest case: any MCP
server referenced `@latest` and run resident must be refused by D1 and D2, while
the same capability as a pinned, per-command CLI must pass. A rule that approves
both has described the past instead of governing the next case.
