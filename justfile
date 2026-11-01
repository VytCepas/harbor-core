# justfile — the hand-run command surface (S4/harbor#140).
#
# WHAT THIS IS FOR. Harbor had no way to answer "what can I run here" except
# reading bin/ script by script — the count is in docs/generated/status.md and it moves.
# `harbor --help` answers it for the 14 frozen verbs; this answers it for
# everything an operator actually types, verbs included, in one call.
#
# THIN WRAPPERS, NEVER LOGIC. Every recipe is one line delegating to a script
# that already exists. A recipe that grew a conditional would be a second
# implementation of a gate, in the one file nothing tests.
#
# NOT A SECOND VERB TABLE. contracts/cli.md is frozen and lint CLI1 keeps
# bin/harbor equal to it; this file deliberately does NOT re-list the verbs with
# their descriptions, because that copy would drift while reading perfectly (T2).
# It delegates to `harbor` and lets the dispatcher print its own table.
#
# `just` IS NOT A HARBOR DEPENDENCY. Nothing in CI, no hook and no script calls
# it — deploy-doctor.sh probes what Harbor needs to RUN, and this is a convenience for
# a person at a terminal. If `just` is absent, every line below still works when
# typed by hand, which is the property that keeps this file from becoming load
# bearing. Lint S5 asserts each path it names resolves.

_default:
    @just --list --unsorted

# ── the frozen verb surface ─────────────────────────────────────────────────

[doc("the harbor dispatcher's own table — status, verify, lint, install, …")]
harbor *ARGS:
    sh bin/harbor {{ ARGS }}

# ── what a session runs most ────────────────────────────────────────────────

[doc("install everything onto THIS box — dry run: preflight + every installer's plan")]
deploy:
    sh bin/deploy.sh --live

[doc("the same, writing: one [y/N], snapshot, install, verify, then YOUR re-pin [y/N]")]
deploy-apply:
    sh bin/deploy.sh --apply --live

[doc("the conventions gate; also the pre-commit hook")]
lint:
    sh bin/lint-conventions.sh

[doc("is the floor actually ON? fires known-blocked shapes at the live config")]
verify:
    sh bin/admission-verify.sh --live

[doc("the generated counts; --apply to rewrite docs/generated/status.md after a change")]
status *ARGS:
    sh bin/status-generate.sh {{ ARGS }}

[doc("build docs/index.html (not committed); --check to only prove it builds")]
docs *ARGS:
    sh bin/doc-index-generate.sh {{ ARGS }}

[doc("external dependencies, each row naming what breaks without it")]
doctor:
    sh bin/deploy-doctor.sh

# ── the always-on context surface (harbor#183/#184, CX1) ────────────────────

[doc("what Harbor costs in EVERY session, against its ceiling")]
budget:
    sh bin/context-budget.sh

[doc("size and age over the memory store; --strict to fail on an over-budget index")]
store *ARGS:
    sh bin/memory-store-check.sh {{ ARGS }}

[doc("link rot in the memory store — dangling, dead paths, slug collisions")]
memory-lint *ARGS:
    sh bin/memory-lint.sh {{ ARGS }}

[doc("skills with no invocation in the window: SILENT ones pay bytes, DORMANT ones cost nothing")]
skills-unused:
    sh bin/skill-usage.sh --unused

# ── suites ──────────────────────────────────────────────────────────────────

[doc("the floor suite, every part — guards, mutation pass, wiring assertions")]
test-floor:
    for f in tests/admission/baseline/*.test.sh; do sh "$f" || exit 1; done

[doc("every suite in contracts/suites.txt, or the ones named (`just test cu`), then `harbor: N passed, M failed`")]
test *SUITES:
    sh tests/lib/run.sh {{ SUITES }}

[doc("the same as `just test`: every suite in contracts/suites.txt, in manifest order")]
test-all:
    sh tests/lib/run.sh

[doc("what is safe to delete on this box, and what only LOOKS safe; --apply to act")]
clean *ARGS:
    sh bin/housekeeping-clean.sh {{ ARGS }}

# ── which suites does a change select? (CI-2, harbor#150) ───────────────────

[doc("which suites a changeset selects, e.g. `just select bin/memory-store-check.sh`")]
select *PATHS:
    sh bin/test-suite-select.sh {{ PATHS }}

# ── worktrees for concurrent sessions (CI-4, harbor#150) ────────────────────

[doc("session worktrees: create / retire / gc")]
worktree *ARGS:
    sh bin/worktree.sh {{ ARGS }}

[doc("refuse to merge a PR with no green verdict on its head SHA")]
merge-check *ARGS:
    sh bin/gate-merge-check.sh {{ ARGS }}
