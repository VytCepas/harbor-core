---
name: doc-learning-artifact
description: "The operator's preferred page for learning anything: one section per tab, hand-drawn SVG diagrams whose boxes open a card under the diagram, a saved-answer quiz, gates in real Chrome (desktop + iPhone) for routing, cards and text fit, and a check that every quiz question is answerable from the page. USE WHEN building or updating a study or exam guide, course notes, a revision page, or teaching or onboarding material that explains a topic, process or system so a person can learn it. NOT FOR a system map to navigate (`doc-atlas`), a live workshop deck (`doc-workshop-deck`), or a status report or findings."
argument-hint: [course or topic, and the deliverable folder]
---

# doc-learning-artifact

## Ideal state

A learner opens one local page and studies from it on a laptop or a phone without
fighting it:

- **One section on screen at a time.** A side list on desktop and a sticky, swipeable
  row of chips on a phone. Every section ends with a prev/next pager, every `#id` link
  opens the tab that holds it, browser back works, and a jump out of a tab (quiz →
  section, card → section) shows "↩ Back to …", which returns to the exact spot.
- **Every section has the same shape:** a number and title, a one-line "The idea" box,
  diagrams, traps, recording notes with ▶ timestamp links, and a links row (builds on /
  leads to / quiz).
- **Diagrams explain themselves.** Tapping any box opens its card **directly under that
  diagram**: source, title, explanation, an exam angle and a link to the full section.
  Never a fixed side drawer or bottom sheet; the operator found the sheet hard to see
  on a phone. Wide diagrams swipe, or "Fit whole".
- **Practice stays.** A quiz with answers saved in the browser, progress, "next
  unanswered", and a "revise …" link to the section from each question. Sections
  marked `data-review` get a "reviewed" tick. Recording notes have an "only the
  stressed points" filter.
- **No horizontal page scroll, no console errors, light and dark themes.**

- **Every practice question is answerable from the page.** Each one carries a verbatim
  quote from the visible text or a card, and `answers_check.py` proves the quote is there.
- **Diagram text never spills** out of its box or its viewBox.

The reference is the CCBD exam guide the operator approved on 2026-10-03 (CCBD guide v8),
and this kit is its engine with the course removed. A second exam guide built on it in 2026-11 added the answer gate, the text-fit
check and editions; the numbers below come from it.

## The kit

`kit/` builds a page from a content folder. Copy `kit/example/` as the starting point:

| File | Holds |
|---|---|
| `meta.json` | `title`, `key` (prefix for saved answers, unique per page), `lang`, `ui` (optional: every UI word, for a page in another language; see the `T` table in `engine.js`) |
| `extra.css`, `extra.js` | optional page widgets: sliders, plots, simulations. `extra.js` runs after the engine |
| `page.html` | `<div class="shell">` with `nav.toc` (each link has two spans: number, name) and `<main>`: `header.hero#start`, then one `section.topic` per tab |
| `cards.json` | `{ "<box label>": { t, d, x?, s?, a? } }`: title, detail, exam angle, source, section id |
| `quiz.json` | `[{ topic, sec, type: multi\|single\|match\|number, conf: sure\|check, q, q2?, yours?, opts \| items+choices \| answer+unit+tol, why }]` |
| `answers.json` | one `{ index, source: "page" \| "card:<key>", quote }` per question, in order: the verbatim words (≤ 160 chars) that answer it |

```sh
python3 kit/build.py <content-dir> ~/Deliverables/<date>-<slug>/<slug>.html
python3 kit/answers_check.py <content-dir> [--against <full-content-dir>]
uvx --with playwright python kit/check.py <that page> <screenshot-dir>
python3 kit/test_kit.py [--browser]   # the kit's own gates, each against a planted fault
```

## Teaching material, not only exams

A course, an onboarding explainer, a "how does X work" for colleagues all use the
same page. Each concept gets a tab, a picture and its traps. The quiz is optional, but it
is the learner's own self-check, never a task set for others. For a system someone
navigates rather than learns, use `doc-atlas`. For a live session, use `doc-workshop-deck`.

## Editions: a full page and a short one

When the source is large, build the full page first, then condensed editions from the
same content. Each edition is a content folder of its own. The 2026-11 guide shipped three
editions from one source: full, a 9-question-per-lecture core, and a final edition at
59 % of the prose with every question kept.

- **Every question kept must stay answerable.** Run `answers_check.py <edition>
  --against <full>`. It also fails any diagram not copied byte-for-byte from the full
  page, because the card keys and the fit check depend on exact labels and geometry.
- **Saved answers are stored by question position** under `meta.key`. An edition with
  the same questions in the same order may share the full page's key, so progress
  carries over. One that drops or reorders questions needs its own key, or every
  saved answer lands on the wrong question.
- **Parallel writers get a brief** that states what done is: every concept, list,
  number and model answer kept, prose at most 60 % of the full page, no new claims,
  and an `answers.json` per section.

Pass `--fragment` when the page goes to a host that adds its own document skeleton (the Artifact tool does).

**A large page with interactive widgets:** the Lithuanian 9th-grade physics + maths guide
(`~/Deliverables/2026-10-03-fizmat-9/`) is the worked example:
- `src/widgets/core.js` is a widget toolkit (slider, plot, canvas, animation loop) and
  `src/widgets_check.py` proves every widget reacts to every control;
- `src/assemble.py` merges per-unit files written by parallel builders, and `BRIEF.md` is
  the brief those builders were given.

Copy them rather than starting over.

A box becomes clickable when its `<rect class="s-…"/>` is followed by a `<text>`
whose label is a key in `cards.json`. `build.py` prints `cards never used`. A
non-empty list means a label and a key disagree.

**Diagram vocabulary is in `kit/head.html`**: `s-box`/`s-acc` boxes, `s-t`/`s-tm`
text, `s-line`/`s-lacc`/`s-dash` lines and the `#ar` markers. Page blocks: `.idea`,
`.trap`, `.tbl`, `.rec`, `.links`, `.pill`, `.infobox`, `.warnbox`, `.examsaid`.
Read the CSS before you invent a class.

## Done means

- `check.py` exits 0 on **both** profiles against the page you built. That includes
  the text-fit check, which measures every diagram on every tab. It skips text and rects under a
  `transform`, so keep labelled boxes untransformed.
- `answers_check.py` exits 0 when the page has a quiz, and `build.py` prints no
  `WARNING`.
- **The answer key had a second reader.** A fresh agent checks each `why` against the
  source slides, not against the page. On the 2026-11 guide two fresh reviewers flagged
  2 of 111 keys, and both were real.
- **If the page has widgets** (`kit/widgets/`: `core.js` toolkit + `core.css`, mounted by `mount.js`, placed as
  `<div class="wg" data-wg="name">`), `widgets_check.py` exits 0 in all four modes. It clicks every button and fails one
  that changes nothing, and it fails a ▶ that does not start motion or does not restart on a second press.
- You viewed both `*-card.png` screenshots, because a pass is not an appearance.
- `build.py` reports no unused cards.
- **After changing the kit**, `test_kit.py --browser` exits 0.
- The page sits in `~/Deliverables/<date>-<slug>/` and is handed over as a `file://` link.
  Publish it only when asked.

## Gotchas, each one measured

- **Writers list the right option first.** It happened in 74 of 89 choice questions on the
  2026-11 guide. `build.py` warns when more than half the
  choice questions start with a correct option. Reorder them in `quiz.json`, and never
  shuffle at runtime, because saved answers are stored by position.
- **Strip inline tags without a space when matching quotes.** Turning `<b>` into a
  space made "Item :" out of "Item:" and gave 4 false "not found" results on the
  2026-11 guide. `answers_check.py` joins inline tags and separates block tags.

- **Never keep animation state in a range input.** The input snaps to its `step`, so adding 0,03 s per frame to a
  0,1 s slider is rounded back every frame and the ▶ button looks dead (15 failing button checks per mode on the first fizmat-9 build, worse at 120 Hz).
  `H.slider` keeps the exact value itself; widget code must not round per-frame steps either.
- **Reduce Motion is common on real devices.** An animation the student starts with ▶ plays anyway, because the
  motion is the lesson; nothing moves by itself. Jumping to the last frame instead read as a broken button.

- **The CSS sets `scroll-behavior: smooth`.** A router scroll must pass
  `behavior: "instant"`, or the back pill restores the wrong position (3351 vs 6123
  measured).
- **A test asserting the card is in view proves nothing about where it sits.** Assert
  `previousElementSibling` is the figure and `position` is `static`. A planted
  regression of the placement passed the viewport check and failed only that one.
- **Scrolling to the whole card pushes the tapped box off a phone screen.** It did for
  122 of 267 boxes in the CCBD guide. `openCard` therefore scrolls no further than
  keeps the box in view, and always shows at least the card's first 160 px. That left
  18, all in diagrams taller than the screen, so keep diagrams short or split them.
