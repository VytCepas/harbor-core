# tests/

Where a Harbor test goes, what shape it takes, and which check enforces each rule (harbor#667).

This is Harbor's implementation of the cross-repo test contract, [CONTRACTS/test-contract.md](../CONTRACTS/test-contract.md) (harbor#734): its six rules say what every governed repo's tests owe, and this file says how Harbor meets them. `just test` runs every suite in `CONTRACTS/suites.txt` through `tests/lib/run.sh` and ends with the total `harbor: N passed, M failed`; `just test <name>` runs one. The live tier is `harbor check --live`, never a suite.
Legacy suites in `bin/*-test.sh` move here in batches. The floor guards' single-input verdicts left the floor suite for `tests/guards`. What stays in `tests/floor/floor-test.sh` and its `floor.<part>-test.sh` parts needs state a row cannot carry (the decision ledger, a mutated guard, a section's own fixture), and the smoke's few liveness checks.

## Where a test goes

| You are testing | It goes in | Runner |
|---|---|---|
| a guard's verdict for one input | a row in `tests/guards/<guard>.jsonl`, or in one part `<guard>.<part>.jsonl` once a table passes 500 rows; each part has its own suite `<guard>.<part>-test.sh` | `t_table` |
| the text a guard shows the operator | a row in `tests/guards/<guard>.msg.jsonl` | `t_msgs` |
| a behaviour every guard shares: upper-case binary, path prefix, `env -S`, heredoc, over-cap, no normalizer, subagent, posture, kill switch | a row in `tests/guards/shapes.jsonl` | `t_shared`, against every guard |
| a command every guard must allow | a row in `tests/guards/benign.jsonl` | `t_shared` |
| a guard that answers a shared row differently on purpose, or has a known gap there | a row in `tests/guards/exemptions.jsonl`, with `why` | `t_shared` |
| a new guard | a line in `tests/guards/guards.jsonl`, a `<guard>.jsonl`, and a `<guard>-test.sh` copied from an existing one. The floor guards (bash, egress, selfedit) run on the installed floor from `floor-fixture.sh` | the registry |
| anything else: a CLI, a hook, a script | `tests/<area>/<name>-test.sh` on `tests/lib/core.sh` | `t_eq` `t_has` `t_hasnt` `t_exit` |

A new kind of check gets its own table and runner, never a flag that makes the runner branch per row.

## A row

```
{"id":"git-reset-soft","rule":"git-reset-hard","want":"allow","cmd":"git reset --soft HEAD~1"}
```

- `id`: unique across the guard's tables. A failure prints `<id> (want 'X', got 'Y')`.
- `rule`: the rule the row is about, spelled as the guard's source names it, or `none`.
- `want`: what the guard answers today. One of `allow`, `ask`, `deny`, `block`.
- The payload is exactly one of: `cmd` (Bash); `tool` + `path` (file tools); `tool` + `input` (any other `tool_input`).
- Placeholders in any string: `{home}` the sandbox HOME, `{cfg}` the config dir, `{tmp}` the suite's temp dir, `{root}` the repo checkout.
- `{j}` expands to nothing. Write a token-shaped literal split by it (`sk_{j}live_...`) so no secret scanner matches the tracked row while the guard still receives the joined string (harbor#1149). `fixtures/guard-corpus.jsonl` takes the same `{j}`, deleted by `bin/floor-equiv.sh`.
- **Optional fields:**
  - `why`: the incident or reason.
  - `todo`: the verdict once a known gap is fixed. It is reported every run and never fails.
  - `env`: variables for the guard.
  - `ctx`: extra payload fields, for example `{"agent_type":"workflow-subagent"}`.
  - `pad`: bytes of space-separated filler appended as a trailing comment (one long token is quadratic in guard-egress, harbor#1092).
  - `fixture`: `nonorm` or `copy`.

Rows run on `$T_JOBS` workers (default 3), and assertions then run in row order. `T_SMOKE=1` runs only the first row per rule and verdict; `hooks/pre-commit` runs that for the guards a commit stages, and its summary says it is not a full run.

## Rules

| | Rule | Checked by |
|---|---|---|
| T1 | A suite sources `tests/lib/core.sh`, calls `t_init` and `t_done`, and defines no assertion helpers of its own. | `check.sh` |
| T2 | Files are at most 500 lines. A file header is at most 8 comment lines; after it, comment runs are at most 3. The story goes in the commit or the issue. | `check.sh` |
| T3 | Every row has the keys its runner reads, a real verdict, one payload, and an id unique across the guard's tables. | `check.sh` |
| T4 | Every table belongs to a registered guard, and every part table has its part suite. Every registered guard has its guard script, a table and a suite. Every suite is listed in `CONTRACTS/suites.txt`. | `check.sh` |
| T5 | Every rule the guard's source names has a row that fires it and an `allow` row beside it. Names come from the `rules` pattern in `guards.jsonl`, read with `\`-continued lines joined. | `check.sh` |
| T6 | Every exemption matches a shared row, and either changes its verdict or records a `todo`. | `check.sh` |
| T7 | Every table can fail. Against a guard that always allows, and one that always denies, exactly the rows expecting otherwise fail. | `check-test.sh` |

**The harness** (`tests/lib/core.sh`, checked by `lib-test.sh`):
- HOME, the config dir and TMPDIR are sandboxed, and the caller's `HELM_*` and `HARBOR_*` knobs and status-gen's `FAST` are cleared, so a verdict never depends on who ran the suite (harbor#773). `T_PASS_ENV` names what travels: status-gen's re-entry marker. A suite that takes a knob from its caller reads it before `t_init`. Lint C10 finds a suite the clearing cannot reach: one that runs a program reading a `T_PASS_ENV` knob, or sits off the harness, without clearing it, and one that reads a knob after `t_init` emptied it.
- Exit codes are exact.
- A crash is never read as `allow`.
- A guard that has not answered after `$T_ROW_SECS` seconds (default 60, far above the slowest normal row) is killed, with every child it forked, under bash or dash, and reads `timeout` (harbor#768).
- A block's message is its stderr, so `t_msgs` can check it.
- An empty section or suite fails.

`check.sh` and `check-test.sh` go red on a broken fixture for every rule. That is how the rules are known to work.

## Adding a case

1. Pick the file from the first table.
2. Write the row, then run `sh tests/guards/<guard>-test.sh`.
3. Run `sh tests/lib/check.sh`. It must print 0 violations.
4. When a rule gains a trigger, add the near-miss the guard must keep allowing, with the same `rule`.

Mutation testing, meaning deliberately breaking a guard to see which rows notice, is advisory. It shows where rows are missing and which rows catch nothing new. It never decides on its own what to delete.

## Moving a legacy suite

One batch is one branch (`sh bin/worktree.sh new test/667-<batch>`) and one PR. The batch's issue names each suite's area.

**Areas:** `floor` (the floor, its tokenizer and marker), `hooks` (hook scripts and hook guards), `install` (installers, deploy, roots), `cli` (operator CLIs), `ci` (PR and CI machinery), `checks` (repo checkers: lint, references, module shape), `memory`, `obs` (instruments and ledgers), `skills` (skill checkers).

1. **Baseline.** Run the legacy suite and note its `N passed`.
2. **Rewrite** it as `tests/<area>/<name>-test.sh` on `core.sh`:
   - Every legacy assertion keeps a counterpart. The count may rise, for example when a compound check splits. If it falls, the PR says why.
   - Exit codes are exact: a legacy `-ne 0` becomes the real code.
   - Local functions may build fixtures or wrap `t_*` calls. They never count passes, and never use T1's reserved names.
   - HOME, the config dir and TMPDIR are sandboxed. A case that read the real HOME now reads the sandbox; the PR says whether its meaning changed.
   - The long WHY header moves to the commit message. The file keeps the issue refs within T2's budgets. T2 counts `#` lines inside heredoc stubs too.
   - Every negative needs evidence that its needle could appear:
     - a prose `t_hasnt … 'x'` needs `t_has … 'x'` (lint F9);
     - any other `t_hasnt` needs a check that the input it reads could hold the needle.
     - `t_hasnt` fails on empty text, so render an empty list non-empty (`jq -c` gives `[]`).
   - One property is one assertion. Where a dependency is missing on this host, skip its assertions with a printed reason rather than folding them into one pass. The PR's count table names the host.
   - A sandboxed live-dir case creates the sandbox's `$HOME/.claude` first. Otherwise the not-a-directory check can exit with the gate's own code, and the case passes vacuously.
   - Anchor short needles: `ok` matches inside `invoked`.
   - A suite that also runs as a `~/.local/bin` shim resolves its own path through the symlink before sourcing `core.sh`.
   - A verifier outside the sandbox, such as Playwright or Chrome, is located before `t_init`, preferably from an explicit variable (`HARBOR_PROBE_DIR`). The suite never writes there.
   - Over 500 lines, split by subject, or into `<name>.<part>-test.sh`. The main part keeps `<name>-test.sh` where one exists. A fixture the parts share gets its own file, like `tests/guards/floor-fixture.sh`.
3. **Prove it can fail.**
   - Mutate each subject at least 3 times, one mutant per behaviour the suite claims.
   - Run the legacy and new suites on each mutant. The new suite must be red wherever the legacy one was.
   - A mutant that leaves the file or the output unchanged proves nothing.
   - Restore the subject from a saved copy, not from git: a subject edit that belongs to the PR would be lost.
   - Run both suites under a throwaway HOME with CLAUDE_CONFIG_DIR unset, and check they are green there unmutated. A mutant that removes a live-dir gate lets a legacy suite write the operator's real `~/.claude` or `~/.local/bin`. The Keychain is not under HOME: stub `security` for anything that reaches it.
   - A legacy suite that reads the git index (`git ls-files`) runs in a clean worktree at the branch base, with the mutated subject copied in.
   - Each suite run gets a fresh HOME and stdin from `/dev/null`, so no state carries between rows and a subject that reads stdin cannot swallow them. A legacy suite that needs the real HOME's layout runs through a wrapper that seeds a throwaway HOME, and the PR says so.
   - Check `ps` afterwards: a mutant can orphan a process (a headless Chrome, `prove`'s `hang.sh`).
   - The PR carries the table.
4. **Wire it:**
   - `git rm` the legacy file.
   - Rename its line in `CONTRACTS/suites.txt`.
   - Re-key its line in `CONTRACTS/suite-paths.txt`: add its new path, `tests/lib/core.sh`, and any file it exercises that the line does not declare yet.
     - An `always` suite keeps the bare word `always`. Globs added beside it make it glob-selected, and no lint catches that.
   - Drop its name from `CONTRACTS/cli.md`.
   - Repoint what `git grep <name>-test` finds. In `bin/` that means path-only edits, including a subject that names its own suite in logic: suite-select's SELF list, proposal's machinery list, port-paths' pathspec. A `CONTRACTS/shims.tsv` row naming the suite moves too, and the operator re-runs the shim installer after merge. Hits outside `bin/` count as well: a skill's `SKILL.md`, and its test-strength control copy. Leave dated records alone: `docs/audits/`, `COVERAGE-INCIDENTS.tsv`, `patches/`.
   - A path on an Evidence line in `harbor-build-tickets.md` gets repointed too, then run `sh bin/plan-status.sh`. PLAN.md derives DONE from those paths, and lint T1c fails on a stale one.
   - Drop the rows in `CONTRACTS/port-paths-exempt.tsv` keyed on the old path.
   - Run `sh bin/docs-gen.sh --check` (the page is not committed; this proves it still builds).
5. **Gates:** each new suite green; `sh tests/lib/check.sh` at 0 violations; `sh bin/lint-conventions.sh` green; every `tests/checks/lint*-test.sh` part too if `bin/lint-conventions.sh` changed.

**Not an agent's to move:** a suite with its own CI job. CI names those in a workflow an agent cannot edit, so they stay in `bin/` until the operator changes it. List them with `grep -o -- '--run [a-z-]*-test\.sh' .github/workflows/governance.yml`.

**Traps seen so far:**
- A legacy `grep -q X || bad …; ok` counts a pass even when it fails. The port is one `t_has`.
- A legacy negative can be vacuous: a fixture without the needle, a variable the caller already set, a path that does not exist. The batches so far found more than a dozen, and a port must not keep them.
- A counter incremented inside a function called as `$(…)` never counts: the subshell's variable dies with it.
- Under /bin/sh, `case x in pat)` inside `$(…)` is a syntax error. Write `(pat)`.
- ugrep skips a file containing a NUL byte (`bin/failure-observe.sh`). Use `grep -a` or awk there.
- Never edit a suite while it runs: `sh` reads the file as it goes.
- On a rebase, conflicts in `CONTRACTS/suites.txt`, `suite-paths.txt`, `cli.md` and `PLAN.md` are expected. Keep both sides, then rerun `plan-status.sh`. `docs/index.html` is built, not committed, so it never conflicts.
- The floor refuses a Bash heredoc whose body mentions a document path like `~/x.pdf` (#716). Write such files with the editor tool.
