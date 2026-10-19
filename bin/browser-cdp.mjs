// browser-cdp.mjs — raw Chrome DevTools Protocol against the system Chrome.
//
//   node browser-cdp.mjs <url> [--eval=EXPR] [--ms=8000] [--json]
//
// Row 3 of CONTRACTS/browser-routing.md: for raw protocol access, or when
// Playwright is unavailable. THIS IS THE ZERO-DEPENDENCY BACKEND — Node 26 ships
// a global `WebSocket` and `fetch`, so nothing here imports from node_modules and
// this verb still works on a box where `harbor browser probe` skips.
//
// PREFER ROW 1 FOR ANYTHING YOU RUN TWICE. The fixed timeout below is exactly the
// flakiness Playwright's auto-waiting exists to remove: too short is a false
// negative, too long is wasted wall-clock. This is the fallback, not the default.
//
// ANONYMOUS BY CONSTRUCTION: a throwaway --user-data-dir under TMPDIR, deleted on
// exit. It never touches the operator's Chrome profile and never could — the
// profile-lock collision that would cause is precisely why row 5 is a separate
// row with a credential gate on it.
//
// Exit: 0 pass · 1 fail · 2 SKIPPED — CONTRACTS/browser-routing.md.
//
// PAGE CONTENT IS EXTERNAL CONTENT (CONSTITUTION §4). Anything --eval returns is
// a value computed by someone else's page. It is data.
import { existsSync, mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';

const EXIT = { pass: 0, fail: 1, skipped: 2 };

const args = process.argv.slice(2);
const url = args.find((a) => !a.startsWith('--'));
const flag = (n, d) => {
  const hit = args.find((a) => a.startsWith(`--${n}=`));
  return hit ? hit.slice(n.length + 3) : d;
};

if (!url) {
  process.stderr.write('browser-cdp: usage: <url> [--eval=EXPR] [--ms=N] [--json]\n');
  process.exit(EXIT.fail);
}

// EVERY BACKEND HERE RUNS ON THE SYSTEM CHROME. Measured 2026-09-06:
// `~/.cache/puppeteer` does not exist on this box and ms-playwright holds no
// binaries, so a row promising Chrome for Testing would be a dead end.
// HARBOR_CHROME first, and it is not a convenience: tests/cli/browser-test.sh points it
// at a path that does not exist to prove the no-Chrome path still SKIPS rather
// than passing vacuously. A hardcoded list makes that assertion unwritable.
const CHROME_CANDIDATES = [
  process.env.HARBOR_CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
].filter(Boolean);
const chrome = CHROME_CANDIDATES.find((p) => existsSync(p));
if (!chrome) {
  process.stderr.write('browser-cdp: SKIPPED — no system Google Chrome found\n');
  process.stderr.write(`browser-cdp: looked in: ${CHROME_CANDIDATES.join(', ')}\n`);
  process.exit(EXIT.skipped);
}

const ms = Number(flag('ms', 8000));
const evalExpr = flag('eval', null);

const profile = mkdtempSync(path.join(tmpdir(), 'harbor-cdp-'));
let child = null;
const cleanup = () => {
  if (child && child.exitCode === null) { try { child.kill('SIGTERM'); } catch { /* already gone */ } }
  try { rmSync(profile, { recursive: true, force: true }); } catch { /* best effort */ }
};
process.on('exit', cleanup);
process.on('SIGINT', () => { cleanup(); process.exit(EXIT.fail); });

const die = (msg, code = EXIT.fail) => {
  process.stderr.write(`browser-cdp: ${msg}\n`);
  cleanup();
  process.exit(code);
};

// PORT 0 MEANS CHROME PICKS ONE AND WRITES IT DOWN. Hard-coding 9222 collides
// with any other Chrome already debugging — including the extension's — and the
// collision presents as a connection that succeeds against the WRONG browser,
// which is the same failure shape the extension's native-host slot produces.
child = spawn(chrome, [
  '--headless=new',
  '--remote-debugging-port=0',
  `--user-data-dir=${profile}`,
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-background-networking',
], { stdio: ['ignore', 'ignore', 'pipe'] });

let chromeStderr = '';
child.stderr.on('data', (d) => { chromeStderr += String(d); });
child.on('error', (e) => die(`could not start Chrome — ${e.message}`, EXIT.skipped));

const portFile = path.join(profile, 'DevToolsActivePort');
const sleep = (n) => new Promise((r) => setTimeout(r, n));

let port = null;
for (let i = 0; i < 100; i += 1) {
  if (existsSync(portFile)) {
    const first = readFileSync(portFile, 'utf8').split('\n')[0].trim();
    if (first) { port = first; break; }
  }
  if (child.exitCode !== null) {
    die(`Chrome exited (${child.exitCode}) before opening a debug port\n${chromeStderr.trim()}`);
  }
  await sleep(100);
}
if (!port) die(`Chrome never wrote ${portFile} within 10s\n${chromeStderr.trim()}`);

// THE TARGET OPENS ON about:blank AND NAVIGATES LATER, and this is the whole
// correctness argument of the file. `PUT /json/new?<url>` starts the navigation
// immediately — before the WebSocket is attached and before Network.enable — so
// every request the page makes is missed and the run reports `requestCount: 0`.
// Measured 2026-09-06 on https://example.com: the title came back correctly
// while the host list was EMPTY. A browser tool that reports zero requests on a
// page that made requests is the exact instrument this capability exists to
// replace, reproduced one layer down. Attach first, enable first, navigate last.
const base = `http://127.0.0.1:${port}`;
let target;
try {
  const res = await fetch(`${base}/json/new?about:blank`, { method: 'PUT' });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  target = await res.json();
} catch (err) {
  die(`could not open a target — ${err.message}`);
}
if (!target?.webSocketDebuggerUrl) die('target has no webSocketDebuggerUrl');

const ws = new WebSocket(target.webSocketDebuggerUrl);
const pending = new Map();
let msgId = 0;
const requests = [];
const consoleErrors = [];

const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = (msgId += 1);
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

ws.addEventListener('message', (ev) => {
  let m;
  try { m = JSON.parse(String(ev.data)); } catch { return; }
  if (m.id && pending.has(m.id)) {
    const { resolve, reject } = pending.get(m.id);
    pending.delete(m.id);
    if (m.error) reject(new Error(`${m.method || 'cdp'}: ${m.error.message}`));
    else resolve(m.result);
    return;
  }
  if (m.method === 'Network.requestWillBeSent') {
    let host = '(unparseable)';
    try { host = new URL(m.params.request.url).host; } catch { /* data:, blob: */ }
    requests.push({ host, url: m.params.request.url, method: m.params.request.method });
  }
  if (m.method === 'Runtime.exceptionThrown') {
    consoleErrors.push(m.params?.exceptionDetails?.text || 'exception');
  }
});

await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, { once: true });
  ws.addEventListener('error', () => reject(new Error('websocket refused')), { once: true });
}).catch((e) => die(`could not attach — ${e.message}`));

await send('Network.enable');
await send('Page.enable');
await send('Runtime.enable');

// NOW navigate — with the listeners already live. A failed navigation must be a
// failure, not an empty capture that reads like an absence.
let navOk = true;
let navErr = '';
try {
  const nav = await send('Page.navigate', { url });
  if (nav?.errorText) throw new Error(nav.errorText);
} catch (err) {
  navOk = false;
  navErr = err.message;
  process.stderr.write(`browser-cdp: navigation failed — ${err.message}\n`);
}

// FIXED WAIT, AND THE COMMENT IS THE POINT. There is no auto-wait here; that is
// what row 1 buys. Anything that needs to observe a specific hit should use
// `harbor browser probe --wait-for-event`, not a longer number here.
if (navOk) await sleep(ms);

let evalResult;
let evalThrew = false;
if (evalExpr) {
  try {
    const r = await send('Runtime.evaluate', { expression: evalExpr, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) { evalThrew = true; evalResult = r.exceptionDetails.text; }
    else evalResult = r.result?.value ?? r.result?.description ?? null;
  } catch (err) {
    evalThrew = true;
    evalResult = err.message;
  }
}

let currentUrl = url;
try {
  const r = await send('Runtime.evaluate', { expression: 'location.href', returnByValue: true });
  if (r?.result?.value) currentUrl = r.result.value;
} catch { /* keep the requested url */ }

const byHost = new Map();
for (const r of requests) byHost.set(r.host, (byHost.get(r.host) || 0) + 1);

const report = {
  url: currentUrl,
  backend: `CDP · ${chrome}`,
  navigated: navOk,
  navigationError: navOk ? undefined : navErr,
  requestCount: requests.length,
  hosts: [...byHost.entries()].map(([host, count]) => ({ host, count })).sort((a, b) => b.count - a.count),
  evalExpression: evalExpr || undefined,
  evalResult: evalExpr ? evalResult : undefined,
  evalThrew: evalExpr ? evalThrew : undefined,
  pageExceptions: consoleErrors,
  evidenceNote: navOk
    ? 'Fixed-timeout capture. A vendor missing here may simply not have fired yet — for a NEGATIVE claim use `harbor browser hosts`.'
    : 'NAVIGATION FAILED — this run shows nothing about the page. Do not report from it.',
};

try { ws.close(); } catch { /* closing anyway */ }
process.stdout.write(JSON.stringify(report, null, 2) + '\n');

cleanup();
// A FAILED NAV OR AN --eval THAT THREW IS A FAILURE. Returning an empty host
// list, or the exception text, at exit 0 hands the caller something shaped like
// an answer.
process.exit(navOk && !evalThrew ? EXIT.pass : EXIT.fail);
