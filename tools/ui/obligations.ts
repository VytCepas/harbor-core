// The Obligations tab (harbor#1053): what is unfinished on the box, new first, then overdue, then oldest.
// Its ONLY input is `sh <root>/bin/status-obligations.sh show --json` (the output of `harbor status obligations --json`, contracts/cli.md),
// run from the console's own checkout and never through a PATH-resolved `harbor`. Every string in it is attacker-influenced text
// from hooks, so each one is clipped and reaches the page through esc(). Nothing here runs a command or touches a file.
import { esc } from "./render.ts";

const ACTIVE = new Set(["open", "overdue"]);
const MAX_ROWS = 200;
const MAX_CLOSED = 50;
const MAX_SOURCES = 50;
const MAX_STR = 200;                      // one field; rows x groupings multiply it, so it is the page-size bound
const MAX_LINK = 2048;
export const OB_MAX_BYTES = 8 * 1024 * 1024; // the command's whole output, checked before it is parsed
export const GROUPS = [{ id: "none", title: "flat" }, { id: "repo", title: "repo" }, { id: "kind", title: "kind" }, { id: "owner", title: "owner" }] as const;
export type GroupId = (typeof GROUPS)[number]["id"];

// What the previous page view saw, kept in this server's memory: nothing is written, so there is no state to leak or corrupt.
// A page load is a view; a re-run pushed over SSE re-renders against the SAME baseline, so rows do not stop being new mid-view.
export const views: { base: Set<string> | null; baseAt: number | null; last: { ids: Set<string>; at: number } | null } = { base: null, baseAt: null, last: null };

const isObj = (v: unknown): v is Record<string, any> => typeof v === "object" && v !== null && !Array.isArray(v);

// "" when json is the frozen shape, else why it is not. A wrong shape is unavailable, never an empty list.
export function shapeProblem(json: unknown): string {
  if (!isObj(json)) return "output is not a JSON object";
  if (!Array.isArray(json.obligations)) return "output has no obligations list";
  if (!isObj(json.sources)) return "output has no sources map";
  return "";
}
const rowsOf = (json: any): Record<string, any>[] => (Array.isArray(json?.obligations) ? json.obligations.filter(isObj) : []);
const idOf = (r: Record<string, any>) => (typeof r.id === "string" ? r.id : "");

// Called once per page view, after the sources have run. A result that did not answer leaves the baseline alone, so an outage
// is never read as "everything was closed", which would make every row new when the source came back.
export function beginView(json: unknown, now = Date.now()) {
  if (shapeProblem(json)) return;
  views.base = views.last ? views.last.ids : null;
  views.baseAt = views.last ? views.last.at : null;
  views.last = { ids: new Set(rowsOf(json).map(idOf).filter(Boolean)), at: now };
}

// The one place an href is decided. https only, then parsed and re-serialised, so what is rendered is what was parsed.
// javascript:, data:, http:, scheme-relative and relative links all come back "".
export function safeLink(link: unknown): string {
  if (typeof link !== "string" || link.length > MAX_LINK || !link.startsWith("https://")) return ""; // guard:link
  try { return new URL(link).href; } catch { return ""; }
}

const clip = (s: string) => (s.length > MAX_STR ? s.slice(0, MAX_STR) + "…" : s);
const text = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? clip(v) : "unknown");
export function ageText(s: unknown): string {
  if (typeof s !== "number" || !Number.isFinite(s) || s < 0) return "age unknown";
  if (s < 90) return `${Math.round(s)}s`;
  if (s < 5400) return `${Math.floor(s / 60)}m`;
  if (s < 172800) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

interface Row { r: Record<string, any>; isNew: boolean; overdue: boolean; age: number }
function classify(json: any): { live: Row[]; done: Record<string, any>[]; other: number } {
  const all = rowsOf(json);
  const base = views.base;
  const live = all.filter((r) => ACTIVE.has(r.state)).map((r): Row => ({
    r, isNew: base !== null && !base.has(idOf(r)), overdue: r.state === "overdue", age: typeof r.age_s === "number" && Number.isFinite(r.age_s) ? r.age_s : -1,
  }));
  live.sort((a, b) => Number(b.isNew) - Number(a.isNew) || Number(b.overdue) - Number(a.overdue) || b.age - a.age); // new, then overdue, then oldest
  const done = all.filter((r) => r.state === "closed" || r.state === "abandoned");
  return { live, done, other: all.length - live.length - done.length };
}

export function headline(json: unknown): string {
  if (shapeProblem(json)) return "unavailable";
  const { live } = classify(json);
  const down = Object.values((json as any).sources).filter((s) => !isObj(s) || s.ok !== true).length;
  const parts = [live.length > 0 ? `${live.length} listed` : down === 0 ? "none open" : "none listed"];
  const od = live.filter((x) => x.overdue).length, nw = live.filter((x) => x.isNew).length;
  if (od) parts.push(`${od} overdue`);
  if (nw) parts.push(`${nw} new`);
  if (down) parts.push(`${down} source${down === 1 ? "" : "s"} down`); // a listed count beside a dead source is not "all clear"
  return parts.join(" · ");
}

const badge = (x: Row) => (x.isNew ? `<span class="badge" data-kind="new">new</span>` : "") + (x.overdue ? `<span class="badge" data-kind="overdue">overdue</span>` : "");
function link(r: Record<string, any>) {
  const href = safeLink(r.link);
  return href ? `<a href="${esc(href)}" target="_blank" rel="noopener noreferrer">${esc(text(r.subject))}</a>` : esc(text(r.subject));
}
const rowHtml = (x: Row) => {
  const r = x.r;
  return `<tr data-state="${esc(text(r.state))}"><td>${badge(x)}</td><td class="age">${esc(ageText(r.age_s))}</td><td>${esc(text(r.title))}</td>` +
    `<td>${link(r)}</td><td class="nw">${esc(text(r.repo))}</td><td class="nw">${esc(text(r.kind))}</td><td>${esc(text(r.owner))}</td>` +
    `<td class="nw">${esc(clip(typeof r.deadline_ts === "string" && r.deadline_ts ? r.deadline_ts : "none"))}</td></tr>`;
};
const HEAD = ["", "age", "title", "link", "repo", "kind", "owner", "deadline"];
const thead = `<thead><tr>${HEAD.map((h) => `<th scope="col">${esc(h)}</th>`).join("")}</tr></thead>`;

function groupedTable(live: Row[], by: GroupId) {
  if (live.length === 0) return `<p class="status">nothing listed</p>`;
  if (by === "none") return `<div class="scroll"><table>${thead}<tbody>${live.slice(0, MAX_ROWS).map(rowHtml).join("")}</tbody></table></div>`;
  const groups = new Map<string, Row[]>();
  for (const x of live.slice(0, MAX_ROWS)) { const k = text(x.r[by]); (groups.get(k) ?? groups.set(k, []).get(k)!).push(x); }
  // Groups carrying something new or overdue come first, so the delta is not buried under a quiet repo's name.
  const order = [...groups].sort((a, b) => Math.max(...b[1].map((x) => +x.isNew * 2 + +x.overdue)) - Math.max(...a[1].map((x) => +x.isNew * 2 + +x.overdue)));
  return order.map(([k, rows]) => `<h3>${esc(by)}: ${esc(k)} <span class="muted">${rows.length}</span></h3><div class="scroll"><table>${thead}<tbody>${rows.map(rowHtml).join("")}</tbody></table></div>`).join("");
}

function sourcesHtml(json: any) {
  const entries = Object.entries(json.sources).sort((a, b) => Number(isObj(a[1]) && a[1].ok === true) - Number(isObj(b[1]) && b[1].ok === true)); // the ones that did not answer first, so the cap never hides them
  if (entries.length === 0) return `<p class="status" data-tone="warn">unavailable: the command reported no sources, so none of this is confirmed</p>`;
  const more = entries.length > MAX_SOURCES ? `<li class="muted">${entries.length - MAX_SOURCES} more sources not shown</li>` : "";
  return `<ul class="sources">${entries.slice(0, MAX_SOURCES).map(([name, s]) => {
    const ok = isObj(s) && s.ok === true;
    const reason = isObj(s) && typeof s.reason === "string" && s.reason.trim() ? s.reason : "no reason given";
    const when = isObj(s) && typeof s.ts === "string" && s.ts ? ` <span class="muted">${esc(clip(s.ts))}</span>` : "";
    return ok ? `<li data-tone="ok"><code>${esc(clip(name))}</code> ok${when}</li>`
      : `<li data-tone="warn"><code>${esc(clip(name))}</code> unavailable: ${esc(clip(reason))}${when}</li>`;
  }).join("")}${more}</ul>`;
}

// The seam for harbor#1052. A proposal is SHOWN here, as text, and nothing on this page applies one: no button, no route.
// #1052 adds its click-to-apply by replacing this one function with a button that POSTs the proposal id to a route that
// looks the row up in a table of allowlisted argv arrays, exactly as /run does for panels. Until then it returns "".
export const proposalActions = (_proposal: Record<string, any>): string => "";

function proposalsHtml(json: any) {
  const ps = Array.isArray(json.proposals) ? json.proposals.filter(isObj) : [];
  if (ps.length === 0) return `<p class="note">No proposals. They arrive with harbor#1052, and each is applied from here only through its own allowlisted command.</p>`;
  return `<ul class="proposals">${ps.slice(0, MAX_ROWS).map((p) => `<li>${esc(text(p.title))} <span class="muted">for ${esc(text(p.obligation_id))}</span>${proposalActions(p)}</li>`).join("")}</ul>`;
}

// One table per grouping, all server-rendered; the page's script only shows one of them. Testable with curl, and a page
// without script still shows the flat view.
export function obligationsBody(json: any): string {
  const { live, done, other } = classify(json);
  const sinceNote = views.baseAt === null
    ? "first view since this console started: nothing is marked new yet"
    : `new = not listed at the previous view, <time datetime="${esc(new Date(views.baseAt).toISOString())}">${esc(new Date(views.baseAt).toLocaleString("sv-SE"))}</time>`;
  const capNote = live.length > MAX_ROWS ? `<p class="note">showing the first ${MAX_ROWS} of ${live.length} listed; the rest are not shown</p>` : "";
  const nav = `<div class="groupnav" role="group" aria-label="Group by">${GROUPS.map((g, i) => `<button type="button" class="ghost" data-group-btn="${g.id}" aria-pressed="${i === 0}">${esc(g.title)}</button>`).join("")}</div>`;
  const views_ = GROUPS.map((g, i) => `<div data-view="${g.id}"${i === 0 ? "" : " hidden"}>${groupedTable(live, g.id)}</div>`).join("");
  const closed = done.length === 0 ? "" :
    `<details><summary>${done.length} closed or abandoned</summary><div class="scroll"><table><thead><tr>${["state", "title", "subject", "repo", "closed by", "closed"].map((h) => `<th scope="col">${esc(h)}</th>`).join("")}</tr></thead><tbody>` +
    done.slice(0, MAX_CLOSED).map((r) => `<tr><td>${esc(text(r.state))}</td><td>${esc(text(r.title))}</td><td>${link(r)}</td><td>${esc(text(r.repo))}</td><td>${esc(text(r.closed_by))}</td><td>${esc(text(r.closed_ts))}</td></tr>`).join("") +
    `</tbody></table></div></details>`;
  const unknownStates = other > 0 ? `<p class="note">${other} row${other === 1 ? "" : "s"} with a state this tab does not know are not shown.</p>` : "";
  const anyDown = Object.values(json.sources).some((s) => !isObj(s) || s.ok !== true);
  const warn = anyDown ? `<p class="status" data-tone="warn">A source did not answer, so this list may be incomplete. An empty list here is not a clean bill.</p>` : "";
  return `<p class="note">generated <time datetime="${esc(text(json.generated_ts))}">${esc(text(json.generated_ts))}</time> · ${sinceNote}</p>` +
    sourcesHtml(json) + warn + capNote + nav + views_ + closed + unknownStates + `<h3>Proposals</h3>` + proposalsHtml(json);
}
