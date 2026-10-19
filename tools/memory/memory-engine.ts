// memory · the engine CLI (harbor#6 — workstream D, D1).
//
// The ONLY file here with argv parsing and stdout formatting. Every algorithm
// lives in a sibling module and is imported, so the ranker and the graph can be
// exercised directly by the test without going through a process boundary.
//
// NOT THE FRONT DOOR. `bin/memory.sh` is what an operator runs and what
// CONTRACTS/cli.md classifies; it decides whether this engine is reachable at
// all and falls back to grep when Bun is absent (D7's third degradation). This
// file may therefore assume Bun exists — nothing else in Harbor may.
//
// Every invocation rebuilds the corpus, the postings and the graph from the
// markdown and then exits. That is not a performance oversight: it is
// CONTRACTS/memory-format.md's "rebuilt in-memory at query time. No DB is the
// source of truth", and D3's done-when — delete every index and retrieval is
// unchanged — is true here by construction, because there is no index to delete.
import { parseArgs } from "node:util";
import { walkCorpus } from "./store.ts";
import { buildIndex, search } from "./bm25.ts";
import { buildGraph, traverse } from "./graph.ts";

const SCHEMA_VERSION = 1;

function defaultRoot(): string {
  const explicit = process.env.HARBOR_MEMORY_ROOT;
  if (explicit && explicit.length > 0) return explicit;
  const cfg = process.env.CLAUDE_CONFIG_DIR;
  if (cfg && cfg.length > 0) return `${cfg}/MEMORY`;
  return `${process.env.HOME ?? "."}/.claude/MEMORY`;
}

const USAGE = `memory-engine (harbor#6) — on-demand L0 memory retrieval

  bun tools/memory/memory-engine.ts search <terms...> [--root DIR] [--limit N] [--json]
  bun tools/memory/memory-engine.ts graph  <slug>     [--root DIR] [--depth N] [--json]
  bun tools/memory/memory-engine.ts stats             [--root DIR] [--json]

Reads markdown only. Writes nothing, anywhere.`;

function main(argv: string[]): number {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: {
        root: { type: "string" },
        limit: { type: "string" },
        depth: { type: "string" },
        json: { type: "boolean", default: false },
        help: { type: "boolean", default: false },
      },
    });
  } catch (err) {
    console.error(`memory-engine: ${(err as Error).message}`);
    console.error(USAGE);
    return 2;
  }
  const { values, positionals } = parsed;
  if (values.help || positionals.length === 0) {
    console.log(USAGE);
    return positionals.length === 0 && !values.help ? 2 : 0;
  }

  const root = (values.root as string | undefined) ?? defaultRoot();
  const verb = positionals[0];
  const rest = positionals.slice(1);
  const asJson = values.json === true;

  const corpus = walkCorpus(root);

  // An empty store is a legitimate state — a fresh machine, a scope with no
  // notes yet — and it is NOT an error. Exiting non-zero here would make the
  // first run of a brand-new install look broken.
  if (verb === "stats") {
    const index = buildIndex(corpus);
    const graph = buildGraph(corpus);
    if (asJson) {
      console.log(
        JSON.stringify({
          schema_version: SCHEMA_VERSION,
          root,
          notes: corpus.notes.length,
          terms: index.df.size,
          avg_length: Number(index.avgLen.toFixed(4)),
          nodes: graph.nodes.size,
          edges: graph.edgeCount,
          dangling: graph.dangling.length,
          collisions: corpus.collisions.length,
          unreadable: corpus.unreadable.length,
        }),
      );
    } else {
      console.log(`root      ${root}`);
      console.log(`notes     ${corpus.notes.length}`);
      console.log(`terms     ${index.df.size}`);
      console.log(`nodes     ${graph.nodes.size}`);
      console.log(`edges     ${graph.edgeCount}`);
      console.log(`dangling  ${graph.dangling.length}`);
      console.log(`collision ${corpus.collisions.length}`);
    }
    return 0;
  }

  if (verb === "search") {
    if (rest.length === 0) {
      console.error("memory-engine: search needs at least one term");
      return 2;
    }
    const limitRaw = values.limit as string | undefined;
    const limit = limitRaw === undefined ? 0 : Number.parseInt(limitRaw, 10);
    if (limitRaw !== undefined && (!Number.isFinite(limit) || limit < 0)) {
      console.error(`memory-engine: --limit expects a non-negative integer, got '${limitRaw}'`);
      return 2;
    }
    const hits = search(corpus, rest.join(" "), { limit });
    if (asJson) {
      console.log(
        JSON.stringify({
          schema_version: SCHEMA_VERSION,
          tier: "bm25",
          root,
          query: rest.join(" "),
          count: hits.length,
          results: hits.map((h) => ({
            slug: h.slug,
            path: h.relPath,
            title: h.title,
            score: Number(h.score.toFixed(6)),
            excerpt: h.excerpt,
          })),
        }),
      );
      return 0;
    }
    for (const h of hits) {
      console.log(`${h.score.toFixed(3)}  ${h.slug}  (${h.relPath})`);
      if (h.excerpt.length > 0) console.log(`       ${h.excerpt}`);
    }
    console.log(`memory: ${hits.length} result(s), tier bm25`);
    return 0;
  }

  if (verb === "graph") {
    if (rest.length === 0) {
      console.error("memory-engine: graph needs a slug");
      return 2;
    }
    const depthRaw = values.depth as string | undefined;
    const depth = depthRaw === undefined ? 1 : Number.parseInt(depthRaw, 10);
    if (!Number.isFinite(depth) || depth < 0) {
      console.error(`memory-engine: --depth expects a non-negative integer, got '${depthRaw}'`);
      return 2;
    }
    const graph = buildGraph(corpus);
    const steps = traverse(graph, rest[0], depth);
    if (asJson) {
      console.log(
        JSON.stringify({
          schema_version: SCHEMA_VERSION,
          root,
          start: rest[0],
          found: steps.length > 0,
          depth,
          steps: steps.map((s) => ({ slug: s.slug, path: s.relPath, title: s.title, distance: s.distance })),
        }),
      );
      return 0;
    }
    if (steps.length === 0) {
      console.log(`memory: no note with slug '${rest[0]}' — nothing to traverse`);
      return 0;
    }
    for (const s of steps) console.log(`${s.distance}  ${s.slug}  (${s.relPath})`);
    console.log(`memory: ${steps.length} node(s) within depth ${depth}, tier graph`);
    return 0;
  }

  console.error(`memory-engine: unknown verb '${verb}'`);
  console.error(USAGE);
  return 2;
}

// Guarded so the modules can be imported by the test without the CLI running.
if (import.meta.main) {
  process.exit(main(process.argv.slice(2)));
}

export { main };
