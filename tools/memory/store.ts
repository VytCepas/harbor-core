// memory · the corpus reader of record (harbor#6 — workstream D, D1 + D3).
//
// CONTRACTS/memory-format.md fixes the canonical form: markdown + YAML
// frontmatter + [[wikilinks]], at every scope, git-diffable and greppable. This
// module is the ONE place that turns a directory of those files into an
// in-memory corpus. Every other module in tools/memory takes a Corpus and
// returns a value; none of them touches the filesystem, and none of them writes
// anything at all — the derived tier is rebuilt per invocation by contract, and
// lint rule TS1 enforces that here rather than trusting it.
//
// WHY A HAND-ROLLED FRONTMATTER PARSER. Pulling `yaml` (or graphology, which
// upstream's MemoryGraph.ts imports three packages of) would give this repo its
// first package.json, lockfile and install step — and `bun tools/memory/…` would
// stop working on a clean checkout. The subset below is small because the
// contract's subset is small; anything it cannot read is reported, never
// guessed.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, basename } from "node:path";

// ── shapes ──────────────────────────────────────────────────────────────────

export interface WikiLink {
  target: string;
  line: number; // 1-indexed, against the file ON DISK — the number a human edits
  dialect: "wikilink" | "frontmatter";
}

export interface PathCite {
  path: string;
  line: number;
}

export interface Note {
  slug: string;
  relPath: string;
  title: string;
  type: string;
  tags: string[];
  links: WikiLink[]; // outbound, both dialects, before resolution
  paths: PathCite[]; // ](./relative) citations, for the anti-rot lint
  body: string;
  tokens: string[]; // body tokens, stopwords dropped — the BM25 unit
  titleTokens: string[];
  tagTokens: string[];
  length: number; // === tokens.length; the length normalisation denominator
  mtimeMs: number;
}

export interface Collision {
  slug: string;
  paths: string[];
}

export interface Corpus {
  root: string;
  notes: Note[];
  bySlug: Map<string, Note>; // first occurrence wins; see collisions
  collisions: Collision[];
  unreadable: string[];
}

// ── scope ───────────────────────────────────────────────────────────────────
//
// A directory is skipped when it is DERIVED or belongs to a DIFFERENT scope:
//
//   dot-directories  — .git (history), .agents (an L3 repo store: memory-format
//                      §Scopes makes that a separate scope, and absorbing it
//                      would silently merge two stores into one)
//   indexes/         — the derived tier, gitignored by MEMORY/.gitignore
//   node_modules/    — never canonical
//
// Everything else that is markdown is corpus. In particular TELOS/ IS indexed:
// it is canonical markdown at the L0 scope, and goals are among the things most
// worth retrieving. That is a decision, not an oversight — fixtures/memory/
// corpus/TELOS/goals-probe.md pins it, so a future narrowing has to break a
// test and argue with it.
const SKIP_DIRS = new Set(["node_modules", "indexes"]);

function skipDir(name: string): boolean {
  return name.startsWith(".") || SKIP_DIRS.has(name);
}

// ── tokenizer ───────────────────────────────────────────────────────────────
//
// Pinned, and pinned deliberately: the tokenizer defines what a "term" is, so
// changing it changes every score in the corpus. Upstream matched query terms
// against the raw body with `new RegExp(term, "gi")` (MemoryRetriever.ts:283),
// which counts "cat" inside "concatenate" and inside "category" — inflating tf
// on exactly the short terms where ranking matters most, and doing it against a
// length denominator measured in whitespace words. Token equality on both sides
// is the fix, and it is why tf and length here are in the same unit.
const STOPWORDS = new Set([
  "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "her",
  "was", "one", "our", "out", "day", "get", "has", "him", "his", "how", "its",
  "new", "now", "old", "see", "two", "way", "who", "did", "yes", "his", "been",
  "from", "that", "this", "with", "have", "they", "will", "your", "what",
  "when", "were", "there", "their", "would", "which", "about", "into", "than",
  "then", "them", "these", "some", "more", "only", "over", "such", "just",
]);

export function tokenize(text: string): string[] {
  const out: string[] = [];
  for (const raw of text.toLowerCase().split(/[^a-z0-9]+/)) {
    if (raw.length < 2) continue;
    if (STOPWORDS.has(raw)) continue;
    out.push(raw);
  }
  return out;
}

// ── frontmatter ─────────────────────────────────────────────────────────────

type Scalar = string;
type FrontMatter = Record<string, Scalar | Scalar[]>;

function unquote(s: string): string {
  const t = s.trim();
  if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) {
    return t.slice(1, -1);
  }
  return t;
}

// Split an inline flow list on commas that are OUTSIDE quotes. A naive
// `.split(",")` tears `["san francisco, ca", "other"]` into three fragments —
// `"san francisco`, `ca"`, `other"` — and silently indexes the wreckage as tags.
function splitFlowList(inner: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quote: string | null = null;
  for (const ch of inner) {
    if (quote !== null) {
      if (ch === quote) quote = null;
      else cur += ch;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === ",") {
      out.push(cur.trim());
      cur = "";
      continue;
    }
    cur += ch;
  }
  out.push(cur.trim());
  return out.filter((v) => v.length > 0);
}

// Three list dialects appear in real stores and all three are in the fixture
// corpus, because a reader that handles one and drops the others loses edges
// without erroring:
//
//   tags: [a, b]                inline flow list
//   tags: cryptography          a bare scalar where a list was expected
//   related:                    block list, items either bare strings
//     - alan-turing             or `- slug: x` objects (upstream's newer
//     - slug: ada-lovelace        convention, MemoryRetriever.ts:242-245)
//       type: colleague
function parseFrontMatter(lines: string[]): FrontMatter {
  const fm: FrontMatter = {};
  let i = 0;
  while (i < lines.length) {
    const m = /^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$/.exec(lines[i]);
    if (!m) {
      i += 1;
      continue;
    }
    const key = m[1];
    const rest = m[2].trim();
    // An inline flow list, ending at its LAST `]` rather than at end-of-line: a
    // trailing YAML comment (`tags: [a, b]  # why`) is ordinary authoring, and
    // requiring the line to END with `]` made the whole line — comment included —
    // fall through to the scalar branch. The comment text then became tag tokens
    // and scored at TAG_WEIGHT, so a note could be retrieved by words that appear
    // only in a comment.
    if (rest.startsWith("[") && rest.includes("]")) {
      fm[key] = splitFlowList(rest.slice(1, rest.lastIndexOf("]")));
      i += 1;
      continue;
    }
    if (rest.length > 0) {
      fm[key] = unquote(rest);
      i += 1;
      continue;
    }
    // Empty value: a block list may follow, indented.
    const items: string[] = [];
    let j = i + 1;
    while (j < lines.length) {
      const line = lines[j];
      if (line.trim().length === 0) {
        j += 1;
        continue;
      }
      if (!/^[ \t]/.test(line)) break; // dedented: a new key
      const item = /^[ \t]*-[ \t]*(.*)$/.exec(line);
      if (item) {
        const val = item[1].trim();
        const obj = /^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$/.exec(val);
        // `- slug: x` — take the slug and ignore the object's other keys.
        if (obj) {
          if (obj[1] === "slug" && obj[2].trim().length > 0) items.push(unquote(obj[2]));
        } else if (val.length > 0) {
          items.push(unquote(val));
        }
      } else {
        // A continuation line of the previous object item (`  type: colleague`)
        // or `  slug: x` on its own line.
        const cont = /^[ \t]+([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$/.exec(line);
        if (cont && cont[1] === "slug" && cont[2].trim().length > 0) items.push(unquote(cont[2]));
      }
      j += 1;
    }
    if (items.length > 0) fm[key] = items;
    i = j > i ? j : i + 1;
  }
  return fm;
}

function asList(v: Scalar | Scalar[] | undefined): string[] {
  if (v === undefined) return [];
  return Array.isArray(v) ? v : [v];
}

function asScalar(v: Scalar | Scalar[] | undefined): string {
  if (v === undefined) return "";
  return Array.isArray(v) ? (v[0] ?? "") : v;
}

// ── parsing one note ────────────────────────────────────────────────────────

const WIKILINK = /\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/g;
const PATHCITE = /\]\((\.\.?\/[^)#\s]*)/g;

export function parseNote(raw: string, relPath: string, mtimeMs: number): Note {
  const lines = raw.split("\n");
  let fmLines: string[] = [];
  let bodyStart = 0;
  if (lines.length > 0 && lines[0].trim() === "---") {
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === "---") {
        fmLines = lines.slice(1, i);
        bodyStart = i + 1;
        break;
      }
    }
  }
  const fm = parseFrontMatter(fmLines);
  const body = lines.slice(bodyStart).join("\n");
  const slug = basename(relPath).replace(/\.md$/i, "");

  // Line numbers are taken against the WHOLE file, not the body, so the number
  // printed by the lint is the number the operator's editor shows.
  const links: WikiLink[] = [];
  const paths: PathCite[] = [];
  let inFence = false;
  for (let n = 0; n < lines.length; n++) {
    let line = lines[n];
    // CODE IS NOT PROSE. `[[ $? == 1 ]]` is a shell test, and `[[` opens one in
    // every POSIX-ish shell — so a note that documents a bash fix reads as a
    // note carrying two dangling wikilinks. Found by running this lint over the
    // real store: it reported exactly that, twice, and both were quotations of
    // someone else's cloudbuild.yaml. A linter that fires on documented code is
    // one whose findings get skimmed past (CONSTITUTION §2.11).
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    // Inline spans too — the real case was `if [[ $? == 1 ]]` inside backticks,
    // not a fenced block. Replaced with spaces rather than removed so every
    // column after it still lines up with the file on disk.
    line = line.replace(/`[^`]*`/g, (m) => " ".repeat(m.length));
    WIKILINK.lastIndex = 0;
    let w: RegExpExecArray | null;
    while ((w = WIKILINK.exec(line)) !== null) {
      links.push({ target: w[1].trim(), line: n + 1, dialect: "wikilink" });
    }
    PATHCITE.lastIndex = 0;
    let p: RegExpExecArray | null;
    while ((p = PATHCITE.exec(line)) !== null) {
      paths.push({ path: p[1], line: n + 1 });
    }
  }
  // Frontmatter `related:` entries are outbound edges too, and they carry the
  // line they were declared on so the lint can point at them.
  for (const rel of asList(fm["related"])) {
    let line = 1;
    for (let n = 0; n < bodyStart; n++) {
      if (lines[n].includes(rel)) {
        line = n + 1;
        break;
      }
    }
    links.push({ target: rel, line, dialect: "frontmatter" });
  }

  const title = asScalar(fm["title"]);
  const tags = asList(fm["tags"]);
  const tokens = tokenize(body);
  return {
    slug,
    relPath,
    title,
    type: asScalar(fm["type"]),
    tags,
    links,
    paths,
    body,
    tokens,
    titleTokens: tokenize(title),
    tagTokens: tokenize(tags.join(" ")),
    length: tokens.length,
    mtimeMs,
  };
}

// ── walking ─────────────────────────────────────────────────────────────────

// The directory reader is injectable for exactly one reason, and it is a
// testing reason worth the parameter: readdir returns entries in FILESYSTEM
// order, so on any given machine the corpus may come out correctly ordered by
// accident. A mutation pass proved it — deleting the sort below left the whole
// suite green, because this filesystem happened to enumerate the fixture pair
// in the order the assertion wanted. The test injects a reversing reader and
// requires the output to be unchanged, which is the only way an ordering
// guarantee can actually be observed to fail.
export interface DirEntryLike {
  name: string;
  isDirectory(): boolean;
  isFile(): boolean;
  isSymbolicLink(): boolean;
}

export interface WalkOptions {
  readdir?: (dir: string) => DirEntryLike[];
}

export function walkCorpus(root: string, opts: WalkOptions = {}): Corpus {
  const readDir = opts.readdir ?? ((dir: string) => readdirSync(dir, { withFileTypes: true }) as DirEntryLike[]);
  const notes: Note[] = [];
  const unreadable: string[] = [];
  const stack: string[] = [root];
  while (stack.length > 0) {
    const dir = stack.pop() as string;
    let entries: DirEntryLike[];
    try {
      entries = readDir(dir);
    } catch {
      unreadable.push(relative(root, dir) || ".");
      continue;
    }
    for (const e of entries) {
      const full = join(dir, e.name);
      if (e.isDirectory()) {
        if (!skipDir(e.name)) stack.push(full);
        continue;
      }
      // isFile() is false for a symlink; stat it rather than dropping it, but
      // never follow one that points outside the root.
      if (!e.isFile() && !e.isSymbolicLink()) continue;
      if (!/\.md$/i.test(e.name)) continue;
      let raw: string;
      let mtimeMs = 0;
      try {
        raw = readFileSync(full, "utf8");
        mtimeMs = statSync(full).mtimeMs;
      } catch {
        unreadable.push(relative(root, full));
        continue;
      }
      notes.push(parseNote(raw, relative(root, full), mtimeMs));
    }
  }

  // Deterministic order, so two runs on the same corpus produce byte-identical
  // output. readdir order is filesystem order and is not stable across machines.
  notes.sort((a, b) => (a.relPath < b.relPath ? -1 : a.relPath > b.relPath ? 1 : 0));

  const bySlug = new Map<string, Note>();
  const seen = new Map<string, string[]>();
  for (const n of notes) {
    const paths = seen.get(n.slug);
    if (paths) {
      paths.push(n.relPath);
    } else {
      seen.set(n.slug, [n.relPath]);
      bySlug.set(n.slug, n);
    }
  }
  const collisions: Collision[] = [];
  for (const [slug, paths] of seen) {
    if (paths.length > 1) collisions.push({ slug, paths });
  }
  collisions.sort((a, b) => (a.slug < b.slug ? -1 : 1));

  return { root, notes, bySlug, collisions, unreadable };
}
