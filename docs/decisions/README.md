---
kind: decision-record
owner: @VytCepas
status: unreviewed
---

# Decision records

One record per operator decision of the naming standard. Each record imports its decision text unchanged;
its `alias` (D-n) is permanent, so a citation of D-n resolves to the record. A superseded record names
its successor in `superseded_by`; a partial revision keeps the record accepted and names the revising decision
in `revised_by`. Format: MADR status (`proposed`, `accepted`, `rejected`, `superseded`).

The id is `harbor/D-<n>` outside this repo and `D-<n>` inside it; yard and fleet keep the same shape in their own `docs/decisions/`
(harbor#1429). Every record opens with `kind`, `status`, `alias`, `date`, `supersedes` and `superseded_by` (`-` for none, else a
comma-separated list of `[system/]D-<n>`); a supersession is written on both records, and `standard.decision-fields` and
`standard.decision-supersession` hold them to it. `contracts/decision-reach.tsv` lists the surfaces read outside the repo, where
a bare `D-<n>` is red. `sh bin/standard-decision-migrate.sh --root <repo> records` moves a repo's older records onto the shape.

The table of every record is generated into docs/index.html (the decisions section), not kept here by hand.
That page is built on demand (`sh bin/doc-index-generate.sh --apply`) and not committed; `--check` is red when it cannot be built.

Two lint rules hold the citations to the records: `standard.decision-dangling` (a D-n with no record) and
`standard.decision-orphan` (a record nothing outside this folder cites, unless listed in
`contracts/decision-orphans.tsv`). `sh bin/doc-graph-generate.sh --refs D-n` lists every site that cites a decision.
