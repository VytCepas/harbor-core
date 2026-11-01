---
description: Resolve the design tree before building it — the whole frontier, numbered, every option with its pros, cons and consequence, the recommendation first, rounds until nothing is left unasked
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

## Every option carries its anatomy, and the recommendation comes first

The question tool is the delivery, and a rule pack denies a call that lacks these
parts, naming each gap — so write them the first time:

- **Every option**, in its description (or its preview, on a single-select):
  what it is in one concrete sentence, then `Pros:`, `Cons:` and `Consequence:` —
  what changes, what breaks or must follow, the cost, whether and how it can be
  undone, and who else it touches.
- **The recommended option is first**, its label ends `(Recommended)`, and only it
  is marked. It also carries `Why:` (why it beats the others) and `Flips if:` (the
  fact or answer that would change your recommendation). On a multi-select, mark
  each option you would pick; each marked one carries both.
- **Two to four real options.** At least one genuine alternative you would pick
  under different facts; **Defer/Hold** with its own consequence wherever waiting
  is honestly on the table. Never a strawman, never "Other" (the tool adds it).
- **When options differ on several axes, put a comparison matrix in the preview**
  (axes as rows, options as columns).
- **Name the option you would argue against** in its `Cons:` — "makes the
  failure undetectable" carries more than four neutral descriptions.

## After each round

Record each answer **where it binds, in this turn**: the ticket or PR it changes,
a decision record under `docs/decisions/`, or a named memory-note edit. A
free-text answer can redirect: re-derive the frontier from it before asking the
next prepared question. Then say what is still coming.

## Facts are not questions

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
