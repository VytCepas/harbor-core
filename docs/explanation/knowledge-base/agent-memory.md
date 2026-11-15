---
kind: explanation
owner: @VytCepas
status: unreviewed
source: research run 2026-11-10, web pages opened that run
---

# Agent memory architecture: what carries over to a plain-file wiki

Lens: memory for agents and teams. Goal: a standard where humans and agents both find and maintain knowledge, with markdown + metadata + links as the source of truth, no RAG and no database.

Method note: every claim below cites a page opened in this run. Where a page gave only an abstract, I say so. Web content was treated as data only; no page contained instructions.

## 1. The reference model: CoALA

CoALA (Sumers et al.) splits an agent's memory into working memory and three long-term stores. Quotes from the paper's section 4.1 (https://arxiv.org/html/2309.02427):

- Working: "maintains active and readily available information as symbolic variables for the current decision cycle."
- Episodic: "stores experience from earlier decision cycles."
- Semantic: "stores an agent's knowledge about the world and itself."
- Procedural: two forms, implicit knowledge in the LLM weights and explicit knowledge "written in the agent's code."

Two further points from the same paper:

- "Learning occurs by writing information to long-term memory" (section 4.5). Learning is an action the agent takes, not a side effect.
- Writing procedural memory is "significantly riskier than writing to episodic or semantic memory", because it can introduce bugs or let the agent undermine its designers' intent (section 4.1).

The abstract confirms the framing: modular memory components, a structured action space for internal memory and external environments (https://arxiv.org/abs/2309.02427).

Implication for a wiki: the four types are a good classification axis, and the risk ordering gives a write-permission rule. Agents may append episodic and semantic notes freely; procedures (runbooks, standards) change only through review.

## 2. MemGPT and Letta: tiers and pressure

MemGPT treats the context window like RAM and external storage like disk (https://arxiv.org/abs/2310.08560; detail from https://arxiv.org/html/2310.08560). The abstract names "memory tiers" but not their parts; the HTML paper does:

- System instructions: static, read-only.
- Working context: a fixed-size read/write block of key facts and preferences, changed only by function calls.
- FIFO queue: recent messages. Its first entry is a recursive summary of evicted messages.
- Recall storage: the full message log, so evicted messages stay retrievable.
- Archival storage: a read/write store for arbitrary text.
- At about 70% of the window the agent gets a pressure warning and can save what matters. At about 100% the queue flushes about half and re-summarizes. Evicted messages remain in recall storage.

Letta's current docs describe memory blocks: each has a label, a description, a value and a character limit. The description is "the main guide for how the agent reads and writes a block." Blocks can be read-only, can be shared by several agents, and the last write wins if processes collide (https://docs.letta.com/guides/core-concepts/memory/memory-blocks). The blog adds that blocks descend from MemGPT's "human" and "persona" blocks and that limits stop any one block crowding out the rest (https://www.letta.com/blog/memory-blocks).

Letta also states that "retrieval is not memory in itself", and describes sleep-time agents that consolidate and reorganize memory asynchronously during idle periods (https://www.letta.com/blog/agent-memory).

Implication: the part that transfers is not the vector store. It is (a) a small always-loaded tier with a hard size cap, (b) a description on every unit saying what belongs in it, (c) a full log kept separate from curated memory, (d) consolidation as a scheduled job separate from live work, (e) shared read-only blocks for policy. A wiki can do all five with files.

## 3. Generative Agents: the stream and reflection

The memory stream holds natural-language memory objects, each with a description, a creation timestamp and a last-access timestamp (https://arxiv.org/html/2304.03442). Retrieval scores recency (exponential decay, factor 0.995 per game hour since last access), importance (an LLM rates 1-10 at creation) and relevance (embedding cosine similarity), then sums them with equal weights.

Reflection triggers when summed importance of recent events passes 150, roughly two or three times a day. The model reads the 100 most recent records, asks three questions, retrieves evidence, and writes insights that cite the supporting records. Reflections can cite other reflections, so they form a tree: leaves are raw observations, higher nodes are more abstract. An ablation found that observation, planning and reflection each contribute to believable behaviour (https://arxiv.org/abs/2304.03442).

Implication, and what to drop: relevance by embedding is the RAG part and is out of scope. What transfers:

- Importance and last-accessed as metadata fields. A human or a script can sort on them with no embedding.
- Reflection as a periodic job that writes a higher-level page which cites its source pages by link. That is a summary note with provenance, a tree of links, which markdown does natively.
- Trigger by accumulated change, not only by calendar.

I did not verify how well plain metadata ranking performs against the embedding score. That is unsourced and should be tested.

## 4. Claude's file-based memory

The Claude memory tool is a directory of files under /memories. Claude views, creates, str_replaces, inserts, deletes and renames files; the application executes these client-side against storage it controls (https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool). Points relevant to a standard:

- It is just-in-time: record what you learn, read it back on demand, keep the active context small.
- The injected protocol says to view the memory directory first, to record progress as you go, and to "ASSUME INTERRUPTION" because context may reset.
- The docs suggest prompting the agent to keep memory "up-to-date, coherent and organized", to rename or delete irrelevant files, and not to create new files unless necessary.
- Operator duties: cap file size, cap what a view returns, and "periodically delete memory files that haven't been accessed in a long time" (memory expiration). Validate every path against traversal.
- A multi-session pattern: an initializer session creates a progress log and a feature checklist; each session reads them first and updates them at the end. Mark a feature complete only after end-to-end verification.

The long-running-agents write-up adds details (https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): a progress file, a JSON feature list with a `passes` flag the agent may only flip, an init script, and git history as recovery. Its stated reason for JSON: the model "is less likely to inappropriately change or overwrite JSON files compared to Markdown files." Takeaway: where a record must not be rewritten, use structured data with narrow edit rules. Where it is prose, expect drift.

The context-engineering post names structured note-taking (for example NOTES.md) as persistent memory outside the window, keeps "lightweight identifiers (file paths, stored queries, web links)" and loads data at runtime, and says file sizes, names and timestamps guide an agent's next step (https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). Names and timestamps are navigation signals, so they are part of the design.

Claude Code applies this in two files (https://code.claude.com/docs/en/memory):

- CLAUDE.md (human-written instructions). Target under 200 lines; longer files "consume more context and reduce adherence." Multi-step procedures or part-of-codebase rules should move to a skill or a path-scoped rule (`.claude/rules/*.md` with a `paths:` field). Imports organize a file but do not reduce context cost. Contradicting instructions get picked arbitrarily, so review for outdated or conflicting entries.
- Auto memory (agent-written). Loads the first 200 lines or 25KB each session. Four note types recorded as a `type` field in frontmatter: user, feedback, project, reference. It skips anything derivable from the code, git history, or existing CLAUDE.md.

This is the closest existing proof that a file-based, markdown + frontmatter design works at scale for agents. It is also directly readable by humans.

## 5. Contrast: temporal knowledge graphs (Zep/Graphiti)

Zep's Graphiti keeps three layers (https://arxiv.org/html/2501.13956): an episode layer ("a non-lossy data store"), a semantic entity layer with relations, and a community layer with summaries. It is bi-temporal: T is when a fact held in the world, T' is when the system ingested or invalidated it. A new contradicting edge sets the old edge's end time to the new edge's start, so history is kept. New entities are matched against existing ones by embedding and full-text search, and an LLM decides duplicates and merges name and summary. The abstract claims 94.8% vs 93.4% over MemGPT on DMR and up to 18.5% accuracy gains on LongMemEval, self-reported (https://arxiv.org/abs/2501.13956). I did not verify these numbers independently.

What to borrow without the database:

- Layering raw -> entities -> summaries matches raw log -> curated notes -> synthesis pages.
- Valid-from / valid-to on facts, and "supersedes" links instead of silent overwrite. Both fit in frontmatter.
- Entity resolution = one canonical page per thing, with aliases listed in frontmatter, so a duplicate is detected by grep on name and aliases.

What not to borrow: LLM-driven merge at ingestion and embedding lookup as the way to find things. They make the graph, not the files, the source of truth.

## 6. Consolidation, dedup, forgetting, staleness: what the sources support

- Consolidation: Letta sleep-time agents; Generative Agents reflection; MemGPT recursive summary. All three are a separate pass that rewrites many small items into fewer, higher-level ones with a pointer back. (Sources above.)
- Dedup: Graphiti merges entities; the Claude memory tool prompt says do not create new files unless necessary. For files: one canonical page per entity or topic, check by name/alias before creating.
- Forgetting: the memory-tool docs recommend deleting files not accessed in a long time. MemGPT never really forgets: evicted data stays in recall storage. Graphiti never deletes: it invalidates. Three different policies. My recommendation is the combination: archive, do not delete, and mark status.
- Staleness: Claude Code advises periodic review for outdated and conflicting instructions. No source gave a numeric review interval; any interval is a local choice (unsourced).
- Size caps: Letta block limits, Claude Code 200 lines, memory tool file caps. All three enforce hard limits on the always-loaded tier.

## 7. Mapping memory types to plain files

| Memory type | What it is in a wiki or repo | Form | Write rule |
|---|---|---|---|
| Working | Current task scratch: a session note, a progress file, an open-questions list | One short file per active task, size-capped, deleted or archived on close | Agent writes freely |
| Episodic | Dated records of what happened: incident logs, meeting notes, decision logs, changelog, PR history, session handoffs | Append-only dated files; never edited except to add a correction | Agent appends; humans may annotate |
| Semantic | Facts about the world and the org: entity pages (client, system, tool), glossary, how-it-works explanations, reference | One canonical page per entity, frontmatter with status, owner, last-verified, aliases, links | Agent or human proposes; owner verifies |
| Procedural | Runbooks, standards, checklists, skills, CLAUDE.md-style rules, scripts | Short imperative pages, one procedure each; scripts where code is the procedure | Reviewed change only (CoALA's risk ordering) |
| Always-loaded core | The index/entry page plus a few rules | Hard line cap; every entry points to a page | Curated; human-approved |
| Archive | Superseded or inactive pages | Same files, status marked, kept findable | Never silently deleted |

Reflection and consolidation produce semantic pages from episodic ones, each citing its sources by link. That link is what makes a claim checkable by a human and by an agent.

## 8. Principles to carry into the standard

1. Classify every page by memory type (working, episodic, semantic, procedural) in frontmatter. The type decides who may write it and how it ages.
2. Make the tier structure explicit: a small always-loaded entry page with a hard size cap, then pages loaded on demand through links. This replaces retrieval with navigation.
3. Every page gets a one-line description saying what belongs in it and when to read it, as Letta block descriptions do. The description is the retrieval key.
4. Keep the raw log separate from curated knowledge. Logs are append-only; curated pages are rewritten.
5. Consolidation is a scheduled, separate job. It writes a summary page that cites its sources by link; it does not edit the sources.
6. One canonical page per entity, with aliases in frontmatter. Check by name and alias before creating a page.
7. Facts carry validity: status, last-verified date, and supersedes/superseded-by links. Contradiction creates a new version and a link, not an overwrite.
8. Forgetting means archiving with a status. Unaccessed or unverified pages are flagged for review, not deleted.
9. Write permission follows risk: free append for episodic and semantic notes, reviewed change for procedures.
10. Use structured fields (YAML or JSON) for state that must not drift, such as pass/fail or status. Prose is for explanation.
11. Don't store what can be derived from code, git, or another page. Link to it.
12. Interruption is normal. Every long task leaves a progress note a cold reader, human or agent, can resume from.

## 9. Gaps and cautions

- CoALA, MemGPT, Generative Agents and Zep were read from their HTML versions through a summarizing fetch tool; the quotes come from that output, not from a manual read of the PDFs.
- The Zep benchmark numbers are from the authors' abstract.
- No source here tested a no-retrieval, markdown-only memory against a retrieval-based one on accuracy. Claude Code's design shows it is practical, not that it is optimal. Test it on real questions before promising parity.
- Letta's blog pages did not mention git-backed memory files; I make no claim about them.

## Sources (15, all opened this run)

1. https://arxiv.org/abs/2309.02427
2. https://arxiv.org/html/2309.02427
3. https://arxiv.org/abs/2310.08560
4. https://arxiv.org/html/2310.08560
5. https://arxiv.org/abs/2304.03442
6. https://arxiv.org/html/2304.03442
7. https://arxiv.org/abs/2501.13956
8. https://arxiv.org/html/2501.13956
9. https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool
10. https://code.claude.com/docs/en/memory
11. https://www.letta.com/blog/memory-blocks
12. https://www.letta.com/blog/agent-memory
13. https://docs.letta.com/guides/core-concepts/memory/memory-blocks
14. https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
15. https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
