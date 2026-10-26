# Verification doctrine — expanded

**On-demand.** The twelve rules live in [CONSTITUTION.md](../CONSTITUTION.md)
§№2 and stay resident. This file holds the incidents that produced them and the
mechanisms that enforce them, moved out of the resident prompt on 2026-07-26
after `bin/context-budget.sh` measured the always-on surface over its ceiling.

Directly modelled on upstream's `UPSTREAM/RULES/VerificationExpanded.md`, which
does the same split for the same reason.

**Load when:** verifying web/UI output, deciding what counts as evidence,
writing a test for a guard, or judging whether a citation is honest.

## Rule 3 — verify the premise

In one session: a P1 review finding dissolved under a control experiment, and an
agent's reported "58 defects" resolved to 57 real and one that reported **the
opposite of the truth**. The claim is wrong often enough that checking it costs
less than planning against it.

## Rule 5 — existence is not support

Two separate facts, and the cheap one gets mistaken for the expensive one
constantly: a URL returning 200, a file that opens, a test that is present.

The mechanism records both halves. [CITATIONS.md](../CITATIONS.md) has an HTTP
column and a *cited for* column; `bin/cite-verify.sh` can only fill the first.
Lint rule **T7** fails the build if a document cites an external URL that was
never verified at all.

**The verifier is part of the fact.** `harbor` is a private repo, so an anonymous
`curl` returns 404 for its own issue URLs while `gh` returns them fine — the
first run of `cite-verify.sh` reported three live citations as broken for exactly
that reason. *"404 to an anonymous fetcher"* and *"does not exist"* are different
facts.

**Generalise past URLs.** Naming a file, a line number, or a prior finding as
evidence is the same claim with the same two halves. `CONTRACTS/marker.md`,
`bin/lint-conventions.sh` and `PROVENANCE.md` are all cited as evidence in this
repo; K1, T3 and T4 check that they *resolve*, and **nothing checks that they say
what the citing sentence claims**. That gap is the reader's job, permanently.

## Rule 6 — modality fidelity

`curl` returning 200 can literally fetch a different page than a browser does —
a Worker answering the request while a real browser gets an SPA fallback. A
web/UI claim closes on a real browser navigation to the actual URL.

## Rule 9 — inference picks the probe, it does not replace it

**Amended 2026-09-01.** The rule read *"reproduce before fixing"* and was scoped
to defect repair alone, while `measurement-debug/SKILL.md` had re-derived it
locally as *"reproduce before diagnosing — code and container analysis without
reproduction is speculation"*. Two copies of one rule, neither of them general,
is the signal from *Fix the system, not your notes*, so the rule was widened here
and that copy became a pointer.

**One candidate was examined and is NOT a copy.** `topology/SKILL.md` says *"ask
in writing what they currently send, field by field, before inferring it from
volumes"*. It was counted as a third copy when this section was drafted, and on
close reading that was wrong: it names which field, which alternative, and why
asking beats measuring for a payload specifically. That is an **instance** of the
rule carrying content the rule does not, and collapsing it would have destroyed
information. The distinction matters more than the count — a de-duplication that
cannot tell a copy from an application is how a tidy-looking edit removes the
only sentence that told you what to do.

**What was NOT adopted, and why it matters.** The proposal that opened the
question was ordering: *inference last, only once deterministic checking is
exhausted*. That is measurably wrong here. `.claude/skills/casefile/SKILL.md`
records EV-1, where the arm given **no instruments at all** produced the clearest
ownership split of any arm — nine tool calls against another arm's forty-three —
and was the only one to lead with what to ask rather than what it had found.
Exhaustive probing is measured harmful. An ordering rule licenses the forty-three.

It also contradicts two rules already here. №2.12 says that where a probe is
expensive you **name its cost and let the operator decide** — "determinism first"
says spend where 2.12 says ask. And it eats its own precondition: inference is how
you choose which probe to run, so a rule that fires it last leaves nothing to
select the checks.

**So the axis is role, not order.** Inference may direct the work and may not
close it. The nine-call arm inferred heavily to choose its questions and closed
nothing on inference; that is the behaviour the rule protects, and an ordering
rule would have forbidden it.

**The falsifier is the last clause, and it is the only observable part.** A
response that stops short of an available check and does not name it has broken
the rule. Naming it is checkable by a reader; its absence is not checkable by
anything, which is the honest limit of this rule — see below.

**No mechanism, and this is declared rather than papered over.** *A rule with no
mechanism is a wish.* Nothing can lint whether a claim closed on inference, and a
guard that tried would fire on prose — №2.11. This sits in the same class as the
critique rule, which already says of itself that nothing enforces it. The known
weakness is the exception clause: `constraints-bind-only-in-the-turn` measured
that **any self-grantable tier gets self-granted**, in good faith and with sound
justification. "Stopping short is allowed" is exactly such a clause, and the
disclosure requirement was written to be the thing holding it shut.

**It does not hold it shut, and that is measured, not feared.** EVALS.md **E12**
tested this rule the day it was written. Where the check was cheap, every arm
already took it and the amendment had nothing to add — a ceiling. Where the
check was expensive and the disclosure clause was the whole question, the arm
carrying this rule disclosed **zero times in eight**, exactly matching the two
arms that had never seen it. The same sentence moved into the *request* scored
four of six.

So the honest standing of this rule is: **its text is true and it removes a rule
that had been re-derived three times, but it is not a behaviour change and must
never be cited as one.** What would make it one is a mechanism that puts the
requirement in the turn rather than in this document. Building that is a
human-gated act and it has not been proposed to the operator as more than a
sentence — until it exists, this section is documentation, by its own definition
one paragraph above.

## Rule 10 — a test that cannot fail

Harbor has shipped two of these and caught both by mutation, including one
written the same hour as the constitution. The first counted matches using the
production regex under test, so it passed for every mutation of that regex; it
was rewritten to assert through an independent reader.

Every rule added to `bin/lint-conventions.sh` since is mutation-checked before it
is trusted — break the thing, watch the rule fire, restore.

**Red on a mutant proves discrimination, not correctness.** A rule that fires on
the planted violation has shown it can tell *something* apart; it has not shown
it can tell the right things apart. A pattern that matches far too much goes red
on every mutant and is still wrong. Two extra cases close it:

- **A valid-but-unusual form must stay green.** The odd-shaped legitimate input
  is where an over-broad rule reveals itself, and it is the case a mutant sweep
  never generates, because mutants are derived from the thing under test.
- **A gate reporting ZERO needs an eligible planted violation.** Otherwise the
  zero may be the harness's, not the system's — the run found nothing because
  nothing it could have found was ever in scope. Plant one that *is* in scope,
  watch the count go to one.

**Coverage is per-case, not per-run.** A sweep that is faithful in every row can
still be blind: sixteen rows that all use one provider prefix exercise one path
sixteen times. The variants that *differ* are the ones a sweep never asks for
unless someone writes them down.

**Measured here, 2026-08-27:** 2 of 44 `bin/*-test.sh` suites planted a
violation, by a method that was not written down, so the number cannot be
re-derived or compared (harbor#490). The suites have since moved to `tests/`.
What can be re-run is a vocabulary count, which says that a suite *talks* about
planting or mutating, never that it does:

```sh
find bin tests -name '*-test.sh' | wc -l                                         # suites
find bin tests -name '*-test.sh' -exec grep -liE 'plant|mutant|mutation' {} + | wc -l
```

On 2026-10-03 that read 46 of 145. Nothing still distinguishes a suite that has
been mutation-checked from one that has not, so rule 10's evidence stays
unrecoverable per suite until a mechanism records it.

## Rule 12 — your own team's documents are claims too

Added 2026-08-26, from reading the three repos of the company's data platform — a well-run,
six-times-audited platform whose own docs record the failure twice.

**The drift is directional, and the repo says so itself.**
The ingestion repo's `docs/roadmap/open-work.md` reconciles its backlog against
production and reports that several `(reported)` figures did not survive
re-measurement: *"every one had been wrong in the flattering direction."* One
item was understated **14×** and blamed the wrong platforms. Nobody had lied;
nobody had re-measured. That is the whole mechanism — a note is written once, at
the moment of most optimism, and never revised downward.

**The doc, the dashboard and the exit code can all agree and all be wrong.**
`docs/architecture/gap-detection.md` records that the platform's only
"a connector stopped delivering" alarm was *"a guarded no-op for its entire
life"*: both CTEs read a mart the production build had never built, so every run took the
`NotFound` path and returned `{"gaps_detected": 0, "skipped": "source table not
found"}, 200`. The scheduler job was ENABLED and *"saw nothing but success."* It
never healed a gap. Green is not evidence; green is a claim.

**The cost branch is the part rule 7 does not cover.** Rule 7 governs an
*unavailable* verifier. The failure this rule names is the *available but
expensive* one — the suite that takes twenty minutes, the query that bills, the
probe that needs an identity you have to go and request — where the silent move
is to trust the doc and call it grounded. Name the price and hand the decision
up; do not relabel convenience as verification.

**Found while writing this rule, in this repo:** the constitution said *"Eleven
rules"* and line 3 of this file said *"The eleven rules live in…"* — one count,
copied into two documents, both of which would have read correctly while being
wrong. Exactly the copy-drift `doc-truth.md` exists to forbid, inside the pair of
files that forbid it.

## Rule 11 — a false positive is a defect

Unmeasurable today, and that is the point of harbor#41: `floor_block()` prints to
stderr and exits, so nothing records which rule fired on what. A rule the system
cannot measure is a rule the system cannot honour. See also
`DEAD-ENDS.md` DE-10, where a "covered" verdict was reached by
matching capability names instead of reading the artefacts.

## Endogenous and exogenous instruments

Spans rules 4, 10 and 12, and generalises rule 12 one layer: if your own
documents are claims, **your own instruments are claims too, and they are harder
to doubt because they run.**

An **endogenous** instrument takes the system's own output as its input. It can
only ever prove *consistency* — that the system agrees with itself. An
**exogenous** instrument takes an input the system did not produce, and is the
only kind that can prove *correctness*.

The distinction was named for the company's data estate, where nearly every defect
traced to it: a freshness check reading the pipeline's own load timestamps, a gap
alarm reading a mart the pipeline never built. It applies to Harbor unchanged,
and nobody had applied it here.

**Measured 2026-08-27, on `~/harbor/bin`:**

| | files | lines | share |
|---|---|---|---|
| Self-referential — Harbor governing, testing or observing Harbor | 120 | 51,708 | **88%** |
| Outward-facing — tracker, gcloud, tag-manager, web, tickets | 11 | 6,834 | 11% |

Forty-four test suites answer *does Harbor work*. Roughly four touch anything
that does paid work. Every `perf` commit on `main` optimises the loop's own
overhead — folding suite jobs, not re-running a 292-second suite to read one
integer, demoting ambient skills that never fire. All real, all inward.

**This is not an argument that the guards are wrong.** A governance repo *should*
be mostly guards; that is its product, and these have caught real defects,
including twenty-four introduced by a previous pass's own confident fixes. The
defect is the *absence of a counterweight*: with no exogenous instrument, nothing
can ever report that the ratio has gone wrong, and a green self-check is
indistinguishable from a green self-check on a dead system.

**The rule.** Every instrument declares which kind it is. An endogenous one may
report and may block, but it may never be cited as evidence that the *work* is
good — only that the system is self-consistent. A claim about the quality of
output closes on an input the system did not generate: a human verdict, a second
independent implementation, a source read for the claim it is cited for.

`bin/ab-tally.sh` is Harbor's first exogenous instrument. Its input is the
operator's verdict, which no part of Harbor produces.
