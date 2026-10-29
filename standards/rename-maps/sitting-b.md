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
| 9 | `docs/src/NN-*.html` | rename all 11, an `order:` list replaces the prefixes | 11 W1 rows (`docs/src/overview.html` and so on, `20-floor` to `baseline`, `30-inject` to `injection-rule`, `80-monitor` to `alert`). The `doc-index-generate.sh` change ships with the W1 PR, not with these rows |
| 10a | Which rows need a symlink | review every file row for an outside reader; keep the date where there is one | new `reader` column; 791 rows with no reader now have `remove_by` `-`; 131 keep their date (see below) |
| 10b | Date spacing | keep weekly | W1 2027-01-31 ... W6b 2027-03-14 |
| 11 | Names to keep | exempt | `exemptions.tsv`: `tool-0025` (`NOTICE`), `world-0002`..`0004` (the memory-corpus and lint-module fixture trees), `world-0005`..`0009` (the five permanent rule ids); the eight legacy rows for the memory corpus removed |

Also done: `rename-0024` (the `skill-book` row) now has wave `T7`, so `--plan --wave W2` no longer exits 3; it exits 0 (below).

## Maps and plan results

All maps are in `standards/rename-maps/`. Columns: `old_path new_path wave recommendation confidence reason remove_by frozen surface reader`; `--import` reads the first five by name and ignores the rest.

| Wave | File | Rows | Dated / `-` | Plan result | Residual |
|---|---|---|---|---|---|
| W1 docs | `w1-docs.tsv` | 555 | 23 / 532 (76 case-only) | 555 ok, 0 failed, 54 flagged | 46: sibling repos (yard 42, fleet 4) naming `docs/generated/plan.md`, `contracts/host-profile.md` and others; fixed per repo in #967 |
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

Kept with a date: **131** rows; dropped to `-`: **791** rows with no reader found (the other 104 `-` rows were already `-`: 76 case-only moves and 28 internal `FLOOR_*` constants). Sources checked for every file row: `~/.claude/settings.json` hook commands, the `com.harbor.*` plists in `~/Library/LaunchAgents` and loaded twins of `launchd/` files, deployed copies under `~/.claude/{bin,commands,hooks,lib}`, `~/.local/bin` links and `contracts/shims.tsv`, `git grep` in the other repos under `~/port` (harbor-core and dbt-core excluded), memory notes under `~/.claude/projects/*/memory`, and `frozen.tsv`. Readers of the 131, by source: memory notes 62, deployed copy in `~/.claude/bin` 56, repo azimuth 29, LaunchAgent plists 21 (+8 loaded twins), repo harbor-private 16, hook commands in `settings.json` 13, repo estate 7, `shims.tsv` 5, deployed `~/.claude/commands` 3, repo studio 2, frozen kill switches 2. A row's `reader` cell names up to three. Only 4 env rows keep a dual-read window: the two kill switches and the two frozen repo-path names.

## What the tooling does that you should know

1. `--import` writes `remove_by` as `-` for every row. Set the dates after each import:
   ```sh
   cat standards/rename-maps/w*.tsv | awk -F'\t' '$4=="rename"{print $1"\t"$7}' > "$TMPDIR/d"
   awk -F'\t' -v OFS='\t' 'NR==FNR{d[$1]=$2;next} /^rename-/&&($2 in d)&&$6=="-"{$6=d[$2]} {print}' "$TMPDIR/d" standards/naming/renames.tsv > "$TMPDIR/r" && mv "$TMPDIR/r" standards/naming/renames.tsv
   ```
2. `--import` skips env rows ("not tracked here"); the 44 env rows are added to `renames.tsv` by hand. The planner accepts them.
3. `standard-frozen-generate.sh` derives 148 frozen rule ids (`bash:*` 110, `egress:*` 17, `destroy:*` 9, `cloud:*` 7, `deliverables:*` 3, `selfedit:*` 2) from the file names `bin/guard-*.sh` and `tests/guards/*.jsonl`. The ids stay, so no alias row, but the W2 and W6a PRs must change those two globs or `standard-frozen-generate.sh --check` goes red.
4. Frozen names touched: `env:HARBOR_SCOPE_FLEET_CONTROLLER`, `env:HARBOR_SCOPE_SCAFFOLDER` (dated rows, alias until 2027-02-28); `HARBOR_ADMISSION_DISABLE` and `HARBOR_ADMISSION_SHADOW`, the kill switches, both spellings read until 2027-02-28; the 148 guard rule ids above; 10 CLI verbs (`status doctor check fresh cite observe dash restore browser chrome`) stay while the scripts behind them move.
5. `SITTING-B` is now `sitting-b.md`. `fleet-modules-in-projects-orchestrator.tsv` and `t4-letter-ids.tsv` are not importable.

## Every row the planner flagged

Every one is a warning; none refused a row. The common kind is "family": lines reach the old name through a glob, a regex or a built name, so no rewrite decides them and a person does (the suite ledger checks). Counts: W1 54, W2 135, W3 45, W4 3, W5 6, W6a 18, W6b 2, 263 in all. One line per row: old path, then why.

```
### W1 (54 flagged)
bin/policy-constitution-install.sh  3 lines in 3 files reach it by family `constitution` (glob, regex or built name), first bin/guard-bash.sh:1241
docs/explanation/absent-by-decision.md  4 lines in 3 files reach it by family `absent` (glob, regex or built name), first contracts/gates.md:82
docs/explanation/case-law.md  4 lines in 4 files reach it by family `case` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-hook-engine-and-eval-internals.md:47
docs/explanation/doc-truth.md  1 lines in 1 files reach it by family `doc` (glob, regex or built name), first bin/guard-deliverables.sh:67
docs/explanation/no-authored-plugins.md  9 lines in 6 files reach it by family `no` (glob, regex or built name), first bin/admission-mutation-tier.sh:129
contracts/host-profile.md  2 lines in 1 files reach it by family `box` (glob, regex or built name), first bin/access-browser-agent.sh:417
contracts/browser-agent-hosts.txt  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
contracts/browser-routing.md  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
contracts/core-writes-allow.tsv  9 lines in 8 files reach it by family `core` (glob, regex or built name), first bin/deploy-bootstrap.sh:76
contracts/decision-orphans.tsv  4 lines in 4 files reach it by family `decision` (glob, regex or built name), first contracts/session-waiting.tsv:16
contracts/dev-paths-allow.tsv  4 lines in 3 files reach it by family `dev` (glob, regex or built name), first bin/scope-layers.sh:6
contracts/domain-allow.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
contracts/domain-repos-allow.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
contracts/domain-terms.tsv  1 lines in 1 files reach it by family `domain` (glob, regex or built name), first bin/lint-leaks.sh:66
contracts/event-kinds.tsv  2 lines in 1 files reach it by family `event` (glob, regex or built name), first bin/guard-bash.sh:343
contracts/event-rules.tsv  2 lines in 1 files reach it by family `event` (glob, regex or built name), first bin/guard-bash.sh:343
contracts/fresh-checks.tsv  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/doc/fresh-verify/fresh-verify.test.sh:42
contracts/git-verbs.md  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
contracts/control-plane-state.md  26 lines in 13 files reach it by family `helm` (glob, regex or built name), first contracts/README.md:30
contracts/hooks-external.tsv  8 lines in 5 files reach it by family `hooks` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/characterise-ecc-test-suite-method.md:43
contracts/issue-taxonomy.tsv  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first docs/explanation/admission-baseline.md:2092
contracts/lint-core-writes-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-dev-paths-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-domain-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-domain-repos-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-leaks-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-secrets-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/lint-siblings-baseline.txt  3 lines in 2 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
contracts/log-exempt.tsv  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
contracts/memory-format.md  1 lines in 1 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
contracts/merge-stack-union.txt  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first contracts/event-rules.tsv:20
contracts/pack-frontmatter-keys.txt  1 lines in 1 files reach it by family `pack` (glob, regex or built name), first bin/pack.sh:166
contracts/port-paths-exempt.tsv  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
contracts/port-root.md  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
contracts/private-layer.md  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
contracts/redteam-baseline.tsv  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first docs/reference/checks.md:58
contracts/redteam-sources.tsv  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first docs/reference/checks.md:58
contracts/repo-slug.txt  9 lines in 9 files reach it by family `repo` (glob, regex or built name), first contracts/pack.md:124
contracts/secret-legacy-refs.txt  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:180
contracts/session-waiting.tsv  3 lines in 2 files reach it by family `session` (glob, regex or built name), first contracts/cli.md:202
contracts/test-contract.md  4 lines in 4 files reach it by family `test` (glob, regex or built name), first bin/guard-stop.sh:271
docs/how-to/harden-the-host.md  1 lines in 1 files reach it by family `SEC` (glob, regex or built name), first tests/skill/prove/report.test.sh:24
docs/reports/platform-epic.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
docs/reports/platform-build-tickets.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
docs/src/timing.html  3 lines in 2 files reach it by family `10` (glob, regex or built name), first tests/lint/conventions/injection-rule.test.sh:75
docs/src/injection-rule.html  4 lines in 2 files reach it by family `30` (glob, regex or built name), first tests/ci/merge-stack/merge.test.sh:40
patches/doc-generate-check.patch.md  1 lines in 1 files reach it by family `governance` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:106
patches/admission-shard.patch.md  1 lines in 1 files reach it by family `governance` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:106
evals/policy/e12rule9/run-disclose.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first contracts/session-waiting.tsv:17
evals/policy/e12rule9/run-inturn.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first contracts/session-waiting.tsv:17
evals/policy/e12rule9/run-mid.sh  9 lines in 7 files reach it by family `run` (glob, regex or built name), first contracts/session-waiting.tsv:17
evals/skill/e5trap/hooks/gate.test.sh  11 lines in 9 files reach it by family `gate` (glob, regex or built name), first .agents/protected-paths.tsv:70
docs/reference/provenance.md  6 lines in 6 files name it beside a same-path file, left as written, first NOTICE:8
docs/reference/provenance.md  79 lines in 36 files name docs/reference/provenance.md, which 3 other tracked files also end with, rewritten to this one, first docs/reference/citations.md:15

### W2 (135 flagged)
tests/lint/adoption/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/doc/cite-verify/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/doc/index-generate/index-generate.test.sh  3 lines in 3 files reach it by family `docs` (glob, regex or built name), first bin/lint-conventions.sh:3639
tests/doc/freshness/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/doc/graph-generate/graph-generate.test.sh  2 lines in 2 files reach it by family `graph` (glob, regex or built name), first bin/memory.sh:145
tests/lint/conventions/conventions.test.sh  7 lines in 5 files reach it by family `lint` (glob, regex or built name), first bin/lint-findings.sh:384
tests/lint/module-shape/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/eval/redteam-corpus/redteam-corpus.test.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first docs/reference/checks.md:58
tests/lint/rule-health/rule-health.test.sh  3 lines in 2 files reach it by family `rule` (glob, regex or built name), first hooks/injection-rule/compaction-digest.test.sh:38
tests/check/schedules/schedules.test.sh  4 lines in 3 files reach it by family `schedules` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/standard/rename/rename.test.sh  7 lines in 3 files reach it by family `standard` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-hook-engine-and-eval-internals.md:164
tests/test/contract/contract.test.sh  4 lines in 4 files reach it by family `test` (glob, regex or built name), first bin/guard-stop.sh:271
tests/doc/visual-check/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/ci/governor/ladder.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/governor/liveness.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/governor/priority.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/governor/governor.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/queue/queue.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runner/alarm.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runner/wedge.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runners/lost.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runners/switch.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runners/runners.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/runs-on/runs-on.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/ci/verified/verified.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/doc/fresh-verify/fresh-verify.test.sh  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/doc/fresh-verify/fresh-verify.test.sh:42
tests/ci/github-plan/github-plan.test.sh  7 lines in 5 files reach it by family `gh` (glob, regex or built name), first bin/floor-normalize.awk:70
tests/deploy/hooks/env.test.sh  8 lines in 5 files reach it by family `hooks` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/characterise-ecc-test-suite-method.md:43
tests/ci/main-tip-verdict/main-tip-verdict.test.sh  5 lines in 3 files reach it by family `main` (glob, regex or built name), first bin/gate-merge-stack.sh:329
tests/gate/merge-check/merge-check.test.sh  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first contracts/event-rules.tsv:20
tests/ci/merge-stack/backdoor-generate.sh  1 lines in 1 files reach it by family `backdoor` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
tests/gate/merged-check/merged-check.test.sh  4 lines in 4 files reach it by family `merged` (glob, regex or built name), first contracts/event-rules.tsv:20
tests/status/plan-generate/plan-generate.test.sh  6 lines in 2 files reach it by family `plan` (glob, regex or built name), first bin/standard-catalog.sh:314
tests/gate/pr-wait/pr-wait.test.sh  16 lines in 6 files reach it by family `pr` (glob, regex or built name), first docs/explanation/admission-baseline.md:2092
tests/status/generate/generate.test.sh  6 lines in 5 files reach it by family `status` (glob, regex or built name), first evals/skill/e5trap/opsctl:93
tests/worktree/worktree/worktree.test.sh  5 lines in 4 files reach it by family `worktree` (glob, regex or built name), first bin/lint-domain.sh:44
tests/access/cli/add-prompts.test.sh  11 lines in 8 files reach it by family `add` (glob, regex or built name), first bin/context-resolve.sh:139
tests/access/cli/secret-gate.test.sh  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:180
tests/access/browser-hosts-add/browser-hosts-add.test.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
tests/access/browser/browser.test.sh  11 lines in 8 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
tests/access/browser/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/access/browser/private-hosts.test.sh  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
tests/audit/collector/collector.test.sh  4 lines in 3 files reach it by family `collector` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/status/console/guards.test.sh  1 lines in 1 files reach it by family `console` (glob, regex or built name), first bin/access-browser-agent.sh:188
tests/status/console/panels.test.sh  1 lines in 1 files reach it by family `console` (glob, regex or built name), first bin/access-browser-agent.sh:188
tests/doc/drive-push/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/access/gcloud-credentials/gcloud-credentials.test.sh  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
tests/access/gcloud-credentials/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/access/gcloud/gcloud.test.sh  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
tests/access/gcloud/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/access/github-app/routing.test.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
tests/housekeeping/clean/clean.test.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
tests/deploy/cli/cli.test.sh  23 lines in 14 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
tests/memory/idea/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/standard/issue-label/issue-label.test.sh  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first docs/explanation/admission-baseline.md:2092
tests/deploy/live-verify/live-verify.test.sh  2 lines in 2 files reach it by family `live` (glob, regex or built name), first bin/guard-egress.sh:64
tests/doc/report-verify/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/access/secret/seam.test.sh  5 lines in 4 files reach it by family `secret` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:180
tests/access/secret/secret.test.sh  9 lines in 7 files reach it by family `secret` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:180
tests/event/wait-for/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/deploy/push/ci-mirror.test.sh  3 lines in 2 files reach it by family `ci` (glob, regex or built name), first bin/deploy-harden.sh:64
tests/admission/deny-hash/deny-hash.test.sh  6 lines in 5 files reach it by family `deny` (glob, regex or built name), first bin/floor-hook.sh:65
tests/admission/deny-hash/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/admission/destroy/snapshot.test.sh  1 lines in 1 files reach it by family `destroy` (glob, regex or built name), first skills/access-ledger/bin/check-routes.sh:685
tests/admission/equivalence/equivalence.test.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/admission/equivalence/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/admission/baseline/fixture.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/admission/baseline/baseline.test.sh  36 lines in 26 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/admission/git/verbs.test.sh  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
tests/scope/marker-backfill/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/scope/marker/marker.test.sh  6 lines in 4 files reach it by family `marker` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/admission/normalize/normalize.test.sh  4 lines in 3 files reach it by family `normalize` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/eval/pass-score/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/deploy/restore/recover.test.sh  4 lines in 3 files reach it by family `recover` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/eval/replay/replay.test.sh  4 lines in 3 files reach it by family `replay` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/eval/replay/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/admission/bash/bash.test.sh  32 lines in 14 files reach it by family `bash` (glob, regex or built name), first registries/coverage-incidents.tsv:110
tests/admission/cloud/cloud.test.sh  6 lines in 5 files reach it by family `cloud` (glob, regex or built name), first bin/lint-conventions.sh:3834
tests/admission/deliverables/deliverables.test.sh  4 lines in 3 files reach it by family `deliverables` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/admission/destroy/destroy.test.sh  5 lines in 4 files reach it by family `destroy` (glob, regex or built name), first skills/access-ledger/bin/check-routes.sh:685
tests/admission/egress/egress.test.sh  5 lines in 4 files reach it by family `egress` (glob, regex or built name), first bin/lint-conventions.sh:5769
tests/admission/bash/fixture.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/admission/selfedit/selfedit.test.sh  4 lines in 3 files reach it by family `selfedit` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/context/injection-rule/agent-brief.test.sh  7 lines in 6 files reach it by family `agent` (glob, regex or built name), first bin/status-obligations.sh:644
tests/admission/apiroute/apiroute.test.sh  3 lines in 2 files reach it by family `apiroute` (glob, regex or built name), first bin/guard-apiroute.sh:246
tests/eval/hook-replay/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/context/injection-rule/fixture.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/context/injection-rule/notes.test.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/context/injection-rule/name-note.test.sh  8 lines in 6 files reach it by family `name` (glob, regex or built name), first contracts/pack.md:124
tests/admission/prod/prod.test.sh  2 lines in 2 files reach it by family `prod` (glob, regex or built name), first bin/guard-egress.sh:337
tests/memory/log-token-save/log-token-save.test.sh  2 lines in 2 files reach it by family `save` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:113
tests/status/statusline/statusline.test.sh  4 lines in 3 files reach it by family `statusline` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/admission/stop/stop.test.sh  1 lines in 1 files reach it by family `stop` (glob, regex or built name), first contracts/event-rules.tsv:20
tests/deploy/bootstrap/bootstrap.test.sh  7 lines in 6 files reach it by family `bootstrap` (glob, regex or built name), first launchd/com.harbor.judge.plist:42
tests/policy/constitution-install/constitution-install.test.sh  2 lines in 2 files reach it by family `constitution` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/deploy/deploy/deploy.test.sh  36 lines in 19 files reach it by family `deploy` (glob, regex or built name), first docs/explanation/admission-baseline.md:1908
tests/deploy/doctor/doctor.test.sh  4 lines in 3 files reach it by family `doctor` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/deploy/doctor/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/deploy/first-run/first-run.test.sh  13 lines in 1 files reach it by family `first` (glob, regex or built name), first bin/decider-set.sh:36
tests/admission/remove/remove.test.sh  32 lines in 23 files reach it by family `floor` (glob, regex or built name), first .agents/protected-paths.tsv:21
tests/context/injection-install/injection-install.test.sh  5 lines in 4 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
tests/drift/install/install.test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
tests/deploy/install/exec.test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
tests/deploy/install-stamp/install-stamp.test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
tests/lint/port-paths/port-paths.test.sh  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
tests/lint/port-paths/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/lint/port-paths/private-exempt.test.sh  1 lines in 1 files reach it by family `private` (glob, regex or built name), first bin/lint-constitution.sh:50
tests/scope/roots/roots.test.sh  4 lines in 3 files reach it by family `roots` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/deploy/runtime-install/runtime-install.test.sh  1 lines in 1 files reach it by family `runtime` (glob, regex or built name), first tests/drift/renew-check/renew-check.test.sh:237
tests/deploy/harden/harden.test.sh  1 lines in 1 files reach it by family `sec0` (glob, regex or built name), first bin/proposal.sh:96
tests/deploy/shim-install/shim-install.test.sh  3 lines in 2 files reach it by family `shim` (glob, regex or built name), first tests/deploy/deploy/deploy.test.sh:122
tests/skill/collision-verify/collision-verify.test.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first contracts/issue-taxonomy.tsv:113
tests/skill/install/install.test.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first contracts/issue-taxonomy.tsv:113
tests/test/lib/check.test.sh  16 lines in 9 files reach it by family `check` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-hook-engine-and-eval-internals.md:116
tests/deploy/install-lib/install-lib.test.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
tests/test/lib/lib.test.sh  6 lines in 4 files reach it by family `lib` (glob, regex or built name), first bin/guard-bash.sh:644
tests/standard/log-lib/log-lib.test.sh  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
tests/context/budget/budget.test.sh  2 lines in 2 files reach it by family `context` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:146
tests/context/ratchet/ratchet.test.sh  2 lines in 2 files reach it by family `context` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:146
tests/memory/route/route.test.sh  1 lines in 1 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
tests/memory/memory/memory.test.sh  5 lines in 4 files reach it by family `memory` (glob, regex or built name), first bin/ci-runners-fleet-lib.sh:232
tests/memory/store-check/store-check.test.sh  4 lines in 2 files reach it by family `store` (glob, regex or built name), first bin/lint-secrets.sh:11
tests/eval/tally/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/lint/findings-run/findings-run.test.sh  1 lines in 1 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
tests/lint/findings/findings.test.sh  5 lines in 4 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
tests/audit/triage-run/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/proposal/proposal/proposal.test.sh  4 lines in 3 files reach it by family `proposal` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/proposal/proposal/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/alert/probe/probe.test.sh  4 lines in 3 files reach it by family `pulse` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
tests/skill/fire/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/status/usage-aggregate/output-contract.test.sh  1 lines in 1 files reach it by family `output` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
tests/skill/eval-runners/eval-runners.test.sh  6 lines in 3 files reach it by family `eval` (glob, regex or built name), first bin/guard-bash.sh:485
tests/skill/prove/prove.test.sh  4 lines in 3 files reach it by family `prove` (glob, regex or built name), first tests/lint/conventions/suites.test.sh:31
fixtures/admission-corpus.jsonl  108 lines in 55 files reach it by family `guard` (glob, regex or built name), first .agents/protected-paths.tsv:20
fixtures/injection-rule/packs/example-store/wipe-destroys-history.md  3 lines in 2 files reach it by family `10` (glob, regex or built name), first tests/lint/conventions/injection-rule.test.sh:75

### W3 (45 flagged)
bin/access-browser-agent.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
bin/access-browser-cdp.mjs  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
bin/access-browser-hosts-add.sh  7 lines in 5 files reach it by family `browser` (glob, regex or built name), first contracts/suite-paths.txt:35
bin/status-dashboard-generate.sh  1 lines in 1 files reach it by family `dashboard` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
bin/doc-drive-push.sh  1 lines in 1 files reach it by family `deliver` (glob, regex or built name), first inject.d/box/agent-brief.sh:36
bin/admission-deny-hash.sh  6 lines in 5 files reach it by family `deny` (glob, regex or built name), first bin/floor-hook.sh:65
bin/doc-index-generate.sh  4 lines in 4 files reach it by family `docs` (glob, regex or built name), first bin/lint-conventions.sh:3639
bin/doc-fresh-verify.sh  1 lines in 1 files reach it by family `fresh` (glob, regex or built name), first tests/doc/fresh-verify/fresh-verify.test.sh:42
bin/standard-frozen-generate.sh  1 lines in 1 files reach it by family `frozen` (glob, regex or built name), first tests/ci/merge-stack/rehearse.test.sh:43
bin/ci-github-plan.sh  7 lines in 5 files reach it by family `gh` (glob, regex or built name), first bin/floor-normalize.awk:70
bin/doc-graph-generate.sh  3 lines in 3 files reach it by family `graph` (glob, regex or built name), first bin/memory.sh:145
bin/access-github-app-install.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
bin/housekeeping-clean.sh  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
bin/context-injection-install.sh  6 lines in 5 files reach it by family `inject` (glob, regex or built name), first bin/guard-bash.sh:1241
bin/drift-install.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
bin/deploy-install-lib.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
bin/deploy-install-stamp.sh  25 lines in 13 files reach it by family `install` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-agentic-architecture-deep-dive.md:80
bin/standard-issue-label.sh  16 lines in 4 files reach it by family `issue` (glob, regex or built name), first docs/explanation/admission-baseline.md:2092
bin/deploy-live-verify.sh  2 lines in 2 files reach it by family `live` (glob, regex or built name), first bin/guard-egress.sh:64
bin/library-log.sh  4 lines in 3 files reach it by family `log` (glob, regex or built name), first bin/guard-bash.sh:1599
bin/ci-main-tip-verdict.sh  5 lines in 3 files reach it by family `main` (glob, regex or built name), first bin/gate-merge-stack.sh:329
bin/scope-marker-backfill.sh  2 lines in 1 files reach it by family `marker` (glob, regex or built name), first tests/scope/registry/repo.test.sh:331
bin/gate-merge-check.sh  17 lines in 14 files reach it by family `merge` (glob, regex or built name), first contracts/event-rules.tsv:20
bin/gate-merged-check.sh  4 lines in 4 files reach it by family `merged` (glob, regex or built name), first contracts/event-rules.tsv:20
bin/eval-pass-score.sh  4 lines in 4 files reach it by family `pass` (glob, regex or built name), first bin/gate-merge-check.sh:309
bin/status-plan-generate.sh  6 lines in 2 files reach it by family `plan` (glob, regex or built name), first bin/standard-catalog.sh:314
bin/lint-port-paths.sh  1 lines in 1 files reach it by family `port` (glob, regex or built name), first bin/lint-domain.sh:44
bin/gate-pr-wait.sh  16 lines in 6 files reach it by family `pr` (glob, regex or built name), first docs/explanation/admission-baseline.md:2092
bin/eval-redteam-corpus.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first docs/reference/checks.md:58
bin/doc-report-verify.sh  2 lines in 2 files reach it by family `report` (glob, regex or built name), first bin/standard-catalog.sh:314
bin/lint-rule-health.sh  3 lines in 2 files reach it by family `rule` (glob, regex or built name), first hooks/injection-rule/compaction-digest.test.sh:38
bin/deploy-runtime-install.sh  2 lines in 2 files reach it by family `runtime` (glob, regex or built name), first tests/admission/baseline/install.test.sh:319
bin/memory-log-token-save.sh  2 lines in 2 files reach it by family `save` (glob, regex or built name), first evals/context/2026-09-07-ecc/subagent-reports/ecc-session-continuity-mechanics.md:113
bin/deploy-harden.sh  1 lines in 1 files reach it by family `sec0` (glob, regex or built name), first bin/proposal.sh:96
bin/skill-collision-verify.sh  7 lines in 7 files reach it by family `skills` (glob, regex or built name), first contracts/issue-taxonomy.tsv:113
bin/skill-install.sh  8 lines in 8 files reach it by family `skills` (glob, regex or built name), first contracts/issue-taxonomy.tsv:113
bin/status-generate.sh  7 lines in 6 files reach it by family `status` (glob, regex or built name), first evals/skill/e5trap/opsctl:93
bin/memory-store-check.sh  4 lines in 2 files reach it by family `store` (glob, regex or built name), first bin/lint-secrets.sh:11
bin/access-github-app/git-credential.sh  5 lines in 4 files reach it by family `git` (glob, regex or built name), first bin/floor-normalize.awk:70
bin/library-gate.sh  7 lines in 6 files reach it by family `gate` (glob, regex or built name), first .agents/protected-paths.tsv:70
commands/context-budget.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
commands/gate-merge.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
commands/skill-catalog.md  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
bin/doc-visual-check.mjs  1 lines in 1 files name it beside a same-path file, left as written, first vendor/archify/bin/archify.mjs:1242
bin/doc-visual-check.mjs  9 lines in 6 files name bin/doc-visual-check.mjs, which 1 other tracked files also end with, rewritten to this one, first contracts/browser-routing.md:279

### W4 (3 flagged)
bin/gcloud-credentials  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
bin/gcloud  15 lines in 4 files reach it by family `gcloud` (glob, regex or built name), first bin/ci-runs-on.sh:61
bin/deploy-shim-install.sh  4 lines in 3 files reach it by family `shim` (glob, regex or built name), first tests/admission/baseline/install.test.sh:319

### W5 (6 flagged)
bin/lint-findings-run.sh  1 lines in 1 files reach it by family `findings` (glob, regex or built name), first bin/lint-module.sh:82
bin/eval-redteam-corpus-run.sh  1 lines in 1 files reach it by family `redteam` (glob, regex or built name), first docs/reference/checks.md:58
systemd/harbor-judge.service  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
systemd/harbor-judge.timer  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
systemd/harbor-pulse.service  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657
systemd/harbor-pulse.timer  19 lines in 11 files reach it by family `harbor` (glob, regex or built name), first bin/access-browser-agent.sh:657

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
