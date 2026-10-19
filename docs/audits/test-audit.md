# Test-suite audit (harbor#667)

**Measured 2026-09-24 against `main` `54bd65c`.** Every number below was derived that day. Re-derive it with the method at the bottom rather than trusting it later: a count in a document is a copy, and copies drift.

The audit asks two questions of every suite: **what does it cost in CI**, and **can it still fail**. #667 has five steps. Their state:

| step | state |
|---|---|
| 1 · inventory: every suite, its CI job, measured runtime, what it guards | **done** — the table below, all 73 tracked test files |
| 2 · bypass forensics from git history | **done** — 71 candidate commits read; verdicts below |
| 3 · mutate every suite once | **PILOT, 15 suites (2026-10-02)** — 11 went red, 4 cannot catch their own code breaking (harbor#905); see § Step 3 below. The other suites are not yet mutated, and this step stays open on #667. The "plants a violation" column is still a *static* read |
| 4 · classify keep / merge / delete / repair | **partial** — repairs for every live bypass; no suite found duplicated; no deletion proposed until step 3 says which suites cannot fail |
| 5 · cut CI time on the evidence | **evidence only** — the critical path is named below; the cuts are owned by #531 and #679 |

## Summary

- **73 tracked test files.** 70 are `bin/*-test.sh`, and all 70 are in `CONTRACTS/suites.txt`; the manifest names no missing file. The other **3 sit outside `bin/`, where lint C3 cannot see them**, and 2 of those 3 are run by no CI job (#695).
- **No suite runs twice.** Every suite with its own CI job logs `skip … (has its own job)` in the manifest shards.
- **The longest single job is now `lint-test.sh`**, with a median of 646 s (range 377–823, n=6). The floor suite, sharded by #688, runs 182, 246 and 257 s per shard (n=2). `lint-test.sh` is where the next CI-time cut is, and the `--only` conversion in #531 is the measured lever.
- **Planted-violation arms: 61 yes, 10 partial, 2 no** (`normalize-test.sh`, `doctor-test.sh`). "Partial" means the only red cases are bad inputs fed to an unmodified tool. This does **not** compare with August's "2 of 44", which used a narrower rubric.
- **History:** 71 commits matched a bypass or net-assertion-removal pattern. Reading each diff gave **63 clean, 4 weakened, 4 bypassed**, and all 8 were still live on `54bd65c`.
- **Suites that could not fail in CI, seen in the logs:** `secret-test.sh` printed `0 passed, 0 failed (all skipped …)` and `gcloud-creds-test.sh` printed `0 passed, 0 failed (10 skipped …)`. Both were a preflight skip that also swallowed a broken tool. Both are repaired below.

## Findings, and what happened to each

| finding | suite · commit | status |
|---|---|---|
| An empty read-back was always taken as "Keychain unreachable", so a `secret` that stores nothing printed SKIP and exited 0 — on this box too, where the Keychain opens. The fix commit's own message says "a no-op `secret` produces the skip at exit 0" | `secret-test.sh` · `123362f` | **FIXED** in this PR. `security` itself is the witness: the Keychain opens and the tool read nothing → red |
| The Keychain skip also covered T1 (never snapshot an empty store) and T4 (never restore over live credentials), which refuse *before* `secret` is called, so the two most important properties were never asserted in CI. A broken `putfile` also read as a skip | `gcloud-creds-test.sh` · `0298ec3` | **FIXED** in this PR. T1/T4 run first on every box, asserting the tool's REFUSING line and an unchanged store; the skip needs `security` to fail too |
| A missing `vendor/archify` (71 tracked files) skipped both renderer self-tests, the same as a missing `node` | `skill-gates-test.sh` · `6dfb080` | **FIXED** in this PR. Absent is a failure; a missing `node` still skips |
| The SHARED TREE alarm assertion went from "leftmost" to "anywhere" when the zones were reversed, so the token moved into the ambient zone passes | `statusline-test.sh` · `865a228` | **FIXED** in this PR. The property is asserted: an alarm survives the narrow tier, which drops the ambient zone |
| The live arm accepted any exit 2 as a skip, and fell back to the reason "backend unavailable" when none was printed | `browser-test.sh` · `e2a4b6e` | **FIXED** in this PR (latent: exit 2 only comes from genuine skips today) |
| **The live arm drives a consented browser session into a client's live site, on every CI run that selects it:** 6 of 6 sampled runs printed `--self-test-live: 3 passed` | `browser-test.sh` | **NOT FIXED — #694**, the operator's decision |
| C3 walks only `bin/*-test.sh`; `skills/<workload>/bin/<name>-preflight-test.sh` and `EVALS-DATA/e5trap/hooks/gate-test.sh` are run by no CI job | lint C3 | **NOT FIXED — #695** |
| replay R14 worker drops every record; prod-guard parity moved to advisory X5; obs-digest's live-ledger ruling; floor-test B9's always-pass `ok` | `61dbeae` · `1a0d619` · `024e40c` · `30c2cab` | **NOT FIXED — #696** |
| Mutate every suite once (step 3) | all | **NOT DONE** — stays on #667 |

## Per-suite inventory

Sorted by measured CI seconds. "History verdict" is the forensics result for commits to that file: `clean ×N` means N candidate commits were read and none weakened a check, and "no candidate" means no commit matched the patterns at all. The CI seconds were measured under load, with four runner processes on one Mac, and lint-test swung 2.2× between runs, so read them as rank rather than precise figures.

| suite | CI job | CI s (median) | assertions | plants a violation | history verdict | guards |
|---|---|---|---|---|---|---|
| `bin/lint-test.sh` | lint-suite (conventions linter suite) | 646 (median n=6, range 377-823) | 342 passed, 0 failed | yes | clean ×4 | lint-conventions.sh rules can each go red, tested hermetically against throwaway fixture … |
| `bin/prove-test.sh` | suite-manifest shard 2 (manifest suites… | 162.05 (median n=6, range 141.4-1… | 276 passed, 0 failed | yes | clean ×1 | prove.sh detector-recall engine: must go red rather than certify a checker that cannot fa… |
| `bin/failure-capture-test.sh` | suite-manifest shard 0 (manifest suites… | 139.95 (median n=6, range 122.7-1… | 130 passed, 0 failed | yes | clean ×1 | failure-capture.sh rules go red on their target shape, stay green on valid-unusual input. |
| `bin/inject-hook-test.sh` | suite-manifest shard 1 (manifest suites… | 106.4 (median n=6, range 84.2-131… | 191 passed, 0 failed | yes | clean ×1 | inject-hook.sh conditional note engine: fires on matching events, stays silent on ordinar… |
| `bin/cloud-guard-test.sh` | suite-manifest shard 0 (manifest suites… | 69.5 (median n=6, range 50.8-80) | 168 passed, 0 failed | yes | no candidate | guard-cloud.sh decisions: red/green and false-positive cases, classification only, no pay… |
| `bin/skill-gates-test.sh` | suite-manifest shard 2 (manifest suites… | 53.6 (median n=6, range 37.7-61.5) | 70 passed, 0 failed | yes | bypassed `6dfb080`, clean ×2 | Skill checkers' self-tests still discriminate, and the check-pack/check-topology pair rej… |
| `bin/recover-test.sh` | fast (fast suites) | 33.5 (median n=6, range 25-37) | no count line; 25 PASS lines … | yes | clean ×1 | restore.sh corrupt-then-restore in a sandbox, fail-closed refusals, kill-switch conventio… |
| `bin/floor-equiv-test.sh` | suite-manifest shard 1 (manifest suites… | 32.65 (median n=6, range 27.8-38.… | 17 passed, 0 failed | yes | no candidate | floor-equiv.sh equivalence harness must go red on a mutated guard, not just green. |
| `bin/statusline-test.sh` | fast (fast suites) | 29.5 = sh 15.5 (median n=6, range… | 236 passed, 0 failed [sh] + 2… | yes | weakened `865a228`, clean ×3 | fleet-glyph.sh statusline and SessionStart verdicts hook produce correct golden output, h… |
| `bin/inject-notes-test.sh` | suite-manifest shard 2 (manifest suites… | 26.85 (median n=6, range 20.3-29) | 123 passed, 0 failed | partial | clean ×1 | Every shipped inject.d note fires and stays silent correctly through the real inject-hook… |
| `bin/harbor-clean-test.sh` | suite-manifest shard 1 (manifest suites… | 24.9 (median n=6, range 20.9-28) | 112 passed, 0 failed | yes | clean ×1 | harbor-clean.sh cleaner: refuses to delete KEEP-class state; dry-run default, live dir ga… |
| `bin/visual-check-test.sh` | suite-manifest shard 0 (manifest suites… | 24.8 (median n=6, range 16.8-28.6) | 2 passed, 0 failed | partial | clean ×1 | visual-check.sh in CI: self-test proves it can fail; regenerable pages legible both theme… |
| `bin/issue-connector-test.sh` | suite-manifest shard 2 (manifest suites… | 23.25 (median n=6, range 14.4-32.… | 46 passed, 0 failed | yes | no candidate | issue-connector.sh label decisions via stubbed gh; every taxonomy theme glob matches a tr… |
| `bin/cu-test.sh` | fast (fast suites) | 22.5 (median n=6, range 16-24) | 766 passed, 0 failed, 0 skipp… | yes | clean ×6 | cu.sh tracker CLI: every guard and every shipped bug stays pinned, hermetically. |
| `bin/browser-test.sh` | suite-manifest shard 2 (manifest suites… | 20.25 (median n=6, range 19.1-23.… | 13 passed, 0 failed, 0 skipped | partial | bypassed `e2a4b6e` | browser.sh dispatcher: offline self-test gates, derived routing contract, honest skips wh… |
| `bin/replay-test.sh` | floor-shard-0 (security-floor shard 0 o… | 19.5 (median n=6, range 15-30) | 51 passed, 0 failed | yes | weakened `61dbeae`, clean ×1 | replay-corpus.sh and replay.sh behaviour, run hermetically against synthetic transcripts,… |
| `bin/pulse-test.sh` | suite-manifest shard 2 (manifest suites… | 17.5 (median n=6, range 9.8-19.7) | 99 passed, 0 failed | yes | clean ×1 | pulse.sh health checks and pulse-notify.sh notification edges, against hermetic fixture c… |
| `bin/worktree-test.sh` | suite-manifest shard 1 (manifest suites… | 16.15 (median n=6, range 10.7-23.… | 53 passed, 0 failed | yes | clean ×2 | worktree.sh never deletes unsafe worktrees; every refusal asserted by what survives on di… |
| `bin/merged-check-test.sh` | suite-manifest shard 1 (manifest suites… | 11.25 (median n=6, range 9.6-14.3) | 47 passed, 0 failed | yes | no candidate | merged-check.sh detects work landed by any merge method, never calling unmerged work merg… |
| `bin/destroy-guard-test.sh` | suite-manifest shard 2 (manifest suites… | 10.4 (median n=6, range 5.3-11.3) | 87 passed, 0 failed | yes | clean ×1 | guard-destroy.sh red/green and false-positive classification, against a private config di… |
| `bin/memory-test.sh` | suite-manifest shard 1 (manifest suites… | 8.75 (median n=6, range 6.5-12.9) | 68 passed, 0 failed | yes | clean ×3 | Memory store readers (memory.sh, memory-lint.sh, tools/memory) against a pinned fixture c… |
| `bin/reference-check-test.sh` | suite-manifest shard 2 (manifest suites… | 7.3 (median n=6, range 3.7-8.8) | 77 passed, 0 failed | yes | no candidate | reference-check.sh: each rule reds on its defect, stays green on valid-but-unusual input,… |
| `bin/inject-install-test.sh` | suite-manifest shard 2 (manifest suites… | 7.25 (median n=6, range 3.8-8.2) | 42 passed, 0 failed | yes | no candidate | inject-install.sh wires the govern-token announce, announced token matches engine stamp, … |
| `bin/harbor-test.sh` | fast (fast suites) | 6.5 (median n=6, range 5-9) | 26 passed, 0 failed | yes | no candidate | harbor dispatcher: contract verbs dispatch, exit codes forwarded verbatim, --json misuse … |
| `bin/store-check-test.sh` | suite-manifest shard 0 (manifest suites… | 6.25 (median n=6, range 4.1-7) | 84 passed, 0 failed | yes | clean ×1 | store-check.sh memory-store size/age bound: reports OVER when exceeded, silent on healthy… |
| `bin/govern-hook-test.sh` | suite-manifest shard 0 (manifest suites… | 5.85 (median n=6, range 4.6-8.2) | 78 passed, 0 failed | yes | clean ×1 | govern-hook.sh fires only on real merges, silent on ordinary work; known holes pinned. |
| `bin/renew-check-test.sh` | suite-manifest shard 2 (manifest suites… | 5.6 (median n=6, range 2.9-6) | 39 passed, 0 failed | yes | clean ×1 | renew-check.sh and fleet-glyph token: box-behind-repo findings, and could-not-look never … |
| `bin/mutation-tier-test.sh` | suite-manifest shard 1 (manifest suites… | 5.25 (median n=6, range 3.8-7.3) | 95 passed, 0 failed | yes | no candidate | mutation-tier.sh tier table must agree with real guard-selfedit and repo-built deny array |
| `bin/proposal-test.sh` | suite-manifest shard 0 (manifest suites… | 5.2 (median n=6, range 4.3-5.9) | 35 passed, 0 failed | yes | no candidate | proposal.sh gates: no approve verb, review signs patch bytes, machinery patches always re… |
| `bin/deliverables-guard-test.sh` | suite-manifest shard 1 (manifest suites… | 4.7 (median n=6, range 4.1-5.5) | 51 passed, 0 failed | yes | no candidate | guard-deliverables.sh red/green and false-positive classification, always against a fixtu… |
| `bin/stop-guard-test.sh` | suite-manifest shard 2 (manifest suites… | 4.35 (median n=6, range 2.9-5.1) | 66 passed, 0 failed | yes | no candidate | guard-stop.sh Stop hook classification: red/green and false-positive cases on synthesised… |
| `bin/memory-route-test.sh` | suite-manifest shard 1 (manifest suites… | 3.9 (median n=6, range 2.9-4.7) | 24 passed, 0 failed | yes | no candidate | memory-route.sh memory-store routing; starved input must stand down (exit 2), never repor… |
| `bin/port-paths-test.sh` | suite-manifest shard 2 (manifest suites… | 3.25 (median n=6, range 1.9-4.1) | 40 passed, 0 failed | yes | clean ×2 | port-paths.sh gate flags any script or config still naming a repo's pre-move address. |
| `bin/usage-aggregate-test.sh` | suite-manifest shard 0 (manifest suites… | 3.15 (median n=6, range 2.8-4) | 67 passed, 0 failed | partial | no candidate | usage-aggregate.sh aggregates synthetic transcripts correctly, never reading real transcr… |
| `bin/gcx-test.sh` | fast (fast suites) | 3 (median n=6, range 2-4) | 68 passed, 0 failed | yes | clean ×1 | bin/gcx guards and account-disclosure drift, plus the gcloud wrapper it execs into. |
| `bin/marker-test.sh` | fast (fast suites) | 3 (median n=6, range 2-4) | 37 passed, 0 failed (STATUS.m… | partial | clean ×3 | Every implementation of the marker-resolution seam (helm, project-init, orchestrator) ans… |
| `bin/prod-guard-test.sh` | fast (fast suites) | 3 (median n=6, range 2-5) | 38 passed, 0 failed (38 asser… | yes | weakened `1a0d619` | prod-guard-ambient.sh shim decides correctly when to run or stand down prod_guard; instal… |
| `bin/shim-install-test.sh` | suite-manifest shard 1 (manifest suites… | 3 (median n=6, range 2.2-4.3) | 14 passed, 0 failed | yes | no candidate | shim-install.sh installer can refuse the live directory and never destroys existing files. |
| `bin/apiroute-guard-test.sh` | suite-manifest shard 0 (manifest suites… | 2.75 (median n=6, range 1.8-4.1) | 41 passed, 0 failed | yes | no candidate | guard-apiroute.sh: no session may change Claude Code's API route; rerouted settings resto… |
| `bin/fleet-sessions-test.sh` | suite-manifest shard 2 (manifest suites… | 2.7 (median n=6, range 1.5-3) | 30 passed, 0 failed | yes | no candidate | fleet-sessions.sh liveness: recycled PIDs never alive, UTC/local start times reconciled. |
| `bin/ticket-note-test.sh` | suite-manifest shard 1 (manifest suites… | 2.7 (median n=6, range 2.4-3.6) | 43 passed, 0 failed | partial | clean ×1 | ticket-note.sh Stop-hook reminder fires on real tickets and stays silent on measured fals… |
| `bin/merge-check-test.sh` | suite-manifest shard 2 (manifest suites… | 2.45 (median n=6, range 1.4-3) | 59 passed, 0 failed | yes | clean ×2 | merge-check.sh merge backstop: refusals and protection checks never silently fail permiss… |
| `bin/constitution-install-test.sh` | suite-manifest shard 1 (manifest suites… | 2.25 (median n=4, range 1.8-2.4) | 21 passed, 0 failed | yes | no candidate | constitution-install.sh back-port gate reads history: refuses only live lines found in no… |
| `bin/module-shape-test.sh` | suite-manifest shard 1 (manifest suites… | 2.2 (median n=6, range 1.9-2.3) | 36 passed, 0 failed | yes | no candidate | module-shape.sh metric classifies ten synthetic codebases correctly, never flattering spl… |
| `bin/install-stamp-test.sh` | suite-manifest shard 0 (manifest suites… | 2 (median n=6, range 1.7-2.4) | 25 passed, 0 failed | yes | clean ×1 | install-stamp.sh deploy-regression guard: refuses deploys that would drop installed commi… |
| `bin/roots-test.sh` | suite-manifest shard 0 (manifest suites… | 1.9 (median n=6, range 1.7-2.6) | 11 passed, 0 failed | yes | no candidate | roots.sh --check fails on drifted, unregistered or dead roots; stays green on correct sha… |
| `bin/pr-wait-test.sh` | suite-manifest shard 1 (manifest suites… | 1.85 (median n=6, range 1.4-2.4) | 10 passed, 0 failed | yes | no candidate | pr-wait.sh red/green behaviour, driven by a stub gh with no network or real PR. |
| `bin/runtime-install-test.sh` | suite-manifest shard 1 (manifest suites… | 1.8 (median n=6, range 1.1-2.4) | 23 passed, 0 failed | yes | no candidate | runtime-install.sh one-word command install: links into main checkout, never overwrites u… |
| `bin/failure-observe-test.sh` | suite-manifest shard 1 (manifest suites… | 1.65 (median n=6, range 0.9-2.8) | 35 passed, 0 failed | yes | clean ×1 | failure-observe.sh sink: stable recurrence key, refusals write nothing, redactions hold, … |
| `bin/normalize-test.sh` | fast (fast suites) | 1.5 (median n=6, range 1-2) | 173 passed, 0 failed (STATUS.… | no | no candidate | floor-normalize.awk tokenizer parses commands into the correct segment table, independent… |
| `bin/suite-select-test.sh` | suite-manifest shard 0 (manifest suites… | 1.5 (median n=6, range 1.3-1.9) | 31 passed, 0 failed | yes | clean ×1 | suite-select.sh never silently drops suites from a run; hermetic fixture roots, noglob re… |
| `bin/install-drift-test.sh` | suite-manifest shard 2 (manifest suites… | 1.4 (median n=6, range 0.9-2.5) | 15 passed, 0 failed | yes | no candidate | install-drift.sh classifier reaches every verdict and stays green on byte-identical insta… |
| `bin/status-gen-test.sh` | suite-manifest shard 1 (manifest suites… | 1.35 (median n=6, range 0.9-1.8) | 12 passed, 0 failed | yes | clean ×1 | status-gen.sh suite-count cache invalidates correctly, never serving a wrong count into S… |
| `bin/deny-hash-test.sh` | suite-manifest shard 2 (manifest suites… | 1.25 (median n=6, range 0.7-1.9) | 40 passed, 0 failed | yes | no candidate | deny-hash.sh filter holds no plaintext; scan goes red on a declared term, green on near-m… |
| `bin/context-budget-test.sh` | suite-manifest shard 1 (manifest suites… | 1.2 (median n=6, range 1-1.5) | 21 passed, 0 failed | yes | clean ×1 | context-budget.sh can say OVER, verdict is deterministic and cwd-independent, summary sha… |
| `bin/skills-install-test.sh` | suite-manifest shard 2 (manifest suites… | 1.2 (median n=6, range 0.6-1.6) | 32 passed, 0 failed | yes | no candidate | skills-install.sh: each failure the verb prevents is asserted by breaking it, off live co… |
| `bin/ci-queue-test.sh` | suite-manifest shard 0 (manifest suites… | 1.15 (median n=6, range 0.9-1.7) | 11 passed, 0 failed | yes | no candidate | ci-queue.sh runner-queue ETA estimate, pinned hermetically against a fake gh. |
| `bin/skill-fire-test.sh` | suite-manifest shard 1 (manifest suites… | 1.1 (median n=6, range 1-1.5) | 16 pass, 0 fail | yes | no candidate | skill-fire.sh children get empty stdin, so sweeps are not contaminated by the answer key. |
| `bin/obs-digest-test.sh` | suite-manifest shard 0 (manifest suites… | 0.9 (median n=6, range 0.6-1.2) | 17 passed, 0 failed | yes | weakened `024e40c`, clean ×1 | floor_log_decision digest reaches guard-cloud/guard-destroy deny/ask verdicts, not only b… |
| `bin/save-log-token-test.sh` | suite-manifest shard 0 (manifest suites… | 0.7 (median n=6, range 0.6-0.9) | 17 passed, 0 failed (17 asser… | partial | no candidate | save-log-token.sh token save, run hermetically: live token and real clipboard never touch… |
| `bin/skill-usage-test.sh` | suite-manifest shard 2 (manifest suites… | 0.6 (median n=6, range 0.4-0.8) | 21 passed, 0 failed | yes | clean ×1 | skill-usage.sh frequency report: states its measured window; separates ambient from invok… |
| `bin/secret-test.sh` | suite-manifest shard 0 (manifest suites… | 0.55 (median n=6, range 0.4-0.7) | 0 passed, 0 failed (all skipp… | yes | bypassed `123362f` | secret CLI stores and runs Keychain credentials correctly; every property has a breaking … |
| `bin/judge-run-test.sh` | suite-manifest shard 1 (manifest suites… | 0.5 (median n=6, range 0.5-0.7) | 25 passed, 0 failed | yes | no candidate | judge-run.sh cache and session-verdicts §5: crit surfaces; garbage verdict never overwrit… |
| `bin/isa-index-test.sh` | suite-manifest shard 2 (manifest suites… | 0.3 (median n=6, range 0.2-0.4) | 10 passed, 0 failed | partial | clean ×1 | isa-index.sh ISA pointer table handles manufactured runs, since no real ISA run exists; h… |
| `bin/ab-tally-test.sh` | suite-manifest shard 0 (manifest suites… | 0.25 (median n=6, range 0.2-0.4) | 19 passed, 0 failed | partial | no candidate | ab-tally.sh refusals: no invented winner, no row without --varied, no prose field |
| `bin/plan-status-test.sh` | suite-manifest shard 0 (manifest suites… | 0.25 (median n=6, range 0.2-0.3) | 15 passed, 0 failed | yes | clean ×1 | plan-status.sh derives DONE only from evidence (existing artifact, zero-exit cmd), never … |
| `bin/skills-collide-test.sh` | suite-manifest shard 0 (manifest suites… | 0.25 (median n=6, range 0.2-0.5) | 9 passed, 0 failed | yes | clean ×1 | skills-collide.sh gate: refuses install over newer live skill; ordinary repo-newer update… |
| `bin/gcloud-creds-test.sh` | suite-manifest shard 0 (manifest suites… | 0.2 (median n=6, range 0.2-0.3) | 0 passed, 0 failed (10 skippe… | yes | bypassed `0298ec3` | gcloud-creds credential snapshot/restore: refusals (empty store, clobber) and byte-exact … |
| `bin/doctor-test.sh` | suite-manifest shard 0 (manifest suites… | 0.1 (median n=6, range 0.1-0.2) | 12 passed, 0 failed | no | no candidate | doctor.sh report lines carry resolved values, FLOOR_GREP pin matches guard-lib, unreadabl… |
| `EVALS-DATA/e5trap/hooks/gate-test.sh` | none | n/a (not run in CI) |  | partial | no candidate | e5trap gate.sh discriminates both directions: regulated rollbacks gated, standard-tier ro… |
| `bin/floor-test.sh` | floor-shard-0, floor-shard-1, floor-sha… | sharded, 3 parallel jobs (n=2 run… | 1878 passed, 0 failed = 486 +… | yes | clean ×11 | Floor guards B1–B5 block dangerous shapes, pass benign ones; kill switch, deny list, defe… |
| `skills/<workload>/bin/<name>-preflight-test.sh` | none | n/a (not run in CI) |  | yes | no candidate | <name>-preflight.sh goes red on every deliberately broken fixture workspace; no credentials … |
| `tools/memory/memory-engine.test.ts` | suite-manifest shard 1 (manifest suites… | in:memory-test.sh | 56 passed, 0 failed (printed … | yes | no candidate | Bun memory engine (store, BM25, graph) matches pinned fixtures/memory/expected.json, not … |

## Method, so it can be re-run

- **Inventory.** The test files come from `git ls-files` by name pattern (`*-test.sh`, `test_*.py`, `*_test.py`, `*.test.{ts,mjs,js}`). CI jobs come from `.github/workflows/governance.yml` and the manifest shards' `== <suite>` log markers. Seconds are step durations from `gh api repos/VytCepas/harbor/actions/runs/<id>/jobs`, or, inside a shard, the log timestamps between consecutive suite markers (suite-select prints a suite's output only after it finishes, so the markers bracket it). Runs used: 36044148847, 36041697803, 36039463941, 36038339366, 36035798948, 36025844481 (all successful, all 2026-09-24).
- **Forensics.** The generator below emits one row per (commit, test file) that removed more assertion-shaped lines than it added, or added a bypass-shaped line. A row is a **lead, not a finding**: `|| true`, a final `exit 0` and a printed SKIP are ordinary idioms in these suites. Each lead was then read as a diff, together with the non-test half of the commit.

```sh
# forensics.sh <repo> -> TSV: file sha date asserts_added asserts_removed bypass_added touched_non_test subject
cd "$1"
git ls-files | grep -E '(-test\.sh|/test_[^/]*\.py|_test\.py|\.test\.(ts|mjs|js))$' | while IFS= read -r f; do
  git log --no-merges --format='@@C %H %ad %s' --date=short -p --follow -- "$f" \
  | awk -v file="$f" -v repo="$1" '
      function flush() { if (sha == "") return
        if (rem > add || byp > 0) {
          cmd = "git -C \"" repo "\" show --name-only --format= " sha " | grep -vE \"(-test\\.sh|test_|_test\\.py|\\.test\\.)\" | grep -c . || true"
          cmd | getline nt; close(cmd)
          printf "%s\t%s\t%s\t%d\t%d\t%d\t%s\t%s\n", file, substr(sha,1,10), date, add, rem, byp, nt, subj } }
      /^@@C / { flush(); sha=$2; date=$3; subj=$0; sub(/^@@C [^ ]+ [^ ]+ /, "", subj); add=0; rem=0; byp=0; next }
      /^\+\+\+|^---/ { next }
      /^\+/ { l = substr($0, 2)
        if (l ~ /(^|[^a-z_])(ok|bad|no|assert|_assert|_run|_rp_red|_rp_green|expect)([ (]|$)/ && l !~ /^[[:space:]]*#/) add++
        if (l ~ /^[[:space:]]*exit 0[[:space:]]*$/ || l ~ /(\.skip\(|pytest\.mark\.(skip|xfail)|[^a-z]SKIP[^a-z])/ \
            || l ~ /^[[:space:]]*#[[:space:]]*(ok|bad|no|assert|_assert|_run|expect)[ (]/) byp++
        next }
      /^-/ { l = substr($0, 2)
        if (l ~ /(^|[^a-z_])(ok|bad|no|assert|_assert|_run|_rp_red|_rp_green|expect)([ (]|$)/ && l !~ /^[[:space:]]*#/) rem++
        next }
      END { flush() }'
done
```

**What this cannot see:** a loosened expected value that keeps the assertion count, or a suite that stopped being *run* (C3's blind spot, #695). Step 3's mutation pass is the instrument for the first; this audit found the second by comparing the inventory against the CI logs.

## Step 3 · mutation pilot (2026-10-02, 15 suites)

One realistic defect planted per suite in the code it guards, suite run, code restored with `git checkout -- <file>`, suite re-run green. A suite that stayed green got a second, different mutation; two greens is the finding. Default modes only (no `--live`, `HARBOR_PROBE_DIR` unset, so browser-test's live arm never ran).

| suite | file:line mutated | the mutation, in words | result | mutation: red N / green |
|---|---|---|---|---|
| `tests/hooks/inject-notes-test.sh` | `bin/inject-hook.sh:799` (then `:216`) | (1) `[ "$_npred" -gt 0 ]` to `-ge 0`: a pack with no `when:` predicate fires on every event instead of being skipped. (2) the oversized-content cap keeps only the head, dropping the tail slice (`.[-65536:]`) | GREEN — cannot catch this (137 passed, 0 failed, both) | red 0 / green 2 |
| `tests/checks/visual-check-test.sh` | `bin/visual-check.mjs:144` (then `:140`) | (1) normal-text contrast floor 4.5 lowered to 1.5. (2) alpha compositing dropped, translucent text judged as opaque | GREEN — cannot catch this (4 passed, 0 failed, both) | red 0 / green 2 |
| `tests/cli/browser-test.sh` | `bin/browser-agent.sh:255` | forced-click refusal inside an iframe replaced by `true` | red (1 failed) | red 1 / green 0 |
| `tests/obs/usage-aggregate-test.sh` | `bin/usage-aggregate.sh:221` | per-request dedupe keeps the record with the fewest output tokens (`max_by` to `min_by`) | red (1 failed) | red 1 / green 0 |
| `tests/floor/marker-test.sh` | `bin/guard-lib.sh:278` | the stop-before-`$HOME` walk no longer breaks (M14) | red (2 failed) | red 1 / green 0 |
| `tests/hooks/ticket-note-test.sh` | `bin/ticket-note.sh:121` | the `stop_hook_active` re-entry guard compares against the wrong value, so it never exits | red (1 failed) | red 1 / green 0 |
| `tests/floor/normalize-test.sh` | `bin/floor-normalize.awk:296` | `-u` dropped from the sudo/doas options-that-take-a-value list | red (1 failed) | red 1 / green 0 |
| `tests/hooks/save-log-token-test.sh` | `bin/save-log-token.sh:76` | token pattern widened with `\|*`, so any clipboard content is saved | red (6 failed) | red 1 / green 0 |
| `tests/memory/isa-index-test.sh` | `bin/isa-index.sh:80` | the `ISA.md`-required `continue` replaced by `:`, so session dirs count as runs | red (5 failed) | red 1 / green 0 |
| `tests/obs/ab-tally-test.sh` | `bin/ab-tally.sh:108` | `--varied` length cap raised from `$VARIED_MAX` to 99999 | red (2 failed) | red 1 / green 0 |
| `tests/install/doctor-test.sh` | `bin/doctor.sh:101` (then `:153`) | (1) `--json` exits 0 instead of 1 when a fatal dependency is missing. (2) text mode exits 0 instead of 1 on `FATAL: N dependency missing` | GREEN — cannot catch this (13 passed, 0 failed, both) | red 0 / green 2 |
| `tests/cli/secret-test.sh` | `bin/secret:164` | libsecret `--locked` refusal made unreachable (stored unlocked instead) | red (1 failed) | red 1 / green 0 |
| `tests/cli/gcloud-creds-test.sh` | `bin/gcloud-creds:82` | the empty-store snapshot refusal made unreachable | red (2 failed) | red 1 / green 0 |
| `tests/skills/skill-gates-test.sh` | `skills/tracking-standards/bin/check-naming.sh:303` (then `skills/topology/bin/check-topology.sh:307`) | (1) `--clones` exits 0 when drift is found. (2) the "refusing to write an empty map" guard replaced by `true` | GREEN — cannot catch this (58 passed, 0 failed, both) | red 0 / green 2 |
| `tests/hooks/statusline-test.sh` | `bin/fleet-glyph.sh:212` | red threshold of the context ramp raised from 90 to 99 | red (2 failed) | red 1 / green 0 |

**Counts: 11 red, 4 GREEN, 0 skipped** (the subagent first wrote 10 and 5; the table above is the source, re-counted 2026-10-02). Of the 11 suites the audit marked "partial"/"no" for planting a violation, 8 went red on the first mutation and 3 stayed green twice (inject-notes, visual-check, doctor). Of the four whose bypasses were repaired on 2026-09-24, secret, gcloud-creds and statusline still fail on a planted violation; skill-gates did not catch either mutation, because it runs each gate's own `--self-test` and nothing asserts those gates' exit codes or refusals on real input. Median suite runtime 4 s (mean 19.5 s; range 0 s to 162 s for skill-gates). Machine time: 273 s for the 15 baseline runs, about 510 s across 19 mutated runs, 273 s for the post-restore re-run, roughly 17 min in all; end-to-end wall-clock including reading the guarded code was about 40 min (estimated, not clocked from the start). At about 2.5 min per suite end-to-end (one to two mutants, dominated by choosing a mutation, not by running it), the remaining ~129 suites would cost about 5 to 6 hours of one agent, of which about 1 hour is suite runtime at the pilot mean; the median of 4 s says most of them are cheaper than the pilot mean. Every mutated file was restored and `git status --short` showed only `docs/audits/test-audit.md` modified afterwards. visual-check's default mode renders local pages in a local headless Chrome (no network); the harbor#694 client-site arm is the one gated behind `HARBOR_PROBE_DIR`, which was unset.
