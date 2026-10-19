// memory · the entity graph and its traversal (harbor#6 — workstream D, D1).
//
// A node is a note; an edge is a link one note declares to another, in either
// of the two canonical dialects CONTRACTS/memory-format.md allows — a
// [[wikilink]] in the body, or a `related:` entry in the frontmatter. Nothing
// is inferred. Upstream's MemoryGraph.ts:230-267 additionally synthesises edges
// from IDF-weighted shared-token cosine similarity, which invents relationships
// the operator never wrote; that is a retrieval feature wearing a graph's
// clothes, and BM25 already covers it. What is written is what is linked.
//
// TRAVERSAL IS UNDIRECTED, on purpose. "What else is near this note" is the
// question the graph is asked, and a note nobody links FROM is not less related
// to the notes that link TO it. Direction is preserved in `out` for anything
// that needs it; BFS walks `adj`.
import type { Corpus } from "./store.ts";

export interface DanglingRef {
  from: string;
  fromPath: string;
  target: string;
  line: number;
  dialect: "wikilink" | "frontmatter";
}

export interface GraphNode {
  slug: string;
  relPath: string;
  title: string;
}

export interface Graph {
  nodes: Map<string, GraphNode>;
  out: Map<string, Set<string>>;
  adj: Map<string, Set<string>>;
  dangling: DanglingRef[];
  edgeCount: number;
}

export interface Step {
  slug: string;
  title: string;
  relPath: string;
  distance: number;
}

// A link target is written by a human, so it is normalised before resolution: a
// trailing `.md`, a leading `./`, a directory prefix and surrounding whitespace
// all appear in real stores and none of them means a different note.
export function normalizeTarget(target: string): string {
  let t = target.trim();
  const hash = t.indexOf("#");
  if (hash >= 0) t = t.slice(0, hash);
  t = t.replace(/\.md$/i, "");
  const slash = t.lastIndexOf("/");
  if (slash >= 0) t = t.slice(slash + 1);
  return t.trim().toLowerCase();
}

export function buildGraph(corpus: Corpus): Graph {
  const nodes = new Map<string, GraphNode>();
  const byLower = new Map<string, string>();
  for (const note of corpus.notes) {
    if (nodes.has(note.slug)) continue; // collisions: first wins, store reports them
    nodes.set(note.slug, { slug: note.slug, relPath: note.relPath, title: note.title });
    byLower.set(note.slug.toLowerCase(), note.slug);
  }

  const out = new Map<string, Set<string>>();
  const adj = new Map<string, Set<string>>();
  const dangling: DanglingRef[] = [];
  const link = (m: Map<string, Set<string>>, a: string, b: string) => {
    const s = m.get(a);
    if (s) s.add(b);
    else m.set(a, new Set([b]));
  };

  for (const note of corpus.notes) {
    for (const l of note.links) {
      const resolved = byLower.get(normalizeTarget(l.target));
      if (resolved === undefined) {
        dangling.push({
          from: note.slug,
          fromPath: note.relPath,
          target: l.target,
          line: l.line,
          dialect: l.dialect,
        });
        continue;
      }
      if (resolved === note.slug) continue; // a self-link is not an edge
      link(out, note.slug, resolved);
      link(adj, note.slug, resolved);
      link(adj, resolved, note.slug);
    }
  }

  dangling.sort(
    (a, b) => (a.fromPath < b.fromPath ? -1 : a.fromPath > b.fromPath ? 1 : a.line - b.line),
  );
  let edgeCount = 0;
  for (const s of out.values()) edgeCount += s.size;
  return { nodes, out, adj, dangling, edgeCount };
}

// Breadth-first, nearest first, ties broken by slug so the output is stable
// across runs. Depth 0 returns the start note alone.
export function traverse(graph: Graph, start: string, depth: number): Step[] {
  const origin = graph.nodes.get(start);
  if (origin === undefined) return [];
  const seen = new Set<string>([start]);
  const steps: Step[] = [{ slug: start, title: origin.title, relPath: origin.relPath, distance: 0 }];
  let frontier = [start];
  for (let d = 1; d <= depth; d++) {
    const next: string[] = [];
    for (const slug of frontier) {
      const neighbours = [...(graph.adj.get(slug) ?? [])].sort();
      for (const n of neighbours) {
        if (seen.has(n)) continue;
        seen.add(n);
        next.push(n);
        const node = graph.nodes.get(n);
        if (node) steps.push({ slug: n, title: node.title, relPath: node.relPath, distance: d });
      }
    }
    if (next.length === 0) break;
    frontier = next;
  }
  return steps;
}
