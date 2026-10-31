# The suite cache — a suite whose inputs already passed is reported `cached` (harbor#1288)

**Opt-in, off by default.** `bin/test-suite-run.sh` calls `bin/test-suite-cache.sh` only when `HARBOR_SUITE_CACHE=1`.
With the variable unset nothing in this file applies: no key is computed, no store is made, and the output and
the results file are what they were before it existed (`tests/ci/suite-cache/cache.test.sh` proves the runner
never calls the cache then).

**What it buys.** A PR re-pushed after a deterministic failure re-runs every selected suite, including the ones
whose inputs are byte-identical to a run that already passed. With the cache on, those are reported `cached`
and only the suites whose inputs moved run.

**What it costs, and the one way it can be wrong.** A suite served from the cache did not run. If it reads an
input its key does not hold, a change to that input is a green row for a run that never happened: a **false
pass**, which is a defect and not a speed-up. Everything below is built to make that case run instead, and the
limits section names what it still cannot see.

## When the cache applies

All of these, or the whole run is uncached and says why on its `cache off — <reason>` line:

| Condition | Why |
|---|---|
| `HARBOR_SUITE_CACHE=1` | opt-in |
| not `GITHUB_REF=refs/heads/main`, and the checkout is not on branch `main` | main keeps a full verdict |
| `bin/test-suite-select.sh --why-all` exits 1 | a run that selects everything — empty or undeterminable changeset, a selector input changed, an unclassified path — is never served from a cache |
| under Actions, `RUNNER_NAME` is set | it is the trust domain (below) |
| the store is a directory this uid owns and can write, not a symlink | see *Trust* |
| `ROOT` is a git checkout | the key is git object ids |

And per suite — any of these makes that suite run every time, with the reason in `test-suite-cache.sh key <suite>`:

- its declaration in `contracts/suite-paths.txt` is `always`, or it has none — its inputs are not declared;
- its own file runs `git -C "$T_ROOT" …` — its verdict can depend on the checkout's history, which no content key holds.

A **failure is never cached**: only `pass` rows are recorded, and only from a run whose results account for
every queued suite (a damaged results file could carry a row no suite wrote).

## The key

`git hash-object` of a manifest — so the key is a git object id of a text made of git object ids:

```
harbor suite-cache v1                       FORMAT — bumping it is a cold cache
runner <oid of the running bin/test-suite-run.sh>
cache  <oid of the running bin/test-suite-cache.sh>
trust  <domain>                             ci:<RUNNER_NAME> under Actions, else local:<hostname>
host   <uname -srm>
salt   <HARBOR_SUITE_CACHE_SALT>            any text; changing it is a cold cache
declared <the suite's globs>
suite <suite>
<oid> <path>                                one per input, sorted
```

The inputs are the union of:

1. **the suite file**;
2. **every path its declaration covers**, matched as `bin/test-suite-select.sh` matches it (`case` patterns, `*` crosses `/`);
3. **`tests/lib/core.sh`**, the shared test library every suite sources;
4. **every repo path the suite names, followed through the code it names** — the static reference closure.
   A token in a code file (`.sh .awk .py .mjs .cjs .js .ts .bash .pl .rb`, or extensionless under `bin/` or
   `hooks/`) that resolves to a file in the tree, from the root, from the file's own directory, or (for a
   name with a dot) from `bin/`, is an input; if it is code it is read in turn. Whole-line comments are
   skipped (prose naming a tool is not a read of it, and following prose drags most of the repo into every
   key); end-of-line comments and strings are not, so the closure over-approximates.

A path's oid is the index's unless the working tree differs (then git hashes the file), `absent` for a tracked
file the tree has lost, and untracked unignored files are included — so the key is the tree the suite
actually runs against, committed or not. A one-byte change to any input is a new key.

**The key is computed again after the run**, and a pass is kept only when the two agree: a file edited while
the suite ran means the pass belongs to neither.

`sh bin/test-suite-cache.sh manifest <suite>` prints the manifest; `undeclared [suite...]` prints, per suite, the
inputs item 4 adds that its declaration misses — the same blind spot `test-suite-select.sh` has when it decides
what a changeset selects, listed rather than guessed.

## The store

`${HARBOR_SUITE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/harbor/suite-cache}/<domain>/<key>`, one file per
pass: `v1 TAB secs TAB count TAB when TAB suite TAB commit`. A hit replays the pass as a results row
`cached TAB secs TAB 0 TAB count TAB suite TAB passed <when> (commit <c>), key <k>`, so the readers of a row
get what a run gives them:

| Reader | Reads | From a `cached` row |
|---|---|---|
| `test-suite-run.sh --tally` (the required contexts' relays) | col 1 (not `fail`, not `skip` = ran), col 4 count | ran, the recorded count — so `floor_count`, `normalize_count`, `marker_count` and status-gen's `HARBOR_STATUS_SUITE_COUNTS` are the pass's |
| `test-suite-run.sh --combine` | one row per candidate | passed through; counted as `N cached` in its note |
| the CI `results_<K>` outputs | the whole TSV, base64 | unchanged |
| `--record` / `--record-from` | col 2 | **ignored**: the table keeps measured times, never replayed ones |
| `standard-rename.sh --pr-body` ledgers | `pass`/`fail` only | not counted — run a rename's before/after ledgers without the cache |

Entries no run has used for `HARBOR_SUITE_CACHE_DAYS` (default 30) are pruned at record time; a hit touches
its entry. `rm -rf ~/.cache/harbor/suite-cache` empties it; so does a new `HARBOR_SUITE_CACHE_SALT`.

**In CI the store is per runner.** The governance runners (`harbor-linux`, `harbor-linux-2`,
`bin/ci-runners.sh`) are persistent containers, so `$HOME/.cache` survives between jobs and goes with the
container when `ci-runners.sh refresh` recreates it for a new image (a new image is a cold cache, which is
right: the tools changed). **The hit-rate consequence:** a shard runs on whichever runner is free, and a suite
hits only when the runner that takes its shard is the one that recorded its pass — with two runners and no
affinity, about half the suites that could hit will miss on a re-push. A shared store would need a writable
mount both containers trust; the provisioning mounts are read-only by design, and the trust domain below
refuses a foreign writer's entries anyway. The events mount is shared and writable and is **not** a store.
GitHub-hosted runners are ephemeral: the cache is on and never hits.

## Trust

- **The trust domain is in the key**, not only in the path: `ci:<RUNNER_NAME>` under Actions, `local:<hostname>`
  elsewhere. A dev-box entry can never satisfy a CI lookup even if the dev box's store were mounted into the
  runner, and one runner never serves another's pass.
- **An entry counts only if this uid owns it**, in a directory this uid owns and can write. A read-only mount
  of somebody else's store is refused as a whole (`cache off — no store this user owns`).
- **An entry that does not parse, or names another suite, is a miss**, never a pass.
- The dev box (local runs, `hooks/pre-push`) keeps its own store and never feeds CI.

## Limits — what the key cannot see

A suite served from the cache can be a false pass when its verdict depends on something below. These are
stated, not caught; the suite pins the first one as a known `LIMIT` case so a reader cannot mistake it for
coverage:

- **a path built at runtime** (`"${d}ta/x"`, a `find` or glob over a directory, a path read from a file) that is
  not also named literally somewhere in the closure;
- **git state of the checkout** reached other than by `git -C "$T_ROOT"` in the suite's own file — history,
  the base ref, branch names;
- **gitignored files** — they are not in the inventory;
- **anything outside the repo**: installed tools and their versions, the OS beyond `uname -srm`, the network,
  the clock, environment variables a suite reads from the caller (t_init clears `HARBOR_*`, `HELM_*`, `GIT_*`,
  `XDG_*`).

When one of these bites, the fix is the declaration (or `always`), and the escape hatch is a salt or `rm -rf`
of the store. `undeclared` is the first place to look.

## Turning it on

- **Locally:** `HARBOR_SUITE_CACHE=1 sh bin/test-suite-run.sh --select`.
- **In CI:** the suite-shard job passes a repository variable through, never on a push (the script refuses
  main too; the workflow line is belt and braces). Then `gh variable set HARBOR_SUITE_CACHE --body 1`; to turn
  it off, `gh variable delete HARBOR_SUITE_CACHE`.
