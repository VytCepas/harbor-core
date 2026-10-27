# Reports — what a generated artefact owes its reader

**Scope: anything this box GENERATES for a person to read.** An HTML audit report,
a diagram, a reconciliation listing, a findings export, a dashboard. Not a commit
message, not a terminal answer, not a client email — those are
`skills/deliverable-contract`, which governs text a person WRITES. The two agree
on the principle and differ on the artefact: this file is the machine-checkable
half.

`CONTRACTS/gates.md` says what a CHECKER owes the person running it. This says
what a REPORT owes the person opening it, which is a different and later reader:
they were not in the session, they did not run the tool, and they will not open a
second document to find out what a column means.

---

## Where this came from

A topology audit shipped on 2026-09-03 that was green on every gate it had. The
defects a reader actually hit were not in its findings — they were in its
*legibility*, and no gate on this box could see any of them:

| what shipped | what the reader got |
|---|---|
| `NOT IN MAP  123456789  ...` | a number that is an ad-platform customer id, an analytics property and a transfer config depending on the line. No way to know which console to open. |
| `40 object(s) matched: 40 in the map, 0 NOT in it` | reads as *the map is complete*. It bounded three of nine object classes and said so nowhere. |
| three diagrams, `1 of 3` first | tags and conversion labels, no pipeline in it at all. The chunker cut at row 10 regardless of what it was cutting. |
| `ACME_SHOP_EU_PLATFOR…` | truncated mid-identifier, so the object could not be named even in the right picture. |

Every one is cheap to fix and none is visible to the author, **who holds the
context and therefore cannot feel its absence.** That is why this is a contract
and not advice.

---

## Required properties of a generated report

1. **It reads cold.** A competent colleague who was not in this session can act
   on it, alone, on a first read. If answering an obvious question about it needs
   a second document, the report is not finished.
2. **Every identifier states its type and its origin.** Not `123456789` but
   *Analytics property `123456789`, read from analyticsadmin accountSummaries, role dir
   `analytics`*. The origin includes **which identity saw it**, because "the map does
   not name this" and "this credential cannot see it" are different findings with
   different owners, and they are indistinguishable without it.
3. **Every number carries its comparison.** `72.02 EUR` lands as a fact;
   `72.02 EUR against the 16,025.59 EUR actually spent` lands as a finding.
   A figure with nothing beside it cannot be acted on and will be skimmed.
4. **It states what it does not cover** — the same obligation gates.md puts on a
   checker (property 6), carried through to the artefact. A reader cannot infer
   scope from a document that looks complete.
5. **It names its source and its as-of date**, and says which wins when they
   disagree. `report-gen.sh` ends every page with *"A projection, never a source:
   when this disagrees with the map, the map is right."*
6. **A generated picture has a text companion, written FIRST, and the picture is
   checked against it.** This one is the load-bearing rule of the file:

   **A diagram is the only artefact whose defects are invisible in its own
   output.** Every renderer defect this box has recorded was found by a person
   opening a picture and noticing an absence — two feeds merged into one box,
   thirty-four edges with no id, a chunk containing no pipeline. Nothing could
   have caught them automatically, because the only description of what SHOULD
   have been drawn lived in the drawing.

   So: emit the markdown BEFORE the render, so it survives a renderer that
   refuses; derive it from the same parse that builds the picture, so it cannot
   drift into a second hand-kept copy; and compare the drawn connectivity against
   the declared connectivity **in both directions** —
   *declared but not drawn* is an omission, *drawn but not declared* is an
   invention with no source, and the second is worse.
7. **A report that grades how badly something hurts grades how well it is
   known.** Severity and confidence are different questions, and a page that
   answers only the first invites the reader to assume the second. Measured on
   a client atlas 2026-09-03: five findings its own source marks *"one lane only.
   Treat as a lead, not a fact"* rendered identically to the fifteen a critic had
   re-measured, and nothing on the page could recover the difference.

   Three fields, and they are three because folding them loses information:
   **grade** (what the adversarial pass concluded), **basis** (traffic,
   query or configuration — the audit's own reading key says these decide ties,
   and configuration lost to traffic four times out of four), and **an ISO date**
   for when the evidence was taken. Staleness is then *derived* by comparing that
   date against the newest one on the page, so nothing has to be relabelled when
   a claim is re-measured — which is the failure mode of every hand-kept
   `last-verified` field this box has had.
8. **Coverage is counted, never written.** A hand-authored "what we did not
   cover" is a copy of a fact that lives in the findings list, and copies drift
   silently while still reading correctly — the same atlas shipped a section
   claiming five open questions where its source carried eight, and a refuted
   table carrying eight rows where its source carried seventeen. Derive the
   counts from the findings at build time. The one part that cannot be derived is
   what nobody could measure at all, and each row of *that* names the single
   probe that would settle it and the person who can run it: a limit with no
   probe beside it is an excuse, not a finding.

---

## The mechanism

`bin/report-contract.sh <artefact>` checks properties 4, 5, 6 and 7 — the ones a
machine can settle. 1, 2, 3 and 8 are judgement and are checked by the author and
by review; they are written here so the judgement has a shape rather than being
re-derived each time.

**Property 7 is checked at the floor, not per finding.** The shell checker can
see only that an artefact grading severity also carries confidence vocabulary
*somewhere*; it cannot see whether every finding carries its own. Per-finding
enforcement belongs where the findings are PRODUCED, the same split property 2
takes: the atlas builder refuses to emit a finding with no grade, no basis and no
ISO date, and proves it by mutation. The floor catches an artefact that never
grades anything; the generator catches the one that grades most things.

**And it is asked only of artefacts that already grade severity.** Every broader
trigger — "does it list findings", "does it have a table" — fires on ordinary
documents, and a guard that fires on ordinary work gets switched off
(gates.md property 5). Measured against six real artefacts on 2026-09-04: the
trigger fired on three, all three already carried confidence vocabulary, and the
three it left alone were correctly left alone.

    sh bin/report-contract.sh <file.html|file.md>   one artefact
    sh bin/report-contract.sh --self-test           prove it goes RED first

It is wired into `tests/skills/skill-gates-test.sh`. A contract with no runner is a wish
(CONSTITUTION, *fix the system*).

**What it deliberately does NOT check:** whether an identifier is typed. Every
heuristic for "a bare id" fires on version numbers, row counts, dates and
currency, and a guard that fires on ordinary work gets switched off
(gates.md property 5). Property 2 is enforced where the ids are PRODUCED —
`reconcile-estate.sh` asserts its own typing in its self-test — not by scanning
finished prose for digits.

---

## Conforming today

| generator | 4 scope | 5 source+date | 6 companion | 7 confidence | 8 derived coverage |
|---|---|---|---|---|---|
| `skills/topology/bin/report-gen.sh` | Gaps tab + per-section notes | footer | n/a — routes to `topology-diagram.sh` | grades freshness (`verified` date, `stale`), never severity — trigger does not fire | `count()` over the same TSV the tabs filter |
| `skills/topology/bin/topology-diagram.sh` | — | in the companion header | `TOPO_EMIT=md` + `flow-connectivity.mjs` | n/a — draws, does not grade | n/a |
| `skills/topology/bin/reconcile-estate.sh` | `NOT ENUMERATED` block | header line | n/a — no picture | n/a — reconciles, does not grade | n/a |
| `skills/atlas/build/build.py` | diagnostics tab | brand line + companion header | companion written first, `connectivity()` both ways | grade + basis + ISO date, refused at build | `diagnose()` counts from the findings |

A generator added later goes in this table or the row says why it is exempt. An
empty cell is a gap someone can see; an absent row is a gap nobody can.

**The atlas row was three `no`s until 2026-09-04 and is now the reference
implementation.** That is worth recording rather than quietly overwriting: it met
none of the mechanical properties, the gap was made visible here before the
plugin was packaged, and closing it is what produced properties 7 and 8. It is
tracked on `main` as of harbor#416, and the properties themselves landed in
harbor#418.

**`report-gen.sh` was written into this table as failing 7 and 8, and it fails
neither.** The row said so for about ten minutes on 2026-09-04 before being
checked: it carries zero severity terms and forty-four freshness ones
(`verified` ×23, `stale` ×21 counting `staleness`), and its gap counts come from
`count()` over the same TSV its tabs filter. Recorded because this file's own
property 5 applies to it — a claim about a generator is a claim, and the check is
one `grep` away.

The count in that sentence was itself wrong on first writing — `stale` ×16, a
number matching no pattern the file can be grepped for — and stood for a day
before a re-check caught it. Twice now on the same sentence, which is the
argument for property 8: a count written by hand into prose is a copy, and this
document cannot compute. Re-derive rather than cite it:

    grep -oi 'verified' skills/topology/bin/report-gen.sh | wc -l
    grep -oi 'stale'    skills/topology/bin/report-gen.sh | wc -l
