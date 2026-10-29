# `PORT_ROOT` — the workspace root the governed repos live under

**Seam:** shared canonical — L0 Helm, L3 Yard (`project-init`), L2 Fleet
(`projects-orchestrator`). **Status: harbor#619 — Helm's half is implemented and
fixtured; the other two halves are written as project-init#1030 and
projects-orchestrator#314, and whether they have landed is those PRs' state, not
this line's.** Read the last section before citing this file as done.

The repos move from `$HOME/<repo>` to `$PORT_ROOT/<repo>`, side by side. Three
codebases then need one answer to *where is the workspace*, and they are in
three languages with no shared runtime — the same shape as
[marker.md](./marker.md) next door, and settled the same way: **one frozen
resolution rule, re-implemented per language, pinned by shared fixtures.** The
POSIX floor must not import a Python resolver across a language boundary.

## The rule

```
PORT_ROOT = $PORT_ROOT if set and non-empty
          otherwise $HOME/port
```

Four clauses, each of which has a way to be wrong:

- **Empty is unset.** `PORT_ROOT=` in a profile is someone clearing the
  variable, never someone naming the root the empty string. In shell this is the
  `${PORT_ROOT:-…}` colon form; the non-colon form hands the walk below an empty
  stop and the safety property silently does not apply.
- **`HOME` unset ⇒ there is no root**, and the caller handles that. This is
  M14's rule for M14's reason: `$HOME/port` with `HOME` unset spells `/port`,
  which is a guess about the machine, and a walk that stops at a guessed path is
  worse than one that does not stop — it un-governs whatever happens to live
  there. Documented rather than silently defaulted.
- **Trailing slashes are stripped.** The stop below is an equality test against
  a physically resolved path. `~/port/` and `~/port` name one directory and
  spell it two ways, and a root that does not exist yet has nothing to resolve
  and keeps its raw spelling — so the two spellings would otherwise give two
  verdicts on one box. Same class as R7 and pass 13's `P13-fs-02`.
- **The default is per OS, and native Windows has none: it is refused**
  ([platforms.md](./platforms.md), harbor#831). WSL2 is Linux and takes the
  `$HOME/port` default. Nothing here guesses a default for a platform nobody
  tests on: a POSIX default asserted as universal is the kind of claim that
  reads correctly on the only machine anyone tests it on.

## The safety property — the walk stops before `PORT_ROOT`

**A marker file at `PORT_ROOT` governs nothing beneath it.** The resolver walks
up from the session cwd looking for `.agents/config.yaml`,
`.agents/project-init.md` or the legacy `.claude/config.yaml`; it stops before
examining `$HOME` (M14) and now also before examining `PORT_ROOT`.

This is M14's hazard one level down, and a likelier one rather than a milder
one. `~/port` is a directory the operator is *told* to create; harbor#620 exists
specifically to put root instruction files in it; and one `.agents/config.yaml`
written there resolves every repository under the workspace to `repo`. The
session hooks stand down and the force-push guard defers to a repo guard that
does not exist — from one file, in the directory the design invites people to
write files into.

**Two stops, not one replacing the other.** `PORT_ROOT` defaults *under* `$HOME`,
so the M14 stop still has work to do for every path outside the workspace.

**Unset is not an opt-out.** The stop applies to the default just as it applies
to an exported value. The pre-move audit for harbor#619 found `PORT_ROOT`,
`HARBOR_REPO`, `ESTATE_DIR` and three more unset in `.zshrc`, `.zprofile` and a
live shell — a guarantee that only held for an exported value would be off on
exactly the machine it was built for.

## Who implements what

| repo | role | owes |
|---|---|---|
| harbor | the floor | `floor_port_root` in `bin/guard-lib.sh` resolves it; `floor_in_repo` stops before it |
| project-init | the scaffolder | stop `prod_guard._find_config`'s walk before it |
| projects-orchestrator | the fleet | default `PO_FLEET_ROOT` and `fleet.yaml`'s scan root from it |

**Nothing writes it.** Every reader takes the environment variable or its
default, so a value written by project-init at init would be a field nothing
reads, and one written into `.agents/config.yaml` would commit a machine path
into the repo. Dropped from harbor#619 on 2026-09-23 for that reason.

`fleet.yaml`'s `roots:` is a **depth-1 scan**, so that default is load-bearing in
the silent direction: point it wrong and the fleet discovers zero projects and
reports no error. It is also gitignored, and `register()` drops two fields and
every comment when it rewrites the file — projects-orchestrator#305. Edit it by
hand.

## Fixtures

`fixtures/marker/cases.json`, ids **M33–M37**, driven by `tests/floor/marker-test.sh`;
the contract text for each is in [marker.md](./marker.md) under its own heading.
A case carries `port_root` (a path, exported for that case) or
`port_root_unset: true` (the default is what is under test). Cases that carry
neither get a `PORT_ROOT` that cannot be an ancestor of anything they build, so
the stop's **absence** is pinned too.

`tests/floor/floor-test.sh` fires two of them — a marker at the root, and a real repo one
level under it — at the **installed** guard rather than at the repo's source,
which is the arm that catches a shipped-vs-source drift.

## What is NOT implemented

- **project-init's and projects-orchestrator's halves ship only when their PRs
  merge** — project-init#1030 (the walker stop) and projects-orchestrator#314
  (the fleet-root default). Until then neither package carries them.
- **M33–M37 run against both walkers** — `resolver` (the floor) and
  `allowlist` (project-init's `_find_config`, since project-init#1030). The
  `descriptor` role walks no markers and does not owe the stop.
- **Per-repo roots are not resolved through `PORT_ROOT` here.** The move
  happened on 2026-09-23. The scans that enumerate the workspace
  (`memory-route.sh`, `harbor-clean.sh`, `port-paths.sh`, lint) derive it from
  `PORT_ROOT`; each repo's own default is a row in `CONTRACTS/roots.tsv`
  (harbor#630), not this file's concern.
- **The `HOME`-unset arm is documented, not fixtured** — exactly as M14's is.
