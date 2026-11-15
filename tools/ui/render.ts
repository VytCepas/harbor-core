// Server-rendered HTML for the console (harbor#738). Every dynamic string goes through esc(); nothing is built with innerHTML on the client
// except fragments this file produced. Tokens are flow UI's DESIGN.md (dense dark instrument panel, healthy is silent).
import { displayCmd, TABS, type Panel, type Result } from "./sources.ts";
import { obligationsBody } from "./obligations.ts";

export const esc = (s: unknown) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"); // guard:escape

export interface PanelState { running: boolean; result?: Result }
const stamp = (t: number) => new Date(t).toLocaleString("sv-SE");
const MAX_LINES = 120;

function lineClass(l: string) {
  if (/^\s*(FAIL|VIOLATION)\b/.test(l)) return "bad";
  if (/^\s*WARN\b/.test(l)) return "warn";
  return "";
}
function textBody(r: Result, quiet?: RegExp) {
  const all = r.text.replace(/\n$/, "").split("\n");
  const loud = quiet ? all.filter((l) => !quiet.test(l)) : all;
  const shown = loud.slice(0, MAX_LINES).map((l) => `<span class="${lineClass(l)}">${esc(l)}</span>`).join("\n");
  const more = loud.length > MAX_LINES ? `\n<span class="muted">… ${loud.length - MAX_LINES} more lines</span>` : "";
  const folded = quiet && all.length > loud.length
    ? `<details><summary>${all.length - loud.length} healthy lines</summary><pre>${all.filter((l) => quiet.test(l)).slice(0, MAX_LINES).map(esc).join("\n")}</pre></details>` : "";
  return `<pre>${shown}${more}</pre>${folded}`;
}
function tableBody(head: string[], rows: unknown[][]) {
  const th = head.map((h) => `<th scope="col">${esc(h)}</th>`).join("");
  const tr = rows.slice(0, 200).map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("");
  return `<div class="scroll"><table><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div>`;
}
function body(p: Panel, r: Result) {
  const v = p.view;
  if (v.kind === "text") return textBody(r, v.quiet);
  if (v.kind === "obligations") return obligationsBody(r.json);
  if (v.kind === "json-table") return tableBody(v.columns.map((c) => c.label), v.rows(r.json).map((row) => v.columns.map((c) => c.get(row))));
  const rows = r.text.split("\n").filter((l) => l.startsWith("|")).map((l) => l.split("|").slice(1, -1).map((c) => c.trim().replace(/`/g, "")));
  return tableBody(v.columns.map((c) => c.label), rows.map((cells) => v.columns.map((c) => cells[c.col] ?? "")));
}

export function headline(p: Panel, st: PanelState): string {
  const r = st.result;
  if (!r) return "running";
  if (r.status === "unavailable") return "unavailable";
  const h = p.headline?.({ text: r.text, json: r.json });
  return h ?? (r.status === "ok" ? "ran ok" : `exit ${r.exit}`);
}
const tone = (st: PanelState) => (!st.result ? "idle" : st.result.status === "ok" ? "ok" : st.result.status === "problem" ? "crit" : "warn");

export function tileHtml(p: Panel, st: PanelState) {
  const t = tone(st);
  const ctx = st.result?.status === "unavailable" ? esc(st.result.reason) : esc(displayHint(p, st));
  return `<a class="tile" id="t-${esc(p.id)}" href="#p-${esc(p.id)}" data-tone="${t}"><span class="label">${esc(p.title)}</span>` +
    `<span class="value">${esc(headline(p, st))}</span><span class="ctx">${ctx}</span></a>`;
}
const displayHint = (p: Panel, st: PanelState) => (st.result ? `${st.result.status} · ${st.result.ms} ms` : p.id);

export function panelHtml(p: Panel, st: PanelState, root: string, home: string) {
  const r = st.result;
  const t = tone(st);
  const status = !r ? "running…" : r.status === "unavailable" ? `unavailable: ${r.reason}` : null;
  const ran = r ? `ran <time datetime="${new Date(r.ranAt).toISOString()}">${esc(stamp(r.ranAt))}</time> · ${r.ms} ms${r.exit === null ? "" : ` · exit ${r.exit}`}` : "not yet run";
  return `<section class="panel" id="p-${esc(p.id)}" data-tab="${esc(p.tab)}" data-tone="${t}">` +
    `<header><h2>${esc(p.title)}</h2><span class="chip" data-tone="${t}">${esc(headline(p, st))}${st.running && r ? " · refreshing" : ""}</span>` +
    `<button type="button" class="ghost" data-run="${esc(p.id)}" aria-label="Re-run ${esc(p.title)}">re-run</button></header>` +
    `<p class="src"><code>${esc(displayCmd(p, root, home))}</code><span>${ran}</span></p>` +
    (p.note ? `<p class="note">${esc(p.note)}</p>` : "") +
    (status !== null ? `<p class="status" data-tone="${t}">${esc(status)}</p>` : body(p, r!)) + `</section>`;
}

export function pageHtml(panels: readonly Panel[], states: Map<string, PanelState>, root: string, home: string, nonce: string, host: string) {
  const st = (p: Panel) => states.get(p.id) ?? { running: true };
  const nav = TABS.length > 1
    ? `<nav aria-label="Tabs">${TABS.map((t, i) => `<button type="button" data-tab-btn="${esc(t.id)}" aria-pressed="${i === 0}">${esc(t.title)}</button>`).join("")}</nav>` : "";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<meta name="referrer" content="no-referrer"><title>Harbor console</title><style nonce="${nonce}">${CSS}</style></head><body>` +
    `<main><h1>Harbor <span class="muted">console · ${esc(host)} · read-only</span></h1>` +
    `<div class="strip" id="strip">${panels.map((p) => tileHtml(p, st(p))).join("")}</div>${nav}` +
    `<div id="panels">${panels.map((p) => panelHtml(p, st(p), root, home)).join("")}</div>` +
    `<p class="foot">Every figure is derived when the page loads and names its source command. Shown only on this Mac.</p></main>` +
    `<script nonce="${nonce}">${JS}</script></body></html>`;
}

const JS = `(()=>{
const $=(s,r=document)=>r.querySelector(s), $$=(s,r=document)=>[...r.querySelectorAll(s)];
history.replaceState(null,"",location.pathname);
const tab=id=>{$$("[data-tab]").forEach(e=>e.hidden=e.dataset.tab!==id);$$("[data-tab-btn]").forEach(b=>b.setAttribute("aria-pressed",String(b.dataset.tabBtn===id)))};
$$("[data-tab-btn]").forEach(b=>b.addEventListener("click",()=>tab(b.dataset.tabBtn)));
if($("[data-tab-btn]"))tab($("[data-tab-btn]").dataset.tabBtn);
let grp="none";
const applyGrp=()=>{$$("[data-view]").forEach(e=>e.hidden=e.dataset.view!==grp);$$("[data-group-btn]").forEach(b=>b.setAttribute("aria-pressed",String(b.dataset.groupBtn===grp)))};
const swap=(id,k,html)=>{const e=document.getElementById(k+"-"+id);if(!e)return;const h=e.hidden;e.outerHTML=html;const n=document.getElementById(k+"-"+id);if(n&&k==="p")n.hidden=h;applyGrp()};
const es=new EventSource("/events");
es.addEventListener("panel",e=>{const d=JSON.parse(e.data);swap(d.id,"p",d.panel);swap(d.id,"t",d.tile)});
document.addEventListener("click",e=>{const g=e.target.closest("[data-group-btn]");if(g){grp=g.dataset.groupBtn;applyGrp();return}
const b=e.target.closest("[data-run]");if(!b)return;
fetch("/run",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({id:b.dataset.run})})});
})();`;

const CSS = `
:root{color-scheme:dark light;--background:#161821;--foreground:#F5F5F5;--card:rgba(255,255,255,.03);--muted:#1d1f2a;--muted-foreground:#a8a8a8;
--border:rgba(255,255,255,.08);--primary:#74fa90;--surface-card-opaque:color-mix(in srgb,var(--background) 97%,white);
--status-warning-fg:#fbbf24;--status-danger-fg:#f87171;--status-warning-bg:rgba(245,158,11,.1);--status-danger-bg:rgba(239,68,68,.1);
--font-sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--font-mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
--text-caption:11px;--text-xs:12px;--text-sm:13px;--text-base:14px;--text-kpi:22px}
@media (prefers-color-scheme:light){:root{--background:#FAFAFA;--foreground:#0D0D0D;--card:#FFFFFF;--muted:#F3F4F6;--muted-foreground:#5A6472;
--border:#E5E7EB;--surface-card-opaque:#FFFFFF;--status-warning-fg:#b45309;--status-danger-fg:#b91c1c;--status-warning-bg:rgba(245,158,11,.1);--status-danger-bg:rgba(239,68,68,.08)}}
*{box-sizing:border-box}body{margin:0;background:var(--background);color:var(--foreground);font:var(--text-base)/1.45 var(--font-sans)}
main{max-width:1600px;margin:0 auto;padding:16px}@media (min-width:768px){main{padding:24px}}
h1{font-size:18px;margin:0 0 16px;font-weight:600}h2{font-size:var(--text-base);margin:0;font-weight:600;flex:1}
.muted{color:var(--muted-foreground);font-weight:400;font-size:var(--text-xs)}
.strip{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:1px;background:var(--border);border:1px solid var(--border);border-radius:10px;overflow:hidden;margin-bottom:16px}
.tile{background:var(--surface-card-opaque);padding:10px 12px;display:flex;flex-direction:column;gap:2px;min-width:0;color:inherit;text-decoration:none;position:relative}
.tile:hover .label,.tile:focus-visible .label{color:var(--primary)}.tile:focus-visible{outline:2px solid var(--primary);outline-offset:-2px}
.label{font-size:var(--text-caption);text-transform:uppercase;letter-spacing:.06em;color:var(--muted-foreground)}
.value{font-size:var(--text-kpi);font-weight:600;font-variant-numeric:tabular-nums;color:var(--foreground);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ctx{font-size:var(--text-caption);color:var(--muted-foreground);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-height:1.45em}
.tile[data-tone=warn]::after,.tile[data-tone=crit]::after{content:"";position:absolute;top:12px;right:12px;width:7px;height:7px;border-radius:50%}
.tile[data-tone=warn]::after{background:var(--status-warning-fg)}.tile[data-tone=crit]::after{background:var(--status-danger-fg)}
nav{display:flex;gap:6px;margin-bottom:12px}nav button{background:var(--card);color:var(--muted-foreground);border:1px solid var(--border);border-radius:8px;padding:6px 12px;font:inherit;font-size:var(--text-sm);cursor:pointer;min-height:28px}
nav button[aria-pressed=true]{color:var(--foreground);background:var(--muted)}
#panels{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,560px),1fr));gap:12px;align-items:start}
.panel{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:12px;min-width:0}.panel[hidden]{display:none}
.panel header{display:flex;align-items:center;gap:8px}
.chip{font-size:var(--text-caption);color:var(--muted-foreground);border:1px solid var(--border);border-radius:999px;padding:1px 8px;max-width:50%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.chip[data-tone=warn]{color:var(--status-warning-fg);background:var(--status-warning-bg)}.chip[data-tone=crit]{color:var(--status-danger-fg);background:var(--status-danger-bg)}
.ghost{background:none;border:1px solid transparent;color:var(--muted-foreground);font:inherit;font-size:var(--text-caption);cursor:pointer;border-radius:6px;padding:4px 8px;min-height:28px}
.ghost:hover,.ghost:focus-visible{color:var(--primary);border-color:var(--border)}
.src{display:flex;flex-wrap:wrap;gap:4px 12px;margin:6px 0 8px;font-size:var(--text-caption);color:var(--muted-foreground)}
code,pre{font-family:var(--font-mono);font-size:var(--text-xs)}code{color:var(--foreground)}
.note{margin:0 0 8px;font-size:var(--text-xs);color:var(--muted-foreground)}
.status{margin:0;font-size:var(--text-sm);color:var(--muted-foreground)}.status[data-tone=warn]{color:var(--status-warning-fg)}
pre{margin:0;white-space:pre-wrap;overflow-wrap:anywhere;max-height:420px;overflow:auto;color:var(--muted-foreground)}
pre .bad{color:var(--status-danger-fg)}pre .warn{color:var(--status-warning-fg)}
details{margin-top:6px;font-size:var(--text-xs);color:var(--muted-foreground)}summary{cursor:pointer;min-height:24px}
.scroll{overflow:auto;max-height:420px}table{border-collapse:collapse;width:100%;font-size:var(--text-sm)}
th{position:sticky;top:0;background:var(--surface-card-opaque);text-align:left;font-size:var(--text-caption);text-transform:uppercase;letter-spacing:.06em;color:var(--muted-foreground);font-weight:500;padding:6px 8px}
td:first-child{white-space:nowrap}td{padding:6px 8px;border-top:1px solid var(--border);overflow-wrap:anywhere;vertical-align:top}
.badge{font-size:var(--text-caption);text-transform:uppercase;letter-spacing:.06em;border:1px solid var(--border);border-radius:999px;padding:0 6px;margin-right:4px;color:var(--primary)}
.badge[data-kind=overdue]{color:var(--status-danger-fg);background:var(--status-danger-bg)}
.groupnav{display:flex;gap:4px;margin:8px 0}.groupnav .ghost[aria-pressed=true]{color:var(--foreground);border-color:var(--border)}
h3{font-size:var(--text-sm);margin:12px 0 4px;font-weight:600}
.sources{list-style:none;margin:0 0 8px;padding:0;font-size:var(--text-xs);color:var(--muted-foreground)}.sources li[data-tone=warn]{color:var(--status-warning-fg)}
td.age,td.nw{white-space:nowrap}.panel[data-tab=obligations]{grid-column:1/-1}a{color:var(--primary)}
.foot{margin-top:16px;font-size:var(--text-caption);color:var(--muted-foreground)}
`;
