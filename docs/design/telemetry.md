# Telemetry: one stream system (harbor#1181)

**Status:** decided by the operator 2026-10-09; built lane by lane (#1181). Lane 0 is #1182, lane 1 is this
document plus `CONTRACTS/streams.tsv`. Research behind it: `~/Deliverables/2026-10-09-research-collection-scan/`.

## Why

Harbor has no logging system. It has ~18 independent logs, ledgers and state files (`CONTRACTS/streams.tsv`) under
two roots, with eight-plus schemas and six retention habits. Three defects follow from that:

- **Loss.** One-generation rotation destroyed 2026-08-06..10-04 of the guard ledger (fixed by #1182). The bus prunes
  at 14 days, transcripts at 30, and fleet, CI and receipt state is overwritten, so it never had history.
- **Forgery.** The guard ledger is Edit/Write-denied, but a Bash `>>` into it is an expected allow
  (`tests/guards/bash.config.jsonl`, case cfg280); usage, the bus, obligations and `checks.log` have no protection.
- **Coupling.** Readers hard-code each other's private files; nothing says which streams exist.

## The decided shape

1. **One contract.** A producer appends one JSON line (≤ 4 KB) to `$HARBOR_SINK/<stream>/<YYYY-MM-DD>/<writer>.jsonl`.
   One file per writer per day: no lock, no interleaving. Producers import nothing, so Python, Bun and the research
   repos (`guard-replay`, `skill-paths`) comply; with `HARBOR_SINK` unset they write `./runs/` and stay portable.
2. **One envelope**, the event bus's extended: `v, id, ts, stream, sess, seq, src, repo, cause, attrs, prev`.
   `seq` and `prev` (hash of the previous line in the file) make gaps and edits visible. OTel GenAI names go inside
   `attrs` where they fit. The guard path keeps its single bounded `printf` to a pre-created file: a guard that forks
   or blocks on logging can hang, and a hung guard is a bypass.
3. **One registry**, `CONTRACTS/streams.tsv` (protected). Lane 1 records today's estate and is held to the code by
   `tests/checks/streams-registry-test.sh`; lane 3 adds the lint that fails an unregistered writer.
4. **One store, at the collector.** Writers keep their files where they are (moving the bus, obligations, usage,
   `checks.log` and approvals would ripple through every reader); the second-uid collector copies every source into
   ONE store it alone can write, `/Library/Application Support/Harbor/collector`, so history outlives the writers'
   own pruning (the bus at 14 days) and rewriting (usage's daily merge). New `harbor_emit` streams land in
   `~/.claude/MEMORY/OBSERVABILITY/<host>/streams/` (private, gitignored). Closed days are signed daily. (Lane 4, revised
   2026-10-10: the decided hot-90-days and Parquet archive are not built; the store keeps everything uncompressed.)
5. **Failure policy** per row: `block` only for approvals and deploys; every other stream spills to a fallback file,
   counts the drop and raises one alert. Never `|| true`, never a hang on the guard path.
6. **Privacy at write time.** Per-stream key allowlist; HMAC-keyed identifiers; no prompts, commands or tool output
   in durable streams; a secret-shape scrubber plus an independent scheduled gitleaks pass.
7. **Safety, by tier** — and every claim says which tier it rests on:
   - *Accident (same uid):* append-only layout, the `prev` chain, a guard rule blocking Bash
     redirects into the store. A same-uid process can still rewrite and re-hash its own files.
   - *Boundary (second uid):* a launchd collector running as `_harborlog` ingests the writers' spool and Claude Code's
     own OTLP stream into a store only it can write, marks every store file append-only (macOS `uappnd`, Linux
     `chattr +a`: an accident guard, root can clear it), and signs a daily checkpoint
     `{origin, size, head hash}` with `ssh-keygen -Y`.
     On Linux the same jobs are systemd system units under `harborlog`; the ingest unit reads through
     `CAP_DAC_READ_SEARCH` instead of an ACL, because a POSIX ACL's mask is reset by the floor's own `chmod 0600/0500`
     and the collector would go blind at every SessionStart (macOS keeps ACLs: chmod leaves them alone there).
   - *Anchor and cross-check:* `collector-check.sh` copies every signed checkpoint, once and never overwritten, into
     `MEMORY/CHECKPOINTS/<host>/`, which `worklog-push.sh` pushes to the private MEMORY remote (off-host); a published
     checkpoint that later differs from its anchored copy is `checkpoint-changed`. It also compares the day's count of
     the client's own `tool_decision` events (pinned in managed settings, out of a session's reach) with the guard
     ledger's tool-call rows: 20+ decisions and no row is `guard-silent`. Detection, not prevention.
8. **Native telemetry** is pinned in `/Library/Application Support/ClaudeCode/managed-settings.json` `env`, with
   every content flag off, and `cleanupPeriodDays` is 365 there too.
9. **Query** through DuckDB views behind `harbor logs query`; statusline, checks and reports read views or a
   cache rebuilt from streams, never another component's file.

## Lanes

The lane table and its order live in #1181; `CONTRACTS/streams.tsv` names the lane that moves each stream.
