#!/usr/bin/env bun
// access-chrome-mcp.ts (harbor#1421, from #1301) — `harbor chrome` as the MCP server `harbor_chrome`, one process per session.
// INTERPRETER EXCEPTION: bun (TypeScript), because the server holds one connection to the session's Playwright daemon for its
// whole life; the shell version paid a new bunx and node process for every call. Zero imports from node_modules.
//
// WHAT HOLDS CHROME. `access-browser-agent.sh attach` starts @playwright/cli's daemon, which holds the extension connection
// for as long as the session lives (measured: cli-client/session.js sends every verb to that daemon's socket; the CLI does
// not reconnect). This server speaks that socket directly, so a verb costs one socket round trip instead of a process chain.
// The verbs that need Chrome's windows or the operator (attach, detach, tabs, front, wait-signin, doctor, status, hosts,
// tab-new) are not hot and own their AppleScript in the shell agent; they are run by it, unchanged, beside this file.
//
// THE GUARDS ARE THIS FILE'S, ported from access-browser-agent.sh and shown refusing in tests/access/chrome/session.test.sh:
// verb and option allowlists, the https host allowlist, the snapshot ref and destructive-label check on click, the --force
// overlay check, the upload path checks, and the lost-tab, hidden-tab, gone-session and signed-out stops. The operator's
// per-call HARBOR_ACCESS_BROWSER_CONFIRM never reaches an MCP server (the launcher scrubs the environment), so a destructive
// click is always a hand-off here, as before. Test seams are a JSON file beside this one, never the environment: a project's
// settings `env` reaches this process, and a seam it can set is a guard it can move.
import { spawn, spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';
import * as readline from 'node:readline';

const HERE = path.dirname(fs.realpathSync(process.argv[1] ?? import.meta.path));
const ROOT = HERE.endsWith('/bin') ? HERE.slice(0, -4) : path.dirname(HERE);
let SEAMS: Record<string, any> = {};
try { SEAMS = JSON.parse(fs.readFileSync(path.join(HERE, 'access-chrome-mcp.seams.json'), 'utf8')); } catch { /* production has none */ }

const AGENT = path.join(HERE, 'access-browser-agent.sh');
const HOSTS_FILE = path.join(ROOT, 'contracts', 'browser-agent-hosts.txt');
const ROUTER = 'contracts/browser-routing.md, row 4';
const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];
const OUT_MAX = 100000;
const SETTLE_MS: number = SEAMS.settleMs ?? 500;   // the extension detached a tab ~300 ms after an input (2026-10-14); the shell waited 1 s
const PATH_FIXED = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
const KEEP = ['HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR', 'TERM', 'CLAUDE_CODE_SESSION_ID', 'HARBOR_ACCESS_BROWSER_SESSION'];
const HOME: string = process.env.HOME ?? os.homedir();
const STATE_EXPR = 'JSON.stringify({visibility: document.visibilityState, focus: document.hasFocus(), ready: document.readyState, host: location.host, blank: location.href === "about:blank", online: navigator.onLine})';
const OWNED_NAME = '.owned-tabs';
const DESTRUCTIVE = ('delete remove archive pause publish unpublish discard pay purchase buy unlink disconnect ' +
  'ištrinti pašalinti archyvuoti sustabdyti pristabdyti publikuoti paskelbti išjungti apmokėti').split(' ');

// Run by the shell agent: the verbs that touch Chrome's windows or wait on the operator.
const LONG: Record<string, number> = { attach: 900, 'wait-signin': 900 };   // seconds
const AGENT_VERBS = new Set(['attach', 'status', 'doctor', 'detach', 'tabs', 'front', 'wait-signin', 'hosts', 'tab-new']);
// Run here. Default-deny: absent on purpose are run-code, eval, cookie-*, *storage-*, state-save/load, requests, route, install...
const HOT_VERBS = new Set(['state', 'goto', 'tab-list', 'tab-select', 'tab-close', 'snapshot', 'find', 'screenshot', 'pdf',
  'go-back', 'go-forward', 'reload', 'console', 'resize', 'click', 'dblclick', 'hover', 'fill', 'type', 'select', 'check', 'uncheck',
  'drag', 'press', 'keydown', 'keyup', 'mousemove', 'mousedown', 'mouseup', 'mousewheel', 'dialog-accept', 'dialog-dismiss', 'upload']);
const INPUT_VERBS = new Set(['click', 'dblclick', 'fill', 'type', 'select', 'check', 'uncheck', 'drag', 'press', 'keydown', 'keyup',
  'hover', 'mousedown', 'mouseup', 'mousewheel']);
const SIGNIN_FAIL_VERBS = new Set(['goto', 'reload', 'go-back', 'go-forward', 'click', 'dblclick']);

const VERBS: Record<string, string> = {
  attach: "connect to the operator's Chrome; the operator clicks Connect unless the extension token is registered",
  status: "this session's browser name, pin, profile and workdir",
  state: "the page's own visibility, focus and load state",
  doctor: 'is harbor chrome ready on this box',
  detach: "release the operator's Chrome; always run it when done",
  tabs: "every Chrome tab by window, query strings cut; = marks this session's page",
  front: "make this session's tab the visible one, then give focus back",
  'wait-signin': 'wait (args: [seconds], default 300) while the operator signs in',
  hosts: 'the host allowlist goto and tab_new read: core, then the private layer',
  goto: 'open one https url (args: [url]) on an allowed host',
  'tab-new': 'open a tab (args: [] or [url] on an allowed host)',
  'tab-list': "this session's tabs", 'tab-select': 'select a tab (args: [index])', 'tab-close': 'close a tab (args: [index])',
  snapshot: 'the page as an accessibility tree with refs', find: 'find on the page (args: [text])',
  screenshot: 'a screenshot (args: [] or [--filename=<bare name>]); it lands in the session workdir',
  pdf: 'the page as a PDF (args: [--filename=<bare name>])',
  'go-back': 'history back', 'go-forward': 'history forward', reload: 'reload the page',
  console: 'the page console', resize: 'resize the viewport (args: [width, height])',
  click: 'click a ref (args: [ref] or [ref, button], --force, --modifiers=<key>)', dblclick: 'double-click a ref',
  hover: 'hover a ref', fill: 'fill a field (args: [ref, text], --submit)', type: 'type text (args: [text], --submit)',
  select: 'select an option (args: [ref, value])', check: 'check a ref', uncheck: 'uncheck a ref',
  drag: 'drag (args: [from-ref, to-ref])', press: 'press a key (args: [key])',
  keydown: 'key down (args: [key])', keyup: 'key up (args: [key])',
  mousemove: 'move the mouse (args: [x, y])', mousedown: 'mouse down', mouseup: 'mouse up',
  mousewheel: 'scroll (args: [dx, dy])', 'dialog-accept': 'accept the open dialog', 'dialog-dismiss': 'dismiss the open dialog',
  upload: 'upload files (args: absolute paths) after a click opened the file chooser',
};
const SCHEMA = { type: 'object', additionalProperties: false, properties: {
  args: { type: 'array', items: { type: 'string' }, description: "the verb's arguments, as harbor chrome takes them" },
  lane: { type: 'string', description: "a parallel agent's own browser session: 1-12 of a-z0-9" } } };
const toolName = (v: string) => v.replace(/-/g, '_');
const TOOLS: Record<string, string> = Object.fromEntries(Object.keys(VERBS).map((v) => [toolName(v), v]));

type Res = { text: string; isError: boolean };
class Refusal extends Error { constructor(msg: string, public fix: string) { super(msg); } }
// Every refusal is FAIL, its fix, the summary: the shape library-log.sh gives the shell agent, so the failure ledger's
// "fail: hand-off:" tag (hooks/failure-observe) reads both alike (harbor#465).
const refuse = (what: string, fix = `none automatic — see ${ROUTER}`): never => { throw new Refusal(what, fix); };
const handoff = (what: string, fix = ''): never => refuse(`hand-off: ${what}`, fix || `none automatic — see ${ROUTER}`);
const refusalText = (r: Refusal) => `  FAIL: ${r.message.replace(/\n/g, ' ')}\n  fix: ${r.fix}\nbrowser-agent: 0 ok, 1 failed, 0 warnings`;

const asciiLower = (s: string) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));
const readText = (p: string) => { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } };

// ── the session ─────────────────────────────────────────────────────────────
// One browser session per Claude session, a lane appended for a parallel agent (access-browser-agent.sh _session).
function sessionName(lane: string): string {
  const id = process.env.CLAUDE_CODE_SESSION_ID ?? '';
  let s = '';
  if (id) s = 'claude-' + id.replace(/[^A-Za-z0-9]/g, '').slice(0, 12);
  else s = process.env.HARBOR_ACCESS_BROWSER_SESSION || `mcp-${process.ppid}`;   // one per parent session, so two never share a page
  const bad = !s || s === 'claude-' || /[^A-Za-z0-9_-]/.test(s);
  const laneBad = lane !== '' && (/[^a-z0-9]/.test(lane) || lane.length > 12);
  if (bad || laneBad) refuse('no session: run inside Claude Code (CLAUDE_CODE_SESSION_ID), or set HARBOR_ACCESS_BROWSER_SESSION outside it; a HARBOR_BROWSER_LANE is 1-12 of a-z0-9', 'export HARBOR_ACCESS_BROWSER_SESSION=manual');
  return lane ? `${s}-${lane}` : s;
}
const workdirOf = (s: string) => path.join((process.env.TMPDIR ?? '/tmp').replace(/\/+$/, ''), 'harbor-browser', s);

// ── the daemon socket (cli-client/session.js: newline-framed JSON, {id, method:'run', params:{args, cwd, raw}}) ──
function daemonDirs(): string[] {
  const base: string = SEAMS.daemonDir ?? (process.platform === 'darwin'
    ? path.join(HOME, 'Library', 'Caches', 'ms-playwright', 'daemon')
    : path.join(process.env.XDG_CACHE_HOME ?? path.join(HOME, '.cache'), 'ms-playwright', 'daemon'));
  try { return fs.readdirSync(base).map((d) => path.join(base, d)).filter((d) => fs.statSync(d).isDirectory()); } catch { return []; }
}
function sessionFile(s: string): { socketPath: string; timestamp: number } | null {
  let best: any = null;
  for (const d of daemonDirs()) {
    try {
      const c = JSON.parse(fs.readFileSync(path.join(d, `${s}.session`), 'utf8'));
      if (c?.socketPath && (!best || (c.timestamp ?? 0) > (best.timestamp ?? 0))) best = c;
    } catch { /* not this directory's */ }
  }
  return best;
}
class Conn {
  private buf = '';
  private next = 1;
  private waiting = new Map<number, { ok: (v: any) => void; no: (e: Error) => void }>();
  dead = false;
  constructor(private sock: net.Socket, public key: string) {
    sock.setEncoding('utf8');
    sock.on('data', (d: string) => {
      this.buf += d;
      let i: number;
      while ((i = this.buf.indexOf('\n')) >= 0) {
        const line = this.buf.slice(0, i); this.buf = this.buf.slice(i + 1);
        let m: any; try { m = JSON.parse(line); } catch { continue; }
        const w = this.waiting.get(m.id);
        if (!w) continue;
        this.waiting.delete(m.id);
        if (m.error) w.no(new Error(String(m.error))); else w.ok(m.result);
      }
    });
    const end = () => { this.dead = true; for (const w of this.waiting.values()) w.no(new Error('Session closed')); this.waiting.clear(); };
    sock.on('close', end); sock.on('error', end);
  }
  static open(p: string, key: string): Promise<Conn> {
    return new Promise((ok, no) => { const s = net.createConnection(p); s.once('connect', () => ok(new Conn(s, key))); s.once('error', no); });
  }
  run(args: Record<string, unknown>, cwd: string, raw: boolean): Promise<{ isError: boolean; text: string }> {
    const id = this.next++;
    return new Promise((ok, no) => { this.waiting.set(id, { ok, no }); this.sock.write(JSON.stringify({ id, method: 'run', params: { args, cwd, raw } }) + '\n'); });
  }
  close() { this.dead = true; this.sock.destroy(); }
}
const conns = new Map<string, Conn>();
class Gone extends Error {}
async function connect(s: string): Promise<Conn> {
  const f = sessionFile(s);
  if (!f) throw new Gone();
  const key = `${f.socketPath}:${f.timestamp}`;
  const have = conns.get(s);
  if (have && !have.dead && have.key === key) return have;
  have?.close(); conns.delete(s);
  try { const c = await Conn.open(f.socketPath, key); conns.set(s, c); return c; } catch { throw new Gone(); }
}

// ── the helpers the guards need ─────────────────────────────────────────────
const scrub = (t: string) => t.replace(/(chrome-extension:\/\/[^ )?]*)[?][^ )]*/g, '$1?<cut>');   // the connect page carries a token
const bareUrl = (u: string) => u.replace(/[?#].*/s, '');
const urlHost = (u: string) => asciiLower(u.replace(/^[a-z]+:\/\/([^/?#]*).*/s, '$1'));
function signinUrl(url: string): boolean {   // a login host, or a sign-in path segment; query and fragment dropped first
  const su = asciiLower(url).replace(/[?#].*/s, '');
  if (!su.startsWith('https://')) return false;
  const rest = su.slice(8);
  const host = rest.split('/')[0];
  const sp = rest.includes('/') ? '/' + rest.slice(rest.indexOf('/') + 1) : '/';
  if (/^(login|signin|accounts|auth|sso|id|identity|passport)\./.test(host)) return true;
  return sp.split('/').some((seg) => /^(login|signin|sign-in|log-in|logon|authorize|accountchooser|servicelogin|uas|checkpoint|oauth2?|sso)(\.(php|html?|aspx?|jsp))?$/.test(seg));
}
function hostOk(url: string): boolean {   // https, a plain host, equal to a listed host or a subdomain of one
  if (!url.startsWith('https://') || /[\\ \t]/.test(url)) return false;
  let h = url.slice(8);
  h = h.split('/')[0].split('?')[0].split('#')[0];
  h = asciiLower(h);
  if (!h || /[^a-z0-9.-]/.test(h) || h.startsWith('.') || h.endsWith('.') || h.includes('..')) return false;
  for (const f of [HOSTS_FILE, privHosts()]) {
    if (!f) continue;
    for (const raw of readText(f).split('\n')) {
      const l = raw.trim();
      if (!l || l.startsWith('#')) continue;
      if (h === l || h.endsWith('.' + l)) return true;
    }
  }
  return false;
}
let _priv: string | undefined;
function privateDir(): string {
  if (_priv === undefined) {
    _priv = SEAMS.privateDir ?? '';
    if (!_priv) { const r = spawnSync('sh', [path.join(HERE, 'scope-roots.sh'), '--private'], { encoding: 'utf8', env: scopeEnv() }); _priv = r.status === 0 ? r.stdout.trim() : ''; }
  }
  return _priv ?? '';
}
const privHosts = () => (SEAMS.privHosts ?? (privateDir() ? path.join(privateDir(), 'browser-hosts.txt') : ''));
const scopeEnv = () => ({ PATH: PATH_FIXED, HOME, ...(SEAMS.scopeEnv ?? {}) });
function accountFor(host: string): string {   // the route card's primary account for a host, or its parent domain
  const ad: string = SEAMS.accessDir ?? (privateDir() ? path.join(privateDir(), 'access') : '');
  if (!ad || !fs.existsSync(ad)) return '';
  let h = host;
  const cards = (() => { try { return fs.readdirSync(ad).filter((n) => /^[a-z].*\.md$/.test(n)).sort(); } catch { return []; } })();
  for (;;) {
    const card = cards.find((n) => readText(path.join(ad, n)).includes(h));
    if (card) {
      for (const line of readText(path.join(ad, card)).split('\n')) {
        const m = /^ *account: *([^ |]*) *\| *primary *\|/.exec(line);
        if (m && m[1]) return `${m[1]} (${card})`;
      }
    }
    if ((h.match(/\./g) ?? []).length >= 2) h = h.slice(h.indexOf('.') + 1); else return '';
  }
}
function relayErr(s: string): string {   // this session's daemon log (written under DEBUG=pw:mcp:relay), if any
  const caches = SEAMS.daemonDir ? [path.dirname(SEAMS.daemonDir)] : [process.env.XDG_CACHE_HOME ?? path.join(HOME, '.cache'), path.join(HOME, 'Library', 'Caches')];
  for (const c of caches) {
    const base = SEAMS.daemonDir ?? path.join(c, 'ms-playwright', 'daemon');
    try { for (const d of fs.readdirSync(base)) { const p = path.join(base, d, `${s}.err`); if (fs.existsSync(p)) return p; } } catch { /* none */ }
  }
  return '';
}
const lines = (p: string) => { const a = p ? readText(p).split('\n') : []; if (a[a.length - 1] === '') a.pop(); return a; };   // wc -l's count

// ── the destructive-label check (access-browser-agent.sh _words, _destructive) ──
function words(t: string): string {   // lower-cased, ASCII non-letters to spaces; non-ASCII stays a letter (š, ė)
  return ' ' + asciiLower(t).replace(/Š/g, 'š').replace(/Ė/g, 'ė').replace(/[\u0000-\u007f]/g, (c) => (/[a-z0-9]/.test(c) ? c : ' ')) + ' ';
}
const destructive = (label: string): string => { const w = words(label); return DESTRUCTIVE.find((d) => w.includes(` ${d} `)) ?? ''; };
const attrs = (s: string) => s.replace(/"([^"\\]|\\.)*"/g, '').replace(/:( .*)?$/, '');
const frameOf = (s: string) => { const m = /\[ref=(f[0-9]+)e/.exec(s); return m ? m[1] : ''; };
const indentOf = (s: string) => s.length - s.trimStart().length;
const bare = (s: string) => s.replace(/\[(ref|box|cursor|level|active|expanded|disabled|checked|selected|pressed|url)(=[^\]]*)?\]/g, '');

// Take a fresh full snapshot, read the target's label and box (a partial one would replace the CLI's ref table).
type Target = { root: string; frame: string; box: string; label: string; file: string };
async function guardSnapshot(c: Conn, S: string, wd: string, verb: string, ref: string): Promise<Target> {
  if (/^(e[0-9]|f[0-9].*e[0-9])/s.test(ref)) { if (/[^a-z0-9]/.test(ref)) refuse(`target refused: '${ref}' — ${verb} takes a snapshot ref`); }
  else refuse(`target refused: '${ref}' — ${verb} takes a snapshot ref (e12, f3e12); a selector carries no label for the destructive check`, 'harbor chrome snapshot');
  fs.mkdirSync(wd, { recursive: true });
  const g = path.join(wd, 'harbor-guard.yml'); fs.rmSync(g, { force: true });
  let r: { isError: boolean; text: string } | undefined;
  try { r = await c.run({ _: ['snapshot'], boxes: true, filename: 'harbor-guard.yml' }, wd, false); } catch { if (!sessionFile(S)) goneRefusal(S); }
  if (!r || r.isError || !fs.existsSync(g) || fs.statSync(g).size === 0) {
    if (r) goneCheck(S, r.text);
    refuse(`no guard snapshot, so ${verb} ${ref} cannot be checked`, 'harbor chrome status');
  }
  const body = fs.readFileSync(g, 'utf8').split('\n');
  let root = '', found = false, ind = 0, tf = '', box = '', label = '';
  for (const line of body) {
    const a = attrs(line);
    if (root === '' && a.includes('[ref=')) root = '-' + frameOf(a);
    if (found && indentOf(line) <= ind) break;
    if (found) { label += ' ' + bare(line); continue; }
    if (a.includes(`[ref=${ref}]`)) {
      found = true; ind = indentOf(line); tf = frameOf(a);
      const m = /\[box=([-0-9.,]+)\]/.exec(a); box = m ? m[1] : '';
      label = bare(line);
      if (/[^ \t:"-]/.test(label.replace(/^ *- *[a-z]+/, ''))) break;
    }
  }
  if (!found) refuse(`ref ${ref} is not in the current snapshot (stale after a page change)`, 'harbor chrome snapshot');
  const lab = label.replace(/[ \t]+/g, ' ').replace(/^ *- /, '').replace(/ $/, '');
  const hit = destructive(lab);
  if (hit) handoff(`destructive ${verb} refused: '${lab}' (${ref}) matches '${hit}' — the operator confirms one call`, `HARBOR_ACCESS_BROWSER_CONFIRM=${ref} harbor chrome ${verb} ${ref}`);
  return { root, frame: '-' + tf, box, label: lab, file: g };
}

// --force: Playwright's force by hand, a real mouse press at the box centre, skipping the visible/stable/receives-events wait.
async function forceClick(c: Conn, S: string, wd: string, ref: string, button: string, t: Target): Promise<Res> {
  if (!t.box) refuse(`no box for ${ref}; nothing to force-click at`);
  if (t.frame !== t.root) refuse(`${ref} is inside an iframe; its box is frame-relative, so a forced click would land elsewhere`, `harbor chrome click ${ref}`);
  const [bx, by, bw, bh] = t.box.split(',').map(Number);
  if (!(bw > 0 && bh > 0 && bx >= 0 && by >= 0)) refuse(`${ref} has box [${t.box}]: hidden, zero-size or scrolled out of view`, 'harbor chrome mousewheel 0 -400');
  const x = Math.trunc(bx + bw / 2), y = Math.trunc(by + bh / 2);
  // The press lands on whatever is on top; snapshot order is not z-order, so every top-frame element whose box holds the point is read.
  for (const line of fs.readFileSync(t.file, 'utf8').split('\n')) {
    const a = attrs(line);
    if (a.includes(`[ref=${ref}]`) || '-' + frameOf(a) !== t.root) continue;
    const m = /\[box=([-0-9.,]+)\]/.exec(a); if (!m) continue;
    const [px, py, pw, ph] = m[1].split(',').map(Number);
    if (x >= px && x <= px + pw && y >= py && y <= py + ph) {
      const r = a.slice(a.lastIndexOf('[ref=') + 5).replace(/\].*/s, '');
      const l = bare(line).replace(/^ *- /, '').replace(/  +/g, ' ').replace(/ +$/, '');
      const hit = destructive(l);
      if (hit) refuse(`forced click on ${ref} refused: the press at ${x} ${y} lands on or through '${l}' (${r}), which matches '${hit}'`, `HARBOR_ACCESS_BROWSER_CONFIRM=${ref} harbor chrome click ${ref} --force`);
    }
  }
  const btn = button ? [button] : [];
  for (const a of [['mousemove', String(x), String(y)], ['mousedown', ...btn]]) {
    const r = await c.run({ _: a }, wd, false);
    if (r.isError) { goneCheck(S, r.text); refuse(`the forced click on ${ref} did not complete`); }
  }
  return runRaw(c, { _: ['mouseup', ...btn] }, wd, false);
}
async function runRaw(c: Conn, args: Record<string, unknown>, wd: string, raw: boolean): Promise<Res> {
  const r = await c.run(args, wd, raw);
  return { text: scrub(r.text ?? ''), isError: !!r.isError };
}

// ── the stops after a verb ──────────────────────────────────────────────────
// The CLI's gone-session answer, with the relay's recorded close and the attach that brings the session back (harbor#920).
function goneCheck(S: string, text: string) {
  if (!/^(The b|B)rowser '[^']*' is not open/m.test(text)) return;
  goneRefusal(S);
}
function goneRefusal(S: string): never {
  const e = relayErr(S);
  const last = e ? lines(e).filter((l) => l.includes('ws closed> ')).slice(-1)[0] : '';
  const why = last ? last.slice(last.indexOf('ws closed> ') + 11).slice(0, 189) : '';
  return handoff(`no Chrome is connected to session ${S}${why ? ` — the relay last closed with ${why}` : ''}`,
    'harbor chrome attach   # then Connect in Chrome; for an app with a login, sign in first and Connect that tab');
}
async function probeState(c: Conn, wd: string): Promise<string | null> {
  try { const r = await c.run({ _: ['eval', STATE_EXPR] }, wd, true); return r.isError ? null : r.text; } catch { return null; }
}
// The daemon's current tab, from its own tab list: a socket round trip of milliseconds, where `eval` waits out the daemon's 500 ms settle.
async function currentUrl(c: Conn, wd: string): Promise<string | null> {
  try {
    const r = await c.run({ _: ['tab-list'] }, wd, false);
    return r.isError ? null : (/^- [0-9]+: \(current\) \[.*\]\((.*)\)$/m.exec(r.text)?.[1] ?? null);
  } catch { return null; }
}
// After an input verb: if the page is now about:blank, Chrome detached the extension from the tab and the CLI swapped in a
// blank one, so the verb reached nothing and "succeeded" (2026-10-14). The detach lands ~300 ms after the input; the daemon's
// own post-action wait counts toward that, so only what is left of SETTLE_MS is slept here.
async function lostCheck(c: Conn, S: string, wd: string, verb: string, held: string, sinceInput: number) {
  if (sinceInput < SETTLE_MS) await sleep(SETTLE_MS - sinceInput);
  if ((await currentUrl(c, wd)) !== 'about:blank') return;
  const e = relayErr(S);
  const det = e ? lines(e).filter((l) => l.includes('Target.detachedFromTarget')).slice(-1)[0] ?? '' : '';
  const at = det ? ` at ${det.slice(0, 24)}` : '';
  const ext = e && lines(e).slice(-401).some((l) => l.includes('chrome-extension:// URL of different extension'));
  const pre = scrub(held);
  const err = ext
    ? new Refusal(`the tab was lost: another extension put a frame in the page${at} (usually a password manager's autofill on a password field), and Chrome lets no extension debug another's, so ${verb} reached nothing`,
        "operator: set that extension's site access to 'On click' for this site (chrome://extensions > Details > Site access), then harbor chrome goto <url>")
    : new Refusal(`the tab was lost: Chrome detached the extension from it${at}, and the CLI now drives a blank tab, so ${verb} reached nothing`,
        'harbor chrome goto <url>   # re-open the page; a frame on an unknown scheme does this too');
  throw withPrefix(err, pre);
}
// After a failed input verb: a hidden tab never paints, so the CLI's waits time out. Say so.
async function hiddenCheck(c: Conn, wd: string, verb: string, held: string) {
  const p = await probeState(c, wd);
  if (p === null || !/visibility\\?":\\?"hidden/.test(p)) return;
  throw withPrefix(new Refusal(`the tab is hidden: Chrome is showing another tab or window, so ${verb} timed out`, 'harbor chrome front'), scrub(held));
}
class PrefixedRefusal extends Refusal { constructor(r: Refusal, public prefix: string) { super(r.message, r.fix); } }
const withPrefix = (r: Refusal, prefix: string) => new PrefixedRefusal(r, prefix);
function signedOut(wd: string, url: string): never {
  const app = readText(path.join(wd, '.app-host')).trim() || urlHost(url);
  const acct = accountFor(app);
  return handoff(`signed out: ${app} sent this session to a sign-in page (${urlHost(url)}). Signing in is the operator's: harbor never fills a password or picks a password-manager entry`,
    `operator: sign in${acct ? ` as ${acct}` : ''}; then harbor chrome wait-signin`);
}

// ── one hot verb ────────────────────────────────────────────────────────────
function envGuards(wd: string) {
  // A token in the environment skips the approval dialog; any PLAYWRIGHT_* or ~/.playwright config undoes the guards below.
  if (process.env.PLAYWRIGHT_MCP_EXTENSION_TOKEN) refuse('PLAYWRIGHT_MCP_EXTENSION_TOKEN is set; it skips the approval dialog and this verb runs attended only', 'unset PLAYWRIGHT_MCP_EXTENSION_TOKEN');
  const pe = Object.keys(process.env).filter((k) => k.startsWith('PLAYWRIGHT_'));
  if (pe.length) refuse(`PLAYWRIGHT_* set in the environment: ${pe.join(' ')} `, `unset ${pe.join(' ')} `);
  if (fs.existsSync(path.join(HOME, '.playwright'))) refuse(`${HOME}/.playwright exists; the CLI would read its config`, `mv '${HOME}/.playwright' '${HOME}/.playwright.disabled'`);
  if (!fs.existsSync(HOSTS_FILE)) refuse(`missing host allowlist: ${HOSTS_FILE}`, 'git checkout -- contracts/browser-agent-hosts.txt');
  fs.mkdirSync(wd, { recursive: true });
  for (let d = wd; d && d !== '/'; d = path.dirname(d)) {   // the CLI also takes config from any .playwright dir up that tree
    if (fs.existsSync(path.join(d, '.playwright'))) refuse(`${d}/.playwright exists; the CLI would read its config`, `mv '${d}/.playwright' '${d}/.playwright.disabled'`);
  }
}
// Options are default-deny: `--session <url>` once smuggled an off-list URL past the host check, and --filename wrote anywhere.
function optionGuards(verb: string, args: string[], wd: string) {
  for (const a of args) {
    if (a.startsWith('--filename=')) {
      const f = a.slice(11);
      if (f === '' || f.startsWith('.') || /[/\\]/.test(f) || /[^A-Za-z0-9._-]/.test(f)) refuse(`filename refused: '${f}' — a bare name only; files land in ${wd}`);
    } else if (/^-[0-9]/.test(a)) { if (/[^0-9-]/.test(a)) refuse(`option refused: ${a}`); }
    else if (['--modifiers=Alt', '--modifiers=Control', '--modifiers=ControlOrMeta', '--modifiers=Meta', '--modifiers=Shift'].includes(a)) {
      if (verb !== 'click' && verb !== 'dblclick') refuse(`option refused: ${a} — --modifiers is for click and dblclick`);
    } else if (a === '--force') { if (verb !== 'click') refuse('option refused: --force is for click only; the mouse verbs it uses carry no click count'); }
    else if (a === '--submit') { if (verb !== 'fill' && verb !== 'type') refuse('option refused: --submit is for fill and type'); }
    else if (a.startsWith('-')) refuse(`option refused: ${a} — only --filename=<name>, on fill and type --submit, and on click --force and --modifiers=<Alt|Control|ControlOrMeta|Meta|Shift>`);
  }
}
const lc = (s: string) => asciiLower(s);
function uploadGuards(args: string[]) {
  if (args.length < 1) refuse('upload takes one or more absolute file paths, after a click that opens the file chooser', 'harbor chrome upload /abs/path/file.csv');
  const root = (p: string) => { try { return fs.realpathSync(p); } catch { return p; } };
  const cd = lc(root(process.env.CLAUDE_CONFIG_DIR ?? path.join(HOME, '.claude'))), hc = lc(root(path.join(HOME, '.claude')));
  for (const a of args) {
    if (!a.startsWith('/')) refuse(`upload refused: '${a}' is not an absolute path`);
    let st: fs.Stats | undefined; try { st = fs.statSync(a); } catch { /* not there */ }
    if (!st?.isFile()) refuse(`upload refused: '${a}' is not a regular file`);
    let rf: string; try { rf = fs.realpathSync(a); } catch { return refuse(`upload refused: '${a}' could not be resolved (a link loop, or an unreadable directory)`); }
    // Compared physical and lower-cased: APFS ignores case, so ~/.CLAUDE is ~/.claude. A hardlink has no path to resolve, so a
    // file with other links is refused outright (adversarial review, 2026-10-14).
    const l = lc(rf) + '/';
    if (l.startsWith(cd + '/') || l.startsWith(hc + '/')) refuse(`upload refused: '${a}' is under ~/.claude, which never goes to a web tool (CONSTITUTION №3)`);
    const links = fs.statSync(rf).nlink;
    if (links !== 1) refuse(`upload refused: '${a}' has ${links} hard links, so where else it lives cannot be checked`, `cp '${a}' "$TMPDIR/" and upload the copy`);
  }
}
function hostGuard(verb: string, args: string[]) {
  if (verb === 'goto' && args.length !== 1) refuse('goto takes exactly one https url', "harbor chrome goto 'https://ads.reddit.com/'");
  if (verb !== 'goto' || hostOk(args[0])) return;
  // The live-walk repo is the private layer's own (harbor.toml live_walk_repo, harbor#1273), its checkout the registry's (harbor#966).
  const m = `host refused: '${args[0]}' is not https on a host in contracts/browser-agent-hosts.txt or the private layer's browser-hosts.txt; client live sites go through the live-walk repo`;
  const sr = (...a: string[]) => spawnSync('sh', [path.join(HERE, 'scope-roots.sh'), ...a], { encoding: 'utf8', env: scopeEnv() });
  const lw = sr('--conf', 'live_walk_repo');
  if (lw.status === 2) handoff(m, 'harbor-private/harbor.toml did not read: sh bin/scope-roots.sh --conf live_walk_repo');
  const repo = (lw.stdout ?? '').trim();
  if (!repo) handoff(m, 'no live-walk repo is set on this box: live_walk_repo in harbor-private/harbor.toml (contracts/private-layer.md)');
  const r = sr('--repo', repo); let ts = r.status === 0 ? (r.stdout ?? '').trim() : '';
  if (ts.startsWith(HOME + '/')) ts = '~' + ts.slice(HOME.length);
  const mm = m.replace(/the live-walk repo$/, repo);
  if (ts) handoff(mm, `cd ${ts} && just live`);
  handoff(mm, `${repo} is not registered on this box (sh bin/scope-roots.sh --repos); register it in harbor-private/repos.tsv`);
}
// The CLI's own argument object (minimist, positionals as strings): the options this file admits, then the rest.
function cliArgs(verb: string, args: string[]): Record<string, unknown> {
  const o: Record<string, unknown> = { _: [verb] };
  for (const a of args) {
    if (a.startsWith('--filename=')) o.filename = a.slice(11);
    else if (a.startsWith('--modifiers=')) o.modifiers = a.slice(12);
    else if (a === '--submit') o.submit = true;
    else (o._ as string[]).push(a);
  }
  return o;
}

type Timing = { guards: number; rpc: number; settle: number };
async function hot(S: string, verb: string, args: string[], tm: Timing): Promise<Res> {
  const t0 = performance.now();
  const wd = workdirOf(S);
  envGuards(wd);
  if (!HOT_VERBS.has(verb)) refuse(`verb refused: ${verb} — not on the allowlist in bin/access-browser-agent.sh`, 'harbor chrome help');
  if (verb === 'state') {
    if (args.length) refuse('state takes no arguments; its expression is fixed', 'harbor chrome state');
    const c = await connectOrGone(S);
    tm.guards = performance.now() - t0;
    const r = await c.run({ _: ['eval', STATE_EXPR] }, wd, true).catch((e) => { if (e instanceof Gone) goneRefusal(S); throw e; });
    tm.rpc = performance.now() - t0 - tm.guards;
    if (r.isError) goneCheck(S, r.text);
    return { text: scrub(r.text), isError: !!r.isError };
  }
  optionGuards(verb, args, wd);
  let ref = '', btn = '', force = false, mods = false;
  if (verb === 'click' || verb === 'dblclick') {
    for (const a of args) {
      if (a === '--force') force = true;
      else if (a.startsWith('--modifiers=')) mods = true;
      else if (a === '' || /^-[0-9]/.test(a)) refuse(`${verb} takes <ref> [button]; '${a}' would shift the CLI's own reading of the target`);
      else if (a.startsWith('-')) continue;
      else if (!ref) ref = a; else if (!btn) btn = a; else refuse(`${verb} takes <ref> [button]`);
    }
    if (!ref) refuse(`${verb} takes a snapshot ref`, 'harbor chrome snapshot');
    if (force && mods) refuse('--force cannot carry --modifiers; the mouse verbs it uses take none');
  }
  if (verb === 'upload') uploadGuards(args);
  hostGuard(verb, args);
  const c = await connectOrGone(S);
  if (ref) {
    const tgt = await guardSnapshot(c, S, wd, verb, ref);
    if (force) {
      const r = await forceClick(c, S, wd, ref, btn, tgt);
      tm.guards = performance.now() - t0;
      return r;
    }
  }
  if (verb === 'goto' && !signinUrl(args[0])) fs.writeFileSync(path.join(wd, '.app-host'), urlHost(args[0]) + '\n');   // a sign-in names the app's account, not the login host's
  const e0 = relayErr(S), el = lines(e0).length;
  tm.guards = performance.now() - t0;
  const t1 = performance.now();
  let r: { isError: boolean; text: string };
  try { r = await c.run(cliArgs(verb, args), wd, false); } catch (e: any) {
    if (!c.dead) throw e;
    if (!sessionFile(S)) goneRefusal(S);
    r = { isError: true, text: `Error: ${e.message}` };
  }
  tm.rpc = performance.now() - t1;
  const rc = r.isError ? 1 : 0, held = r.text ?? '';
  // A goto that fails on another extension's frame says so (login pages with a password field).
  if (verb === 'goto' && rc && e0 && lines(e0).slice(el).some((l) => l.includes('chrome-extension:// URL of different extension'))) {
    const host = urlHost(args[0]), acct = accountFor(host);
    throw withPrefix(new Refusal("hand-off: the tab was lost on load: another extension put a frame in the page (usually a password manager's autofill on a sign-in form), and Chrome lets no extension debug another's",
      `operator: sign in to ${host}${acct ? ` as ${acct}` : ''}; then harbor chrome wait-signin`), scrub(held));
  }
  // A failed navigation whose tab Chrome shows on a sign-in page: signed out, whatever the CLI says. The tab list is Chrome's,
  // read through the shell agent (AppleScript); this is the failure path, not the hot one.
  if (rc && fs.existsSync(path.join(wd, OWNED_NAME)) && readText(path.join(wd, OWNED_NAME)).trim() && SIGNIN_FAIL_VERBS.has(verb)) {
    const pu = await signedOutProbe(S);
    if (pu) { try { signedOut(wd, pu); } catch (e) { throw withPrefix(e as Refusal, scrub(held)); } }
  }
  if (rc) goneCheck(S, held);
  if (verb === 'upload' && rc && /setFileInputFiles.*Not allowed/.test(held)) {
    throw withPrefix(new Refusal('upload refused by Chrome: the Playwright Extension has no access to file URLs',
      'operator: chrome://extensions > Playwright Extension > Details > Allow access to file URLs (the extension can then read local files)'), scrub(held));
  }
  if (INPUT_VERBS.has(verb)) {
    const t2 = performance.now();
    if (!rc) await lostCheck(c, S, wd, verb, held, tm.rpc); else await hiddenCheck(c, wd, verb, held);
    tm.settle = performance.now() - t2;
  }
  if (!rc) {
    const pu = (held.match(/^- Page URL: (.*)$/gm) ?? []).slice(-1)[0]?.slice(12) ?? '';
    if (pu && signinUrl(pu)) { try { signedOut(wd, pu); } catch (e) { throw withPrefix(e as Refusal, scrub(held)); } }
  }
  return { text: scrub(held), isError: rc !== 0 };
}
async function connectOrGone(S: string): Promise<Conn> {
  try { return await connect(S); } catch (e) { if (e instanceof Gone) return goneRefusal(S); throw e; }
}
// This session's own page URL while Chrome shows it on a sign-in host: the shell agent's `tabs` marks the session's tabs with `=`.
async function signedOutProbe(S: string): Promise<string> {
  const r = await viaAgent(S, 'tabs', [], '');
  for (const l of r.text.split('\n')) {
    const m = /^= window \S+ tab \S+ +(?:active )? *(\S+)$/.exec(l);
    if (m && signinUrl(m[1])) return m[1];
  }
  return '';
}

// ── the shell agent, for the verbs that are Chrome's own ────────────────────
function agentEnv(S: string, lane: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const k of KEEP) if (process.env[k]) env[k] = process.env[k];
  env.PATH = PATH_FIXED;
  if (!env.CLAUDE_CODE_SESSION_ID && !env.HARBOR_ACCESS_BROWSER_SESSION) env.HARBOR_ACCESS_BROWSER_SESSION = `mcp-${process.ppid}`;
  if (lane) env.HARBOR_BROWSER_LANE = lane;   // access-browser-agent.sh validates it
  for (const [k, v] of Object.entries(SEAMS.agentEnv ?? {})) env[k] = String(v);
  return env;
}
function viaAgent(S: string, verb: string, args: string[], lane: string): Promise<Res> {
  const limit = (LONG[verb] ?? 180) * 1000;
  return new Promise((resolve) => {
    let out = '', err = '', done = false;
    const p = spawn('/bin/sh', [AGENT, verb, ...args], { env: agentEnv(S, lane), stdio: ['ignore', 'pipe', 'pipe'] });
    const fin = (r: Res) => { if (!done) { done = true; clearTimeout(timer); resolve(r); } };
    const timer = setTimeout(() => { p.kill('SIGKILL'); fin({ text: `harbor chrome ${verb} did not finish within ${limit / 1000} s`, isError: true }); }, limit);
    p.stdout.on('data', (d) => (out += d)); p.stderr.on('data', (d) => (err += d));
    p.on('error', (e) => fin({ text: `harbor chrome could not start: ${e.message}`, isError: true }));
    p.on('close', (code) => {
      let text = out;
      if (code !== 0) text = (text + (text ? '\n' : '') + err).trim() || `exit ${code}`;
      fin({ text: text.slice(0, OUT_MAX), isError: code !== 0 });
    });
  });
}

// ── tool calls, one at a time per browser session ───────────────────────────
const queues = new Map<string, Promise<unknown>>();
function appendTiming(wd: string, verb: string, total: number, tm: Timing) {
  try {
    const f = path.join(wd, '.timings.tsv');
    if (fs.existsSync(f) && fs.statSync(f).size > 65536) fs.writeFileSync(f, readText(f).split('\n').slice(-200).join('\n'));
    fs.appendFileSync(f, `${new Date().toISOString()}\t${verb}\t${total.toFixed(0)}\t${tm.guards.toFixed(0)}\t${tm.rpc.toFixed(0)}\t${tm.settle.toFixed(0)}\n`);
  } catch { /* timing is a courtesy */ }
}
async function call(name: string, argsIn: unknown): Promise<Res> {
  const verb = TOOLS[name];
  if (verb === undefined) return { text: `unknown tool: ${name}`, isError: true };
  if (typeof argsIn !== 'object' || argsIn === null || Array.isArray(argsIn)) return { text: 'arguments must be an object', isError: true };
  const a = argsIn as Record<string, unknown>;
  const args = a.args ?? [];
  if (!Array.isArray(args) || !args.every((x) => typeof x === 'string')) return { text: 'args must be a list of strings', isError: true };
  if (a.lane !== undefined && typeof a.lane !== 'string') return { text: 'lane must be a string', isError: true };
  const lane = (a.lane as string | undefined) ?? '';
  let S = '';
  try { S = sessionName(lane); } catch (e) { return { text: refusalText(e as Refusal), isError: true }; }
  const prev = queues.get(S) ?? Promise.resolve();
  const run = prev.then(async (): Promise<Res> => {
    const t0 = performance.now(), tm: Timing = { guards: 0, rpc: 0, settle: 0 };
    try {
      if (AGENT_VERBS.has(verb)) {
        const r = await viaAgent(S, verb, args as string[], lane);
        if (verb === 'attach' || verb === 'detach') { conns.get(S)?.close(); conns.delete(S); }   // a new daemon, a new socket
        return r;
      }
      const r = await hot(S, verb, args as string[], tm);
      appendTiming(workdirOf(S), verb, performance.now() - t0, tm);
      return { text: r.text.slice(0, OUT_MAX), isError: r.isError };
    } catch (e) {
      if (!(e instanceof Refusal)) return { text: `harbor chrome ${verb} failed: ${(e as Error).message}`, isError: true };
      const pre = e instanceof PrefixedRefusal ? e.prefix : '';
      return { text: ((pre ? pre + '\n' : '') + refusalText(e)).slice(0, OUT_MAX), isError: true };
    }
  });
  queues.set(S, run.catch(() => undefined));
  return run;
}

// ── JSON-RPC over stdio ─────────────────────────────────────────────────────
async function handle(msg: any): Promise<any | null> {
  const mid = msg.id, method = msg.method, params = msg.params ?? {};
  if (mid === undefined || mid === null) return null;   // a notification: initialized, cancelled
  const err = (code: number, message: string) => ({ jsonrpc: '2.0', id: mid, error: { code, message } });
  if (typeof method !== 'string') return err(-32600, 'invalid request');
  if (typeof params !== 'object' || Array.isArray(params)) return err(-32602, 'params must be an object');
  let result: any;
  if (method === 'initialize') {
    result = { protocolVersion: PROTOCOLS.includes(params.protocolVersion) ? params.protocolVersion : PROTOCOLS[0], capabilities: { tools: {} }, serverInfo: { name: 'harbor_chrome', version: '2' } };
  } else if (method === 'ping') result = {};
  else if (method === 'tools/list') result = { tools: Object.entries(VERBS).map(([v, d]) => ({ name: toolName(v), description: `harbor chrome ${v}: ${d}`, inputSchema: SCHEMA })) };
  else if (method === 'tools/call') {
    if (typeof params.name !== 'string') return err(-32602, 'name must be a string');
    const r = await call(params.name, params.arguments ?? {});
    result = { content: [{ type: 'text', text: r.text }], isError: r.isError };
  } else return err(-32601, `method not found: ${method}`);
  return { jsonrpc: '2.0', id: mid, result };
}
function main() {
  const rl = readline.createInterface({ input: process.stdin });
  const open = new Set<Promise<void>>();
  const send = (o: unknown) => process.stdout.write(JSON.stringify(o) + '\n');
  rl.on('line', (line) => {
    line = line.trim(); if (!line) return;
    let msg: any;
    try { msg = JSON.parse(line); } catch { return send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }); }
    if (typeof msg !== 'object' || msg === null || Array.isArray(msg)) return send({ jsonrpc: '2.0', id: null, error: { code: -32600, message: 'invalid request' } });
    const p: Promise<void> = handle(msg).then((o) => { if (o) send(o); }, (e) =>   // one bad request must not end the session's browser tools
      send({ jsonrpc: '2.0', id: msg.id ?? null, error: { code: -32603, message: `internal error: ${(e as Error).name}` } })).finally(() => open.delete(p));
    open.add(p);
  });
  rl.on('close', async () => { await Promise.allSettled([...open]); for (const c of conns.values()) c.close(); });   // the loop then empties and the process ends
}
if (import.meta.main) main();
