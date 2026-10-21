# Skills unification — separating from upstream, on Harbor's own rules

**Branch:** `feat/skills-unification` — **gone as of 2026-08-28**; `git branch -a`
has no trace of it, while this file has sat on `main` since. Last substantive
touch was before `a7e3992` (2026-08-13), which only renamed the CI worktree
across the tree. A plan whose branch has been deleted reads exactly like a plan
in progress, which is the drift §№2.12 names.

> **Landed 2026-08-28 on `feat/harness-pass-2026-08`, from the Q1–Q7 frontier:**
> the **HOLD marker** is on all 13 held skills (§"Per-skill disposition" had
> called it one line each and it had never landed — `grep -ril` returned 0);
> `DOCTRINE/grilling.md` is new; `DOCTRINE/modularity.md` gained the deep-module
> vocabulary; `DOCTRINE/verification-expanded.md` gained the endogenous/exogenous
> split and the discrimination clause; `bin/ab-tally.sh` is the first exogenous
> instrument (harbor#293 · option A, comparative signal);
> `skills/test-strength/` re-authors project-init's `verify-test-strength` under
> the box-profile seam. **Still not done from this plan:** the 6 CONVERT and 6
> REWRITE re-authorings, and the 31 dead `execution.jsonl` citations.

> **RETRACTED 2026-09-06 — the tier is retired; see
> [`DOCTRINE/no-authored-plugins.md`](../DOCTRINE/no-authored-plugins.md) and lint
> X10.** The note below is kept as written because its own last sentence called
> the outcome: *"no rule yet watches `plugins/`, and that is the next gap."* It
> was seven gaps, not one, and the premise underneath was false — a user-scope
> plugin loads in every session (`atlas`: ~398 tok always-on), while
> `disable-model-invocation: true` on a skill costs zero. `atlas` moved back to
> `skills/atlas/`. The §2 argument survives; the tier was the wrong mechanism for it.
>
> **Landed 2026-09-02 — §2's plugin tier is now a tree, not an argument.**
> `plugins/atlas/` is the first Harbor-authored plugin and
> `.claude-plugin/marketplace.json` makes this repo the marketplace, so the L3
> model §2 said to adopt at L0 is adopted. `atlas` was authored into `skills/`
> first and **moved**, which is the point of the tier: it reads a project's
> diagram specs and writes into that project's deliverable folder, so a session
> not building an atlas should not carry it. `just lint` is green across the new
> tree — 66 rules, 0 violations — which also says no rule yet *watches*
> `plugins/`, and that is the next gap rather than a clean bill.

Testing comes later; this file is the plan and the record of what it rests on.

**Tickets:** extends #7 (I · Skills — I1 vendor, I2 dedup, I3 collision scan).
Related: #129 (architecture-blueprint skill vs its contract), #44 (UPSTREAM/TOOLS
observe/learn half). #162 closed 2026-08-07 — all installed skills are governed.

## The goal, in the operator's words

Stop vendoring from upstream and instead **take the ideas and re-author them under
Harbor's rules**. Land on **10–20 skills**, some of which are instruction-shaped
skills that manage the rest — so a session carries less context and the operator
has more direct control over what loads and when.

## What the research changed about this plan

Five findings that move the target. Each is measured; the measurement is named.

**1 · The context problem is not where anyone thought, including me.**
`bin/context-budget.sh` — the authority lint X3 enforces — skips any skill
carrying `disable-model-invocation: true`, because an invoked-only skill is
absent from the model's listing entirely and costs nothing per session.

**One denominator, and it is the session.** An earlier cut of this table put
73.5% next to 7.1% in the same column with different bases — the first was a
share of ambient *skill* bytes, the second a share of *session spend* — which
made the vendored set look an order of magnitude smaller than Harbor's own when
the real ratio is under 3×. Every row below is a share of what a session
actually pays.

| Always-on source | Bytes | Share of session |
|---|---|---|
| `~/.claude/CLAUDE.md` | 16,145 B | **49.7%** |
| **auto-memory index** (cwd-keyed) | **10,471 B** | **32.2%** |
| Harbor's own ambient skills | 4,325 B | 13.3% |
| Vendored upstream (3 of 25 ambient) | 1,565 B | 4.8% |
| Invoked-only (24 skills) | **0 B** | — |
| **spent every session** | **32,506 B** | **135% of ceiling** |

Two instruments were wrong, in the same direction, at once.
the data-estate repo's `bin/check-skills.sh` reported 17,459 B by summing every tier — wrong by
3×, fixed in estate #16. And `bin/context-budget.sh`, the authority lint X3
enforces, had **zero** references to the cwd-keyed auto-memory index and so
reported 22,035 B: 91% of ceiling, with headroom, while the true figure was
135% and over. Fixed on this branch; the index is the second-largest always-on
item on the box and was the one nothing measured.

**So the conclusion inverts twice and lands somewhere neither original argument
pointed.** Retiring vendored skills is a clarity argument, not a context
argument — 4.8% of spend. Harbor's own nine are 13.3%. **The two files nobody
was treating as a context surface are 82% of it**, and one of them is not a
skill at all.

**2 · L3 already implements what we are trying to build.** `projects-orchestrator`
looked like it had 18 skills invisible to Claude Code. It does not. Its
`.claude/skills` holds only `plan` **by design**; the other eighteen arrive from
the `project-init-workflow` **plugin**, enabled per-repo in that repo's own
`.claude/settings.json`; and `.agents/skills` carries `--no-plugin` fallback
copies for harnesses that read that path (Codex, Antigravity). Three delivery
mechanisms, scoped, with a documented fallback.

**That is the model to adopt at L0** — not a new index. A plugin is loaded when
its repo is entered; `~/.claude/skills` is loaded always. The unit of control we
want already exists one layer down.

**3 · The router already exists, and it is `<tag-manager-skill>`.** A `| Load | When the question
is |` table; `skills/README.md` calls it "the router for the four below". It was
extended to `topology` in #172 so the practice has a situation-first entry point.

> **Both reasons given here for ruling out `skill-book` were false, and they are
> corrected rather than deleted because the conclusion survives on a third
> reason.** *"It is generated, so hand-written guidance is destroyed"* — the
> router table is data `bin/skill-book.sh` reads (`CONTRACTS/skill-book-router.tsv`
> since harbor#1149; it was a literal inside the script), and you edit that, which
> is exactly how the situation-first table in the book got there. *"It reads
> only the box skills dir and cannot see a repo-scoped skill"* — it reads `$PWD/.claude/skills` too and emits a separate repo-scoped section
> for them. What is actually true is narrower and still decisive: **`skill-book`'s
> own `USE WHEN` triggers are entirely meta** — *what skills do I have*, *list
> skills*, *I forgot the name of that skill* — so it surfaces when you ask
> **about** skills and never when you are doing the work a skill covers. A router
> that only opens when you already know to ask for a router is not a router.
> That is A5 in harbor#173, and it is one edit to the generator.

**4 · Three things must not be done, and the reason is a mechanism each.**

- **Do not move vendored skills out of `vendor/skills/`.** Lint V2 pins upstream
  SHA `a4e8e74` there and cross-checks it against two guards; `PROVENANCE.md`'s
  re-sync clause is the only written route back to upstream fixes. A move leaves
  PROVENANCE lying and lint T6 silently vacuous. **Re-authored skills are new
  skills in `skills/`; the vendored originals stay where they are** until they
  are deleted with their PROVENANCE row in the same commit.
- **Do not strip `version`/`effort`/`context`/`license` as a convention fix.**
  N2's allowed-list already names all four as known legacy and the lint is green.
  It moves no rule red→green and rewrites 25 files inside a B8-watched tree.
- **Do not give L2/L3 skills a tracked source in Harbor.** `CONTRACTS/box-profile.md`
  makes the box profile the *only* up-pointing edge, and names D7 — "a repo works
  with no upstream platform" — as what a second one breaks. project-init owns that layer.

**5 · The install was the riskiest step and had no installer — now it has one.**
`harbor skills` (`bin/skills-install.sh`, this branch). Before it,
`skills/README.md` documented a hand-typed `cp -R skills/<name>/. ~/.claude/skills/<name>/`
whose missing trailing `/.` silently nests a stale duplicate and leaves the old
copy serving. 25 of the re-authorings are also **directory renames**
(PascalCase → kebab), which invalidate every sibling cross-reference in the
descriptions. Renames and descriptions must still move in one commit.

The verb dry-runs by default, verifies byte-identity with `diff -r` after
writing, refuses to leave a nested `<name>/<name>/`, and takes `--from-old` so a
rename removes the PascalCase directory instead of leaving both in the listing.
Writing the live dir needs `--apply --live` — lint D2 caught the missing gate
and it was right to: installing changes what every future session loads, and the
B8 re-pin afterwards is the operator's act.

## Target shape

| Tier | Count | What it is |
|---|---|---|
| **Ambient** | 9–11 | Loaded every session. Harbor's practice: `topology`, `access-ledger`, `<tag-manager-skill>`, `<server-tagging-skill>`, `measurement-debug`, `platform-signals`, `reporting-apis`, `mail-cal`, `skill-book` |
| **Invoked-only** | 6–9 | Zero context. Re-authored reasoning skills, reached by name or by the router |
| **On hold** | 13 | Left installed and untouched, marked *do not use pending review* |

Lands at **15–20 skills**, inside the operator's target.

## Per-skill disposition

Groupings from the DS-6 research pass; the reasons are its, the decisions are
open until each is done.

**CONVERT — real capability, cheap fix (6).** `RootCauseAnalysis`,
`FirstPrinciples`, `RedTeam`, `Council`, `ArXiv`, `ExtractWisdom`.

**REWRITE — idea worth keeping, body is upstream-shaped (6).** `ContextSearch`,
`Telos`, `Delegation`, `SystemsThinking`, `ApertureOscillation`, `IterativeDepth`.

**HOLD — not for use until reviewed (13).** `Optimize`, `Evals`, `ISA`,
`Prompting`, `Fabric`, `WriteStory`, `PrivateInvestigator`, `WorldThreatModel`,
`Science`, `Sales`, `Aphorisms`, `BeCreative`, `Ideate`.

**Nothing here is deleted, and that is the operator's call rather than a
softening.** The research grouped these as RETIRE on the grounds that none fired
across five evals. The grounds are weak: all five were measurement-domain tasks,
so silence is evidence of a routing failure at least as much as of uselessness —
and `Evals` and `Optimize` describe precisely the work those five studies did by
hand instead.

So they stay installed, stay tracked, and stay in `PROVENANCE.md`. What changes
is one line in each body: **do not reach for this skill until it has been
reviewed.** They are already invoked-only, so they cost zero always-on context
and holding them costs nothing but the line.

Review each one against the same question before promoting or deleting: *what
would this have changed in a task we actually ran?* A skill that cannot answer
that is not retired for being unpopular — it is retired for having no worked
example, which is a falsifiable claim rather than an absence of one.

## The hook layer — the other half of "fewer skills, more control"

The operator's second proposal: inject the reminder at the moment it applies
instead of paying for it in every session's prefix. **The instinct holds and the
stated reason does not** — a hook that fires N times costs N injections landing
after the cached prefix, so on tokens it loses to `CLAUDE.md`, which is paid once
inside it. What it buys, measured here on 2026-08-07: the SessionStart pin-drift
banner was read straight past while a `guard-bash.sh` denial arriving mid-turn
redirected the work immediately. Constraints bind in the turn, not in the prefix
— and `CLAUDE.md` cannot stop a commit.

`CONTRACTS/hooks.md` carries the layer split. The finding worth repeating here:
**four of the five moments need a git hook, not a harness hook.** A git hook's
stderr *is* the Bash tool result, so it reaches context for free with no
`additionalContext` and no harness dependency. Only one moment is unreachable
that way — **a PR merge is server-side, so no local git process runs and no
`post-merge` hook can ever fire.** That single gap is what `bin/govern-hook.sh`
exists for.

| Landed on this branch | |
|---|---|
| `hooks/commit-msg` | the no-AI-attribution rule as a mechanism. Lint **C2** now reads its pattern instead of carrying a second copy |
| `hooks/pre-push` | the suites `bin/suite-select.sh` selects for the pushed range |
| `bin/govern-hook.sh` | the merge moment — the one no git hook can reach |
| `tests/hooks/govern-hook-test.sh` | the behavioural suite; it caught a defect no unit case could |
| `bin/inject-hook.sh` + `inject.d/` | **the vehicle, and it is now wired** — harbor#173 · A1 |

**Two claims in this section were stale and are corrected here.** The first said
the vehicle was an open question: it is not any more. `bin/inject-hook.sh` is one
engine reading declarative rule packs, wired **once at the box level** by
`harbor inject`, and it discovers each repo's packs from the session's cwd at fire
time — so harbor, every workload repo and every repo created after this get
the same channel with no settings file of their own. `CONTRACTS/inject.md` is the
format. `govern-hook.sh` kept only the merge moment; its `PreCompact` and
`SubagentStart` branches were universal rules living in harbor-only payload and
moved to `inject.d/box/`.

The second said PreToolUse `additionalContext` had **never been observed landing**
here. It had — probe P1 passed on 2026-08-07 and `CONTRACTS/hooks.md` records it,
inside the same commit this paragraph was written in. E6 has since measured what
the channel is worth rather than whether it exists: the same sentence scored
**0/4** as prose in a runbook the model had already opened and **4/4** injected at
the tool call.

## What has to exist before the surgery

Instruments first, because every one of these is currently capable of reporting
green on a broken result:

1. ~~A `harbor skills` verb~~ — **done, this branch.** Dry-run default,
   post-write `diff -r`, nesting refusal, `--from-old` for renames, `--live`
   gate on the live dir.
2. **`check-skills.sh` tier-aware** — done, estate #16.
3. ~~Lint X8 must recognise a generated skill~~ — **done, this branch.** It
   detects the `Generated by \`…\`` marker the generator writes into its own
   output and prints `regenerate` instead of a copy direction in either
   direction; both of the old branches were destructive for a generated skill.
4. ~~Lint V1's reverse walk~~ — **done, this branch.** The rule has promised
   "and vice versa" since it was written and only ever checked one direction, so
   a **deletion** was undetectable — which is precisely what this unification
   does 25 times over. A row now fails when its `vendor/skills/` directory is
   gone.
5. **A B8 re-pin is required after every batch**, and it is operator-only. Batch
   the changes so the operator re-pins once per group, not once per skill.

## The 31 dead telemetry citations

Every vendored skill ends with an instruction to append to
`~/.claude/MEMORY/SKILLS/execution.jsonl`. That directory does not exist; it went
with upstream on 2026-07-23. Verified as a footer rather than logic —
`grep -rn 'execution\.jsonl' | grep -v '>>'` returns empty, so nothing reads it.

**Deliberately not fixed on `main`.** These files are being re-authored or
deleted here; cleaning them there is work thrown away, and it would churn a
B8-watched tree twice. They go when their skill goes.

## Deferred, with reasons

- **`~/port/harbor` is the primary checkout on `main`** — run governance from here;
  `~/harbor-ci` is the detached CI worktree, kept current with `main` but not
  owning the branch. (Superseded the 2026-08 state where `~/harbor` sat on a
  feature branch and the second worktree — then `~/harbor-m5` — held `main`.)
- **`plan` is 16 byte-identical copies** across repos, `.agents/` mirrors,
  project-init templates and a `.venv`. Not a defect — it is the scaffolder
  working — but nothing records that they are identical, so a reader assumes
  local customisation that is not there. The per-repo text in the listing is
  synthesised by the harness, not in the file.

## The tier sweep — run twice, and the second run is the one to read

The same seventeen cases, the same roster of thirty-nine with
`disable-model-invocation` stripped from the copies, run before and after
`bin/skill-fire.sh` stopped feeding each session its own case file. The first
run cost ~$100 and its stdin leak put the whole fixture — `want` column
included — into every prompt. The second run is clean.

**The leak manufactured exactly half the fire rate.** Fourteen fires became
seven.

| case | contaminated | clean | |
|---|---|---|---|
| `red-team-big` | red-team | — | **lost** |
| `rca-big` | root-cause-analysis | — | **lost** |
| `council-decision` | council | — | **lost** |
| `recurring-problem` | systems-thinking | — | **lost** |
| `prior-work` | context-search | — | **lost** |
| `name-something` | be-creative | — | **lost** |
| `ideal-state` | flow, isa | flow | **isa lost** |
| `first-principles-big` | first-principles | first-principles | stands |
| `measurement-debug` | measurement-debug | measurement-debug | stands |
| `ticket-file` | tracker | tracker | stands |
| `eval-design` | evals | evals | stands |
| `prompt-write` | prompting | prompting | stands |
| `trim-setup` | bitter-pill-engineering | bitter-pill-engineering | stands |
| `long-doc` · `parallel-work` | — | — | still nothing |
| both `NONE` controls | — | — | still silent |

**A retraction.** After the first run this document said `evals`, `prompting`,
`isa` and `be-creative` all stood, on the grounds that none of the four is named
anywhere in the fixture. `evals` and `prompting` do stand. `isa` and
`be-creative` do not — both vanish on the clean run. The reasoning was wrong,
not just the conclusion: the leak's mechanism was never *the name appearing in
the prompt*, it was 3.7 KB of other people's tasks changing what the session
did. Checking for the name tested the wrong thing, and got the right answer
twice by luck.

**Zero false fires, on a clean run this time.** Both controls drew nothing with
all thirty-nine listed — the trivial question and the substantial
wrong-domain task alike. The fear that put most of these skills in the hidden
tier, that a large roster degrades selection, now has a clean measurement
against it rather than a contaminated one.

**The finding that decides the tier.** Seven distinct skills fired across
seventeen real tasks, and **six of the seven are hidden today** —
`first-principles`, `measurement-debug`, `evals`, `prompting`, `flow`,
`bitter-pill-engineering`. Only `tracker` is reachable as the box currently
stands. **The roster this operator can actually invoke fired once in seventeen
tasks drawn from their own work.**

**Listing is necessary and not sufficient.** `red-team` and
`root-cause-analysis` were listed, were given proportionate tasks written for
them, and drew nothing — the two `MISS` verdicts. `long-doc` and
`parallel-work` drew nothing for the second time, and that result is now clean
rather than confounded: `delegation` and `extract-wisdom` were visible, their
descriptions carry `fan out` and `distill`, and neither matched. Whatever
governs firing, it is not vocabulary presence and it is not tier alone.

**Still unanswered:** the nine held skills no case exercised. Two sweeps have
now shown that absence is the weakest evidence here and that a fire can be an
artefact, so neither run is grounds to delete anything.


## The 2026-08-29 sweep — rewritten descriptions, and five held-out cases

Twenty-seven cases, the same roster of thirty-nine, with five descriptions
rewritten to lead with the skill's differentiated outcome instead of its method
inventory. 129 minutes, 4.8 a case.

**On the seventeen cases all three sweeps share: five gains, one loss.**

| case | old descriptions | rewritten |
|---|---|---|
| `rca-big` | nothing | **root-cause-analysis** |
| `red-team-big` | read the file only | **invoked red-team** |
| `council-decision` | read the file only | **invoked council** |
| `recurring-problem` | nothing | **systems-thinking** |
| `prior-work` | nothing | **context-search** |
| `ideal-state` | flow | flow **+ isa** |
| `prompt-write` | prompting | **nothing** — a regression, and `prompting` was not touched |

Distinct skills invoked across those seventeen went from seven to thirteen.

**The held-out cases are the ones that mean anything.** Five prompts written for
a specific skill, phrased deliberately differently and verified to share ZERO
trigger phrases with that skill's `USE WHEN`. Re-running the original cases
alone could not separate routing from memorisation, because those prompts were
in front of whoever wrote the descriptions.

| held-out case | result |
|---|---|
| `rca-holdout` | **root-cause-analysis** — routed on meaning alone |
| `context-holdout` | **context-search** — routed on meaning alone |
| `creative-holdout` | **be-creative** — routed on meaning alone |
| `systems-holdout` | nothing |
| `delegation-holdout` | nothing |

**`systems-thinking` is the instructive failure.** It fired on
`recurring-problem`, whose prompt contains the phrase "recurring problem" that
sits in its own `USE WHEN`, and did NOT fire on `systems-holdout`, which
describes the same archetype without the words. That is keyword matching, not
routing, and only a held-out case can tell the two apart. `delegation` reached
nothing in either phrasing across three sweeps and remains the roster's hardest
non-router.

**Zero false fires, three controls silent** — including a new third shape,
substantial but purely mechanical, which a roster matching effort rather than
subject would have fired on.

**The measurement is noisier than one run suggests, and this is a caveat on all
of the above.** `prompt-write` invoked `prompting` in the two earlier sweeps and
nothing in this one, with that skill untouched. `name-something` drew nothing
while `creative-holdout` and `novel-options`, both naming-and-ideation tasks,
reached `be-creative`. A single run distinguishes a strong effect from noise
only where the effect is large; the five-gain shift is, one case flipping is
not.

**Two defects found incidentally.** `trim-setup` invoked `harbor-context`, which
is a slash command rather than a skill — the report counts an ATTEMPT, and this
one errored. It errored because `/harbor-context` embeds
`` !`sh ~/harbor/bin/context-budget.sh 2>&1` `` and that script exits 1 whenever
the budget is stressed, so the command fails in exactly the situation it exists
to diagnose. Neither is a roster finding; both are live and neither had a
falsifier before this sweep ran.
