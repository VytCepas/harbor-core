---
name: learning-artifact
description: "The approved house style and build kit for study pages — an exam guide, a course explainer, a revision page: one section per tab, hand-drawn SVG diagrams whose boxes open a detail card INLINE under the diagram, a saved-answer quiz, study aids, and a Playwright check that runs in real Chrome on desktop and iPhone. USE WHEN building or updating a study guide, exam guide, course notes page, revision page or learning artifact; when somebody wants to learn a course, a lecture series or a topic from one page. NOT FOR an architecture or system diagram (`atlas`), a status report or findings, or anything that is not meant to be studied."
argument-hint: [course or topic, and the deliverable folder]
disable-model-invocation: true
---

# learning-artifact

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

The reference is the CCBD exam guide the operator approved on 2026-10-03, which is
CCBD guide v8 in the `learning-artifact-style` memory. This kit is that page's engine
with the course content removed.

## The kit

`kit/` builds a page from a content folder. Copy `kit/example/` as the starting point:

| File | Holds |
|---|---|
| `meta.json` | `title`, `key` (prefix for saved answers, unique per page), `lang`, `ui` (optional: every UI word, for a page in another language; see the `T` table in `engine.js`) |
| `extra.css`, `extra.js` | optional page widgets: sliders, plots, simulations. `extra.js` runs after the engine |
| `page.html` | `<div class="shell">` with `nav.toc` (each link has two spans: number, name) and `<main>`: `header.hero#start`, then one `section.topic` per tab |
| `cards.json` | `{ "<box label>": { t, d, x?, s?, a? } }`: title, detail, exam angle, source, section id |
| `quiz.json` | `[{ topic, sec, type: multi\|single\|match\|number, conf: sure\|check, q, q2?, yours?, opts \| items+choices \| answer+unit+tol, why }]` |

```sh
python3 kit/build.py <content-dir> ~/Deliverables/<date>-<slug>/<slug>.html
uvx --with playwright python kit/check.py <that page> <screenshot-dir>
```

Pass `--fragment` when the page goes to a host that adds its own document skeleton (the Artifact tool does).

**A large page with interactive widgets:** the Lithuanian 9th-grade physics + maths guide
(`~/Deliverables/2026-10-03-fizmat-9/`) is the worked example:
- `src/widgets/core.js` is a widget toolkit (slider, plot, canvas, animation loop) and
  `src/wgtest.py` proves every widget reacts to every control;
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

- `check.py` exits 0 on **both** profiles against the page you built.
- **If the page has widgets** (`kit/widgets/`: `core.js` toolkit + `core.css`, mounted by `zz-mount.js`, placed as
  `<div class="wg" data-wg="name">`), `wgtest.py` exits 0 in all four modes. It clicks every button and fails one
  that changes nothing, and it fails a ▶ that does not start motion or does not restart on a second press.
- You viewed both `*-card.png` screenshots, because a pass is not an appearance.
- `build.py` reports no unused cards.
- The page sits in `~/Deliverables/<date>-<slug>/` and is handed over as a `file://` link.
  Publish it only when asked.

## Gotchas, each one measured

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
