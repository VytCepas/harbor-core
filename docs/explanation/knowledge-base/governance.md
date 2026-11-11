---
kind: explanation
owner: @VytCepas
status: unreviewed
source: research run 2026-11-10, web pages opened that run
---

# Knowledge governance and lifecycle: findings

Lens: who owns knowledge, how it stays true, how it is named, and how we know it can be found. For humans and agents. No RAG assumed.

Source rule: a URL below means the page was opened this run and the claim is on it. "Snippet only" means it appeared in search results but the page body did not load. "Unsourced" means I could not verify it.

## 1. Ownership and verification dates

**Guru (opened).** Every card has a named verifier, "the person or team accountable for keeping that content current". The interval ranges from "Does not expire" to one year. A card becomes unverified when the interval lapses, or when someone who is not the verifier (or in the verifying group) edits it. Unverified cards stay searchable but appear in the verifier's task list; nothing is deleted. A Knowledge Agent can be set to "Verified only", so agents skip unverified content. Anyone can unverify a wrong card. Source: https://help.getguru.com/docs/verifying-and-unverifying-cards

**Guru health metrics (opened).** Three reports: verification score over time, unverified cards by verifier (top 20), and most urgent cards to verify (unverified, sorted by views). Guru recommends a score above 80%. The score is not formally defined on the page. Source: https://help.getguru.com/docs/evaluating-verification-health-analytics

**Confluence (snippet only, not opened).** Search results say Confluence has a Verified page status that only page owners and admins can set, that it does not expire on its own, and that the community workaround is a scheduled automation that flips pages "verified" and not updated for a year to "needs review" and notifies the owner. Treat as unconfirmed. Seen at: https://community.atlassian.com/forums/Confluence-articles/Verified-Pages-Now-Available-in-Confluence/ba-p/2664827 (body did not load).

**GitLab (not verified).** The handbook-usage page loaded as navigation only; I could not read its text on handbook-first, single source of truth or ownership. Any claim about GitLab practice here is unsourced. URL tried: https://handbook.gitlab.com/handbook/about/handbook-usage/

**Content audits (opened).** NN/g: assign clear ownership of the inventory and audit; inventory fields include name, URL, owner, format, dates, metadata; each item gets one status (keep, update, remove); an update needs a documented action and an assigned owner; automate the inventory, have people do the audit; run continuous monitoring. Source: https://www.nngroup.com/articles/content-audits/

**Schema.org lifecycle fields (opened).** CreativeWork (inherited by WebPage) has `dateModified`, `author`, `expires` ("no longer useful or available"), `isBasedOn`, `inLanguage`, `keywords`. Source: https://schema.org/WebPage

**Checkable rules from this section**
- R1. Every page has exactly one named owner (person or team) and a `last_verified` date. A page missing either fails lint.
- R2. A page is "stale" when today minus `last_verified` exceeds its interval. Intervals are set by page type (suggest 90 / 180 / 365 days / evergreen), never blank.
- R3. An edit by a non-owner clears `last_verified` (Guru's rule). Stale and unverified pages stay readable but are marked, and agents must say "unverified" when quoting them.
- R4. Retirement is explicit: a retired page carries `status: archived` and a pointer to its replacement (see section 3), not silent deletion.
- R5. Track a verified share (verified pages / all pages) and a top-N list of stale pages by views. Target is a starting point, borrowed from Guru's 80% guidance, to be tuned.

## 2. ROT audits (redundant, outdated, trivial)

NN/g's audit article does not use the term "ROT" and does not cover "trivial" (opened, same URL as above). The acronym is common practice but I did not find a primary source for the definition this run: unsourced. What the NN/g article does give is the mechanic: inventory, rate each page high/mediocre/low against best practice and organisational standards, add performance data (views, clicks), and assign keep / update / remove. It advises starting with the most-used, task-critical content and timeboxing the first pass (example: six weeks).

Operational ROT tests we can compute (our design, not from a source):
- Outdated: stale per R2, or links to a replaced/archived page.
- Redundant: two pages with the same title after normalisation, or the same `answers` question (section 3).
- Trivial: no inbound links, zero views in 12 months, body under a minimum length, and no owner claim. Candidate only; a human decides.

Rule R6: run the ROT query on a schedule; output is a delta list (new this period), each row ending in keep / update / remove with an owner.

## 3. Single source of truth and deduplication

Evidence found this run is thin. Google says localised versions are duplicates only if the main content is untranslated (https://developers.google.com/search/docs/specialty/international/localized-versions), which is a search-engine note, not a general SSOT rule. Dublin Core gives relation terms `replaces` and `isReplacedBy` (https://www.dublincore.org/specifications/dublin-core/dcmi-terms/). Schema.org has `isBasedOn` (https://schema.org/WebPage).

Rules (design, informed by the above):
- R7. One fact has one home page. Other pages link to it; they do not restate it. A restated value is a lint warning when the same literal (e.g. a price, a limit, an ID) appears in two pages.
- R8. Every page states what question it answers in one line (`answers:`). Two pages with near-identical `answers` are a duplicate candidate.
- R9. Supersession is machine-readable: `replaces` / `replaced_by` fields (Dublin Core names). A page with `replaced_by` must render a banner, and agents follow the pointer.
- R10. Derived copies (summaries, indexes) declare their source with `derived_from` and are regenerated, not hand-edited.

## 4. Controlled vocabularies and metadata standards

**Dublin Core (opened).** 15 core elements: Contributor, Coverage, Creator, Date, Description, Format, Identifier, Language, Publisher, Relation, Rights, Source, Subject, Title, Type. `dcterms:modified`, `replaces`, `isReplacedBy`, `language` exist; Language should use ISO 639 or BCP 47 values. Source: https://www.dublincore.org/specifications/dublin-core/dcmi-terms/

**SKOS (opened).** `prefLabel` (one preferred label per concept per language tag), `altLabel` (synonyms, abbreviations), `hiddenLabel` (misspellings, searchable but not displayed), `broader`/`narrower`/`related`, `ConceptScheme` for a whole vocabulary. The three label types are disjoint: the same string cannot be both preferred and alternative. The primer recommends no two concepts in a scheme share a preferred label in the same language. Sources: https://www.w3.org/TR/skos-primer/ and https://www.w3.org/TR/skos-reference/ (integrity condition S13; `exactMatch`/`closeMatch` for cross-vocabulary mapping).

**Schema.org (opened).** Shared types and properties, usable in Microdata, RDFa or JSON-LD; types inherit from parents (Thing is the root). The getting-started page does not cover `dateModified`, `inLanguage` or `keywords`; those are on the WebPage/CreativeWork page. Sources: https://schema.org/docs/gs.html, https://schema.org/WebPage

Practical reading: do not adopt RDF tooling. Borrow the field names and the label discipline. A front-matter block per page maps cleanly: `title` (dc:title), `owner` (dc:creator/publisher), `last_verified` (own field), `modified` (dcterms:modified), `language` (BCP 47), `type`, `subject` (controlled term), `replaces`/`replaced_by`.

Rules
- R11. `subject` and `type` values come from a published list (one page, in the wiki). A value not in the list fails lint.
- R12. Each term has one preferred label per language, plus alternative labels (synonyms, abbreviations, other-language equivalents) and hidden labels (common misspellings). Same string is never both preferred and alternative.
- R13. The vocabulary page is itself a governed page with an owner and changelog.

## 5. Tagging practice and tag sprawl

Dovetail's taxonomy guide (opened; a vendor guide, so practitioner advice, not research): name one to three stewards; they approve new tags, merge duplicates, retire obsolete ones; a 30-minute monthly review is often enough; 50 to 150 well-maintained tags cover most teams' core themes; over 200 with no hierarchy is a warning sign; keep hierarchy to two or three levels; each quarter archive tags with zero or very few uses; keep a changelog of additions, merges, renames and retirements with reasons; give contributors a low-friction way to request tags. Source: https://dovetail.com/research/tagging-taxonomy-research-repository-scales-across-teams/

I could not open an NN/g tagging article (URL returned 404), so no NN/g claim is made on tags. BookStack's own tag documentation did not load either; its overview page only links to it (https://www.bookstackapp.com/docs/user/content-overview/).

Rules
- R14. Tags are a closed list owned by stewards. Free-text tags are not allowed; a request goes to a named queue.
- R15. Tag count budget (starting point from Dovetail's numbers): alert at 150, review at 200. Every tag has a one-line definition and at least N pages (suggest 3); below that for a quarter, archive or merge.
- R16. Tags describe topic or audience. Structure (type, status, owner, language) lives in typed fields, not tags. This keeps the tag list short.
- R17. Tag changes are logged (add, merge, rename, retire, reason).

## 6. Multilingual knowledge bases

Opened evidence:
- Google: give each language variant its own URL; link variants to each other, both ways, with `hreflang`; translate the main content; add an `x-default` fallback. Google does not state a rule on mixing languages in one page. https://developers.google.com/search/docs/specialty/international/localized-versions
- W3C: declare the page language with `lang` on `html`; mark foreign passages with their own `lang`; values follow BCP 47. https://www.w3.org/International/questions/qa-html-language-declarations
- SKOS: labels carry language tags; one preferred label per language; a concept can carry labels in several languages. https://www.w3.org/TR/skos-primer/
- Dublin Core: language values from ISO 639 or BCP 47. https://www.dublincore.org/specifications/dublin-core/dcmi-terms/

I did not find a primary source comparing "one language per page" with "translations in one page" for internal wikis: unsourced. The choice below is a design call consistent with the above.

Rules
- R18. One language per page. The page declares `language` (BCP 47: `lt`, `en`). Quoted foreign strings are fine; mixed bodies are not.
- R19. A translation is a separate page that points to its source page by id (`translation_of`, `source_language`), and records the source's `last_verified` it was checked against. If the source changes, the translation is marked stale.
- R20. Concepts, not words, are the unit: the vocabulary holds one concept with a Lithuanian and an English preferred label and cross-language alternatives. Search and agents map either label to the same concept. This is the bilingual-keyword mechanism, with no embeddings.
- R21. Each page has an `answers` line and a `keywords` list in its own language, plus alternative-language keywords for terms people actually search in the other language (from search logs, section 7).
- R22. Decide a primary language per space; pages with no translation are allowed, but the missing translation is listed, not hidden.

## 7. Measuring findability

**Search logs (opened).** NN/g: take the top ~1,000 queries over 3 to 6 months; review roughly the top 300 then look for synonyms and clusters; pull zero-result queries ("misspellings and wanted information the search engine can't find"), ignore rare ones and investigate frequent ones; sequential searches from one user can reveal failed queries; blank searches and very long queries are signals; strip personal data before sharing logs and delete logs after analysis. https://www.nngroup.com/articles/search-log-analysis/

**Zero-result pages (opened).** Baymard: about half of ecommerce sites give poor recovery on no-results pages; tips alone are not enough; offer related categories, alternative searches, popular items. This is ecommerce evidence; apply with care to a wiki. https://baymard.com/research-articles/no-results-page

**Task success (opened).** NN/g: success rate is the percentage of users who complete a task; report a confidence interval; partial credit levels (complete, minor issue, major issue, failure) reported separately, not averaged; small tests of 4 to 5 users give insight but wide intervals; the article gives no benchmark values. https://www.nngroup.com/articles/success-rate-the-simplest-usability-metric/

**Content audit data (opened).** Views, clicks and similar metrics feed the audit. https://www.nngroup.com/articles/content-audits/

Rules
- R23. Keep a findability set: 20 to 50 real questions (from search logs, tickets, chat) each with the page(s) that should answer it. Run it monthly for humans (can they find it) and for an agent (does it open the right page from the index with no vector search). Report pass rate with a confidence interval, and partial levels separately.
- R24. Log wiki search queries. Monthly: list frequent zero-result queries; each becomes an alt/hidden label, a new page, or a documented "out of scope".
- R25. Every zero-result fix is traced: query, action, date, owner.
- R26. Logs are pseudonymised and have a retention limit (NN/g privacy advice).

## 8. Principles for the standard

1. Every page has one owner and one verification date; unowned or unverified is visible, never hidden.
2. Staleness is computed from dates and interval, not judged.
3. One fact, one home; everything else links.
4. Supersession is explicit and machine-readable.
5. Metadata is a small typed front-matter block using Dublin Core / schema.org names; values from a controlled list.
6. Vocabulary is concept-based: one preferred label per language, alternative and hidden labels for synonyms and misspellings.
7. Tags are a closed, stewarded list kept short; structure goes in typed fields.
8. One language per page; translations are separate pages linked to their source and checked against its version.
9. Findability is measured with a fixed question set and search logs, on a schedule.
10. Audits report deltas and end in keep / update / remove with an owner.
11. A lint can check every rule above; a rule that cannot be checked is rewritten.

## 9. Open items and caveats

- GitLab handbook practice: unsourced (page did not load as text).
- Confluence Verified status: snippet only.
- ROT acronym definition: no primary source opened.
- Numeric thresholds (80%, 50 to 150 tags, 90/180/365 days, 3 pages per tag) come from vendor guidance or are my starting points; tune them on our own wiki.
- BookStack field support (owner, verified date, language) was not verified; the overview page only describes shelves, books, chapters, pages and short descriptions (https://www.bookstackapp.com/docs/user/content-overview/).
