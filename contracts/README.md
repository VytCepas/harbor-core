# CONTRACTS — the cross-layer seams (freeze before parallel build)

Harbor spans four repos (`harbor`, `project-init`, `projects-orchestrator`, `helm-log`). They can only be built **in parallel** if the seams between layers are **first-class, versioned artifacts with fixtures** — not prose in tickets. This directory is the single source of truth for those seams.

| Seam | Direction | Status | Spec |
|---|---|---|---|
| Descriptor | L3 Yard → L2 Fleet + L0 Helm | **already first-class — EXTEND, never reinvent** | [descriptor.md](./descriptor.md) |
| `--json` output | L2 Fleet → L0 Helm | **not yet first-class — freeze here** | [fleet-controller-json.md](./fleet-controller-json.md) |
| Detect-and-defer marker | L3 Yard → L2 Fleet + L0 Helm | **frozen; Helm side implemented, fixtures shared BY ID ONLY** (M12/M13 settled 2026-07-25; **M14 settled 2026-08-02** — [marker.md](./marker.md) says so at its own M14 heading, and this row read "open" until 2026-08-13; case count in `docs/generated/status.md`) | [marker.md](./marker.md) |
| Box profile | L0 Helm → L3 Yard (**the ONLY up-pointing read** — advisory, absent-safe) | **frozen v1; the Yard's reader is implemented and tested** (project-init `box_profile.py`, `tests/unit/test_box_profile.py`). **Helm produces no file yet**: on this box `test -e ~/.claude/box-profile.toml` failed on 2026-10-03, so the wizard runs on its defaults, as the absent-safe clause requires (BOX-1, harbor#325) | [host-profile.md](./host-profile.md) |
| Memory format | shared canonical | conventions | [memory-format.md](./memory-format.md) |
| Naming (every name: files, ids, env, skills) | shared canonical | **the standard** and its registry `standards/naming/`, judged by lint **N4** (harbor#950); the old `contracts/naming.md` is deleted (D-39) | [standards/naming.md](../standards/naming.md) |
| The practice layer, and where it should live | shared canonical | **decision brief 2026-08-29** (R7) — recommends folding it into harbor; nothing moved, the call is the operator's | [knowledge-base.md](./knowledge-base.md) |
| Where a checker lives, and who runs it | shared canonical | **proposed 2026-08-29** (R5) — measured: three contracts, three checkers, zero wired to CI | [gates.md](./gates.md) |
| What a GENERATED report owes its reader | shared canonical | **2026-09-03** (harbor#411) — measured: an audit shipped green on every gate and unreadable to the person who opened it | [reports.md](./reports.md) |
| `prove` target declarations — proving a gate can fail | shared canonical | **proposed 2026-08-30** (R5): the grammar `skills/test-strength/bin/prove.sh` parses and lint **C6** enforces. Every mutator derives its sites from the seed, so no declaration ever states a count; a target with no valid-but-unusual control is refused rather than scored | [prove-targets.md](./prove-targets.md) |
| Subagents — roles, stop rules, the stop check | L0 Helm → every subagent on the box | **written 2026-10-10** (harbor#445 item E): what SubagentStart and SubagentStop receive, the role table, the universal stop rules | [subagent.md](./subagent.md) |
| `harbor` CLI surface | L0 Helm → the operator | **frozen 2026-07-30** (CLI-1); verbs, exit codes and `--json`, enforced by lint **CLI1** | [cli.md](./cli.md) |
| Hooks — the layer split | L0 Helm → every governed repo | **proposed 2026-08-07** (harbor#7): which moment gets a git hook and which needs the harness, plus which injection channels are measured live here and which are only documented | [hooks.md](./hooks.md) |
| Rule packs — just-in-time governance | L0 Helm → every repo on the box, present and future | **implemented 2026-08-08** (harbor#173 · A1): the frontmatter keys, the predicate vocabulary and the two pack tiers. One box wiring serves every repository, so a new project adds a directory rather than a deployment | [injection-rule.md](./injection-rule.md) |
| The ISA ledger — where a run lives, and what indexes it | the vendored ISA skill ↔ Harbor's Log (G2) | **implemented 2026-08-22** (harbor#117 · F1): both write under `MEMORY/WORK`, neither knew about the other. `sessions/` is the Log's reservation; a directory is an ISA run only when it holds `ISA.md`. The index is generated to `build/`, never committed, because its input is machine state | [isa-ledger.md](./isa-ledger.md) |
| Vendoring — refuse, depend, vendor, or take the idea | L0 Helm → every intake decision, in any of the four repos | **written 2026-09-17, not mechanised** (harbor#459): four verdicts, eleven clauses, first match wins, and a verdict names the tier it ships to. Re-derived against the tree, which corrected the proposal: archify was vendored, and three of the "decisions" were closures on other grounds. Nothing reads it yet — #447 and #448 are where a check would live | [vendoring.md](./vendoring.md) |
| `PORT_ROOT` — the workspace root | shared canonical (L0 Helm + L3 Yard + L2 Fleet) | **Helm's half implemented 2026-09-22** (harbor#619): one resolution rule, re-implemented per language like the marker beside it. The floor resolves it and its marker walk stops before it, fixtured M33–M37. project-init's and projects-orchestrator's halves are project-init#1030 and projects-orchestrator#314 and land when those merge — the file says so rather than reading as done | [port-root.md](./port-root.md) |
| The private layer - `harbor-private/` | core reads it, data only | **implemented 2026-10-10** (harbor#966): the registry reader and harbor.toml reader in `scope-roots.sh`, `harbor scope install`, and the sibling-literal ratchet. The floor does not read it | [private-layer.md](./private-layer.md) |
| The access card - the format of the access register | core ships the format and the checker; the cards are private data | **implemented 2026-10-11** (harbor#1149): the card fields, the `account:` line, the tier ladder, the generated `ACCOUNTS.md` and `DISPATCH.md`, and how `sh bin/scope-roots.sh --access` finds the register. Core holds no card | [access-card.md](./access-card.md) |
| The access register - one list of every identity an agent may use | core ships the format, the reader (`harbor access`) and the gate; the entries are private data | **implemented 2026-10-12** (harbor#1205): the entry fields, the `secret:` reference (a value never goes in the register), `bin/secret` refusing a ref no entry names (with `contracts/secret-legacy-refs.txt`, which only goes down), `harbor access add\|list\|has\|refs\|check`, and the `lint.credential-reads` ratchet. Migration of the existing consumers is the follow-up | [access-register.md](./access-register.md) |
| The pack loader - `harbor pack` | a workload repo's `harbor-pack/` -> the config dir | **built 2026-10-11** (harbor#1149): `bin/pack.sh` list/install/remove, five refusals, an exact-remove manifest; `deploy` installs the `packs` harbor.toml lists, a pack's check rows are the private `checks.md` fragment shape composed into the one `bin/docs/reference/checks.md` | [pack.md](./pack.md) |
| Which browser, and why — the router | L0 Helm → every session, measurement skill loaded or not | **implemented 2026-09-06** (harbor#458 · C1): the routing table lived inside a workload skill and nowhere else, so harbor#445 refused a browser capability on the opposite of what that table said. Two axes — login, and attended-vs-unattended — six rows, one of them (a live logged-in profile) declared and **refused** because it is an unledgered credential. `harbor browser route` prints it | [browser-routing.md](./browser-routing.md) |
| A finding — key, digest, age, disposition | every detecting layer → the operator | **implemented** for the lint and check tiers (harbor#590, #856): `bin/lint-findings.sh` reconciles daily under launchd (`docs/reference/checks.md` row `findings`), lint **FL1**/**FL2** hold its lanes and subjects; the CI, review and floor tiers are still intent, as its header says. One GitHub issue per rule firing on the published default branch, keyed by a hidden marker. A digest of the emitter-declared subjects, never the message. `accepted` and `superseded` are a person's, `fixed` is the reconcile's and needs a passing run. The per-call guard ledger stays local, and the daily judge promotes candidates from it | [finding.md](./finding.md) |
| The `.helm-*` state files — integrity or cache | L0 Helm's writers → the floor's readers | **implemented 2026-09-27** (harbor#779): one row per `.helm-*` name in `bin/`, each naming the reader that trusts it and the writer that owns it. An integrity row is refused by guard-bash, guard-selfedit and the B1 deny list. Lint **F14** fails an unclassified name, a stale row, and a layer that disagrees with the table | [control-plane-state.md](./control-plane-state.md) |
| One `--status` for every drift check — desired, observed, delta and age per row | L0 Helm check → the console, the batch report and the operator | **PR 1 implemented 2026-10-14** (harbor#1031): the record shape, D-29 exit codes and the first-seen state in `bin/library-log.sh`; `memory-route.sh` and `drift-reference-check.sh` adopt it, and the adopters are derived from the `controls.tsv` check rows whose script answers `--status`. The allowlist, the consumers and the other adopters are PR 2 | [reconcile.md](./reconcile.md) |
| One log format — the run log, beside the guard channel and harness protocol output | L0 Helm → the operator, CI, and the agent reading a run | **implemented 2026-09-27** (harbor#771): the line shape and its TAG set, a `fix:` after every `FAIL`, one summary line whose exit code agrees, and the log file under `backups/<tool>/<TS>/`. `bin/library-log.sh` writes it and lint **LOG1** enforces it, with a ratchet, `log-exempt.tsv`, that only shrinks. The installers convert in Wave B of the install standard, so until then their rows say so | [logging.md](./logging.md) |
| The test contract — the rules every governed repo's tests follow | shared canonical (Harbor, project-init, projects-orchestrator, every scaffolded repo) | **written 2026-09-28** (harbor#734, epic harbor#733): six rules, each naming the mechanism per implementation, one entry point (`just test`) and one summary line a fleet runner adds up; the gaps no mechanism covers yet are named with their tickets | [test-contract.md](./test-contract.md) |
| Git verbs — the git command shapes that pass, and the ones refused on purpose | L0 Helm → every session on the box | **implemented 2026-10-17** (harbor#1291): reads, everyday writes and gated forms, each naming what lets it through and the spelling that passes. `bin/floor-deny.sh` derives the allow and ask rules from it; `tests/admission/git/verbs.test.sh` holds it to those rules, the deny list and guard-bash's read-only git list | [git-verbs.md](./git-verbs.md) |
| The suite cache — a suite whose inputs already passed is `cached`, not re-run | `bin/test-suite-run.sh` → CI and the operator | **implemented 2026-10-17, opt-in** (harbor#1288): `HARBOR_SUITE_CACHE=1`; the key is git object ids of the suite, its declared paths, the shared test library and every path it names; never on main, never when everything runs, a failure never cached, a store per trust domain. The limits (paths built at runtime, state outside the repo) are stated, not caught | [suite-cache.md](./suite-cache.md) |
| Platforms — where every solution runs | shared canonical (Harbor, project-init, projects-orchestrator, every scaffolded repo) | **written 2026-09-30, not enforced** (harbor#832, epic harbor#831): macOS and Linux; Windows only inside WSL2; a native Windows shell is refused. Each repo's refusal is a named ticket, and harbor's macOS-only parts (#617, #618) are its Linux gap | [platforms.md](./platforms.md) |

## Rules for every seam

**Read the status column beside each rule.** Three of the five below are the
intent and not the state, and until 2026-08-13 all five were written as though
they held — which is the failure mode this whole directory exists to prevent, in
the document that indexes it.

| Rule | State |
|---|---|
| Each schema carries a **`schema_version`** | holds where a schema exists |
| The **producer** ships golden fixtures; **every consumer** validates against the *same* fixtures | **NOT the state.** Measured 2026-08-13: `project-init` and `projects-orchestrator` **cite** `fixtures/marker/cases.json` in docstrings and reuse its case **ids**; neither opens the file and neither names a harbor path anywhere in its tests. Shared vocabulary, re-implemented assertions. The drift this rule exists to prevent is live |
| **Additive-only** within a major version; a breaking change bumps and lands lock-step | intent; nothing measures it |
| A **CI freshness check** fails if a consumer's vendored copy drifts from the source | **the harbor side exists** (lint X2/X2b/X8/CM3, `drift-renew-check.sh`); no consumer repo runs one against harbor |
| Any PR touching a seam is labeled `3-repo-coordinated` and cross-linked | **IMPOSSIBLE AS WRITTEN.** The label does not exist: `gh label list` returns 17 labels and none matches `3-repo`. Across the repo's whole PR history exactly one PR carries any label at all. A rule nothing can satisfy is not a rule |

## How these are enforced

Until 2026-07-25 the rules above were **prose** — an audit found harbor had no
CI, no active git hooks, and exactly one continuously-enforced rule (the
work-log gitleaks pre-push gate). The line about a "CI freshness check" described
something that did not exist. What enforces what today:

| Mechanism | Enforces | When it runs |
|---|---|---|
| `bin/lint-conventions.sh` | the naming/shape/safety conventions, plus the seam rules — **M1** (the marker walk lives in exactly one function), **X1/X2** (neither the dev sandbox nor the live install may drift from `bin/`), **K1/T3** (a cited path must resolve), **T1/T2** (docs/generated/status.md is generated, and no other document restates a count). Run `sh bin/lint-conventions.sh --list` for the current set; the count is in `docs/generated/status.md`. | pre-commit + CI |
| `hooks/pre-commit` | the linter, locally | every commit in **this** checkout (bypass: `--no-verify`) — see the note below |
| `hooks/commit-msg` | the no-AI-attribution rule, at the only moment it is preventable. **Defines the pattern lint C2 reads** — one definition, not two greps for the same shape | **NOT INSTALLED on this box** — measured 2026-08-13, `.git/hooks/` holds one symlink (`pre-commit`, hand-made 2026-07-25). The rule is enforced only by lint C2 in CI, i.e. after the commit exists |
| `hooks/pre-push` | the suites `bin/test-suite-select.sh` selects for the pushed range, before the serialised runner is occupied. Prints the stood-down count, because a silent cap reads as full coverage | **NOT INSTALLED on this box** — the push that landed harbor#214 ran no suites |
| `bin/govern-hook.sh` | the merge moment — the one a git hook cannot reach, because a PR merge is server-side. Conditional or silent | **wired since 2026-08-08** via the rule-pack channel: `context-rules/harbor/post-merge-state.md` → `merge-note.sh` → `sh bin/govern-hook.sh --note`, with `inject-hook.sh` on `PostToolUse` in the live settings. Since harbor#516 floor-install also wires `govern-hook.sh --box` on PreToolUse `Bash`, so the merge deny reaches sessions launched outside the repo (docs/explanation/admission-baseline.md). This row read "not wired yet" until 2026-08-13. See [hooks.md](./hooks.md) |

**The git hooks are a manual, per-checkout step, and nothing installs them.** No
script in `bin/` and no `core.hooksPath` setting creates those symlinks — grep for
`git/hooks` or `core.hooksPath` and there are no matches, which is why two of the
three have never run here. This is recorded rather than mechanised on purpose: a
lint rule over `.git/hooks` would fire on every CI checkout, where no hook is
installed and none should be, and a rule that is red in every run protects
nothing (CONSTITUTION §2.11). The install, in one command that covers all three
at once and survives future hooks:

```sh
git config core.hooksPath hooks
```

`hooks/commit-msg` does discriminate — verified 2026-08-13 by running it directly:
a clean message exits 0, `Co-Authored-By: Claude` and the robot-emoji trailer both
exit 1. It is a working guard that is switched off.
| `.github/workflows/governance.yml` | linter + the floor suite (`tests/admission/baseline/`) + `tests/deploy/restore/recover.test.sh` | every push and PR |
| `tests/admission/baseline/baseline.test.sh` and its `floor.<part>-test.sh` parts | the security floor's behaviour — a mutation pass, a SessionStart perf bound, and assertions on the INSTALLED hook matchers (assertion count: `docs/generated/status.md`) | CI + on demand |
| `tests/scope/marker/marker.test.sh` | the detect-and-defer spec, against `fixtures/marker/cases.json`. **Harbor is the only repo that READS that file** — the two consumers cite it and reuse its case ids in their own Python assertions, which is a shared vocabulary and not a shared fixture suite (measured 2026-08-13; this row claimed they "read too") | CI + on demand |
| `bin/guard-integrity.sh` (B6) | runtime drift: deny/lock hashes, guard content pins, hook wiring | every SessionStart, once installed |
| `worklog/pre-push` | fail-closed gitleaks gate on the work-log | every push to `helm-log` |

**A convention that nothing checks is a suggestion.** Adding a rule to
`bin/lint-conventions.sh` is how a convention becomes binding; if a rule cannot
be expressed as a check, say so in the contract rather than pretending it is
enforced. Exceptions belong in the rule **with their reason** — a linter that
flags correct design teaches people to ignore it.
