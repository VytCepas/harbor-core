// VISUAL CHECK (harbor#392) — the browser half. Renders a generated page at every
// theme/viewport combination and asserts two things a stylesheet cannot assert
// about itself: that text is legible against the ground it actually lands on,
// and that the page does not scroll sideways.
//
// WHY THIS EXISTS. Harbor generates three HTML surfaces and had no automated
// check that any of them RENDERS correctly. On 2026-08-31 bin/dashboard-gen.sh
// was found drawing its "unknown" status at 3.42:1 on the dark ground, under the
// 4.5:1 AA floor, and it had been doing so since the dark palette landed. Lint
// H1 now catches that specific cause — a colour token with no dark value — but
// H1 is set arithmetic over source text, and a page can fail legibility with
// every token present: a hand-written literal, a token used on the wrong
// surface, an inherited colour nobody thought about. Appearance closes only on
// a render (CONSTITUTION No.2.8).
//
// PROVENANCE. The shape is taken from tt-a1i/archify (MIT), whose visual-check
// renders four viewports across light and dark and asserts overflow, occlusion
// and a projected-text readability floor. Nothing is copied: its assertions are
// about its own SVG stage furniture, and — measured 2026-08-31 — it does not
// check contrast at all, which is the one assertion that would have caught our
// defect. What transferred is the idea that a generated page gets rendered and
// looked at, and its exit-code contract: pass 0, fail 1, so an unavailable verifier defers instead of being
// quietly downgraded (No.2.7). Here that is D-29's: usage 2, UNCHECKED 3 (it was SKIPPED 2 before D-49).

import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const EXIT = { pass: 0, fail: 1, usage: 2, unchecked: 3 };

// The probe host is where Playwright and a Chrome channel live. Overridable so
// this never hard-codes one machine's home into a public repo (No.3).
const PROBE_DIR = process.env.HARBOR_PROBE_DIR
  || path.join(process.env.HOME || '', '.local/lib/browser-probes');

const VIEWPORTS = [
  { width: 720, height: 1000, label: 'narrow' },
  { width: 1440, height: 1000, label: 'wide' },
];
const THEMES = ['light', 'dark'];

// The WCAG AA floors (4.5 normal, 3.0 large text at >=24px or >=18.66px bold)
// are declared INSIDE auditInPage and nowhere else. They cannot be module
// constants: that function is serialised and evaluated in the page, so it closes
// over nothing here, and a pair of module-scope constants naming the thresholds
// would read as the source of truth while the browser used its own copy.

const targets = process.argv.slice(2).filter((a) => !a.startsWith('-'));
if (targets.length === 0) {
  process.stderr.write('  FAIL: no target given\n  fix: sh bin/visual-check.sh <file.html>\n');
  process.exit(EXIT.usage);
}
for (const t of targets) {
  if (!existsSync(t)) {
    process.stderr.write(`  FAIL: no such file: ${t}\n  fix: sh bin/visual-check.sh <an existing .html file>\n`);
    process.exit(EXIT.usage);
  }
}

let chromium;
try {
  const entry = path.join(PROBE_DIR, 'node_modules/playwright/index.mjs');
  if (!existsSync(entry)) throw new Error(`no playwright at ${entry}`);
  ({ chromium } = await import(pathToFileURL(entry).href));
} catch (err) {
  // UNCHECKED, never a pass (D-29). A missing verifier is reported as missing: nothing was judged.
  process.stderr.write(`  FAIL: unchecked — ${err.message}, so nothing was judged\n`);
  process.stderr.write('  fix: set HARBOR_PROBE_DIR to a tree with playwright installed\n');
  process.exit(EXIT.unchecked);
}

// Runs inside the page. Returns every text-bearing element whose computed
// colour fails the AA floor against its effective background, plus the page
// overflow measurement.
function auditInPage() {
  const parse = (c) => {
    const m = String(c).match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(/[,\s/]+/).filter(Boolean).map(Number);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  };
  const lum = ({ r, g, b }) => {
    const f = (v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (x, y) => {
    const a = lum(x), b = lum(y);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  };
  const over = (fg, bg) => ({
    r: fg.r * fg.a + bg.r * (1 - fg.a),
    g: fg.g * fg.a + bg.g * (1 - fg.a),
    b: fg.b * fg.a + bg.b * (1 - fg.a),
    a: 1,
  });

  // Walk ancestors until something opaque is found, compositing any
  // semi-transparent layers on the way. The viewer paints its own ground behind
  // the page, so an entirely transparent chain resolves to the canvas colour.
  const effBg = (el) => {
    const layers = [];
    let cur = el;
    while (cur) {
      const c = parse(getComputedStyle(cur).backgroundColor);
      if (c && c.a > 0) {
        layers.push(c);
        if (c.a >= 1) break;
      }
      cur = cur.parentElement;
    }
    let base = layers.length && layers[layers.length - 1].a >= 1
      ? layers.pop()
      : parse(getComputedStyle(document.documentElement).backgroundColor) || { r: 255, g: 255, b: 255, a: 1 };
    if (base.a < 1) base = { r: 255, g: 255, b: 255, a: 1 };
    while (layers.length) base = over(layers.pop(), base);
    return base;
  };

  const failures = [];
  const seen = new Set();
  for (const el of document.querySelectorAll('body *')) {
    // Only elements that render their OWN text; a wrapper inherits its
    // childrens colours and would triple-count the same pixel.
    const own = Array.from(el.childNodes)
      .filter((n) => n.nodeType === 3 && n.textContent.trim().length > 0)
      .map((n) => n.textContent.trim())
      .join(' ');
    if (!own) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || Number(cs.opacity) === 0) continue;
    const box = el.getBoundingClientRect();
    if (box.width < 1 || box.height < 1) continue;

    const fg = parse(cs.color);
    if (!fg || fg.a === 0) continue;
    const bg = effBg(el);
    const composited = fg.a < 1 ? over(fg, bg) : fg;
    const size = parseFloat(cs.fontSize) || 16;
    const weight = Number(cs.fontWeight) || 400;
    const large = size >= 24 || (size >= 18.66 && weight >= 700);
    const floor = large ? 3.0 : 4.5;
    const r = ratio(composited, bg);
    if (r + 0.005 < floor) {
      const key = `${cs.color}|${bg.r},${bg.g},${bg.b}|${large}`;
      if (seen.has(key)) continue; // one report per colour pair, not per node
      seen.add(key);
      failures.push({
        selector: el.tagName.toLowerCase() + (el.className && typeof el.className === 'string'
          ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : ''),
        text: own.slice(0, 40),
        fg: cs.color,
        bg: `rgb(${Math.round(bg.r)}, ${Math.round(bg.g)}, ${Math.round(bg.b)})`,
        ratio: Math.round(r * 100) / 100,
        floor,
        fontPx: Math.round(size * 10) / 10,
      });
    }
  }

  return {
    failures,
    overflowPx: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    bodyBg: getComputedStyle(document.body).backgroundColor,
  };
}

let browser;
try {
  browser = await chromium.launch({ channel: 'chrome' });
} catch (err) {
  process.stderr.write(`  FAIL: unchecked — cannot launch Chrome: ${err.message.split('\n')[0]}, so nothing was judged\n`);
  process.stderr.write('  fix: sh bin/visual-check.sh --self-test   # once Chrome is installed\n');
  process.exit(EXIT.unchecked);
}

let failed = 0;
let combos = 0;
for (const target of targets) {
  const url = pathToFileURL(path.resolve(target)).href;
  for (const theme of THEMES) {
    for (const vp of VIEWPORTS) {
      combos++;
      const ctx = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        colorScheme: theme,
      });
      const page = await ctx.newPage();
      await page.goto(url, { waitUntil: 'load' });
      const res = await page.evaluate(auditInPage);
      const tag = `${path.basename(target)} ${theme}/${vp.label}`;
      // Every FAIL is followed by its fix: the same command, after the CSS it names is repaired.
      const fix = `  fix: sh bin/visual-check.sh ${target}   # after repairing what the line above names\n`;

      // A transparent body borrows the host ground — the page must paint its own.
      if (/rgba\(0, 0, 0, 0\)|transparent/.test(res.bodyBg)) {
        process.stdout.write(`  FAIL: ${tag}: body has no background of its own (${res.bodyBg})\n${fix}`);
        failed++;
      }
      if (res.overflowPx > 1) {
        process.stdout.write(`  FAIL: ${tag}: page scrolls sideways by ${res.overflowPx}px\n${fix}`);
        failed++;
      }
      for (const f of res.failures) {
        process.stdout.write(
          `  FAIL: ${tag}: ${f.ratio}:1 under ${f.floor}:1 — ${f.selector} `
          + `${f.fg} on ${f.bg} at ${f.fontPx}px ("${f.text}")\n${fix}`,
        );
        failed++;
      }
      if (!res.failures.length && res.overflowPx <= 1) {
        process.stdout.write(`  ok: ${tag}\n`);
      }
      await ctx.close();
    }
  }
}
await browser.close();

process.stdout.write(`  note: ${combos} render(s), ${failed} failure(s)\n`);
process.exit(failed ? EXIT.fail : EXIT.pass);
