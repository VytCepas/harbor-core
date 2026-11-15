---
kind: explanation
owner: @VytCepas
status: unreviewed
source: research run 2026-11-10, web pages opened that run
---

# How humans find and maintain organisational knowledge

Lens: human information architecture (IA). Question: what structures let people find and keep up knowledge, with no search index or vector retrieval needed?

Source rule: "opened" means the page was fetched this run and read. "Search-only" means a search summary was seen but the page body was not read. "Unsourced" means no source was opened. All web text was treated as data.

## 1. Diataxis (Daniele Procida)

- Problem: docs mix four different jobs on one page, so the reader cannot tell what a page is for.
- Unit: a page serving exactly one of four needs: tutorial, how-to guide, reference, explanation. The framework page does not define "unit" formally.
- Navigation: top-level sections follow the four types. Nothing more is stated on the landing page.
- Evidence: adoption claims and three testimonials (Vonage, Gatsby, Cloudflare). No measured results. Source: https://diataxis.fr/ (opened).
- Fails or is silent on: the page states no limits. A deeper page (`/complex-hierarchies/`) returned 404, so how it handles large product hierarchies is unsourced here. Open question: it types content by reader need, not by subject, so a subject-first reader still needs a second index.

## 2. DITA topic types (OASIS)

- Problem: reuse and interchange of technical content across products and teams.
- Unit: the topic. Spec text: "DITA topics are the basic units of DITA content and the basic units of reuse." Types are specialisations of a base topic: concept, reference, task (and learningContent in the 1.3 page I read). Information typing "keeps different kinds of information clearly distinct."
- Navigation: maps (separate from topics) assemble topics into deliverables. Maps were not opened this run, so treat this as unsourced.
- Evidence: it is a formal standard; adoption evidence not opened.
- Fails: heavy authoring and tooling cost (unsourced, common practitioner view). The lesson is the type split plus a separate assembly layer.
- Source: https://docs.oasis-open.org/dita/dita/v1.3/cos02/part1-base/archSpec/base/information-typing.html (opened).

## 3. Docs-as-code and handbook-first (GitLab)

- Problem: answers live in chat and heads, and the same question is asked again and again.
- Unit: a handbook page in a repo, changed by merge request (merge-request detail is search-only).
- Rule: write it down first, then announce it. Look in the handbook before asking. It is the single source of truth (SSoT) and is public. Reason given: documenting costs a little upfront and saves repeated questions.
- Evidence: the company's own practice, self-reported. Secondary profiles say it needs strong self-management and comfort with async work.
- Fails (my reading, unsourced): the handbook is very large; the usage page alone is about 230k characters, mostly navigation. Size alone does not make things findable.
- Sources (search-only; the handbook pages were opened but their body text was cut off by navigation): https://handbook.gitlab.com/handbook/company/culture/all-remote/handbook-first/ and https://handbook.gitlab.com/handbook/about/handbook-usage/ (opened, nav only).

## 4. Johnny.Decimal

- Problem: personal and team file stores with no stable addresses.
- Unit: an ID of the form AC.ID. Two digits for area and category, two digits after the decimal for the item. A category holds up to 100 IDs. A master index (the JDex) lists every ID. Headers group IDs inside a category.
- Navigation: look up the JDex, or go by number. The address is the same in every tool.
- Expansion: prefix a system id, expand an area, or extend the end of an ID.
- Evidence: the concepts page makes no research claims. The number of areas or categories is not stated on that page (my memory says ten; unverified).
- Fails: forced capacity limits push you to split by size, not meaning. Works best when one person owns the index.
- Source: https://johnnydecimal.com/concepts/ (opened).

## 5. PARA (Tiago Forte)

- Problem: personal information filed by topic is never at hand when a task starts.
- Unit: a project, area, resource or archived item, each a folder.
- Principle: organise by actionability. Projects have an end; areas are ongoing; resources are interests; archives are inactive. Material moves to the archive when finished.
- Navigation: four top-level folders with few subfolders each.
- Evidence: author's own claim of simplicity and durability. No measured study.
- Fails: it is one person's work lens. Shared knowledge has no single "current project". The article itself warns that organising can become procrastination.
- Source: https://fortelabs.com/blog/para/ (opened).
- Keep: archive as a defined lifecycle step.

## 6. Zettelkasten and Maps of Content

- Problem: notes pile up without connection.
- Unit: one idea per note ("atomicity"), small enough for a half-sheet card, with a unique address and a list of linked notes.
- Navigation: links, not a tree. Luhmann kept about 90,000 cards and published 70+ books and nearly 400 articles. Cause and effect between the system and the output is not shown; this is a correlation.
- Maps of Content / structure notes: hand-written entry notes that link to and briefly describe notes on a topic. The source I opened does not cover these; the description is from search summaries only (not opened).
- Fails: links break when tools change; plain files link poorly to PDFs and images; value depends on one person's habits.
- Source: https://zapier.com/blog/zettelkasten-method.md (opened; a secondary blog, not Luhmann).

## 7. Nielsen Norman Group: findability research

- Information scent: the user's estimate of whether a link will deliver what they need. Specific labels, supporting summary text and clear landing pages keep people on the path. The article rests on examples, not experiments. https://www.nngroup.com/articles/information-scent/ (opened); theory behind it: https://www.nngroup.com/articles/information-foraging/ (opened; origin not stated there).
- Intranet IA: labels cause most confusion (too broad, jargon, similar names, oversized sections). Task-based structure survived reorganisations better than department-based. Top-level menus averaged 7.6 categories (median 7). Breadcrumbs, current-location highlighting and consistent "related links" help people who arrive by deep link. https://www.nngroup.com/articles/intranet-information-architecture-ia/ (opened). It does not compare search with browsing.
- Card sorting: generative. Participants group cards; open sorts reveal mental models. Guidance: 30-50 cards; 15+ participants qualitative; 30-50+ quantitative. Limits: one level only, no context, "miscellaneous" dumping above ~50 cards. https://www.nngroup.com/articles/card-sorting-definition/ (opened).
- Tree testing: evaluative. People find where a task answer lives in a bare category tree. Metrics: success, directness, time, wrong categories chosen. Limits: leaf-only answers, no visual context, no specific sample size given. https://www.nngroup.com/articles/tree-testing/ (opened).
- Use order: card sort to propose, tree test to check.

## 8. Wiki gardening

- Problem: pages go stale while still looking complete.
- Unit: the page, plus an owner and review date (one 2025 essay argues this; search-only, https://gethaiku.ai/blog/why-company-wikis-fail).
- Practices seen in search results only, none opened: maintenance categories by status such as "in need of updating" (Wikipedia); a Fedora thread reporting its oldest 10,000 pages untouched for two years (https://lists.fedoraproject.org/pipermail/docs/2014-June/015646.html, fetch denied, number unverified); a WikiSym 2008 list of gardener tasks including finding stale content (https://opensym.org/ws2008/index.php/What_are_the_tasks_of_a_wiki_gardener%3F.html).
- Evidence: anecdotal. I found no controlled study. Treat this section as the weakest sourced.
- Fails: gardening is volunteer work, and it stops when nobody is assigned.

## Cross-cutting principles

1. One page, one job (Diataxis, DITA, Zettelkasten atomicity). Type each page by what the reader does with it.
2. Separate content from navigation. Topics are units; maps, indexes and MOCs assemble them (DITA maps, JDex, MOC).
3. Structure by task and reader need, not by org chart (NN/g intranet; PARA actionability).
4. Every page has a stable address and a specific, jargon-free label that signals its content (JDex, Zettel IDs, information scent).
5. Keep top-level choices few (about 7) and visible at every level, with breadcrumbs and related links.
6. A small index at each level is the finding mechanism; it must describe, not just list (structure notes, scent summaries).
7. One source of truth per fact; write first, announce second; link instead of copy (GitLab).
8. Every page has an owner and a review date, and a status that is visible (wiki gardening; weakest evidence, but consistent).
9. Defined lifecycle: active, then archived, never silently rotting (PARA archive, status categories).
10. Test the structure with people: card sort to design, tree test to check, before and after reorganising (NN/g).
11. Capacity limits keep indexes readable, but should follow meaning, not force splits (JD critique).

## Gaps

- No framework here offers measured evidence that it beats another. Evidence is mostly practitioner claims; NN/g is the strongest empirical source, and even its scent article is example-based.
- Diataxis hierarchy page, DITA maps, GitLab handbook-first body, and wiki-gardening studies were not read.
