#!/usr/bin/env bun
// fake-daemon.ts (harbor#1421) — a stand-in for @playwright/cli's session daemon, for tests/access/chrome/session.test.sh.
// INTERPRETER EXCEPTION: bun, because it must speak the daemon's newline-framed JSON on a unix socket, as the real one does.
//
//   bun fake-daemon.ts <socket> <ctl dir> <snapshot file>
//
// Every request is logged to <ctl>/calls as `verb args --opt=v`. Behaviour is switched by files in <ctl>, read per request, so a
// suite changes it with `: > $CTL/blank`: blank, hidden, eval_fail, tablist_fail, fail, upload_denied, late_blank, xerr (holds a log path),
// page_url (holds a URL), delay_ms (holds a number). The shapes are agent-stub.sh's, which copied the real CLI's (0.1.22).
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as path from 'node:path';

const [sock, ctl, snap] = process.argv.slice(2);
const flag = (n: string) => fs.existsSync(path.join(ctl, n));
const val = (n: string) => { try { return fs.readFileSync(path.join(ctl, n), 'utf8').trim(); } catch { return ''; } };

function reply(args: any, cwd: string, raw: boolean): { isError: boolean; text: string } {
  const [verb, ...pos] = args._ as string[];
  const opts = Object.entries(args).filter(([k]) => k !== '_').map(([k, v]) => (v === true ? `--${k}` : `--${k}=${v}`));
  fs.appendFileSync(path.join(ctl, 'calls'), [verb, ...pos, ...opts].join(' ') + (raw ? ' [raw]' : '') + '\n');
  if (verb === 'snapshot') {
    if (args.filename) { fs.copyFileSync(snap, path.join(cwd, args.filename)); return { isError: false, text: `### Snapshot\n[Snapshot](${args.filename})` }; }
    return { isError: false, text: '### Snapshot' };
  }
  if (verb === 'eval') {
    if (flag('eval_fail')) return { isError: true, text: 'Error: Execution context was destroyed' };
    const late = flag('late_blank') && flag('late_blank_now');
    if (flag('hidden')) return { isError: false, text: '"{\\"visibility\\":\\"hidden\\",\\"host\\":\\"business.facebook.com\\",\\"blank\\":false}"' };
    if (flag('blank') || late) return { isError: false, text: '"{\\"host\\":\\"\\",\\"blank\\":true}"' };
    return { isError: false, text: '"{\\"visibility\\":\\"visible\\",\\"host\\":\\"business.facebook.com\\",\\"blank\\":false}"' };
  }
  if (verb === 'tab-list') {
    if (flag('tablist_fail')) return { isError: true, text: 'Error: Target closed' };
    const blank = flag('blank') || (flag('late_blank') && flag('late_blank_now'));
    const url = blank ? 'about:blank' : (flag('page_url') ? val('page_url') : 'https://business.facebook.com/');
    let t = `STUB pwd=${cwd} args=tab-list\n- 0: (current) [Page](${url})`;
    if (flag('token_url')) t += '\n- 1: [Welcome](chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws&token=SEKRET99)';
    return { isError: false, text: t };
  }
  if (verb === 'fill' && flag('late_blank')) { try { fs.rmSync(path.join(ctl, 'late_blank_now')); } catch { /* none */ } setTimeout(() => fs.writeFileSync(path.join(ctl, 'late_blank_now'), ''), 300); }
  if (verb === 'upload' && flag('upload_denied')) return { isError: true, text: 'fileChooser.setFiles: Protocol error (DOM.setFileInputFiles): {"code":-32000,"message":"Not allowed"}' };
  if (verb === 'goto' && flag('xerr')) {
    fs.appendFileSync(val('xerr'), 'pw:mcp:error Error: Cannot access a chrome-extension:// URL of different extension\n');
    return { isError: true, text: 'Error: Target page, context or browser has been closed' };
  }
  if (verb !== 'snapshot' && flag('fail')) return { isError: true, text: 'TimeoutError: Timeout 5000ms exceeded.' };
  let text = `STUB pwd=${cwd} args=${[verb, ...pos, ...opts].join(' ')}`;
  if (['goto', 'click', 'reload'].includes(verb) && flag('page_url')) text += `\n- Page URL: ${val('page_url')}`;
  return { isError: false, text };
}

fs.rmSync(sock, { force: true });
net.createServer((s) => {
  fs.appendFileSync(path.join(ctl, 'conns'), 'c\n');   // one line per connection: the suite counts them
  let buf = '';
  s.setEncoding('utf8');
  s.on('data', (d: string) => {
    buf += d;
    let i: number;
    while ((i = buf.indexOf('\n')) >= 0) {
      const m = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1);
      const out = () => s.write(JSON.stringify({ id: m.id, result: reply(m.params.args, m.params.cwd, !!m.params.raw) }) + '\n');
      const delay = Number(val('delay_ms') || 0);
      if (delay && !['tab-list', 'eval', 'snapshot'].includes(m.params.args._[0])) setTimeout(out, delay); else out();   // an action is slow, a probe is not
    }
  });
  s.on('error', () => {});
}).listen(sock, () => fs.writeFileSync(path.join(ctl, 'ready'), ''));
