---
kind: decision-record
status: accepted
alias: D-88
date: 2026-10-23
source: harbor#1272
---

# A hook engine is a folder named after it

Naming-standard decision D-88. Revises D-11, D-40 and D-58 for one kind; their content holds everywhere else.

## Context

- Operator decision, 2026-10-23 (harbor#1272 step 3, recorded on the issue the same day).
- Hooks are scattered: one hook is an entry point in `bin/`, a test in `tests/hooks/`, a note in `inject.d/`, a
  `settings.json` line written at deploy and a register row. Adding one touches about 9 files outside any one place.
- The structure reflection (2026-10-16) set the grain: the engine, not the control. 350 controls run on 13 engines.
- Source: harbor#1272; the pilot's rows are `rename-0001` to `rename-0023` in `standards/naming/renames.tsv`.

## Decision

**A non-floor hook engine is a folder, `hooks/<engine>/`, holding `<engine>.sh`, its tests and its manifest.**
The file is named after its folder: the one place a nested namespace repeats its grouping (revises D-58's
flat-surface rule for this kind). `bin/` stays flat for every other script (revises D-11 for this kind).
The floor's hooks stay where they are, pinned by hand in their three places.

**A component folder carries a tracked `README.md`**: seven sections generated from the manifest, one
hand-written why. A stranger reads it on GitHub, where the generator cannot run, so it is tracked beside the
component rather than under `docs/generated/` (revises D-40's location for this kind). A check fails on a
component folder with no README.

## Consequences

- Adding a hook is measured: files touched outside the engine's folder, 9 today, target at most 1. The pilot
  fails if the renderer needs a per-hook exception, a six-task cold-agent navigation test does not halve tool
  calls, or an upgrade from the previous tag leaves a dangling command (harbor#1272).
- Nothing moves before the protected-path rows for the manifests and `controls.tsv` (harbor#1272 step 4).
