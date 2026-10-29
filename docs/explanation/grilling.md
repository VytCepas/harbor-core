# Grilling — resolving a design tree before building against it

**Two halves, two scopes.** *The anatomy of an option*, *the option set* and
*after the answer* govern **every question put to the operator** — a choice is a
choice whether it comes from a design review or a one-off fork mid-task — and
two rule packs deliver them at the tool call, so nothing here has to be loaded
for them to bind. The frontier and its rounds are the on-demand half: they apply
when the operator proposes a design, a plan, or a change whose shape is not yet
settled, and the honest answer is a set of questions rather than an artefact.
`/grillme` loads that half into the turn.

## The claim

**Ask the whole frontier at once, with a recommendation on each.** A design is a
tree: every decision branches into the decisions that hang off it. The
**frontier** is every decision whose prerequisites are already settled — the
questions answerable *now*, without guessing at answers not yet heard.

Working the tree in rounds is what makes the session terminate. Each round the
operator's answers push the frontier outward and unblock what depended on them.
The session is done when the frontier is empty: every branch visited, nothing
left silently assumed.

A question whose answer depends on another question still open in this round
belongs to a **later round**, not this one. Asking it early forces a guess, and a
guessed prerequisite is how a design tree grows a branch nobody chose.

**"The whole frontier at once" is not implementable as written, and the runtime
wins silently.** The interactive question tool caps a call at four questions,
each with two to four options — so a frontier of six is truncated to four by the
runtime with nothing said, and the two that vanished are indistinguishable from
two that were never on the tree. The termination condition (an empty frontier)
and the tool's constraint (four at a time) are compatible only if the iteration
is **explicit**: ask four, state what is still coming, ask the next four. The
mechanism that does this is `/grillme` — a command rather than a skill, because
a constraint written in a background document is advisory and the same
constraint restated inside the turn binds (harbor#463).

## Why one-at-a-time was wrong

policy/constitution.md §"Context sufficiency" said *"up to three specific questions, one
at a time"*. The cap is sound; the serialisation was not.

Independent questions do not need ordering, and paying a round-trip for each one
buys nothing. Four independent decisions cost four rounds serially and one round
batched — and the operator, who is holding the whole design in their head at that
moment, has to reload it three extra times. **Serialise only what actually
depends on something.** The cap that matters is on the *frontier*, not on the
count.

The operator's "ask interactively, one at a time" (2026-10-03) asked for
dependency order, because a free-text answer can redirect the next question. That
part stands: a decision that depends on an open answer waits for it. Independent
decisions still batch.

## The four properties

1. **Number them, and recommend an answer to each.** A question with no
   recommendation is work handed back. The recommendation is what makes a round
   answerable with one word per item, and it is where the critique obligation
   (policy/constitution.md §"Recommendation and critique") is discharged.
2. **Every option carries its pros, its cons and its consequence** — the anatomy
   below. "I would argue against (c), it makes the failure undetectable" is the
   consequence written for the option you would not pick; a neutral one-liner per
   option is a menu, not a decision.
3. **Facts are yours; decisions are the operator's.** When a frontier question
   needs a fact from the environment, go and find it — read the file, run the
   probe, dispatch a subagent. Never ask the operator for anything you could look
   up. Do not block on it either: a running exploration is an unsettled
   prerequisite, so only the questions *downstream* of it wait; ask the rest of
   the frontier now.
4. **Do not act on the tree until the operator confirms.** Grilling is the
   read-only half. policy/constitution.md §5 governs the verb; a resolved frontier is
   not itself a licence to write.

## The anatomy of an option

The operator chooses from what the option *says*, so an option that leaves its
cost out has made the choice for them. Every option a person is asked to choose
between carries five parts, in its description or, for a single-select question,
in its preview:

| Part | What it holds |
|---|---|
| what it is | the first sentence: the act, concretely, not a category |
| `Pros:` | what it buys |
| `Cons:` | what it costs or risks |
| `Consequence:` | what changes; what breaks or must follow; the cost (time, money, CI, a person's attention); whether it can be undone and how; who else it touches |
| the label | short; the recommended one ends `(Recommended)`, which the question tool's own description asks for |

**The recommended option is first**, and only it is marked. It carries two more:

- `Why:` — why it beats the others, not why it is good in the abstract.
- `Flips if:` — the fact or answer that would change the recommendation. A
  recommendation with no flip condition is a preference; with one, it is a claim
  the operator can test against what only they know.

A multi-select question marks every option you would select; each marked one
carries `Why:` and `Flips if:`.

## The option set

- **Two to four options, all real.** The tool takes two to four. Fill them with
  genuine alternatives — the one you would argue for, at least one you would pick
  under different facts — never a strawman placed to make the first look good.
  An option nobody would choose costs the operator a read and buys nothing.
- **Defer or hold is an option where it is honest**, with its own consequence:
  what waits, what keeps breaking, who is blocked. Leaving it out pretends waiting
  is free; adding it where the work cannot wait is a strawman.
- **The tool adds "Other" itself.** Never add one, and read a free-text answer as
  a possible redirect (below).
- **No question whose answer is a fact.** If reading a file, running a probe or
  checking a ticket would answer it, do that instead. The operator's attention is
  for what only the operator knows: preference, priority, risk appetite, and
  context that lives outside the box.
- **No per-item walks.** A list that needs the operator's judgement item by item
  (twenty-five labels, a dozen rows) is shown once, whole, with your read of the
  common pattern, and takes one answer plus exceptions. It is not a round per
  item.

## The round

- **Batch the whole frontier of independent decisions**, up to the tool's four
  questions per call; **serialise only what depends** on an answer not yet given.
  Between rounds, say how many questions remain and the one-line shape of each.
- **When the options differ on several axes, put a comparison matrix in the
  preview** — rows are the axes (cost, reversibility, risk, who it touches),
  columns the options — so the operator compares in one look rather than holding
  four descriptions in their head. The preview renders markdown in a monospace
  box, and only on a single-select question.
- **A dependent question is not batched with its prerequisite.** Its options
  would have to be written for an answer you are guessing.

## After the answer

**Record each answer where it binds, in the same turn** — the ticket or PR it
changes, a decision record under `docs/decisions/`, or a named memory-note edit
the operator can apply. An answer that lives only in the chat is lost at the next
compaction, and the next session asks it again.

**A free-text answer can redirect the tree.** Re-derive the frontier from it
before asking the next prepared question; a prepared round written before that
answer may be asking about a branch that no longer exists.

## The failure mode this replaces

**Premature completion.** A vague bound ("understanding reached") lets attention
slip to *being done* while branches sit unvisited, and the work that follows is
built on assumptions nobody chose. An empty frontier is a checkable bound; a
shared understanding is not.

The reverse failure is real too and cheaper to spot: a round that asks about
branches the operator has already settled reads as not listening, and trains them
to skim the next one.

## Provenance

The frontier/rounds formulation is taken from `mattpocock/skills`
(`skills/productivity/grilling/SKILL.md`, read 2026-08-27), which is the reusable
primitive behind that repo's `grill-me`, `triage` and `wayfinder`. Harbor takes
the algorithm and the fact/decision split; the recommendation-per-question and
argue-against-one clauses are Harbor's own §"Recommendation and critique"
obligation, which upstream does not carry.

**What is enforced, and what is not.** Two rule packs carry the standard to the
moment of use. `context-rules/user/decision-question-shape.md` runs
`decision-question.sh` on every `AskUserQuestion` call and **denies** one whose
options lack `Pros:`, `Cons:` or `Consequence:`, whose recommendation is missing or
not first, or whose recommended option lacks `Why:` or `Flips if:` — a deny rather
than a note, because a note rides back with the answer, after the operator has
already chosen from the thin question. `decision-answer-binds.md` speaks when the
answers come back, which is the moment the recording duty is live. The suite is
`tests/context/injection-rule/decision-question.test.sh`, and it also fails when
this document or `/grillme` stops naming a label the script enforces.

**The check reads labels, not honesty.** A strawman with all five parts passes;
a fact-question with tidy options passes; four questions that were the wrong four
pass. No check can read a round and say whether it was the right round, and the
operator noticing arrives one turn too late to be one — the same gap
§"Recommendation and critique" names about itself. What the packs and `/grillme`
supply beyond the labels is a **placement**: the method arrives inside the turn,
where the 2026-08-06 measurement says a constraint binds. The judgement it rests on
afterwards is still judgement, and saying so is the honest form.
