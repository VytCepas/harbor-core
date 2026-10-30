---
name: doc-atlas
description: "The single owner of human-readable HTML artefacts on this box: an atlas whose subject is a DRAWING, not prose. The diagram takes the whole stage with pan-and-zoom navigation, clicking any component opens structured fields — what it is, what it carries, why it exists, which files it lives in — and nothing is learned by scrolling. Tabs group the diagrams, dropdowns hold the detail, every authored string has an enforced word ceiling, and the output lands in ~/Deliverables/<date>-<slug>/ as a local file. Renders archify specs. USE WHEN presenting an architecture, a technology stack, a module or connection structure to a person; when an existing atlas needs updating; when somebody asks for a diagram they can click. NOT FOR a status write-up, a what-changed report, findings, or test output — those belong in the terminal, the PR body or a repo doc, and an HTML page that reproduces terminal output is never opened twice. NOT FOR a projection of a TOPOLOGY.md, which is `topology`'s own report-gen.sh."
argument-hint: [system to draw, or the deliverable folder to update]
---

# atlas

## Ideal state

**A person opens the file and is looking at the system, not reading about it.**
The drawing fills the stage and can be pushed around and zoomed like any schema
tool. Every box is operable: one click says what that part is, why it is there,
and which files it lives in — in fields, not paragraphs. The reader never scrolls
to learn something; they switch a tab, open a dropdown, or move the canvas.

Testable, in this order:

1. **At rest, the largest thing on screen is the diagram.** If prose occupies the
   first screen, this is a document and it has failed.
2. **Every component answers on click** — what it is, why it exists, where it
   lives — and the panel closes.
3. **Anything the drawing already shows is collapsed**, connections first. The
   panel's open space is for what the picture cannot say.
4. **No page scroll at 1920x1080.** The shell is `100dvh`; the canvas pans, the
   panel scrolls, the page never does.
5. **Every authored string is under its ceiling**, enforced by the build.

## Where the output goes — never a host

**`~/Deliverables/<YYYY-MM-DD>-<slug>/`, then `open` it and hand over the
`file://` link.** The config, the descriptions and the page live in that one
folder, so the deliverable and its source travel together. This is
`CLAUDE.md`'s deliverable rule and `admission-deliverables.sh` enforces it.

**Do not publish it.** Not to an artifact host, not anywhere with a URL. Two
things go wrong and both were paid for: a publish is keyed on the FILE PATH, so
renaming the output silently forks a second copy and leaves a stale page under
the old name; and a hosted page is a copy that drifts the moment the folder is
rebuilt, while a `file://` link always opens what the build just wrote.

## Scan it for vendor ids — and do not trust a clean scan you have not falsified

A deliverable is read by more people than a repo is, so **every file in the
folder gets scanned before the link is handed over — the page and the source and
the data side-car**, not just the page. The side-car is the one that bites:
raw API output carries ids the rendered page never shows. Measured 2026-09-10 —
the HTML was clean and the JSON beside it held a live analytics measurement id,
because the fetch that built it returns the id inside the data-stream object.

**The scan itself is the thing to distrust.** A scanner built on `\b<id>\b` is
blind to the decorated form, and the decorated form is the normal one:

| written | matches | misses |
|---|---|---|
| `\b376556078\b` | a bare id | **`p376556078`** — every analytics deep link |
| `(?<!\d)376556078(?!\d)` | both | a longer number that merely contains it |

`\b` does not fire between a letter and a digit. That page was scanned, reported
**0 leaks**, and was one step from being handed over.

**So the rule is: before the first hand-over of any new deliverable shape, plant
an id and watch the scan go red.** A scan that has never been seen red is not
evidence. This is No.2.10 applied to the one check whose failure is permanent —
you cannot un-send a link.

**Structural ids can stay; credentials cannot.** A property or container id is
usually required for the deep links that make the page useful, and it is already
in the repo. A measurement id, an Ads conversion id or label, a pixel id is
never required for anything a reader does. When you keep one, say in the page
that you kept it and why.

## What this is NOT

**The failure it exists to stop:** an HTML file that says what was done, what
works, what is still open, and what the test suite reported. That is a terminal
message with a stylesheet. Written once, read once, never opened again.

| you have | it goes |
|---|---|
| what changed and whether it works | the terminal, and the PR body |
| findings, gaps, what is still open | a ticket, or a repo doc |
| the evidence behind a decision | the repo, beside the code |
| **what the system IS** | **here** |

## The unification, and what still owns what

Four tools on this box make human-readable output. They are not competitors and
the seams are real; read this before writing a fifth.

| tool | input | output | owner |
|---|---|---|---|
| `topology/bin/topology-diagram.sh` | TOPOLOGY.md Flow table | archify **specs** | `topology` |
| **`atlas/build/build.py`** | **archify specs** | **an interactive atlas** | **here** |
| `topology/bin/report-gen.sh` | TOPOLOGY.md | a tabbed **projection of a map** | `topology` |
| `topology/bin/archify-embed.mjs` | rendered archify pages | an embeddable fragment | `topology` |

**The chain composes:** a map becomes specs becomes an atlas. `topology` owns
mapping and its own projections; this owns turning specs into something a person
clicks.

**`archify-embed.mjs` overlaps `build.py`'s extraction and has a live defect.**
It found the same three facts independently — 2.35% of the page is the drawing,
zero inline colours, archify is dark-first — and scopes tokens to `.af` where
this scopes to `.canvas`. But `extract()` returns each `<svg>` verbatim with **no
ID rewriting**, and its self-test passes a **single** file, so the multi-diagram
collision below cannot be caught by it: any report it builds with more than one
diagram loses its arrowheads. The fix is the same rewrite `build/namespace.py`
does. **Not applied here** — it is a tracked file in a governed tree and the
change belongs on its own branch.

## Navigation

Fitting alone cannot rescue a tall drawing: the admission sequence is aspect
**1.07** against a **1.59** stage, so a third of the stage is unreachable however
tight the box is. So the canvas behaves like a schema tool.

- **wheel** zooms about the pointer — the user-space point under the cursor stays
  under the cursor (measured drift: **0.007** user units)
- **drag** pans; a drag that ends over a box does **not** select it
- **`+` `-` `0`**, and a `− 100% + ⌗` cluster in the bar
- bounds are 0.4x–8x of the fitted box, and **Fit returns exactly home**

Two things make this correct rather than nearly correct. The viewBox is what
moves — no CSS transform — so hit testing, text rendering and the SVG's own
geometry stay exact at every zoom. And the canvas is `overflow:hidden` with
`touch-action:none`, because a scrollbar and a drag competing for one gesture is
how a canvas feels broken.

## Sizing: three levers, and two of them are traps

**1 · Fit the box to the drawing.** archify sizes the viewBox from the authored
layout, not from what is drawn — measured **15–21% empty on all four diagrams**.
`atlas.js` re-fits each viewBox to the real content bbox. Two details make it
right: `getBBox` returns zeroes inside `display:none`, so a plate is measured only
once **visible**; and text extents depend on the font that loaded, so it re-fits
after `document.fonts.ready`.

**2 · Widening `meta.viewBox` alone makes it WORSE, and reports success.** archify
keeps a fixed lane pitch, so a wider box leaves the participants clustered at the
left while only the segment FRAMES grow. Every fitted-box metric improves — this
one went from "65%" to "91%" — while the drawing got emptier. **`meta.column_fit:
"spread"` is the switch** that makes lane pitch follow the viewBox
(`renderers/sequence/render-sequence.mjs`, the `? :` at lines 35 and 38). Both
move together or neither does.

**The metric that caught it: measure the COMPONENT span, not the fitted box.**
`max(right) - min(left)` over `[data-node-id]`, as a fraction of the drawn width.
A frame can grow without a single component moving; components cannot.

    admission, before          65% of stage, components spanning 62% of the drawing
    viewBox widened alone     "91% of stage", components spanning 62%   <- the lie
    + column_fit: spread       90% of stage, components spanning 97%

**3 · Participant order changes travel, not the box.** Total message travel —
sum of `|column(from) - column(to)|` — is worth minimising over all orders
(7 participants is 5,040, brute force is instant). It shortens arrows and reduces
crossing. It does **not** change the aspect, because the box is declared, not
derived. Optimise travel subject to keeping column order roughly the order
participants first speak, or the pure optimum will park a participant that first
appears at step 6 in column 0.

## Ceilings, enforced

An advisory ceiling is not a ceiling. `build.py` refuses to build:

| field | limit | is |
|---|---|---|
| `kind` | 4 words | what class of thing this is |
| `role` | 12 words | what it does, one line |
| `facts` | 3-word label, 8-word value, 4 rows | the scannable half |
| `why` | 26 words | the one non-obvious reason |
| `sources` | 6 paths, no spaces | the files it lives in |

Plus **description drift**: every component in the spec must be described and
every description must match a component.

All of it was falsified when written — control passes, ten planted defects go
red, and the boundaries are exact (8-word fact value passes, 9 refused; 6 source
files pass, 7 refused). Re-falsify after editing; a gate nobody has watched fail
is a gate nobody knows works.

**Check `sources` against the branch, not the disk** —
`git ls-tree -r --name-only main`. A file that exists only in your worktree links
to a 404 for everyone else.

## The data layer: which columns actually move

`facts` says what a component IS. **`fields` says which named columns, parameters or keys
move through it** — and those are different questions. A reader chasing a column is not
reading prose; they are scanning for a name, so it renders as a name/type/meaning grid,
open by default, immediately below `Carries`. It is the one thing on the panel the drawing
genuinely cannot show.

```json
"hit": {"kind": "...", "role": "...", "facts": [], "why": "...",
        "fields": [["en", "string", "event name; 40-character ceiling"],
                   ["ep.*", "string", "string parameters; 100-character ceiling"],
                   ["gcs", "string", "consent state; G100 denied, G111 granted"]]}
```

**Relationships carry columns too, and that is usually the more interesting half** — a node
holds a schema, an edge says which part of it crossed. They live under a reserved `_edges`
key per diagram, keyed by the edge id the spec declares:

```json
"analytics": {
  "_edges": {"params-reg": {"fields": [["parameterName", "string",
              "the join between what is sent and what is queryable"]]}},
  "hit": { ... }, "params": { ... }
}
```

Keys beginning with `_` are exempt from the description-drift gate — without that, the gate
reads `_edges` as a description of a node that does not exist, which is the error it was
built to catch aimed at itself. **`_edges` ids are checked against the SPEC** exactly like
node descriptions: an entry naming an edge the drawing no longer has would render nothing
and read as *"this relationship carries no columns"*, the same expensive wrong answer a
dangling finding gives.

| field | limit | is |
|---|---|---|
| `fields` rows | 12 | longer is a schema dump, and belongs in the repo |
| field `name` | 3 words | an identifier, not a phrase |
| field `type` | 3 words | `string`, `cookie`, `hashed`, `low card`, `absent` |
| field `note` | 12 words | the only place a column's meaning fits, so it gets the most |

Duplicated names, rows that are not exactly `[name, type, note]`, empty names and `<` are
all refused. **Falsified 2026-09-07: control green, thirteen planted defects red, three
boundaries exact (12 rows pass / 13 refused, 3-word name passes / 4 refused, 12-word note
passes / 13 refused), and both directions of the drift gate still fire.** Re-falsify after
editing this.

**A node whose edges carry columns says so in the `Carries` list** — a `N cols` badge per
row — and those rows are **clickable**, opening that edge's panel. That is not a
convenience. It is the only reliable way to reach an edge whose stroke is covered.

### Two sharp edges, both measured

- **A standalone em dash counts as a word**, because the ceiling is `len(value.split())`.
  `"no request — drawn only to be counted"` is one word longer than it reads. Use a
  semicolon inside a field note.
- **`<` is refused in a field, so an angle-bracket placeholder cannot be a column name.**
  `_ga_<id>` is a natural way to write a cookie family and the gate cannot distinguish it
  from `<b>`. Write `_ga_*`. Narrowing the guard does not help — `<id>` matches every
  pattern `<b>` does.

### archify does not check edge-over-edge occlusion

Its `clean-flow` validator refuses an edge crossing an unrelated **node** and refuses
overlapping **labels**, both with exact suggested coordinates — which is what makes
authoring a dense dataflow tractable. It does **not** check whether one edge lies on top of
another. Measured on a client atlas 2026-09-07: two edges leaving the same node ran
nearly parallel, and the upper one covered the lower along **12 of 21 sampled points**, so
clicking the lower edge was impossible at any point on its own stroke. Separately, an
edge's own label can swallow a click at the exact midpoint — the most obvious gesture a
reader has.

Neither is caught by the build, and neither is caught by `--check`. **The mitigation is the
clickable `Carries` row**, which reaches any edge from either endpoint. When probing edges
from Node, aim at `getPointAtLength(total * f)` mapped through `getScreenCTM()` and try
several `f` — the bounding-box centre of a diagonal path is empty space, so
`page.click()` on an edge lands on the canvas and silently opens nothing.

## Zones: group the parts by who owns or runs them

**A drawing of 8 or more parts gets labelled zones** — archify `boundaries` on an
architecture spec. Undivided, a 21-part data map read as one field; seven zones (the
visit, the client's shop, consent, in the page, the server, the receivers, our warehouse)
made every arrow that crosses a line read as a hand-over, which is the thing the reader is
there to see (operator, 2026-10-19).

```json
"boundaries": [{"kind": "region", "label": "Server: own subdomain", "wraps": ["api", "worker"]},
               {"kind": "security-group", "label": "Trust line: auth", "wraps": ["auth"]}]
```

- **A zone is an owner, a runtime or a trust line**, never a theme. The label names it.
  `security-group` (dashed) is for a trust or consent line, `region` for the rest.
- **One zone per part**, and the members must be contiguous on the grid: a zone is drawn as
  the bounding box of its members, so a foreign part inside that box sits in the wrong zone.
  Place the grid so each zone is a block of cells first, then wrap.
- **A single-part zone is fine** when that part is its own owner or runtime.
- **Look at it.** archify validates the boxes, not whether a label covers an edge label;
  view the screenshot before calling it done.

**The build warns, it does not refuse.** `build.py` prints `zones WARNING` naming every
architecture drawing of 8+ parts with no `boundaries`. A drawing that genuinely has no
ownership lines (a matrix of scenarios, a list of options) sets `"zones_waived": "<why>"`
on its entry in `diagrams`, and the warning names it no more.

## Inside views: one part, drawn deeper

**When one box hides a system of its own, give it an inside view**: a separate diagram that
declares which part it opens. The part's panel then carries **Open the inside view**, the
child's tab sits indented under its parent in the menu, and the child's panel at rest
carries **↑ Inside of <part>** back to it (operator, 2026-10-19).

```json
"diagrams": {
  "map":    {"spec": "map.architecture.json", "parts": "components", "edges": "connections", "tab": "0 · Map"},
  "server": {"spec": "server.architecture.json", "parts": "components", "edges": "connections",
             "tab": "0.1 · Inside the server", "inside": {"diagram": "map", "node": "api"}}
}
```

- **The child declares its parent**, never the other way round, so one key cannot drift
  from a second copy. The build places the child's tab right after its parent's,
  whatever order the config lists them in.
- **The build refuses**: an unknown diagram or part, a diagram inside itself, two inside
  views on one part, and a cycle (`tests/skill/atlas/inside.test.sh`).
- **`--check` walks every pair**: click the part, follow the link down, follow the link
  back, and the panel must name the part again — `inside views open and lead back: N/N`.
- **Draw the inside at the next level of detail, not the same one.** A server's inside view
  shows its intake, triggers and tags; repeating the parent's boxes with new labels is not
  a deeper view.
- **Wide inside views can outgrow archify's checker report.** It died at 64 KB until the
  fix recorded in `vendor/archify/PROVENANCE.md`; a `SyntaxError ... position 6553x` from
  `validate` is that bug, not your spec.

## The exposure layer: was anybody looking

`facts` says what a part IS and `fields` says what moves through it. Neither answers the
question an audit reader asks second, and it is the question that decides who has to be
told: **was this defect SEEN, or did it disappear?**

Those are different incidents. A wrong number on a scorecard was read and believed by
somebody who then made a decision. A metric that rendered as zero was also read and
believed — as *no spend* — which is worse, because nothing about a zero says "broken". And
a metric no surface renders at all was never seen by anyone, so the fix restores data that
will change no screen until somebody builds a tile. Collapsing all three into the word
*affected* throws away the only distinction a person can act on.

So the state is a **closed enum**, not prose. Five values a reader runs down one column:

| state | means |
|---|---|
| `visible` | a wrong number was displayed, and somebody could have read it |
| `silent` | displayed, but as a zero or blank that reads as legitimate |
| `absent` | no surface renders it at all, so the defect had nowhere to show |
| `clean` | displayed and correct — the control that makes the others provable |
| `unknown` | nobody can say from here, and saying so beats guessing |

```json
"i1": {"kind": "…", "role": "…", "facts": [], "why": "…",
       "exposure": [["overview scorecards", "visible", "revenue read 4.8x high through June"],
                    ["cost tiles", "silent", "showed zero; reads as no spend, not as broken"],
                    ["impressions", "absent", "no client surface renders this column"],
                    ["Danbalt revenue", "clean", "unchanged to the cent across the fix"]]}
```

| field | limit | is |
|---|---|---|
| `exposure` rows | 8 | past this it is an inventory of surfaces, not a claim |
| `surface` | 4 words | where a person was looking, held as tight as a field name |
| `state` | the enum above | free text here lets "affected" back in |
| `note` | 12 words | the only place the difference between the states fits |

**It is optional and absent it changes nothing**, which is not politeness — a required
field would have made this skill refuse the four atlases it was derived from. Verified by
rebuilding the MCP estate example against the new build: 4 drawings, 30 parts, exit 0,
unchanged.

**Why this is per-NODE and findings are per-PATH.** A finding says *there is a defect and
it runs through here*; exposure says *and this is the screen it reached*. One defect
usually has one path and several exposures with different states — which is exactly the
shape that a single severity cannot carry.

**Falsified 2026-09-09: 19 cases, control green on both a normal block and one using every
enum value, ten planted defects red (nine rows, two-item and four-item rows, a row that is
not a list, an empty surface, a duplicated surface, a bogus state, a capitalised state, and
`<` in both a note and a surface), and three boundaries exact — 8 rows pass / 9 refused,
4-word surface passes / 5 refused, 12-word note passes / 13 refused.** Re-falsify after
editing this; the harness is a dozen lines and rebuilding it costs less than trusting it.

## The reach layer: how far it gets, and who ends up reading it

**Where a defect IS and how far its consequence TRAVELS are two paths, and a drawing that
paints only the first answers the wrong question.** A reader asks "where is it" once, and
"who ends up reading this" every single time — because that is the question that decides
whether the client has to be told today. Measured on a client atlas 2026-09-10: a wrong tag
and the weekly report that inherited it were lit in the same colour, so the two things the
reader most needed to tell apart were the one pair the drawing could not distinguish.

`reach` sits on the **finding**, beside `nodes` and `edges`:

```json
"reach": {"audience": ["client", "platform"],
          "note": "The ad platform bids on it, and the Video CPA in our report inherits it",
          "nodes": ["dts", "ds", "marts", "report"],
          "edges": ["adsrc-dts", "marts-report"]}
```

**`audience` is a closed enum for the same reason `exposure`'s state is** — free text lets
*affected* back in, and *affected* is precisely the word that hides whether anyone saw it.
Four values, because they are the four different conversations:

| value | means | what it costs you |
|---|---|---|
| `client` | a number the client reads, or a decision they make, is wrong | a message today |
| `platform` | an ad platform receives, records or optimises on a wrong value | money, continuously |
| `agency` | only our own internal view is wrong; the client never sees it | a ticket |
| `nobody` | no surface renders it yet, so the consequence is latent | a note, and no alarm |

A list, widest first, because *client + platform* is the commonest real answer — though
not the most common: on one client's atlas, 25 findings of 35 name `client` and only 12 name `platform`,
because most tag-layer privacy and security defects have no platform audience at all.
**`nobody` cannot share the row with another value** — it is the absence of an audience, and a chip
strip reading `CLIENT · NOBODY` prints the two answers a reader has to choose between as
if both were true.

| field | limit | is |
|---|---|---|
| `audience` | 1–4, from the enum, no repeats | who ends up reading it |
| `note` | 16 words, required | what they actually see — the sentence the enum cannot carry |
| `nodes` / `edges` | ids on the finding's own diagram | how far, as a path |

**The two ceilings that matter are the enum and the note together.** A chip with no
sentence is the *affected* this field exists to replace; a sentence with no chip is prose
nobody can scan down a column. The build refuses either alone.

### The highlight is the point, and it is a THIRD state

**The cause is RED and the consequence is YELLOW**, set 2026-09-10: `--cause` on
`.lit.cause` at opacity 1, `--effect` on `.reach` at `.82` with a wider doubled halo, and
`--dim` for everything else.

**`.cause` is a class ON TOP of `.lit`, and that seam is load-bearing.** `light()` is
called from three places — a node click, an edge click, and a finding — and all three used
`.lit`. Painting `.lit` red would have told a reader that every healthy box they clicked
was broken. So an ordinary selection keeps `--accent` and only a finding adds `.cause`.

**Four separable channels, because any one alone fails somewhere real.** Red against
yellow is a weaker HUE pair than the blue/amber it replaced — both are warm, and a
protanope or deuteranope loses much of the difference — so the tokens are picked far apart
in LUMINANCE instead: light `#c0271d` against `#b58900`, dark `#ff7a6e` against `#ffd75f`.
That pair separates on brightness alone, which is what survives greyscale and the common
colour blindnesses. The opacity ordering `dim < reach < cause` is the third channel and
the doubled halo width the fourth. **Measured in both themes 2026-09-10:** light
`.34 < .82 < 1`, dark `.44 < .82 < 1`, cause and effect filters distinct, nothing carrying
both classes, and an ordinary click still resolving to `--accent` rather than to red.

**The legend is the two panel headings**, each coloured to match its own halo — *Where it
happens* in `--cause`, *How far it reaches* in `--effect`. A key in the corner is the
one part nobody looks at; a heading the reader is already reading is free.

**Reach ids do not travel with `also`.** They are home-diagram ids, so the second halo is
drawn only on the finding's own diagram and the panel says which tab that is. Painting a
home id on a foreign drawing would either miss silently or hit an unrelated box that
happens to share a name.

### Two sharp edges, both measured

- **An id cannot be in both paths, and the build refuses it** — one box in two colours
  teaches the reader that the distinction is decorative.
- **The declared path is not the whole lit path.** A finding that names no `edges` has them
  **inferred** from its nodes by `light()`, so a `reach.edges` running between two of the
  finding's own nodes gets both halos while the config looks clean. Found by this feature's
  own browser assertion on the first config that used it. The build now mirrors that
  inference and refuses it; if the defect is on that arrow, declare it in `edges`.

**Optional in the build, required by the audit.** Absent, nothing changes and every earlier
atlas still builds — the same call `exposure` made, and for the same reason. What makes it
mandatory is `measurement-audit`, which is the layer that governs what an audit must
produce rather than what a page can render.

**How it composes with `exposure`.** They answer different halves and are not
interchangeable: `reach` is per-FINDING and says *how far this defect travels and who reads
it*; `exposure` is per-NODE and says *what that particular screen showed* — a wrong number,
a believable zero, or nothing at all. Use `reach` on every finding; add `exposure` to a node
when the same defect hit several surfaces in different states.

**Falsified 2026-09-10: 28 cases. Nine controls green** — including the whole shipped client
config unmodified, `nobody` alone, three audiences, and a 16-word note — **nineteen planted
defects red**, and the note boundary exact at 16 passing / 17 refused. The browser assertion
was driven red by deleting the highlight from a copy of the built page: 25 `reach unlit`
against zero on the pristine one. Re-falsify after editing this.

## `kind`: a proposal is not a weak fact

**An audit carries two sorts of item and only one of them is a fault.** Rendered on one
axis, a tracked improvement reads as a defect whose severity happens to be low — which is
how somebody's owned work comes to look like a passing request. Measured on a client atlas
2026-09-10: six improvements sat in a brief section as prose, with no id, no owner, and no
entry in the picker; nothing on the page said who had put them there.

`kind` is a second axis on the finding, defaulting to `defect`:

| kind | means | its `status` vocabulary |
|---|---|---|
| `defect` | something is wrong now | `confirmed` `understated` `overstated` `reframed` `lead` |
| `improvement` | nothing is wrong; this would make it better | `proposed` |

**The two vocabularies do not mix, and the build cross-checks them.** A defect cannot be
`proposed` — it either holds or it is graded — and an improvement cannot be `confirmed`,
because there is no measurement of a thing nobody has done. Without that cross-check the
enum is decoration and the axis it was added to separate collapses again.

**Why `kind` rather than a sixth `status`.** `status` answers *how well is this known*. A
proposal is not a weaker fact, so putting `proposed` in that column asks the reader to
compare it with `confirmed` on an axis it does not sit on. Two fields, two questions, both
columns still scannable.

### The halos keep their meaning; the words change

Red is always the thing you would act on, yellow always what lies downstream of it. So the
same two highlights serve both kinds and the panel relabels them:

| | defect | improvement |
|---|---|---|
| red path | Where it happens | Where it would change |
| yellow path | How far it reaches | What it would improve |
| `reach.note` | They see | Who gains |

**A third highlight was the alternative and is the wrong one** — three is where a legend
stops being readable off the headings, which is the whole reason the legend lives in them.
`reach.audience` needs no new values either: the same four answer *who gains* when read
from the other side.

**Grouping is array order.** The picker is emitted in the order the findings array carries,
so sorting `kind` first and severity second is what puts improvements in their own block
after the defects. Prefix the label `IMPROVEMENT · ` as well — the picker is the one
surface where all three groups are adjacent.

**Falsified 2026-09-10: 12 cases. Four controls green** — no `kind` at all, `defect` with
two different grades, `improvement` with `proposed` — **eight planted defects red**,
including every crossed vocabulary in both directions and a `kind` that was capitalised.
The twelfth case found a real bug: an unhashable `kind` raised `TypeError` past the
membership test and killed the build with a traceback instead of the named refusal every
other gate gives. Fixed, and the type check is why. Re-falsify after editing this.

## archify: what is true, measured 2026-09-02

Six things not in its documentation, each of which cost a debugging pass:

1. **The canonical drawing is one `<svg>` inside a ~700 KB viewer document, and it
   carries ZERO hex colours.** Every fill is a class (`c-security`, `t-muted`)
   resolving to a custom property. Lift the `<svg>` plus the rules its classes
   match and both themes come free. 22–26 KB instead of 700.
2. **Inlining more than one archify document collides on IDs.** Four documents put
   four `id="arrowhead"` markers in one page; `url(#arrowhead)` binds to the
   first, which sits in a hidden tab panel, and **a marker inside `display:none`
   paints nothing** — so every diagram after the first silently loses its
   arrowheads. `build/namespace.py` rewrites every `id`, `url(#…)`, `href="#…"`
   and `aria-labelledby` per diagram and asserts no reference dangles.
3. **archify's `:root` is its DARK palette.** The host contract wants light on bare
   `:root`. Invert deliberately, and write all three theme states.
4. **archify names two tokens `--panel` and `--bg`.** On `:root` they repaint the
   host page. Scope them to the canvas; properties inherit.
5. **The SVG already carries the click affordance** — `data-node-id`,
   `data-node-kind`, `data-edge-from/to/label`, plus `role="button"` and
   `tabindex="0"` on every node. Do not build hit targets.
6. **The component schema is `additionalProperties: false` with no description
   field.** `label`, `sublabel`, `tag` are all a component can hold, which is why
   descriptions live outside the spec and why the drift gate has to exist.

Known and not ours: some sequence participants render their brand icon over the
label. Present in archify's own PNG output; do not patch the renderer.

## Previewing

**Serve the wrapped preview, never the bare file.** `python3 -m http.server`
sends no charset, the browser guesses Latin-1, and every `·` becomes `Â·` — a
property of the preview, not the page. `build.py --preview` writes
`preview.html` with the right skeleton around it.

## Finding things, and pointing at them

Thirty components across four tabs is past what anyone scans, so the page carries
three things that only an atlas can:

- **`/` searches every diagram at once**, over label, sublabel, kind, role and tab
  name — so "grant" finds the policy gate without knowing its name.
- **The URL is a location**: `#admission/mcpauth`. It updates as the reader moves
  and restores on load, which is the difference between sending someone *this
  view* and sending them the file plus directions.
- **"Also appears in"** links the same component across diagrams. Matched on
  **label, not id** — ids are per-spec and already differ, while the label is what
  the author asserted is the same thing.

## Findings: the second subject

**An atlas of a system that is broken has two subjects.** The drawing says what the
system IS; a reader handed one during an audit is asking where it FAILS, and that
answer is a **path** — some nodes and the arrows between them — not a box.

Optional `findings` in the config. Absent, the control is hidden and nothing changes.

```json
"findings": [
  {"id": "F1", "severity": "critical", "label": "The join discards 41-56% of spend",
   "status": "confirmed", "basis": "query", "measured": "2026-09-03",
   "diagram": "join", "nodes": ["arms", "sheet", "allplat"], "edges": ["arms-sheet"],
   "what": "One sentence on the defect. 60 words, hard ceiling.",
   "cost": "EUR 750,664.16", "owner": "adops", "fix": "Move the test into the JOIN",
   "keys": [["joined on", "campaign_name = Names.string_field_0"],
            ["why it deletes", "no match leaves it NULL, and NULL IN (...) is not TRUE"]],
   "tables": [{"title": "What each arm loses", "cols": ["arm", "EUR"],
               "rows": [["LT Google", "189,348.82"],
                        {"cells": ["six arms", "748,570.81"], "mark": "total"}],
               "note": "One line under the table, for what the numbers do not say."}],
   "open": [{"label": "The crosswalk sheet", "href": "https://docs.google.com/spreadsheets/d/*",
             "note": "Column A is the campaign name. The access condition goes here."}]}
]
```

**`status`, `basis` and `measured` are required, and the build refuses a finding
without them.** Severity says how badly it hurts; these say how well it is known, and a
page answering only the first invites the reader to assume the second. Measured on a
client atlas 2026-09-03: five findings the audit marks *"one lane only \u2014 treat as a lead,
not a fact"* rendered identically to the fifteen a critic had re-measured.

| field | values | what it answers |
|---|---|---|
| `status` | `confirmed`, `understated`, `overstated`, `reframed`, `lead` | what the adversarial pass concluded. `lead` renders as an outlined **ONE LANE** badge beside the severity |
| `basis` | `traffic`, `query`, `configuration` | what the claim rests on. This decides ties: in that audit configuration and traffic disagreed four times and traffic won every one |
| `measured` | ISO date | when the evidence was taken. Staleness is **derived** from it against the newest date on the page, so nothing needs relabelling when a claim is re-measured |

**Three fields, not one, because folding them loses the kind.** A single "inherited"
value would say a claim is old and stop saying whether anyone ever watched it on the
wire.

**Optional `blocked`** is the other half, and the only authored part of the diagnostics
tab \u2014 what nobody could measure is not derivable from what somebody did. Each row needs
`what`, `probe` and `owner`, and the build refuses a row missing any of them: *a limit
stated without the probe that would settle it and the person who can run it is an excuse,
not a finding.*

```json
"blocked": [
  {"what": "The content of all 26 crosswalk sheets",
   "probe": "a drive.readonly grant on a role ADC, then one SELECT per sheet",
   "owner": "us \u2014 the highest-value single unblock in this estate"}
]
```

**`what` is one sentence and the ceiling is enforced, because the other three fields
exist.** A finding that needs a paragraph needs a table. `keys` carries the measurements
the claim rests on, `tables` carries the figures — `mark` is `total`, `control` or `bad` and
styles the row so the eye finds the line carrying the argument — and `open` says where to
go and look. An `open` entry with no `href` is legitimate and sometimes required: *ask
the warehouse connector for X* has no URL, and the Apps Script whose deployment URL IS
the credential must not be linked from the document describing that defect.

The `keys` block is headed **What the numbers say**. Set `"keysTitle"` on a finding to
override it — the heading was hard-coded to *Which columns do not match* until 2026-09-07,
which was true of the one atlas this skill was built from and false of most findings, and
which collided with the genuinely column-shaped **Columns it holds** once the data layer
landed.

**Every one of these renders through `textContent`, so markup arrives as characters.**
`build.py` refuses `<` in `what`, `label`, `cost`, `owner`, `fix`, `ticket`, `keysTitle`, in every
`keys` pair, and in every table cell. This is not fussiness — it shipped: on 2026-09-03 a
finding was rewritten with `<b>` around its dates and the reader was shown a paragraph
reading `<b>one fourteen-day window</b>`, through a build that reported success and an
acceptance suite that passed. Both were blind to it because both ask whether an element
EXISTS, never what it says. The brief is the exception and takes raw HTML, which is
exactly why the defect appeared in one place and not the other.

**The acceptance suite cannot see a broken panel.** `showFinding` lights the path and
then builds the body, so a throw in the table or link code leaves the diagram correctly
lit and the panel half-built — which `--check` scores as a pass. `atlas-panel.mjs` in
`~/.local/lib/browser-probes/` opens every finding and compares what is on screen against
what the data says should be, and it is falsified by injecting a row loss and an href
loss (4 and 19 findings go red respectively). Run both.

**A box on a topology is a place, and a place has an address.** Node descriptions in the
`describe` file take the same `links` array, rendered by the same helper:

```json
"sheet": {"kind": "...", "role": "...", "facts": [], "why": "...",
          "links": [{"label": "LT — KAMPANIJU PAVADINIMAI",
                     "href": "https://docs.google.com/spreadsheets/d/*",
                     "note": "needs Drive access to the client folder"}]}
```

Without it a diagram is checkable only by whoever drew it. Where a box genuinely has no
address — a step in a mechanism, a person deliberately not named, a URL that is itself
the credential — say so **in a link entry with no href** rather than leaving it blank, so
a node that later loses its address is distinguishable from one that never had one.

Picking one switches to its diagram, dims the rest to the same level a selection does,
and fills the panel with the finding plus **a button per node and per edge on the path**
— which is what turns "there is a problem" into "it is HERE". `Esc` clears it, and so
does changing tab, because a finding belongs to one diagram and a picker still reading
`F1` on another page says the highlight is somewhere on screen when it is not.

Three rules, all enforced by the build:

- **A named edge wins over an inferred one.** Lighting every edge between a finding's
  nodes would implicate hops the finding does not claim. Name edges and only those light;
  name none and the endpoint inference a selection uses still applies.
- **Ids are checked against the SPEC**, exactly like the description gate. A finding
  pointing at a node that no longer exists would light nothing and read as *not a problem
  any more*, which is the most expensive wrong answer this page can give.
- **A finding that lights nothing is refused.** It is a sentence, not a finding, and it
  belongs in the ticket.

It dims and never hides, for the reason the highlight already gives: a hidden edge
changes what the picture claims, and a reader comparing two findings would be shown two
different graphs.

**A finding whose mechanism will not fit on the overview gets its own diagram.** On the
overview a join defect is one arrow between two boxes; what makes a number believable is
what happens to ONE row, and that is a different drawing rather than a bigger one. Draw
it as a normal tab and point a second finding at it.

## The brief: the one place prose is allowed a tab

Rule 1 says prose on the first screen means this is a document and it has failed. That
stands for an atlas somebody navigates repeatedly. **For an audit it is reversed: the
brief is the FIRST tab and the default, and the diagrams follow it.** Changed on
2026-09-04 at the operator's instruction, and the reasoning is the cold-read rule — a
reader who lands on a drawing they have never seen has to reconstruct what it means
before they can use it, and the brief is the only thing on the page that answers *what am
I looking at*. The cost is one extra click for a returning reader, and the brief's own
"Show me on the diagram" buttons pay it back. `build.py` emits it first; nothing in the
config selects this.

**The views live in a menu, not a row of tabs.** A row clipped three of seven at 1512px
with the scrollbar hidden; wrapping stopped the clipping and took a permanent second row
of header — 110px on a page whose whole subject is a drawing. The buttons still carry
`role=tab` and every attribute the script and `check.mjs` select them by. Nothing in the
config touches this, and adding a diagram costs no header height.

**`What we cannot see` is emitted LAST, after the diagrams,** and is not authored: it is
`diagnose()` counting the findings above it. What the page is not telling you only means
something once the reader has seen what it is.

Optional `brief` in the config. Absent, no tab appears and nothing else changes.

```json
"brief": {
  "tab": "Explained", "blurb": "What is healthy, what is not, and why",
  "title": "…", "standfirst": "<b>HTML</b> is allowed in body copy",
  "sections": [
    {"title": "What is working", "tone": "good", "intro": "…",
     "items": [{"h": "Headline", "p": "<b>Body</b>", "finding": "F7"}]},
    {"title": "What we took back", "cols": ["Claimed", "Held up"], "rows": [["…", "…"]]}
  ]
}
```

Three shapes only — a lede, a list of items, a table. A fourth would be an invitation to
rebuild the whole report in here, and the drawing is still the subject.

### More than one document, for more than one reader

`briefs` is a list and takes the same shape, each entry with its own `id`. `brief`
(singular) still works and becomes a list of one, so nothing that exists breaks.

```json
"briefs": [
  {"id": "brief",  "tab": "Explained",   "blurb": "…", "sections": [...]},
  {"id": "detail", "tab": "Full detail", "blurb": "…", "sections": [...]}
]
```

**Use it when the same findings have to be told to an outsider and to the team.** Not to
soften anything — to drop the parts a reader cannot act on. File paths, probe commands,
internal tooling and access grants are references the outside reader cannot follow, and a
reference you cannot follow reads as one you are not trusted with, which is worse than its
absence. Everything about the SUBJECT stays in both.

The first entry is the default tab. Ids must not collide with a diagram name or `gaps` —
every tab is a URL fragment and a stored preference, and the build refuses a clash.

**Sections and items are numbered automatically** — `1`, then `4.2` for the second item of
section four — and an item carrying `finding` also renders that id as a tag. Two different
references, because they answer two different questions: where this sits in *this*
document, and which finding on the *drawings* it is about. An audit gets argued over in a
room where nobody is on the same screen, and "4.2" survives that conversation while "the
bit about the join" does not.

**`finding` on an item is what makes this a tab rather than a second document.** It
renders a *Show me on the diagram* button that switches tab, dims the rest, and lights
that finding's path — so an explanation and its evidence are one click apart. The build
refuses an item pointing at a finding the atlas does not carry, and `check.mjs` drives
every one of those buttons with a real mouse and asserts the drawing actually lit.

**Say what is HEALTHY, not only what is broken.** A brief that lists only faults gives a
reader no sense of proportion and quietly overstates every one of them — and on a review
the working controls are usually what make the faults *provable* in the first place. Give
the good news its own section, first, with the same evidence standard as the bad.

**Not every tab is a drawing, so the script has to ask.** `order` still lists only the
diagrams, which keeps the wheel, drag and zoom wiring off the brief for free; the paths
driven by the *tab* — fit, home, the panel, the hash, the font re-fit — go through
`isDiagram(name)`. The plate scrolls inside itself; the page still never does, and the
suite asserts that.

## Running it

```sh
mkdir -p ~/Deliverables/$(date +%F)-<slug> && cd $_
cp <specs>/… .            # atlas.config.json + components.json live here
python3 ~/.claude/skills/doc-atlas/build/build.py atlas.config.json --check
open estate.html
```

**`--check` builds, serves on an ephemeral port, runs `check.mjs` against a real
Chrome, and tears the server down.** A gate that needs a server, a browser and
node is a gate nobody runs, so the build starts them. It exits non-zero on any
failure, and **127 means the pieces are not on this box — a deferral, not a pass**,
and it says so.

`check.mjs` drives the **real mouse from Node**, never `dispatchEvent` in the
page. That is not a style preference: synthetic `setPointerCapture` throws and is
swallowed, so a dispatched click is never redirected — and the capture bug that
killed all thirty nodes scored **PASS** on a synthetic suite and **0/30** on this
one. A check that aims events at its target cannot discover the target is
unreachable.

`build.py` re-extracts on every run. The drawings are a cache of `just diagrams`
output, and a cache refreshed only when somebody remembers is how a page ends up
showing last week's topology under this week's descriptions — with the drift gate
seeing nothing, because it compares descriptions against the SPEC, not the drawing.

## Output

The `file://` link, and one line per diagram saying how many parts and
connections it carries. Not a description of the page — the person is about to
look at it.

## On a phone

Measured on a 390×844 viewport, because "responsive" is a claim and a viewport is a
number.

**The header was four stacked rows — 186px of an 844px screen, 22% of the device, before
a pixel of the drawing.** Brand, view menu, search and the findings picker each took a
full row. Search and findings are both occasional and the view menu is not, so the two
occasional ones go behind one button below 760px and the bar returns to a single row.
Measured 186px → 55px, and the canvas grew 647px → 778px.

**Pinch-to-zoom is implemented here, not inherited.** The canvas sets
`touch-action:none` so a one-finger drag pans the drawing instead of scrolling the page —
which also disables the browser's own pinch. Without a handler a phone could pan a
drawing it had no way to magnify, leaving two 28px corner buttons as the only zoom. A
wide architecture diagram renders about 250px across at that width, which is legible to
nobody. Two pointers now zoom about their midpoint, re-based every frame so the gesture
stays anchored to the fingers.

Touch targets in the zoom cluster are 2.4rem minimum. A 28px control is a miss.

**Check both, and check them by measuring.** A screenshot at desktop width will not show
any of this, and a window resize may be silently ignored by a maximised window — the
reliable harness is a same-origin iframe at the target size, which gives the media
queries a real viewport. Delete it afterwards; it is not part of the deliverable.

### A finding that appears on more than one drawing

`also` maps a diagram name to the ids a finding lights *there*, when it is not that
finding's home diagram.

```json
{"id": "F3", "diagram": "collect", "nodes": ["server-tag", "conv-api"],
 "also": {"pipeline": ["server-tag", "conv-api", "server-tag-conv-api"]}}
```

**The failure it exists to stop:** adding a whole-estate map leaves every finding
pointing at the detail diagrams and none at the map. Measured on a client atlas,
2026-09-04 — a 23-node pipeline map that not one of 22 findings could light, so the
states drawn on it were a picture the evidence could not be reached from, and the
coverage diagnostic honestly reported all 23 parts as unexamined.

Two behaviours follow. **Selecting a finding while an `also` diagram is open keeps the
reader there** and lights the path on it — otherwise the first finding somebody opens
throws them out of the map they were reading. From anywhere else the finding still
jumps to its home diagram, unchanged. And the coverage count treats a node reached
through `also` as covered, so an overview map is not reported as unexamined while every
part of it is named by a finding somewhere.

Node ids and edge ids share one list; they cannot collide inside a diagram, so each is
routed by which it turns out to be. The build refuses an `also` naming a diagram the
atlas lacks, an id that diagram lacks, an empty list, or the finding's own diagram.

## Light by default, and the width goes sideways

**Light is the starting theme, not the system setting.** An audit is read once, by people
who did not choose its theme, mostly on a machine set to dark for editors rather than for
long-form prose. A stored choice always wins, and the toggle is one click for anyone who
disagrees.

Verified in light at 1512px, because a theme claim closes on an image somebody looked at:
node type colours stay distinct, every state tag is legible, and the focus dim measures
**0.34** against **1.0** for a lit node — the highlight survives the palette, which is the
thing that broke last time and in one theme only.

**A document tab gets the whole stage.** The inspector has nothing to put in it beside
prose, and an empty 22rem panel was exactly the width the text was missing. Measured 736px
→ 1088px.

**Extra width goes to a side heading, never to a longer line.** Widening the measure is
the obvious move and the wrong one — 68rem is about 128 characters, well past where the
eye loses the return sweep. Instead the heading and its reference sit in their own 15rem
column with the body beside them at a readable 40rem, which uses the space AND turns the
headings into a column that can be scanned without reading the prose.
