---
kind: explanation
owner: @VytCepas
status: unreviewed
source: research run 2026-11-10, web pages opened that run
---

# How agents find documentation without a vector/RAG layer

Lens: structure docs so AI agents navigate them with list, read, grep and glob. Humans use the same structure. All web content below was treated as data. Claims marked "unsourced" or "not verified" are flagged.

## 1. Short answer

A no-RAG knowledge base works when three things are true: a small always-loaded entry point tells the agent what exists; every deeper file is reachable by a short path or link; and the vocabulary agents search for appears literally in the text. It stops working when the corpus is large, mixed-format, or queried in words the authors never wrote. The mitigations below are all text-based: aliases, keywords, summaries, controlled vocabulary.

## 2. Anthropic's position: just-in-time context, hybrid by design

- Anthropic's context-engineering article describes agents that keep "lightweight identifiers (file paths, stored queries, web links, etc.)" and load the data with tools only when needed. Exploration lets agents "incrementally discover relevant context". It names a hybrid: some data up front for speed, then exploration at the agent's discretion. Claude Code is the example: CLAUDE.md loaded up front, glob and grep for on-demand retrieval. It also states that recall accuracy falls as context grows ("context rot"), so context is a finite resource. Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Claude Code's creator is reported (secondary sources only; I could not open the original post, and the sources disagree on date) to have said early versions used RAG plus a local vector DB and that agentic search "generally works better", citing simplicity and avoiding staleness, security, privacy and reliability problems. He called the evidence mostly "vibes" plus some internal benchmarks. Treat as an anecdote, not a benchmark. Secondary: https://smartscope.blog/en/ai-development/practices/rag-debate-agentic-search-code-exploration/ and https://officechai.com/ai/claude-researcher-explains-how-agentic-search-performed-better-than-rag-for-code-generation/
- Cost of agentic search: repeated exploration adds latency and tokens (same secondary summaries, not verified against a primary).

## 3. Always-loaded layer: AGENTS.md and CLAUDE.md

- AGENTS.md is plain Markdown, "a README for agents". No required headings. Nested files are allowed; the nearest file to the edited file wins; a direct user prompt overrides all. Source: https://agents.md/
- Claude Code docs: CLAUDE.md is loaded each session; target under 200 lines per file; longer files "consume more context and reduce adherence". Imports (`@path`) organise a file but do not reduce context cost. Subdirectory CLAUDE.md files load on demand when a file in that directory is read. Path-scoped rules in `.claude/rules/` load only for matching files. Claude Code can read AGENTS.md in place of CLAUDE.md. Auto memory index `MEMORY.md`: only the first 200 lines or 25KB load at start; the rest is dropped, so the index must keep one line per entry and move detail into topic files. Source: https://code.claude.com/docs/en/memory
- Lesson: the entry point is a budgeted resource with a hard cut-off. Design it as a map, not a manual.

## 4. Agent Skills: the clearest progressive-disclosure pattern

- Three levels: (1) name and description of every skill pre-loaded; (2) SKILL.md body loaded when relevant; (3) linked files read only when needed. Because bundled files load on demand, the amount bundled is effectively unbounded. Source: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
- Authoring rules (all from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):
  - name max 64 chars, lowercase letters, digits, hyphens; description max 1,024 chars, third person, says what it does AND when to use it, with key terms. The description is how Claude picks a skill "from potentially 100+".
  - SKILL.md body under 500 lines.
  - References one level deep from SKILL.md. Nested references get partially read (Claude may `head -100` them).
  - Files over 100 lines get a table of contents at the top so a partial read still shows full scope.
  - Organise by domain (`reference/finance.md`), name files descriptively (`form_validation_rules.md`, not `doc2.md`), use consistent terminology, avoid time-sensitive text (put deprecated material in an "old patterns" section).
  - Test navigation: watch which files the agent opens; never-read files are noise; always-read files belong in the parent.
  - Evaluation first: build at least three evaluations, test on small and large models.
- Lesson: this is a hierarchical index plus lazy loading, with no embeddings. The description is the only retrieval key for level 1, so it carries the trigger words.

## 5. llms.txt and llms-full.txt

- Spec: Markdown at the site root or a subpath; required H1; blockquote summary; H2 sections of `[name](url): note` links; an "Optional" H2 for skippable links. Pages should have `.md` twins. Must stay small enough for a context window; the proposal itself says windows are still too small for most whole sites. The page I fetched does not describe llms-full.txt. Source: https://llmstxt.org/
- Real example: Anthropic's developer docs llms.txt. About 893 English pages, one bullet per page as `- [Title](url.md) - description`, about 900 lines, roughly 100 KB or about 25k tokens (the size is an estimate by the fetch tool, not measured), with a footer pointing to llms-full.txt. Many titles are generic ("Overview", "Quickstart"), so the description after the dash does the discriminating. Source: https://platform.claude.com/docs/llms.txt
- Note the scale point: a flat index of ~900 entries already costs ~25k tokens. That is too large for an always-loaded layer; it works as a fetch-on-demand file. Use nested indexes instead of one flat one.
- Evidence of use is weak. Ahrefs (137K domains, May 2026): 28% publish the file (upper bound, skewed sample), 97% of valid files got no requests; AI bots were 19.5% of requests, AI agents the largest AI group (10.5%); Claude-Code fetched it more than most retrieval bots. Verdict: little effect on AI search visibility; plausible audience is coding agents. Source: https://ahrefs.com/blog/llmstxt-study/ . Other industry tests agree but are blog-grade: https://www.optimizely.com/field-notes/articles/does-llms-txt-work/
- Implication for us: copy the format (it is a good index shape and humans can read it), not the expectation that outside crawlers will find it. For an internal wiki, the agent is told where the index is.

## 6. Tool and resource design for browsing (MCP)

- MCP resources: each has a URI, name, optional title, description, mimeType, size. `resources/list` supports pagination; resource templates (RFC 6570) expose parameterised URIs; annotations carry `audience` (user/assistant), `priority` (0.0 to 1.0) and `lastModified`. The spec says resources are application-driven: tree or list views, search and filter, or model-selected inclusion. Source: https://modelcontextprotocol.io/specification/2025-06-18/server/resources
- Anthropic's tool-writing guidance: prefer targeted search tools over dump tools (`search_logs` over `read_logs`); combine pagination, range selection, filtering and truncation with sensible defaults; Claude Code caps tool responses at 25,000 tokens by default; truncation messages should steer toward "many small and targeted searches"; offer a concise/detailed `response_format` (example 72 vs 206 tokens, about one third); replace opaque UUIDs with readable names, which "significantly improves Claude's precision in retrieval tasks by reducing hallucinations"; errors should be actionable. Source: https://www.anthropic.com/engineering/writing-tools-for-agents
- Lesson for a wiki-backed knowledge base: expose list-children, read-page, search, and a cheap "summary only" read; use readable slugs as identifiers; hard-cap response size.

## 7. Reading long text: layout inside the context

Anthropic's prompting guide: put long documents at the top of the prompt, the query after them; for long-document tasks ask the model to quote the relevant parts first, then answer. Source: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices (the guide is a very long page; I read the lines on these two points only).

## 8. Where no-RAG navigation breaks

Evidence is mixed and partly vendor-interested. Honest summary:

| Condition | What happens | Source |
|---|---|---|
| Corpus of hundreds to low thousands of plain-text docs | Grep and navigation work well; fast and precise on known tokens | https://www.llamaindex.ai/blog/is-grep-all-you-need-lexical-vs-sematic-search-for-agents (vendor of a RAG product; qualitative) |
| Millions of files | Plain grep scan "more than 4 seconds to scan 1,000,000 files" (same post). Latency, not just recall | same |
| Vocabulary mismatch | Query "revenue recognition" misses docs that say "ASC 606" or "when we record sales"; the agent must already know the corpus vocabulary | same |
| Non-text formats | Grep cannot read PDFs, scanned images, Office files | same |
| Common tokens | "Thousands of incidental matches" fill the context | same |
| Agentic keyword search on QA benchmarks | Reported competitive with RAG (one summary says over 90% of RAG metrics; another paper, "Is Grep All You Need?", found dense retrieval not strictly necessary on LongMemEval). I only saw abstracts and summaries, not full papers | search summaries of https://arxiv.org/abs/2605.15184 ; not verified |
| Scale studies | A 2026 study titled "BM25 Wins at Scale" favours lexical retrieval over graph RAG; corpus sizes not confirmed | https://huggingface.co/papers/2607.26497.md (title and abstract only) |

Practical reading: no-RAG breaks on (a) synonym and paraphrase queries, (b) corpora past roughly tens of thousands of text files without an index layer, (c) binary formats, (d) "which page covers X" queries when X has no page title. I found no source giving a precise corpus-size threshold; any number would be unsourced. Our own wiki size should be measured before relying on a threshold.

## 9. Non-RAG mitigations (text only)

These are my synthesis; each follows from the sources above, but the combination is not benchmarked.

1. **Aliases and synonyms in the page itself.** A `keywords:` or `Also known as:` line listing synonyms, abbreviations, old names, and Lithuanian and English terms. Grep then hits "ASC 606" and "revenue recognition" alike. This directly answers the vocabulary-mismatch failure.
2. **Controlled vocabulary.** One canonical term per concept, one glossary page mapping variants to it. Anthropic's skill guide asks for consistent terminology for the same reason.
3. **Summaries as navigation.** Every page opens with a 1-2 sentence summary; every folder or book has an index listing child pages with one-line descriptions (the llms.txt entry shape). The agent reads the index, not the pages.
4. **Nested indexes with a token budget.** Root index small (cap near 200 lines, as CLAUDE.md and MEMORY.md limits suggest); per-section indexes loaded on demand; never one flat list of hundreds (the 893-entry file costs ~25k tokens).
5. **Contents block on long pages** (over about 100 lines) so partial reads still show scope.
6. **Readable, stable identifiers** (slugs), not numeric ids.
7. **Search tool with caps.** Keyword search returning titles, summaries and snippets, paginated, with a 25k-token style ceiling and a hint to refine the query.
8. **Text twins for binaries.** Extract PDFs and Office files to Markdown at the same path.
9. **Freshness metadata** (`lastModified`, owner, status) so the agent can discount stale pages; MCP annotations model this.
10. **Test with real questions.** Keep a set of questions with known answer pages; measure whether the agent reaches them and which synonyms fail. Anthropic's skill guide makes evaluations the source of truth.

## 10. Principles for the standard

1. Small always-loaded entry point, hard budget (about 200 lines), a map not a manual.
2. Progressive disclosure in three levels: index line, page summary, page body.
3. Every page and folder has a "what and when to use" description with trigger words.
4. Nesting depth: links one level from the parent index; avoid chains.
5. Aliases, synonyms and bilingual keywords live in the page text.
6. One canonical term per concept plus a glossary.
7. Long pages carry a contents block and a summary at the top.
8. Readable stable slugs; flat predictable paths.
9. Bounded tools: search returns summaries, paginated, size-capped, with refine hints.
10. Text-first: every binary has a Markdown twin.
11. State the limits: if the corpus or query type passes the measured threshold, add a search index. A lexical index (BM25) is still not RAG with vectors.
12. Evaluate with a question set; do not rely on llms.txt being discovered by outsiders.

## 11. Gaps

- No primary source for the Claude Code creator's statements; secondary only.
- No sourced corpus-size threshold for no-RAG failure.
- Academic papers seen as abstracts and summaries only.
- llms-full.txt: referenced by Anthropic's file; the llmstxt.org page I fetched does not describe it.
- Ahrefs and Optimizely are industry studies, not peer-reviewed.
