"""The atlas stylesheet: an app shell that fills the viewport and does not scroll.

The page it replaces was a document — masthead, prose, diagrams sunk into the column, and a
reader who had to scroll past three screens of text to reach a picture. This is the other
shape: the drawing gets the whole stage, the words live in a panel beside it, and the only
thing that ever scrolls is the panel's own content.

archify's palette is scoped to `.canvas` rather than `:root` because two of its token names
(`--panel`, `--bg`) are also the page's own. Custom properties inherit, so the SVG still
resolves every one; nothing outside the stage can see them.
"""


def css(light: str, dark: str) -> str:
    return (
        SHELL
        + f".canvas{{{light}}}\n"
        + f'@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]) .canvas{{{dark}}}}}\n'
        + f':root[data-theme="dark"] .canvas{{{dark}}}\n'
    )


SHELL = """
:root{
  color-scheme: light dark;
  --ground:#eef1f5; --panel:#ffffff; --panel-2:#f4f6f9; --sink:#e4e9f0;
  --ink:#12161c; --ink-soft:#4c5666; --ink-faint:#5b6678;
  --rule:#d5dce5; --rule-soft:#e6eaf1;
  --accent:#1c5c88; --accent-soft:#e3edf5; --good:#1c6b45;
  --flow:#15706a; --gate:#a3521b;
  --shadow:0 1px 2px rgba(16,24,40,.06),0 8px 24px rgba(16,24,40,.08);
  --display:Spectral,"Iowan Old Style",Palatino,Georgia,serif;
  --sans:"IBM Plex Sans",ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --ground:#0c1015; --panel:#151a22; --panel-2:#1b212b; --sink:#080b0f;
  --ink:#e9eef4; --ink-soft:#aab5c5; --ink-faint:#9aa5b5;
  --rule:#28303c; --rule-soft:#202730;
  --accent:#7ab3d8; --accent-soft:#16242f; --good:#7fd0a6;
  --flow:#68c5bb; --gate:#e3a069;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.35);
}}
:root[data-theme="dark"]{
  --ground:#0c1015; --panel:#151a22; --panel-2:#1b212b; --sink:#080b0f;
  --ink:#e9eef4; --ink-soft:#aab5c5; --ink-faint:#9aa5b5;
  --rule:#28303c; --rule-soft:#202730;
  --accent:#7ab3d8; --accent-soft:#16242f; --good:#7fd0a6;
  --flow:#68c5bb; --gate:#e3a069;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.35);
}

*{box-sizing:border-box}
html,body{height:100%}
body{margin:0;background:var(--ground);color:var(--ink);overflow:hidden;
  font:400 15px/1.55 var(--sans);-webkit-font-smoothing:antialiased}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}
button{font:inherit;color:inherit}

.app{height:100dvh;display:grid;grid-template-rows:auto minmax(0,1fr)}

/* ---------- bar ---------- */
.bar{display:grid;grid-template-columns:auto minmax(0,1fr) auto auto auto;align-items:center;
  gap:.4rem 1rem;padding:.35rem .8rem;background:var(--panel);
  border-bottom:1px solid var(--rule)}
.baraux{display:contents}
.barmore{display:none}
/* ON A PHONE THE HEADER WAS FOUR STACKED ROWS — 186px of an 844px screen, 22% of the
   device, before a single pixel of the drawing the page exists to show. Brand, view menu,
   search and the findings picker each took a full row because each was `grid-column:1/-1`.
   Search and findings are both occasional; the view menu is not. So the occasional two go
   behind one button and the bar returns to a single row. Measured 186px -> 46px. */
@media (max-width:760px){
  .bar{grid-template-columns:minmax(0,1fr) auto auto;padding:.4rem .55rem;gap:.35rem .5rem}
  .bar .tabnav{grid-column:auto;order:0}
  .tabpop{left:0;right:0;min-width:0}
  .brand span{display:none}
  .brand b{font-size:.875rem}
  .baraux{display:none;grid-column:1/-1;order:9;gap:.4rem;
    grid-template-columns:minmax(0,1fr);padding-top:.15rem}
  body.baropen .baraux{display:grid}
  .barmore{display:inline-flex;align-items:center;justify-content:center}
  body.baropen .barmore{background:var(--accent-soft);border-color:var(--accent);
    color:var(--accent)}
  .q,.q:focus{width:100%}
  .find,.issues{grid-column:1/-1}
  /* A 28px control is a miss on a touch screen; the zoom cluster is the only way to
     magnify besides the pinch, so it must not be the harder of the two. */
  .zoombar button{min-width:2.4rem;min-height:2.4rem}
  .zoombar{gap:.15rem}
}
.brand{display:flex;flex-direction:column;line-height:1.15;margin-right:.3rem}
.brand b{font:600 .9375rem/1.2 var(--display);letter-spacing:-.01em}
.brand span{font:500 .625rem/1.4 var(--mono);letter-spacing:.11em;text-transform:uppercase;
  color:var(--ink-faint)}
/* A MENU, NOT A ROW OF TABS. Laid out in a row this clipped three of seven tabs at
   1512px with the scrollbar hidden, so a tab a reader could not see did not exist; laid
   out wrapped it stopped clipping and took a permanent second row of header instead. On
   a page whose subject is a DRAWING, vertical space is the resource being spent, and
   spending it on navigation that is used once per view is the wrong trade. Both measured
   2026-09-04, the second one immediately after shipping the first.

   The buttons keep role=tab and every attribute the script and the suite select them by
   — they are the same tabs, in a panel instead of a row. */
.tabnav{position:relative;min-width:0;justify-self:start}
.tabtrig{appearance:none;display:flex;flex-direction:column;gap:.04rem;justify-content:center;
  max-width:20rem;background:var(--panel-2);border:1px solid var(--rule);border-radius:7px;
  padding:.3rem 1.5rem .3rem .6rem;cursor:pointer;min-height:2.1rem;text-align:left;
  background-image:linear-gradient(45deg,transparent 50%,var(--ink-faint) 50%),
                   linear-gradient(135deg,var(--ink-faint) 50%,transparent 50%);
  background-position:calc(100% - .78rem) 50%,calc(100% - .5rem) 50%;
  background-size:.28rem .28rem,.28rem .28rem;background-repeat:no-repeat}
.tabtrig:hover{border-color:var(--accent)}
.tabtrig[aria-expanded=true]{border-color:var(--accent);background-color:var(--panel)}
.tabtrig b{font:500 .8125rem/1.2 var(--sans);color:var(--ink);white-space:nowrap;
  overflow:hidden;text-overflow:ellipsis}
.tabtrig i{font:400 .6875rem/1.2 var(--sans);font-style:normal;color:var(--ink-faint);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tabpop{position:absolute;top:calc(100% + .3rem);left:0;z-index:60;min-width:16rem;
  display:flex;flex-direction:column;gap:.1rem;padding:.28rem;background:var(--panel);
  border:1px solid var(--rule);border-radius:9px;box-shadow:var(--shadow)}
/* `display:flex` on a class beats the user agent's `[hidden]{display:none}`, so the
   panel stayed painted while every scripted check reported it hidden. The attribute was
   true and the pixels disagreed with it — found by looking at a screenshot, which is the
   only thing that could have found it. */
.tabpop[hidden]{display:none}
[role=tab]{appearance:none;background:transparent;border:1px solid transparent;
  border-radius:7px;padding:.34rem .55rem;cursor:pointer;white-space:nowrap;text-align:left;
  display:flex;flex-direction:column;gap:.04rem;min-height:2.1rem;justify-content:center}
[role=tab] b{font:500 .8125rem/1.2 var(--sans);color:var(--ink-soft)}
[role=tab] i{font:400 .6875rem/1.2 var(--sans);font-style:normal;color:var(--ink-faint)}
[role=tab]:hover{background:var(--panel-2)}
[role=tab]:hover b{color:var(--ink)}
[role=tab][aria-selected=true]{background:var(--accent-soft);border-color:var(--accent)}
[role=tab][aria-selected=true] b{color:var(--accent)}
/* An inside view's tab sits under its parent's (SKILL.md § Inside views). */
[role=tab].sub{margin-left:1.1rem;border-left:2px solid var(--rule)}
[role=tab].sub b::before{content:"↳ ";color:var(--ink-faint)}
.drill{display:block;width:100%;text-align:left;margin:.15rem 0 .9rem;padding:.55rem .7rem;
  border:1px solid var(--accent);border-radius:7px;background:var(--accent-soft);color:var(--accent);
  font:600 .8125rem/1.3 var(--sans);cursor:pointer}
.drill:hover{background:var(--panel-2)}
.drill.up{border-color:var(--rule);background:var(--panel-2);color:var(--ink-soft)}
.find{position:relative;min-width:0}
.q{appearance:none;width:11rem;max-width:100%;background:var(--panel-2);
  border:1px solid var(--rule);border-radius:7px;padding:.42rem .6rem;
  font:400 .8125rem/1 var(--sans);color:var(--ink);min-height:2rem}
.q::placeholder{color:var(--ink-faint)}
.q:focus{width:15rem;border-color:var(--accent);background:var(--panel)}
.hits{position:absolute;top:calc(100% + .3rem);right:0;z-index:40;margin:0;padding:.25rem;
  list-style:none;min-width:16rem;max-height:19rem;overflow-y:auto;background:var(--panel);
  border:1px solid var(--rule);border-radius:9px;box-shadow:var(--shadow)}
.hits li{display:flex;flex-direction:column;gap:.05rem;padding:.4rem .55rem;
  border-radius:6px;cursor:pointer}
.hits li b{font:500 .8125rem/1.3 var(--sans);color:var(--ink)}
.hits li span{font:400 .6875rem/1.3 var(--mono);color:var(--ink-faint)}
.hits li:hover,.hits li.on{background:var(--accent-soft)}
.hits li:hover b,.hits li.on b{color:var(--accent)}
@media (max-width:760px){.find{grid-column:1/-1;order:3}.q,.q:focus{width:100%}}

/* THE FINDINGS PICKER. A native <select> on purpose: it is the one control that is
   keyboard-navigable, type-ahead searchable and correctly sized on a phone without a
   line of script, and a list of nineteen findings is exactly what it was designed for. */
/* THE BRIEF. The page still never scrolls — this plate does, inside itself, exactly as the
   inspector panel does. The column is capped at a reading measure because a 1920px-wide
   paragraph is not prose, it is a wall, and the whole point of this tab is that somebody
   reads it. */
.plate.brief.on{display:block;overflow-y:auto;overscroll-behavior:contain;padding:0}
.prose{max-width:46rem;margin:0 auto;padding:2rem 1.5rem 4rem;color:var(--ink)}
/* USING THE WIDTH WITHOUT LENGTHENING THE LINE. At 46rem a document leaves about a
   third of a 1512px stage empty, which reads as a narrow column of text in a wide
   frame. Simply widening the measure is the obvious fix and the wrong one: 64rem is
   roughly 128 characters a line, well past where the eye loses its place returning to
   the left margin. So the extra width goes to a SIDE HEADING instead — the heading and
   its reference sit in their own column, the body keeps a readable measure beside it,
   and the headings become a column somebody can scan down without reading the prose. */
@media (min-width:1100px){
  .prose{max-width:68rem}
  .prose .item{display:grid;grid-template-columns:15rem minmax(0,40rem);gap:.2rem 2rem}
  .prose .item h3{grid-column:1;grid-row:1;margin:0}
  .prose .item .p{grid-column:2;grid-row:1}
  .prose .item .tofind{grid-column:2;grid-row:2;justify-self:start;margin-top:.35rem}
  /* A side heading wraps in a narrow column, so the number must not be swallowed by
     the first word — it stays on its own line above the text it numbers. */
  .prose .item h3 .itemn{display:block;margin:0 0 .1rem}
  .prose .item h3 .itemf{margin-left:0;display:inline-block;margin-top:.25rem}
}
.prose h1{font:600 1.5rem/1.25 var(--serif,var(--sans));letter-spacing:-.015em;margin:0 0 .5rem}
.prose .stand{font-size:1rem;line-height:1.6;color:var(--ink-soft);margin:0 0 1.75rem}
.prose h2{font:600 1.05rem/1.3 var(--sans);letter-spacing:-.01em;margin:2.25rem 0 .3rem;
  padding-bottom:.35rem;border-bottom:1px solid var(--rule)}
.prose h2.t-good{color:var(--good,#1c6b45);border-color:var(--good,#1c6b45)}
.prose h2.t-bad{color:var(--accent);border-color:var(--accent)}
.prose .intro{font-size:.875rem;line-height:1.6;color:var(--ink-soft);margin:.5rem 0 1rem}
.prose p{font-size:.9375rem;line-height:1.65;margin:.5rem 0}
.prose ul{margin:.5rem 0;padding-left:1.1rem}
.prose li{font-size:.9375rem;line-height:1.6;margin:.3rem 0}
.prose code{font:500 .86em/1.4 var(--mono);background:var(--panel-2);padding:.1em .32em;border-radius:4px}
.prose pre{font:400 .78rem/1.6 var(--mono);background:var(--panel-2);border:1px solid var(--rule);
  border-radius:8px;padding:.7rem .85rem;overflow-x:auto;margin:.6rem 0}
.prose table{border-collapse:collapse;width:100%;margin:.75rem 0;font-size:.875rem}
.prose th,.prose td{text-align:left;padding:.42rem .6rem;border-bottom:1px solid var(--rule-soft);
  vertical-align:top}
.prose th{font:600 .68rem/1.4 var(--mono);text-transform:uppercase;letter-spacing:.06em;
  color:var(--ink-faint)}
.prose .item{margin:1rem 0;padding-left:.85rem;border-left:2px solid var(--rule)}
.prose .item.t-good{border-left-color:var(--good,#1c6b45)}
.prose .item.t-bad{border-left-color:var(--accent)}
.prose .item.t-open{border-left-color:var(--ink-faint);border-left-style:dashed}
.prose .item h3{font:600 .9375rem/1.4 var(--sans);margin:0 0 .15rem;color:var(--ink)}
/* NUMBERS SO THE DOCUMENT CAN BE CITED OUT LOUD. An audit is argued about in a room where
   nobody is on the same screen, and "4.2" survives that conversation while "the bit about
   the join" does not. Monospaced and dimmed: a reference mark the eye can skip when it is
   reading and find instantly when it is looking. */
.secn{font:500 .75rem/1 var(--mono);color:var(--ink-faint);margin-right:.5rem;
  letter-spacing:.02em}
.itemn{font:500 .6875rem/1 var(--mono);color:var(--ink-faint);margin-right:.45rem}
/* The finding id is a reference to ANOTHER surface — the drawings — so it reads as a tag
   rather than as part of the sentence. */
.itemf{margin-left:.45rem;font:500 .625rem/1.5 var(--mono);color:var(--accent);
  background:var(--accent-soft);border-radius:4px;padding:.05rem .3rem;
  vertical-align:.05em;white-space:nowrap}
.prose .item .p{font-size:.9375rem;line-height:1.65;color:var(--ink-soft)}
.prose .item .p b{color:var(--ink)}
.tofind{appearance:none;margin-top:.5rem;background:var(--accent-soft);color:var(--accent);
  border:1px solid transparent;border-radius:6px;padding:.32rem .55rem;cursor:pointer;
  font:500 .75rem/1 var(--sans)}
.tofind:hover{border-color:var(--accent)}
@media (max-width:760px){.prose{padding:1.25rem 1rem 3rem}}

.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.issues{display:flex;gap:.3rem;align-items:center;min-width:0}
.issues[hidden]{display:none}
.fsel{appearance:none;max-width:17rem;background:var(--panel-2);color:var(--ink);
  border:1px solid var(--rule);border-radius:7px;padding:.42rem 1.4rem .42rem .6rem;
  font:400 .8125rem/1 var(--sans);min-height:2rem;cursor:pointer;
  background-image:linear-gradient(45deg,transparent 50%,var(--ink-faint) 50%),
                   linear-gradient(135deg,var(--ink-faint) 50%,transparent 50%);
  background-position:calc(100% - .78rem) 50%,calc(100% - .5rem) 50%;
  background-size:.28rem .28rem,.28rem .28rem;background-repeat:no-repeat}
.fsel:focus{border-color:var(--accent);background-color:var(--panel)}
.fclear{appearance:none;background:var(--accent-soft);color:var(--accent);
  border:1px solid var(--accent);border-radius:7px;padding:.4rem .5rem;cursor:pointer;
  font:500 .75rem/1 var(--mono);min-height:2rem}
@media (max-width:1100px){.fsel{max-width:9rem}}
@media (max-width:760px){.issues{grid-column:1/-1;order:4}.fsel{max-width:100%;flex:1}}

/* A finding's panel. The path buttons are the point: naming the boxes and the arrows it
   runs through is what turns "there is a problem" into "it is HERE". */
.fnd-sev{display:inline-block;font:600 .625rem/1 var(--mono);letter-spacing:.09em;
  text-transform:uppercase;padding:.28rem .45rem;border-radius:5px;margin-bottom:.5rem}
.fnd-sev.critical{background:var(--accent-soft);color:var(--accent)}
.fnd-sev.high{background:var(--panel-2);color:var(--ink)}
.fnd-sev.medium,.fnd-sev.low{background:var(--panel-2);color:var(--ink-soft)}
/* Confidence, beside severity. `lead` is outlined rather than filled so it reads as an
   asterisk on the claim next to it, not as a second severity competing with the first. */
.fnd-st{display:inline-block;font:500 .625rem/1 var(--mono);letter-spacing:.09em;
  text-transform:uppercase;padding:.28rem .45rem;border-radius:5px;margin:0 0 .5rem .3rem;
  border:1px solid var(--rule);color:var(--ink-faint);cursor:help}
.fnd-st.st-lead{border-color:var(--gate);color:var(--gate);font-weight:600}
.fnd-st.st-confirmed{border-color:var(--good);color:var(--good)}
.path{display:flex;flex-wrap:wrap;gap:.28rem;margin:.15rem 0 .1rem}
.path button{appearance:none;background:var(--panel-2);border:1px solid var(--rule);
  border-radius:6px;padding:.28rem .45rem;cursor:pointer;
  font:400 .75rem/1.2 var(--sans);color:var(--ink)}
.path button:hover{border-color:var(--accent);color:var(--accent)}
.path button.edge{font-family:var(--mono);font-size:.6875rem;color:var(--ink-soft)}

.tools{display:flex;gap:.3rem;align-items:center}
.panner{appearance:none;background:var(--panel-2);border:1px solid var(--rule);
  border-radius:7px;padding:.4rem .55rem;cursor:pointer;font:500 .8125rem/1 var(--mono);
  color:var(--ink-soft)}
.panner:hover{color:var(--ink);border-color:var(--ink-faint)}
.panner[aria-pressed=true]{background:var(--accent-soft);border-color:var(--accent);
  color:var(--accent)}
@media (max-width:960px){.panner{display:none}}
/* Floating over the drawing, bottom-right, the way every canvas tool puts them. It is a
   sibling of .canvas rather than a child, so panning never has to be suppressed here. */
.zoombar{position:absolute;right:1rem;bottom:1rem;z-index:5;display:flex;align-items:stretch;
  border:1px solid var(--rule);border-radius:8px;overflow:hidden;
  background:color-mix(in srgb, var(--panel) 88%, transparent);
  backdrop-filter:blur(6px);box-shadow:var(--shadow)}
.zoombar button{appearance:none;background:transparent;border:0;cursor:pointer;
  padding:.42rem .62rem;min-width:2.1rem;min-height:2.1rem;
  font:500 .9375rem/1 var(--mono);color:var(--ink-soft)}
.zoombar button:hover{background:var(--rule-soft);color:var(--ink)}
/* On a phone the inspector is a bottom sheet whose collapsed handle is 2.9rem tall and
   sits above this. Measured: the bar landed at y=792 with the sheet starting at y=798, so
   elementFromPoint returned the sheet and the zoom controls could not be touched at all.
   Clear the handle. Once the sheet is opened it covers the bar, which is correct — the
   reader is in the panel then, not on the canvas. */
@media (max-width:960px){
  .zoombar{bottom:calc(2.9rem + .55rem);right:.55rem}
  body:has(.inspect.open) .zoombar{opacity:0;pointer-events:none}
}
.level{display:flex;align-items:center;padding:0 .5rem;min-width:3.4rem;
  justify-content:center;font:500 .6875rem/1 var(--mono);color:var(--ink-faint);
  border-left:1px solid var(--rule);border-right:1px solid var(--rule);
  font-variant-numeric:tabular-nums}
.themer{appearance:none;background:var(--panel-2);border:1px solid var(--rule);
  border-radius:7px;padding:.4rem .55rem;cursor:pointer;font:500 .75rem/1 var(--mono);
  color:var(--ink-soft);min-width:2.9rem}
.themer:hover{color:var(--ink);border-color:var(--ink-faint)}

/* ---------- stage ---------- */
main{display:grid;grid-template-columns:minmax(0,1fr) min(33rem,40vw);min-height:0}
body.nopanel main{grid-template-columns:minmax(0,1fr)}
body.nopanel .inspect{display:none}
/* A document tab has nothing to put in the inspector, and an empty panel
   beside a column of prose is the width the prose was missing. */
body.docview main{grid-template-columns:minmax(0,1fr)}
body.docview .inspect{display:none}
@media (max-width:960px){main{grid-template-columns:minmax(0,1fr)}}
.stage{position:relative;min-width:0;min-height:0;background:var(--sink);
  display:grid;place-items:stretch}
.plate{display:none;position:relative;min-width:0;min-height:0;padding:.35rem}
.plate.on{display:grid;grid-template-rows:minmax(0,1fr)}
.canvas{min-height:0;display:grid;place-items:center;
  background:var(--panel);border:1px solid var(--rule);border-radius:10px}
/* The drawing always fills its canvas; what changes is the viewBox, driven by the
   navigation. `overflow:hidden` because panning replaces scrolling — a scrollbar and a
   drag competing for the same gesture is how a canvas feels broken. */
.canvas{overflow:hidden;cursor:grab;touch-action:none}
.canvas.grabbing{cursor:grabbing}
.canvas svg{display:block;width:100%;height:100%;max-height:100%}

/* interactive nodes: they must look operable */
.canvas [data-node-id],.canvas [data-edge-id].hit{cursor:pointer}
.canvas [data-edge-id].hit path,.canvas [data-edge-id].hit line{stroke-linecap:round}
.canvas [data-edge-id].hit:hover{filter:brightness(1.25)}
.canvas [data-node-id] *{transition:opacity .13s ease}
.canvas [data-node-id]:hover{filter:brightness(1.06)}
/* The dim level is a TOKEN, and the theme only ever changes the token. Written as three
   themed rule-sets instead, the dark one — `:root[data-theme=dark] .canvas[data-focus]
   [data-node-id]`, specificity (0,5,0) — outranks the highlight rule
   `.canvas[data-focus] [data-node-id].lit` at (0,4,0), so the SELECTED node was dimmed
   along with everything else and nothing appeared highlighted at all. In dark mode only,
   which is why every check passed. One element rule per state cannot lose that race. */
.canvas[data-focus]{--dim:.34}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) .canvas[data-focus]{--dim:.44}}
:root[data-theme="dark"] .canvas[data-focus]{--dim:.44}
.canvas[data-focus] [data-node-id],
.canvas[data-focus] [data-edge-id]{opacity:var(--dim)}
.canvas[data-focus] [data-node-id].lit,
.canvas[data-focus] [data-edge-id].lit{opacity:1}
.canvas[data-focus] [data-node-id].lit{filter:drop-shadow(0 0 3px var(--accent))}
.canvas[data-focus] [data-edge-id].lit{filter:drop-shadow(0 0 2px var(--accent))}

/* ---------- inspector ---------- */
.inspect{border-left:1px solid var(--rule);background:var(--panel);
  display:flex;flex-direction:column;min-height:0}
@media (max-width:960px){
  .inspect{position:fixed;inset:auto 0 0 0;max-height:62dvh;border-left:0;
    border-top:1px solid var(--rule);border-radius:12px 12px 0 0;box-shadow:var(--shadow);
    transform:translateY(calc(100% - 2.9rem));transition:transform .2s ease;z-index:10}
  .inspect.open{transform:translateY(0)}
  .ins-head{cursor:pointer}
}
.ins-head{display:flex;align-items:flex-start;gap:.6rem;padding:.7rem .85rem;
  border-bottom:1px solid var(--rule-soft);background:var(--panel-2);min-height:2.9rem}
.ins-head .t{flex:1;min-width:0}
.ins-head h2{margin:0;font:600 .9375rem/1.25 var(--sans);overflow-wrap:anywhere}
.ins-head p{margin:.1rem 0 0;font:400 .6875rem/1.4 var(--mono);color:var(--ink-faint);
  overflow-wrap:anywhere}
.x{appearance:none;background:transparent;border:1px solid var(--rule);border-radius:6px;
  width:1.7rem;height:1.7rem;flex:none;cursor:pointer;color:var(--ink-faint);
  font:400 .95rem/1 var(--sans);display:none;align-items:center;justify-content:center}
.x:hover{color:var(--ink);border-color:var(--ink-faint)}
.inspect.node .x{display:flex}
.ins-body{overflow-y:auto;padding:.85rem;flex:1;min-height:0}

.kind{display:inline-block;font:500 .625rem/1 var(--mono);letter-spacing:.09em;
  text-transform:uppercase;color:var(--accent);background:var(--accent-soft);
  border-radius:99px;padding:.28rem .5rem;margin:0 0 .6rem}
.role{margin:0 0 .85rem;font-size:.9375rem;line-height:1.5;color:var(--ink)}

.facts{margin:0 0 .95rem;display:grid;grid-template-columns:auto 1fr;
  gap:.32rem .7rem;font-size:.8125rem}
.facts dt{font:500 .625rem/1.7 var(--mono);letter-spacing:.07em;text-transform:uppercase;
  color:var(--ink-faint);white-space:nowrap}
.facts dd{margin:0;color:var(--ink-soft);line-height:1.5;overflow-wrap:anywhere}

.sec{font:500 .625rem/1 var(--mono);letter-spacing:.09em;text-transform:uppercase;
  color:var(--ink-faint);margin:0 0 .45rem;padding-top:.75rem;
  border-top:1px solid var(--rule-soft);display:flex;justify-content:space-between}
.wires{list-style:none;margin:0 0 .3rem;padding:0}
.wires li{display:grid;grid-template-columns:.95rem 1fr;gap:.4rem;align-items:baseline;
  padding:.24rem 0;font-size:.8125rem;line-height:1.45}
.wires .d{font:500 .8125rem/1.4 var(--mono);text-align:center}
.wires .d.out{color:var(--flow)}
.wires .d.in{color:var(--ink-faint)}
.wires .peer{display:block;font:500 .75rem/1.4 var(--mono);color:var(--ink);
  overflow-wrap:anywhere}
.wires .cargo{display:block;color:var(--ink-faint);overflow-wrap:anywhere}
.wires .cols{display:inline-block;margin-top:.15rem;padding:.05rem .3rem;border-radius:.6rem;
  background:var(--chip,rgba(127,127,127,.14));color:var(--ink-faint);
  font:600 .625rem/1.5 var(--mono);letter-spacing:.03em;text-transform:uppercase}
.wires li.hot{cursor:pointer}
.wires li.hot:hover .peer{color:var(--flow)}
/* THE DATA LAYER. A name/type/meaning grid, not prose: the reader is scanning for a
   column, so the identifier column is monospace, fixed-left and never wraps mid-token,
   and the meaning takes whatever width is left. */
table.fields{width:100%;border-collapse:collapse;font-size:.75rem;table-layout:auto}
table.fields td{padding:.2rem .45rem .2rem 0;vertical-align:top;
  border-bottom:1px solid var(--rule,rgba(127,127,127,.16))}
table.fields tr:last-child td{border-bottom:0}
table.fields .fname{white-space:nowrap;width:1%}
table.fields .fname code{font:600 .6875rem/1.5 var(--mono);color:var(--ink);
  background:var(--chip,rgba(127,127,127,.14));padding:.05rem .3rem;border-radius:.25rem}
table.fields .ftype{white-space:nowrap;width:1%;color:var(--flow);
  font:500 .6875rem/1.5 var(--mono)}
table.fields .fnote{color:var(--ink-faint);line-height:1.45}

/* The exposure grid. Same skeleton as .fields on purpose — a reader who has learnt one
   three-column block has learnt both. The state is the only part that carries colour,
   because it is the only part worth scanning without reading: `visible` is filled so it
   is found first, `silent` is outlined in the same warning hue because a zero somebody
   believed is the quieter half of the same defect, and `clean` is the control. */
table.expo{width:100%;border-collapse:collapse;font-size:.75rem;table-layout:auto}
table.expo td{padding:.24rem .45rem .24rem 0;vertical-align:top;
  border-bottom:1px solid var(--rule,rgba(127,127,127,.16))}
table.expo tr:last-child td{border-bottom:0}
table.expo .xsurf{color:var(--ink);font-weight:500;line-height:1.45}
table.expo .xstate{white-space:nowrap;width:1%}
table.expo .xnote{color:var(--ink-faint);line-height:1.45}
.xbadge{display:inline-block;font:600 .5625rem/1 var(--mono);letter-spacing:.08em;
  text-transform:uppercase;padding:.26rem .4rem;border-radius:5px;
  border:1px solid var(--rule);color:var(--ink-faint)}
.xbadge.x-visible{background:var(--gate,#a8412a);border-color:var(--gate,#a8412a);color:#fff}
.xbadge.x-silent{border-color:var(--gate,#a8412a);color:var(--gate,#a8412a)}
.xbadge.x-absent{border-style:dashed;color:var(--ink-faint)}
.xbadge.x-clean{border-color:var(--good);color:var(--good)}
.xbadge.x-unknown{border-style:dotted;color:var(--ink-faint)}

details{border-top:1px solid var(--rule-soft);padding:.55rem 0 .1rem}
details summary{cursor:pointer;list-style:none;display:flex;align-items:center;gap:.4rem;
  font:500 .625rem/1 var(--mono);letter-spacing:.09em;text-transform:uppercase;
  color:var(--ink-faint);padding:.15rem 0}
details summary::-webkit-details-marker{display:none}
details summary::before{content:"+";font:500 .8125rem/1 var(--mono);color:var(--accent);
  width:.7rem}
details[open] summary::before{content:"–"}
details summary:hover{color:var(--ink)}
details .in{padding:.45rem 0 .5rem 1.1rem;font-size:.8125rem;line-height:1.55;
  color:var(--ink-soft)}
details .in ul{margin:0;padding-left:1rem}
details .in li{margin:.3rem 0}
.files{list-style:none;padding:0!important}
.files li{margin:.22rem 0}
.files a,.files code{font:400 .75rem/1.5 var(--mono);overflow-wrap:anywhere}
.files a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent}
.files a:hover{border-bottom-color:var(--accent)}
.files code{color:var(--ink-soft);background:var(--panel-2);padding:.08em .3em;border-radius:3px}

/* Evidence, as a table. Figures are tabular-nums and right-aligned so a column of money
   compares by eye — the whole reason for preferring a table to a sentence. */
table.ev{border-collapse:collapse;width:100%;font-size:.75rem;margin:.1rem 0 .3rem}
table.ev th{font:500 .5938rem/1.6 var(--mono);letter-spacing:.06em;text-transform:uppercase;
  color:var(--ink-faint);text-align:left;padding:.2rem .45rem .3rem 0;
  border-bottom:1px solid var(--rule)}
/* padding-right:0 flushes a money column to the panel edge, which is right for ONE
   column of figures and wrong for several: three adjacent yes/no columns rendered as
   `yesyesyes`, and the column after them as `yesours, in the container`. The gap has to
   sit on EVERY cell that follows another, not only the numeric ones — a prose column
   next to a figure column collides just as hard and is harder to notice, because it
   still reads as words. */
table.ev td:not(:first-child),table.ev th:not(:first-child){padding-left:.55rem}
table.ev th:not(:first-child),table.ev td.num{text-align:right;padding-right:0}
table.ev td{padding:.28rem .45rem .28rem 0;border-bottom:1px solid var(--rule-soft);
  color:var(--ink-soft);line-height:1.45;vertical-align:top}
table.ev td.num{font-variant-numeric:tabular-nums;font-family:var(--mono);font-size:.7188rem;
  white-space:nowrap}
table.ev tr:last-child td{border-bottom:0}
table.ev tr.mark-total td{color:var(--ink);font-weight:600;border-top:1px solid var(--rule)}
table.ev tr.mark-control td{color:var(--ok, var(--ink-soft))}
table.ev tr.mark-bad td:first-child{color:var(--ink);font-weight:500}
/* A figures table inside the brief. Same reasoning as table.ev: a column of money
   is compared by eye, so it is tabular-nums and right-aligned. */
.prose table.bev{font-size:.8125rem;margin:.7rem 0}
.prose table.bev th{font:600 .6875rem/1.5 var(--mono);letter-spacing:.04em;
  text-transform:uppercase;color:var(--ink-faint);text-align:left;padding:.25rem .6rem .3rem 0;
  border-bottom:1px solid var(--rule)}
.prose table.bev th:not(:first-child),.prose table.bev td:not(:first-child){text-align:right}
.prose table.bev td{padding:.3rem .6rem .3rem 0;border-bottom:1px solid var(--rule-soft);
  color:var(--ink-soft)}
.prose table.bev td:not(:first-child){font-variant-numeric:tabular-nums;
  font-family:var(--mono);font-size:.75rem;white-space:nowrap}
.prose table.bev tr.bad td:first-child{color:var(--ink);font-weight:600}
p.evnote{margin:.4rem 0 0;font-size:.7188rem;line-height:1.5;color:var(--ink-faint)}

/* Where to go and look. The note is the access condition, and it is deliberately quiet
   next to the link — a reader scans the labels and reads the note only when blocked. */
.opens{list-style:none;padding:0!important}
.opens li{margin:.34rem 0;line-height:1.45}
.opens a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent;
  font-size:.75rem}
.opens a:hover{border-bottom-color:var(--accent)}
.opens .nolink{font-size:.75rem;color:var(--ink)}
.opens .onote{display:block;font-size:.6875rem;color:var(--ink-faint);margin-top:.05rem}

/* The join keys. Monospace on the value because every one of these IS a column name. */
.keys{margin:0;display:grid;grid-template-columns:auto 1fr;gap:.3rem .7rem}
.keys dt{font:500 .625rem/1.7 var(--mono);letter-spacing:.06em;text-transform:uppercase;
  color:var(--ink-faint);white-space:nowrap}
.keys dd{margin:0;font-family:var(--mono);font-size:.7188rem;line-height:1.5;
  color:var(--ink-soft);overflow-wrap:anywhere}

.views{list-style:none;margin:0;padding:0}
.views li{padding:.5rem 0;border-bottom:1px solid var(--rule-soft)}
.views li:last-child{border-bottom:0}
.views b{display:block;font:500 .8125rem/1.35 var(--sans);color:var(--ink);
  margin-bottom:.12rem}
.views p{margin:0 0 .28rem;font-size:.8125rem;line-height:1.5;color:var(--ink-soft)}
.who{display:flex;flex-wrap:wrap;gap:.22rem}
.who button{appearance:none;background:var(--panel-2);border:1px solid var(--rule);
  border-radius:99px;padding:.24rem .5rem;cursor:pointer;min-height:1.6rem;
  font:400 .6875rem/1.4 var(--mono);color:var(--ink-soft)}
.who button:hover{color:var(--accent);border-color:var(--accent);background:var(--accent-soft)}

/* Motion here is feedback, never information: a dimming fade and the phone sheet's
   slide. Both go when the reader has asked for less. */
@media (prefers-reduced-motion:reduce){
  *,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;
    transition-duration:.01ms!important;scroll-behavior:auto!important}
}
"""
