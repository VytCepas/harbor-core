---
kind: standard
status: experimental
owner_issue: harbor#1501
---
# Knowledge base standard

How a knowledge base is structured so that a person can browse it and an agent can find answers in it with list,
read and keyword search alone, with no vector retrieval (no RAG). A knowledge base here is a wiki, a document base or
a shared agent memory store. Decided by D-93 (`docs/decisions/0093-knowledge-base-standard.md`); the method that
applies it is the hidden skill `skills/doc-knowledge-base/`.

## Contents

1. Scope and citations
2. What done looks like
3. The core and the extensions
4. Layers
5. Page kinds
6. Page shape
7. Metadata
8. Navigation and wiring
9. Governance and lifecycle
10. Checks
11. How it degrades with size
12. Mapping onto Harbor
13. Platform profiles
14. Migration
15. Open questions

## 1. Scope and citations

### 1.1 Scope

- **It binds external knowledge bases**: a company wiki, a document base, a shared agent memory store, built new or
  restructured to it. (D-93)
- **It does not govern Harbor's own docs or agent memory.** D-90 (four doc kinds), D-22 (the doc header), naming §15
  (front matter) and `contracts/memory-format.md` stay as they are. Section 12 is the bridge. (D-93)
- **Platform facts live in a profile, not here.** Each base has a profile beside its own tooling (section 13): the
  platform's containers, limits, search syntax and templates. This file states the platform-independent rules.
- **Layers are named, not numbered.** Harbor and other systems already use "L3" for different things; this standard
  says "entry", "map", "page", "record", "draft", "archive".

### 1.2 Citations

| Tag | Meaning |
|---|---|
| HIA §n | `docs/explanation/knowledge-base/human-findability.md`: how people find and keep organisational knowledge |
| NR §n | `docs/explanation/knowledge-base/agent-no-rag.md`: how agents navigate without retrieval |
| AM §n | `docs/explanation/knowledge-base/agent-memory.md`: agent memory architectures |
| GOV §n | `docs/explanation/knowledge-base/governance.md`: ownership, lifecycle, audits, measurement |
| **judgment** | A design call. Numbers marked judgment are starting points, tuned by the findability set (9.6) |

The research files record which web pages were opened and which were seen only as search summaries.

## 2. What done looks like

A base conforms when all of these hold. Each one is testable.

1. **A cold reader finds the answer without vector search.** On the findability set (9.6), run by an agent through the
   deployed tools with their real instructions, at least **80%** of questions end on the right page with full success.
   Partial and failed results are reported apart, with a confidence interval. Each passing question takes **5 tool
   calls or fewer** (searches, browses and reads together). (GOV §7 R23; 80% and 5 calls: judgment)
2. **Every page says what it is before it is opened.** Its first sentence is a summary that fits the platform's list
   preview, and its kind is in its metadata. (NR §4; HIA §7 information scent)
3. **Every fact has one home.** Other pages link to it. A value is edited in place. (GOV §3 R7)
4. **Every page shows who owns it, when it was last checked, and whether it is live.** (GOV §1 R1-R4)
5. **The words people search for are on the page**, in the form search matches. (NR §8)
6. **A script can fail the base** on every check marked "lint" in section 10, and every check is registered.
   (GOV §8 principle 11)
7. **It got better, measurably.** The findability rate and the tools' solved rate (9.6) rose from a baseline taken
   before the change.

## 3. The core and the extensions

Editors of a shared base are mostly not technical. **The core is what every page needs on day one.** An extension is
added only when its trigger fires.

### 3.1 The core (what editors keep)

| Item | What it is |
|---|---|
| 4 metadata fields | `kind`, `owner`, `status`, `verified` |
| 2 lines at the top of the body | A summary, then "Also known as" (only when a search has missed the page) |
| 7 kinds | `how-to`, `reference`, `policy`, `decision-record`, `record`, `glossary`, `map` |
| 1 glossary | One page, in every language the base is written in |
| 1 entry page | The base's home |
| 1 editor guide | One page in the base's default language, no layer jargon, no YAML |

### 3.2 Extensions and their triggers

| Extension | Add it when |
|---|---|
| `tutorial`, `explanation` kinds | A page needs one and none of the core kinds fit |
| `language` field | A page is not in the base's default language (stored only as the exception) |
| `subject` list with stewards | Subjects span many containers (section 11) |
| Translations (`translation-of`) | The first translated page is written |
| Generated maps | The agent's browse tool cannot return page summaries (8.3) |
| A-Z alias index | The findability set records vocabulary misses that aliases on pages did not fix |
| Per-page `review-every` | An owner asks for an interval other than the kind's default |

## 4. Layers

Six layers. Knowledge moves down the list as it matures and to the archive when it retires. The layer decides who
writes, how it is reached and what it may cost. (AM §2, §7; NR §4)

| Layer | Holds | Who writes | How it is reached | Budget |
|---|---|---|---|---|
| **Entry** | One page: what the base is, the top containers with one line and trigger words each, where the glossary and the editor guide are. A map, not a manual. | A steward. Human-approved. | The base's home. Named by stable link in the agent's tool instructions (8.2). | ≤ 200 lines and ≤ half the read ceiling |
| **Map** | One per container and a few cross-cutting maps of content (per platform, per process). | Containers: their description field. Cross-cutting maps: a person. | Linked from the entry page or a parent. | ≤ 60 entries per map |
| **Page** | Canonical pages: how-to, reference, policy, glossary (and tutorial, explanation). One job each. | People. Agents propose drafts. | Exactly one home container; may also appear in cross-cutting maps. | Under the read ceiling; contents block over 8,000 characters |
| **Record** | Dated, one event each: decisions, meeting notes, incidents, hand-offs, workshop notes. | People and agents add. Corrections are added, not rewritten. | Its container; linked from the page it informs. | One event per record |
| **Draft** | Work in progress: agent proposals, open questions. | Anyone; agents freely. | Not linked from the entry page. | Reviewed or archived in 30 days (judgment) |
| **Archive** | Superseded and retired pages, kept findable. | A status change by the owner. | The archive container; a `replaced-by` pointer from the old page. | No limit |

Why these budgets:

- **The read ceiling is the agent's.** It is the most characters the agent's read tool returns for one page; the
  profile states it. The entry page is read in every session that needs it, so it stays at half the ceiling. 200 lines
  is judgment, borrowed from Claude Code's memory files, which "consume more context and reduce adherence" when longer
  (NR §3). Pages stay under the ceiling with room for the tool's own framing. Size caps are in characters, not lines.
  With a 40,000-character ceiling the defaults are 20,000 for the entry page and 30,000 for a page (judgment).
- **Disclosure has three levels**: a line in a map or list, the page's summary, the page body. Detail sits one level
  below its parent; no chains of "see also". (NR §4, §10.4)
- **Write rights follow risk.** Records and drafts are open to agents. Procedures and policies change only by a
  reviewed edit. Judgment, inspired by CoALA's point that an agent rewriting its own procedures is riskier than
  writing facts (AM §1); the paper is about agent code, not human runbooks.
- **Records are kept apart from curated pages.** A log is never edited into a page; a page links to the records it
  rests on. Consolidation is a separate pass, gated by a person. (AM §2, §3, §8.4-8.5)
- **Interruption is normal.** A long task leaves a draft progress note a cold reader can resume from. (AM §4, §8.12)

## 5. Page kinds

### 5.1 The list

`kind` names the page's shape: what the reader does with it. Topic comes from the container and the title, never from
`kind`. (HIA §1 Diátaxis, §2 DITA)

| kind | Reader's job | Core? |
|---|---|---|
| `map` | Find where things are | core |
| `how-to` | Do one task they already have | core |
| `reference` | Look up a fact: a price list, a contact list, an account set-up, an entity profile | core |
| `policy` | Know a rule they must follow | core |
| `glossary` | Map a word to a concept and its home page | core |
| `decision-record` | See what was decided, when and why | core |
| `record` | See what happened: a meeting, an incident, a hand-off, a workshop | core |
| `tutorial` | Learn by doing one lesson | extension |
| `explanation` | Understand why | extension |

- **`record` versus Harbor's `report`.** A record says what happened at one event. A report (Harbor's kind,
  `standards/naming/kinds.tsv`) gives the findings of an investigation. `record` is a base kind; Harbor keeps `report`.
- **`reference` is hand-written in a base and generated in Harbor.** The reader's job is the same, so the shared word
  is deliberate. What differs is the lifecycle: a base's reference page is verified by its owner; a Harbor reference
  file is regenerated.
- **A page serves one kind.** A page that needs two is two pages linked to each other. (HIA §1)
- **An entity** (a client, a platform, a portal) has one home page; its how-tos and records link to it. Duplicates are
  found by title plus "Also known as". (AM §5, §8.6)

### 5.2 Required sections by kind

Headings follow the page's language. The profile gives the twin of each heading in each language of the base, and a
check accepts any of them.

| kind | Required sections |
|---|---|
| `map` | Purpose · Contents (one line per child: link and its summary) · Not here (what people look for that lives elsewhere) |
| `how-to` | Goal · Before you start (access, inputs) · Steps · Check it worked · If it fails · Owner and escalation |
| `reference` | The facts (a table where possible) · Where these facts come from |
| `reference`, entity profile | Who or what it is · Names and IDs (aliases, public identifiers, never secrets) · Key facts · Related pages |
| `policy` | Rule · Why · Who it applies to · Exceptions · Who checks |
| `glossary` | One row per concept: the term in each language · other names · home page link · not to be confused with |
| `decision-record` | Context · Decision · Consequences · Alternatives rejected |
| `record` | When · Who · What happened · Actions (each with an owner) · Links |
| `tutorial` | What you will make · Before you start · Steps · What you learned · Next |
| `explanation` | Question · Short answer · Reasoning · Alternatives and trade-offs |

The rows are judgment, after Diátaxis (HIA §1). `decision-record` adds "Alternatives rejected" to D-22's three
sections because a base's readers were not in the room.

## 6. Page shape

Every page, in this order:

1. **Title.** A specific label, unique within its container after case and diacritic folding. No "Overview", "Notes",
   "Misc". (HIA §7; NR §5)
2. **Summary.** The first paragraph of the body: one or two sentences, at most 250 characters, saying what question the
   page answers and when to read it. **Its first sentence fits the platform's list preview** (the profile states the
   length). No block of any kind comes before it.
3. **Also known as.** One line of other names: old names, abbreviations, the other language's term, the stem people
   type. Added when the findability set or a person records a miss, not guessed up front. (NR §9.1)
4. **Contents**, only on pages over 8,000 characters, so a partial read still shows scope. (NR §4)
5. The kind's sections (5.2).
6. **Related.** Links to the home of every fact this page uses but does not own. (HIA §7; GOV §3 R7)
7. **Retirement banner**, only on a superseded or archived page, at the very top above the summary: "Replaced by:
   <link>". This is the one thing allowed above the summary. (GOV §3 R9)

There is **no metadata block in the body** of a platform page: it would fill the list preview with noise. Metadata goes
in native fields (section 7). In a repo, metadata stays in YAML front matter.

## 7. Metadata

### 7.1 Where it lives

- **The platform's native fields are canonical**: tags, labels or properties, edited in the platform's own editor, so
  that platform search can filter on them. In a markdown-in-git base, YAML front matter is the native field.
- **Agents change metadata by merge, never by overwrite.** Where the platform's update replaces the whole tag set, a
  tag write reads the current set, merges the change and writes the full set back, under the same "show the person
  first" rule as every write. Until such a tool exists, an agent writes proposed tags into a draft and a person or the
  structure tool applies them.
- **The stable key is the platform's own id**, linked by its permalink form. No hand-kept slug.

### 7.2 Fields

| Field | Who sets it | Required | Values |
|---|---|---|---|
| `kind` | person | all | 5.1 |
| `owner` | person | all | One person, as their platform user handle, resolvable to a user id. Never a team. |
| `status` | person | all | 9.3 |
| `verified` | person | all except `record` and generated pages | ISO date the owner last confirmed the page is true |
| `replaced-by` | person | on `superseded` | Id of the replacement |
| agent-provenance field | the agent's write tool | on pages an agent created | Set by the tool, never by hand |
| `generated-from` | the generator | generated pages | The source system |
| `edit-in` | the generator | when `generated-from` is set | URL where the source is edited |
| `language` | person | only when not the default | BCP 47 |

- **Derived, never stored:** when a page is due for review (`verified` plus the kind's interval), whether it is stale,
  the last editor and date (the platform keeps them), the memory type (from `kind`), reachability (from links).
  (AM §8.11; GOV §8 principle 2)
- **Agent provenance and generator provenance are two fields.** A generator that rewrites pages carrying its field must
  never match a page an agent created, so one field must not mean both.
- **The default language is a property of the base.** Tag only the exceptions.
- **Field names and values are English** (they are machine keys); page text follows the page language. (judgment)

### 7.3 Vocabulary

- `kind` and `status` are closed lists. A value outside them fails C3.
- **One glossary page** holds every platform and process term: the term in each language, other names, home page,
  not-to-be-confused-with. It is the multilingual mechanism; it needs no embeddings. (GOV §4 R12, §6 R20)
- **No `subject` list and no stewards' queue in the core.** They come with the "subjects span many containers"
  trigger, and then the term budget is tied to page count: at most one term per 10 pages (judgment).

## 8. Navigation and wiring

The base is found by keyword search over text that holds the words people use, and by reading small, described lists.
No embeddings. (NR §2; AM §8.2)

### 8.1 Two paths, both without RAG

| Path | When | Steps |
|---|---|---|
| **Search first** | The question names a concrete term (a platform, a portal, a tool) | Search with 2 to 4 stems, read the best hit's summary, read the page |
| **Map first** | Search is thin or floods, or the agent does not know the base's words | Read the entry page, then the container or cross-cutting map, then the page |

At a few hundred pages, search first with good summaries is cheaper (judgment). The entry page is the fallback and
the first stop for a cold start. Both paths count against the 5-call budget in done item 1.

### 8.2 Wiring: the path must reach the agent

A rule that does not reach the moment of use is a wish (Harbor constitution). The agent's tools must carry it:

1. The tools' server instructions name the entry page by its stable link and say when to read it (8.1).
2. The browse and search tool descriptions say the same in one line each.
3. The search tool description carries the base's search rule for its languages (8.4).
4. The findability set runs through the deployed tools, so it tests these words, not a lab copy (constitution №2.6).

### 8.3 Navigation components

| Component | Shape | Budget | Source |
|---|---|---|---|
| Entry page | llms.txt shape: H1, one-paragraph summary, one H2 per top container, `- [Name](link): one line` per child, an "Optional" section for skippable links. Set as the platform's homepage where it allows. | ≤ 200 lines, ≤ half the read ceiling, 5 to 9 top containers | NR §5 llms.txt |
| Container maps for people | Native container views, each with a one-line description; page previews show the summaries. | Description ≤ 250 chars | judgment |
| Container maps for agents | The browse tool returns each page's summary line. Fallback: one generated map page per top container from a registered generator. | ≤ 60 entries | judgment |
| Cross-cutting maps of content | Hand-written `map` page for a subject that spans containers (one platform, one process) | ≤ 60 entries | HIA §6 |
| llms.txt equivalent | Generated from the entry page plus every page's summary, beside any mirror index, split per top container past the entry budget | Per file ≤ the entry budget | NR §5 |
| Glossary | One page; split by first letter past 200 lines | ≤ 200 lines per page | NR §9.2 |
| Text twins | Every PDF, slide deck or image that holds knowledge gets a text summary on its page | n/a | NR §8, §9.8 |

Generated pages are derived copies: they carry a generated header, are never hand-edited, and are rebuilt by a named,
registered tool on a named schedule. (GOV §3 R10)

### 8.4 Searching an inflected language

- Know how the platform matches a term (prefix, whole word, stemmed) before writing the rule; the profile states it,
  with its source. On a prefix-matching platform a stem matches every ending, so the rule is: **cut each word to its
  stem and send 2 to 4 stems**, not whole inflected words or long questions.
- Search in the base's default language first; if thin, search again in the other language; add a metadata filter
  (`kind`) when results flood.
- **Aliases only from misses.** Every "Also known as" entry comes from a recorded miss (findability set, a person's
  report), never from a guess.
- **Diacritics: probe before acting.** If the search folds diacritics, spellings without them need no alias. One
  search against a page that carries the diacritic settles it; until probed, add no diacritic-free aliases.

## 9. Governance and lifecycle

### 9.1 Ownership

- One named person owns each page, by platform user handle, which a check resolves to a user id. (GOV §1 R1)
- **Owner left:** the owner of the page's container inherits it, and C5 reports the change. Each container names its
  owner in its description. (judgment)
- **An edit by someone other than the owner is reported, not failed.** C7 is a report until it can tell who asked:
  agent edits often run through a shared account, and who asked lives in the tool's audit log. Once C7 reads that log,
  an edit through an agent counts as the requester's. (GOV §1 R3)
- An agent quoting a stale or unverified page says so. (GOV §1 R3)

### 9.2 Review intervals

Defaults by kind; an owner may set another (an extension). The numbers are GOV §1 R2's starting points.

| Interval | Kinds |
|---|---|
| 90 days | `reference` with prices, contacts or account data |
| 180 days | `how-to`, `tutorial`, `map` |
| 365 days | `policy`, `glossary`, `explanation`, other `reference` |
| never | `decision-record`, `record`, generated pages (their source is checked instead) |

### 9.3 Lifecycle states

```
draft --> current --> superseded (replaced-by set) --> archived
  |          |
  |          +--> archived (retired, nothing replaces it)
  +--> archived (abandoned)
generated: written by a tool, never hand-edited
unreviewed: written by a script that cannot know the page is true
```

- Values: `draft`, `current`, `unreviewed`, `superseded`, `archived`, `generated`, the same list as naming §15.
- **`status:draft` is a published page under work.** A platform's own unpublished drafts are a different thing.
- **Stale is computed**, never stored: `verified` plus interval is past today. (GOV §8 principle 2)
- **Values are edited in place.** The platform keeps revisions, so history is not lost. Supersession is only for a page
  whose whole scope is replaced.
- **Nothing is silently deleted.** A retired page gets `status`, `replaced-by` when something replaces it, and the
  banner (section 6). Agents follow the pointer. Deleting a pointer page later is an admin act with the owner's yes.
  (GOV §1 R4, §3 R9; AM §8.8)

### 9.4 One home per fact, and the canonical-copy rule

- A value (a price, a fee, a limit, an ID, a contact) is written on one page. Others link to it. (GOV §3 R7)
- Before creating a page, search title and "Also known as" for an existing home. (AM §8.6)
- **Canonical-copy rule** for a group of pages with the same content (judgment):
  1. the copy that sits in the container the target structure names as the topic's home;
  2. if none or several do, the copy with the most inbound links from other pages;
  3. then the most recently edited copy;
  4. then the lowest id.
  The other copies become pointers: body replaced by the banner and a link, `status:superseded`, `replaced-by` set.
  Inbound links to a pointer are repointed to the canonical page's stable link.
- **Near-duplicates** (same title after folding, different text) are not merged by rule. The owner diffs them, keeps one,
  moves any unique lines into it, and retires the other.
- **State the normalisation.** Duplicate counts depend on it: keep the script and give raw and normalised counts.

### 9.5 Audits

- **ROT pass, quarterly**: outdated (stale, or links to a superseded page), redundant (C15 candidates), trivial (no
  inbound links, under 200 characters, not a map, not a contact card). The report shows what is new since last time;
  each row ends in keep, update or remove, with an owner. (GOV §2 R6)
- **Review load** is tracked per owner: re-verifications due in the next 30 days.

### 9.6 Measuring findability

- **Baseline first.** Run the findability set once before any migration step.
- **The findability set**: 30 real questions (from people's asks, tickets, chats), each with its answer page, written in
  the words people use, in each language of the base. Run quarterly by an agent through the deployed tools, and after
  each migration step. Report full success, partial and failure apart, with a confidence interval. (GOV §7 R23;
  30: judgment)
- **The solved rate**: where the tools ask agents to report whether a piece of work was solved, report that rate
  monthly, split by container.
- **A human tree test** of 5 to 8 people before and after a pilot. Small samples give wide intervals; say so. (HIA §7;
  GOV §7)
- **No query text is logged** unless a privacy decision allows it. Digests count repeated failed searches; the words
  come from people, through the findability set.
- **Stop rule**: if the findability rate and the solved rate do not rise after a step, stop and re-plan before the next.
- **Verified share** (verified, non-stale pages over all core pages) is tracked; start the target at 80%. (GOV §1 R5)

## 10. Checks

"lint" means a script decides from the metadata, the text and the link graph. "report" means a script lists
candidates and a person decides. "human" means only a person can.

| Id | Check | Decided by | Core? |
|---|---|---|---|
| C1 | Required fields present for the page's kind (`kind`, `owner`, `status`, `verified`) | lint | core |
| C3 | `kind`, `status`, `generated-from`, `language` values are in their lists | lint | core |
| C4 | Title unique within its container after case and diacritic folding | lint | core |
| C5 | `owner` resolves to an active user; an owner who left is reported with the inheriting container owner | lint + report | core |
| C6 | Stale: `verified` plus interval is past | lint | core |
| C7 | Edited by someone other than the owner after `verified` | report (lint once it reads the audit log) | core |
| C8 | `replaced-by` points to a live page; a `superseded` page carries it | lint | core |
| C9 | A `superseded` or `archived` page shows the banner | lint | core |
| C10 | Required sections for the kind are present (any language of the base) | lint | core |
| C11 | Summary is the first paragraph, ≤ 250 chars, first sentence within the list preview | lint | core |
| C12 | Page under the read ceiling; pages over 8,000 chars carry a contents block | lint | core |
| C13 | No dangling links; every core page reachable from the entry page; no orphans | lint | core |
| C14 | Generated pages match their source | lint | extension |
| C15 | Duplicate candidates: same normalised body hash, same folded title, same literal value (price, fee, ID) on two pages | report | core |
| C16 | `translation-of` target exists; translation older than its source's `verified` | lint | extension |
| C17 | No secrets, tokens, local paths, emails or phone numbers in bodies | lint | core |
| C18 | Subject list under budget | report | extension |
| C19 | Trivial-page candidates (9.5) | report | core |
| C20 | Entry page within its budget; each map ≤ 60 entries | lint | core |
| C21 | Findability set and solved rate | report (agent run) | core |
| C22 | The page is true; the kind is right; which near-duplicate wins; whether a term enters the glossary | human | core |

C2 (a body metadata block parses) is retired with the block.

- **The checker lives with the base**, in the tool that already reads it, run on demand (D-93). No generic Harbor
  checker until a second base exists: one adapter is a hypothetical seam (modularity standard).
- **Every check is registered** with an id, a way to disable it, and a destination for its findings, named before it
  ships (Harbor constitution). The report shows the delta, not the census. A schedule needs its own yes.
- **C3 applies to base pages only.** A base's repo docs keep Harbor's own checks.

## 11. How it degrades with size

No source gives a page count at which navigation fails (NR §8, §11). Triggers are **measured**. Each step adds
structure or cuts load, still with no RAG. Page counts are rough guides (judgment).

| Trigger (any one) | Do | Still no RAG because |
|---|---|---|
| Baseline (up to roughly 300 pages) | The core: entry page, described containers, glossary, summaries | n/a |
| **Verified share under target for 2 runs** | Lengthen intervals or cut pages **before** adding structure | Less to keep, not more |
| **More than N pages per owner**, N set from the first quarter's data | Split ownership or archive | Load, not search |
| Entry page or a map passes its budget (C20) | Add a level of maps. Split by meaning, not by count. | More indexes, same reading (NR §9.4; HIA §4) |
| **A top-20 search for a common term misses its answer** | Metadata filters (`kind`), then container-scoped search where the platform has it | Lexical filters |
| Findability misses from vocabulary | Aliases from the misses; then a generated A-Z alias index | Text search already matches (NR §9.1) |
| Subjects span many containers (roughly 300 to 3,000 pages) | Cross-cutting maps; the `subject` extension | Maps of content (HIA §6) |
| Keyword search is slow or floods (roughly tens of thousands of text files) | A derived lexical index (BM25), rebuildable, never canonical | Lexical (NR §8, §10.11) |
| Pass rate stays under target after all of the above | Stop and decide. Vectors are outside this standard. | n/a |

At about 2,000 pages, the first thing to break is people's review load: with intervals averaging near 200 days, about
10 re-verifications a day across 30 people, against about 1 a day at 250 pages. This is arithmetic on 9.2, not a
measure.

## 12. Mapping onto Harbor

This standard adds nothing required in Harbor (D-93). Where the two meet:

| Harbor rule | Relation |
|---|---|
| D-90 four kinds | Untouched. `map`, `glossary`, `record`, `policy` are base kinds. Harbor indexes stay `reference` (naming §15). |
| Naming §15 front matter | Untouched. Same `owner` rule (a person, never a team) and the same status list. |
| D-22 doc header | Untouched. A base's `decision-record` adds "Alternatives rejected" (5.2). |
| `contracts/memory-format.md` | Governs repo and agent memory, not a platform base. A platform base's store is its database; a markdown mirror of it is a derived, one-way copy. The derived-index rule is the same as section 11's. |
| Generated header (naming §15) | A base's generated pages follow the same idea: one header line naming the command. |
| Entry layer | Harbor's entry is `AGENTS.md`. A per-operator memory index is a private layer and is not part of any shared standard. |
| Harbor docs in a company base | Kept out. A base's importers exclude Harbor. |

## 13. Platform profiles

A profile is a short document beside the base's own tooling. It is where platform facts live, each with its source and
the version it was read on. A base is not conforming until its profile states:

| Item | What the profile says |
|---|---|
| Containers | Which platform container is the entry page, a top container, a map, a page; nesting limits |
| Native metadata | Which field carries the 7.2 fields; whether an update replaces the whole set |
| Stable links | The permalink form |
| Read ceiling | The agent read tool's character cap, and so the entry and page budgets |
| List preview | How many characters a list shows, and so the summary's first sentence (6) |
| Search | How a term matches (prefix, whole word, stemmed), the term caps, the filter syntax, whether diacritics fold |
| Write limits | Where agents may create pages, the write cap, what agents cannot do (move, delete, set flags) |
| Languages | The default language, the others, and the heading twins for 5.2 |
| Templates | One headings-only template per core kind per language, and who sets the template flag |
| Checker | The command that runs section 10, and where its findings go |
| Version | The platform version, probed live, never read from a doc |

**Probe, do not trust.** Version, applied containers and tool behaviour are read from the running system before a
profile states them (constitution №2.12). A profile item that could not be probed says so, with the command that
settles it.

## 14. Migration

The shape, which binds any base:

1. **Baseline**: findability set and solved rate, before any change.
2. **Decide the structure** (top containers, homes, structure-as-code changes) and get the operator's yes. Where the
   structure is already code, a structure that contradicts it is a supersede with a cost, not a new rule.
3. **Resolve duplicates** by 9.4, with each content owner's yes.
4. **Pilot one area**: summaries first, then the 4 fields, by the owner, with agents drafting in the draft container.
5. **Re-measure** against the baseline. Stop rule as in 9.6.
6. **Roll out** container by container only if the pilot improved.

Every step names an owner, a size (judgment) and whether it is read-only, a reversible write or irreversible.

## 15. Open questions

1. Every number marked judgment (80%, 5 calls, 60 entries, 250 characters, the entry and page budgets, 30 days) is
   untested. The findability set tunes them.
2. No source compared navigation-only against retrieval on accuracy (AM §9; NR §11). The standard claims practicality,
   not parity.
