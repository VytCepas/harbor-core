#!/usr/bin/env bun
// benchmark-driver.ts (harbor#1421) — time MCP tool calls against a harbor_chrome server, for tests/access/chrome/benchmark.sh.
// INTERPRETER EXCEPTION: bun, because it drives the server over stdio and times each reply with one clock.
//
//   bun benchmark-driver.ts <label> <n> <tool> <arg>... -- <server command...>
//
// Starts the server, runs `snapshot` once to read the ref of the button named "Go", warms with one call of <tool> (<arg> may be
// the word REF for that ref, or REF:<name> for the button of that name), then times <n> calls. Prints one JSON object: label, tool, n, ms[] sorted, median, p90, first.
import { spawn } from 'node:child_process';
import * as readline from 'node:readline';

const argv = process.argv.slice(2);
const dash = argv.indexOf('--');
const [label, nStr, tool, ...args] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const n = Number(nStr);
const p = spawn(cmd[0], cmd.slice(1), { stdio: ['pipe', 'pipe', 'inherit'] });
const rl = readline.createInterface({ input: p.stdout });
const waiting = new Map<number, (m: any) => void>();
rl.on('line', (l) => { try { const m = JSON.parse(l); waiting.get(m.id)?.(m); waiting.delete(m.id); } catch { /* not a reply */ } });
let id = 0;
const rpc = (method: string, params: object) => new Promise<any>((ok) => { const i = ++id; waiting.set(i, ok); p.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: i, method, params }) + '\n'); });
const callTool = async (name: string, a: string[]) => {
  const t0 = performance.now();
  const r = await rpc('tools/call', { name, arguments: { args: a } });
  return { ms: performance.now() - t0, text: String(r.result?.content?.[0]?.text ?? ''), isError: !!r.result?.isError };
};

await rpc('initialize', { protocolVersion: '2025-06-18' });
const snap = await callTool('snapshot', []);
const refOf = (name: string) => new RegExp(`button "${name}"[^\\n]*\\[ref=(e[0-9]+)\\]`).exec(snap.text)?.[1] ?? '';
const ref = refOf('Go');
if (!ref && tool === 'click') console.error(`${label}: no button "Go" in the snapshot: ${snap.text.slice(0, 600)}`);
const real = args.map((a) => (a === 'REF' ? ref : a.startsWith('REF:') ? refOf(a.slice(4)) : a));
const first = await callTool(tool, real);
const ms: number[] = [];
let last = first;
for (let i = 0; i < n; i++) { last = await callTool(tool, real); ms.push(last.ms); }
ms.sort((a, b) => a - b);
const q = (f: number) => ms[Math.min(ms.length - 1, Math.floor(ms.length * f))];
const title = (t: string) => /Page Title: (.*)/.exec(t)?.[1] ?? '';
const after = await callTool('snapshot', []);   // a script click (harbor#1507) replies without the title
console.log(JSON.stringify({ label, tool, n, ref, titleBefore: title(snap.text), titleAfter: title(after.text), median: Math.round(q(0.5)), p90: Math.round(q(0.9)), first: Math.round(first.ms), error: last.isError, last: last.text.slice(0, 400), ms: ms.map(Math.round) }));
p.stdin.end();
