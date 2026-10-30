# docs/ — the architecture page

`index.html` is **built on demand and not committed** (gitignored, harbor#1197). A fresh clone has none.

```sh
sh bin/doc-index-generate.sh --apply    # build docs/index.html (~14 s); rerun after any change
sh bin/doc-index-generate.sh --check    # exit 1 if the page cannot be built or has an unknown hole
sh bin/doc-index-generate.sh --tokens   # list every derived hole and whether it is filled
```

Open it with `open docs/index.html`. The core export (`bin/deploy-push.sh`) builds it into the snapshot.

## Why it is generated

The same argument `docs/generated/status.md` is built on, applied to prose. An
inventory written into a document — the lint rules, the CLI verbs, the rule
packs, the CI jobs — is a **copy** of a fact that lives in a script, and copies
drift while reading perfectly. Lint rules T1/T2/T3 exist because a sweep found
the same fact stated three different ways in three documents, none of them wrong
when written.

So the page has two halves:

| | |
|---|---|
| `src/*.html` | the **argument** — hand-written, and where every improvement goes |
| `<!--gen:NAME-->` | a hole the generator fills from the repository |
| `index.html` | the built page — not committed, built by `bin/doc-index-generate.sh --apply`, never hand-edited |

## Changing it

**Prose** — edit the relevant `src/NN-name.html` and regenerate. The section rail
is built from each file's `<h2 id="…">`, so a new section needs no registration
anywhere; a heading without an `id` is skipped rather than linked to nothing.

**A new derived table** — write a `d_NAME` function in
[`bin/doc-index-generate.sh`](../bin/doc-index-generate.sh) and put `<!--gen:NAME-->` in the prose. An
unknown hole is a **build failure**, not an empty space: a section that silently
renders as nothing is how a document loses a chapter without anyone noticing.

**Anything that changes a derived fact** — a lint rule, a CLI verb, a rule pack, a
suite, a contract, a CI job — regenerate in the same commit, the same way
`docs/generated/status.md` is regenerated.

## The diagrams

Hand-authored inline SVG, no libraries and no external assets, drawn in
`currentColor` so they invert with the page. The page is theme-aware: it follows
the reader's light or dark preference, and every colour is defined as a token at
the top of the generated stylesheet.
