// The console's allowlist (harbor#738): every command `harbor ui` may run, in ONE table, each an argument array.
// A request names a panel id and nothing else; no command text, path or argument ever comes from the wire.
// Adding a panel (the Obligations tab, harbor#1053) is one entry here and nothing else.
import { existsSync } from "node:fs";
import { headline as obligationsHeadline, shapeProblem as obligationsShape, OB_MAX_BYTES } from "./obligations.ts";

export interface Column { label: string; get: (row: any) => unknown }
export type View =
  | { kind: "text"; quiet?: RegExp }                          // quiet: lines that are healthy, folded away
  | { kind: "json-table"; rows: (json: any) => any[]; columns: Column[] }
  | { kind: "pipe-table"; columns: { label: string; col: number }[] }
  | { kind: "obligations" };                                    // harbor#1053: obligations.ts renders it; its JSON shape is checked on arrival
export interface Panel {
  readonly id: string;
  readonly title: string;
  readonly tab: string;
  readonly argv: readonly string[];
  readonly okExits: readonly number[];   // exits that are an answer; any other exit is "unavailable"
  readonly timeoutMs: number;
  readonly view: View;
  readonly note?: string;
  readonly headline?: (r: Parsed) => string | undefined;
}
export interface Parsed { text: string; json?: any }
export interface Result {
  status: "ok" | "problem" | "unavailable";
  reason: string;
  exit: number | null;
  text: string;
  json?: any;
  ranAt: number;
  ms: number;
}
export const TABS = [{ id: "state", title: "State" }, { id: "work", title: "Work" }, { id: "obligations", title: "Obligations" }] as const;

const MAX_BYTES = 256 * 1024;
const lines = (t: string) => t.split("\n");
const lastMatch = (t: string, re: RegExp) => lines(t).reverse().map((l) => l.match(re)).find(Boolean) ?? null;
const countOf = (t: string, re: RegExp) => lines(t).filter((l) => re.test(l)).length;
const SUMMARY = /(\d+) ok, (\d+) failed, (\d+) warnings\s*$/;
const logSummary = (r: Parsed) => {
  const m = lastMatch(r.text, SUMMARY);
  if (!m) return undefined;
  return +m[2] > 0 ? `${m[2]} failed · ${m[1]} ok` : +m[3] > 0 ? `${m[1]} ok · ${m[3]} warn` : `${m[1]} ok`; // short: a tile is one line
};
const dash = (v: unknown) => (v === undefined || v === null || v === "" ? "unknown" : v);

export function makePanels(root: string, cfg: string, home: string): readonly Panel[] {
  const sh = (script: string, ...args: string[]) => ["sh", `${root}/bin/${script}`, ...args];
  const short = (p: unknown) => (typeof p === "string" && p.startsWith(home) ? "~" + p.slice(home.length) : p);
  return Object.freeze([
    { id: "floor", title: "Floor", tab: "state", argv: sh("floor-verify.sh", "--live"), okExits: [0, 1], timeoutMs: 120_000,
      view: { kind: "text", quiet: /^\s*ok:/ }, headline: logSummary },
    { id: "findings", title: "Findings", tab: "state", argv: sh("lint-findings.sh", "report"), okExits: [0, 1], timeoutMs: 60_000,
      note: "the findings store (harbor#590); no accept button until #741",
      view: { kind: "text" }, headline: (r) => { const m = lastMatch(r.text, /open: (\d+)/); return m ? `${m[1]} open` : undefined; } },
    { id: "register", title: "Check register", tab: "state", argv: ["grep", "-E", "^\\| `", `${root}/docs/reference/checks.md`], okExits: [0], timeoutMs: 10_000,
      view: { kind: "pipe-table", columns: [{ label: "id", col: 0 }, { label: "schedule", col: 2 }, { label: "notifies", col: 3 }] },
      headline: (r) => `${countOf(r.text, /^\| `/)} checks` },
    { id: "checks", title: "Check alerts", tab: "state", argv: ["tail", "-n", "40", `${cfg}/cache/checks.log`], okExits: [0], timeoutMs: 10_000,
      note: "the last 40 lines of checks.log: the delta, never a census",
      view: { kind: "text" }, headline: (r) => { const m = lastMatch(r.text, /\[check:([^\]]+)\] (\S+)/); return m ? `${m[1]} · ${m[2]}` : undefined; } },
    { id: "guards", title: "Guard blocks", tab: "state", argv: sh("admission-observe-report.sh", "--fp"), okExits: [0], timeoutMs: 120_000,
      note: "false-positive candidates; the floor's own probe traffic is dropped first (harbor#560), so a self-test is never ranked",
      view: { kind: "text" }, headline: (r) => { const n = countOf(r.text, /^\s+\d+ x /); return n > 0 ? `${n} repeat shapes` : undefined; } },
    { id: "context", title: "Context", tab: "state", argv: sh("context-budget.sh", "--check"), okExits: [0, 1], timeoutMs: 60_000,
      view: { kind: "text" }, headline: logSummary },
    { id: "memory", title: "Memory", tab: "state", argv: sh("memory-route.sh", "--live"), okExits: [0, 1], timeoutMs: 60_000,
      view: { kind: "text", quiet: /^\s+ok\s/ },
      headline: (r) => lastMatch(r.text, /^\[check:memory-route\] (.*)$/)?.[1] },
    { id: "backlog", title: "Backlog", tab: "state", argv: sh("standard-issue-label.sh", "--audit"), okExits: [0, 1], timeoutMs: 90_000,
      note: "open issues missing an axis, and themes whose members cite no sibling",
      view: { kind: "text" }, headline: (r) => { const n = countOf(r.text, /^\s+#\d+/); return n > 0 ? `${n} flagged` : undefined; } },
    { id: "fleet", title: "Fleet", tab: "work", argv: ["projects-orchestrator", "snapshot", "--json"], okExits: [0], timeoutMs: 90_000,
      view: { kind: "json-table", rows: (j) => (Array.isArray(j) ? j : []), columns: [
        { label: "project", get: (r) => dash(r.descriptor?.name) },
        { label: "branch", get: (r) => dash(r.status?.branch) },
        { label: "tree", get: (r) => (r.status?.dirty === undefined ? "unknown" : r.status.dirty ? "dirty" : "clean") },
        { label: "ahead/behind", get: (r) => (r.status ? `${r.status.ahead ?? "?"}/${r.status.behind ?? "?"}` : "unknown") },
        { label: "last commit", get: (r) => dash(r.status?.last_commit) }] },
      headline: (r) => (Array.isArray(r.json) ? `${r.json.length} repos` : undefined) },
    { id: "sessions", title: "Sessions", tab: "work", argv: sh("context-peers.sh", "--json"), okExits: [0], timeoutMs: 30_000,
      view: { kind: "json-table", rows: (j) => (Array.isArray(j) ? j : []), columns: [
        { label: "name", get: (r) => dash(r.name) }, { label: "status", get: (r) => dash(r.status) },
        { label: "kind", get: (r) => dash(r.kind) }, { label: "tree", get: (r) => dash(short(r.tree)) },
        { label: "branch", get: (r) => dash(r.branch) }] },
      headline: (r) => (Array.isArray(r.json) ? `${r.json.length} live` : undefined) },
    { id: "worktrees", title: "Worktrees", tab: "work", argv: sh("worktree.sh", "list"), okExits: [0], timeoutMs: 60_000,
      view: { kind: "text" }, headline: (r) => { const n = countOf(r.text, /^(SKIP|COLLECT|KEEP)\s/); return n > 0 ? `${n} worktrees` : undefined; } },
    { id: "prs", title: "Pull requests", tab: "work", argv: ["gh", "pr", "list", "--json", "number,title,headRefName,isDraft,updatedAt", "--limit", "40"],
      okExits: [0], timeoutMs: 30_000,
      view: { kind: "json-table", rows: (j) => (Array.isArray(j) ? j : []), columns: [
        { label: "#", get: (r) => dash(r.number) }, { label: "title", get: (r) => dash(r.title) },
        { label: "branch", get: (r) => dash(r.headRefName) }, { label: "draft", get: (r) => (r.isDraft ? "draft" : "") },
        { label: "updated", get: (r) => dash(r.updatedAt) }] },
      headline: (r) => (Array.isArray(r.json) ? `${r.json.length} open` : undefined) },
    { id: "obligations", title: "Obligations", tab: "obligations", argv: sh("status-obligations.sh", "show", "--json"), okExits: [0], timeoutMs: 30_000,
      note: "what is unfinished on the box (harbor#1050): new since the last view, then overdue, then oldest",
      view: { kind: "obligations" }, headline: (r) => obligationsHeadline(r.json) },
  ] satisfies Panel[]);
}

const firstLine = (s: string) => (s.split("\n").map((l) => l.trim()).find(Boolean) ?? "").slice(0, 160);
const unavailable = (reason: string, t0: number, exit: number | null = null, text = ""): Result =>
  ({ status: "unavailable", reason, exit, text, ranAt: t0, ms: Date.now() - t0 });

// The ONE place a process is started. It takes a Panel from the table, never an argv from anywhere else.
export async function runPanel(p: Panel, root: string, capMs = Infinity): Promise<Result> {
  const limit = Math.min(p.timeoutMs, capMs);
  const t0 = Date.now();
  const script = p.argv[0] === "sh" ? p.argv[1] : undefined;
  if (script !== undefined && !existsSync(script)) return unavailable(`${script.startsWith(root + "/") ? script.slice(root.length + 1) : script} is not on this box`, t0);
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn([...p.argv], { cwd: root, stdin: "ignore", stdout: "pipe", stderr: "pipe", detached: true, env: { ...process.env, NO_COLOR: "1" } }); // own process group, so a timeout reaches the grandchildren
  } catch {
    return unavailable(`${p.argv[0]} is not installed on this box`, t0);
  }
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<"timeout">((r) => { timer = setTimeout(() => r("timeout"), limit); });
  const done = Promise.all([new Response(proc.stdout as ReadableStream).text(), new Response(proc.stderr as ReadableStream).text(), proc.exited]);
  const first = await Promise.race([done, deadline]); // guard:deadline
  clearTimeout(timer);
  if (first === "timeout") {
    try { process.kill(-proc.pid, "SIGKILL"); } catch { proc.kill(); } // guard:groupkill
    done.catch(() => {});
    return unavailable(`timed out after ${Math.round(limit / 1000)}s`, t0);
  }
  const [out, err, code] = first;
  if (!p.okExits.includes(code)) return unavailable(`exit ${code}: ${firstLine(err) || firstLine(out) || "no output"}`, t0, code); // guard:exit
  const both = err.trim() ? out + (out && !out.endsWith("\n") ? "\n" : "") + err : out; // log-lib tools write to either stream
  const text = both.length > MAX_BYTES ? both.slice(0, MAX_BYTES) + "\n[output cut]" : both;
  if (p.view.kind === "obligations" && Buffer.byteLength(out) > OB_MAX_BYTES) return unavailable(`output is larger than ${OB_MAX_BYTES / 1048576} MB`, t0, code); // before JSON.parse: one hostile row must not become a page
  let json: any;
  if (p.view.kind === "json-table" || p.view.kind === "obligations") {
    try { json = JSON.parse(out); } catch { return unavailable("output is not JSON", t0, code); }
  }
  if (p.view.kind === "obligations") { const bad = obligationsShape(json); if (bad) return unavailable(bad, t0, code); } // not the frozen shape: unavailable, never an empty list
  if (!text.trim()) return unavailable("the command printed nothing", t0, code);
  return { status: code === 0 ? "ok" : "problem", reason: "", exit: code, text, json, ranAt: t0, ms: Date.now() - t0 };
}

export const displayCmd = (p: Panel, root: string, home: string) =>
  p.argv.map((a) => (a.startsWith(root + "/") ? a.slice(root.length + 1) : a.startsWith(home + "/") ? "~" + a.slice(home.length) : a)).join(" ");
