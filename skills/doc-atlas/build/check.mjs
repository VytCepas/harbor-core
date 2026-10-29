// check.js — the atlas's own acceptance suite, run against a real browser.
//
//   node check.mjs <url>           # e.g. http://127.0.0.1:8797/estate.html
//
// It is .mjs and imports rather than requires, because the probe directory that
// carries playwright declares "type": "module" — a .js there is an ES module and
// `require` is not defined in it.
//
// WHY THIS EXISTS AS A BROWSER RUN AND NOT A UNIT TEST. Every defect this page has
// shipped was invisible to static inspection and to synthetic events:
//
//   * setPointerCapture on pointerdown redirected the click to the canvas, so all 30
//     nodes were dead while dispatching a click straight onto a node still "passed";
//   * `data-edge-id` sits on a <g> in a sequence diagram and on the <path> ITSELF in an
//     architecture one, so a descendant query silently found nothing for half of them;
//   * four inlined archify documents collided on `id="arrowhead"`, and a <marker> inside
//     display:none paints nothing, so every tab after the first lost its arrowheads.
//
// None of those is visible without layout, hit testing and a real event path. So the
// suite drives the page the way a person does — elementFromPoint, then the full pointer
// sequence at that coordinate — and never dispatches an event onto the element it is
// testing. That distinction is the whole point: a check that aims at the target cannot
// discover that the target is unreachable.
//
// Exit 0 all green, 1 on any failure. Prints one line per check.

// IMPORTED DYNAMICALLY so that an unresolvable playwright is a DEFERRAL and not a
// verdict. A static `import` fails before any of this file's code runs, and node exits
// 1 — which is this suite's "measured, found problems" code, so build.py printed a raw
// ERR_MODULE_NOT_FOUND trace and its caller read it as a FAILING page. Measured
// 2026-09-05 on an empty HOME: SCENARIO_A_EXIT=1. Missing node was already handled
// (build.py catches FileNotFoundError and returns 127); missing playwright was not, and
// it is the likelier of the two on any box that is not this one, because the probe
// directory is hard-coded.
//
// 2 is what contracts/gates.md prescribes for a verifier that could not run. The 127 for
// a missing node predates that contract and still stands; both mean deferral, and the
// docs now say so. Anything else here is a real verdict.
let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch (err) {
  console.error('NOT CHECKED — playwright is not resolvable from this file\'s directory. '
    + 'This is a deferral, not a pass. Install it beside check.mjs, or in the probe '
    + 'directory build.py copies this file to.');
  console.error(String(err && err.message ? err.message : err));
  process.exit(2);
}

const AA_NORMAL = 4.5;   // WCAG 2.1 AA, body text
const AA_LARGE = 3.0;    // >= 24px, or >= 18.66px bold
const MIN_TARGET = 24;   // hard floor; 44 is the recommendation

// THE TAB STRIP IS BEHIND A POPOVER, and it closes again after every selection.
// build.py emits the tabs inside `<nav class="tabpop" … hidden>`, atlas_css.py hides that
// with `display:none`, and atlas.js opens it only on a `.tabtrig` click — then its
// select() calls menu(false) on the way out. So every Playwright click on a tab has to
// reveal the strip first. The in-page `.click()` calls further down are unaffected, which
// is exactly why half this suite kept working while the other half went blind.
//
// Measured 2026-09-05: without this the suite timed out 30s on the FIRST tab and exited 2
// with NO VERDICT LINE AT ALL, on every atlas today's build produces — including a
// one-diagram atlas with no brief and no findings. It had been blind since the popover
// landed on 2026-09-04, and nothing caught it because nothing runs this file.
//
// Silent on the older shell BY DESIGN: an atlas built before the popover has a permanently
// visible strip and no `.tabtrig`, and has to keep passing. That is the valid-but-unusual
// input this reveal must not break.
async function revealTabs(page) {
  const pop = await page.$('.tabpop');
  if (!pop || !(await pop.isHidden())) return;
  const trig = await page.$('.tabtrig');
  if (!trig) return;
  await trig.click();
}

async function main() {
  const url = process.argv[2];
  if (!url) {
    console.error('usage: node check.js <url>');
    process.exit(2);
  }
  // The bundled headless shell is not downloaded on this box; the installed Chrome is,
  // and it is also closer to what a reader will actually open.
  const browser = await chromium.launch({ channel: 'chrome' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  // A PAGE-WIDE TIMEOUT. Playwright's default is 30s, and the edge loop below tries up to
  // six points per edge before giving up on it. Measured 2026-09-05: one unreachable edge
  // point cost 30,003 ms, so 48 edges could take hours to report a total failure — the
  // precise outcome the comment above the node cap says must never happen. Navigation
  // keeps the long default; it is the only call here that legitimately waits on a network.
  page.setDefaultTimeout(5000);
  page.setDefaultNavigationTimeout(30000);

  // A page served from a bare http.server has no favicon; that 404 is the harness, not
  // the page. Filter on the failing URL, because the console TEXT is a generic
  // "Failed to load resource" that names nothing.
  const consoleErrors = [];
  page.on('console', m => {
    if (m.type() !== 'error') return;
    const from = (m.location() && m.location().url) || '';
    if (/favicon\.ico$/.test(from)) return;
    consoleErrors.push(m.text() + (from ? ` @ ${from}` : ''));
  });
  page.on('pageerror', e => consoleErrors.push('uncaught: ' + e.message));

  await page.goto(url, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);


  // ── clicking, with the REAL mouse ────────────────────────────────────────────────
  // This has to be driven from Node. An in-page `dispatchEvent` sequence cannot
  // reproduce pointer capture — `setPointerCapture` on a synthetic pointer throws, the
  // catch swallows it, and the click is never redirected. That is exactly the bug that
  // killed every node on the page, and a synthetic suite scored it PASS. Measured: with
  // capture-on-pointerdown replanted, dispatched events said green and the real mouse
  // said red. So: hit-test in the page, click from out here.
  //
  // edgeSkipped is SEPARATE from edgeFail. Once a cap trips, the remaining edges are never
  // clicked, and counting an unattempted edge as unreachable makes the report state a
  // measurement it did not take — `edges reachable: 0/48` when zero were attempted.
  const clickReport = { nodes: 0, nodeTotal: 0, nodeFail: [], edges: 0, edgeTotal: 0, edgeFail: [], edgeSkipped: [] };

  const tabNames = await page.$$eval('[role=tab]', ts => ts.map(t => t.dataset.name));
  for (const tab of tabNames) {
    await revealTabs(page);
    await page.click(`[role=tab][data-name="${tab}"]`);
    // A TAB IS NOT ALWAYS A DRAWING. The brief is a plate with no canvas, and the edge
    // hit-testing below reaches into __ATLAS__.diagrams[name] — which for the brief is
    // undefined and throws inside page.evaluate, failing the whole suite on a tab that has
    // nothing to click.
    if (!(await page.evaluate((n) => !!window.__ATLAS__.diagrams[n], tab))) continue;

    const nodeTargets = await page.evaluate(() =>
      [...document.querySelectorAll('.plate.on .canvas [data-node-id]')].map(n => {
        const r = n.getBoundingClientRect();
        return { id: n.getAttribute('data-node-id'),
                 x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
      }));
    clickReport.nodeTotal += nodeTargets.length;
    for (const t of nodeTargets) {
      // A suite that takes five minutes to report a total failure does not get run. Once
      // a whole tab's nodes are dead the cause is structural, never per-node.
      if (clickReport.nodeFail.length > 6) break;
      await page.mouse.click(t.x, t.y);
      const got = await page.textContent('.ins-head h2');
      const want = await page.evaluate(([n, i]) => window.__ATLAS__.diagrams[n].nodes[i].label, [tab, t.id]);
      if (got === want) clickReport.nodes++;
      else clickReport.nodeFail.push(`${tab}/${t.id} -> "${got}"`);
    }

    // Points ON each edge: the midpoint of its hit twin, with fallbacks along the line and
    // finally its label, because parallel edges overlap and the label is then the target.
    const edgeTargets = await page.evaluate(() => {
      const name = document.querySelector('.plate.on').dataset.name;
      const c = document.querySelector('.plate.on .canvas');
      return window.__ATLAS__.diagrams[name].wires.map(w => {
        const pts = [];
        const seg = c.querySelector(`[data-edge-id="${w.id}"] [data-hit-twin], [data-edge-id="${w.id}"][data-hit-twin]`);
        if (seg && seg.getTotalLength) {
          const L = seg.getTotalLength(), m = seg.getScreenCTM();
          if (m) for (const f of [0.5, 0.35, 0.65, 0.2, 0.8]) {
            const p = seg.getPointAtLength(L * f);
            pts.push({ x: Math.round(p.x * m.a + p.y * m.c + m.e), y: Math.round(p.x * m.b + p.y * m.d + m.f) });
          }
        }
        const lab = c.querySelector(`g[data-edge-id="${w.id}"]`);
        if (lab) { const r = lab.getBoundingClientRect();
          pts.push({ x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) }); }
        return { id: w.id, pts };
      });
    });
    for (const e of edgeTargets) {
      clickReport.edgeTotal++;
      // CAPPED ON BOTH COUNTS, not just the node one. Once a tab's nodes are dead the cause
      // is structural — and once seven edges have missed, so is that. Before this cap the
      // edge loop was the only unbounded cost in the suite: six points x 30s x every
      // remaining edge. The node loop has had a cap since it was written; this is the same
      // reasoning applied to the path that is two orders of magnitude more expensive.
      if (clickReport.nodeFail.length > 6 || clickReport.edgeFail.length > 6) {
        clickReport.edgeSkipped.push(`${tab}/${e.id}`); continue; }
      let ok = false;
      for (const p of e.pts) {
        if (p.x < 0 || p.y < 0 || p.x > 1440 || p.y > 900) continue;
        await page.mouse.click(p.x, p.y);
        // A SHORT, EXPLICIT timeout: the panel is rebuilt synchronously by the click
        // handler, so anything beyond a few hundred ms is a miss, not a slow hit. The
        // page-wide 5s default is the backstop for everything else; here it would still
        // be 30x more patience than the assertion can use.
        if ((await page.textContent('.ins-body .kind', { timeout: 400 }).catch(() => '')) === 'Connection') { ok = true; break; }
      }
      if (ok) clickReport.edges++; else clickReport.edgeFail.push(`${tab}/${e.id}`);
    }
  }

  // ── the brief must reach the drawing ─────────────────────────────────────────────
  // SELECTED BY data-name, NOT BY CLASS. The diagnostics plate reuses `.plate.brief` for
  // its prose styling, so a class selector now matches two plates and the first one it
  // finds is a DOM-order accident. Narrowed 2026-09-04, when that second plate was added.
  // The brief earns its tab only because an explanation is one click from the path it is
  // about. If those buttons do not switch the tab and light the finding, this is a second
  // document sharing a file with the first, which is the thing this skill refuses to build.
  const briefReport = { total: 0, ok: 0, fail: [] };
  const hasBrief = await page.evaluate(() => !!document.querySelector('.plate[data-name="brief"]'));
  if (hasBrief) {
    await revealTabs(page);
    await page.click('[role=tab][data-name="brief"]');
    const noCanvas = await page.evaluate(() =>
      !document.querySelector('.plate[data-name="brief"] .canvas') &&
      document.querySelector('.plate[data-name="brief"]').classList.contains('on'));
    if (!noCanvas) briefReport.fail.push('the brief plate did not open, or carries a canvas');
    // The page itself must still not scroll — the plate does.
    const pageScrolls = await page.evaluate(() =>
      document.documentElement.scrollHeight > window.innerHeight + 2);
    if (pageScrolls) briefReport.fail.push('the brief makes the PAGE scroll, not the plate');
    const wants = await page.$$eval('.plate[data-name="brief"] .tofind',
      bs => bs.map(b => b.getAttribute('data-finding')));
    for (const want of wants) {
      briefReport.total++;
      await revealTabs(page);
      await page.click('[role=tab][data-name="brief"]');
      await page.click(`.plate[data-name="brief"] .tofind[data-finding="${want}"]`);
      const v = await page.evaluate((wid) => {
        const f = (window.__ATLAS__.findings || []).find(x => x.id === wid);
        if (!f) return 'no such finding';
        const plate = document.querySelector('.plate.on');
        if (!plate || plate.dataset.name !== f.diagram) return 'stayed on ' + (plate && plate.dataset.name);
        const c = plate.querySelector('.canvas');
        if (!c.hasAttribute('data-focus')) return 'nothing lit';
        const head = document.querySelector('.ins-head h2').textContent || '';
        return head.indexOf(f.id) < 0 ? 'panel reads "' + head + '"' : null;
      }, want);
      if (v === null) briefReport.ok++; else briefReport.fail.push(`${want}: ${v}`);
    }
    await revealTabs(page);
    // Return to a DRAWING, not merely to tab 0 — which is the brief on any atlas that
    // has findings, leaving the sections below inspecting a plate with no canvas.
    const firstDrawing = await page.evaluate(
      (names) => names.find((n) => window.__ATLAS__.diagrams[n]) || names[0], tabNames);
    await page.click(`[role=tab][data-name="${firstDrawing}"]`);
  }

  // ── every inside view opens from its part and leads back to it ──────────────────
  const insideReport = { total: 0, ok: 0, fail: [] };
  const pairs = await page.evaluate(() => {
    const out = [];
    for (const [d, g] of Object.entries(window.__ATLAS__.diagrams))
      for (const [id, n] of Object.entries(g.nodes)) if (n.inside) out.push([d, id, n.inside[0], n.label]);
    return out;
  });
  for (const [d, id, child, label] of pairs) {
    insideReport.total++;
    await revealTabs(page);
    await page.click(`[role=tab][data-name="${d}"]`);
    const at = await page.evaluate((i) => {
      const r = document.querySelector(`.plate.on .canvas [data-node-id="${i}"]`).getBoundingClientRect();
      return { x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) };
    }, id);
    await page.mouse.click(at.x, at.y);
    const drill = await page.$('.ins-body .drill:not(.up)');
    if (!drill) { insideReport.fail.push(`${d}/${id}: no inside link in its panel`); continue; }
    await drill.click();
    const down = await page.evaluate((c) => {
      const p = document.querySelector('.plate.on');
      if (!p || p.dataset.name !== c) return 'stayed on ' + (p && p.dataset.name);
      return document.querySelector('.ins-body .drill.up') ? null : 'no way back up';
    }, child);
    if (down) { insideReport.fail.push(`${d}/${id} -> ${child}: ${down}`); continue; }
    await page.click('.ins-body .drill.up');
    const back = await page.evaluate(([dd, lab]) => {
      const p = document.querySelector('.plate.on');
      if (!p || p.dataset.name !== dd) return 'up went to ' + (p && p.dataset.name);
      const h = document.querySelector('.ins-head h2').textContent;
      return h === lab ? null : 'panel reads "' + h + '"';
    }, [d, label]);
    if (back === null) insideReport.ok++; else insideReport.fail.push(`${child} -> ${d}/${id}: ${back}`);
  }

  // ── every finding must light the path it claims ──────────────────────────────────
  // A finding is a claim that something fails HERE, and the whole value of it is the
  // highlight. A picker that switches the tab and lights nothing is worse than no picker:
  // it reads as "this hop is fine". Driven through the real <select> for the same reason
  // the clicks above use the real mouse — a change event set by hand skips the browser's
  // own commit path, which is where a control breaks.
  const findReport = { total: 0, ok: 0, fail: [] };
  const nFind = await page.evaluate(() => (window.__ATLAS__.findings || []).length);
  for (let i = 0; i < nFind; i++) {
    findReport.total++;
    await page.selectOption('.fsel', String(i));
    const v = await page.evaluate((k) => {
      const f = window.__ATLAS__.findings[k];
      const plate = document.querySelector('.plate.on');
      const c = plate && plate.querySelector('.canvas');
      if (!plate || plate.dataset.name !== f.diagram) return { why: 'wrong tab: ' + (plate && plate.dataset.name) };
      if (!c.hasAttribute('data-focus')) return { why: 'nothing dimmed' };
      const litN = [...c.querySelectorAll('[data-node-id].lit')].map(n => n.getAttribute('data-node-id'));
      // COUNT EDGES, NOT ELEMENTS. archify draws one edge as three nodes that all carry
      // the same data-edge-id — the visible path, its wider hit twin, and the label
      // group — so a set of element counts scored 3 lit for 1 named and failed all 21
      // findings against code that was correct. The id is the edge; the elements are not.
      const litE = [...new Set([...c.querySelectorAll('[data-edge-id].lit')]
        .map(n => n.getAttribute('data-edge-id')))];
      const missN = (f.nodes || []).filter(x => litN.indexOf(x) < 0);
      const missE = (f.edges || []).filter(x => litE.indexOf(x) < 0);
      if (missN.length || missE.length) return { why: 'unlit ' + missN.concat(missE).join(',') };
      // A named edge wins: nothing beyond the named set may be lit, or the finding
      // implicates hops it does not claim.
      if ((f.edges || []).length && litE.length !== f.edges.length) {
        return { why: 'lit ' + litE.length + ' edges for ' + f.edges.length + ' named' };
      }
      const head = document.querySelector('.ins-head h2').textContent || '';
      if (head.indexOf(f.id) < 0) return { why: 'panel reads "' + head + '"' };
      return { ok: 1 };
    }, i);
    if (v.ok) findReport.ok++; else findReport.fail.push(`${await page.evaluate((k) => window.__ATLAS__.findings[k].id, i)}: ${v.why}`);
  }
  if (nFind) {
    // Clearing must actually clear, or the reader carries one finding's dimming into the
    // next thing they look at and reads it as that thing's state.
    await page.click('.fclear');
    const cleared = await page.evaluate(() =>
      !document.querySelector('.plate.on .canvas').hasAttribute('data-focus'));
    if (!cleared) findReport.fail.push('clear left the diagram dimmed');
  }

  const results = await page.evaluate(async ({ AA_NORMAL, AA_LARGE, MIN_TARGET }) => {
    const fail = [];
    const note = [];
    const A = window.__ATLAS__;

    // ── selecting must actually LOOK selected, in every theme ────────────────────
    // The panel opening is not the feature; the feature is being able to SEE which box
    // you picked. Those are separate failures and only one of them was ever checked — a
    // theme rule outranked the highlight rule and the selected node dimmed with the rest,
    // in dark mode only, while every panel assertion stayed green. Opacity is read after
    // the transition settles, because reading it at t=0 returns the start value and makes
    // a broken highlight look fine.
    for (const theme of ['light', 'dark']) {
      document.documentElement.setAttribute('data-theme', theme);
      // TAB 0 IS NOT ALWAYS A DRAWING. build.py puts the brief first whenever findings
      // exist, and a brief plate has no `.canvas` — so the old `[0]` deref threw and
      // failed the WHOLE suite on every brief-first atlas. The main loop at the top of
      // this file already guards on __ATLAS__.diagrams; these two sites did not.
      ([...document.querySelectorAll('[role=tab]')]
        .find(t => window.__ATLAS__.diagrams[t.dataset.name])
        || document.querySelectorAll('[role=tab]')[0]).click();
      const c = document.querySelector('.plate.on .canvas');
      const ids = [...c.querySelectorAll('[data-node-id]')].map(n => n.getAttribute('data-node-id'));
      const pick = c.querySelector(`[data-node-id="${ids[0]}"]`);
      const rest = c.querySelector(`[data-node-id="${ids[ids.length - 1]}"]`);
      const r = pick.getBoundingClientRect();
      const x = Math.round(r.left + r.width / 2), y = Math.round(r.top + r.height / 2);
      const hit = document.elementFromPoint(x, y);
      if (hit) {
        ['pointerdown', 'pointerup'].forEach(t => hit.dispatchEvent(
          new PointerEvent(t, { bubbles: true, clientX: x, clientY: y, button: 0, pointerId: 1 })));
        hit.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y }));
      }
      await new Promise(r2 => setTimeout(r2, 350));
      if (!c.getAttribute('data-focus')) fail.push(`${theme}: selecting sets no focus state`);
      const on = parseFloat(getComputedStyle(pick).opacity);
      const off = parseFloat(getComputedStyle(rest).opacity);
      if (!(on > off + 0.2)) fail.push(
        `${theme}: selection is not visible — selected ${on}, unselected ${off}`);
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      await new Promise(r2 => setTimeout(r2, 200));
      const cleared = parseFloat(getComputedStyle(rest).opacity);
      if (cleared < 0.95) fail.push(`${theme}: Escape leaves the diagram dimmed (${cleared})`);
    }
    document.documentElement.removeAttribute('data-theme');

    // ── arrowheads resolve inside their OWN svg ──────────────────────────────────
    for (const t of document.querySelectorAll('[role=tab]')) {
      t.click();
      const name = document.querySelector('.plate.on').dataset.name;
      const svg = document.querySelector('.plate.on .canvas svg');
      // A PLATE IS NOT ALWAYS A DRAWING — the brief has no canvas and no svg. Skipping is
      // right here and would be wrong two blocks down: a tab that fails to switch its
      // plate is a defect whatever the plate contains, so only the svg-shaped assertions
      // are guarded, never the tab-shaped ones.
      if (!svg) continue;
      const defined = new Set([...svg.querySelectorAll('marker[id]')].map(m => m.id));
      const used = new Set();
      svg.querySelectorAll('[marker-end],[marker-start]').forEach(e =>
        ['marker-end', 'marker-start'].forEach(a => {
          const v = e.getAttribute(a);
          if (v) used.add(v.replace(/^url\(#|\)$/g, ''));
        }));
      [...used].filter(u => !defined.has(u)).forEach(u =>
        fail.push(`${name}: marker ${u} referenced but not defined in this svg`));
      if (!defined.size) fail.push(`${name}: no arrowhead markers at all`);
    }

    // ── no duplicate ids anywhere in the document ────────────────────────────────
    const seen = {};
    document.querySelectorAll('[id]').forEach(el => { seen[el.id] = (seen[el.id] || 0) + 1; });
    Object.entries(seen).filter(([, n]) => n > 1)
      .forEach(([k, n]) => fail.push(`duplicate id "${k}" x${n} — markers bind to the first`));

    // ── contrast, both themes ────────────────────────────────────────────────────
    const lum = c => {
      const [r, g, b] = c.match(/[\d.]+/g).slice(0, 3).map(Number).map(v => {
        v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
      });
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
    const groundOf = el => {
      let n = el;
      while (n && n !== document.documentElement) {
        const bg = getComputedStyle(n).backgroundColor;
        if (bg && !/rgba\(0, 0, 0, 0\)|transparent/.test(bg)) return bg;
        n = n.parentElement;
      }
      return getComputedStyle(document.body).backgroundColor;
    };
    for (const theme of ['light', 'dark']) {
      document.documentElement.setAttribute('data-theme', theme);
      // TAB 0 IS NOT ALWAYS A DRAWING. build.py puts the brief first whenever findings
      // exist, and a brief plate has no `.canvas` — so the old `[0]` deref threw and
      // failed the WHOLE suite on every brief-first atlas. The main loop at the top of
      // this file already guards on __ATLAS__.diagrams; these two sites did not.
      ([...document.querySelectorAll('[role=tab]')]
        .find(t => window.__ATLAS__.diagrams[t.dataset.name])
        || document.querySelectorAll('[role=tab]')[0]).click();
      document.querySelectorAll('.bar *, .inspect *').forEach(el => {
        if (!el.textContent.trim() || el.children.length) return;
        const r = el.getBoundingClientRect();
        if (!r.width || !r.height) return;
        const cs = getComputedStyle(el);
        const size = parseFloat(cs.fontSize), bold = parseInt(cs.fontWeight) >= 700;
        const need = (size >= 24 || (size >= 18.66 && bold)) ? AA_LARGE : AA_NORMAL;
        const got = ratio(cs.color, groundOf(el));
        if (got < need) fail.push(
          `contrast ${theme} ${got.toFixed(2)}:1 (need ${need}) — "${el.textContent.trim().slice(0, 30)}"`);
      });
    }
    document.documentElement.removeAttribute('data-theme');

    // ── hit-target size ──────────────────────────────────────────────────────────
    document.querySelectorAll('button, a[href]').forEach(el => {
      const r = el.getBoundingClientRect();
      if (!r.width) return;
      if (r.width < MIN_TARGET || r.height < MIN_TARGET)
        fail.push(`target ${Math.round(r.width)}x${Math.round(r.height)} below ${MIN_TARGET}px — ${el.className || el.tagName}`);
    });

    // ── aria wiring ──────────────────────────────────────────────────────────────
    if (!document.querySelector('[role=tablist]')) fail.push('no tablist');
    document.querySelectorAll('[role=tab]').forEach(t => {
      const panel = document.getElementById(t.getAttribute('aria-controls'));
      if (!panel) fail.push(`tab ${t.dataset.name}: aria-controls dangles`);
      else if (panel.getAttribute('role') !== 'tabpanel') fail.push(`${t.dataset.name}: panel is not a tabpanel`);
      if (!t.hasAttribute('aria-selected')) fail.push(`tab ${t.dataset.name}: no aria-selected`);
    });
    document.querySelectorAll('button').forEach(b => {
      if (!b.textContent.trim() && !b.getAttribute('aria-label') && !b.getAttribute('title'))
        fail.push(`unlabelled button: ${b.className}`);
    });

    // ── the page itself never scrolls; the canvas and the panel do ───────────────
    if (document.body.scrollHeight > window.innerHeight + 2)
      fail.push(`page scrolls: ${document.body.scrollHeight} > ${window.innerHeight}`);

    // ── reduced motion is honoured ───────────────────────────────────────────────
    const rm = [...document.styleSheets]
      .flatMap(s => { try { return [...s.cssRules]; } catch (e) { return []; } })
      .filter(r => r.conditionText && /prefers-reduced-motion/.test(r.conditionText)).length;
    if (!rm) fail.push('no prefers-reduced-motion rule');

    // ── every tab actually switches ──────────────────────────────────────────────
    for (const t of document.querySelectorAll('[role=tab]')) {
      t.click();
      if (document.querySelector('.plate.on').dataset.name !== t.dataset.name)
        fail.push(`tab ${t.dataset.name} does not switch the plate`);
    }

    // ── the viewBox is fitted to the drawing, not to the authored layout ─────────
    for (const t of document.querySelectorAll('[role=tab]')) {
      t.click();
      const svg = document.querySelector('.plate.on .canvas svg');
      if (!svg) continue;                     // the brief again: nothing to fit
      if (svg.dataset.fitted !== '1')
        fail.push(`${document.querySelector('.plate.on').dataset.name}: viewBox not fitted`);
    }

    return { fail, note };
  }, { AA_NORMAL, AA_LARGE, MIN_TARGET });

  // BOTH LINES CARRY THEIR DENOMINATOR. `nodes reachable: 1` was printable on a page with
  // 30 nodes, 29 of them broken — a number a reader can only misread as a scale they do
  // not have. And the edge denominator now excludes what a cap stopped it from attempting,
  // with the shortfall named on its own line rather than folded into the failures.
  const edgeTried = clickReport.edgeTotal - clickReport.edgeSkipped.length;
  console.log(`  nodes reachable: ${clickReport.nodes}/${clickReport.nodeTotal}`);
  console.log(`  edges reachable: ${clickReport.edges}/${edgeTried}`);
  if (clickReport.edgeSkipped.length)
    console.log(`  edges NOT ATTEMPTED: ${clickReport.edgeSkipped.length} of ${clickReport.edgeTotal}`
      + ` — a failure cap tripped, so this run did not measure them`);
  if (findReport.total) console.log(`  findings light their path: ${findReport.ok}/${findReport.total}`);
  if (briefReport.total) console.log(`  brief links reach the drawing: ${briefReport.ok}/${briefReport.total}`);
  if (insideReport.total) console.log(`  inside views open and lead back: ${insideReport.ok}/${insideReport.total}`);
  results.note.forEach(n => console.log(`  ${n}`));
  const failures = results.fail
    .concat(clickReport.nodeFail.map(f => `node unreachable or wrong panel: ${f}`))
    .concat(clickReport.edgeFail.map(f => `edge unreachable: ${f}`))
    .concat(findReport.fail.map(f => `finding lights nothing: ${f}`))
    .concat(briefReport.fail.map(f => `brief link broken: ${f}`))
    .concat(insideReport.fail.map(f => `inside view broken: ${f}`))
    .concat(consoleErrors.map(e => `console: ${e}`));
  const real = failures;

  if (real.length) {
    console.log(`\nFAIL — ${real.length} problem(s)`);
    real.forEach(f => console.log(`  ✗ ${f}`));
  } else {
    console.log('\nPASS — every check green');
  }
  await browser.close();
  process.exit(real.length ? 1 : 0);
}

main().catch(e => { console.error(e); process.exit(2); });
