# Detect-and-defer marker seam — FREEZE (and fix the name collision)

The marker tells every layer *"this is a project-init-governed repo → the repo wins on workflow, conventions and tooling, and the global (Helm) engine stands down for those."* **The stand-down is scoped, not total** (harbor#581, decided 2026-09-22): the constitution's five rules never yield, and every place Harbor stands down is listed in [What stands down inside a governed repo](#what-stands-down-inside-a-governed-repo), which lint **M2** checks against the code. It must be **one defined signal** all three layers read identically.

## The key
- Use **`context: repo`** in `.agents/config.yaml`.
- ~~emitted by **augmenting the existing** `templates/base/dot_agents/project-init.md.tmpl`~~ — **CORRECTED 2026-07-25 (PI-901).** That file is Markdown. `.agents/config.yaml` — the file `prod_guard._find_config` actually reads — renders from **`templates/base/dot_agents/config.yaml.tmpl`**, which is where every other config key already flows. **Landed:** project-init [#902](https://github.com/VytCepas/project-init/pull/902).
- Do **NOT** use `governance:` — project-init already defines `governance` as a **boolean** (the SYSTEM_CARD gate toggle, `variables.py`). Overloading it is a wizard/schema collision. **Landed:** a contract test now asserts no top-level `governance` key appears in a `governance=True` render, so the collision cannot come back by accident.
- **Add `context` to `descriptor.schema.json`** (additive, v2) so the contract test protects it — otherwise project-init could drop/rename it and no test fails, silently breaking Helm's deferral in every scaffolded repo. **Landed, with two refinements:**
  - **Not in `required`.** Every descriptor scaffolded before PI-901 lacks the key; requiring it would fail validation across the whole installed base until H3's back-fill finishes. What protects the key instead is a **producer-side contract test** asserting a fresh scaffold emits it — a schema property alone does not fail when the template drops it.
  - **`enum: [repo, ambient]`.** For a key three implementations in two languages read, the realistic failure is a near-miss value (`Repo`, `project`) that looks marked to a human and resolves to nothing in code.
- **`upgrade` back-fills it.** `config.yaml` is never re-rendered wholesale, so the template line alone would only ever mark NEW projects. project-init's `_ensure_context_key` splices it into existing configs, and never overwrites an owner's `context: ambient`.

## Resolution algorithm (ONE spec, shared fixtures)
Input: cwd. Walk up. Output: `repo | ambient`.
- `repo` **iff** a marker is found: `.agents/` present (`project-init.md` / `config.yaml`) **OR** legacy `.claude/config.yaml`.
- **Ambiguous / unset ⇒ `repo`** for any hook that WRITES the global log (fail-toward-repo).
- **Nested repos: the innermost marker wins.**

### The marker's VALUE (added 2026-07-25 — PI-901 gave the marker one)
The original spec decided everything from marker **presence**. `context:` now carries a value, and a value nobody reads is a field whose documented meaning is a lie. So:

- **`context: ambient` in the found marker's `config.yaml` ⇒ `ambient`,** even though the marker is present. It is the owner opting this repo back in to the global layer.
- **Read it AT the marker the walk finds, and decide there.** The innermost marker wins, so an explicit inner opt-out must not fall through and be overruled by an outer repo's marker.
- **`context` absent ⇒ UNKNOWN, fall back to presence. Never read absence as `ambient`** — that would un-govern the entire pre-PI-901 installed base in one step.
- **Top-level only, matched at column 0.** A `context:` indented under another block is a different key that shares a name.
- **But every valid top-level *spelling* counts** — `context : ambient`, `"context": ambient`, `context: "ambient"`. The reader is deliberately the permissive one about spelling: missing a genuine opt-out means resolving `repo` and **standing the floor down**, the unsafe direction. project-init's `_CONTEXT_KEY_RE` preserves exactly these spellings on upgrade; a spelling the writer keeps but the reader misses is an opt-out that survives and is then ignored (found by review on project-init [#902](https://github.com/VytCepas/project-init/pull/902)).
- The legacy `.claude/config.yaml` marker is **not** consulted for the value: it predates the field and no schema defines it there.

**Implementation status — all three read it as of 2026-08-02.** Helm's `floor_in_repo` was first, because for a **guard** the direction is safe in only one way: `ambient` means *stay fully armed*, and the dangerous direction (standing the floor down) is decided by presence and is not reachable through this value. The other two landed with the H1 close-out, each in the form its own role allows:

| reader | what `ambient` does there | why that is the safe direction |
|---|---|---|
| `floor_in_repo` | resolves `ambient` — the floor stays armed | the repo declined to govern, so the global layer must not stand down |
| `prod_guard._find_config` | returns `None` — the repo supplies **no** `safety.allow` | a repo that opted out of governed status does not get to relax the deny table; no allowlist means keep guarding |
| `resolve_config` / `parse_config` | surfaces `context` on the descriptor; discovery is unchanged | the fleet manages a project either way — dropping it would delete it from `projects`/`snapshot`/`audit`/`heal` on the strength of a field about which *agent layer* governs |

`prod_guard` **decides** at the marker rather than continuing the walk, which is the M19 rule and the difference between a forgery and a declaration: a symlink is refused and the walk continues, because nobody meant it; an `ambient` value stops the walk, because the owner did. The orchestrator gets M22/M23/M25–M27 for free — it parses real YAML, where a commented-out key is not a key and an indented one belongs to its parent block.

Fixtures **M18–M23, M25–M27** pin all seven rules above, and `tests/floor/marker-test.sh` now runs them against all three.

## One spec, three ROLES, one fixture suite

This section read *"three implementations of one predicate"* until 2026-08-02. **That was measured and it was false** — and it mattered, because it made two readers look non-conformant when they were answering a different question, and it hid the places where they genuinely were. They share the marker; they do not share the question:

| role | question | implementation | verdict mapping |
|---|---|---|---|
| **resolver** | *does a repo govern this cwd?* | Helm `floor_in_repo` (POSIX sh) | the verdict itself |
| **allowlist** | *which config supplies `safety.allow` here?* | project-init `prod_guard._find_config` (Python) | a config ⇒ `repo`, `None` ⇒ `ambient` |
| **descriptor** | *where is THIS project's descriptor?* | projects-orchestrator `resolve_config` (Python) | a config ⇒ `repo` unless its `context` says `ambient`, `None` ⇒ `ambient` |

Only the resolver walks up **and** accepts every marker spelling. The allowlist role walks but needs `.agents/config.yaml` specifically — `project-init.md` carries no allowlist. The descriptor role does not walk at all: the fleet has already pointed it at a project directory, and a walk would make a subdirectory resolve as a project.

So each fixture declares the `roles` it applies to (absent ⇒ all three), and **`tests/floor/marker-test.sh` drives all three from the one file** — the shell inline, the two Python roles through one adapter process each. A missing sibling clone SKIPS loudly; a clone that is present and disagrees FAILS, because harbor owns the contract. `HARBOR_SKIP_CROSS=1` runs the shell alone.

The POSIX floor must still **NOT** import the private `_find_config` across a language boundary — it re-implements the same spec, and the fixtures are what pin the two together.

**What every role owes regardless of question:** marker validity (M11–M13, M24 — a named non-symlink FILE), the `context:` value rules (M18–M27), and, for the two that walk, the `$HOME` stop (M14, M28–M30) and the `PORT_ROOT` stop (M33–M37, harbor#619 — owed by both walkers, implemented by the resolver only so far).

## The two divergences — SETTLED 2026-07-25 (owner)

They were not hypotheticals. `prod_guard._find_config` and Helm's `floor_in_repo` disagreed by default, and nothing surfaced it.

| case | was | now | who changed |
|---|---|---|---|
| **M12** bare empty `.agents/` | project-init `ambient` (requires a *file*) · Helm `repo` (accepts the bare dir) | **`ambient` — a named marker FILE is required** | **Helm.** The spec always read "`.agents/` present (`project-init.md` / `config.yaml`)"; Helm was the permissive one, which is the wrong direction for a guard — a bare directory made the floor stand down over a repo with no policy in it yet, exactly the window a scaffolder opens when it `mkdir`s `.agents/` before writing. |
| **M13** symlinked marker | project-init `repo` (`is_file()` follows) · Helm `ambient` (refused) | **`ambient` — refused, and the walk continues** | **project-init** ([#904](https://github.com/VytCepas/project-init/pull/904)). |

**M13 was a live hole in project-init, not just a contract mismatch.** `_find_config` locates the file `safety.allow` is read from, so a planted `.agents` link supplied its own allowlist and `allow: [".*"]` switched the whole destructive-command deny table off — terraform destroy, kubectl delete, DROP DATABASE, `rm -rf` outside the project. The link is the entire payload; nothing inside the repo has to change. Refusing is also the safe default on its own: no allowlist means keep guarding.

Both refusals **continue the walk** rather than returning, so a refused inner marker cannot shadow a real outer one.

### M14 — SETTLED 2026-08-02 (owner): the walk stops BEFORE `$HOME`

A marker at `$HOME` resolved every directory beneath it to `repo` and stood the global layer down machine-wide, from one file. Both walkers went to `/` with no stop condition, so it was never a divergence — which is why it stayed open while the divergences got fixed.

**The decision: the walk ends at `$HOME` without examining it.** Everything below `$HOME` resolves exactly as before, and a path outside `$HOME` still walks to `/`.

- **The hazard is an accident, not an attack.** `project-init` run once in the wrong cwd scaffolds `.agents/` right there. M12 raised the bar from a bare directory to a named FILE and did not help, because a scaffolder writes named files.
- **Safe in every role.** The floor stays armed; `prod_guard` finds no config and therefore no `safety.allow` to relax its deny table with; the orchestrator simply does not call `$HOME` a project.
- **`HOME` unset ⇒ the stop does not apply.** There is no home to stop before, and inventing one would be a guess about the machine. Documented rather than silently defaulted.
- **Compare resolved paths.** The stop is an equality test, and `$HOME/.`, `$HOME//x/..` and a symlinked route all spell the same directory differently. Helm resolves the cwd once with `cd -P` before walking (every ancestor a `dirname` yields is then physical too); `prod_guard` calls `Path.resolve()`. This is the same class as R7 and pass 13's `P13-fs-02`, where string-comparing path spellings got past a guard.
- Re-verified on the reference machine 2026-08-02: neither `~/.agents` nor `~/.claude/config.yaml` exists, and the floor resolves `ambient` at `$HOME` and one level down.

Fixtures **M14** (refused), **M28** (a real repo under `$HOME` still resolves `repo` — the stop must not over-fire), **M29** (a `$HOME` that is not an ancestor changes nothing) and **M30** (the boundary is *before* `$HOME`, not *at* it) pin all four directions.

### M33–M37 — harbor#619: the walk also stops before `PORT_ROOT`

The governed repos move out of `$HOME` and into a workspace root, `PORT_ROOT`,
defaulting to `$HOME/port`. The setting itself — its resolution rule, who writes
it, who reads it — is [port-root.md](./port-root.md). What belongs here is the
one thing it changes about this spec: **the walk stops before `PORT_ROOT`, as it
stops before `$HOME`.**

**This is M14's hazard one level down, and a likelier one.** `~/port` is a
directory the operator is told to create, harbor#620 exists specifically to put root
instruction files in it, and one `.agents/config.yaml` there resolves every
repository under the workspace to `repo` — the session hooks stand down and the
force-push guard defers to a repo guard that does not exist. M14 was an accident
a scaffolder could cause; this one is a design that invites the file.

- **Two stops, not one replacing the other.** `PORT_ROOT` defaults *under*
  `$HOME`, so M14 still decides every path outside the workspace.
- **Unset is not an opt-out.** The stop applies to the default exactly as it
  applies to an exported value. The pre-move audit for #619 measured `PORT_ROOT`
  unset in `.zshrc`, `.zprofile` and a live shell, so a guarantee that held only
  for an exported value would be off on the machine it was built for. **M37** is
  that case and is the one the implementation is likeliest to get wrong.
- **Compare resolved paths**, for M14's reason and by M14's method.
- **`HOME` unset and `PORT_ROOT` unset ⇒ no root and no stop.** Inventing
  `/port` would be a guess about the machine.

Fixtures **M33** (a marker at the root is never examined), **M34** (a real repo
one level under the root still resolves `repo` — and after the move that is
*every* repo the operator owns, so an over-firing stop would un-govern the whole
installed base while reading as a security fix), **M35** (a `PORT_ROOT` that is
not an ancestor changes nothing) and **M36** (the boundary is *before* the root,
so a cross-repo session started in the workspace resolves `ambient`) pin the four
directions; **M37** pins the default.

**Scoped to `resolver` and `allowlist`.** Both walkers owe this stop, and both
now have it: the floor's since harbor#631, project-init's `_find_config` since
project-init#1030. `tests/floor/marker-test.sh` hands the case's `PORT_ROOT` to the
allowlist adapter as a fifth column, `-` meaning unset so M37 exercises the
default there as well.

## What stands down inside a governed repo

Added 2026-09-24 for harbor#581. Decision (A): the repo wins on workflow, conventions and tooling, and the five constitutional rules never yield. This table is every place Harbor's code stands down because a repo governs the cwd. **A marker alone hands nothing off** (harbor#954, D-46): a rule stands down only to a guard the repo actually wires, and the engine only on the repo's explicit `worklog: off`. Lint **M2** holds it to the code both ways: a call with no row fails, and so does a row with no call. A row covers a file and a function, not a line, so a file may stand down **once** per function. A second call would inherit the first one's tier, and M2 fails it. A shell script is anything named `*.sh` or starting with a shell shebang, so `bin/harbor` and `hooks/pre-commit` are covered.

| site | stands down via | tier | what stops | ticket |
|---|---|---|---|---|
| `bin/guard-bash.sh` | `floor_repo_wires` | project | the protected-branch force-push rules, only where the repo wires `github_command_guard` (a PreToolUse hook, or the `project-init-lifecycle` plugin enabled and installed), which then owns them; a marker alone keeps them armed | harbor#954 |
| `bin/worklog-push.sh` | `floor_engine_stand_down` | engine | appending this session to the machine-wide work log, only where the repo's `.agents/config.yaml` says `worklog: off` | harbor#954 |
| `bin/memory-harvest.sh` | `floor_engine_stand_down` | engine | reconciling the work log into memory, only on `worklog: off` | harbor#954 |
| `bin/context-resolve.sh` | `floor_in_repo` | report | nothing: it records the session's verdict | — |
| `bin/fleet-sessions.sh` | `floor_in_repo` | report | nothing: it prints each session's verdict | — |

**The tiers.**
- `project`: a workflow, convention or tooling rule, which (A) lets the repo own.
- `engine`: Harbor acting on the operator's behalf across repos. Standing down means not acting; no rule is withdrawn.
- `report`: reads the verdict and stands nothing down.
- `constitutional`: enforces one of the five. Under (A) it may not stand down at all, so a row with this tier is a declared exception, and M2 fails it unless it names the ticket that owns the decision. **No row carries it today.** The one exception, the Stop gate (`bin/guard-stop.sh`, SG-1 and SG-2 of №2), was armed everywhere by harbor#676.

**What M2 cannot check.**
- Whether a tier is *true* is judgment: a №3 guard declared `project` passes. The table makes the claim explicit and reviewable, not correct.
- A stand-down that bypasses all three functions (`floor_in_repo`, `floor_repo_wires`, `floor_engine_stand_down`) is invisible to M2. M1 is what keeps marker-based stand-downs on `floor_in_repo`.
- Whether `floor_repo_wires` reads the right wiring is not M2's question; the guard suite fires the force-push rows against wired and unwired fixture repos.
- `bin/prod-guard-ambient.sh` defers on a different predicate: whether the repo wires its own `prod_guard`. It hands the rule to an equivalent guard rather than withdrawing it, so it is not listed.

## `.agents/` stays canonical; `.claude/` stays a generated mirror

Raised 2026-07-25: should `.claude/` become the primary directory, since Claude Code reads only `.claude/` natively? **No** — recorded here so it is not re-litigated:

1. **`.claude/` is vendor-specific and the scaffolder is not.** project-init already ships surface overlays for Codex, Antigravity, Amp and Junie. Making `.claude/` primary declares every scaffolded project a Claude project, which is the coupling `.agents/` exists to avoid.
2. **PI-627 already moved the other way, deliberately, with a failure behind it.** The contract surfaces were relocated `.claude/` → `.agents/` because the split-brain broke the downstream orchestrator; `test_descriptor_is_agents_only_never_claude` and `_PROJECTION_EXCLUDE` keep the descriptor in exactly one place.
3. **The reason `.claude/` feels primary is already solved.** `_generate_claude_projection` mirrors settings/hooks/skills/commands/agents into it. The descriptor is deliberately *not* mirrored, because a config with two homes is a config with two answers.
4. **The marker spec already accepts both**, so a project handed off without Helm resolves identically either way.

The real inconsistency was never the directory name — it was that the two implementations keyed off different predicates. That is what M12 and M13 fixed.

_Owners: H1 / H3 (project-init + orchestrator), H2 + B5 (helm)._
