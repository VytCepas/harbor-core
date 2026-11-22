#!/usr/bin/env bun
// access-desktop-mcp.ts — harbor desktop as MCP tools (harbor/D-95, harbor#1440). Zero dependencies; stdio JSON-RPC.
// INTERPRETER EXCEPTION: bun (TypeScript), the sibling of access-chrome-mcp.ts: one long-lived stdio server per session,
// the same layer and runtime as harbor_chrome. Zero imports from node_modules.
// Every call relays to bin/access-desktop.sh, which launches the helper app and passes one JSON line; the helper holds
// the grants and the policy, so this file adds only the operator's confirmation: the confirm_* tools, script and
// shortcut_run pass --confirm, and run only while ~/.claude/settings.json has a permissions.ask rule for them.
// Register: claude mcp add --scope user harbor_desktop -- bun <checkout>/bin/access-desktop-mcp.ts
import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const CLI = path.join(HERE, 'access-desktop.sh');
const S = (d: string) => ({ type: 'string', description: d });
const B = (d: string) => ({ type: 'boolean', description: d });
const N = (d: string) => ({ type: 'integer', description: d });
const bundle = S('the app bundle id, from apps');
const ref = S('an element ref from tree, e.g. 0.3.1');
const gen = S('the gen tree returned: refuses if the app restarted since');
const expect = S('text the element label must contain, from tree: a moved ref is refused');

type Tool = { verb: string; confirm?: boolean; fixed?: Record<string, unknown>; d: string; props: Record<string, unknown>; req: string[] };
const TOOLS: Record<string, Tool> = {
  doctor: { verb: 'doctor', d: 'the helper: version, whether macOS granted Accessibility and Screen Recording, the allow-list', props: {}, req: [] },
  apps: { verb: 'apps', d: 'running apps: bundle id, name, allowed/not-allowed/denied, which is in front', props: {}, req: [] },
  windows: { verb: 'windows', d: 'one app\'s windows', props: { bundle }, req: ['bundle'] },
  tree: { verb: 'tree', d: 'one app\'s accessibility tree as lines: ref role "label" [actions]; read this before acting',
    props: { bundle, depth: N('max depth, default 14'), max: N('max nodes, default 1500'), enhance: B('ask a Chromium/Electron app to build its tree first') }, req: ['bundle'] },
  shot: { verb: 'shot', d: 'a PNG of one window, captured without raising it; returns the file path', props: { bundle, title: S('part of the window title') }, req: ['bundle'] },
  press: { verb: 'action', fixed: { action: 'AXPress' }, d: 'press a button, checkbox, link or menu item in the background (no pointer, no focus); a live-change label is refused: use confirm_press',
    props: { bundle, ref, gen, expect }, req: ['bundle', 'ref', 'expect'] },
  action: { verb: 'action', d: 'perform one accessibility action (AXShowMenu, AXIncrement, AXPick…); actions that take focus need foreground',
    props: { bundle, ref, gen, expect, action: S('the action name from tree'), foreground: B('allow an action that may bring the app forward') }, req: ['bundle', 'ref', 'action', 'expect'] },
  set_value: { verb: 'set-value', d: 'set a text field or control value directly (no typing, no focus); reads it back; a live-change label is refused: use confirm_set_value', props: { bundle, ref, gen, expect, value: S('the new value') }, req: ['bundle', 'ref', 'value', 'expect'] },
  menu: { verb: 'menu', d: 'choose a menu item by path, e.g. "File > Export…", in the background; a live-change item is refused: use confirm_menu', props: { bundle, path: S('Menu > Item > Subitem') }, req: ['bundle', 'path'] },
  type: { verb: 'type', d: 'type text into the app\'s focused field, posted to that app only; prefer set_value; a line break is refused (it submits): use confirm_key return', props: { bundle, text: S('the text') }, req: ['bundle', 'text'] },
  key: { verb: 'key', d: 'one named key with modifiers (tab, escape, arrows, cmd+…); Enter and Space are refused (they submit or press): use confirm_key', props: { bundle, combo: S('e.g. tab, shift+tab, escape, down') }, req: ['bundle', 'combo'] },
  shortcuts_list: { verb: 'shortcuts', d: 'the operator\'s Shortcuts, by name', props: {}, req: [] },
  confirm_press: { verb: 'action', confirm: true, fixed: { action: 'AXPress' }, d: 'press a live-change control (Save, Send, Delete…) the operator approves in the dialog', props: { bundle, ref, gen, expect }, req: ['bundle', 'ref', 'expect'] },
  confirm_set_value: { verb: 'set-value', confirm: true, d: 'set the value of a live-change control (a switch or field whose label is Delete, Publish…) the operator approves', props: { bundle, ref, gen, expect, value: S('the new value') }, req: ['bundle', 'ref', 'value', 'expect'] },
  confirm_menu: { verb: 'menu', confirm: true, d: 'choose a live-change menu item the operator approves', props: { bundle, path: S('Menu > Item') }, req: ['bundle', 'path'] },
  confirm_key: { verb: 'key', confirm: true, d: 'press Enter, Space or another submitting key the operator approves', props: { bundle, combo: S('e.g. return, space') }, req: ['bundle', 'combo'] },
  script: { verb: 'script', confirm: true, d: 'run AppleScript or JXA in the helper (the operator approves each run); the general controller for scriptable apps',
    props: { source: S('the script'), language: S('applescript (default) or javascript') }, req: ['source'] },
  shortcut_run: { verb: 'shortcuts', confirm: true, d: 'run one of the operator\'s Shortcuts by name (the operator approves each run)', props: { name: S('the Shortcut name'), input: S('optional input text') }, req: ['name'] },
};

// A confirm tool runs only behind an ask rule, so the operator's dialog is what passes --confirm (D-94's shape).
function askRule(tool: string): boolean {
  try {
    const s = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude', 'settings.json'), 'utf8'));
    return (s?.permissions?.ask ?? []).includes(`mcp__harbor_desktop__${tool}`);
  } catch { return false; }
}

function call(name: string, input: Record<string, unknown>): { text: string; isError: boolean } {
  const t = TOOLS[name];
  if (!t) return { text: `unknown tool ${name}`, isError: true };
  if (t.confirm && !askRule(name)) {
    return { text: `${name} refused: no permissions.ask rule for mcp__harbor_desktop__${name} in ~/.claude/settings.json, so no dialog would ask the operator`, isError: true };
  }
  const args = { ...input, ...(t.fixed ?? {}) };
  delete (args as Record<string, unknown>).confirmed;
  const argv = [CLI, t.verb, JSON.stringify(args)].concat(t.confirm ? ['--confirm'] : []);
  const r = spawnSync('sh', argv, { encoding: 'utf8', timeout: 60_000, stdio: ['ignore', 'pipe', 'pipe'] });
  const out = (r.stdout || '').trim(), err = (r.stderr || '').trim();
  let text = out || err || `exit ${r.status}`;
  try { const j = JSON.parse(out); text = j.tree ? `${j.tree}\n\ngen=${j.gen} nodes=${j.nodes}${j.truncated ? ' TRUNCATED' : ''}` : JSON.stringify(j, null, 1); } catch { /* not JSON: pass through */ }
  return { text, isError: r.status !== 0 };
}

function reply(id: unknown, result: unknown) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n'); }
function fail(id: unknown, code: number, message: string) { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }) + '\n'); }

let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk: string) => {
  buf += chunk;
  let i: number;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!line) continue;
    let m: any; try { m = JSON.parse(line); } catch { fail(null, -32700, 'parse error'); continue; }
    if (m.id === undefined) continue;  // notifications
    if (m.method === 'initialize') reply(m.id, { protocolVersion: m.params?.protocolVersion ?? '2024-11-05', capabilities: { tools: {} }, serverInfo: { name: 'harbor_desktop', version: '1' } });
    else if (m.method === 'tools/list') reply(m.id, { tools: Object.entries(TOOLS).map(([name, t]) => ({ name, description: t.d, inputSchema: { type: 'object', properties: t.props, required: t.req, additionalProperties: false } })) });
    else if (m.method === 'tools/call') { const r = call(m.params?.name, m.params?.arguments ?? {}); reply(m.id, { content: [{ type: 'text', text: r.text }], isError: r.isError }); }
    else if (m.method === 'ping') reply(m.id, {});
    else fail(m.id, -32601, `method not found: ${m.method}`);
  }
});
