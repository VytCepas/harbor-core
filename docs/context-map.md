---
kind: context-map
status: generated
owner_issue: 996
layer: generated
---

# Context map

Where every tracked file sits on the levels of D-57, generated from the catalog; do not edit.

Regenerate with `sh bin/standard-catalog.sh --map`; `sh bin/standard-catalog.sh --check` is red when this file is stale.
Ask the catalog instead of reading this page: `harbor find <family>` lists a family's scripts, tests, checks, docs and controls,
`harbor tree` renders the levels, and `sh bin/standard-catalog.sh --census` writes `build/catalog.tsv` with every row and
`build/catalog-findings.tsv` with every level the registry could not fill. The README and HANDOFF sections that describe the
layout stay; this page adds to them and never replaces them.

## Levels

metasystem › domain › system › subsystem › family › component › element

System `harbor` sits in domain `platform`. A file's subsystem is read from its family's `broader` chain in `standards/naming/terms.tsv`.

## Kinds and where they live

| Kind | Folder | Level | Layer | Lifecycle | Files |
|---|---|---|---|---|---|
| policy | policy/ | system | source | living | 11 |
| standard | standards/ | system | source | versioned | 13 |
| contract | contracts/ | system | source | versioned | 30 |
| decision-record | docs/decisions/ | element | source | dated | 88 |
| injection-rule | context-rules/<scope>/ | component | source | living | 35 |
| hook | bin/ | component | source | living | 12 |
| skill | skills/ | component | source | living | 41 |
| fixture | fixtures/ | element | source | living | 252 |
| registry | registries/ | component | source | versioned | 49 |
| test | tests/ | component | source | living | 426 |
| report | docs/reports/ | element | report | dated | 1 |
| design | docs/design/ | component | source | living | 6 |
| context-map | docs/context-map.md | system | generated | generated | 1 |
| script | bin/ | component | source | living | 208 |
| (no kind) | - | - | - | - | 171 |

## Folders

| Folder | Files | Families | Kinds |
|---|---|---|---|
| (repo root) | 21 | 3 | 2 |
| `.agents/` | 4 | 1 | 1 |
| `.claude/` | 4 | 1 | 1 |
| `.github/` | 4 | 2 | 1 |
| `CONTRACTS/` | 79 | 9 | 2 |
| `DOCTRINE/` | 10 | 1 | 1 |
| `bin/` | 213 | 22 | 2 |
| `commands/` | 5 | 1 | 1 |
| `docs/` | 109 | 6 | 5 |
| `fixtures/` | 252 | 9 | 1 |
| `hooks/` | 7 | 1 | 1 |
| `inject.d/` | 31 | 1 | 1 |
| `launchd/` | 12 | 3 | 1 |
| `patches/` | 12 | 1 | 1 |
| `runners/` | 2 | 1 | 1 |
| `skills/` | 41 | 5 | 1 |
| `standards/` | 13 | 1 | 1 |
| `systemd/` | 15 | 1 | 1 |
| `tests/` | 426 | 21 | 1 |
| `tools/` | 10 | 2 | 1 |
| `vendor/` | 73 | 1 | 1 |
| `worklog/` | 1 | 1 | 1 |

## Families

| Family | Subsystem | Scripts | Tests | Docs | Other files | Checks | Controls |
|---|---|---|---|---|---|---|---|
| access | control-plane | 4 | 6 | 2 | 2 | 0 | 0 |
| admission | control-plane | 5 | 1 | 0 | 0 | 0 | 146 |
| alert | observability | 1 | 1 | 0 | 0 | 0 | 0 |
| audit | control-plane | 0 | 0 | 0 | 0 | 0 | 2 |
| check | observability | 1 | 4 | 0 | 1 | 50 | 0 |
| ci | coordination | 12 | 58 | 1 | 3 | 0 | 5 |
| context | control-plane | 3 | 0 | 1 | 36 | 0 | 29 |
| deploy | control-plane | 4 | 6 | 1 | 1 | 0 | 7 |
| doc | control-plane | 1 | 1 | 0 | 8 | 0 | 16 |
| drift | control-plane | 1 | 1 | 0 | 4 | 2 | 12 |
| eval | control-plane | 0 | 1 | 0 | 0 | 0 | 0 |
| event | observability | 3 | 16 | 0 | 2 | 0 | 0 |
| gate | control-plane | 10 | 7 | 0 | 0 | 0 | 0 |
| housekeeping | control-plane | 0 | 0 | 0 | 2 | 0 | 0 |
| lint | control-plane | 15 | 37 | 0 | 8 | 0 | 31 |
| memory | memory-store | 4 | 11 | 1 | 23 | 0 | 1 |
| pack | catalog | 1 | 0 | 1 | 1 | 0 | 0 |
| policy | policy-function | 0 | 0 | 11 | 0 | 0 | 3 |
| proposal | proposal-pipeline | 1 | 2 | 0 | 0 | 0 | 0 |
| scope | coordination | 1 | 10 | 0 | 0 | 0 | 4 |
| session | data-plane | 10 | 5 | 0 | 1 | 0 | 0 |
| skill | catalog | 3 | 5 | 0 | 4 | 0 | 11 |
| standard | policy-function | 3 | 8 | 101 | 0 | 0 | 43 |
| status | observability | 3 | 7 | 0 | 1 | 0 | 0 |
| test | control-plane | 0 | 1 | 2 | 7 | 0 | 7 |
| worktree | coordination | 1 | 0 | 0 | 0 | 0 | 0 |

## Per family

Scripts, hooks, docs and other files by path; tests, fixtures and eval data are counted above and not listed. A path's purpose is in `harbor find <family>`.

### access

- `CONTRACTS/access-card.md`
- `CONTRACTS/access-register.md`
- `bin/access-chrome-mcp.py`
- `bin/access-confinement.sh`
- `bin/access-environment.sh`
- `bin/access.sh`
- `skills/access-ledger/SKILL.md`

### admission

- `bin/guard-bash.sh`
- `bin/guard-cloud.sh`
- `bin/guard-egress.sh`
- `bin/guard-selfedit.sh`
- `bin/guard-stop.sh`

### alert

- `bin/alert-lib.sh`

### check

- `CHECKS.md`
- `bin/check-registry-generate.sh`

### ci

- `.github/workflows/governance.yml`
- `.github/workflows/public-ci.yml`
- `bin/ci-governor-hook.sh`
- `bin/ci-governor.sh`
- `bin/ci-lost-job.sh`
- `bin/ci-mirror.sh`
- `bin/ci-queue.sh`
- `bin/ci-runners-fleet-lib.sh`
- `bin/ci-runners-github-lib.sh`
- `bin/ci-runners-provision-lib.sh`
- `bin/ci-runners-watch-lib.sh`
- `bin/ci-runners.sh`
- `bin/ci-runs-on.sh`
- `bin/ci-verified.sh`
- `docs/design/ci-local-heal.md`
- `launchd/com.harbor.ci-governor.plist`

### context

- `.claude/inject.d/10-constitution-edit-is-undeployed.md`
- `.claude/inject.d/20-merge-governance.md`
- `.claude/inject.d/21-post-merge-state.md`
- `.claude/inject.d/merge-note.sh`
- `bin/context-budget.sh`
- `bin/context-resolve.sh`
- `bin/inject-hook.sh`
- `docs/context-map.md`
- `inject.d/box/10-subagent-contract.md`
- `inject.d/box/20-post-compaction-carry.md`
- `inject.d/box/30-external-content-is-data.md`
- `inject.d/box/40-repo-skills-pointer.md`
- `inject.d/box/45-access-route-pointer.md`
- `inject.d/box/50-project-pointer.md`
- `inject.d/box/60-variable-is-one-argument.md`
- `inject.d/box/65-browser-route-harbor-chrome.md`
- `inject.d/box/66-browser-route-reminder.md`
- `inject.d/box/70-confinement-refused.md`
- `inject.d/box/80-large-tool-result.md`
- `inject.d/box/85-tool-failure-is-not-a-result.md`
- `inject.d/box/90-unbounded-wait-loop.md`
- `inject.d/box/95-repo-tier-not-loaded.md`
- `inject.d/box/96-agent-brief.md`
- `inject.d/box/97-agent-model-required.md`
- `inject.d/box/98-name-note.md`
- `inject.d/box/access-route.sh`
- `inject.d/box/agent-brief.sh`
- `inject.d/box/agent-model.sh`
- `inject.d/box/browser-route.sh`
- `inject.d/box/confinement-refused.sh`
- `inject.d/box/large-tool-result.sh`
- `inject.d/box/name-note.sh`
- `inject.d/box/post-compaction-carry.sh`
- `inject.d/box/project-pointer.sh`
- `inject.d/box/repo-skills.sh`
- `inject.d/box/repo-tier.sh`
- `inject.d/box/tool-failure.sh`
- `inject.d/box/unbounded-wait-loop.sh`
- `inject.d/box/variable-is-one-argument.sh`

### deploy

- `bin/deploy-confinement.sh`
- `bin/deploy-fleet.sh`
- `bin/deploy-push.sh`
- `bin/deploy.sh`
- `docs/design/deploy-fleet.md`

### doc

- `bin/doc-refs.sh`

### drift

- `bin/drift-confinement.sh`

### event

- `CONTRACTS/event-rules.tsv`
- `bin/event-bus.sh`
- `bin/event-dispatch.sh`
- `bin/event-hook.sh`
- `launchd/com.harbor.event.dispatch.plist`

### gate

- `bin/gate-approve.sh`
- `bin/gate-classify.sh`
- `bin/gate-codeowners.sh`
- `bin/gate-lib.sh`
- `bin/gate-merge-stack-resolve.py`
- `bin/gate-merge-stack.sh`
- `bin/gate-merge.sh`
- `bin/gate-queue.sh`
- `bin/gate-register-derive.sh`
- `bin/gate-required-generate.sh`

### housekeeping

- `skills/housekeeping/SKILL.md`

### lint

- `CONTRACTS/lint-core-writes-baseline.txt`
- `CONTRACTS/lint-dev-paths-baseline.txt`
- `CONTRACTS/lint-domain-baseline.txt`
- `CONTRACTS/lint-domain-repos-baseline.txt`
- `CONTRACTS/lint-leaks-baseline.txt`
- `CONTRACTS/lint-secrets-baseline.txt`
- `CONTRACTS/lint-siblings-baseline.txt`
- `bin/lint-comment-commands.awk`
- `bin/lint-constitution.sh`
- `bin/lint-conventions.sh`
- `bin/lint-core-writes.sh`
- `bin/lint-dev-paths.sh`
- `bin/lint-domain.sh`
- `bin/lint-layout-map.sh`
- `bin/lint-leaks.sh`
- `bin/lint-locale-ranges.awk`
- `bin/lint-module.sh`
- `bin/lint-name.sh`
- `bin/lint-platform.sh`
- `bin/lint-secrets.sh`
- `bin/lint-share.sh`
- `bin/lint-siblings.sh`

### memory

- `CONTRACTS/memory-format.md`
- `bin/memory-harvest.sh`
- `bin/memory-lint.sh`
- `bin/memory-route.sh`
- `bin/memory.sh`
- `tools/memory/memory-engine.test.ts`
- `tools/memory/memory-engine.ts`

### pack

- `CONTRACTS/pack-frontmatter-keys.txt`
- `CONTRACTS/pack.md`
- `bin/pack.sh`

### policy

- `CONSTITUTION.md`
- `DOCTRINE/absent-by-decision.md`
- `DOCTRINE/case-law.md`
- `DOCTRINE/credential-boundary.md`
- `DOCTRINE/critique-expanded.md`
- `DOCTRINE/doc-truth.md`
- `DOCTRINE/grilling.md`
- `DOCTRINE/modularity.md`
- `DOCTRINE/no-authored-plugins.md`
- `DOCTRINE/verification-expanded.md`
- `DOCTRINE/wiring-new-capability.md`

### proposal

- `bin/proposal.sh`

### scope

- `bin/scope.sh`

### session

- `CONTRACTS/session-waiting.tsv`
- `bin/session-check.sh`
- `bin/session-ci-watch.sh`
- `bin/session-cleanup-report.sh`
- `bin/session-notify.sh`
- `bin/session-react-lib.sh`
- `bin/session-save-now.sh`
- `bin/session-state.sh`
- `bin/session-subagent-check.sh`
- `bin/session-title.sh`
- `bin/session-verdicts.sh`

### skill

- `CONTRACTS/skill-book-router.tsv`
- `CONTRACTS/skill-pack-frontmatter-keys.txt`
- `bin/skill-book.sh`
- `bin/skill-fire.sh`
- `bin/skill-usage.sh`
- `skills/skill-book/SKILL.md`

### standard

- `bin/standard-catalog.sh`
- `bin/standard-rename.sh`
- `bin/standard-shape.sh`
- `docs/decisions/0001-uppercase-policy.md`
- `docs/decisions/0002-term-for-tool-call-enforcement.md`
- `docs/decisions/0003-term-for-control-plane.md`
- `docs/decisions/0004-where-human-docs-go.md`
- `docs/decisions/0005-sense-of-metasystem.md`
- `docs/decisions/0006-term-for-ship.md`
- `docs/decisions/0007-handover-term.md`
- `docs/decisions/0008-claude-memory-and-memory-store.md`
- `docs/decisions/0009-registry-format.md`
- `docs/decisions/0010-lint-ids.md`
- `docs/decisions/0011-bin-layout.md`
- `docs/decisions/0012-marker.md`
- `docs/decisions/0013-cli-shape.md`
- `docs/decisions/0014-test-file-names.md`
- `docs/decisions/0015-env-var-prefix.md`
- `docs/decisions/0016-spelling.md`
- `docs/decisions/0017-family-granularity.md`
- `docs/decisions/0018-abbreviations.md`
- `docs/decisions/0019-id-stability.md`
- `docs/decisions/0020-references.md`
- `docs/decisions/0021-commit-messages.md`
- `docs/decisions/0022-doc-header.md`
- `docs/decisions/0023-reply-shape.md`
- `docs/decisions/0024-memory-note-names.md`
- `docs/decisions/0025-domain-material-to-workload.md`
- `docs/decisions/0026-client-names.md`
- `docs/decisions/0027-vsm.md`
- `docs/decisions/0028-versioning-the-standard.md`
- `docs/decisions/0029-status-words.md`
- `docs/decisions/0030-labels-and-issue-titles.md`
- `docs/decisions/0031-prose-references.md`
- `docs/decisions/0032-package-code-layout.md`
- `docs/decisions/0033-cloud-and-data-resources.md`
- `docs/decisions/0034-host-records.md`
- `docs/decisions/0035-skills-agents-workflows.md`
- `docs/decisions/0036-secrets.md`
- `docs/decisions/0037-harbors-own-scope.md`
- `docs/decisions/0038-object-words.md`
- `docs/decisions/0039-superseded-docs.md`
- `docs/decisions/0040-generated-docs.md`
- `docs/decisions/0041-python-ts-executables.md`
- `docs/decisions/0042-language.md`
- `docs/decisions/0043-injection-rule-order.md`
- `docs/decisions/0044-build-first.md`
- `docs/decisions/0045-workload-repo-names.md`
- `docs/decisions/0046-stand-down-fix.md`
- `docs/decisions/0047-vale.md`
- `docs/decisions/0048-commit-scope-everywhere.md`
- `docs/decisions/0049-exit-codes-and-output-tags.md`
- `docs/decisions/0050-workload-labels.md`
- `docs/decisions/0051-time-zone.md`
- `docs/decisions/0052-vendored-and-harness-names.md`
- `docs/decisions/0053-external-platform-objects.md`
- `docs/decisions/0054-domain-abbreviations.md`
- `docs/decisions/0055-flow-repos.md`
- `docs/decisions/0056-remaining-gap-review-rules.md`
- `docs/decisions/0057-levels.md`
- `docs/decisions/0058-where-a-level-shows-what-system-means.md`
- `docs/decisions/0059-families-across-systems.md`
- `docs/decisions/0060-modularity-enforcement.md`
- `docs/decisions/0061-registry-shape.md`
- `docs/decisions/0062-controls.md`
- `docs/decisions/0063-the-standards-own-family.md`
- `docs/decisions/0064-mode-words.md`
- `docs/decisions/0065-repo-root.md`
- `docs/decisions/0066-rename-safety.md`
- `docs/decisions/0067-force-push-allowed-in-four-workloads.md`
- `docs/decisions/0068-memory-notes-store.md`
- `docs/decisions/0069-remaining-repo-names.md`
- `docs/decisions/0070-platform-repos-and-the-prefix-rule.md`
- `docs/decisions/0071-constitution-edits.md`
- `docs/decisions/0072-billed-probe.md`
- `docs/decisions/0073-order-of-the-registry-landing.md`
- `docs/decisions/0074-epic-done-when-full-rename.md`
- `docs/decisions/0075-cuts.md`
- `docs/decisions/0076-rename-pr-shape.md`
- `docs/decisions/0077-the-event-family.md`
- `docs/decisions/0078-the-workspace.md`
- `docs/decisions/0079-the-private-layer.md`
- `docs/decisions/0080-the-pack.md`
- `docs/decisions/0081-the-config-format.md`
- `docs/decisions/0082-repos-tsv.md`
- `docs/decisions/0083-the-share-axis.md`
- `docs/decisions/0084-command-names.md`
- `docs/decisions/0085-client-terms-leave-core.md`
- `docs/decisions/0086-the-session-family.md`
- `docs/decisions/0087-the-public-export-repo.md`
- `docs/decisions/README.md`
- `standards/modularity.md`
- `standards/naming.md`
- `standards/naming/aliases.tsv`
- `standards/naming/controls.tsv`
- `standards/naming/dialects.tsv`
- `standards/naming/exemptions.tsv`
- `standards/naming/frozen.tsv`
- `standards/naming/kinds.tsv`
- `standards/naming/registers.tsv`
- `standards/naming/renames.tsv`
- `standards/naming/repo-kinds.tsv`
- `standards/naming/surfaces.tsv`
- `standards/naming/terms.tsv`

### status

- `bin/status-console.sh`
- `bin/status-gen.sh`
- `bin/status-obligations.sh`

### test

- `CONTRACTS/test-contract.md`
- `docs/audits/test-audit.md`
- `skills/test-strength/SKILL.md`

### worktree

- `bin/worktree.sh`

## Not placed

Files whose family the registry cannot name yet (`build/catalog-findings.tsv` lists each with its reason), by top folder:

| Folder | Files without a family |
|---|---|
| (repo root) | 19 |
| `.agents/` | 4 |
| `.github/` | 2 |
| `CONTRACTS/` | 62 |
| `bin/` | 126 |
| `commands/` | 5 |
| `docs/` | 17 |
| `fixtures/` | 214 |
| `hooks/` | 7 |
| `launchd/` | 10 |
| `patches/` | 12 |
| `runners/` | 2 |
| `skills/` | 29 |
| `systemd/` | 15 |
| `tests/` | 238 |
| `tools/` | 8 |
| `vendor/` | 73 |
| `worklog/` | 1 |

## Top-level layout

Every tracked top-level entry, its kind and layer from `CONTRACTS/layout-map.tsv`; Ships is read from `CONTRACTS/layers.tsv` (core ships in harbor-core, dev is box or dev data). `bin/lint-layout-map.sh` is red on an entry with no row.

| Entry | Kind | Layer | Ships |
|---|---|---|---|
| `.agents/` | config | source | core |
| `.claude/` | config | source | core |
| `.github/` | config | source | core |
| `CONTRACTS/` | contract | source | core |
| `DOCTRINE/` | explanation | source | core |
| `EVALS-DATA/` | eval | source | dev |
| `bin/` | script | source | core |
| `commands/` | command | source | core |
| `docs/` | explanation | source | core |
| `fixtures/` | fixture | source | core |
| `hooks/` | hook | source | core |
| `inject.d/` | injection-rule | source | core |
| `launchd/` | deploy-unit | source | core |
| `patches/` | vendored | source | core |
| `runners/` | deploy-unit | source | core |
| `skills/` | skill | source | core |
| `standards/` | standard | source | core |
| `systemd/` | deploy-unit | source | core |
| `tests/` | test | source | core |
| `tools/` | code | source | core |
| `vendor/` | vendored | source | dev |
| `worklog/` | hook | source | core |
| `.gitignore` | config | source | core |
| `.gitleaks.toml` | config | source | core |
| `justfile` | config | source | core |
| `AGENTS.md` | policy | source | core |
| `CLAUDE.md` | policy | source | core |
| `CONSTITUTION.md` | policy | source | core |
| `LICENSE` | policy | source | core |
| `NOTICE` | policy | source | core |
| `SECURITY.md` | policy | source | core |
| `CONTRIBUTING.md` | policy | source | core |
| `README.md` | explanation | source | core |
| `APPROACH.md` | explanation | source | core |
| `BOUNDARY.md` | explanation | source | core |
| `PROVENANCE.md` | explanation | source | core |
| `RUNTIME.md` | explanation | source | core |
| `CITATIONS.md` | registry | source | core |
| `CHECKS.md` | registry | source | core |
| `COVERAGE.md` | registry | source | core |
| `EVALS.md` | report | source | core |
| `FLOOR.md` | explanation | source | core |
| `STATUS.md` | generated-doc | generated | dev |
| `PLAN.md` | generated-doc | generated | dev |
| `CONTEXT-BASELINE.tsv` | record | record | dev |
| `COVERAGE-INCIDENTS.tsv` | record | record | dev |
| `DEAD-ENDS.md` | record | record | dev |
| `HANDOFF.md` | handover | source | dev |
| `HANDOFF-ARCHIVE.md` | record | record | dev |
| `harbor-build-tickets.md` | record | record | dev |
| `harbor-epic.md` | record | record | dev |
| `trio-decoupling-epic.md` | record | record | dev |
| `REVIEW-2026-07-23.md` | record | record | dev |
| `SEC-0.md` | record | record | core |
| `QA-PLAN.md` | record | record | dev |
