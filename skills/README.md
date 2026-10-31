# skills — Harbor-authored skills (tracked home)

**Status:** created 2026-07-30 · owner: operator · first inhabitant: `<tag-manager-skill>`

The tracked source for skills **Harbor itself authors**. Distinct from
`vendor/skills/`, which holds *vendored* upstream skills and
carries a `vendor/skills/PROVENANCE.md` pinning an upstream
SHA and a re-sync diff procedure.

**Why a separate directory rather than one more row in `vendor/`.** Provenance
semantics differ, and that is the whole point of `vendor/`: every entry there
answers *"what upstream did this come from, and how do I re-harvest it?"* A
Harbor-authored skill has no upstream — filing it under `vendor/` would make that
file lie about its own contents, and lint rule **K1** exists precisely because a
citation that misdescribes reality is worse than an absent one.

## Rules

1. **Directory + `name:` are kebab-case** — [`standards/naming.md`](../standards/naming.md),
   binding for anything created after 2026-07-25.
2. **Frontmatter uses harness-defined keys only** — `name`, `description`,
   `user-invocable`, `argument-hint`, `allowed-tools`, `disable-model-invocation`.
   No bespoke keys: the upstream `version`/`effort` pair folds into `description`,
   which is what the model actually matches on (standards/naming.md §6.4).
   **Three optional ownership keys are allowed** (read by `context-rules/user/skill-on-first-use`, which
   names the skill the first time a session uses what it owns): `owns-commands` (space-separated CLI
   names), `owns-tools` (harness tool names such as `Agent`), and `inline-section` (the `## ` heading
   whose body the note carries, read live from this file). A skill that names a client system in them
   belongs in the private layer, never in core.
3. **A skill states *how*, never *which*.** Per-project facts (IDs, current
   state, findings) belong in that project's own `.agents/memory/` — the L3 scope
   in [`contracts/memory-format.md`](../contracts/memory-format.md). A skill that
   hardcodes a container ID or a version number is restating territory, and it
   rots silently the moment the source moves.

## This is the only home — the `plugins/` sibling was retired 2026-09-06

**Every skill lands here.** `UNIFICATION.md` §2 argued for a second tier and
`plugins/atlas/` was built on it 2026-09-02; the tier was retired four days later
because its founding premise measured false. A plugin installed at user scope is
active in **every** session — `atlas` cost ~398 tokens always-on — while a skill
here carrying `disable-model-invocation: true` costs **zero**. The tier charged a
governance price (seven of eight gates greped `plugins/` zero times) for a saving
that was never there. Full measurements: [`docs/explanation/no-authored-plugins.md`](../docs/explanation/no-authored-plugins.md),
enforced by lint **X10**.

**Cost is controlled by the frontmatter flag, not by the directory.** A skill a
session should not carry everywhere gets `disable-model-invocation: true` and is
reached by name or through `skill-catalog`. A skill needing plugin powers — an MCP
server, hooks, an agent — gets a `.claude-plugin/plugin.json` *inside its own
directory here* and loads as `<name>@skills-dir`, still under every gate.

`atlas` reads a project's diagram specs and writes into that project's
deliverable folder, so a session that is not building an atlas should not be
paying for it — that argument was right, and the flag is what delivers it.
`topology` and
`<tag-manager-skill>` are the other way round: they decide whether work starts at all, so they
have to be present before anyone knows they were needed.

**Delivery differs, and so does the failure mode.** Installing from here is a
copy into `~/.claude/skills/` and drift is caught by lint X8. A plugin is
installed by the harness from the marketplace, so there is no second copy to
drift — but nothing detects an *uninstalled* one either, and a plugin that was
never installed looks exactly like a plugin that does not exist.

## Install rule

Mirrors `vendor/skills/`'s Phase-0 home rule — **this dir is the tracked source;
install = copy to `~/.claude/skills/<name>/`**.

```sh
# First install only — the destination must NOT already exist:
cp -R skills/<name> ~/.claude/skills/<name>

# Updating an existing install — note the trailing `/.`:
cp -R skills/<name>/. ~/.claude/skills/<name>/
```

**The trailing `/.` is load-bearing and its absence is silent.** `cp -R src dest`
copies *into* `dest` when `dest` already exists, producing
`~/.claude/skills/<name>/<name>/` — a stale nested duplicate — while the files
you meant to update are left untouched. Nothing errors. Measured 2026-08-04: the
installed `<tag-manager-skill>` kept serving its old routing table after an "install" that
appeared to succeed, and only a recursive compare showed why. The one-form rule
that used to stand here is what produced that.

The copy is what the harness loads; this tree is what git remembers. **Drift
between them is detected by lint rule X8** (`bin/lint-conventions.sh`), which
compares recursively — `SKILL.md` alone is not enough, because the bulk of a
skill lives in `references/*.md` and the nested-copy failure above presents as an
extra path rather than a changed byte. X8 resolves the installed name the way X4
does, so a kebab source installed CamelCase is still compared rather than
skipped. `mail-cal` was that case until 2026-08-05 — tracked kebab, installed
CamelCase — and the fallback is what kept it under comparison instead of
silently exempting the one skill whose two names disagreed. It is installed
kebab now, so the fallback currently has no live subject; keep it, because the
next hand-install is where the same divergence reappears.

X8 is **advisory**: it names drift, it does not fail the build, because the
correct resolution is sometimes to re-install and sometimes to promote the live
copy back into the tree, and a linter cannot know which.

## Cost

Ambient skills are paid for **every session, forever** — the `description` is the
always-on surface, the body loads only on invocation. `bin/context-budget.sh`
measures it against a ceiling and lint rule **X3** surfaces it. Prefer an
invoked-only skill (`disable-model-invocation: true`) unless the model genuinely
must select it unprompted.

## Inhabitants

| Skill | Tier | Why it exists |
|---|---|---|
| `<tag-manager-skill>` (a pack, harbor#1149) | ambient | Google Tag Manager work must go through the Tag Manager API from the terminal. Without it, a session reaches for the browser UI and burns turns discovering that the auth path is ADC-under-`gcx`, not `gcloud auth login`. Also the **router** for the four below. |
| `<server-tagging-skill>` (a pack, harbor#1149) | ambient | Server-side tagging is live for six clients on three hosting substrates. Without it, a session conflates Tag Gateway with a server container, or claims a first-party cookie benefit that CNAME cloaking has already capped. |
| `measurement-debug` (a pack, harbor#1149) | ambient | "The numbers are wrong" is the most common inbound question and the easiest to answer badly. Carries the debug ladder and the expected reconciliation gaps, so a discrepancy gets explained rather than investigated. |
| `platform-signals` (a pack, harbor#1149) | ambient | Vendor event and parameter vocabularies diverge between browser and server, and a wrong field name fails silently. Also carries the dated platform changes that look exactly like a tracking failure. |
| `reporting-apis` (a pack, harbor#1149) | ambient | The four above answer "why is this number wrong" and "how do I get a conversion into Ads", and answered "what happened to performance last week" nowhere. Carries the grant each reporting API needs and the rule that reachability is proven before it is planned against — because no identity on this machine currently holds a reporting scope at all. |
| `mail-cal` (a pack, harbor#1149) | ambient | Gmail and Calendar for the work account. Reads are free; **calendar writes exist and are approval-gated** — `gcal-write` holds `calendar.events`, so the constraint is a rule rather than a missing scope, and the skill's §Write Policy is the only thing standing between a request and an event on the operator's calendar. Mail cannot be written at all. |
| `topology` (a pack, harbor#1149) | ambient | Work scoped to one system silently misses the middlemen. Maps the whole scope first — client maps to `CLIENTS/<NAME>/TOPOLOGY.md` in the measurement repo (resolved through the repo registry), company-internal to the data-estate repo (resolved through the repo registry) — and the cross-repo index is generated, never hand-edited. Routes to `access-ledger`. |
| `flow` (a pack, harbor#1149) | ambient | The data-estate repo (resolved through the repo registry) documents the estate that is being **retired**, and a session that reads it will confidently describe a retired connector, `dbt_prod` and `marts_*` — none of which is what runs. Carries the live platform's identity (`tools@`, not the README's analytics@), the region that returns 0 jobs and exit 0 when guessed wrong, and the measured fact that CORE is fully promoted while the transform repo README still calls it unproven. |
| [`access-ledger`](./access-ledger/) | ambient | An access request made in pieces is refused in pieces. Turns a drawn topology into ONE complete ask, ordered by what it unblocks, least privilege first, and records the outcome in the access register (`harbor-private/access/`). Credentials stay in the Keychain behind a wrapper, never in a transcript. |
| [`skill-catalog`](./skill-catalog/) | ambient | Most skills on this box carry `disable-model-invocation: true` and are absent from the model's listing entirely, so a session cannot be reminded they exist. Carries **paths**: a hidden skill cannot be invoked, but its `SKILL.md` can always be read. Generated by `bin/skill-catalog.sh`: the tracked copy lists only the skills this repo ships (lint **T9** reports staleness), and the copy a deploy installs lists every skill on the box, packs' included. |
| [`skill-book`](./skill-book/) | invoked-only | The old name of `skill-catalog` (harbor#1010), kept for one release so a document or a habit that says `skill-book` still lands on the index. A stub that points at the catalog; it goes with its `standards/naming/renames.tsv` row. |
| `casefile` (a pack, harbor#1149) | ambient | `topology`'s nine-section contract is structural — `bin/check-topology.sh` in the data-estate repo (resolved through the repo registry) asserts headings exist and exits 0 on a map missing the entire subject of its own case. This one gates a diagnosis on a **row-level** pack: every hop names an owner from a closed enum, a reachability, a probe and a date, and a case naming an ad platform must name, as a row, an object it spends against. It is **ambient by necessity, not by preference** — `EVALS/DS-1-why-answers-diverge.md` in the data-estate repo (resolved through the repo registry) measured six of six agents declining to invoke `topology` when it was visible and correctly described, so an invoked-only version of this reproduces the failure it exists to fix. Reimplements nothing; routes to the eight skills above. |
| `ad-inventory` (a pack, harbor#1149) | ambient | The one domain the library did not cover. Measured 2026-08-29 across all 40 installed skills, `product feed`, `dpa`, `remarketing list`, `shopping feed` and `merchant center` had **no owner at all**. `platform-signals` owns conversions *in*, `reporting-apis` owns numbers *out*, and nothing owned **what the ad is made of** — which is where the money is, and where both the PANDORA and the ad-platform cases lived. Walks campaign → ad set → product set → catalogue → feed → source URL → producer, and requires the DIRECTION each filter resolves to today: an exclusion set matching nothing excludes nothing, and that defect reports healthy at every level while spending. Invoked-only; `casefile` and `topology` route to it. |
| [`doc-deliverable-contract`](./doc-deliverable-contract/) | ambient | Moved out of `topology` on 2026-08-29, verbatim. A client-communication standard living inside a mapping skill is advertised by that skill's description, which promises a map — and `EVALS/DS-1-why-answers-diverge.md` measured six of six agents declining to open that file and then failing this exact axis. Carries the verb rule (a review does not license a change), the audience-and-language rule, the five moves that took one real reply from 2/7 to 7/7 with **no new measurement**, and the two registers with the finding that a tier an agent may grant itself is an escape hatch it will take in good faith. Model-invocable on purpose: the measured failure is that the rule does not bind unless it is in the turn. |
| [`test-strength`](./test-strength/) | invoked-only | CONSTITUTION §№2 rule 10 had no mechanism: measured 2026-08-27, **2 of 44 `bin/*-test.sh` suites plant a violation**, and nothing tells a checked suite from an unchecked one. Carries the three checks — red on a planted violation, **green on a valid-but-unusual input**, and an *eligible* planted violation for any gate reporting zero — because red on a mutant proves discrimination, not correctness. Re-authored from `project-init`'s `verify-test-strength` rather than copied: `contracts/host-profile.md` forbids an L0 dependency on a Yard plugin, and the upstream's Python-runner-first shape inverts for a POSIX-`sh` estate. Invoked-only because the always-on surface is over its ceiling. |
| `tracking-standards` (a pack, harbor#1149) | ambient | The library said how to DEBUG a measurement estate and, in eleven skills, nowhere how to BUILD one. Measured 2026-09-05: `find` across `~/.claude/skills`, two workload repos and `~/harbor` for any naming, convention or standard document returned harbor's own layer-naming rule and a TypeScript style guide — nothing about tags, events, containers, conversions or campaigns. The cost is visible in the containers: **14 tag names differ across one client's three cloned market containers**, including `Facebook - Purchase` against `Facebook - purchase`, and another client runs a `Google Optimize` tag and four `UA - Purchase - *` triggers against products sunset in 2023. Half the standard was enforced by `bin/check-naming.sh` (a self-test that prints its own count, four rules, each one a defect already shipped here); that half now lives in the measurement repo's `packages/standard` as `just <tool>-lint`, the script is retired with every caller repointed to that lint (the measurement repo's catalog lane, 2026-10), and the skill says plainly which half has no mechanism. **Ambient on purpose**: it is the only model-invocable entry point for a *build* task — `topology`, `<tag-manager-skill>`, `<server-tagging-skill>` and `ad-inventory` are all invoked-only, and `casefile` fires on a live problem, so before this a request to add a pixel reached no skill at all. |
| `measurement-audit` (a pack, harbor#1149) | invoked-only | The audit practice existed only as a per-audit brief in a dated data folder of the measurement repo (resolved through the repo registry), so the next audit re-derives it or copies it and drifts. Carries the genre rule (correctness is not prioritisation), the read-only constitution, the five-field finding contract, the checked-and-clear list that separates coverage from silence, and the required **defects in our own instruments** section. Two findings gave it teeth: one client audit's lanes were hand-picked and, read against the nine layers, `origin`, `storage` and `serving` had **no lane at all**; and its own instrument defect (`shard-age.sh` turning a credential failure into a data verdict) was recorded accurately and stayed broken two days, because a note has no destination. **Invoked-only by arithmetic** — `bin/context-budget.sh` showed 176 bytes of headroom on 2026-09-05, so `tracking-standards` is the ambient entry point and routes here. |
| [`access-browser`](./access-browser/) | invoked-only | The estate's routing table for "which browser tool" lived inside a workload skill and nowhere else, so a session that had not loaded a measurement skill picked a backend by habit — and harbor#445 refused a browser capability on the stated ground that `<tag-manager-skill>` enforces APIs-over-browsers, which is the **opposite** of what its own table said. Nothing caught it, because the table was not somewhere a reader would look. The table now lives in `contracts/browser-routing.md`, `harbor browser route` prints it, and `tests/access/browser/browser.test.sh` asserts the print is **byte-identical** so a second copy cannot reappear. Two axes rather than one: login, and attended-vs-unattended — the second is what produces row 5, a logged-in surface driven repeatedly, whose backend the box **already runs** (`@playwright/mcp@latest` against a profile holding `Cookies` and `Login Data`) and which is therefore **declared and refused** pending an access-ledger entry and a pin. The load-bearing finding is its own: measured 2026-09-06 on a client storefront, an anonymous run reported `meta` **ABSENT** while accepting the consent banner turned up **39 more hosts** including Meta's tag host — a confident false negative from the tool built to make negatives trustworthy — so `hosts` now **withholds** an absence verdict when a CMP loaded and nothing accepted it. Invoked-only by arithmetic: `bin/context-budget.sh` showed 56 bytes of headroom the day this shipped, and `bin/context-budget.sh:125` charges an invoked-only skill nothing. |
| [`housekeeping`](./housekeeping/) | invoked-only | Nothing on this box decided what was safe to delete, and the 2026-09-06 sweep showed why that is not a tidiness problem. The two largest apparent wins were both **live**: `~/.claude/security/agent-sdk-venv` is 282 MB untouched for 50 days *and* is recreated by the `security-guidance` plugin's `ensure_agent_sdk.py`, and `.helm-replay` is 820 KB untouched for 31 days *and* is read by `eval-replay.sh`. A size-ranked sweep reaches for exactly those first. Three more findings the same day set the rules: a workload repo held **69 uncommitted lines** of `docs/reports/rejected-approaches.md` that nothing regenerates; the `Mac` memory shard read as 51 poorer duplicates but a line-level union showed **27 of 51 carried lines that existed nowhere else**; and running `projects-orchestrator`'s pytest suite set **`core.bare=true` on the operator's real checkout**, whose `git status` read clean throughout. So the skill leads with the refusal list, `bin/housekeeping-clean.sh` is `--dry-run` until told otherwise and prints KEEP rows with their predicate under `--json` too, and `harbor-clean-test.sh` asserts each refusal by planting the thing and checking it survived `--apply` — mutation-tested, since a cleaner that reclaims everything passes any "did it free space" test. **The count is in `docs/reference/checks.md` as `housekeeping.clean`, the delete is not** (2026-09-22): `--record` runs at 09:00 and 16:00 inside the fleet refresher and puts `🧹N` and `SWEEP` on the statusline, and it refuses `--apply` — deciding what to delete stays human-gated, and the rows only a person can decide come to the operator as one batch. Invoked-only by arithmetic — the always-on surface had 248 bytes of headroom the day this shipped. |
| [`doc-learning-artifact`](./doc-learning-artifact/) | invoked-only | The operator approved one study-page style on 2026-10-03, after four rounds of iteration on the CCBD exam guide: tabs, a tap-a-box card **inline under its diagram** (the earlier phone bottom sheet was hard to see), a saved-answer quiz and study aids. Its engine was buried in a one-course build script that patched an older page's quiz in place, so the next guide would have been designed fresh or copied with the course inside it. `kit/` is that engine with the course removed, an example content folder, and `check.py`, a Playwright check in real Chrome on desktop and iPhone. Three planted engine defects each turned it red: card placement, the saved answers and the tabs. Invoked-only: the `learning-artifact-style` memory pointer already loads every session and names this path. |
| [`agent-routing`](./agent-routing/) | invoked-only | The harbor#818 tier rule lived in a memory note and in one deny message that still taught the pre-trial table. A 141-run trial (2026-10-08) moved scoped, gate-checked writes to Haiku at high effort. This carries the table, the escalation rule and the headless-brief rule. Hidden because the moment of use is an Agent call, and `97-agent-model-required`'s deny names this path there. |
| [`audit-review-fanout`](./audit-review-fanout/) | ambient | Review ran as one agent on whatever tier the plugin pinned (`code-reviewer` pins Opus). The trial showed the extra real bugs come from *different* lenses, not more copies, and that each added reviewer adds false positives. Ambient because a review is asked for in prose and no hook can see it coming; the verify step is the half that keeps it from violating №2.11. |
| [`atlas`](./atlas/) | invoked-only | The old name of `doc-atlas` (harbor#1010), kept until 2026-11-15 so a document or a habit that says `atlas` still lands on the skill. A stub: it points at the new name and carries no workflow. |
| [`browser`](./browser/) | invoked-only | The old name of `access-browser` (harbor#1010), kept until 2026-11-15. A stub: it points at the new name and carries no workflow. |
| [`deliverable-contract`](./deliverable-contract/) | ambient | The old name of `doc-deliverable-contract` (harbor#1010), kept until 2026-11-15. A stub: it points at the new name and carries no workflow. |
| [`learning-artifact`](./learning-artifact/) | invoked-only | The old name of `doc-learning-artifact` (harbor#1010), kept until 2026-11-15. A stub: it points at the new name and carries no workflow. |
| [`review-fanout`](./review-fanout/) | ambient | The old name of `audit-review-fanout` (harbor#1010), kept until 2026-11-15. A stub: it points at the new name and carries no workflow. |

## Retired

- One client weekly-report skill: retired 2026-10-27 (harbor#1010; operator decision 3 on #949). It never had a tracked source, so no repo change removes it: `deploy.sh --prune` judges only skills the repo once shipped, and the manifest drift check reports the installed copy with no row. The operator removes the installed copy on the box; its name is a client's, so it is recorded in the private layer, not here.
