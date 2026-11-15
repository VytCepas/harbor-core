---
kind: design
owner: @VytCepas
status: unreviewed
---

# Narrowing `bin/*` in `contracts/suite-paths.txt` (harbor#150)

Why: 99 of the suites a one-file `bin/` change selected matched only because their
declaration carried the broad `bin/*` glob. A change to `bin/access-chrome-mcp.ts` alone
selected 126 suites (99 by declaration, 27 declared always) and chrome PRs ran ~25 min.

## Method (a suite is narrowed only when all five hold)

1. **Static trace.** Start at the suite file and follow every non-comment reference to a
   script by name or path (`. x`, `sh x`, `bun x`, `"$BIN/x"`, `cp bin/x`, an assignment
   that aliases a path) through the test's helpers (`tests/lib`, `fixture.sh`, stubs) and
   then through each bin script it reaches. Inside bin/ and hooks/ a mention counts only
   in command or alias position, not inside a message string, a comment or a `[ -f ]`
   probe; in tests every mention counts. A file that is only read (`sed`, `grep`, `cat`)
   is a leaf: listed, not followed.
2. **Tree readers stop the trace.** A suite whose trace reaches a script that reads the
   whole tree, or dispatches by a variable name, keeps `bin/*`: `lint-conventions.sh`,
   `lint-name.sh`, `harbor` (verb dispatch), `scope-system.sh`, `deploy-runtime-install.sh`,
   `member-install.sh`, `member-update.sh`, `drift-install.sh`, `standard-inventory.sh`,
   `standard-register.sh`, `standard-shape.sh`, `test-sandbox-make.sh`,
   `gate-register-derive.sh`, the format script that greps `check=` out of every bin script, `doc-index-generate.sh`,
   `standard-frozen-generate.sh`. A suite that itself scans bin/ (`registry.test.sh`,
   `mktemp-template.test.sh`) or builds its subjects at run time (`deny-hash.test.sh`,
   named in the header of `suite-paths.txt`) keeps it too.
3. **Sabotage run.** In a scratch copy, every bin/ file outside the traced set was replaced
   by a stub that exits 97, and the suite ran. It must pass with the same count as the
   unmodified copy. The method can go red: stubbing a traced file (`status-subagent-glyph.sh`,
   `admission-normalize.awk`) turned subagent 58/58 into 6 passed 52 failed and normalize
   204/204 into 7 passed 197 failed.
4. **Red proof on the selector.** With a traced file broken, the narrowed suite is still
   selected (`sh bin/test-suite-select.sh <suite>` exits 0) and goes red.

5. **A sharded suite narrows as one.** Every part of a suite split into parts must carry the
   main part's `suite-paths.txt` line (`tests/admission/baseline/shards.test.sh`), so a part
   is narrowed only together with all the others. `confinement.test.sh` traced clean but is a
   part of the baseline suite, and narrowing it alone turned hosted CI red on harbor#1536.

The trace is a static approximation: it cannot see a script run through a variable built
at run time, which is why rule 2 and the sabotage run exist. Over-selection stays the safe
direction (rule 1 of the header).

## Narrowed suites (traced bin/ files; counts: unmodified / every other bin file stubbed)

- `tests/admission/normalize/normalize.test.sh` — admission-normalize.awk; 204 / 204
- `tests/status/statusline/statusline.test.sh` — status-fleet-glyph.sh; 61 / 61
- `tests/status/statusline/machine.test.sh` — status-fleet-glyph.sh; 94 / 94
- `tests/status/statusline/subagent.test.sh` — status-fleet-glyph.sh, status-subagent-glyph.sh; 58 / 58
- `tests/status/statusline/row2.test.sh` — status-fleet-glyph.sh and the ci-runners / ci-governor family it renders, access.sh, secret, library-hub.sh, scope-roots.sh, event-bus.sh; 208 / 208
- `tests/gate/merge-check/merge-check.test.sh` — gate-merge-check.sh, gate-required-generate.sh, ci-lost-job.sh, policy-check.sh (reads `*.tsv`, not bin/), library-log.sh; 157 / 157
- `tests/drift/reference-check/skills.test.sh` — drift-reference-check.sh, doc-graph-generate.sh, doc-cited-paths.awk, access.sh, secret, library-hub.sh/fs/log, scope-roots.sh; runs on fixture trees; 44 / 44
- `hooks/failure-observe/failure-observe.test.sh` — library-admission.sh and what it sources (admission-decide, admission-normalize.awk, event-bus, memory, status-suggest), admission-observe.sh; 45 / 45
- `tests/admission/api-route/api-route.test.sh` — admission-api-route.sh plus the same library-admission set; 78 / 78
- `tests/context/peers/peers.test.sh` — context-peers.sh plus the same library-admission set; 35 / 35
- `tests/scope/marker/marker.test.sh` — scope-roots.sh, library-admission.sh set, access.sh, secret, library-hub.sh; 54 / 54
- `tests/memory/memory/memory.test.sh` — memory.sh, memory-lint.sh, library-admission.sh set, scope-roots.sh, access.sh, secret; 86 / 86
- `tests/audit/telemetry/e2e.test.sh` — admission-observe.sh, audit-collector(-check).sh, audit-otlp-receiver.py, audit-stream-export.py, audit-stream-lib.sh, status-telemetry-report.sh, library-admission.sh set; 28 / 28

## Not narrowed, and why

The other 86 suites still select on any bin/ change. Their trace reaches a tree reader
(rule 2) through a real chain: a fixture that runs `lint-conventions.sh` against `$T_ROOT`
(`tests/checks/lint-fixture.sh`), `hub.sh` -> `scope-repo.sh` -> `lint-conventions.sh`,
`library-admission.sh` -> `member-dispatch.sh` -> `deploy-harden.sh` -> `deploy.sh` ->
`deploy-runtime-install.sh`, and shared `fixture.sh` files that source them. Narrowing
those needs a different mechanism (a per-path exclusion the selector understands), not a
longer list here. `tests/access/chrome/mcp.test.sh` is one of them: it calls
`lint-name.sh --check`, and that script also lists the tracked files (`git ls-files`),
so it is a tree reader until someone proves the `--check` path does not.
