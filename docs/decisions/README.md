# Decision records

One record per operator decision of the naming standard. Each record imports its decision text unchanged;
its `alias` (D-n) is permanent, so a citation of D-n resolves to the record. A superseded record names
its successor in `superseded_by`; a partial revision keeps the record accepted and names the revising decision
in `revised_by`. Format: MADR status (`proposed`, `accepted`, `rejected`, `superseded`).

The table of every record is generated into docs/index.html (the decisions section), not kept here by hand.
That page is built on demand (`sh bin/docs-gen.sh --apply`) and not committed; `--check` is red when it cannot be built.

Two lint rules hold the citations to the records: `standard.decision-dangling` (a D-n with no record) and
`standard.decision-orphan` (a record nothing outside this folder cites, unless listed in
`CONTRACTS/decision-orphans.tsv`). `sh bin/graph-gen.sh --refs D-n` lists every site that cites a decision.
