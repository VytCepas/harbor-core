// memory · the engine's assertions (harbor#6 — workstream D, K3).
//
// Every Bun-dependent assertion lives here, in ONE file, and tests/memory/memory-test.sh
// invokes it as a single folded assertion. That split is deliberate: CI's
// preflight does not include bun, so a suite that needed it would either fail on
// a hosted runner or be quietly skipped — and a suite that skips itself reports
// success for work it never did.
//
// Nothing here asserts the engine against itself. The arbiter is
// fixtures/memory/expected.json, which is also what bin/memory-lint.sh is held
// to; two implementations checked against each other can drift together and
// still agree, which is the failure this arrangement exists to prevent.
import { readFileSync, readdirSync } from "node:fs";
import type { DirEntryLike } from "./store.ts";
import { walkCorpus, tokenize, parseNote } from "./store.ts";
import { buildIndex, search, idf, BM25_K1, BM25_B, TITLE_WEIGHT, TAG_WEIGHT } from "./bm25.ts";
import { buildGraph, traverse, normalizeTarget } from "./graph.ts";

const ROOT = process.env.HARBOR_MEMORY_FIXTURES ?? "fixtures/memory";
const CORPUS = `${ROOT}/corpus`;
const expected = JSON.parse(readFileSync(`${ROOT}/expected.json`, "utf8"));

let pass = 0;
let fail = 0;

function check(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass += 1;
    return;
  }
  fail += 1;
  console.error(`  FAIL: ${name}\n        want ${w}\n        got  ${g}`);
}

function ok(name: string, cond: boolean, detail = ""): void {
  if (cond) {
    pass += 1;
    return;
  }
  fail += 1;
  console.error(`  FAIL: ${name}${detail ? `\n        ${detail}` : ""}`);
}

const corpus = walkCorpus(CORPUS);
const index = buildIndex(corpus);
const graph = buildGraph(corpus);

// ── corpus shape ────────────────────────────────────────────────────────────
check("notes indexed", corpus.notes.length, expected.corpus.notes_indexed);
check("graph nodes", graph.nodes.size, expected.corpus.graph_nodes);
check("graph edges", graph.edgeCount, expected.corpus.graph_edges);
ok(
  "an L3 .agents/ store is NOT absorbed into the L0 corpus",
  !corpus.notes.some((n) => n.relPath.includes(".agents")),
  corpus.notes.map((n) => n.relPath).join(" "),
);
ok(
  "the derived indexes/ tier is not indexed",
  !corpus.notes.some((n) => n.relPath.startsWith("indexes/")),
);
ok(
  "a filename containing a space survives the walk",
  corpus.notes.some((n) => n.relPath.includes("spaced name.md")),
);
ok(
  "a note with no frontmatter is kept, not silently dropped",
  corpus.bySlug.has("no-frontmatter"),
);

// ── frontmatter dialects ────────────────────────────────────────────────────
check(
  "object-dialect related: (- slug: x) yields the edge",
  corpus.bySlug.get("ada-lovelace")?.links.map((l) => l.target),
  ["alan-turing"],
);
check(
  "scalar-dialect tags: (a bare string) is read as a one-element list",
  corpus.bySlug.get("alan-turing")?.tags,
  ["cryptography"],
);
check(
  "inline-list tags: [a, b]",
  corpus.bySlug.get("bm25-rare-term")?.tags,
  ["storage", "columnar"],
);

// ── frontmatter shapes that are not in the corpus ───────────────────────────
// Exercised through parseNote on synthetic input rather than by adding notes to
// fixtures/memory/corpus: every pinned count in expected.json is a function of
// the corpus, so growing it to test a parser branch means re-deriving df, N and
// every score. The parser is a pure function; test it as one.
{
  const withComment = parseNote(
    ["---", "title: Comment test", "tags: [alpha, beta]  # a trailing comment", "---", "body"].join("\n"),
    "synthetic/comment.md",
    0,
  );
  check("an inline list ending in a trailing YAML comment still parses as a list",
    withComment.tags, ["alpha", "beta"]);
  ok("comment text does not leak into the tag tokens",
    !withComment.tagTokens.includes("trailing") && !withComment.tagTokens.includes("comment"),
    withComment.tagTokens.join(","));

  const quotedComma = parseNote(
    ["---", "title: Quoted", 'tags: ["san francisco, ca", "other"]', "---", "body"].join("\n"),
    "synthetic/quoted.md",
    0,
  );
  check("a quoted list item containing a comma stays one item",
    quotedComma.tags, ["san francisco, ca", "other"]);

  // The sh lint is held to the same behaviour in tests/memory/memory-test.sh — the two
  // readers must agree about what counts as a link, or the shared arbiter is
  // arbitrating two different questions.
  const withCode = parseNote(
    [
      "---", "title: Documents a shell fix", "---",
      "Inline: the guard is `if [[ $? == 1 ]]` and it is wrong.",
      "",
      "```sh",
      "if [[ $? == 1 ]]; then echo hi; fi",
      "```",
      "",
      "But [[a-real-link]] in prose still counts.",
    ].join("\n"),
    "synthetic/code.md",
    0,
  );
  check("a shell test in inline code or a fence is not a wikilink",
    withCode.links.map((l) => l.target), ["a-real-link"]);

  const unclosed = parseNote(
    ["---", "title: Unclosed", "related:", "  - ghost", "", "body prose"].join("\n"),
    "synthetic/unclosed.md",
    0,
  );
  check("an UNCLOSED frontmatter block is treated as body, not frontmatter",
    unclosed.links.map((l) => l.target), []);
  check("...and its title is not read either", unclosed.title, "");
}

// ── collisions ──────────────────────────────────────────────────────────────
check(
  "slug collisions are reported, all carriers named",
  corpus.collisions,
  expected.collisions,
);

// ── dangling references, against the pinned arbiter ─────────────────────────
check(
  "dangling references match fixtures/memory/expected.json exactly",
  graph.dangling.map((d) => ({
    path: d.fromPath,
    line: d.line,
    dialect: d.dialect,
    target: d.target,
  })),
  expected.dangling,
);

// ── BM25 ────────────────────────────────────────────────────────────────────
check("k1 is pinned", BM25_K1, 1.5);
check("b is pinned", BM25_B, 0.75);
check("df('fixture') — the corpus-universal token", index.df.get("fixture"), expected.document_frequency.fixture);
check("df('parquet') — the rare token", index.df.get("parquet"), expected.document_frequency.parquet);

// IDF must be strictly positive at every df in [1, N]. The textbook form goes
// negative past df > N/2, which lets a common query term SUBTRACT score.
let negative = 0;
for (let df = 1; df <= index.n; df++) {
  const v = Math.log(1 + (index.n - df + 0.5) / (df + 0.5));
  if (v <= 0) negative += 1;
}
check("IDF is positive for every df in [1,N]", negative, 0);
ok(
  "a rare term outweighs a corpus-universal one",
  idf(index, "parquet") > idf(index, "fixture") * 10,
  `parquet=${idf(index, "parquet").toFixed(4)} fixture=${idf(index, "fixture").toFixed(4)}`,
);

for (const q of expected.queries) {
  const hits = search(corpus, q.query);
  check(`query '${q.query}' → count`, hits.length, q.count);
  check(`query '${q.query}' → top hit`, hits[0]?.slug ?? null, q.top);
}

// THE discriminating assertion, restated as a computation rather than a claim:
// re-score the corpus with the IDF factor removed — upstream's exact shape — and
// require the winner to CHANGE. If it does not, this fixture has stopped
// measuring what it was built to measure and every "BM25-ranked" claim above is
// unfalsified.
{
  const terms = tokenize(expected.queries[0].query);
  const noIdf = corpus.notes
    .map((n) => {
      const counts = new Map<string, number>();
      const add = (toks: string[], w: number) => {
        for (const t of toks) counts.set(t, (counts.get(t) ?? 0) + w);
      };
      add(n.tokens, 1);
      add(n.titleTokens, TITLE_WEIGHT);
      add(n.tagTokens, TAG_WEIGHT);
      let s = 0;
      for (const t of terms) {
        const tf = counts.get(t) ?? 0;
        if (tf <= 0) continue;
        s += (tf * (BM25_K1 + 1)) / (tf + BM25_K1 * (1 - BM25_B + BM25_B * (n.length / index.avgLen)));
      }
      return { slug: n.slug, s };
    })
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s);
  ok(
    "removing IDF changes the winner (the fixture still discriminates)",
    noIdf[0]?.slug !== undefined && noIdf[0].slug !== expected.queries[0].top,
    `without idf the winner is '${noIdf[0]?.slug}', with idf it is '${expected.queries[0].top}'`,
  );
}

// Token equality, not substring: upstream counts "cat" inside "concatenate".
ok(
  "tf is token-equality, not substring",
  tokenize("concatenate the category").every((t) => t !== "cat"),
  tokenize("concatenate the category").join(","),
);

// ── graph traversal ─────────────────────────────────────────────────────────
check(
  "BFS order matches the pinned traversal",
  traverse(graph, expected.graph_traversal.start, expected.graph_traversal.depth).map((s) => s.slug),
  expected.graph_traversal.order,
);
check("traversal from an unknown slug is empty, not an error", traverse(graph, "zznosuchslugzz", 2), []);
ok(
  "a note linking to ITSELF does not create an edge",
  (graph.out.get("graph-hub") ?? new Set()).has("graph-hub") === false,
  [...(graph.out.get("graph-hub") ?? [])].join(","),
);

// Equal scores must order by relPath, not by whatever the sort happened to do.
// Pinned because a mutation pass proved the tie-break was unreachable before
// tie-alpha/tie-beta existed: removing it left the whole suite green.
{
  const tied = search(corpus, "zztiezz");
  ok("the tie fixtures really do score identically", tied.length === 2 && tied[0].score === tied[1].score,
    tied.map((h) => `${h.slug}=${h.score}`).join(" "));
  check("equal scores break on relPath, stably", tied.map((h) => h.slug), ["tie-alpha", "tie-beta"]);

  // ...and again with the corpus order deliberately REVERSED before scoring, so
  // the assertion depends on the ranker's tie-break rather than on the walker
  // having already sorted. Both mechanisms are real; each is now observable on
  // its own, which is what stops them masking each other.
  const reversed = { ...corpus, notes: [...corpus.notes].reverse() };
  check(
    "ties still break on relPath when the corpus arrives unsorted",
    search(reversed, "zztiezz").map((h) => h.slug),
    ["tie-alpha", "tie-beta"],
  );
}

// The walker's own ordering guarantee, made observable: enumerate every
// directory backwards and require a byte-identical corpus order.
{
  const backwards = walkCorpus(CORPUS, {
    readdir: (dir) => (readdirSync(dir, { withFileTypes: true }) as DirEntryLike[]).slice().reverse(),
  });
  check(
    "corpus order does not depend on filesystem enumeration order",
    backwards.notes.map((n) => n.relPath),
    corpus.notes.map((n) => n.relPath),
  );
  check(
    "ranking does not depend on filesystem enumeration order",
    search(backwards, "fixture parquet").map((h) => h.slug),
    search(corpus, "fixture parquet").map((h) => h.slug),
  );
}
check("depth 0 returns the start note alone", traverse(graph, "graph-hub", 0).map((s) => s.slug), ["graph-hub"]);
check("a link target is normalised before resolution", normalizeTarget("../People/Ada-Lovelace.md#bio"), "ada-lovelace");

// ── determinism and the no-write contract ───────────────────────────────────
check(
  "two walks of the same corpus produce identical order",
  walkCorpus(CORPUS).notes.map((n) => n.relPath),
  corpus.notes.map((n) => n.relPath),
);
check(
  "two searches of the same corpus produce identical scores",
  search(walkCorpus(CORPUS), "fixture parquet").map((h) => h.score),
  search(corpus, "fixture parquet").map((h) => h.score),
);

// ── empty and malformed stores ──────────────────────────────────────────────
{
  const empty = walkCorpus(`${ROOT}/does-not-exist-at-all`);
  check("a missing store yields an empty corpus, not a throw", empty.notes.length, 0);
  check("searching an empty corpus returns no hits", search(empty, "anything").length, 0);
  const emptyIndex = buildIndex(empty);
  ok("avgLen on an empty corpus is not NaN or 0-divide", Number.isFinite(emptyIndex.avgLen), String(emptyIndex.avgLen));
}
check("an empty query returns nothing rather than everything", search(corpus, "   ").length, 0);
check("a stopword-only query returns nothing", search(corpus, "the and for").length, 0);

// ── the floor ───────────────────────────────────────────────────────────────
// OBSERVED, not estimated. A block that dies silently must not read as success.
const FLOOR = 55;
ok(`at least ${FLOOR} assertions ran`, pass + fail >= FLOOR, `${pass + fail} ran`);

console.log(`memory-engine.test: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
