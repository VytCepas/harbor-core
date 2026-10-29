---
description: Resolve the design tree before building it — the whole frontier, numbered, one recommendation each, rounds until nothing is left unasked
---

**For this conversation the ask-sparingly default is suspended.** Not softened —
suspended. Your standing instructions, and the question tool's own description,
both reserve questions for cases where proceeding would be unsafe and warn you
off asking where a conventional default exists. That is the correct default and
it is the wrong one here: the operator has just told you the shape of this design
is not settled, which is the one condition under which a set of questions IS the
deliverable and an artefact is not.

This override is why the doctrine failed on its own. `docs/explanation/grilling.md`
carries the method and gates itself on a self-assessment — *"roughly one turn in
twenty"* — and it ships two clauses you can grant yourself: that gate, and the
constitution's own instruction to flag an interpretation fork in one line and
keep going. Measured on this box across six runs with one variable
(`constraints-bind-only-in-the-turn`): a constraint written in a background
document is advisory and gets violated by an agent that read it, understood it
and agreed with it; the same constraint restated inside the request binds. **Any
exception clause will be taken.** So neither clause is available for the rest of
this conversation.

## Done looks like

**An empty frontier.** Every decision whose prerequisites are settled has been
put to the operator and answered. Nothing was assumed on their behalf, and
nothing was asked that you could have looked up. That is a checkable bound; "we
have a shared understanding" is not, and premature completion is the failure this
whole procedure replaces.

Read `docs/explanation/grilling.md` for the method — the frontier, the rounds, the four
properties, and the fact/decision split. It is the argument; this is the
mechanism, and where they differ, the paragraph below wins because it is in the
turn.

## The cap is four, and it is the runtime's, not a preference

The interactive question tool takes at most **four questions per call**, each
with **two to four options**. The doctrine says "ask the whole frontier in one
round" and the runtime refuses more than four, so as written it is
unimplementable — the document and the runtime disagree and the runtime wins
silently, by truncation, which is the worst of the three outcomes because nobody
sees it happen.

So the frontier is worked in **iterated rounds against the cap**:

- Ask up to four. Never more, and never *four for the sake of four* — a round
  that manufactures questions to fill the cap trains the operator to skim, which
  costs you the round after it. One genuine open decision is one question.
- Between rounds, **say what is still coming**: the count and the one-line shape
  of the questions not yet asked. The operator can then see how long this is,
  redirect it, or cut it short — none of which they can do if each round arrives
  with no horizon.
- Stop when the frontier is empty, not when it feels resolved.

A question whose answer depends on another question still open **belongs to a
later round**. Serialise only genuine dependencies; batch everything else. Asking
a dependent question early forces a guess, and a guessed prerequisite is how a
design grows a branch nobody chose.

## Every question carries a recommendation

- **Recommend an answer to each**, and put the recommended option first, marked.
  A question with no recommendation is work handed back.
- **Name the option you would argue against, and the consequence** — where there
  is one. Not every round has one. "I would argue against (c), it makes the
  failure undetectable" carries more than four neutral descriptions.
- **Facts are yours, decisions are the operator's.** When a frontier question
  needs a fact from the environment, go and get it: read the file, run the probe,
  check the ticket. Never ask for something you could look up. Do not block on it
  either — a running exploration is an unsettled prerequisite, so only the
  questions *downstream* of it wait. Ask the rest of the frontier now.
- Where an option set genuinely will not compress into two-to-four choices, ask
  it as an open question rather than dropping it. The cap is a limit on the tool,
  not a filter on the design.

## Read-only until the operator says otherwise

A resolved frontier is not a licence to write. `policy/constitution.md` §5 still governs
the verb: this command resolves a design, it does not build one. When the
frontier is empty, hand back the resolved tree and the plan it implies, and stop
there.
