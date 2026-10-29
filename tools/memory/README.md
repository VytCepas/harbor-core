# tools/memory — the L0 retrieval engine (harbor#6, workstream D)

Harbor's first first-party TypeScript. It exists because
[`../../contracts/memory-format.md`](../../contracts/memory-format.md) fixes the
canonical store as markdown + YAML frontmatter + `[[wikilinks]]`, and makes
every index **derived, gitignored and rebuilt in memory at query time** — which
is a retrieval problem, not a shell problem.

## Why this is TypeScript when the rest of `bin/` is POSIX sh

`policy/constitution.md` § *Operational rules* sets the language by layer: the security
floor is pure POSIX `sh`, and skill-tools are TypeScript on Bun. This is the
skill-tool layer. Two measured facts make the split load-bearing rather than
stylistic:

- `../../bin/deploy-doctor.sh` classifies `bun` as **optional**, on the stated grounds
  that *the floor is deliberately zero-Bun*.
- CI's preflight asserts a fixed list of binaries and `bun` is not on it.

So anything Harbor must be able to run **anywhere** lives in `bin/` and is sh —
the front door, the anti-rot lint, the suite. The ranker and the graph live
here. [`../../bin/memory.sh`](../../bin/memory.sh) is what an operator actually
runs; it uses this engine when Bun is present and answers over the same markdown
with `grep` when it is not.

## What is here

| File | What it owns |
|---|---|
| `store.ts` | the corpus reader of record — walk, frontmatter, tokenizer |
| `bm25.ts` | the ranker: BM25 **with** IDF, field weights inside the saturation, a relative cut |
| `graph.ts` | edges from the two link dialects, dangling-reference collection, BFS |
| `memory-engine.ts` | the CLI; the only file with argv parsing and stdout formatting |
| `memory-engine.test.ts` | every Bun-dependent assertion, folded into one suite |

## Two rules this tree lives under, both enforced

Lint rule **TS1** in [`../../bin/lint-conventions.sh`](../../bin/lint-conventions.sh)
checks both, and [`../../tests/lint/conventions/docs.test.sh`](../../tests/lint/conventions/docs.test.sh) proves it can
fail:

- **No off-disk imports.** There is no `package.json`, no lockfile, no
  `node_modules` and no build step — `bun memory-engine.ts` on a clean checkout
  is the whole story. One npm import ends that, and ends it silently on the
  machine that already has the package cached.
- **No filesystem writes.** The derived tier is rebuilt per invocation by
  contract. A cache is the obvious optimisation and it is exactly what the
  contract forbids, so the ban is checked rather than trusted.

## What it deliberately does not do

- **No inferred edges.** Upstream additionally synthesises relationships from
  IDF-weighted token similarity. That invents links the operator never wrote;
  BM25 already answers "what is similar". What is written is what is linked.
- **No daemon, no port, no network.** D1's own words: *not the 31337 daemon*.
- **No synthesis into `KNOWLEDGE/`.** Promoting a durable lesson is human-gated
  by [`../../contracts/memory-format.md`](../../contracts/memory-format.md).
- **No always-on injection.** Retrieval is on demand. Anything loaded every
  session is paid for every session, which lint **X3** measures.

## The arbiter

Neither implementation of "what is a dangling reference" is the source of truth.
[`../../fixtures/memory/expected.json`](../../fixtures/memory/expected.json)
holds the pinned answers, and both this engine and the POSIX
[`../../bin/memory-lint.sh`](../../bin/memory-lint.sh) are asserted against it —
never against each other. Two readers compared to one another can drift together
and still agree.
