# Test contract — the rules every governed repo's tests follow

**Seam:** shared canonical — Harbor, `project-init`, `projects-orchestrator`, and every repo
`project-init` scaffolds. **Status: written 2026-09-28 (harbor#734, epic harbor#733).** Each rule
names the mechanism that fails when the rule is broken, per implementation. Where no mechanism
exists yet, the rule says so and names the ticket, so no one reads it as checked.

**The decision (harbor#733): unify the contract, not the harness code.** Harbor's suites run on
[tests/lib/core.sh](../tests/lib/core.sh) in POSIX sh; the Python repos run pytest. Porting either
harness into the other language makes both worse and breaks the language-by-layer rule. What is
shared is these rules, one entry point — `just test` — and one summary line a fleet runner can add up.

## Two tiers

- **Hermetic** — "is the code correct". Every test in every suite, CI included. Rules 1 to 5.
- **Live** — "does the installed box work". A separate, read-only command the operator types.
  Rule 6. A clean environment alone cannot answer it, and a hermetic suite must never try.

## The rules

1. **Hermetic by default.** Every test runs with HOME, the config dir (`CLAUDE_CONFIG_DIR`, and
   the XDG dirs where the language reads them) and TMPDIR inside a throwaway directory, so no
   test reads or writes the operator's real home, and a verdict never depends on who ran it.
   - *Harbor:* `t_init` in [core.sh](../tests/lib/core.sh) points HOME, `CLAUDE_CONFIG_DIR` and
     TMPDIR into a fresh temp dir and clears the floor's `HELM_*` knobs, plus (harbor#824) the
     `GIT_*` vars a git hook exports — see the rule below. Checked by
     [lib-test.sh](../tests/lib/lib-test.sh).
   - *Python:* an autouse fixture in the root `conftest.py` that `project-init` scaffolds
     (project-init#1044) points HOME, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`,
     `XDG_STATE_HOME`, `CLAUDE_CONFIG_DIR` and TMPDIR at the test's `tmp_path`. Toolchain caches
     (uv, cargo, rustup, go, bun) keep their real locations: they are content, not configuration,
     and a cold cache turns every `uv run` into a download. Checked by project-init's
     `tests/contracts/test_test_contract.py`, which scaffolds a repo, plants a test asserting
     `Path.home()` is not the real home, and runs it.
   - *Known class — an inherited knob:* a suite that reads a `HARBOR_*` variable its caller
     exported. CI's `HARBOR_SUITE_COUNTS` changed what `floor.status-test` counted, so the
     environment decided the verdict. Clearing every inherited `HARBOR_*` in `t_init`, and the
     check that finds a suite the clearing cannot reach, are harbor#773's.
   - **A test never writes outside its own sandbox — including into a repo it merely reads
     alongside its own.** `git` exports `GIT_DIR` into every hook it fires (and
     `GIT_WORK_TREE`/`GIT_INDEX_FILE` from a linked worktree). `GIT_DIR` wins over an unrelated
     `-C <dir>` for every ref-touching operation, so a suite that builds its own scratch git repo
     in its sandbox and drives it with `git -C "$T_TMP/…"`, expecting isolation, instead acts on
     whatever repo the *caller's* `GIT_DIR` names if the harness does not clear it first —
     project-init#1065: synthetic commits landed on the pushed branch, local `main` moved, and
     `core.bare=true`/`user.name=t` were written to the shared config. *Harbor:* `t_init` clears
     `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_OBJECT_DIRECTORY`,
     `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_QUARANTINE_PATH` and `GIT_PREFIX` alongside the
     `HELM_*`/`HARBOR_*` knobs above, and `hooks/pre-push` and `hooks/pre-commit` additionally run
     every suite, the linter and the floor smoke through `hook_scrub_run` ([hooks/lib.sh](../hooks/lib.sh)),
     which drops the same vars around that one dispatch — never around the hook's own git calls,
     which need the real `GIT_DIR` to see the repo the hook fired in. Checked by
     [hooks-env-test.sh](../tests/ci/hooks-env-test.sh) (harbor#824), which reproduces the hazard
     with two real git repos, then fires the actual hook scripts end-to-end and asserts the
     suites they run never see the vars.

2. **Exact exit codes.** A test asserts the code it expects, never "non-zero": a crash, a usage
   error and a refusal are different answers, and "non-zero" passes all three.
   - *Harbor:* `t_exit <label> <code> <cmd>` takes the code, and [core.sh](../tests/lib/core.sh)
     has no "non-zero" assertion to reach for.
   - *Python:* `just test` exits with pytest's own code, unchanged: 0 all passed, 1 a test
     failed, 2 interrupted, 5 nothing collected. Checked by project-init's
     `tests/contracts/test_test_contract.py`. **An assertion of `returncode != 0` in a Python test
     is not mechanised:** project-init#1052.

3. **One summary line per suite, `<suite>: N passed, M failed`**, so a fleet runner can add the
   numbers up. The line matches `^[A-Za-z0-9._-]+: [0-9]+ passed, [0-9]+ failed$`. A run of
   several suites ends with one total line of the same shape, named after the repo, and **a fleet
   runner reads the last such line**. The exit code agrees with it: 0 means M is 0, and M above 0
   means a non-zero exit. A non-zero exit with M at 0 is a run that did not finish (a crash, a
   usage error, nothing collected), and the runner reports the exit code beside it.
   - *Harbor:* `t_done` prints the suite's line. `just test` is [run.sh](../tests/lib/run.sh):
     every suite in [suites.txt](./suites.txt), or the ones named, then the total
     `harbor: N passed, M failed`. A suite that exits non-zero without counting a failure, or
     prints no summary, counts as one failed. Checked by
     [test-contract-test.sh](../tests/checks/test-contract-test.sh).
   - *Python:* the scaffolded root `conftest.py` prints `<project>: N passed, M failed` at the
     end of every pytest run, `just test` and `just test-cov` alike. An error counts as failed; a
     skip counts in neither. Checked by project-init's `tests/contracts/test_test_contract.py`.
   - *The reader:* `projects-orchestrator test-fleet` (projects-orchestrator#316) runs `just
     test` in every repo `fleet.yaml` names and prints one row per repo: repo, passed, failed,
     exit.

4. **Every suite is in the repo's CI manifest, checked both ways**: no suite runs only on a
   laptop, and no manifest line names a suite that is gone.
   - *Harbor:* [suites.txt](./suites.txt) is the manifest CI iterates. Lint **C3** fails a
     tracked `*-test.sh` it does not list, a line naming a file that does not exist, and a
     manifest CI does not read; **C5** fails a suite with no selecting paths in
     [suite-paths.txt](./suite-paths.txt).
   - *Python:* pytest discovery is the manifest, and CI runs the whole of `tests/` through the
     justfile (`just test-cov` in the template's CI). A test file outside discovery's
     `test_*.py` and `*_test.py` patterns is collected by nothing, and **nothing reports it:**
     project-init#1053.

5. **A changed test shows it can fail.** A test added or changed is shown red against a mutant
   of its subject, then green against the real one (CONSTITUTION №2.10). A test that cannot fail
   is worse than none.
   - *Harbor:* for the guard tables it is mechanised — [check-test.sh](../tests/lib/check-test.sh)
     (rule T7) runs every table against a guard that always allows and one that always denies,
     and exactly the rows expecting otherwise must fail. Everywhere else it is the PR's
     red-then-green table, at least three mutants per changed behaviour
     ([tests/README.md](../tests/README.md), "Prove it can fail"), read by a reviewer.
   - *Python:* the template's `just test-mutation` (mutmut) runs nightly in CI. Per change, it
     is the PR's red-then-green evidence, read by a reviewer. **Not machine-checked per PR in
     either language.**

6. **Live checks are a separate, read-only tier**, never mixed into a hermetic suite. A live
   check reads the real box and writes nothing to it; a hermetic suite never reads the real box
   at all (rule 1), so the two cannot blur.
   - *Harbor:* `harbor check --live` ([live-verify.sh](../bin/live-verify.sh), harbor#735) runs
     every existing live check — the floor, doctor, install drift, the shims, the roots, sec0's
     four decided `env` keys (harbor#816) — one line each with its id, and exits 1 if any is
     red. `--probes` adds the opt-in real-system
     probes harbor#667 moved behind stubs. It refuses to run in CI, writes nothing (proved by a
     stamp and `find -newer` in [live-verify-test.sh](../tests/cli/live-verify-test.sh)), and
     is the `live-verify` row of [CHECKS.md](../CHECKS.md).
   - *Python:* rule 1's fixture keeps the real home out of every test. A live check is a
     command, never a pytest test.

## The entry point

`just test` in every governed repo runs its hermetic tests, ends with the rule 3 summary line and
exits with the exact code. `just lint` and `just ci` sit beside it. `project-init` stamps the
contract into every repo it scaffolds and carries it into existing ones on `project-init
upgrade`; `projects-orchestrator test-fleet` reports every fleet repo red or green in one table.

## What nothing enforces

Said here so no one reads it as checked: that a Python test asserts an exact exit code
(project-init#1052); that every Python test file is discoverable (project-init#1053); that a
changed test was shown red, outside Harbor's guard tables; and that the template's Node, Go and
Rust `just test` recipes print the rule 3 line (project-init#1054) — today only the Python
template does.
