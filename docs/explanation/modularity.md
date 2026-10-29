# Modularity — a planning-time decision with coding-time consequences

**On-demand.** Not resident: this changes what you *build*, and the moment it
can change anything is before the code exists. Loading it in every session would
cost context in exactly the sessions where it is least actionable.

**Load when:** designing a new component, choosing where a seam goes, or
wondering why `bin/guard-bash.sh` is several times the length of everything else
here. `sh bin/lint-conventions.sh` names the file and its current length; this
line used to carry the number and was wrong by the time anyone read it.

## The claim

**Modularity is decided in planning and paid for in coding.** In a planning
session the whole system is in view and the seams are still free to move;
choosing where they go costs nothing but thought. By coding time the structure
is fixed and you are only living with it — and *restructuring mid-task is itself
the failure mode*, because you are reorganising a file under a context window
that already cannot hold it.

So the doctrine has two different forms, and confusing them is how it gets
misapplied:

| session | the rule | why |
|---|---|---|
| **planning** | *Where do the seams go?* Decide deliberately; this is the only moment it is free. | Structure is still liquid. |
| **coding** | *Don't grow the file you're in.* If it is already over the line, **record it as a finding, do not fix it inline.** | A split under pressure is the high-risk edit the doctrine exists to prevent. |

## Why it matters to an agent specifically

An agent has no working-memory limit, so the human argument for a monolith
("keep it all in one place") does not transfer. Three things replace it:

- **Context is a budget, not a container.** A 1,500-line file read to change ten
  lines spends the budget on the 1,490. Facts in the middle of a long file are
  the ones missed.
- **Blast radius is bounded by the file, not by the intent.** An edit to fix one
  rule in a 425-line guard can silently alter a sibling rule sharing the same
  variable — recorded, with receipts, in DE-01 (`docs/decisions/rejected-approaches.md`).
- **Compute is all-or-nothing at the module boundary.** You re-run what you
  cannot isolate.

The last one is measured here, not asserted. One `guard-bash.sh` invocation
**forks 99 external commands** (232 ms; 97% of it inside the rule body, not
startup). A full replay of real traffic is **~36 minutes serial**. There is no
way to re-run *one rule* — the smallest executable unit is the whole guard. That
cost was fixed at planning time and is paid in every session since.

## What Harbor already has, and it is the harder half

The context-economics half is real and **mechanically enforced**, which is more
than most codebases manage:

| concern | mechanism |
|---|---|
| Context exhaustion | `bin/context-budget.sh` + lint **X3** — a byte ceiling on the always-on prompt surface. It caught the surface at **106%** and forced the trim to this directory. |
| Too many tools to choose between | The **invoked-only skill tier** (`disable-model-invocation: true`) — vendored skills cost *zero* context until called. This is the answer to hyper-fragmentation: a large catalogue is free as long as it is not resident. |
| Composition without coupling | [`CONTRACTS/`](../../contracts/) — frozen seams (descriptor, `--json`, marker, box-profile, memory-format) so four repos build in tandem without reading each other. |
| Blast radius | The detect-and-defer marker + the enforcement ladder (Deny > Block > Fail > Report > Document). |

**What is absent is any standard about code structure**, and Harbor's own numbers
are the counter-example: a median well under the G1 line across `bin/`, with a
handful of outliers. The median used to be written here as `p50 = 108`. It was
**172** when checked on 2026-08-01 — a 59% error, three lines above the sentence
below explaining that stating these in prose is the drift T2 exists to prevent.
This file was not scanned by T2 or T3, because every T-rule loops over
`$ROOT/*.md` and `$ROOT/CONTRACTS/*.md` and `DOCTRINE/` is in neither.
The live figures are generated, never restated here — `sh bin/lint-conventions.sh`
names every file currently over the line, and lint **G1** is the mechanism.
Stating them in prose is exactly the drift **T2** exists to prevent, and the
first version of this file did it and was stale within one commit.

## The floor's exemption, and its actual reason

**The guards are deliberately monolithic, and this is not an oversight.** It has
never been written down, which is the gap this file closes: until now nothing
distinguished *"one file on purpose"* from *"nobody split it yet"*.

Three mechanisms require it:

1. **Lint F1** requires the `HARBOR_ADMISSION_DISABLE` kill-switch to be the *first
   live line* of every guard. A guard split across files has more than one first
   line, and the escape hatch must be unmissable in the file you are reading.
2. **B6** hash-pins *each guard file* into `.helm-pins/`. Splitting `guard-bash.sh`
   into a file per rule multiplies the pin surface by the rule count — and every one of those
   pins is a thing that can drift, be forgotten, or be tampered with individually.
3. **Fork cost.** Rules already cost 99 forks per invocation. Per-rule *files*
   would add a process spawn per rule, and DE-09 records that a
   per-segment fork regression took SessionStart from 0.23s to 38s — and **a hook
   that exceeds its timeout is skipped, so a slowdown in a guard is a fail-open
   bypass, not a slowdown.**

The two harnesses (`floor-test.sh`, `lint-conventions.sh`) are exempt for a
weaker but sufficient reason: they are flat lists of independent assertions.
Splitting them moves lines between files without reducing anyone's blast radius,
because no assertion can affect another.

**An exemption must carry its reason in the file's own header.** Lint **G1**
enforces exactly that — the point is not to permit large files but to make the
permission *argued*, so it cannot spread by imitation.

## The rule

- New non-floor code: **300 lines** is the advisory line — chosen to sit between
  the p75 and p90 of `bin/*.sh` at the time of writing, so it flags outliers and
  nothing routine. Recompute before moving it; do not restate it.
- Advisory, not blocking. A size threshold is a *smell*, and promoting a smell to
  a build failure is how a linter becomes something people route around.
- **Over the line in a coding session? Record it, don't fix it.** The split is a
  planning decision; making it mid-task is the edit this doctrine warns about.

## The trap on the other side

Splitting too far is its own failure. A system of hundreds of tiny components
with non-uniform interfaces makes *discovery* the bottleneck: the agent burns
its reasoning loops working out which component failed, and fragmented state
across many stores makes "what is true right now" unanswerable.

Harbor's protection against this is not restraint, it is **uniformity**: every
guard takes the same hook JSON on stdin and answers with the same exit codes,
and every contract in `CONTRACTS/` is frozen. A catalogue of dozens of skills and a
handful of guards is navigable because they all answer the same way. Count is not
the problem; *variety of interface* is.

## The shape question — depth, seams and adapters

Everything above answers *when* to decide a structure and *how large* a file may
get. Neither answers *what shape* the thing should be, and that is the axis a
reader actually has to choose on. This section supplies the vocabulary. Use these
words exactly; substituting "component", "service", "API" or "boundary" is what
the vocabulary exists to prevent.

**Module** — anything with an interface and an implementation. Scale-agnostic on
purpose: a function, a script, a guard, a skill, a repo. *Avoid*: unit,
component, service.

**Interface** — everything a caller must know to use the module correctly. Not
just the signature: invariants, ordering constraints, error modes, exit codes,
required configuration, performance characteristics. A guard's interface is *hook
JSON on stdin, these exit codes, this timeout* — the timeout is part of it,
because DE-09 is what happens when a caller does not know it.
*Avoid*: API, signature — both name only the type-level surface.

**Depth** — leverage at the interface: how much behaviour a caller or a test can
exercise per unit of interface it has to learn. **Deep** is a large
implementation behind a small interface. **Shallow** is an interface nearly as
complex as the implementation, which is a pass-through wearing a module's name.

**Seam** *(Feathers)* — a place where behaviour can be altered without editing in
that place; the *location* at which an interface lives. Where the seam goes is a
separate decision from what sits behind it. *Avoid*: boundary — overloaded with
DDD's bounded context, and Harbor already uses "boundary" for the credential and
privacy senses ([credential-boundary.md](./credential-boundary.md)).

**Adapter** — a concrete thing satisfying an interface at a seam. Names a *role*,
not a substance.

**Leverage** and **locality** are what depth buys, and they split by audience.
Leverage is the caller's: one implementation pays back across N call sites and M
tests. Locality is the maintainer's: change, bugs, knowledge and verification
concentrate in one place instead of spreading across callers.

### Three tests that decide it

- **The deletion test.** Imagine the module gone. If complexity vanishes, it was
  a pass-through. If complexity reappears across N callers, it was earning its
  keep.
- **The interface is the test surface.** Callers and tests cross the same seam.
  Wanting to test *past* the interface is evidence the module is the wrong shape,
  not evidence that a test helper is needed. `bin/admission-mutation-tier.sh`'s header makes
  exactly this argument for staying one file: one predicate plus two renderers
  over one fixture, tested through the predicate.
- **One adapter is a hypothetical seam; two is a real one.** Do not introduce a
  seam until something actually varies across it. A single-adapter seam is
  indirection with a design word on it.
- **Reality and value are two questions, and only both together justify a split.**
  *Reality*: cut the file at its own function boundaries, cut a copy at arbitrary
  offsets into the same number of parts, and compare what each costs to describe
  (`gzip` bounds it — AIT gives `C(x) >= K(x)`). Structure survives the first cut
  and not the second. *Value*: count symbols with at least two callers **outside
  the file**. Real-but-private is the commonest good state, not a defect: a suite
  of independent assertions has perfectly real boundaries that nothing crosses.
  Measured 2026-08-30 across the **52** files over three hundred lines here, 36
  have real internal boundaries, two have two or more external callers, and **not
  one meets both**. `guard-lib.sh` is the instructive case: 13 of its symbols are
  called from two or more other files, and its own function boundaries score
  `gain=+0.031` — below the threshold. It is correctly ONE deep shared library
  rather than a set of them, and no arrangement of its internals would follow the
  substance better. A metric reporting only reality would have recommended
  fragmenting 36 files, every test suite included. Both questions are answered by
  [`bin/lint-module-shape.sh`](../../bin/lint-module-shape.sh) — `--seam <file>` for one file,
  no flag for a whole tree.

### This reframes the floor exemption

The exemption above is argued defensively — three mechanisms *require* the guards
to be monolithic. Depth makes the same case affirmatively, and the stronger claim
is worth stating: **the guards are deep modules, and that is why the exemption is
correct rather than merely permitted.** A very large implementation sits behind
an interface of hook JSON, five exit codes and a timeout. Splitting per rule
would not reduce the interface — it would multiply it by the rule count while
leaving every implementation line exactly where it was. That is the shallow
direction, and the size threshold would have applauded it.

**So the two axes can disagree, and when they do, depth wins.** A file over the
300-line advisory line whose interface is one predicate is healthier than five
files under it sharing a mutable global. Record the size finding; do not let it
drive a split that widens the interface.

## Rejected framings

Recorded because each is a plausible next proposal, and
`docs/decisions/rejected-approaches.md` is for strategies while this is for *definitions*
— the confusion is cheaper to prevent here, beside the word it would corrupt.

- **Depth as the ratio of implementation lines to interface lines** (Ousterhout's
  own formulation). Rejected: it rewards padding the implementation, and Harbor
  already has a line-count axis that would then be measuring the same thing
  twice, in opposite directions. Depth here is leverage, not ratio.
- **"Interface" as the public function list.** Too narrow. Under it, a guard
  whose exit codes changed would have an unchanged interface, which is the one
  change most likely to break every caller.
- **Splitting to satisfy the 300-line advisory.** The line flags outliers for
  *examination*; satisfying it is not the goal, and doing so by widening an
  interface is a regression the linter would score as an improvement.
- **A shared library as the first move.** `bin/guard-lib.sh` earns it, and the
  number matters: **16 of 134** scripts actually `.`-source it, and **13** of its
  symbols have two or more external callers. An earlier revision of this line said
  *53 of 131*, which counted every file that mentions the string — a 3.3x
  overstatement, drifting in the direction that flatters the argument it supports. A second one extracted before two callers exist is the
  single-adapter seam above.

### Flagged ambiguity — "mutation"

The word carries two unrelated senses in this repo and both are load-bearing:

- **Mutation testing** — policy/constitution.md §№2 rule 10: break the thing a test
  guards, watch it go red, restore.
- **Mutation tier** — `bin/admission-mutation-tier.sh`: what *writing* to a path lets an
  agent do to the floor.

Neither is renamed here, because both names are correct in their own literature
and each is already load-bearing in code. Say **mutation testing** in full
wherever rule 10 is meant; a bare "mutation" in a path or permissions context
means the tier.

