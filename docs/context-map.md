---
kind: context-map
status: generated
owner: harbor#996
source: sh bin/standard-catalog.sh --map
layer: generated
---
<!-- generated-by: sh bin/standard-catalog.sh --map -->

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
| policy | policy/ | system | source | living | 3 |
| standard | standards/ | system | source | versioned | 32 |
| contract | contracts/ | system | source | versioned | 47 |
| decision-record | docs/decisions/ | element | source | dated | 94 |
| hook | hooks/ | component | source | living | 50 |
| skill | skills/ | component | source | living | 58 |
| fixture | fixtures/ | element | source | living | 439 |
| template | templates/ | component | source | living | 16 |
| registry | registries/ | component | source | versioned | 82 |
| test | tests/ | component | source | living | 671 |
| report | docs/reports/ | element | report | dated | 2 |
| design | docs/design/ | component | source | living | 9 |
| context-map | docs/context-map.md | system | generated | generated | 1 |
| generated-doc | docs/generated/ | component | generated | generated | 2 |
| script | bin/ | component | source | living | 298 |
| how-to | docs/how-to/ | component | source | living | 7 |
| reference | docs/reference/ | component | generated | generated | 90 |
| explanation | docs/explanation/ | component | source | living | 106 |
| (no kind) | - | - | - | - | 288 |

## Folders

| Folder | Files | Families | Kinds |
|---|---|---|---|
| (repo root) | 12 | 1 | 1 |
| `.agents/` | 4 | 1 | 1 |
| `.github/` | 4 | 2 | 1 |
| `bin/` | 302 | 32 | 2 |
| `commands/` | 5 | 4 | 1 |
| `context-rules/` | 68 | 6 | 1 |
| `contracts/` | 128 | 15 | 2 |
| `docs/` | 324 | 26 | 9 |
| `fixtures/` | 439 | 11 | 1 |
| `hooks/` | 46 | 7 | 1 |
| `launchd/` | 22 | 10 | 1 |
| `mods/` | 7 | 1 | 2 |
| `patches/` | 17 | 4 | 1 |
| `policy/` | 3 | 1 | 1 |
| `registries/` | 1 | 1 | 1 |
| `relay/` | 4 | 1 | 1 |
| `runners/` | 2 | 1 | 1 |
| `skills/` | 58 | 10 | 1 |
| `standards/` | 32 | 1 | 1 |
| `systemd/` | 15 | 1 | 1 |
| `templates/` | 16 | 3 | 1 |
| `tests/` | 671 | 30 | 1 |
| `tools/` | 10 | 2 | 1 |
| `vendor/` | 104 | 1 | 1 |
| `worklog/` | 1 | 1 | 1 |

## Families

| Family | Subsystem | Scripts | Tests | Docs | Other files | Checks | Controls |
|---|---|---|---|---|---|---|---|
| access | control-plane | 12 | 32 | 2 | 6 | 0 | 0 |
| admission | control-plane | 27 | 90 | 0 | 6 | 0 | 176 |
| agent | control-plane | 1 | 2 | 0 | 12 | 0 | 0 |
| alert | observability | 2 | 3 | 0 | 3 | 0 | 0 |
| audit | control-plane | 9 | 15 | 0 | 17 | 0 | 2 |
| bq | observability | 3 | 6 | 0 | 2 | 0 | 0 |
| check | observability | 2 | 5 | 0 | 1 | 59 | 0 |
| ci | coordination | 17 | 46 | 2 | 20 | 1 | 7 |
| context | control-plane | 6 | 16 | 1 | 3 | 0 | 50 |
| deploy | control-plane | 16 | 31 | 1 | 4 | 0 | 7 |
| doc | control-plane | 16 | 13 | 0 | 44 | 0 | 22 |
| drift | control-plane | 8 | 10 | 0 | 11 | 4 | 14 |
| eval | control-plane | 11 | 8 | 0 | 2 | 0 | 0 |
| event | observability | 3 | 19 | 0 | 12 | 0 | 2 |
| gate | control-plane | 19 | 13 | 0 | 5 | 0 | 6 |
| housekeeping | control-plane | 1 | 1 | 0 | 3 | 0 | 0 |
| hub |  | 13 | 39 | 1 | 7 | 0 | 5 |
| library | policy-function | 11 | 0 | 0 | 0 | 0 | 0 |
| lint | control-plane | 26 | 75 | 0 | 20 | 3 | 39 |
| member | control-plane | 20 | 93 | 1 | 13 | 6 | 3 |
| memory | memory-store | 6 | 10 | 1 | 24 | 0 | 1 |
| pack | catalog | 1 | 0 | 1 | 1 | 0 | 0 |
| policy | policy-function | 3 | 4 | 3 | 137 | 0 | 7 |
| proposal | proposal-pipeline | 1 | 2 | 0 | 0 | 0 | 0 |
| scope | coordination | 14 | 22 | 0 | 1 | 0 | 5 |
| session | data-plane | 14 | 5 | 0 | 7 | 0 | 0 |
| skill | catalog | 5 | 18 | 0 | 8 | 0 | 16 |
| standard | policy-function | 18 | 29 | 126 | 16 | 14 | 61 |
| status | observability | 13 | 29 | 0 | 10 | 0 | 0 |
| test | control-plane | 4 | 5 | 2 | 8 | 0 | 15 |
| worktree | coordination | 1 | 2 | 0 | 0 | 0 | 0 |

## Per family

Scripts, hooks, docs and other files by path; tests, fixtures and eval data are counted above and not listed. A path's purpose is in `harbor find <family>`.

### access

- `bin/access-browser-agent.sh`
- `bin/access-browser-cdp.mjs`
- `bin/access-browser-flow.sh`
- `bin/access-browser-hosts-add.sh`
- `bin/access-browser.sh`
- `bin/access-chrome-mcp.py`
- `bin/access-chrome-mcp.ts`
- `bin/access-environment.sh`
- `bin/access-github-app-install.sh`
- `bin/access.sh`
- `context-rules/user/access-route-pointer.md`
- `context-rules/user/access-route.sh`
- `contracts/access-card.md`
- `contracts/access-register.md`
- `hooks/access-confinement/access-confinement.sh`
- `hooks/access-confinement/access-confinement.test.sh`
- `skills/access-browser/SKILL.md`
- `skills/access-ledger/SKILL.md`

### admission

- `bin/admission-api-route.sh`
- `bin/admission-bash.sh`
- `bin/admission-cloud.sh`
- `bin/admission-decide.sh`
- `bin/admission-decider-set.sh`
- `bin/admission-deliverables.sh`
- `bin/admission-deny-hash.sh`
- `bin/admission-deny.sh`
- `bin/admission-destroy.sh`
- `bin/admission-egress.sh`
- `bin/admission-equivalence.sh`
- `bin/admission-hook.sh`
- `bin/admission-install.sh`
- `bin/admission-integrity.sh`
- `bin/admission-mutation-tier.sh`
- `bin/admission-normalize.awk`
- `bin/admission-observe-report.sh`
- `bin/admission-observe.sh`
- `bin/admission-remove.sh`
- `bin/admission-replay.sh`
- `bin/admission-self-edit.sh`
- `bin/admission-stop.sh`
- `bin/admission-verify.sh`
- `bin/annotate-web.sh`
- `bin/govern-hook.sh`
- `bin/govern-token.sh`
- `bin/prod-guard-ambient.sh`
- `docs/explanation/admission-baseline.md`
- `docs/reference/check-rows/admission-api-route.txt`
- `docs/reference/check-rows/admission-destroy-snapshot.txt`
- `docs/reference/check-rows/admission-managed-mods.txt`
- `patches/admission-shard.patch.md`

### agent

- `bin/agent-idle-check.sh`
- `context-rules/user/agent-brief.md`
- `context-rules/user/agent-brief.sh`
- `context-rules/user/agent-model-required.md`
- `context-rules/user/agent-model.sh`
- `contracts/agent-architectures.tsv`
- `contracts/agent-tools.tsv`
- `docs/explanation/knowledge-base/agent-memory.md`
- `docs/explanation/knowledge-base/agent-no-rag.md`
- `docs/reference/agent-architectures.md`
- `docs/reference/check-rows/agent-idle.txt`
- `launchd/com.harbor.agent.idle.plist`
- `skills/agent-routing/SKILL.md`

### alert

- `bin/alert-notify.sh`
- `bin/alert-probe.sh`
- `docs/reference/check-rows/alert-probe.txt`
- `docs/src/alert.html`
- `launchd/com.harbor.alert.probe.plist`

### audit

- `bin/audit-collector-check.sh`
- `bin/audit-collector-install.sh`
- `bin/audit-collector.sh`
- `bin/audit-otlp-receiver.py`
- `bin/audit-review-config.sh`
- `bin/audit-stream-export.py`
- `bin/audit-stream-lib.sh`
- `bin/audit-triage-run.sh`
- `bin/audit-triage.sh`
- `docs/reference/check-rows/audit-collector-checkpoint.txt`
- `docs/reference/check-rows/audit-collector-health.txt`
- `docs/reference/check-rows/audit-collector.txt`
- `docs/reference/check-rows/audit-otlp-receiver.txt`
- `docs/reference/check-rows/audit-triage.txt`
- `launchd/com.harbor.audit.collector-checkpoint.plist`
- `launchd/com.harbor.audit.collector.plist`
- `launchd/com.harbor.audit.otlp-receiver.plist`
- `launchd/com.harbor.audit.triage.plist`
- `skills/audit-claims/SKILL.md`
- `skills/audit-review-fanout/SKILL.md`

### bq

- `bin/bq-format.sh`
- `bin/bq-load.sh`
- `bin/bq-logs.sh`
- `contracts/bq-schema.tsv`
- `contracts/bq-values.tsv`

### check

- `bin/check-registry-generate.sh`
- `bin/check-run.sh`
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
- `context-rules/user/ci-wait-on-the-bus.md`
- `context-rules/user/ci-wait-on-the-bus.sh`
- `docs/design/ci-local-heal.md`
- `docs/design/ci-tests-on-this-host.md`
- `docs/reference/check-rows/ci-fleet-contract-freshness.txt`
- `docs/reference/check-rows/ci-fleet-scheduled.txt`
- `docs/reference/check-rows/ci-github-plan.txt`
- `docs/reference/check-rows/ci-governor.txt`
- `docs/reference/check-rows/ci-lost-rerun.txt`
- `docs/reference/check-rows/ci-main-tip-verdict.txt`
- `docs/reference/check-rows/ci-queue.txt`
- `docs/reference/check-rows/ci-release-names.txt`
- `docs/reference/check-rows/ci-runner-alarm.txt`
- `docs/reference/check-rows/ci-runner-switch-org.txt`
- `docs/reference/check-rows/ci-runner-switch.txt`
- `docs/reference/check-rows/ci-runners.txt`
- `docs/reference/check-rows/ci-scaffolder-nightly.txt`
- `docs/reference/check-rows/ci-scaffolder-third-party-updates.txt`
- `launchd/com.harbor.ci.governor.plist`
- `launchd/com.harbor.ci.release-names.plist`

### context

- `bin/context-budget.sh`
- `bin/context-compaction-digest.sh`
- `bin/context-injection-install.sh`
- `bin/context-peers.sh`
- `bin/context-resolve.sh`
- `commands/context-budget.md`
- `docs/context-map.md`
- `hooks/injection-rule/context-rules.test.sh`
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
- `bin/deploy-launchd-sync.sh`
- `bin/deploy-live-verify.sh`
- `bin/deploy-push.sh`
- `bin/deploy-restore.sh`
- `bin/deploy-runtime-install.sh`
- `bin/deploy-shim-install.sh`
- `bin/deploy.sh`
- `docs/design/deploy-fleet.md`
- `docs/reference/check-rows/deploy-fleet.txt`
- `docs/reference/check-rows/deploy-launchd.txt`
- `docs/reference/check-rows/deploy-live-verify.txt`

### doc

- `bin/doc-checks-generate.sh`
- `bin/doc-cite-verify.sh`
- `bin/doc-cited-paths.awk`
- `bin/doc-drive-push.sh`
- `bin/doc-fresh-verify.sh`
- `bin/doc-freshness.sh`
- `bin/doc-graph-generate.sh`
- `bin/doc-index-generate.sh`
- `bin/doc-isa-index.sh`
- `bin/doc-refs.sh`
- `bin/doc-register-index.sh`
- `bin/doc-report-verify.sh`
- `bin/doc-shape.sh`
- `bin/doc-vale.sh`
- `bin/doc-visual-check.mjs`
- `bin/doc-visual-check.sh`
- `contracts/doc-folders.tsv`
- `docs/explanation/doc-truth.md`
- `patches/doc-generate-check.patch.md`
- `skills/doc-atlas/SKILL.md`
- `skills/doc-deliverable-contract/SKILL.md`
- `skills/doc-knowledge-base/SKILL.md`
- `skills/doc-learning-artifact/SKILL.md`
- `skills/doc-workshop-deck/SKILL.md`

### drift

- `bin/drift-confinement.sh`
- `bin/drift-install.sh`
- `bin/drift-launchd-wall.sh`
- `bin/drift-port-root.sh`
- `bin/drift-reference-check.sh`
- `bin/drift-renew-check.sh`
- `bin/drift-status.sh`
- `bin/drift-wall.sh`
- `docs/reference/check-rows/drift-confinement.txt`
- `docs/reference/check-rows/drift-launchd-wall.txt`
- `docs/reference/check-rows/drift-port-root.txt`
- `docs/reference/check-rows/drift-reference-check.txt`
- `docs/reference/check-rows/drift-renew-check.txt`
- `docs/reference/check-rows/drift-repo-visibility.txt`
- `docs/reference/check-rows/drift-wall.txt`

### eval

- `bin/eval-git-verbs-probe.sh`
- `bin/eval-hook-latency.sh`
- `bin/eval-hook-replay.sh`
- `bin/eval-pass-score.sh`
- `bin/eval-redteam-corpus-run.sh`
- `bin/eval-redteam-corpus.sh`
- `bin/eval-replay-corpus.sh`
- `bin/eval-replay-worker.sh`
- `bin/eval-replay.sh`
- `bin/eval-suggest-replay.sh`
- `bin/eval-tally.sh`
- `docs/reference/check-rows/eval-redteam-corpus.txt`
- `launchd/com.harbor.eval.redteam-corpus.plist`

### event

- `bin/event-bus.sh`
- `bin/event-dispatch.sh`
- `bin/event-hook.sh`
- `contracts/event-kinds.tsv`
- `contracts/event-rules.tsv`
- `docs/reference/check-rows/event-alerting.txt`
- `docs/reference/check-rows/event-dispatch.txt`
- `docs/reference/check-rows/event-fleet-snapshot.txt`
- `docs/reference/check-rows/event-retention.txt`
- `docs/reference/check-rows/event-session-check.txt`
- `docs/reference/check-rows/event-session-ci-watch.txt`
- `docs/reference/check-rows/event-session-cleanup-report.txt`
- `docs/reference/check-rows/event-session-notify.txt`
- `docs/reference/check-rows/event-session-save-now.txt`
- `launchd/com.harbor.event.dispatch.plist`

### gate

- `bin/gate-approve.sh`
- `bin/gate-classify.sh`
- `bin/gate-codeowners.sh`
- `bin/gate-merge-check.sh`
- `bin/gate-merge-stack-resolve.py`
- `bin/gate-merge-stack.sh`
- `bin/gate-merge.sh`
- `bin/gate-merged-check.sh`
- `bin/gate-pr-plan.sh`
- `bin/gate-pr-wait.sh`
- `bin/gate-push.sh`
- `bin/gate-queue.sh`
- `bin/gate-register-derive.sh`
- `bin/gate-repo-drift.sh`
- `bin/gate-required-generate.sh`
- `bin/gate-verbs.sh`
- `commands/gate-merge.md`
- `docs/reference/check-rows/gate-approve.txt`
- `docs/reference/check-rows/gate-merge-backstop.txt`
- `docs/reference/check-rows/gate-repo-drift.txt`
- `hooks/commit-msg`
- `hooks/pre-commit`
- `hooks/pre-push`
- `launchd/com.harbor.gate.repo-drift.plist`

### housekeeping

- `bin/housekeeping-clean.sh`
- `docs/reference/check-rows/housekeeping-clean.txt`
- `skills/housekeeping/SKILL.md`

### hub

- `bin/hub-approval.sh`
- `bin/hub-board.sh`
- `bin/hub-digest.sh`
- `bin/hub-events.sh`
- `bin/hub-fetch.sh`
- `bin/hub-format.sh`
- `bin/hub-gate.sh`
- `bin/hub-pin-upgrade.sh`
- `bin/hub-support.sh`
- `bin/hub-sync.sh`
- `bin/hub-tier.sh`
- `bin/hub-tools.sh`
- `bin/hub.sh`
- `contracts/hub-vocabulary.tsv`
- `contracts/hub.md`
- `docs/how-to/hub-admin.md`
- `patches/hub/hub-bq-load.patch.md`
- `patches/hub/hub-digest.patch.md`
- `patches/hub/hub-gates.patch.md`
- `patches/hub/hub-silent.patch.md`
- `patches/hub/hub-watchdog.patch.md`

### library

- `bin/library-admission.sh`
- `bin/library-alert.sh`
- `bin/library-board.sh`
- `bin/library-bq.sh`
- `bin/library-fs.sh`
- `bin/library-gate.sh`
- `bin/library-git-safe.sh`
- `bin/library-hub.sh`
- `bin/library-log.sh`
- `bin/library-pack-version.sh`
- `bin/library-repo-rules.sh`

### lint

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
- `bin/lint-name-ratchet.sh`
- `bin/lint-name.sh`
- `bin/lint-platform.sh`
- `bin/lint-port-paths.sh`
- `bin/lint-pr.sh`
- `bin/lint-renderer.sh`
- `bin/lint-rule-health.sh`
- `bin/lint-secrets.sh`
- `bin/lint-share.sh`
- `bin/lint-siblings.sh`
- `bin/lint-suggest-table.sh`
- `contracts/lint-core-writes-baseline.txt`
- `contracts/lint-dev-paths-baseline.txt`
- `contracts/lint-domain-baseline.txt`
- `contracts/lint-domain-repos-baseline.txt`
- `contracts/lint-leaks-baseline.txt`
- `contracts/lint-name-baseline.txt`
- `contracts/lint-secrets-baseline.txt`
- `contracts/lint-siblings-baseline.txt`
- `docs/reference/check-rows/lint-credential-reads.txt`
- `docs/reference/check-rows/lint-findings.txt`
- `docs/reference/check-rows/lint-leaks.txt`
- `docs/reference/check-rows/lint-name-ratchet.txt`
- `docs/reference/check-rows/lint-port-paths.txt`
- `docs/reference/check-rows/lint-pr-body-shape.txt`
- `docs/reference/check-rows/lint-pr-issue-link.txt`
- `docs/reference/check-rows/lint-pr-no-ai-attribution.txt`
- `docs/reference/check-rows/lint-rule-health.txt`
- `launchd/com.harbor.lint.findings.plist`
- `launchd/com.harbor.lint.rule-health.plist`

### member

- `bin/member-bootstrap.sh`
- `bin/member-connectors.sh`
- `bin/member-dispatch.sh`
- `bin/member-install.sh`
- `bin/member-integrity.sh`
- `bin/member-managed.sh`
- `bin/member-mcp-launch.sh`
- `bin/member-memory.sh`
- `bin/member-post.sh`
- `bin/member-prereqs.sh`
- `bin/member-session.sh`
- `bin/member-setup-generate.sh`
- `bin/member-standard.sh`
- `bin/member-support-guard.sh`
- `bin/member-support.sh`
- `bin/member-tests.sh`
- `bin/member-tools.sh`
- `bin/member-update.sh`
- `bin/member-upgrade.sh`
- `bin/member-windows.sh`
- `contracts/member-context-rules.tsv`
- `contracts/member-files.txt`
- `contracts/member-guards.tsv`
- `contracts/member-hosts.txt`
- `contracts/member-law.md`
- `contracts/member-prereqs.txt`
- `docs/how-to/member-install.md`
- `docs/how-to/member-support.md`
- `docs/reference/check-rows/member-standard.txt`
- `skills/member-setup/SKILL.md`
- `templates/member-project/member-agents.md.tmpl`
- `templates/member-project/member-claude.md.tmpl`
- `templates/member/member-update.service`
- `templates/member/member-update.timer`

### memory

- `bin/memory-lint.sh`
- `bin/memory-log-token-save.sh`
- `bin/memory-route.sh`
- `bin/memory-store-check.sh`
- `bin/memory.sh`
- `contracts/memory-format.md`
- `docs/reference/check-rows/memory-route.txt`
- `hooks/memory-harvest/memory-harvest.sh`
- `tools/memory/memory-engine.test.ts`
- `tools/memory/memory-engine.ts`

### pack

- `bin/pack.sh`
- `contracts/pack-frontmatter-keys.txt`
- `contracts/pack.md`

### policy

- `bin/policy-check.sh`
- `bin/policy-constitution-install.sh`
- `bin/policy-resolve.sh`
- `docs/reference/check-rows/policy-enforcement-report.txt`
- `policy/clauses.tsv`
- `policy/constitution.md`
- `policy/enforcement.tsv`
- `templates/hub/policy.json`

### proposal

- `bin/proposal.sh`

### scope

- `bin/scope-layers.sh`
- `bin/scope-managed-folders.sh`
- `bin/scope-managed-mods.sh`
- `bin/scope-managed-retention.sh`
- `bin/scope-managed-telemetry.sh`
- `bin/scope-marker-backfill.sh`
- `bin/scope-repo-rename.sh`
- `bin/scope-repo-sources.sh`
- `bin/scope-repo.sh`
- `bin/scope-repos-generate.sh`
- `bin/scope-roots.sh`
- `bin/scope-system.sh`
- `bin/scope.sh`
- `docs/reference/check-rows/scope-repos-generated.txt`
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
- `docs/reference/check-rows/session-reply-shape.txt`
- `docs/reference/check-rows/session-state.txt`
- `docs/reference/check-rows/session-subagent-stop.txt`
- `docs/reference/check-rows/session-title.txt`
- `hooks/session-state/session-state.sh`
- `hooks/session-subagent-check/session-subagent-check.sh`
- `hooks/session-title/session-title.sh`
- `hooks/session-title/session-title.test.sh`
- `hooks/session-verdicts/session-verdicts.sh`

### skill

- `bin/skill-catalog.sh`
- `bin/skill-collision-verify.sh`
- `bin/skill-fire.sh`
- `bin/skill-install.sh`
- `bin/skill-usage.sh`
- `commands/skill-catalog.md`
- `context-rules/user/skill-first-use.sh`
- `context-rules/user/skill-on-first-use.md`
- `contracts/skill-book-router.tsv`
- `contracts/skill-pack-frontmatter-keys.txt`
- `docs/explanation/skill-unification.md`
- `skills/skill-catalog/SKILL.md`

### standard

- `bin/standard-catalog.sh`
- `bin/standard-decision-migrate.sh`
- `bin/standard-fleet-names-run.sh`
- `bin/standard-fleet-names.sh`
- `bin/standard-frozen-generate.sh`
- `bin/standard-id-resolve.sh`
- `bin/standard-inventory.sh`
- `bin/standard-issue-label.sh`
- `bin/standard-kit.sh`
- `bin/standard-label-sync.sh`
- `bin/standard-register.sh`
- `bin/standard-rename.sh`
- `bin/standard-render-check.sh`
- `bin/standard-schema.sh`
- `bin/standard-seams-fresh.sh`
- `bin/standard-shape.sh`
- `bin/standard-vendor-scaffolder.sh`
- `bin/standard-vendor.sh`
- `contracts/standard-coverage.tsv`
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
- `docs/decisions/0093-knowledge-base-standard.md`
- `docs/decisions/README.md`
- `docs/reference/check-rows/standard-coverage.txt`
- `docs/reference/check-rows/standard-fleet-names.txt`
- `docs/reference/check-rows/standard-label-registered.txt`
- `docs/reference/check-rows/standard-label-sync.txt`
- `docs/reference/check-rows/standard-repo-verbs.txt`
- `docs/reference/check-rows/standard-schedule-registered.txt`
- `docs/reference/check-rows/standard-script-uncalled.txt`
- `docs/reference/check-rows/standard-seam-fresh.txt`
- `docs/reference/check-rows/standard-vendor-scaffolder-fresh.txt`
- `launchd/com.harbor.standard.coverage.plist`
- `launchd/com.harbor.standard.fleet-names.plist`
- `launchd/com.harbor.standard.label-registered.plist`
- `launchd/com.harbor.standard.schedule-registered.plist`
- `launchd/com.harbor.standard.script-uncalled.plist`
- `launchd/com.harbor.standard.seam-fresh.plist`
- `standards/knowledge-base.md`
- `standards/modularity.md`
- `standards/naming.md`
- `standards/naming/aliases.tsv`
- `standards/naming/controls.tsv`
- `standards/naming/dialects.tsv`
- `standards/naming/exemptions.tsv`
- `standards/naming/frozen.tsv`
- `standards/naming/kinds.tsv`
- `standards/naming/kit.tsv`
- `standards/naming/label-axes.tsv`
- `standards/naming/label-retired.tsv`
- `standards/naming/registers.tsv`
- `standards/naming/renames.tsv`
- `standards/naming/repo-kinds.tsv`
- `standards/naming/schemas.tsv`
- `standards/naming/surfaces.tsv`
- `standards/naming/terms.tsv`
- `standards/naming/verbs.tsv`
- `standards/naming/versions.tsv`
- `standards/naming/words.tsv`
- `standards/naming/writers.tsv`
- `standards/rename-maps/fleet-modules-in-fleet.tsv`
- `standards/rename-maps/sitting-b.md`
- `standards/rename-maps/t4-letter-ids.tsv`
- `standards/rename-maps/w1-docs.tsv`
- `standards/rename-maps/w2-tests.tsv`
- `standards/rename-maps/w3-bin.tsv`
- `standards/rename-maps/w4-path-shims.tsv`
- `standards/rename-maps/w5-state-env-launchd.tsv`
- `standards/rename-maps/w6a-admission-hooks.tsv`
- `standards/rename-maps/w6b-admission-hook-and-integrity.tsv`

### status

- `bin/status-console.sh`
- `bin/status-dashboard-generate.sh`
- `bin/status-fleet-glyph.sh`
- `bin/status-fleet-snapshot-refresh.sh`
- `bin/status-fleet-watch.sh`
- `bin/status-generate.sh`
- `bin/status-obligations.sh`
- `bin/status-plan-generate.sh`
- `bin/status-subagent-glyph.sh`
- `bin/status-suggest-scan.sh`
- `bin/status-suggest.sh`
- `bin/status-telemetry-report.sh`
- `bin/status-usage-aggregate.sh`
- `docs/reference/check-rows/status-fleet-snapshot.txt`
- `docs/reference/check-rows/status-fleet-watch.txt`
- `docs/reference/check-rows/status-obligations.txt`
- `docs/reference/check-rows/status-usage-sessions.txt`
- `docs/reference/check-rows/status-usage.txt`
- `launchd/com.harbor.status.fleet-snapshot.plist`
- `launchd/com.harbor.status.usage-sessions.plist`
- `launchd/com.harbor.status.usage.plist`
- `skills/status-suggest-scan/SKILL.md`

### test

- `bin/test-sandbox-make.sh`
- `bin/test-suite-cache.sh`
- `bin/test-suite-run.sh`
- `bin/test-suite-select.sh`
- `contracts/test-contract.md`
- `docs/audits/test-audit.md`
- `docs/reference/check-rows/test-fleet.txt`
- `skills/test-strength/SKILL.md`

### worktree

- `bin/worktree.sh`

## Not placed

Files whose family the registry cannot name yet (`build/catalog-findings.tsv` lists each with its reason), by top folder:

| Folder | Files without a family |
|---|---|
| (repo root) | 12 |
| `.agents/` | 4 |
| `.github/` | 2 |
| `bin/` | 12 |
| `commands/` | 2 |
| `context-rules/` | 56 |
| `contracts/` | 95 |
| `docs/` | 134 |
| `fixtures/` | 264 |
| `hooks/` | 33 |
| `mods/` | 7 |
| `patches/` | 10 |
| `relay/` | 4 |
| `runners/` | 2 |
| `skills/` | 1 |
| `systemd/` | 15 |
| `templates/` | 11 |
| `tests/` | 28 |
| `tools/` | 8 |
| `vendor/` | 104 |
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
| `mods/` | code | source | core |
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
| `.shellcheckrc` | config | source | core |
| `justfile` | config | source | core |
| `AGENTS.md` | policy | source | core |
| `CLAUDE.md` | policy | source | core |
| `LICENSE` | policy | source | core |
| `NOTICE` | policy | source | core |
| `SECURITY.md` | policy | source | core |
| `CONTRIBUTING.md` | policy | source | core |
| `README.md` | explanation | source | core |
| `CHANGELOG.md` | record | source | core |
| `trio-decoupling-epic.md` | record | record | dev |
| `templates/` | template | source | core |
| `relay/` | deploy-unit | source | core |
