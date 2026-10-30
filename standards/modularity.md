---
kind: standard
status: experimental
owner_issue: harbor#996
---
# Modularity standard

How the metasystem is cut into parts, what each part may depend on and expose, and which rules the reference graph
checks. It is the structural half of `docs/explanation/modularity.md`, which keeps the file-size doctrine (depth, seams, the
two-adapter rule) and the rationale. This file states no enumeration the registry owns: the families, their
allowed dependencies and the rules with their modes are rows in `standards/naming/terms.tsv` and
`standards/naming/controls.tsv`. The levels come from D-57 (`docs/decisions/0057-levels.md`), where a level shows
from D-58, the one global family set from D-59, and the enforcement from D-60
(`docs/decisions/0060-modularity-enforcement.md`).

## 1. Levels

Seven named levels, never numbered. The legacy L0, L2 and L3 are aliases for one product's build order, not for a
containment model.

| Level | Term | Is | Physical form | Its interface | Versioned by |
|---|---|---|---|---|---|
| 1 | **metasystem** | everything | the workspace and the host | none | none |
| 2 | **domain** | systems that share purpose and vocabulary | a registry class `domain`; the repo-name prefix (D-45) | none: grouping only | none |
| 3 | **system** | one repo: the unit of deploy, ownership and release | a repo carrying `.agents/config.yaml` | **contracts only** (M1) | a SemVer tag `v<x.y.z>` |
| 4 | **subsystem** | a viable-system function inside a system | registry `broader` only: never a folder, never in a name | none | none |
| 5 | **family** | a module: components behind one interface | `bin/<family>-*`, `src/<pkg>/<family>/`, `tests/<family>/`, ids `<family>.*` | one CLI subtree and the package's public exports | none (internal) |
| 6 | **component** | one named unit | one file or one registry row | its name or its id | id permanence (D-19) |
| 7 | **element** | a function, field, option or rule clause | inside a component | none | field deprecation |

**Containment invariant.** Every artifact has exactly one parent at each level. Zero parents or two is a finding.

**Where a level shows (D-58).** A flat namespace carries the grouping it flattens as a prefix; a nested one carries it
as a folder; never both.

| Surface | Flattens | So it carries |
|---|---|---|
| the repo list | domains | `<domain>-<system>` (platform repos are exempt, and listed) |
| `bin/` | families | `<family>-<object>` |
| launchd, env, `~/.local/bin` | systems | `com.harbor.`, `<REPO>_`, `<system>` or `<vendor>` |
| `src/<pkg>/`, `tests/`, `docs/` | nothing | folders: `<family>/<object>` |
| ids and references | families; systems across boundaries | `<family>.<object>`; `<system>/<register>:<id>` |

**One slot per level, filled per domain (D-59).** Platform systems fill the family slot from one global set of
families, shared by every platform system. Workloads fill it with a registered `area` instead.

## 2. Rules

Each rule names the control that checks it. A control is a row of `standards/naming/controls.tsv` (D-62); the rows
below are the ones `bin/lint-module.sh` evaluates.

### M1 · Systems meet only through registered contracts

Contracts are `contracts/` and `contracts/` documents, `schemas/` files carrying a `schema_version`, a CLI's
`--json` output, the scope marker, the descriptor and registry files. A system never reads another system's
internal paths and never names its repo literally.

*Why.* A rename or refactor inside one system must not break another.

*Check.* `module.cross-system-path`: a `references` edge from system A to a path of system B that is not a contract
path.

### M2 · Dependencies point one way

Workloads depend on platform contracts. Fleet, the scaffolder and the memory store depend on harbor's standard and
contracts. Harbor depends on others only through contracts that harbor itself defines (the descriptor, the marker).
There are no cycles between systems.

*Why.* Dependency inversion: the control plane governs workloads whose insides it does not know.

*Check.* `module.system-cycle`: a cycle in the graph of cross-system edges.

### M3 · Families meet only through a public entry

A family's public entry is its command (`<system> <family> ...`, `bin/<family>-*`) or its package's exported names.
Files whose name starts with `_`, files named `lib` or ending in `-lib`, and anything under a `lib/` or `_*/` folder
are private. The families a family may use are the `depends_on` column of its row in `standards/naming/terms.tsv`.

*Why.* A family is a module, not a prefix, only if something stops its neighbours reaching past its entry.

*Check.* `module.private-use`: an edge from one family's file to another family's private file.
`module.family-cycle`: a cycle between families, over the graph's edges and the declared `depends_on`.

### Layer direction

The derivation layers (`standards/naming.md` section 5) run source, then generated, then deployed, and a layer reads
only the one below it: nothing upstream consumes what is derived from it.

*Check.* `module.layer-direction`: code (`bin/`, `src/`, `hooks/`, `githooks/`, `tools/`) that reads a generated
file, other than the generator that writes it. A generated file is one a `derives_from` edge names, or one under
`build/` or `docs/generated/`. Deployed copies are not judged yet: the graph cannot tell an installer writing a
path from a script reading it. This rule is the ticket's addition to D-60's four.

## 3. How it is checked

`sh bin/doc-graph-generate.sh` writes `build/graph.tsv`, one row per edge between two nodes, and `sh bin/lint-module.sh`
judges it. `sh bin/lint-conventions.sh` runs both under `module.graph-conform` and prints every finding as an
advisory.

- **Only `references` edges are judged.** An edge says a line holds a path as a literal substring: a mention, not
  proof of a call. So the rules skip files that record or exercise and set aside a mention that cannot read, and
  every finding left names its site for a person to confirm.
  - *Not judged:* prose (`*.md`, `docs/`, `evals/`), the contract and register areas (`contracts/`,
    `contracts/`, `schemas/`, `standards/`, `.agents/config.yaml`), and `tests/` and `fixtures/`. A register row
    names a path to define the seam, and a test names one to build or assert on it. A test's family is its
    directory name, a suite group and not the owner of the thing under test (`tests/ci/` exercises
    `gate-merge-stack.sh`), so a test cannot make a family cycle.
  - *Set aside as inert:* a mention whose cited line is a comment (first non-blank character `#` or `//`), or
    holds the path only as the tail of a longer name (`docs/reports/qa-plan.md` holds `docs/generated/plan.md`). The line is read from the
    tree; a line that cannot be read, or does not hold the path, keeps its finding.
  - *Listed, so no cut is silent:* `sh bin/lint-module.sh --format inert` lists every pair a cut set aside, with
    why. A comment-only or longer-name pair is listed whether it would have been a finding or only an edge of the
    system or family cycles, and a path of another system that a test names is listed as `test`.
  - *Not seen at all:* a path built from parts (a directory variable joined to a file name) leaves the graph no
    literal to match, so no rule sees that read, even when a comment also names the file. The list shows the
    comment and not the read behind it.
- **A system** is a node prefix that is also an input row of the graph. **A family** is read from a path alone.
- **A graph that is missing or stale is not judged.** `sh bin/lint-module.sh` exits 3 (unchecked), never 0.
- **Modes (D-29, D-64).** Every rule is born `warn`. Promotion to `block` is a person's pull request, after the rule
  went red on a fixture and ran four weeks with no finding accepted as false. `module.family-shape` stays `shadow`
  until the catalog exists.
- **Each rule went red on a fixture:** `sh bin/lint-module.sh --self-test` runs `fixtures/lint-module/`, and a
  fixture that stops yielding its id fails the run.

## 4. Not yet adopted

Three questions the lint cannot answer from a line of text. The first two keep their sites as
`module.layer-direction` findings until the operator rules, and the third keeps its sites out of the findings:

- **Does a checker of a generated file read it?** A gate or lint that names `docs/generated/status.md` to confirm it is current
  (by running the generator's `--check`, or by leaving the file out of a diff) is not the generator, and the
  graph cannot tell it from a consumer.
- **How is a confirmed non-read recorded?** A help line, a rule label or a skip list that names a generated file
  without opening it has no mechanical class: no check on the line separates it from `git show "$sha:docs/generated/status.md"`.
- **Does a test that reads another system's real installed file count under `module.cross-system-path`?** Tests
  are not judged, because most name a path of another system to build a fixture or assert on a row, and judging
  them would put those back as findings. Some really read the operator's installed copy, and the lint cannot tell
  the two apart from the line. They are listed as `test` in `--format inert` and stay out of the findings until
  the operator rules.

The research proposes further rules (a uniform interface shape at every level, how a new family or system is
admitted, where findings route, and what is versioned). They are not part of this standard until the operator
rules on them.
