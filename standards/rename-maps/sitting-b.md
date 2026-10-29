# Sitting B: the six-wave rename maps (harbor#961, lane E)

Answered by the operator on 2026-10-27; the maps below carry the answers. Every figure is from `standard-rename.sh --plan` on a scratch clone of origin/main 3d0a8293 with the registry edits of this branch applied. Nothing was applied to a real file.

## Answered 2026-10-27

| # | Question | Answer | What changed in the maps |
|---|---|---|---|
| 1 | `inject.d/` wave | #1010's context-rules lane moves it, with an engine that reads both directories | all 41 `inject.d` and `.claude/inject.d` rows removed; **#1010 owns them** |
| 2 | Families for 12 scripts | register `library`; the four libs become `library-fs.sh`, `library-log.sh`, `library-alert.sh`, `library-gate.sh`; the other ten as mapped | `library` added to `terms.tsv` (family, broader `standard`); 4 W3 rows; the ten low-confidence rows are now `high` |
| 3 | Four docs and the superseded four | as mapped | none |
| 4 | `EVALS-DATA` families and arm folders | as mapped | none |
| 5 | Six skills, three commands | skills are decided in #1010 (`agent-routing` keeps its name, `agent` is now a family); the commands are approved | the 6 skill `decide` rows dropped; `commands/harbor-{context,merge,skills}.md` are W3 `rename` rows to `context-budget`, `gate-merge`, `skill-catalog`, old names kept until the W3 date |
| 6 | Cross-repo names | (a) `ship.conf` and `SHIP_*` go to #967; (b) as proposed, dual read to 2027-02-28 | the `.agents/ship.conf` row removed; `HARBOR_SCOPE_FLEET_CONTROLLER` and `HARBOR_SCOPE_SCAFFOLDER` kept with a date |
| 7 | ~100 family-less `HARBOR_*` env names | no map now; a separate wave after sitting C | none |
| 8 | Fleet modules | hold | the file header says "DRAFT, NOT APPROVED; for #967's own sitting" |
| 9 | `docs/src/NN-*.html` | rename all 11, an `order:` list replaces the prefixes | 11 W1 rows (`docs/src/overview.html` and so on, `20-floor` to `baseline`, `30-inject` to `injection-rule`, `80-monitor` to `alert`). The `docs-gen.sh` change ships with the W1 PR, not with these rows |
| 10a | Which rows need a symlink | review every file row for an outside reader; keep the date where there is one | new `reader` column; 791 rows with no reader now have `remove_by` `-`; 131 keep their date (see below) |
| 10b | Date spacing | keep weekly | W1 2027-01-31 ... W6b 2027-03-14 |
| 11 | Names to keep | exempt | `exemptions.tsv`: `tool-0025` (`NOTICE`), `world-0002`..`0004` (the memory-corpus and lint-module fixture trees), `world-0005`..`0009` (the five permanent rule ids); the eight legacy rows for the memory corpus removed |

Also done: `rename-0024` (the `skill-book` row) now has wave `T7`, so `--plan --wave W2` no longer exits 3; it exits 0 (below).

## Maps and plan results

All maps are in `standards/rename-maps/`. Columns: `old_path new_path wave recommendation confidence reason remove_by frozen surface reader`; `--import` reads the first five by name and ignores the rest.

| Wave | File | Rows | Dated / `-` | Plan result | Residual |
|---|---|---|---|---|---|
| W1 docs | `w1-docs.tsv` | 555 | 23 / 532 (76 case-only) | 555 ok, 0 failed, 54 flagged | 46: sibling repos (yard 42, fleet 4) naming `PLAN.md`, `CONTRACTS/box-profile.md` and others; fixed per repo in #967 |
| W2 tests | `w2-tests.tsv` | 283 | 10 / 273 | 283 ok, 0 failed, 135 flagged; **`--plan --wave W2` exits 0** | 0 |
| W3 bin | `w3-bin.tsv` | 90 | 51 / 39 | 90 ok, 0 failed, 45 flagged | 1: `hooks/failure-observe/failure-observe.sh` holds NUL bytes, so the codemod treats it as binary |
| W4 PATH | `w4-path-shims.tsv` | 4 | 4 / 0 | 4 ok, 0 failed, 3 flagged | 0 |
| W5 state/env/launchd | `w5-state-env-launchd.tsv` | 25 files + 16 env | 20 / 21 | 25 ok, 0 failed, 6 flagged | 99: 98 env uses no rewrite decides (the kill-switch names in `guard-bash.sh` regexes, prose, tests) plus the same binary file |
| W6a admission | `w6a-admission-hooks.tsv` | 23 files + 28 env | 21 / 30 (28 internal constants) | 23 ok, 0 failed, 18 flagged | 1: the same binary file |
| W6b | `w6b-admission-floor-hook-and-integrity.tsv` | 2 | 2 / 0 | 2 ok, 0 failed, 2 flagged | 0 |
| T4 letter ids | `t4-letter-ids.tsv` | 93 | n/a | not a path rename; all 93 new ids pass `lint-name.sh --check rule-id` | n/a |
| Fleet modules | `fleet-modules-in-projects-orchestrator.tsv` | 56 | n/a | draft, not approved, not planned, that repo untouched | n/a |

Dates: W1 2027-01-31, W2 02-07, W3 02-14, W4 02-21, W5 02-28, W6a 03-07, W6b 03-14 (T4 01-31, fleet 03-21).

## Q10a: readers found (checked 2026-10-27, read-only)

Kept with a date: **131** rows; dropped to `-`: **791** rows with no reader found (the other 104 `-` rows were already `-`: 76 case-only moves and 28 internal `FLOOR_*` constants). Sources checked for every file row: `~/.claude/settings.json` hook commands, the `com.harbor.*` plists in `~/Library/LaunchAgents` and loaded twins of `launchd/` files, deployed copies under `~/.claude/{bin,commands,hooks,lib}`, `~/.local/bin` links and `CONTRACTS/shims.tsv`, `git grep` in the other repos under `~/port` (harbor-core and dbt-core excluded), memory notes under `~/.claude/projects/*/memory`, and `frozen.tsv`. Readers of the 131, by source: memory notes 62, deployed copy in `~/.claude/bin` 56, repo azimuth 29, LaunchAgent plists 21 (+8 loaded twins), repo harbor-private 16, hook commands in `settings.json` 13, repo estate 7, `shims.tsv` 5, deployed `~/.claude/commands` 3, repo studio 2, frozen kill switches 2. A row's `reader` cell names up to three. Only 4 env rows keep a dual-read window: the two kill switches and the two frozen repo-path names.

## What the tooling does that you should know

1. `--import` writes `remove_by` as `-` for every row. Set the dates after each import:
   ```sh
   cat standards/rename-maps/w*.tsv | awk -F'\t' '$4=="rename"{print $1"\t"$7}' > "$TMPDIR/d"
   awk -F'\t' -v OFS='\t' 'NR==FNR{d[$1]=$2;next} /^rename-/&&($2 in d)&&$6=="-"{$6=d[$2]} {print}' "$TMPDIR/d" standards/naming/renames.tsv > "$TMPDIR/r" && mv "$TMPDIR/r" standards/naming/renames.tsv
   ```
2. `--import` skips env rows ("not tracked here"); the 44 env rows are added to `renames.tsv` by hand. The planner accepts them.
3. `frozen-gen.sh` derives 148 frozen rule ids (`bash:*` 110, `egress:*` 17, `destroy:*` 9, `cloud:*` 7, `deliverables:*` 3, `selfedit:*` 2) from the file names `bin/guard-*.sh` and `tests/guards/*.jsonl`. The ids stay, so no alias row, but the W2 and W6a PRs must change those two globs or `frozen-gen.sh --check` goes red.
4. Frozen names touched: `env:HARBOR_ORCHESTRATOR`, `env:HARBOR_PROJECT_INIT` (dated rows, alias until 2027-02-28); `HELM_DISABLE_FLOOR` and `HELM_FLOOR_SHADOW`, the kill switches, both spellings read until 2027-02-28; the 148 guard rule ids above; 10 CLI verbs (`status doctor check fresh cite observe dash restore browser chrome`) stay while the scripts behind them move.
5. `SITTING-B` is now `sitting-b.md`. `fleet-modules-in-projects-orchestrator.tsv` and `t4-letter-ids.tsv` are not importable.

## Every row the planner flagged

Every one is a warning; none refused a row. The common kind is "family": lines reach the old name through a glob, a regex or a built name, so no rewrite decides them and a person does (the suite ledger checks). Counts: W1 54, W2 135, W3 45, W4 3, W5 6, W6a 18, W6b 2, 263 in all. One line per row: old path, then why.

```
### W1 (54 flagged)
bin/constitution-install.sh  3 lines in 3 files reach it by family `constitution` (glob, regex or built name), first bin/guard-bash.sh:1241
DOCTRINE/absent-by-decision.md  4 lines in 3 files reach it by family `absent` (glob, regex or built name), first CONTRACTS/gates.md:82
DOCTRINE/case-law.md  4 lines in 4 files reach it by family `case` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-hook-engine-and-eval-internals.md:47
DOCTRINE/doc-truth.md  1 lines in 1 files reach it by family `doc` (glob, regex or built name), first bin/guard-deliverables.sh:67
DOCTRINE/no-authored-plugins.md  9 lines in 6 files reach it by family `no` (glob, regex or built name), first bin/mutation-tier.sh:129
CONTRACTS/box-profile.md  2 lines in 1 files reach it by family `box` (glob, regex or built name), first bin/browser-agent.sh:417
CONTRACTS/browser-agent-hosts.txt  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
CONTRACTS/browser-routing.md  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
CONTRACTS/core-writes-allow.tsv  9 lines in 8 files reach it by family `core` (glob, regex or built name), first bin/bootstrap.sh:76
CONTRACTS/decision-orphans.tsv  4 lines in 4 files reach it by family `decision` (glob, regex or built name), first CONTRACTS/session-waiting.tsv:16
CONTRACTS/dev-paths-allow.tsv  4 lines in 3 files reach it by family `dev` (glob, regex or built name), first bin/layers.sh:6
CONTRACTS/domain-allow.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
CONTRACTS/domain-repos-allow.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
CONTRACTS/domain-terms.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
CONTRACTS/event-kinds.tsv  2 lines in 1 files reach it by family `event` (glob, regex or built name), first bin/guard-bash.sh:343
CONTRACTS/event-rules.tsv  2 lines in 1 files reach it by family `event` (glob, regex or built name), first bin/guard-bash.sh:343
CONTRACTS/fresh-checks.tsv  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/ci/fresh-check-test.sh:42
CONTRACTS/git-verbs.md  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
CONTRACTS/helm-state.md  26 lines in 13 files reach it by family `helm` (glob, regex or built name), first CONTRACTS/README.md:30
CONTRACTS/hooks-external.tsv  8 lines in 5 files reach it by family `hooks` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/Characterise-ECC-test-suite-method.md:43
CONTRACTS/issue-taxonomy.tsv  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first FLOOR.md:2092
CONTRACTS/lint-core-writes-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-dev-paths-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-domain-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-domain-repos-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-leaks-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-secrets-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/lint-siblings-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
CONTRACTS/log-exempt.tsv  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
CONTRACTS/memory-format.md  1 lines in 1 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
CONTRACTS/merge-stack-union.txt  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
CONTRACTS/pack-frontmatter-keys.txt  1 lines in 1 files reach it by family `pack` (glob, regex or built name), first bin/pack.sh:166
CONTRACTS/port-paths-exempt.tsv  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
CONTRACTS/port-root.md  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
CONTRACTS/private-layer.md  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
CONTRACTS/redteam-baseline.tsv  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first CHECKS.md:58
CONTRACTS/redteam-sources.tsv  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first CHECKS.md:58
CONTRACTS/repo-slug.txt  9 lines in 9 files reach it by family `repo` (glob, regex or built name), first CONTRACTS/pack.md:124
CONTRACTS/secret-legacy-refs.txt  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:180
CONTRACTS/session-waiting.tsv  3 lines in 2 files reach it by family `session` (glob, regex or built name), first CONTRACTS/cli.md:202
CONTRACTS/test-contract.md  4 lines in 4 files reach it by family `test` (glob, regex or built name), first bin/guard-stop.sh:271
SEC-0.md  1 lines in 1 files reach it by family `SEC` (glob, regex or built name), first tests/skills/prove.report-test.sh:24
harbor-epic.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
harbor-build-tickets.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
docs/src/10-timing.html  3 lines in 2 files reach it by family `10` (glob, regex or built name), first tests/checks/lint.inject-test.sh:75
docs/src/30-inject.html  4 lines in 2 files reach it by family `30` (glob, regex or built name), first tests/ci/merge-stack/merge.test.sh:40
patches/governance-docs-gen-check.patch.md  1 lines in 1 files reach it by family `governance` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:106
patches/governance-security-floor-shard.patch.md  1 lines in 1 files reach it by family `governance` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:106
EVALS-DATA/e12rule9/run-disclose.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first CONTRACTS/session-waiting.tsv:17
EVALS-DATA/e12rule9/run-inturn.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first CONTRACTS/session-waiting.tsv:17
EVALS-DATA/e12rule9/run-mid.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first CONTRACTS/session-waiting.tsv:17
EVALS-DATA/e5trap/hooks/gate-test.sh  11 lines in 9 files reach it by family `gate` (glob, regex or built name), first .agents/protected-paths.tsv:70
PROVENANCE.md  6 lines in 6 files name it beside a same-path file, left as written, first NOTICE:8
PROVENANCE.md  79 lines in 36 files name PROVENANCE.md, which 3 other tracked files also end with, rewritten to this one, first CITATIONS.md:15

### W2 (135 flagged)
tests/checks/adoption-check/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/checks/cite-verify/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/checks/docs-gen-test.sh  3 lines in 3 files reach it by family `docs` (glob, regex or built name), first bin/lint-conventions.sh:3639
tests/checks/freshness/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/checks/graph-gen-test.sh  2 lines in 2 files reach it by family `graph` (glob, regex or built name), first bin/memory.sh:145
tests/checks/lint-test.sh  7 lines in 5 files reach it by family `lint` (glob, regex or built name), first bin/findings.sh:384
tests/checks/module-shape/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/checks/redteam-corpus-test.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first CHECKS.md:58
tests/checks/rule-health-test.sh  3 lines in 2 files reach it by family `rule` (glob, regex or built name), first hooks/injection-rule/compaction-digest.test.sh:38
tests/checks/schedules-test.sh  4 lines in 3 files reach it by family `schedules` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/checks/standard-rename-test.sh  7 lines in 3 files reach it by family `standard` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-hook-engine-and-eval-internals.md:164
tests/checks/test-contract-test.sh  4 lines in 4 files reach it by family `test` (glob, regex or built name), first bin/guard-stop.sh:271
tests/checks/visual-check/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/ci/ci-governor-ladder-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-governor-liveness-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-governor-priority-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-governor-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-queue-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runner-alarm-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runner-wedge-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runners-lost-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runners-switch-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runners-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-runs-on-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/ci-verified-test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/ci/fresh-check-test.sh  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/ci/fresh-check-test.sh:42
tests/ci/gh-plan-test.sh  7 lines in 5 files reach it by family `gh` (glob, regex or built name), first bin/floor-normalize.awk:70
tests/ci/hooks-env-test.sh  8 lines in 5 files reach it by family `hooks` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/Characterise-ECC-test-suite-method.md:43
tests/ci/main-tip-verdict-test.sh  5 lines in 3 files reach it by family `main` (glob, regex or built name), first bin/gate-merge-stack.sh:329
tests/ci/merge-check-test.sh  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
tests/ci/merge-stack/backdoor-gen.sh  1 lines in 1 files reach it by family `backdoor` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
tests/ci/merged-check-test.sh  4 lines in 4 files reach it by family `merged` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
tests/ci/plan-status-test.sh  6 lines in 2 files reach it by family `plan` (glob, regex or built name), first bin/standard-catalog.sh:314
tests/ci/pr-wait-test.sh  16 lines in 6 files reach it by family `pr` (glob, regex or built name), first FLOOR.md:2092
tests/ci/status-gen-test.sh  6 lines in 5 files reach it by family `status` (glob, regex or built name), first EVALS-DATA/e5trap/opsctl:93
tests/ci/worktree-test.sh  5 lines in 4 files reach it by family `worktree` (glob, regex or built name), first bin/lint-domain.sh:44
tests/cli/access/add-prompts.test.sh  11 lines in 8 files reach it by family `add` (glob, regex or built name), first bin/context-resolve.sh:139
tests/cli/access/secret-gate.test.sh  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:180
tests/cli/browser-hosts-add-test.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
tests/cli/browser-test.sh  11 lines in 8 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
tests/cli/browser/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/browser/private-hosts.test.sh  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
tests/cli/collector-test.sh  4 lines in 3 files reach it by family `collector` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/cli/console-guards-test.sh  1 lines in 1 files reach it by family `console` (glob, regex or built name), first bin/browser-agent.sh:188
tests/cli/console-panels-test.sh  1 lines in 1 files reach it by family `console` (glob, regex or built name), first bin/browser-agent.sh:188
tests/cli/deliver-drive/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/gcloud-creds-test.sh  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
tests/cli/gcloud-creds/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/gcloud-wrapper-test.sh  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
tests/cli/gcloud-wrapper/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/harbor-app-routing-test.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
tests/cli/harbor-clean-test.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
tests/cli/harbor-test.sh  23 lines in 14 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
tests/cli/idea/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/issue-connector-test.sh  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first FLOOR.md:2092
tests/cli/live-verify-test.sh  2 lines in 2 files reach it by family `live` (glob, regex or built name), first bin/guard-egress.sh:64
tests/cli/report-contract/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/cli/secret-seam-test.sh  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:180
tests/cli/secret-test.sh  9 lines in 7 files reach it by family `secret` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:180
tests/cli/wait-for/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/export/ci-mirror.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/sec0-harden.sh:64
tests/floor/deny-hash-test.sh  6 lines in 5 files reach it by family `deny` (glob, regex or built name), first bin/floor-hook.sh:65
tests/floor/deny-hash/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/floor/destroy-snapshot-test.sh  1 lines in 1 files reach it by family `destroy` (glob, regex or built name), first skills/access-ledger/bin/check-routes.sh:685
tests/floor/floor-equiv-test.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/floor/floor-equiv/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/floor/floor-fixture.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/floor/floor-test.sh  36 lines in 26 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/floor/git-verbs-test.sh  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
tests/floor/marker-backfill/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/floor/marker-test.sh  6 lines in 4 files reach it by family `marker` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/floor/normalize-test.sh  4 lines in 3 files reach it by family `normalize` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/floor/pass-score/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/floor/recover-test.sh  4 lines in 3 files reach it by family `recover` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/floor/replay-test.sh  4 lines in 3 files reach it by family `replay` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/floor/replay/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/guards/bash-test.sh  32 lines in 14 files reach it by family `bash` (glob, regex or built name), first COVERAGE-INCIDENTS.tsv:110
tests/guards/cloud-test.sh  6 lines in 5 files reach it by family `cloud` (glob, regex or built name), first bin/lint-conventions.sh:3834
tests/guards/deliverables-test.sh  4 lines in 3 files reach it by family `deliverables` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/guards/destroy-test.sh  5 lines in 4 files reach it by family `destroy` (glob, regex or built name), first skills/access-ledger/bin/check-routes.sh:685
tests/guards/egress-test.sh  5 lines in 4 files reach it by family `egress` (glob, regex or built name), first bin/lint-conventions.sh:5769
tests/guards/floor-fixture.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/guards/selfedit-test.sh  4 lines in 3 files reach it by family `selfedit` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/hooks/agent-brief-test.sh  7 lines in 6 files reach it by family `agent` (glob, regex or built name), first bin/status-obligations.sh:644
tests/hooks/apiroute-guard-test.sh  3 lines in 2 files reach it by family `apiroute` (glob, regex or built name), first bin/guard-apiroute.sh:246
tests/hooks/hook-replay/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/hooks/inject-fixture.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/hooks/inject-notes-test.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/hooks/name-note-test.sh  8 lines in 6 files reach it by family `name` (glob, regex or built name), first CONTRACTS/pack.md:124
tests/hooks/prod-guard-test.sh  2 lines in 2 files reach it by family `prod` (glob, regex or built name), first bin/guard-egress.sh:337
tests/hooks/save-log-token-test.sh  2 lines in 2 files reach it by family `save` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:113
tests/hooks/statusline-test.sh  4 lines in 3 files reach it by family `statusline` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/hooks/stop-guard-test.sh  1 lines in 1 files reach it by family `stop` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
tests/install/bootstrap-test.sh  7 lines in 6 files reach it by family `bootstrap` (glob, regex or built name), first launchd/com.harbor.judge.plist:42
tests/install/constitution-install-test.sh  2 lines in 2 files reach it by family `constitution` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/install/deploy-test.sh  36 lines in 19 files reach it by family `deploy` (glob, regex or built name), first FLOOR.md:1908
tests/install/doctor-test.sh  4 lines in 3 files reach it by family `doctor` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/install/doctor/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/install/first-run.test.sh  13 lines in 1 files reach it by family `first` (glob, regex or built name), first bin/decider-set.sh:36
tests/install/floor-uninstall-test.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/install/inject-install-test.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/install/install-drift-test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
tests/install/install-exec-test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
tests/install/install-stamp-test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
tests/install/port-paths-test.sh  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
tests/install/port-paths/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/install/port-paths/private-exempt.test.sh  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
tests/install/roots-test.sh  4 lines in 3 files reach it by family `roots` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/install/runtime-install-test.sh  1 lines in 1 files reach it by family `runtime` (glob, regex or built name), first tests/obs/renew-check-test.sh:237
tests/install/sec0-harden-test.sh  1 lines in 1 files reach it by family `sec0` (glob, regex or built name), first bin/proposal.sh:96
tests/install/shim-install-test.sh  3 lines in 2 files reach it by family `shim` (glob, regex or built name), first tests/install/deploy-test.sh:122
tests/install/skills-collide-test.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first CONTRACTS/issue-taxonomy.tsv:113
tests/install/skills-install-test.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first CONTRACTS/issue-taxonomy.tsv:113
tests/lib/check-test.sh  16 lines in 9 files reach it by family `check` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-hook-engine-and-eval-internals.md:116
tests/lib/install-lib-test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
tests/lib/lib-test.sh  6 lines in 4 files reach it by family `lib` (glob, regex or built name), first bin/guard-bash.sh:644
tests/lib/log-lib-test.sh  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
tests/memory/context-budget-test.sh  2 lines in 2 files reach it by family `context` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:146
tests/memory/context-ratchet-test.sh  2 lines in 2 files reach it by family `context` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:146
tests/memory/memory-route-test.sh  1 lines in 1 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
tests/memory/memory-test.sh  5 lines in 4 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
tests/memory/store-check-test.sh  4 lines in 2 files reach it by family `store` (glob, regex or built name), first bin/lint-secrets.sh:11
tests/obs/ab-tally/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/obs/findings-run-test.sh  1 lines in 1 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
tests/obs/findings-test.sh  5 lines in 4 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
tests/obs/judge-run/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/obs/proposal-test.sh  4 lines in 3 files reach it by family `proposal` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/obs/proposal/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/obs/pulse-test.sh  4 lines in 3 files reach it by family `pulse` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
tests/obs/skill-fire/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/obs/usage-aggregate/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/skills/eval-runners-test.sh  6 lines in 3 files reach it by family `eval` (glob, regex or built name), first bin/guard-bash.sh:485
tests/skills/prove-test.sh  4 lines in 3 files reach it by family `prove` (glob, regex or built name), first tests/checks/lint.suites-test.sh:31
fixtures/guard-corpus.jsonl  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
fixtures/inject/packs/example-store/10-wipe-destroys-history.md  3 lines in 2 files reach it by family `10` (glob, regex or built name), first tests/checks/lint.inject-test.sh:75

### W3 (45 flagged)
bin/browser-agent.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
bin/browser-cdp.mjs  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
bin/browser-hosts-add.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first CONTRACTS/suite-paths.txt:35
bin/dashboard-gen.sh  1 lines in 1 files reach it by family `dashboard` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
bin/deliver-drive.sh  1 lines in 1 files reach it by family `deliver` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
bin/deny-hash.sh  6 lines in 5 files reach it by family `deny` (glob, regex or built name), first bin/floor-hook.sh:65
bin/docs-gen.sh  4 lines in 4 files reach it by family `docs` (glob, regex or built name), first bin/lint-conventions.sh:3639
bin/fresh-check.sh  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/ci/fresh-check-test.sh:42
bin/frozen-gen.sh  1 lines in 1 files reach it by family `frozen` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
bin/gh-plan.sh  7 lines in 5 files reach it by family `gh` (glob, regex or built name), first bin/floor-normalize.awk:70
bin/graph-gen.sh  3 lines in 3 files reach it by family `graph` (glob, regex or built name), first bin/memory.sh:145
bin/harbor-app-install.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
bin/harbor-clean.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
bin/inject-install.sh  6 lines in 5 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
bin/install-drift.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
bin/install-lib.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
bin/install-stamp.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-agentic-architecture-deep-dive.md:80
bin/issue-connector.sh  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first FLOOR.md:2092
bin/live-verify.sh  2 lines in 2 files reach it by family `live` (glob, regex or built name), first bin/guard-egress.sh:64
bin/log-lib.sh  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
bin/main-tip-verdict.sh  5 lines in 3 files reach it by family `main` (glob, regex or built name), first bin/gate-merge-stack.sh:329
bin/marker-backfill.sh  2 lines in 1 files reach it by family `marker` (glob, regex or built name), first tests/scope/registry/repo.test.sh:331
bin/merge-check.sh  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
bin/merged-check.sh  4 lines in 4 files reach it by family `merged` (glob, regex or built name), first CONTRACTS/event-rules.tsv:20
bin/pass-score.sh  4 lines in 4 files reach it by family `pass` (glob, regex or built name), first bin/merge-check.sh:309
bin/plan-status.sh  6 lines in 2 files reach it by family `plan` (glob, regex or built name), first bin/standard-catalog.sh:314
bin/port-paths.sh  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
bin/pr-wait.sh  16 lines in 6 files reach it by family `pr` (glob, regex or built name), first FLOOR.md:2092
bin/redteam-corpus.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first CHECKS.md:58
bin/report-contract.sh  2 lines in 2 files reach it by family `report` (glob, regex or built name), first bin/standard-catalog.sh:314
bin/rule-health.sh  3 lines in 2 files reach it by family `rule` (glob, regex or built name), first hooks/injection-rule/compaction-digest.test.sh:38
bin/runtime-install.sh  2 lines in 2 files reach it by family `runtime` (glob, regex or built name), first tests/floor/floor.install-test.sh:319
bin/save-log-token.sh  2 lines in 2 files reach it by family `save` (glob, regex or built name), first EVALS-DATA/ecc-2026-09-07/subagent-reports/ECC-session-continuity-mechanics.md:113
bin/sec0-harden.sh  1 lines in 1 files reach it by family `sec0` (glob, regex or built name), first bin/proposal.sh:96
bin/skills-collide.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first CONTRACTS/issue-taxonomy.tsv:113
bin/skills-install.sh  8 lines in 8 files reach it by family `skills` (glob, regex or built name), first CONTRACTS/issue-taxonomy.tsv:113
bin/status-gen.sh  7 lines in 6 files reach it by family `status` (glob, regex or built name), first EVALS-DATA/e5trap/opsctl:93
bin/store-check.sh  4 lines in 2 files reach it by family `store` (glob, regex or built name), first bin/lint-secrets.sh:11
bin/harbor-app/git-credential.sh  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
bin/gate-lib.sh  7 lines in 6 files reach it by family `gate` (glob, regex or built name), first .agents/protected-paths.tsv:70
commands/harbor-context.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
commands/harbor-merge.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
commands/harbor-skills.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
bin/visual-check.mjs  1 lines in 1 files name it beside a same-path file, left as written, first vendor/archify/bin/archify.mjs:1242
bin/visual-check.mjs  9 lines in 6 files name bin/visual-check.mjs, which 1 other tracked files also end with, rewritten to this one, first CONTRACTS/browser-routing.md:279

### W4 (3 flagged)
bin/gcloud-creds  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
bin/gcloud-wrapper.sh  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
bin/shim-install.sh  4 lines in 3 files reach it by family `shim` (glob, regex or built name), first tests/floor/floor.install-test.sh:319

### W5 (6 flagged)
bin/findings-run.sh  1 lines in 1 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
bin/redteam-corpus-run.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first CHECKS.md:58
systemd/harbor-judge.service  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
systemd/harbor-judge.timer  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
systemd/harbor-pulse.service  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657
systemd/harbor-pulse.timer  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/browser-agent.sh:657

### W6a (18 flagged)
bin/floor-deny.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-equiv.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-install.sh  33 lines in 24 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-normalize.awk  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-observe.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-uninstall.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/floor-verify.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/guard-apiroute.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-bash.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-cloud.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-deliverables.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-destroy.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-egress.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-lib.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-selfedit.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/guard-stop.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
bin/prod-guard-ambient.sh  2 lines in 2 files reach it by family `prod` (glob, regex or built name), first bin/guard-egress.sh:337
bin/prod-guard-install.sh  2 lines in 2 files reach it by family `prod` (glob, regex or built name), first bin/guard-egress.sh:337

### W6b (2 flagged)
bin/floor-hook.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
bin/guard-integrity.sh  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
```
