# Gates — where a checker lives, and who runs it

**Status:** proposed 2026-08-29 · ticket **R5** · the rule below is written
because measurement found the opposite everywhere it looked.

## The rule

> **A checker travels with the contract it enforces. The repo that HOSTS the
> subject is the repo that runs it.**

Two halves, and both are load-bearing:

- **Travels with the contract.** A contract stated in a skill and enforced by a
  script in some other repo's `bin/` can only be run by someone standing in that
  other repo. Put the checker in the skill's own `bin/`, so installing the skill
  installs the gate and it runs from any cwd.
- **Hosted, not owned.** No repo needs read access to another. Each repo's CI
  gates the trees it actually holds. A cross-repo gate is a gate that silently
  degrades to "unchecked" the moment CI runs somewhere the other repo is absent.

## What this replaces, measured 2026-08-29

| contract | its checker | where the subject lives | what runs it |
|---|---|---|---|
| topology's nine sections | the data-estate repo's `bin/check-topology.sh` | `<repo>/CLIENTS/` | **nothing** |
| the pack's row format | `harbor/skills/casefile/bin/check-pack.sh` | wherever the case is | **nothing** |
| the route card | `harbor/skills/access-ledger/bin/check-routes.sh` | `harbor-private/access/` | **nothing** |

Three contracts, three working checkers, **zero of them wired to anything**. Each
is hand-run by whoever remembers. That is not a weaker gate than intended, it is
the absence of one, and it is invisible because every checker passes when you run
it deliberately.

The cross-repo half is just as measurable. `<repo>` holds the only client map on
this box and names `CLIENTS` **zero times** in its CI workflow, its justfile, its
`CLAUDE.md` and its `AGENTS.md`. the data-estate repo holds the checker for that map and
invokes it in neither its CI nor its justfile.

## Required properties of a checker

1. **It runs from any cwd.** Resolve subject directories from an environment
   variable with a sane default, never from `$PWD`.
2. **It cannot see its subject → it says UNCHECKED, and never `ok`.**
   `check-topology.sh` already does this correctly and it is the behaviour to
   copy: *"a checker that silently skips its main subject is worse than no
   checker."*
3. **It has a `--self-test` that goes RED before you trust it GREEN.** Mutations
   for each rule, plus at least one **valid-but-unusual** input that must stay
   green — falsification proves discrimination, not correctness.
4. **It asserts substance, not only shape.** A structural check passes a file
   with the right headings and none of the subject. That is exactly how a 25 KB
   nine-section client map passed while missing the entire case it was written
   for.
5. **It does not fire on ordinary work.** A guard that produces false positives
   gets switched off, and a disabled guard protects nothing.
6. **A green result states its own scope.** Name the classes, paths or cases it
   did **not** cover, on every run, pass or fail. Property 2 covers a checker
   that cannot see its subject at all; this covers the commoner and quieter case
   — one that sees part of it and reports like it saw all of it. Measured
   2026-09-03: `reconcile-estate.sh` printed `40 object(s) matched: 40 in the
   map, 0 NOT in it`, which reads as *the map is complete*. It had enumerated
   three object classes out of nine, and said so nowhere. The most consequential
   fact about that estate — a client-facing dashboard rendering ~2% of actual
   spend — was in a class it cannot see, and its green said nothing about it.
   **That line is the difference between an instrument and a reassurance, and it
   costs one `printf`.**
7. **It distinguishes "I could not run" from "I found nothing".** Two different
   claims, and collapsing them fails in the direction that MANUFACTURES a
   finding. Convention: exit `0` measured with data, `1` measured with no data,
   `3` could not run — auth, network, a missing binary, an unreadable input (D-29
   `unchecked`, D-49; this said `2` until then, and `2` is now a bad argument).
   Measured 2026-09-03: `shard-age.sh` answered `no shards matched` and exit 1
   against a table holding 1,382 of them, because a `2>/dev/null` swallowed a
   reauth failure and the exit status came from a trailing `grep .`. It said
   *this feed is dead* when it meant *I could not look*. Prove it with a
   deliberately poisoned credential — a probe that still returns 1 fails, which
   is what `check-topology.sh --probe --adversarial` runs.
8. **A vocabulary it declares, it enforces.** A closed list of legal values that
   nothing checks is decoration, and it costs more than it looks: it teaches the
   reader that parts of the contract are inert, and then they discount the parts
   that are not. Measured 2026-09-03: the measurement pack declared
   `evidence=config|traffic` and `consent=bound|hardcoded|absent|n-a`, both
   enforced by nothing, on a map that passed with **no row carrying either
   value** — while thirty tags across three markets sent customer email
   addresses and phone numbers with consent gating off. Either wire it, or
   delete it and say the contract does not cover that.

   **CLOSED, and the exemplar is kept because the incident is why the property
   exists.** Both enums are enforced now: `check-topology.sh` reads them at
   `:120` (`PACK_ENUMS=$(pack_field "$_pkf" enums)`) and checks them at `:154`
   and `:211`, against `skills/topology/packs/measurement.md:6`, held by the
   self-test at `:2060` — *"a pack enum must be enforced, not merely declared"*.
   Verified 2026-09-05. Read the paragraph above as the case, not as open work:
   until then it described a fixed defect in the present tense, which is the
   same drift the count in "Done 2026-08-29" had.

## Done 2026-08-29

- **`check-topology.sh` now lives in `skills/topology/bin/`**, travels with the
  skill, resolves `ESTATE_DIR` / `GTM_DIR` rather than `$PWD`, carries the
  conditional ad-delivery rule that was stranded on an unmerged branch, and has a
  `--self-test` where it had none before — five mutations red, a client dir with
  no map red, an internal map with no ad platform green, restore green, and a
  good deal more since. **The count is not written here on purpose.** It read
  "8 assertions" from 2026-08-29 until 2026-09-05, by which time the tool
  reported 79; a count in prose is a COPY, and copies drift silently while still
  reading correctly (`CHECKS.md`, which deleted its own status column on
  2026-09-04 for exactly this). Ask the tool:
  `sh skills/topology/bin/check-topology.sh --self-test | tail -1`.
- **`tests/skills/skill-gates-test.sh` is the wiring**, and it goes through
  [`suites.txt`](./suites.txt), **not** a workflow file. The workflow tree is
  denied to agents deliberately (harbor#61) so an agent cannot rewrite the gate
  that judges it; the tracked, agent-editable manifest is the answer that already
  existed for exactly this. Verified with the selector: a change to any of the
  three checkers selects the suite, an unrelated change stands it down.
- **A workload repo's own `bin/check-topology.sh` is now superseded and is a second source of
  truth.** Removing it is a deletion in another repo and therefore an operator
  act; until then the harbor copy is canonical — it is the one with the
  ad-delivery rule and the self-test.
- **`<repo>` gating its own `CLIENTS/` is still unwired.** The checker can now be run
  from that repo without reaching into another, which is what the move bought;
  adding the line to its CI is the remaining step and it is not harbor's to take.

## Falsifier — asserted, not asserted about

`tests/skills/skill-gates-test.sh` builds a hollow `TOPOLOGY.md` — every required heading,
an ISO date, an ad platform named, `TBD.` underneath each one — and asserts:

| assertion | result |
|---|---|
| structure alone PASSES the hollow map | passes, and that is the documented division of labour, not a bug |
| substance (`check-pack.sh --map`) REJECTS it | rejects |
| a map with real content survives BOTH | survives |

**One checker alone cannot fail a hollow map.** Asserting the pair is what keeps
the division of labour honest; asserting the control is what stops the pair
becoming a guard that fires on ordinary work.
