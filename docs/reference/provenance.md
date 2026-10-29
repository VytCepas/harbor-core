# PROVENANCE — every asset Harbor took from upstream, and what we changed

**A2 (harbor#2).** Harbor does not fork upstream; it **adopts and upgrades** it
(decision 2026-07-25, `docs/reports/platform-epic.md` amendment). This file is what makes that
safe: without an overlay branch there is no `git merge` to tell you what
diverged, so the divergence is written down instead.

It replaces both `A2 · docs/reference/provenance.md` and `A4 · FORK_CHANGES.md`. With no
overlay there is no merge to survive, so A4's *merge-safety* purpose is gone —
but its *legibility* purpose is not, and it lives here as the *Changed on intake*
column.

**This file is load-bearing.** `docs/explanation/admission-baseline.md` records "enumerated lists drift" as an
accepted residual and names **this cadence** as its only mitigation: new provider
key prefixes, new exfil CLIs and new destructive verbs appear constantly, and
nothing else in Harbor will notice.

## Upstream

| | |
|---|---|
| Repo | Daniel Miessler's MIT-licensed upstream project (name withheld by decision, harbor#1149) |
| Pinned at | tag **v7.1.1** = `a4e8e7466c5e01af1fff865c6ad4258282fac63e` |
| Local mirror | `~/.harbor-upstream` — **pristine, never edited**, the diff source for re-harvests (A1, done) |
| Since the pin | upstream `main` has moved and includes a **repo restructure**. Expect harvest diffs to be structural, not just textual. |

Re-harvest is `git -C ~/.harbor-upstream fetch && git diff a4e8e74..<new> -- <path>`,
then re-apply the *Changed on intake* column, then update the row.

## What was taken

| Asset | Upstream path | How taken | Changed on intake | Re-harvest trigger |
|---|---|---|---|---|
| **Security corpus** (B3/B4) — `DANGEROUS_PATTERNS`, `SECRET_VALUE_SHAPES`, `SECRET_ASSIGNMENT_SHAPE`, the external-content warning + injection shapes | `safety-classifier.ts:44-76`, `egress-class-core.ts:27-38`, `Safety.hook.ts:186` | **PORTED — clean-room POSIX rewrite.** No upstream code runs: zero Bun, zero TypeScript, zero daemon. | Rewritten entirely as `bin/guard-*.sh`. Dropped the OpenRouter/US-ZDR routing shapes (an engine concern, not a floor's). Dropped the low-precision `Bearer <token>` and `<NAME>KEY=` shapes — they fired on publishable/anon keys and made routine API work impossible. Converted from "de-auto-approve" to a hard veto (`docs/reports/platform-epic.md`:44). | **Any upstream release.** This is the drift `docs/explanation/admission-baseline.md` warns about — new key prefixes and exfil CLIs land constantly. |
| **System-file containment** (B2) | `containment-zones.ts`, `system-file-guard-core.ts` | PORTED — POSIX rewrite | Narrowed to the floor's self-protection concern only; the upstream content-egress scanner became B4 instead. | Any upstream release |
| **Vendored skills** (I1, I1-ext, and the 2026-07-26 re-take) | `Upstream/install/skills/<Name>/` | **VENDORED as plain markdown** → `vendor/skills/` | De-persona'd and de-platformed per skill — see **`vendor/skills/PROVENANCE.md`** for the per-skill table, verdicts and edits. Methodology and frontmatter kept verbatim. | Upstream skill edits |
| **Append-only observability pattern** (G2) | `OBSERVABILITY/*.jsonl` | **PATTERN ONLY** — the shape was copied, the code was not | Reimplemented as host-partitioned `WORK/sessions/<host>/<date>-<id>.md` | n/a |
| **Memory layout + engine** (D1) | `MEMORY/` layout, `KnowledgeGraph`, `MemoryRetriever` | **CORRECTED 2026-08-13 — TAKEN, as on-demand Bun skill-tools and not the 31337 daemon.** `tools/memory/` holds the engine (`memory-engine.ts`, `store.ts`, `bm25.ts`, `graph.ts`) behind `bin/memory.sh`, with `bin/memory-lint.sh` as the anti-rot gate and `contracts/memory-format.md` as the format seam. This row read "NOT YET TAKEN" for the whole life of the built subsystem. | De-persona'd on intake; two-rung degradation (Bun engine → grep tier) so a missing runtime narrows the answer instead of failing. | Upstream engine edits |
| **Pulse** (E1) | Pulse app | **CORRECTED 2026-08-13 — TAKEN.** Shipped 2026-08-02 as `bin/alert-probe.sh` on a `com.harbor.pulse` launchd schedule, with `bin/alert-notify.sh` as the edge-triggered sink. `docs/explanation/absent-by-decision.md` already recorded it as shipped while this row still read "NOT YET TAKEN" — two governance documents disagreeing about one live subsystem. | Reimplemented rather than installed: a between-sessions health probe, not the upstream app. | n/a |
| **Constitution** (C1) | `UPSTREAM/UPSTREAM_SYSTEM_PROMPT.md` (196 lines) | **CURATED — `policy/constitution.md`.** Rewritten, not copied; never injected via `--append-system-prompt` (`docs/reports/platform-epic.md` §0). | KEPT: the 5 constitutional rules, Ideal-State Prompting, Context Sufficiency, Self-Healing (as a routing table with real destinations). ADAPTED: the language rule → **per-layer** (POSIX floor / Python trio / Bun skill-tools) — upstream's "TypeScript always, never Python" is actively wrong here; the browser doctrine → the **fidelity principle** kept, the Playwright ban dropped; №1 → a response *shape* principle, not a template. DROPPED: the banner, the closer, the DA/principal persona, the memory-delta fields (no hook emits them — an unfillable field teaches the reader the document is partly inert), and **every pointer to `UPSTREAM/RULES/*`, Pulse, Interceptor, the Algorithm runtime and the release-scrub path**. Those pointers were dropped **by name, not repointed**: the upstream mirror is readable at `~/.harbor-upstream`, so a relative pointer would resolve *into* the engine the no-fork decision excluded, and a bare basename is worse — `Philosophy.md` silently resolves to the RedTeam skill's file. ADDED, from Harbor's own record: a test that cannot fail, a false positive is a defect, verify the premise, and a rule with no mechanism is a wish. | Any upstream release |
| **ISA / Algorithm model** (F1) | `UPSTREAM/ALGORITHM/`, ISA skill | **CORRECTED 2026-07-26 — the ISA SKILL IS VENDORED AND INSTALLED.** `vendor/skills/isa/` → `~/.claude/skills/ISA`, full fourteen-section body plus five workflows. **The tier is NOT stated here — ask lint X4, which derives it from disk.** This cell read *"ambient every session"* from 2026-07-29 until 2026-08-22: the skill was flipped to `disable-model-invocation: true` on 2026-07-31, two days after the correction was written, and the correction that fixed one error in this row introduced another in the same sentence. A hand-typed tier is the `Installed` column's mistake one file over, and the repair is the same one `vendor/skills/PROVENANCE.md` already prescribes — stop stating it. This row previously read "MODEL ONLY", and ticket F1 proposed replacing it with a 4-section version — a downgrade nobody caught, because three documents disagreed about one live asset. | De-persona'd on intake. F1's remaining debt — the pointer table and the decision about where a run's ledger lives — is settled in [contracts/isa-ledger.md](../../contracts/isa-ledger.md) and generated by `bin/doc-isa-index.sh`. What is genuinely NOT taken is the ALGORITHM **runtime**: no `~/.claude/UPSTREAM/ALGORITHM/`, no `LATEST`, nothing drives runs from the skill. | Upstream skill edits |

## Licences

The upstream project is MIT (c) 2025 Daniel Miessler, verified against its licence file at the pinned commit. Fabric patterns are MIT, verified from https://raw.githubusercontent.com/danielmiessler/fabric/main/LICENSE. Per-tree licence files and the full list are in `NOTICE`.

## Intake rules (A3 — what survives of the brand rename)

The rename existed to make *upstream's own UI and prompts* read as Harbor/Helm.
Harbor does not run them, so there is nothing to rename and `HELM_ROOT` is moot.
What survives is the rule every intake follows, already applied by I1:

1. **De-persona** — `{DA_IDENTITY.NAME}`, the `kai` roster, ElevenLabs voice IDs.
2. **De-platform** — delete `curl localhost:31337` / voice-notification blocks and
   `UPSTREAM/USER/CUSTOMIZATIONS` blocks.
3. **Repoint, don't restructure** — `~/.claude/UPSTREAM/MEMORY/…` → `~/.claude/MEMORY/…`.
4. **Disable, don't rewrite, load-bearing platform machinery** — mark it
   `harbor: platform ref disabled` so a re-harvest can find it.
5. **Record the surgery here.** An unrecorded edit is one a future harvest silently reverts.

## What was NOT taken, deliberately

**Corrected 2026-07-26.** This section previously reproduced `docs/reports/platform-epic.md`
§6's TRIM list verbatim and named **seven skills that are vendored**
(PrivateInvestigator, WorldThreatModel, Sales, WriteStory, Aphorisms,
BeCreative, ApertureOscillation — I1-ext took them into the invoked tier on
2026-07-24). A stale not-taken list is the worst kind: it is the document
someone reads to decide whether a capability is worth revisiting, and it told
them to stop looking. Lint rule **T6** now fails if a name here has a directory
in `vendor/skills/`.

Upstream ships **51** skills at the pin; `vendor/skills/` holds **28**. The
other 23, by reason:

**Governs upstream itself — nothing to port** (5): `upstream` (its
installer/onboarding), `CreateSkill`, `Migrate` (upstream taxonomy), `Trim` (a
Upstream context-file byte budget), `Upgrade` (upstream upgrade recommendations).

**Declined — the capability is not wanted** (1): `Daemon`. Note the name: it is
**not** a monitor. It aggregates upstream sources into a public profile site
(VitePress → Cloudflare Pages). Harbor's monitoring answer is Pulse, which is
kept — workstream E. Worth harvesting even so: Daemon's `SecurityFilter` is a
**deterministic, code-level, non-LLM** sanitizer with structurally-excluded
source dirs, which is the same posture as `bin/guard-egress.sh` and a better
articulation of it.

**Declined on an unavailable dependency** (2): `Interceptor` — built from source
at the author's own `~/Projects/interceptor`, not obtainable; and `CMUX` —
needs the Mac-only cmux app, and **upstream marks its live-driving path
UNPROVEN** in the skill's own status line.

**Declined on dependency weight or scope** (9): `Art`, `Remotion`,
`AudioEditor`, `Webdesign`, `Apify`, `BrightData`, `LocalIntelligence`,
`USMetrics`, `CreateCLI`.

**Method worth taking, skill not portable** (4). *This row replaces a
"duplicated by the platform Harbor already runs" claim made on 2026-07-26 that
was wrong on three of its four entries — it matched on capability names without
reading the skills.* The overlap is real but partial, and what does not overlap
is the part worth having:

| Skill | What the platform covers | What it does NOT cover |
|---|---|---|
| `Loop` | `/loop` self-paces a repeating task | **Nothing else.** upstream `Loop` runs full Algorithm cycles with a **dead-ends ledger** (rejected approaches carried across iterations) and **MAD confidence gating** (flag a delta below the noise floor instead of banking it). Different mechanism, not a duplicate. |
| `HTML` | `Artifact` publishes a self-contained page | `Artifact` is the *publisher*; `HTML` is a **deterministic renderer above it** — the model emits typed JSON, `Render.ts` owns every layout/type/color choice, with named registers so consecutive outputs do not converge. |
| `Research` | `Workflow` fans out multi-agent research | Its **UrlVerificationProtocol** and confidence-tagged output. The multi-model roster (Gemini/Grok/Perplexity) needs keys Harbor does not have; the verification protocol needs nothing. |
| `Interview` | — | The **method**: read the constitutional files that exist, score staleness per section, and ask *"still right?"* instead of *"what's your mission?"*. Not portable: `TelosFreshness.ts`/`InterviewScan.ts` (Bun), the seven upstream-specific files, the Pulse freshness cache. **Called platform-only twice before; that conflated the method with its plumbing.** |

**Not adjudicated — genuinely open, not declined** (2): `BiasCheck` and
`Hardening`. Both are portable prompt-plus-method skills with no upstream platform
coupling. They are listed here so the omission is visible rather than silent.

`Hardening` is the only one of the two with a **real** twin to merge against —
`verify-test-strength`, which exists in three places. `BiasCheck` was paired in
I2 against `critique`, **which does not exist anywhere**; see the correction on
I2 in `docs/reports/platform-build-tickets.md`. Four skills had
their disposition recorded as "dedupe against X" for an X that was never
checked, which reads as decided and is not.

**Method takes landed 2026-07-26** — the portable half of three skills, without
the skill:

| From | Taken as | Mechanism |
|---|---|---|
| `Loop` — dead-ends ledger | `docs/decisions/rejected-approaches.md` | append-only approach ledger; 10 entries recovered from commit messages |
| `Loop` — MAD confidence gating | `bin/eval-pass-score.sh` | gates docs/explanation/admission-baseline.md's pass table so a delta below the noise floor is not banked |
| `Interview` — staleness as priority | `bin/doc-freshness.sh` | per-document age from git against per-class thresholds; `--open` is its ContextAudit half |
| `Research` — UrlVerificationProtocol | [docs/reference/citations.md](./citations.md) + `bin/doc-cite-verify.sh` + lint **T7** | existence and support recorded as separate columns, because only one is machine-checkable |
| `Doctor` (UPSTREAM/TOOLS) | `bin/deploy-doctor.sh` | probes every external dependency, each row naming **what breaks** — B9 was one instance of a class nobody had enumerated |
| `BudgetCheck` (UPSTREAM/TOOLS) | `bin/context-budget.sh` | a ceiling on what Harbor costs in every session. First run: **already over**, before TELOS/IDENTITY/memory land |

Also not taken: the Pulse **WSL** voice/bridges, and the `DA_IDENTITY` persona.

Also never taken, and this is the whole point of the no-fork decision: the
installer that merges into `~/.claude`, the Bun/TypeScript hook engine,
`InstallHooks.ts` / `InstallSettings.ts`, and the `CORE` constitution injected
via `--append-system-prompt`. §0's verdict stands — *"do not run the upstream
installer/engine/CORE unattended against `~/.claude`."*
