# Trio standard — one contract across Harbor, Fleet and Yard

**Status:** design, 2026-11-01. Lane epic harbor#1423 (T18 of #949), with sub-issues #1424–#1437; the control
plane it builds on is #1422 (T17). Every measured fact behind this design lives in those issues with the command
that re-derives it; this page states no counts, because a count written here is wrong by the next commit
(see [Re-deriving the state](#re-deriving-the-state)).

## What done looks like

- Every fact the box acts on is a **row in a register**, every register declares its own schema, and one
  reader parses them all.
- Every rule, guard and check is a **control**: a `standards/naming/controls.tsv` row before it is code (D-62),
  born `warn`, promoted only by a person's PR after it has gone red once and run clean.
- Every register is **checked both ways**: a thing with no row is red, and a row with no thing is red.
- A **new repo**, or a **whole new system** built the same way, inherits every register, control, check,
  template and version pin its kind needs, by one command, and is operable through `harbor`.
- **Health and schedules** have one home each. A new project appears in health with no wiring by hand.

## The model

Five levels, each the evidence for the one above:

| Level | What it is | Where it lives |
|---|---|---|
| clause | a rule a person wrote: the constitution, a decision record | `CLAUDE.md` source, `docs/decisions/` (#1026) |
| control | the row that enforces a clause: id, mode, type, moment, engine, owner, red proof | `standards/naming/controls.tsv` |
| engine | the code that evaluates a control | `bin/`, a hook, a CI job, Fleet |
| evidence | what the engine saw: a red in a suite, a guard-ledger line, a snapshot | `red_proof`, ledgers, `snapshot.v1` |
| finding | a red that needs a person, with a lane: HEAL, PROPOSE or DECIDE | `contracts/finding.md` |

## The rules every register follows

1. **A schema row.** The register has a row in the register of registers: columns, key, the columns that
   reference other registers, owner, and the check that reads it (#1424).
2. **Two-way checks.** Missing row and orphan row are both red.
3. **A kit row.** The register states its share (`core`, `hub`, `workload`, `personal`) and whether Yard
   vendors it, so it reaches new repos and new systems (#1436).
4. **Controls before code.** Each check the register needs is a `controls.tsv` row born `warn` (D-62).

**Declared is not enforced.** `standards/naming/kinds.tsv` already declares what each kind of file carries in
its `required_fields` column — the `generated-by` header on generated docs (D-40), front matter on the Diátaxis
doc kinds and on this one, `status` on decision records, `schema_version` on contracts, the `# WHY` header on
registers — and no script reads that column. One control, `standard.kind-fields`, closes that for every kind
at once (#1424).

## Where each concern lives

| Concern | Lives in | Why |
|---|---|---|
| Registers of record: controls, kinds, versions, seams, labels, env vars, executables, the kit manifest | **Harbor (L0)**, `standards/` and `contracts/`, share `core` | one registry per box; Yard vendors them, Fleet reads them |
| On-box schedules: launchd jobs, event rules | **Harbor (L0)**, each a row in the one check register | the admission guards already refuse a session installing a unit, so the box's identity runs them |
| Alerting and findings | **Harbor (L0)**: `check.alerting`, `check.findings` | one notifier per box; a finding has a named destination |
| Cross-repo health: status, audit, drift, CI verdicts, version, seam, label and verb drift | **Fleet (L2)**, run by Harbor's schedule; Fleet emits, never notifies | Fleet reads across repos, in Python, with versioned schemas |
| Health state | Fleet's `snapshot.v1` and `history`, cached by `bin/fleet-snapshot-refresh.sh` | already the statusline's source |
| What is watched | `docs/reference/checks.md`, generated from `controls.tsv` and repo fragments | it is hand-kept today |
| Hosted schedules: GitHub Actions `schedule:` | **each repo**, rendered by **Yard (L3)**, registered as fragments into Harbor's check register | they run where the repo's CI runs |
| A repo's own health signals | **each repo**, in the schema its producer owns (#1425) | the producer validates what it emits |
| Repo birth and upgrade | **Yard (L3)** renders; `project-init --json` feeds Fleet's `register` (#510) | the seam exists |
| Operating all of it | `harbor` — `harbor repo`, `harbor fleet`, `harbor yard`, `harbor status` | one front door, dispatched from the registers |

Languages follow the layer: the floor and the lints Yard vendors into every repo are POSIX `sh`; Fleet and Yard
are Python; Harbor dispatches to their CLIs and never reimplements them.

## The registers

| Register | Lane | State today |
|---|---|---|
| register of registers (schemas, one reader, generated indexes) | #1424 | `standards/naming/registers.tsv` names a minority of the box's `.tsv` files |
| seams: every contract that crosses a repo boundary | #1425 | Fleet checks one vendored contract weekly; Yard's vendored naming package is checked by nothing |
| versions: runtimes, tools, libraries, action SHAs | #1426 | Yard's `tools/pinned-third-party.toml` holds the right semantics for one tool |
| labels | #1427 | `label-axes.tsv` exists; live labels are not compared with it |
| task verbs per repo kind | #1428 | Yard's `justfile.tmpl` is the de-facto list; nothing checks a repo against it |
| decision records, box-wide ids | #1429 | per-repo series that collide; the reference form `system/register:id` exists (D-20) |
| where a repo is known | #1430, #966 | several sources, partly checked by `context.*` and `check.port-drift` |
| environment variables | #1431 | `contracts/roots.tsv` covers the root variables only |
| executables | #1432 | `contracts/layout-map.tsv` covers top-level entries only |
| schedules | #1433 | `drift.launchd-plist` checks one direction |
| generated files | #1434 | `contracts/fresh-checks.tsv` in Harbor only |
| document metadata | #1435 | declared in `kinds.tsv`, unchecked |
| the kit manifest | #1436 | missing |

## Controls the lanes add

New ids follow `<family>.<slug>` (D-10) and are judged by `name.control-shape` when their rows land.

| Control | Type · moment | Engine | New or extends | Lane |
|---|---|---|---|---|
| `standard.kind-fields` | lint · ci | `bin/standard-shape.sh` | new | #1424, serves #1425 #1429 #1434 #1435 |
| `name.registry-shape` to every registry | lint · ci | `bin/lint-name.sh` | extends | #1424 |
| `standard.register-declared`, `standard.reference-resolves` | lint · ci | `bin/lint-name.sh` | new | #1424 |
| `standard.seam-registered` | lint · ci | `bin/lint-name.sh` | new | #1425 |
| `check.seam-fresh` | check · schedule | Fleet | new | #1425 |
| `module.cross-system-path` reads the seams register | lint · ci | `bin/lint-module.sh` | extends | #1425 |
| `ci.action-sha-pinned` | lint · ci | `bin/lint-conventions.sh`, vendored | new | #1426 |
| `check.version-drift`, `standard.version-registered` | check · schedule; lint · ci | Fleet; `bin/lint-name.sh` | new | #1426 |
| `check.label-registered`, `check.label-sync` (corrective, applied by a person) | check · schedule; check · manual | Harbor `bin/` | new | #1427 |
| `name.repo-kind` to required verbs, `check.repo-verbs` | lint · ci; check · schedule | `bin/lint-name.sh`; Fleet | extends; new | #1428 |
| `standard.decision-dangling`, `-orphan` across repos; `standard.decision-supersession` | lint · ci | `bin/lint-conventions.sh` | extends; new | #1429 |
| `context.repo-sources-agree` | lint · ci | `bin/lint-conventions.sh` | new | #1430 |
| `standard.env-registered`; `scope.root-defaults` reads it | lint · ci | `bin/lint-name.sh`; `bin/lint-conventions.sh` | new; extends | #1431 |
| `standard.script-registered`, `check.script-uncalled` | lint · ci; check · schedule | `bin/lint-name.sh`; `bin/standard-shape.sh` | new | #1432 |
| `drift.launchd-plist` both ways; `check.schedule-registered` | lint · ci; check · schedule | `bin/lint-conventions.sh`; `bin/check-registry-generate.sh` | extends; new | #1433 |
| `doc.fresh-registered` (succeeds the three `doc.*-generated` rules) | lint · ci | `bin/lint-conventions.sh` | new | #1434 |
| `doc.kind-folder` | lint · ci | `bin/lint-conventions.sh` | new | #1435 |

## Inheritance: a new repo, a new system

- **A new repo** is made by `harbor repo new <name> --kind <repo-kind>` (or adopted with `harbor repo adopt`):
  Yard renders the files the kit lists for that kind, Fleet's `register` records it, Harbor writes its
  registry row, memory route and `context-rules/<name>/`, then the label sync and the version check run. The
  acceptance test is the existing controls going green on it in one run (#1430).
- **A new system** is bootstrapped from the core share on a clean box: `harbor scope install` and
  `harbor deploy` give an empty but valid register set, the core controls and the scheduled checks (#1436).
- **The CLI dispatches from the registers.** A system registered with its verbs is callable as
  `harbor <system> <verb>`; `bin/lint-name.sh --gen cli-tree` already renders that tree and becomes the
  dispatch table. The new verbs amend the frozen table in `contracts/cli.md`, which the operator signs at merge.

## Order

1. **#1424** first: every other lane adds a register, and each must land in the schema table.
2. **#1425, #1426** next: every other standard travels between repos as a copy or a pin.
3. **#1427, #1428, #1429, #1431–#1435** in any order.
4. **#1430, #1436, #1437** last: they compose the rest into one command, one kit and one health view.

The quick, independent fix is #1426 condition 6: the required check on harbor main runs from `harbor-core`'s
workflows, which pin `actions/checkout` by a mutable tag.

## Re-deriving the state

Each lane's issue carries its measurement commands. The headline ones:

```sh
find . -name '*.tsv' -not -path './.git/*' -not -path '*/fixtures/*' -not -path '*/test*' | wc -l    # registers
grep -oE '[A-Za-z0-9_./-]+\.tsv' standards/naming/registers.tsv | sort -u | wc -l                     # declared
grep -l required_fields bin/*.sh bin/*.py                                                           # kinds.tsv readers
grep -rhE 'uses: [^@ ]+@v[0-9]' .github/workflows                                                   # mutable action tags
grep -rhoE '\bHARBOR_[A-Z0-9_]+' bin | sort -u | wc -l                                              # env vars read
```

## Decided

- **Fleet's `watch` and `notify`.** `watch` no longer pushes (`--webhook` removed, projects-orchestrator#362);
  Harbor runs it as the registered check `status.fleet-watch` inside the fleet-snapshot refresh (#1437, #1459).
- **The CLI table.** `harbor repo` and `harbor <system> <verb>` are rows in `contracts/cli.md`, generated from
  `contracts/cli.md.tmpl` and `verbs.tsv` (#1430, #1436).

## Not in this design

The repo registry and renames (#966), Yard rendering the standard (#967), the clause register and the why-graph
(#1026), the enforcement matrix (#1028), one decision function for the admission guards (#1030), and the label
taxonomy's content (#512, #978) are owned by their issues; this design composes them.
