# Grilling — resolving a design tree before building against it

**On-demand.** This changes how a *question* is asked, and the moment it can
change anything is before the work starts. Loading it every session would pay
for a procedure that applies in roughly one turn in twenty.

**Load when:** the operator proposes a design, a plan, or a change whose shape is
not yet settled — and the honest answer is a set of questions rather than an
artefact.

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

CONSTITUTION.md §"Context sufficiency" said *"up to three specific questions, one
at a time"*. The cap is sound; the serialisation was not.

Independent questions do not need ordering, and paying a round-trip for each one
buys nothing. Four independent decisions cost four rounds serially and one round
batched — and the operator, who is holding the whole design in their head at that
moment, has to reload it three extra times. **Serialise only what actually
depends on something.** The cap that matters is on the *frontier*, not on the
count.

## The four properties

1. **Number them, and recommend an answer to each.** A question with no
   recommendation is work handed back. The recommendation is what makes a round
   answerable with one word per item, and it is where the critique obligation
   (CONSTITUTION.md §"Recommendation and critique") is discharged.
2. **Say which option you would argue against, and name the consequence.** Not
   every round has one. Where it does, "I would argue against (c)" carries more
   than four neutral descriptions.
3. **Facts are yours; decisions are the operator's.** When a frontier question
   needs a fact from the environment, go and find it — read the file, run the
   probe, dispatch a subagent. Never ask the operator for anything you could look
   up. Do not block on it either: a running exploration is an unsettled
   prerequisite, so only the questions *downstream* of it wait; ask the rest of
   the frontier now.
4. **Do not act on the tree until the operator confirms.** Grilling is the
   read-only half. CONSTITUTION.md §5 governs the verb; a resolved frontier is
   not itself a licence to write.

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

**Nothing lints a round.** No check can read four questions and say whether they
were the right four, and the operator noticing a serialised frontier arrives one
turn too late to be one — the same gap §"Recommendation and critique" names about
itself. What `/grillme` supplies is not a lint but a **placement**: the method
arrives inside the turn, where the 2026-08-06 measurement says a constraint
binds, instead of in a document an agent can read, agree with and not follow.
That is the difference between doctrine with a mechanism and doctrine with a
reader, and it is the whole of what the command buys. The judgement it rests on
afterwards is still judgement, and saying so is the honest form.
