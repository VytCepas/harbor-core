---
name: doc-workshop-deck
description: "Prepare a live workshop or teaching session: a backward-designed plan, an assertion-evidence slide deck (.pptx) with speaker notes and timed activities, a lint that fails a deck which breaks the evidence-based rules, and four subagent reviews — a learner who sees only the slides, a pedagogy reviewer, a visual reviewer and a fact check. USE WHEN preparing a workshop, training, lecture, onboarding session, teach-in, lunch-and-learn, or slides meant to TEACH colleagues or a class; when somebody says prepare slides to explain X. NOT FOR a pitch, status or decision deck (pptx skill alone), a self-study page (`doc-learning-artifact`), or an architecture diagram (`doc-atlas`)."
argument-hint: [topic, audience, minutes, and the deliverable folder]
disable-model-invocation: true
---

# doc-workshop-deck — a session people leave able to do something

## Ideal state

The facilitator walks in with one folder in `~/Deliverables/<date>-<slug>/` and the session
works on the first run:

- **`plan.json` exists before any slide does.** It names the audience and what they already
  know, 2–4 outcomes written as observable verbs, the duration, ONE running example
  that every section returns to, the check for each outcome, the glossary, and what the
  audience does differently next week. Every activity serves an outcome; every outcome has a
  check (backward design: Wiggins & McTighe).
- **Every content headline is an assertion** — a short sentence the slide proves — and the
  body is the evidence: a diagram, a code or data sample, a comparison. Not bullets.
  (Assertion-evidence: Alley; Garner & Alley 2013.)
- **Concrete before abstract.** Each concept appears first as a piece of the running example,
  then as the general term, then as an analogy only if it maps.
- **The slide is not the script.** Speaker notes carry what is said; the slide never carries a
  sentence the speaker reads aloud (Mayer's redundancy principle).
- **People do something at least every ten minutes** — a recall question, a sort, a hands-on
  step — and the session opens and closes with retrieval, not recap (retrieval practice:
  Roediger & Karpicke 2006). Ten is a design default, not an attention-span fact.
- **The deck passes `kit/lint_deck.py`**, and every judgment finding from the four reviews is
  either fixed or answered in `<deck>.context.md`.

## Inputs — ask the whole frontier in one round

Ask only what you cannot find. Each question carries your recommended default, so the
operator can answer "proceed with your defaults":

1. Audience, and what they already know (roles, not names).
2. Outcomes: 2–4 verbs a facilitator could observe ("put the steps in order", "find the
   request in DevTools"), never "understand".
3. Minutes and room: live or remote, and whether they will have laptops.
4. The running example: one real flow from the audience's own work.
5. Language of the slides and the notes.
6. What must stay off the slides: security weaknesses, credentials, IPs, client data.

Copy `kit/plan.example.json` to the deliverable folder and fill it in.

## Notes tags — the contract the lint reads

The **first line** of every slide's speaker notes carries tags; the rest is the script.

| Tag | Meaning |
|---|---|
| `[3 min]` | Planned minutes. Required on every slide. |
| `[title]` `[content]` `[activity]` `[check]` | Slide kind. `activity` and `check` reset the interaction clock. |
| `[O2]` | Outcome id this slide serves. Required on `activity` and `check`. |
| `[def DNS]` | The slide where a glossary term is defined. It must come at or before the term's first on-slide use. |

## Build

Build with the `pptx` skill (pptxgenjs, a structured deck). That skill owns the layout, theme
and render rules. Size the deck to **at most one slide per planned minute**. Put a progress
marker for the running example on every content slide (Mayer's signaling). Name its shapes
`nav-…` (pptxgenjs `objectName`): the lint skips them, so the marker never counts as body text.

```sh
uv run --no-project --with python-pptx python kit/lint_deck.py <deck.pptx> <plan.json>
uv run --no-project --with python-pptx python kit/test_lint_deck.py    # the lint's own test
```

The lint exits 1 on any FAIL and prints one line per finding with its rule id. Its thresholds
live in `plan.json → limits`. **Never loosen a limit to pass a deck.** A limit changes only on
a written reason in `<deck>.context.md`.

## Review — four subagents, in parallel, after the lint passes

Render the deck to images first (`pptx` skill). Each brief is in `briefs/`. Paste the brief,
and restate its constraints in the call: a rule that sits only in a file is not followed.

| Brief | Model · effort | Sees | Answers |
|---|---|---|---|
| `briefs/learner.md` | `haiku` · `medium` | slide images and slide text only, **never the notes** | Can the target audience answer every check question from the deck? Which terms lost them? |
| `briefs/pedagogy.md` | `sonnet` · `medium` | plan, slide text, notes | Do the analogies map? Is it concrete before abstract? Can each activity be done in its minutes? Does each check test its outcome's verb? |
| `briefs/visual.md` | `haiku` · `medium` | the rendered images | Overflow, overlap, contrast, legibility from the back of the room. Does the visual carry the headline? |
| `audit-claims` skill | its own tiers | every factual claim and its source | Supported, unsupported or contradicted. Unsupported claims are cut or marked. |

Fix, re-lint, re-render the changed slides, and stop. One review round is the default. A
second round runs only when the first round changed a slide's message.

## Done means

- `lint_deck.py` exits 0 on the delivered deck, and `test_lint_deck.py` exits 0.
- You viewed every rendered slide image yourself, after the last fix.
- `<deck>.context.md` sits beside the deck (the `office-context` skill): plan summary, each
  review finding marked fixed or answered, and the facts with their sources and dates.
- The folder is handed over as `file://` links. Publish it only when asked.

## Gotchas, each one measured

- **The lint reads a headline's word count, not its grammar.** It catches a topic label
  ("Debesų kompiuterija"), not every non-sentence. Asking whether the headline is a claim
  stays a pedagogy-review question.
- **A learner reviewer that sees the notes passes every deck.** The notes contain the
  answers. Hand it slides only.
- **Infrastructure facts from memory or a repo doc are claims with a date.** Put the date on
  the slide or in the notes, and send them through `audit-claims`.
- **pptxgenjs writes its title placeholder at `idx="100"`.** python-pptx's `shapes.title` finds
  only `idx 0`, so a naive reader sees no headline on any slide. The lint matches the
  placeholder *type*; `test_lint_deck.py` covers it. Measured on the first use (2026-11-10).
- **The running example drifts out of the deck unnoticed.** On the first use, the lint passed
  and the pedagogy reviewer found that the purchase vanished after slide 2. Every content
  headline was a true assertion about something else. A headline that names the example is
  the cheapest fix.
- **The learner marks activity answers `GUESSED` when the answer is given aloud.** That is
  correct: put the answer in the notes. Treat it as a gap only on a content slide.
- **LibreOffice can exit 1 with no output inside the Claude sandbox.** That failure is the
  sandbox, not the deck: render outside it, with `-env:UserInstallation=file://<dir>`. Where
  `pdftoppm` is missing, PyMuPDF (`uv run --with pymupdf`) turns the PDF into images.
