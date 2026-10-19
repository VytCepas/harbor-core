// `harbor ui` (harbor#738): a localhost console of Harbor's live state, read-only. One Bun.serve, no framework, no dependencies.
//   bun tools/ui/server.ts [--port N] [--idle SECS] [--wait SECS] [--min-age SECS] [--timeout SECS] [--open]
// Security: loopback only, a Host and Origin check, a single-use launch code swapped for a session cookie, and a table of commands it may run (sources.ts).
// Each guard line below carries a `// guard:<name>` mark; tests/cli/console-guards-test.sh deletes each in turn and the suite goes red.
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { homedir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { makePanels, runPanel, type Panel, type Result } from "./sources.ts";
import { beginView } from "./obligations.ts";
import { headline, pageHtml, panelHtml, tileHtml, type PanelState } from "./render.ts";

const VALUE_FLAGS = ["--port", "--idle", "--wait", "--min-age", "--timeout"];
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (VALUE_FLAGS.includes(a)) { if (!/^\d+(\.\d+)?$/.test(process.argv[++i] ?? "")) { console.error(`harbor ui: ${a} needs a number`); process.exit(2); } }
  else if (a !== "--open") { console.error(`harbor ui: unknown argument ${a} (--port N, --idle SECS, --wait SECS, --min-age SECS, --timeout SECS, --open)`); process.exit(2); }
}
const arg = (name: string, dflt: string) => { const i = process.argv.indexOf(name); return i > 0 ? (process.argv[i + 1] ?? dflt) : dflt; };
const num = (name: string, dflt: number) => { const n = Number(arg(name, String(dflt))); return Number.isFinite(n) && n >= 0 ? n : dflt; };
const ROOT = resolve(process.env.HARBOR_STATUS_CONSOLE_ROOT ?? resolve(dirname(fileURLToPath(import.meta.url)), "../.."));
const HOME = process.env.HOME ?? homedir();
const CFG = process.env.CLAUDE_CONFIG_DIR ?? `${HOME}/.claude`;
const IDLE_MS = Math.max(1, num("--idle", 1800)) * 1000;
const WAIT_MS = Math.min(100, num("--wait", 3)) * 1000; // below idleTimeout, or Bun drops the waiting request
const MIN_AGE_MS = num("--min-age", 300) * 1000; // a page load re-runs only what is older than this
const CAP_MS = num("--timeout", 0) > 0 ? num("--timeout", 0) * 1000 : Infinity;
const CODE = randomBytes(32).toString("hex"); // in the URL, good for one exchange
let codeUsed = false;
let session: string | null = null; // the cookie's value: never the code
const PANELS = makePanels(ROOT, CFG, HOME);
const BY_ID = new Map<string, Panel>(PANELS.map((p) => [p.id, p]));

// ── the panel store: latest result per source, one run in flight per source ──
const states = new Map<string, PanelState>(PANELS.map((p) => [p.id, { running: false }]));
const inflight = new Map<string, Promise<void>>();
const subscribers = new Set<(chunk: string) => void>();
const frag = (p: Panel) => { const s = states.get(p.id)!; return { id: p.id, panel: panelHtml(p, s, ROOT, HOME), tile: tileHtml(p, s) }; };
const push = (p: Panel) => { const m = `event: panel\ndata: ${JSON.stringify(frag(p))}\n\n`; for (const f of subscribers) f(m); };
function refresh(p: Panel): Promise<void> {
  const live = inflight.get(p.id); if (live) return live; // guard:inflight
  states.get(p.id)!.running = true;
  const run = runPanel(p, ROOT, CAP_MS)
    .catch((e): Result => ({ status: "unavailable", reason: `could not run: ${String(e).slice(0, 120)}`, exit: null, text: "", ranAt: Date.now(), ms: 0 }))
    .then((result) => { states.set(p.id, { running: false, result }); push(p); })
    .finally(() => inflight.delete(p.id));
  inflight.set(p.id, run);
  return run;
}
const refreshAll = () => Promise.all(PANELS.map(refresh));

// ── the guards ──
const sha = (s: string) => createHash("sha256").update(s).digest();
const same = (given: string | null, want: string | null) => given !== null && want !== null && timingSafeEqual(sha(given), sha(want));
const cookieName = (port: number) => `harbor_ui_${port}`;
function cookie(req: Request, name: string) {
  for (const part of (req.headers.get("cookie") ?? "").split(";")) {
    const [k, ...v] = part.trim().split("=");
    if (k === name) return v.join("=");
  }
  return null;
}
const FORBIDDEN = () => new Response("forbidden\n", { status: 403, headers: { "content-type": "text/plain", "cache-control": "no-store" } });

let lastActive = Date.now();
const start = Date.now();

let server: ReturnType<typeof Bun.serve>;
try { server = serve(); } catch (e) { console.error(`harbor ui: cannot listen on 127.0.0.1:${num("--port", 0)}: ${String(e).slice(0, 120)}`); process.exit(1); }
function serve() { return Bun.serve({
  hostname: "127.0.0.1", // guard:bind
  port: num("--port", 0),
  idleTimeout: 120,
  maxRequestBodySize: 4096,
  development: false, // guard:dev  no error page with source and paths
  error() { return new Response("error\n", { status: 500, headers: { "content-type": "text/plain" } }); }, // guard:error
  async fetch(req) {
    const port = server.port;
    const hosts = [`127.0.0.1:${port}`, `localhost:${port}`];
    if (!hosts.includes(req.headers.get("host") ?? "")) return FORBIDDEN(); // guard:host
    const origin = req.headers.get("origin");
    if (origin !== null && !hosts.some((h) => origin === `http://${h}`)) return FORBIDDEN(); // guard:origin
    const sfs = req.headers.get("sec-fetch-site"); // a browser says who is asking; another localhost port is same-site, not same-origin
    if (sfs !== null && sfs !== "same-origin" && sfs !== "none") return FORBIDDEN(); // guard:fetchsite
    let url: URL;
    try { url = new URL(req.url); } catch { return FORBIDDEN(); }
    const hasSession = same(cookie(req, cookieName(port)), session);
    const exchange = !hasSession && !codeUsed && url.pathname === "/" && req.method === "GET" && same(url.searchParams.get("token"), CODE);
    if (!hasSession && !exchange) return FORBIDDEN(); // guard:token

    if (url.pathname !== "/events") lastActive = Date.now();
    const noStore = { "cache-control": "no-store", "referrer-policy": "no-referrer", "x-content-type-options": "nosniff" }; // guard:referrer

    if (exchange) {
      codeUsed = true; // guard:once
      session = randomBytes(32).toString("hex");
      return new Response(null, { status: 303, headers: { ...noStore, location: "/", "set-cookie": `${cookieName(port)}=${session}; Path=/; HttpOnly; SameSite=Strict` } });
    }

    if (url.pathname === "/" && (req.method === "GET" || req.method === "HEAD")) {
      const due = PANELS.filter((p) => { const r = states.get(p.id)!.result; return !r || Date.now() - r.ranAt >= MIN_AGE_MS; });
      await Promise.race([Promise.all(due.map(refresh)), new Promise((r) => setTimeout(r, WAIT_MS))]);
      if (req.method === "GET") beginView(states.get("obligations")?.result?.json); // a page load is a view: what it shows as new is relative to the one before
      const nonce = randomBytes(16).toString("base64");
      const headers: Record<string, string> = {
        ...noStore, "content-type": "text/html; charset=utf-8",
        "content-security-policy": `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
      };
      return new Response(req.method === "HEAD" ? null : pageHtml(PANELS, states, ROOT, HOME, nonce, `127.0.0.1:${port}`), { headers });
    }

    if (url.pathname === "/events" && req.method === "GET") {
      let send: (c: string) => void = () => {};
      let beat: ReturnType<typeof setInterval>;
      const enc = new TextEncoder();
      const stream = new ReadableStream({
        start(c) {
          send = (m) => { try { c.enqueue(enc.encode(m)); } catch { /* the client went away */ } };
          subscribers.add(send);
          send(": connected\n\n");
          for (const p of PANELS) if (states.get(p.id)!.result) send(`event: panel\ndata: ${JSON.stringify(frag(p))}\n\n`);
          beat = setInterval(() => send(": beat\n\n"), 10_000);
        },
        cancel() { subscribers.delete(send); clearInterval(beat); },
      });
      return new Response(stream, { headers: { ...noStore, "content-type": "text/event-stream", connection: "keep-alive" } });
    }

    if (url.pathname === "/refresh" && req.method === "POST") { await refreshAll(); return new Response("{}\n", { headers: { ...noStore, "content-type": "application/json" } }); }

    if (url.pathname === "/run" && req.method === "POST") {
      if (!(req.headers.get("content-type") ?? "").startsWith("application/json")) return new Response("expected application/json\n", { status: 415 });
      const raw = await req.text();
      if (raw.length > 1024) return new Response("body too large\n", { status: 413 });
      let id: unknown;
      try { id = JSON.parse(raw)?.id; } catch { return new Response("bad json\n", { status: 400 }); }
      const panel = typeof id === "string" ? BY_ID.get(id) : undefined; // guard:allowlist
      if (!panel) return new Response(JSON.stringify({ error: "not in the allowlist" }) + "\n", { status: 403, headers: { "content-type": "application/json" } });
      await refresh(panel);
      return new Response(JSON.stringify({ id: panel.id, headline: headline(panel, states.get(panel.id)!) }) + "\n", { headers: { ...noStore, "content-type": "application/json" } });
    }

    return new Response("not found\n", { status: 404 });
  },
}); }

const base = `http://127.0.0.1:${server.port}/`;
console.log(`harbor ui: ${base}?token=${CODE}`);
console.log(`harbor ui: read-only, 127.0.0.1 only, the link opens once, stops after ${Math.round(IDLE_MS / 1000)}s idle; ctrl-c to stop now`);
if (process.argv.includes("--open")) {
  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  try { Bun.spawn([opener, `${base}?token=${CODE}`], { stdin: "ignore", stdout: "ignore", stderr: "ignore" }); } catch { console.error(`harbor ui: no ${opener} here; open the URL above`); }
}

const idle = setInterval(() => {
  if (Date.now() - lastActive < IDLE_MS) return; // guard:idle
  clearInterval(idle);
  console.log(`harbor ui: stopped after ${Math.round((Date.now() - start) / 1000)}s, idle for ${Math.round(IDLE_MS / 1000)}s`);
  server.stop(true);
  process.exit(0);
}, Math.min(1000, Math.max(100, IDLE_MS / 4)));
for (const sig of ["SIGINT", "SIGTERM"] as const) process.on(sig, () => { server.stop(true); process.exit(0); });
