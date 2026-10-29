# COVERAGE — upstream's hook surface, and Harbor's disposition for each

**Why this file exists.** A 186-capability coverage sweep ran on 2026-07-26 and
found 73 capabilities *unnoticed* — neither built, ticketed, nor decided
against. Its findings were written into **a commit message** (`ea65713`) and
nowhere else. Asked two days later whether the backlog was recorded, the honest
answer was no: the largest artefact of the largest review lived somewhere nobody
would look. That is the same defect as the stale not-taken list (T6) and the
phantom I2 pairs, for the third time.

So this file is **re-derived from the pin**, not reconstructed from that report.
Skills live in [docs/reference/provenance.md](./provenance.md); this covers the **hook engine**,
which is where the unnoticed capabilities concentrated — Harbor ships a handful of
guards against upstream's 43 hooks, and most of that gap had never been looked at.
The guard count is in `docs/generated/status.md` and is stated nowhere else — not
even here, which is the repair: this line used to carry the number, and carried
it wrong. `guard-lib.sh` matches `guard-*.sh` and is a library that vetoes
nothing, so a glob counted it and every document quoting the total promised a
guard that does not exist. T2 did not catch it because the rule keys on the
two-word phrase "floor guards" and this sentence used the bare noun — a copy of a
generated fact, hiding behind a synonym.

Upstream: `Upstream/install/hooks/` @ `a4e8e74`. Lint rule **T8** fails if a hook
exists there with no row here — the point is that a gap must be *visible*, not
that it must be closed.

**Disposition vocabulary.** `covered` — Harbor has it. `different-machinery` —
the platform provides it another way. `ticketed` — a ticket exists. `declined` —
decided against, with a reason. **`OPEN`** — nobody has decided. An OPEN row is
not a bug; an *undeclared* OPEN row is.

## The four that matter most

Pulled out because each closes a gap Harbor has already named as a problem.

| Upstream | Harbor's gap it answers | Status |
|---|---|---|
| `EventLogger` — "unified observability event logger" | `bin/floor-observe.sh` + `floor_log_decision` | **BUILT** — L1 / harbor#41. Redacted by construction, not by scanner: rule id, verdict, shape class, tool class, keyed truncated digest — never the command text. |
| `VerificationGate` — "task-aware verification gate (Stop)" | №2 Verification is Harbor's longest constitutional rule and had **no mechanism**, in a file that says *"a rule with no mechanism is a wish"* | **NARROWED 2026-08-23** — harbor#291 |
| `WorkCompletionLearning` — "extract learnings from completed work" | the work-log payload is one line per session | **OPEN**, depends on L1 |
| `SatisfactionCapture` — implicit + explicit satisfaction rating | no feedback signal of any kind | **OPEN**, depends on L1 — and **has no ticket anywhere**, which is why its consumer M6 was voided 2026-08-05 rather than left waiting on it. Still a genuine gap; it needs its own ticket before anything can synthesise over it |

`VerificationGate` was the sharpest of these: upstream blocks a done-claim at the
Stop event when the transcript shows no matching evidence. Harbor stated the same
rule constitutionally and enforced it nowhere.

**Half of it is now built** — `bin/guard-stop.sh` (harbor#291), opt-in per box.
The half that is built is the half a shell script can decide without judgement:
where the *repo* defines what evidence means, the gate refuses the turn until the
evidence exists. A floor surface edited with no `floor-test.sh` run after it; a
suite this session ran and left red. Both read from the transcript, never from
the wording, which is the property that makes rewording useless against it.

**`Stop` is the end of a TURN, not of a session** — the binary's own summaries at
2.1.241 are `Stop`: *"Right before Claude concludes its response"* and
`SessionEnd`: *"When a session is ending"*. So the gate refuses **once per
distinct defect**, not once per turn: at every-turn cadence an unverified floor
edit would refuse every later turn until a five-minute suite run, including the
turn spent writing its assertion, and §2.11 says what happens to a guard like
that. The nudge also lands at the earliest moment anything can be done about it,
which is strictly better than the session-end firing this was first designed for.

**The half that is not built is the general grader, and it is not a scheduling
matter.** Deciding whether an arbitrary claim is a done-claim is judgement, and
`sh` cannot do it. The route exists — a `prompt` or `agent` hook evaluates a
condition with a model — but the table above records both as restricted to the
three tool events, so not at Stop. Until that changes, the general case is open
by *platform*, not by neglect, and the row must not be flipped on the strength of
the narrow gate.

## Self-healing, precisely

`HookHealer` is the hook that prompted *"will it self-heal?"*. Read at the pin,
it is **much narrower than the name suggests** — and knowing that is worth more
than the hook:

> *"Self-healing for the registered-script **exec-bit class**. The Write tool
> creates files mode 0644. A hook registered as a direct-exec command then fails
> every invocation with Permission denied until someone notices."*

It repairs **one failure class**, automatically, and warns on two others. It is
not a system that observes recurring failures and rewrites itself. Two design
details are worth stealing regardless: it is registered as `bun <path>` so it is
**immune to losing its own exec bit**, and it is non-blocking on every path
including internal error.

Harbor's equivalent exposure is real — `bin/floor-install.sh` writes guards that
must be executable — but Harbor's shape differs (guards are invoked as
`/bin/sh <path>`, so the exec bit is not load-bearing). **Disposition: declined
as written, class re-checked.** The general self-heal the question was really
about does not exist upstream either.

## Full surface

| Hook | Purpose | Disposition |
|---|---|---|
| `PreToolGuard` | the ONE PreToolUse blocking-guard dispatcher | **covered** — B2–B5, deliberately as separate guards; one dispatcher is a single point of failure for the whole floor |
| `SystemFileGuard` | blocks writes of user-identifying patterns | **covered** — `guard-selfedit.sh` (B2) |
| `EgressClassGuard` | PreToolUse Bash gate for the data-class model | **covered** — `guard-egress.sh` (B4) |
| `Safety` | the DANGEROUS_PATTERNS scanner | **covered** — `guard-bash.sh` (B3), converted from de-auto-approve to hard veto |
| `IntegrityCheck` | integrity check (SessionEnd) | **covered** — `guard-integrity.sh` (B6), moved to SessionStart and fail-CLOSED |
| `EventLogger` | unified observability event logger | **BUILT** — L1 / harbor#41 |
| `VerificationGate` | task-aware verification gate (Stop) | **NARROWED, still OPEN** — harbor#291 gives №2 teeth for the classes where the repo already DEFINES the evidence (a floor edit ⇒ its suite; a red suite ⇒ a green one). The general done-claim grader is still missing and cannot be built in `sh`: grading a claim needs a `prompt`/`agent` hook and `contracts/hooks.md` records those as restricted to the three tool events. Do not flip this row to BUILT on the strength of the Stop gate |
| `WorkCompletionLearning` | extract learnings from completed work | **OPEN** — the work-log's missing payload |
| `SatisfactionCapture` | implicit + explicit satisfaction rating | **OPEN** — the only feedback signal upstream has, and Harbor has no rating surface at all. Its would-be consumer (`LearningPatternSynthesis`, M6) is void as of 2026-08-05, so nothing is blocked on it today |
| `HookHealer` | self-heal the exec-bit class | **declined** — see above; Harbor invokes guards via `/bin/sh` |
| `DocIntegrity` | check cross-refs when system docs change | **covered** — lint K1/T3/T4/T7, and enforced in CI rather than at runtime |
| `LoadContext` | inject dynamic context (SessionStart) | **covered** — `context-resolve.sh` (H2), narrowed to the boundary notice |
| `LoadMemory` | inject hot-layer memory (UserPromptSubmit) | **ticketed** — workstream D |
| `MemoryTurnStart` / `MemoryDeltaSurface` / `MemoryHealthGate` / `MemoryReviewFire` | the memory cadence | **ticketed** — workstream D. Note `policy/constitution.md` dropped upstream's memory-delta *fields* because no hook emits them; these are the hooks that would |
| `StopGates` | the ONE Stop-event gate | **BUILT 2026-08-23** — `bin/guard-stop.sh` + `tests/admission/stop/stop.test.sh` (harbor#291), opt-in via `floor-install.sh --with-stop-gate`. Two rules, both read from the transcript: a floor surface edited with no `floor-test.sh` run **after** it, and a suite this session ran that was left red. Fails OPEN, which is the inverse of every other guard and argued at the head of the file rather than assumed |
| `FormatGate` / `WritingGate` / `CommunicationSkillGuard` | output-format teeth, writing audit, outbound-email catch | **declined** — №1 is a response *shape* principle in Harbor, not a template, so there is nothing deterministic to gate |
| `AlgorithmNudge` / `ISASync` / `ISARenderOnStop` / `CheckpointPerISC` | the Algorithm/ISA runtime | **declined** — `docs/reference/provenance.md` F1: the ISA *skill* is vendored, the *runtime* is not |
| `TaskGovernance` | subagent task-creation governance | **OPEN** |
| `AgentInvocation` | fills in missing SubagentStart/Stop payload data | **OPEN** — platform-shaped; re-check against current Claude Code before deciding |
| `PostToolObserver` | sync catchall consolidation | **OPEN**, depends on L1 |
| `LoopDetector` | detect repetition loops | **OPEN** |
| `DriftReminder` | drift reminders | **covered** — lint X1/X2 cover config drift; the *behavioural* half is not, and that is a narrower OPEN than the row suggests |
| `SessionCleanup` / `UpdateCounts` | SessionEnd state + counts | **different-machinery** — `status-generate.sh` generates counts on demand rather than on exit |
| `PromptProcessing` / `TabState` / `KittyEnvPersist` | Kitty tab titles, tab state, env persistence | **declined** — terminal-emulator specific |
| `VoiceCompletion` | voice notification | **declined** — de-platformed on intake (`docs/reference/provenance.md` A3) |
| `ReminderRouter` | reminder/research/queue routing | **declined** — routes into the upstream platform |
| `LastResponseCache` | cache the last response | **OPEN** |
| `ContextReduction` | reduce context | **OPEN** |

## Beyond hooks — the rest of the install surface

Added after the hook table, because "what about PULSE, ALGORITHM, agents,
commands, settings?" was a fair question the first pass did not answer.

### `UPSTREAM/PULSE/` — the monitoring app

Conduit · MenuBar · VoiceServer · Observability · Performance · Schema ·
adapters · checks, plus `com.upstream.pulse.plist` / `com.upstream.deriver.plist`
(launchd) and a `PULSE.toml`. It is the localhost:31337 service every other
skill posts to.

**Disposition: the SERVICE declined, the MONITORING taken — E1 shipped
2026-08-02.** What landed is a launchd-scheduled probe in POSIX sh: no resident
daemon, no `localhost:31337`, no menubar app (the statusline glyph is already
that surface), no voice. Harbor was already running a launchd job
(`com.harbor.status.fleet-snapshot`), so the scheduling pattern was proven here before
E started; `com.harbor.alert.probe` is the second.

This file's own sentence is what settled it. The de-platforming applied to
skills removed the *callers* (`curl localhost:31337/notify`), not the service,
and this section already said that if E shipped, those notify blocks would come
back **as a Harbor-side sink, not as upstream's**. `docs/reports/platform-build-tickets.md`
still said "install Pulse from the fork, no adaptation" — written before the
no-fork decision and never revisited. The operator chose the Harbor-side
reading on 2026-08-02 and the ticket was rewritten to match, so the two
documents no longer describe different systems.

The WSL half is unchanged and still deferred (`SPIKE-PULSE-WSL`): that box
cannot host always-on local monitoring at all, which is a different problem from
this one.

### `UPSTREAM/ALGORITHM/` — the seven-phase runtime

`v8.4.0.md` + `LATEST` + `modes/` + `mode-detection` · `optimize-loop` ·
`ideate-loop` · `parameter-schema` · `target-types` · `eval-guide`.

**Disposition: declined (runtime), taken (model).** `docs/reference/provenance.md` F1: the ISA
*skill* is vendored and installed; the runtime that drives runs from it is not.
The four hooks that serve it (`AlgorithmNudge`, `ISASync`, `ISARenderOnStop`,
`CheckpointPerISC`) are declined for the same reason.

Worth naming: `optimize-loop.md` is where the **MAD confidence gating** came
from that is now `bin/eval-pass-score.sh`. The runtime was declined; one of its ideas
was not.

### `agents/` — a cross-vendor research roster

Six agents, each paired with a `*Context` file: `ClaudeResearcher`,
`GeminiResearcher`, `GrokResearcher`, `PerplexityResearcher`, `CodexResearcher`,
and `Forge` (GPT via `codex exec`).

**Disposition: declined — different machinery, and paid keys.** They exist to
give the `Research` skill a multi-vendor panel; Claude Code has first-class
subagents and the `Workflow` tool, which is the same fan-out without four API
keys billed outside the subscription. This is the one place where the
"different machinery" verdict genuinely holds, unlike the four it was wrongly
applied to (see `docs/reports/rejected-approaches.md` DE-10).

**What does NOT come free with our subagents** is upstream's
`UrlVerificationProtocol` — already taken, see [docs/reference/citations.md](./citations.md).

### `commands/` — thin, and mostly aliases

`context-search`, `cs` (its short alias), `pu`.

**Disposition: `context-search` covered** — the skill is vendored and installed.
`pu` (extract system improvements from content, monitor external sources, scan
bookmarks) is **OPEN**: it is the closest thing upstream has to a *"watch the
outside world and propose upgrades"* loop, and Harbor has nothing in that shape.

### `settings.system.json` — the wiring, and a harvest source

No `hooks` key — hooks are registered separately in `hooks/hooks.json`. What it
carries is the harness surface (`autoMode`, `loadAtStartup`, `dynamicContext`,
`postCompactRestore`, `skillListingBudgetFraction`, …) plus a large
`permissions` block: **allow, deny and ask lists far larger than Harbor's**.

**Disposition: wiring declined, deny-list OPEN as a harvest source.** Harbor
does not adopt upstream's settings file — that is the installer the no-fork
decision excluded, and several keys it sets do not exist in Claude Code. But
`permissions.deny` is the layer `docs/explanation/admission-baseline.md` calls *"the only one the model cannot
argue with"*, Harbor's live copy is much thinner, and B1's twelve Bash globs
were written from scratch rather than from this list. **Diffing the two is
cheap and has never been done.**

`settings.enhancements.json` is spinner text. Declined.

### `UPSTREAM/TOOLS/` — the Bun/TypeScript tool library

152 files. `KnowledgeGraph` / `MemoryRetriever` / `SessionHarvester` (workstream
**D**, ticketed), `TelosFreshness` / `InterviewScan` (**method taken** — see
`bin/doc-freshness.sh`), plus a long tail: banners, `AgentWatchdog`, `BudgetCheck`,
`BookmarkSweep`, `ArchDecisionHarvest`, `CarrierProbe`.

**SURVEYED 2026-07-26.** This row previously read *"named, not enumerated,
because a 152-row table nobody reads would be the same defect in a new shape."*
That was half right and half an excuse: the fix for an unreadable dump is a
**judged** list, not no list. Six of these land directly on problems Harbor has
already written down as open.

#### Take — each closes a named Harbor gap

| Tool | What it is | The Harbor gap it closes |
|---|---|---|
| **`DoctrineReplay`** | *"the regression corpus the Algorithm never had: 80+ doctrine versions shipped with no way to check a rewrite against real past work"* — stratified sample of archived work, replayed against a rule change | **The install decision.** Twelve passes rewrote the floor's rules against 573 *synthetic* assertions and zero real traffic. That is why every pass "fixed" things and the next found ~24 regressions. With L1 recording real commands, a replay corpus turns "did this rule change help?" from an argument into a measurement. **This is the missing half of the criterion.** |
| **`DeriveDenyHashes`** | *"turn the principal's PRIVATE corpus into a SALTED-HASH leak filter, so the guard can block private data appearing in shipping code WITHOUT the filter ever containing that data in the clear"* | `guard-egress.sh` knows generic secret *shapes* — `sk-`, `ghp_`, PEM headers. It cannot know **your** secrets, so it cannot catch your API key with an unusual prefix or your client's name. This solves that without the guard becoming the leak. Also the exact primitive L1 needs for its truncated hashes. |
| **`BudgetCheck`** | *"backpressure against always-on context re-accretion. Without a ceiling those files regrow: proposals auto-append, ISAs accrete, rules stack"* | **A risk Harbor is actively walking into.** L2 adds `CLAUDE.md` + `TELOS` + `IDENTITY` to every session and nothing bounds them. Upstream hit this and built a ceiling; we have not noticed it yet. |
| **`SessionHarvester`** | extracts learnings from `~/.claude/projects/` transcripts into `LEARNING/` | **VOID by owner decision 2026-08-05** (M4). Its value is transcript CONTENT, refused twice — DE-16 for the durable corpus and the standing "never persist a distilled copy" rule for the digest. The safe residue is the transcript INDEX, and `hooks/memory-harvest/memory-harvest.sh` (D1) already reads it. Aggravating fact: `LEARNING/*.md` is inside `worklog-push.sh`'s allowlist, so its output would have been published. |
| **`LearningPatternSynthesis`** | *"aggregate ratings into actionable patterns… recurring patterns… synthesis reports for continuous improvement"* | **VOID by owner decision 2026-08-05** (M6). Every input is accounted for: `SatisfactionCapture` has no ticket and no rating surface exists, `SessionHarvester` is void, and the one real signal — ledger recurrence — is already ranked by M5's FC-5, which also excludes the verifier's own probe traffic. A synthesis step over a signal nobody captures. |
| **`FailureCapture`** | full-context failure analysis | The substrate the self-heal question was really about. Upstream's `HookHealer` heals one class; **this** is the part that notices a failure worth healing. **BUILT 2026-08-04** — `bin/audit-triage.sh` (M5), and deliberately NARROWER than upstream's name: it judges the guard-decision ledger, it does not capture full context. A durable store of command text is refused by owner decision (`docs/reports/rejected-approaches.md` DE-16) and the ledger is redacted by construction, so "full context" is unavailable on purpose. It reports and never repairs. |

#### Take if cheap — real value, no urgency

| Tool | Why |
|---|---|
| `Doctor` | capability prober: which external tools does doctrine assume exist? **B9 exists because a missing `jq` made every guard exit 0 on `rm -rf /`.** A prober would have caught that whole class before it shipped. Harbor also assumes `grep`, `gitleaks`, `gh`. |
| `ReferenceCheck` | full-surface reference validator over `~/.claude`. Lint K1/T3 do this for the **repo**; nothing validates the **installed** surface, which is the one that runs. |
| `CheckFileBoundary` | runs the guard's own `evaluateWrite()` in CI / pre-commit rather than only at runtime. **Half of this was already closed** — the floor suite (`tests/floor/`) fires every guard in CI. **SCOPED 2026-08-05** (M11) to the residue: a `--smoke` mode on that same suite, wired into pre-commit, where a guard regression currently reaches a push behind style checks only. One implementation, so the predicates cannot drift. |
| `UsageAggregator` + `CostTracker` | durable per-day usage. `CostTracker`'s stated origin is an invoice *"dominated by upstream-local processes that billed API instead of subscription"* — a failure mode Harbor's future skill-tools share. |
| `MutationTier` | four-tier classifier for paths under `~/.claude`. `guard-selfedit.sh` is binary (protected / not); tiers are what let a rule be strict about `settings.json` and relaxed about a cache. **SCOPED 2026-08-05** (M10): the table ships as a fixture with a suite assertion that the REAL guard agrees with it on tier ≤ 1, so it is load-bearing without moving a hash-pinned control surface. Consuming the tiers inside the guard stays a separate operator decision. |
| `ProposalGC` | GC for auto-appended memory proposals. **VOID as a take 2026-08-05** — the memory engine (D1/D2/D3/D7) shipped with no proposal concept, so the GC never had a subject. The surviving concern, the store growing until it costs context, is registered as **CX1** under its own letter, and deliberately as a REPORT rather than a GC: automatic deletion of the operator's memory is a data-loss path with no undo. |

#### Skip

Banners (five variants) · `UpstreamLogo` · `AddBg`/`RemoveBg` · `Transcribe*` ·
`YouTubeApi` · `SplitAndTranscribe` · `Recommend` (restaurants/movies/books) ·
`Grok`/`OpenRouter`/`PerplexitySearch` (paid keys, and see `agents/`) · `gmail` ·
`PangramScore` · `DAGrowth`/`DAInterview`/`DASchedule` (persona) ·
`Conveyor`/`PipelineOrchestrator` (platform) · the `Install*.ts` launchd
installers (**pattern only** — Harbor already runs launchd) · `Migrate*` (upstream
taxonomy) · `Wisdom*` (life content) · `UpstreamConfig`/`UpstreamUpgrade`/
`UpdateUpstreamState` (platform).

**`SecretScan` — skip, with the reason recorded:** it wraps TruffleHog, and
Harbor already has a **fail-CLOSED gitleaks gate** on the work-log push. Two
scanners is not twice the safety; it is two things to keep current. Revisit only
if gitleaks proves insufficient.

### `UPSTREAM/RULES/` — three files, all dropped *by name*

`Philosophy.md`, `SelfHealing.md`, `VerificationExpanded.md`. `docs/reference/provenance.md`
records dropping every pointer to `UPSTREAM/RULES/*` by name rather than
repointing — see `docs/reports/rejected-approaches.md` DE-05 for why. Their *content* was handled
separately, and unevenly:

| File | Status |
|---|---|
| `SelfHealing.md` | **taken, and improved.** `policy/constitution.md` § *"Fix the system, not your notes"* is this file's routing table pointed at real Harbor destinations, plus two rules upstream does not have (*derive, don't state*; *a rule with no mechanism is a wish*). Note the section was **retitled**, so a reader grepping for "self-healing" finds nothing — upstream's own phrase won. |
| `VerificationExpanded.md` | **partly taken.** №2 has modality fidelity, defer-never-substitute, appearance≠existence and reproduce-before-fixing — all four incidents. What it does **not** have is upstream's enforcement: `VerificationGate.hook.ts` grades evidence *from the transcript*, not from the message's wording, so rewording never passes it. That remains the OPEN row above. |
| `Philosophy.md` | **declined.** Current-state→ideal-state via TELOS and the Algorithm — the framing Harbor kept as *Ideal-state prompting* without the Algorithm runtime underneath it. |

### `USER/` — the personal spine

`TELOS/`, `PRINCIPAL/`, `DIGITAL_ASSISTANT/`, `Daemon/`, `SECURITY/`,
`CONFIG/`, `CUSTOMIZATIONS/`, `SHARED/`, `WORK/`, plus `ABOUTME` `OPINIONS`
`PROJECTS` `CONTACTS` `GEAR` `OUR_STORY` `FEED` `DEFINITIONS`
`TECHSTACKPREFERENCES` `AI_WRITING_PATTERNS` `ALGOPREFS` `ARCHITECTURE`.

**Disposition: TELOS ticketed (L2 / harbor#43), the rest declined.** This is the
life half. Harbor takes the working slice — goals and standing constraints — and
`DA_IDENTITY`/`PRINCIPAL_IDENTITY` stay on the never-taken list (`docs/reference/provenance.md`
A3, de-persona).

`USER/CONFIG/OPERATIONAL_RULES.md` is the one row worth a second look: it is
where upstream's self-healing table sends *principal-specific* operational
preferences, and Harbor's equivalent destination is currently "the repo's
`CLAUDE.md`" — which does not exist for the ambient case. Folded into L2.

## Honest totals

Not stated as counts here — `docs/generated/status.md` owns numbers (lint T2). What the table
says qualitatively: the **guard** surface is genuinely covered, the **memory**
surface is ticketed as workstream D, and the **observe → verify → learn** surface
is almost entirely OPEN, with one ticket (L1) at the front of it.

That is the same conclusion the coverage sweep reached. The difference is that
this time it is in a file, with a lint rule holding it complete.

## The diff that had never been run

`settings.system.json`'s `permissions.deny` carries **42** curated entries.
Harbor's B1 list was written from scratch, and the two had never been compared —
a curated deny list sat in the tree this whole build harvests from, unread.

Eight classes were missing outright. One badly:

| Missing class | Why it matters |
|---|---|
| `curl \| bash` · `curl \| sh` · `curl \| zsh` (and `wget`) | The most common real-world compromise shape there is. **[docs/explanation/approach.md](../explanation/approach.md):33 has said *"never `curl \| bash`"* since day one, with nothing enforcing it.** `policy/constitution.md`'s *"a rule with no mechanism is a wish"* — found in Harbor's own approach document. |
| `* > /dev/disk*` · `* > /dev/sd*` | Raw disk write by **redirect**. The `dd` form was covered; the redirect form was not. |
| `rm -rf ~/.claude` · `~/.claude/*` | **Deleting the floor's own home.** Nothing denied it. |
| `rm -rf .git` | Repo history. |
| `chmod -R 777 ~` · `$HOME` | Only `/` and `/*` were covered. |
| `git push --force*master*` | Only the `main` spelling was covered. |

All added to `bin/floor-deny.sh`, applied to the sandbox. Glob matches, not a
parser — `curl $U | bash` still walks past, and that is the layer's stated
nature, not a defect in it.

**This is the argument for the narrowed install**, concretely: these cost
nothing, are evaluated by the harness before any hook runs, cannot be swallowed
by a broken guard, and are wholly independent of the scanner decision that
twelve adversarial passes have not settled.
