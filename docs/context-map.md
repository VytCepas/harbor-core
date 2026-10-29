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
| policy | policy/ | system | source | living | 6 |
| standard | standards/ | system | source | versioned | 26 |
| contract | contracts/ | system | source | versioned | 33 |
| decision-record | docs/decisions/ | element | source | dated | 93 |
| hook | hooks/ | component | source | living | 47 |
| skill | skills/ | component | source | living | 47 |
| fixture | fixtures/ | element | source | living | 261 |
| registry | registries/ | component | source | versioned | 52 |
| test | tests/ | component | source | living | 446 |
| report | docs/reports/ | element | report | dated | 2 |
| design | docs/design/ | component | source | living | 7 |
| context-map | docs/context-map.md | system | generated | generated | 1 |
| script | bin/ | component | source | living | 275 |
| how-to | docs/how-to/ | component | source | living | 1 |
| reference | docs/reference/ | component | generated | generated | 5 |
| explanation | docs/explanation/ | component | source | living | 14 |
| (no kind) | - | - | - | - | 236 |

## Folders

| Folder | Files | Families | Kinds |
|---|---|---|---|
| (repo root) | 19 | 3 | 2 |
| `.agents/` | 4 | 1 | 1 |
| `.github/` | 4 | 2 | 1 |
| `DOCTRINE/` | 4 | 1 | 1 |
| `bin/` | 279 | 28 | 2 |
| `commands/` | 8 | 4 | 1 |
| `context-rules/` | 43 | 6 | 1 |
| `contracts/` | 84 | 9 | 2 |
| `docs/` | 137 | 11 | 8 |
| `fixtures/` | 261 | 10 | 1 |
| `hooks/` | 43 | 6 | 1 |
| `launchd/` | 13 | 8 | 1 |
| `patches/` | 12 | 3 | 1 |
| `policy/` | 1 | 1 | 1 |
| `registries/` | 1 | 1 | 1 |
| `runners/` | 2 | 1 | 1 |
| `skills/` | 47 | 8 | 1 |
| `standards/` | 26 | 1 | 1 |
| `systemd/` | 15 | 1 | 1 |
| `tests/` | 446 | 27 | 1 |
| `tools/` | 10 | 2 | 1 |
| `vendor/` | 92 | 1 | 1 |
| `worklog/` | 1 | 1 | 1 |

## Families

| Family | Subsystem | Scripts | Tests | Docs | Other files | Checks | Controls |
|---|---|---|---|---|---|---|---|
| access | control-plane | 12 | 20 | 2 | 6 | 0 | 0 |
| admission | control-plane | 19 | 82 | 0 | 4 | 0 | 167 |
| agent | control-plane | 0 | 1 | 0 | 5 | 0 | 0 |
| alert | observability | 5 | 3 | 0 | 2 | 0 | 0 |
| audit | control-plane | 13 | 14 | 0 | 5 | 0 | 2 |
| check | observability | 1 | 4 | 0 | 1 | 51 | 0 |
| ci | coordination | 20 | 50 | 2 | 5 | 1 | 5 |
| context | control-plane | 8 | 10 | 1 | 4 | 0 | 34 |
| deploy | control-plane | 22 | 25 | 1 | 1 | 0 | 7 |
| doc | control-plane | 21 | 12 | 0 | 33 | 0 | 17 |
| drift | control-plane | 7 | 6 | 0 | 4 | 2 | 13 |
| eval | control-plane | 11 | 7 | 0 | 1 | 0 | 0 |
| event | observability | 3 | 18 | 0 | 3 | 0 | 2 |
| gate | control-plane | 15 | 10 | 0 | 2 | 0 | 0 |
| housekeeping | control-plane | 2 | 1 | 0 | 2 | 0 | 0 |
| library | policy-function | 6 | 0 | 0 | 0 | 0 | 0 |
| lint | control-plane | 27 | 54 | 0 | 9 | 3 | 34 |
| memory | memory-store | 8 | 10 | 1 | 23 | 0 | 1 |
| pack | catalog | 1 | 0 | 1 | 1 | 0 | 0 |
| policy | policy-function | 3 | 2 | 6 | 0 | 0 | 3 |
| proposal | proposal-pipeline | 1 | 2 | 0 | 0 | 0 | 0 |
| scope | coordination | 9 | 15 | 0 | 0 | 0 | 4 |
| session | data-plane | 14 | 4 | 0 | 3 | 0 | 0 |
| skill | catalog | 7 | 18 | 0 | 10 | 0 | 13 |
| standard | policy-function | 8 | 14 | 119 | 1 | 2 | 48 |
| status | observability | 15 | 20 | 0 | 4 | 0 | 0 |
| test | control-plane | 7 | 5 | 2 | 7 | 0 | 14 |
| worktree | coordination | 1 | 2 | 0 | 0 | 0 | 0 |

## Per family

Scripts, hooks, docs and other files by path; tests, fixtures and eval data are counted above and not listed. A path's purpose is in `harbor find <family>`.

### access

- `bin/access-browser-agent.sh`
- `bin/access-browser-cdp.mjs`
- `bin/access-browser-hosts-add.sh`
- `bin/access-browser.sh`
- `bin/access-chrome-mcp.py`
- `bin/access-environment.sh`
- `bin/access-github-app-install.sh`
- `bin/access.sh`
- `bin/browser-agent.sh`
- `bin/browser.sh`
- `context-rules/user/access-route-pointer.md`
- `context-rules/user/access-route.sh`
- `contracts/access-card.md`
- `contracts/access-register.md`
- `hooks/access-confinement/access-confinement.sh`
- `hooks/access-confinement/access-confinement.test.sh`
- `skills/access-browser/SKILL.md`
- `skills/access-ledger/SKILL.md`

### admission

- `FLOOR.md`
- `bin/admission-deny-hash.sh`
- `bin/admission-mutation-tier.sh`
- `bin/admission-observe-report.sh`
- `bin/annotate-web.sh`
- `bin/floor-hook.sh`
- `bin/floor-observe.sh`
- `bin/govern-hook.sh`
- `bin/govern-token.sh`
- `bin/guard-apiroute.sh`
- `bin/guard-bash.sh`
- `bin/guard-cloud.sh`
- `bin/guard-deliverables.sh`
- `bin/guard-destroy.sh`
- `bin/guard-egress.sh`
- `bin/guard-integrity.sh`
- `bin/guard-selfedit.sh`
- `bin/guard-stop.sh`
- `bin/observe-report.sh`
- `bin/prod-guard-ambient.sh`
- `docs/explanation/admission-baseline.md`
- `patches/admission-shard.patch.md`

### agent

- `context-rules/user/agent-brief.md`
- `context-rules/user/agent-brief.sh`
- `context-rules/user/agent-model-required.md`
- `context-rules/user/agent-model.sh`
- `skills/agent-routing/SKILL.md`

### alert

- `bin/alert-lib.sh`
- `bin/alert-notify.sh`
- `bin/alert-probe.sh`
- `bin/pulse-notify.sh`
- `bin/pulse.sh`
- `docs/src/alert.html`
- `launchd/com.harbor.alert.probe.plist`

### audit

- `bin/audit-collector-check.sh`
- `bin/audit-collector-install.sh`
- `bin/audit-collector.sh`
- `bin/audit-otlp-receiver.py`
- `bin/audit-stream-export.py`
- `bin/audit-stream-lib.sh`
- `bin/audit-triage-run.sh`
- `bin/audit-triage.sh`
- `bin/collector-check.sh`
- `bin/collector-setup.sh`
- `bin/failure-capture.sh`
- `bin/judge-run.sh`
- `bin/stream-lib.sh`
- `launchd/com.harbor.audit.collector-checkpoint.plist`
- `launchd/com.harbor.audit.collector.plist`
- `launchd/com.harbor.audit.otlp-receiver.plist`
- `launchd/com.harbor.audit.triage.plist`
- `skills/audit-review-fanout/SKILL.md`

### check

- `bin/check-registry-generate.sh`
- `docs/reference/checks.md`

### ci

- `.github/workflows/governance.yml`
- `.github/workflows/public-ci.yml`
- `bin/ci-github-plan.sh`
- `bin/ci-governor-hook.sh`
- `bin/ci-governor.sh`
- `bin/ci-lost-job.sh`
- `bin/ci-main-tip-verdict.sh`
- `bin/ci-mirror.sh`
- `bin/ci-queue.sh`
- `bin/ci-release-names.sh`
- `bin/ci-runner-switch.sh`
- `bin/ci-runners-fleet-lib.sh`
- `bin/ci-runners-github-lib.sh`
- `bin/ci-runners-provision-lib.sh`
- `bin/ci-runners-watch-lib.sh`
- `bin/ci-runners.sh`
- `bin/ci-runs-on.sh`
- `bin/ci-verified.sh`
- `bin/ci-wait.sh`
- `bin/gh-plan.sh`
- `bin/main-tip-verdict.sh`
- `bin/runner-switch.sh`
- `context-rules/user/ci-wait-on-the-bus.md`
- `context-rules/user/ci-wait-on-the-bus.sh`
- `docs/design/ci-local-heal.md`
- `docs/design/ci-tests-on-this-host.md`
- `launchd/com.harbor.ci.governor.plist`

### context

- `bin/context-budget.sh`
- `bin/context-compaction-digest.sh`
- `bin/context-injection-install.sh`
- `bin/context-peers.sh`
- `bin/context-resolve.sh`
- `bin/fleet-sessions.sh`
- `commands/context-budget.md`
- `commands/harbor-context.md`
- `docs/context-map.md`
- `hooks/injection-rule/context-rules.test.sh`
- `hooks/injection-rule/injection-rule.sh`
- `registries/context-ratchet.tsv`

### deploy

- `bin/deploy-bootstrap.sh`
- `bin/deploy-confinement.sh`
- `bin/deploy-doctor.sh`
- `bin/deploy-fleet.sh`
- `bin/deploy-harden.sh`
- `bin/deploy-hooks.sh`
- `bin/deploy-install-lib.sh`
- `bin/deploy-install-stamp.sh`
- `bin/deploy-launchd-render.sh`
- `bin/deploy-live-verify.sh`
- `bin/deploy-push.sh`
- `bin/deploy-restore.sh`
- `bin/deploy-runtime-install.sh`
- `bin/deploy-shim-install.sh`
- `bin/deploy.sh`
- `bin/install-lib.sh`
- `bin/install-stamp.sh`
- `bin/launchd-render.sh`
- `bin/restore.sh`
- `bin/runtime-install.sh`
- `bin/sec0-harden.sh`
- `bin/shim-install.sh`
- `docs/design/deploy-fleet.md`

### doc

- `bin/cite-verify.sh`
- `bin/cited-paths.awk`
- `bin/deliver-drive.sh`
- `bin/doc-cite-verify.sh`
- `bin/doc-cited-paths.awk`
- `bin/doc-drive-push.sh`
- `bin/doc-fresh-verify.sh`
- `bin/doc-freshness.sh`
- `bin/doc-graph-generate.sh`
- `bin/doc-index-generate.sh`
- `bin/doc-isa-index.sh`
- `bin/doc-refs.sh`
- `bin/doc-report-verify.sh`
- `bin/doc-vale.sh`
- `bin/doc-visual-check.mjs`
- `bin/doc-visual-check.sh`
- `bin/docs-gen.sh`
- `bin/freshness.sh`
- `bin/report-contract.sh`
- `bin/visual-check.mjs`
- `bin/visual-check.sh`
- `docs/explanation/doc-truth.md`
- `patches/doc-generate-check.patch.md`
- `skills/doc-atlas/SKILL.md`
- `skills/doc-deliverable-contract/SKILL.md`
- `skills/doc-learning-artifact/SKILL.md`

### drift

- `bin/drift-confinement.sh`
- `bin/drift-install.sh`
- `bin/drift-reference-check.sh`
- `bin/drift-renew-check.sh`
- `bin/install-drift.sh`
- `bin/reference-check.sh`
- `bin/renew-check.sh`

### eval

- `bin/eval-hook-replay.sh`
- `bin/eval-pass-score.sh`
- `bin/eval-redteam-corpus-run.sh`
- `bin/eval-redteam-corpus.sh`
- `bin/eval-replay-corpus.sh`
- `bin/eval-replay-worker.sh`
- `bin/eval-replay.sh`
- `bin/eval-tally.sh`
- `bin/pass-score.sh`
- `bin/redteam-corpus-run.sh`
- `bin/redteam-corpus.sh`
- `launchd/com.harbor.eval.redteam-corpus.plist`

### event

- `bin/event-bus.sh`
- `bin/event-dispatch.sh`
- `bin/event-hook.sh`
- `contracts/event-kinds.tsv`
- `contracts/event-rules.tsv`
- `launchd/com.harbor.event.dispatch.plist`

### gate

- `bin/gate-approve.sh`
- `bin/gate-classify.sh`
- `bin/gate-codeowners.sh`
- `bin/gate-lib.sh`
- `bin/gate-merge-check.sh`
- `bin/gate-merge-stack-resolve.py`
- `bin/gate-merge-stack.sh`
- `bin/gate-merge.sh`
- `bin/gate-merged-check.sh`
- `bin/gate-pr-wait.sh`
- `bin/gate-queue.sh`
- `bin/gate-register-derive.sh`
- `bin/gate-required-generate.sh`
- `bin/merge-check.sh`
- `bin/merged-check.sh`
- `commands/gate-merge.md`
- `commands/harbor-merge.md`

### housekeeping

- `bin/harbor-clean.sh`
- `bin/housekeeping-clean.sh`
- `skills/housekeeping/SKILL.md`

### library

- `bin/fs-lib.sh`
- `bin/library-alert.sh`
- `bin/library-fs.sh`
- `bin/library-gate.sh`
- `bin/library-log.sh`
- `bin/log-lib.sh`

### lint

- `bin/findings-run.sh`
- `bin/findings.sh`
- `bin/lint-adoption.sh`
- `bin/lint-comment-commands.awk`
- `bin/lint-comment.sh`
- `bin/lint-constitution.sh`
- `bin/lint-conventions.sh`
- `bin/lint-core-writes.sh`
- `bin/lint-dev-paths.sh`
- `bin/lint-domain.sh`
- `bin/lint-findings-run.sh`
- `bin/lint-findings.sh`
- `bin/lint-layout-map.sh`
- `bin/lint-leaks.sh`
- `bin/lint-locale-ranges.awk`
- `bin/lint-module-shape.sh`
- `bin/lint-module.sh`
- `bin/lint-name.sh`
- `bin/lint-platform.sh`
- `bin/lint-port-paths.sh`
- `bin/lint-pr.sh`
- `bin/lint-renderer.sh`
- `bin/lint-rule-health.sh`
- `bin/lint-secrets.sh`
- `bin/lint-share.sh`
- `bin/lint-siblings.sh`
- `bin/port-paths.sh`
- `contracts/lint-core-writes-baseline.txt`
- `contracts/lint-dev-paths-baseline.txt`
- `contracts/lint-domain-baseline.txt`
- `contracts/lint-domain-repos-baseline.txt`
- `contracts/lint-leaks-baseline.txt`
- `contracts/lint-secrets-baseline.txt`
- `contracts/lint-siblings-baseline.txt`
- `launchd/com.harbor.lint.findings.plist`

### memory

- `bin/memory-lint.sh`
- `bin/memory-log-token-save.sh`
- `bin/memory-route.sh`
- `bin/memory-store-check.sh`
- `bin/memory.sh`
- `bin/save-log-token.sh`
- `bin/store-check.sh`
- `contracts/memory-format.md`
- `hooks/memory-harvest/memory-harvest.sh`
- `tools/memory/memory-engine.test.ts`
- `tools/memory/memory-engine.ts`

### pack

- `bin/pack.sh`
- `contracts/pack-frontmatter-keys.txt`
- `contracts/pack.md`

### policy

- `CONSTITUTION.md`
- `DOCTRINE/credential-boundary.md`
- `DOCTRINE/doc-truth.md`
- `DOCTRINE/modularity.md`
- `DOCTRINE/verification-expanded.md`
- `bin/constitution-install.sh`
- `bin/policy-constitution-install.sh`
- `bin/policy-resolve.sh`
- `policy/constitution.md`

### proposal

- `bin/proposal.sh`

### scope

- `bin/roots.sh`
- `bin/scope-layers.sh`
- `bin/scope-managed-mods.sh`
- `bin/scope-managed-retention.sh`
- `bin/scope-managed-telemetry.sh`
- `bin/scope-marker-backfill.sh`
- `bin/scope-roots.sh`
- `bin/scope.sh`
- `hooks/injection-rule/scope.test.sh`

### session

- `bin/session-autocompact.sh`
- `bin/session-check.sh`
- `bin/session-ci-watch.sh`
- `bin/session-cleanup-report.sh`
- `bin/session-cleanup.sh`
- `bin/session-notify.sh`
- `bin/session-react-lib.sh`
- `bin/session-save-now.sh`
- `bin/session-workflow-progress.sh`
- `context-rules/user/session-title-missing.md`
- `context-rules/user/session-title-missing.sh`
- `contracts/session-waiting.tsv`
- `hooks/session-state/session-state.sh`
- `hooks/session-subagent-check/session-subagent-check.sh`
- `hooks/session-title/session-title.sh`
- `hooks/session-title/session-title.test.sh`
- `hooks/session-verdicts/session-verdicts.sh`

### skill

- `bin/skill-book.sh`
- `bin/skill-catalog.sh`
- `bin/skill-collision-verify.sh`
- `bin/skill-fire.sh`
- `bin/skill-install.sh`
- `bin/skill-usage.sh`
- `bin/skills-install.sh`
- `commands/harbor-skills.md`
- `commands/skill-catalog.md`
- `context-rules/user/skill-first-use.sh`
- `context-rules/user/skill-on-first-use.md`
- `contracts/skill-book-router.tsv`
- `contracts/skill-pack-frontmatter-keys.txt`
- `docs/explanation/skill-unification.md`
- `skills/skill-book/SKILL.md`
- `skills/skill-catalog/SKILL.md`

### standard

- `bin/standard-catalog.sh`
- `bin/standard-fleet-names-run.sh`
- `bin/standard-fleet-names.sh`
- `bin/standard-frozen-generate.sh`
- `bin/standard-issue-label.sh`
- `bin/standard-rename.sh`
- `bin/standard-shape.sh`
- `bin/standard-vendor.sh`
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
- `docs/decisions/0088-hook-engine-folders.md`
- `docs/decisions/0089-event-and-manual-moments.md`
- `docs/decisions/0090-doc-kinds-follow-diataxis.md`
- `docs/decisions/0091-object-slot-open.md`
- `docs/decisions/0092-promote-name-rules-on-evidence.md`
- `docs/decisions/README.md`
- `launchd/com.harbor.standard.fleet-names.plist`
- `standards/modularity.md`
- `standards/naming.md`
- `standards/naming/aliases.tsv`
- `standards/naming/controls.tsv`
- `standards/naming/dialects.tsv`
- `standards/naming/exemptions.tsv`
- `standards/naming/frozen.tsv`
- `standards/naming/kinds.tsv`
- `standards/naming/label-axes.tsv`
- `standards/naming/registers.tsv`
- `standards/naming/renames.tsv`
- `standards/naming/repo-kinds.tsv`
- `standards/naming/surfaces.tsv`
- `standards/naming/terms.tsv`
- `standards/naming/words.tsv`
- `standards/naming/writers.tsv`
- `standards/rename-maps/fleet-modules-in-projects-orchestrator.tsv`
- `standards/rename-maps/sitting-b.md`
- `standards/rename-maps/t4-letter-ids.tsv`
- `standards/rename-maps/w1-docs.tsv`
- `standards/rename-maps/w2-tests.tsv`
- `standards/rename-maps/w3-bin.tsv`
- `standards/rename-maps/w4-path-shims.tsv`
- `standards/rename-maps/w5-state-env-launchd.tsv`
- `standards/rename-maps/w6a-admission-hooks.tsv`
- `standards/rename-maps/w6b-admission-floor-hook-and-integrity.tsv`

### status

- `bin/fleet-glyph.sh`
- `bin/fleet-snapshot-refresh.sh`
- `bin/status-console.sh`
- `bin/status-dashboard-generate.sh`
- `bin/status-fleet-glyph.sh`
- `bin/status-fleet-snapshot-refresh.sh`
- `bin/status-gen.sh`
- `bin/status-generate.sh`
- `bin/status-obligations.sh`
- `bin/status-plan-generate.sh`
- `bin/status-subagent-glyph.sh`
- `bin/status-telemetry-report.sh`
- `bin/status-usage-aggregate.sh`
- `bin/subagent-glyph.sh`
- `bin/usage-aggregate.sh`
- `launchd/com.harbor.status.fleet-snapshot.plist`
- `launchd/com.harbor.status.usage-sessions.plist`
- `launchd/com.harbor.status.usage.plist`

### test

- `bin/sandbox-make.sh`
- `bin/suite-run.sh`
- `bin/suite-select.sh`
- `bin/test-sandbox-make.sh`
- `bin/test-suite-cache.sh`
- `bin/test-suite-run.sh`
- `bin/test-suite-select.sh`
- `contracts/test-contract.md`
- `docs/audits/test-audit.md`
- `skills/test-strength/SKILL.md`

### worktree

- `bin/worktree.sh`

## Not placed

Files whose family the registry cannot name yet (`build/catalog-findings.tsv` lists each with its reason), by top folder:

| Folder | Files without a family |
|---|---|
| (repo root) | 17 |
| `.agents/` | 4 |
| `.github/` | 2 |
| `bin/` | 24 |
| `commands/` | 2 |
| `context-rules/` | 31 |
| `contracts/` | 66 |
| `docs/` | 34 |
| `fixtures/` | 222 |
| `hooks/` | 32 |
| `patches/` | 10 |
| `runners/` | 2 |
| `skills/` | 7 |
| `systemd/` | 15 |
| `tests/` | 37 |
| `tools/` | 8 |
| `vendor/` | 92 |
| `worklog/` | 1 |

## Top-level layout

Every tracked top-level entry, its kind and layer from `contracts/layout-map.tsv`; Ships is read from `contracts/layers.tsv` (core ships in harbor-core, dev is box or dev data). `bin/lint-layout-map.sh` is red on an entry with no row.

| Entry | Kind | Layer | Ships |
|---|---|---|---|
| `.agents/` | config | source | core |
| `.github/` | config | source | core |
| `contracts/` | contract | source | core |
| `evals/` | eval | source | dev |
| `bin/` | script | source | core |
| `commands/` | command | source | core |
| `context-rules/` | injection-rule | source | core |
| `docs/` | explanation | source | dev |
| `fixtures/` | fixture | source | core |
| `hooks/` | hook | source | core |
| `launchd/` | deploy-unit | source | core |
| `patches/` | vendored | source | core |
| `policy/` | policy | source | dev |
| `registries/` | record | record | dev |
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
| `LICENSE` | policy | source | core |
| `NOTICE` | policy | source | core |
| `SECURITY.md` | policy | source | core |
| `CONTRIBUTING.md` | policy | source | core |
| `README.md` | explanation | source | core |
| `trio-decoupling-epic.md` | record | record | dev |
