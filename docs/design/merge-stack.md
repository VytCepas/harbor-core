# Merge stack — many PRs onto main, in order, without surprises

**Status:** harbor#1060. `harbor merge-stack check|rehearse|merge|verify <plan>`, one POSIX `sh` tool
(`bin/gate-merge-stack.sh`) and its list resolver (`bin/gate-merge-stack-resolve.py`), ported from the
2026-10-06 night stack, where every rule below was a defect that run hit. The suites are
`tests/ci/merge-stack/`; each trap in the table has a mutant in them that goes red when the fix is removed.

The tool never edits the plan. It reads the plan, drives `gh` and `git`, and ends with the log shape of
[logging.md](../../contracts/logging.md): exit 0 clean, 1 a problem was reported, 2 a usage error or a bad plan.

## The plan

One file per batch, `#` starts a comment. Keys, one per line:

```
repo     owner/name
checkout the local main checkout of that repo (deploy and the generators run from it; gate-merge-check.sh does not)
workflow the CI workflow file that gates a merge. Without it the latest run of EVERY workflow on the head must be success
tested   the integration-check branch whose CI passed on the combined tree (rehearse --push names it)
pr N     a PR to merge, in merge order. Every PR is based on the default branch; a conflict after an earlier merge is rebased
pr N head <sha>   the same, pinned to the commit that was judged (the full 40-hex sha, compared with =, never a prefix): any other head is needs-rebase, never synced
after N  CMD...   printed right after PR N merges: a one-time step the operator runs (e.g. a secret import)
```

A `pr` line is `pr N` or `pr N head <40-hex sha>`; anything else, and a pin that is short, upper case or not hex, is a usage error. `repo` must be `owner/name`, each `pr` a number and `checkout` a directory, or the tool exits 2 before it
runs anything. `tested` is never `main` or one of the plan's own PR branches: `rehearse --push` overwrites it.

## The procedure

| Step | Who | Command | Done when |
|---|---|---|---|
| 1. Plan | Claude | write the plan: repo, checkout, workflow, `pr` lines in merge order, `after` steps | the order puts dependencies first |
| 2. Review | Claude | one adversarial review per PR; fixes pushed as new commits | every verdict is MERGE |
| 3. Rehearse | Claude | `harbor merge-stack rehearse <plan>` | `rehearsal clean`: every PR rebased, no conflict left for a person (lint and suites are step 4's CI) |
| 4. Integration CI | Claude | `harbor merge-stack rehearse <plan> --push` | the DO-NOT-MERGE PR is green on the full suite |
| 5. Ready? | either | `harbor merge-stack check <plan>` | no FAIL line |
| 6. Merge | **operator, real Terminal** | `harbor merge-stack merge <plan>` | `done`; run each printed `run once now:` line |
| 7. Verify | operator | `harbor merge-stack verify <plan>` | `ALL CLEAR` |
| 8. Deploy | **operator, real Terminal** | `sh <checkout>/bin/deploy.sh --live`, then `--apply --live` | deploy's own verify passes |
| 9. Clean up | operator | `gh pr close <integration PR> --delete-branch` | only after step 7 |

Steps 6 and 8 cannot run inside a Claude session: auto mode refuses a merge and a force-push, deploy's
`--apply` refuses a session, and deploy asks `[y/N]` on a tty. `check` writes nothing. `rehearse` writes a scratch
clone (`$HARBOR_GATE_REHEARSE_DIR`, default `~/.cache/merge-stack`, under `~` because a session scratchpad can be
purged mid-run) and, with `--push`, the `tested` branch and its PR. `merge` rebases and force-pushes a PR branch only
when GitHub calls it conflicting. `verify` fast-forwards the checkout to the default branch's `origin/` ref and adds a throwaway worktree
it removes. `harbor` on the box is a copy: a new verb reaches it with `harbor deploy`, not with `git pull`.

## The traps this tool already handles

| Trap (2026-10-06) | Handled by |
|---|---|
| `gh pr checks --required` reports nothing forever on a repo with no branch protection, so the merge hung | `green` waits on the PR head's own CI run; `gate-merge-check.sh` gates on the required-checks list read from `origin/<default branch>` |
| A run cancelled while it was watched counted as red, or as a pass | `green` re-looks-up the runs and waits on a newer run of that workflow and event; with none after six looks (10 s apart) the cancelled run is red and the merge stops |
| A workflow whose only run was cancelled dropped out of the judged set, so `gh run cancel` on a failing run let the merge go on (5b.12) | a cancelled latest run stays in the set and is not `success`: `check` reports it red, `merge` refuses |
| Right after a sync push GitHub still reported the OLD head, so its old green run was judged and merge-check refused the new head (#1115) | `sync` records the sha it pushed in `PUSHED`, clears it for each PR, and `green` waits (36 tries, 5 s apart) until the PR head equals it, then looks up the run |
| `merge-stack` called `bin/gate-merge-check.sh` inside the target repo's checkout, so a repo that is not harbor could not merge through it | `gate-merge-check.sh` is resolved from the tool's own install dir, with `HARBOR_REPO=<owner/name>` from the plan and the repo's required-checks list from origin; merge-check's own gate logic is unchanged (ship contract 5a.6) |
| The opt-in file was read from the checkout's working tree, so an uncommitted edit, or a checkout on the PR's own branch, let a PR drop its own required check (5b.11) | the file is read from `origin/<default branch>` after a fetch, into a temp file; the working tree is never read |
| With no `.agents/required-checks.tsv` on origin (harbor's own case) the list was not passed, so merge-check read the file beside itself: from a checkout's `bin/` the working tree, where an uncommitted edit or the PR's branch dropped a check; once installed, nothing, so harbor was refused even when green (r4 #1) | merge-check is **always** handed the required checks read from origin (see "Any repo" below), never a working tree, in both layouts |
| `gh run list --limit 100` returns the newest 100 runs, so 100 newer `workflow_dispatch` runs hid an older red `pull_request` run (r4 #4) | a page that comes back full is refused: `check` reports it, `merge` stops on it. A commit with that many runs is judged by a person |
| The head that merged was not the head that was judged: `green` re-read the PR head, a push could land between the run and the merge, and `sync` could rebase a classified PR (ship contract 5b.10) | `green` records the sha whose runs it judged; the merge passes `gate-merge-check.sh --match-head-commit <that sha>`, so gh refuses it if the head moved. A pinned PR (`pr N head <sha>`) on any other head is reported `needs-rebase` and skipped, never synced; the run then exits 3 |
| With no `workflow` key only one run on the head was judged, so a red `lint` beside a newer green `test` merged (5b.12) | the latest run of every workflow (and event) on the head is listed; each must be `success`. A red, skipped, neutral or pending one blocks (pending is waited for) |
| `sync`, `rehearse` and `verify` assumed harbor: they took `docs/index.html` and `docs/generated/status.md` from the base on any repo, ran harbor's generators, and hard-coded `main` (5b.11) | no file is taken from the base and no generator runs (r5 #2); `verify` leaves `docs/generated/status.md` out of its tested-tree diff only where the repo owns its generator (`docs/index.html` is built on demand and not committed since harbor#1197, so it is no longer special). The default branch is read from GitHub (else `origin/HEAD`) and passed on as `HARBOR_BRANCH` |
| A 7-hex pin merged a commit that only shared its prefix | a pin is the full 40-hex sha, compared with `=`; anything shorter is a usage error |
| Two workflow files can share a `name:`, so a red run hid behind a green one of the same name | runs are grouped by `workflowDatabaseId`, never by name |
| A newer green `workflow_dispatch` (or `push`) run of a workflow hid a red `pull_request` run of the same workflow on the head | runs are grouped by workflow id AND `event`, and the latest run of every group must be `success` |
| An unpinned conflicting PR merged the local checkout's copy of its branch: an unpushed commit, or a stale branch that wiped a reviewed fix | `sync` refuses unless the local branch equals `origin/<branch>` after a fetch |
| An empty `headRefOid` read dropped the pin silently (merge-check on main would have refused an empty value) | `green()` dies on an empty or non-40-hex head; merge-check rejects an empty or non-40-hex `--match-head-commit` |
| The resolver unioned code and brought back what a PR had deleted (`FILES="a b c"` against `"a c d"`, a `rm -rf build/` line against one that dropped `build/`) | the rebase uses diff3, and the resolver accepts only blocks where both sides are pure additions to the base; a deletion or an edit stops for a person |
| Any line starting with `#` counted as a comment, so two conflicting C `#define`s were both kept and the later one won; in a `.sh` the same `#define`s inside a here-doc still were (r4 #3) | no line is taken for a comment: whether a `#` line is one cannot be proved from a conflict block, so a block holding one is refused. The resolver also works only on files whose syntax it knows |
| Each merge changes main, so the next PR conflicts in shared lists (`suites.txt`, `suite-paths.txt`) | `sync` rebases it, and the resolver keeps both sides' pure line additions in the `.txt`/`.tsv` line lists declared in `contracts/merge-stack-union.txt` |
| git's `union` driver on `bin/harbor` brought back a word main had deleted: the result held both `ALLOW="status"` and the PR's `ALLOW="status deploy doctor"` (r4 #2) | git's union driver is never used. A declared line list loses no line (a block where either side dropped a base line stops); `bin/harbor` and `cli.md` are no longer lists, so a conflict there stops for a person |
| A rehearsal's net commit is titled `#N net`, a comment line to git's editor step, so a `--continue` after a resolved conflict saw an empty message and looped forever | rebases run with `core.commentChar=auto`, and a `--continue` that fails with nothing left conflicted stops the run |
| Two PRs add words to one list line (`FILES="…"`, a `case a\|b)` exemption, a word list) | `bin/gate-merge-stack-resolve.py` keeps both sides. Any other conflict shape stops for a person |
| An operator's `merge.conflictStyle` changes what the resolver is handed | the rebase is always run with `merge.conflictStyle=diff3`, so the resolver sees the base |
| Replaying a PR commit by commit under a line union resurrected a line the PR itself had deleted | `sync` rebases the PR's **net** change as one commit (it is squash-merged anyway), so a line it added and removed again never conflicts |
| Union kept a line both sides added, so a suite ran twice and its result was LOST | after the rebase, `contracts/suites.txt` and `suite-paths.txt` are deduped (awk, no PR code) |
| `sync` ran the rebased PR's own `bin/doc-index-generate.sh` and `bin/status-generate.sh` with the operator's credentials before its CI was judged, so a red PR's generator wrote a commit to main (r5 #2, probe n14) | **merge-stack never runs code from a PR branch.** No generator runs: they execute the tree they read (docs-gen its lint, status-gen its suites), so no copy of them, installed or `origin`'s, could rebuild a PR's files without running the PR. A conflict in a generated file stops for a person; a stale one fails the PR's own CI, which stops the run. Every git command runs with `core.hooksPath=/dev/null`, because a relative hooks path resolves into the PR's tree and harbor's own `pre-push` runs `bin/` from it. `rehearse` runs no lint, suite or generator of the combined tree: step 4's CI does |
| A modify/delete conflict leaves no marker, so the resolver passed it and `settle` staged the surviving side: main's deletion was undone, or a PR's approved deletion dropped (r5 #1, probe n9) | a conflicted file is resolved only when git lists all three stages of it, each the same regular-file mode, and the resolver resolved at least one block (a file with no block exits 1). A deletion, an add/add, a binary file, a mode change, a link or a submodule stops for a person, in `merge` and `rehearse` alike |
| The target repo's `.gitattributes` (or a global or system attributes file, or `merge.default`) still routed a path through git's `union` driver during the rebase (r5 #5, probe n15) | the rebase reads no attributes from the tree, the global or the system file (`--attr-source=<empty tree>`, git 2.42+, checked at start), runs with `merge.default=text` and no rerere; `$GIT_DIR/info/attributes` cannot be switched off, so a PR whose paths it gives a merge driver is refused before the rebase |
| An earlier PR in the plan lowered the required checks the later PRs were judged by, and a repo's own file replaced harbor's rows for it, even a weaker one (r5 #3, #4, probes n11, n13) | the required checks are read once, at preflight, and held for the run; they are the union of every declaration (see "Any repo") |
| `rehearse` left out a PR whose head branch was not on origin (a fork PR), labelled the next PR's change with its number, and still reported clean (r5 #6, probe n12) | a PR whose head is not `origin/<its branch>` stops the rehearsal, and so does any step that fails to build its net change or to fast-forward the combined tree onto it |
| A PR that is green alone failed only in combination (a tripwire against a new `stat -f`; a new top-level dir deploy's snapshot missed) | step 4: CI on the combined tree, before any merge |
| A script that is never shipped silently never runs once deployed | step 2's review brief: "prove the installed layout runs" |
| `gate-merge-stack.sh` was never installed under `~/.claude/bin/`, nor were `gate-merge-check.sh` and the resolver it runs from its own dir, and its union list was read from `../CONTRACTS/`, which an install does not have (5b.9) | `deploy-runtime-install.sh` ships all three, and `contracts/merge-stack-union.txt` into `bin/` beside them; the tool reads the union list from its own dir first, and `check`/`merge` refuse when it is in neither place |
| A lint run inside the main checkout scanned a leftover `.claude/worktrees/agent-*` tree | `verify` lints a clean throwaway checkout of `origin/main` |
| `secret` and other `~/.local/bin` links run from the checkout, so a new verb exists only after `git pull` | `after` lines are printed after the merge; run them after step 7's fast-forward |
| A sibling repo the deploy also installs was behind or on a detached HEAD, so the deploy preflight failed | `verify` step 5 runs the deploy plan, and its FAIL names the repo |

## Any repo, not just harbor

`merge` calls `gate-merge-check.sh` from the same directory as `gate-merge-stack.sh`, never from the target repo, so a repo
needs none of harbor's scripts. It passes `HARBOR_REPO=<owner/name>` from the plan and, always,
`HARBOR_REQUIRED_CHECKS=<a temp file>` holding the **union** of every declaration for that repo (r5 #3, #1139):
`.agents/required-checks.tsv` and `contracts/required-checks.tsv` as the repo's `origin/<default branch>` holds them, and
harbor's own `contracts/required-checks.tsv` rows for the repo, from the copy installed beside the tool (`bin/required-checks.tsv`,
deployed from harbor's main) or, run from a harbor checkout, as that checkout's `origin/<default branch>` holds it. Those rows are
core's (harbor's own, and every repo whose name may be public) followed by the private layer's `required-checks.tsv` (the rows whose repo
cannot be named in a public tree, `bin/gate-required-generate.sh`, harbor#1149): `deploy-runtime-install.sh` writes the sum into the installed
copy, and a checkout run composes origin's blob with the layer's file, which is no branch of any repo being merged but no protected path
either: an edit to it needs no approval, so it holds only the rows core cannot carry. A layer file that does not compose, or exists and
cannot be read, refuses the run. A repo's own
file can add a check and never drop one harbor requires. The list is read **once, at preflight**, and held for the whole run,
so a PR earlier in the plan cannot lower the gate a later one is judged by (r5 #4). No repo's working tree is read for it (ship
contract 5b.11; the private layer's file is the one working-tree read, and the reason it holds only what core cannot carry), and
merge-check never falls back to the file beside itself. The file is `repo<TAB>check name`, one row per
required check; rows for another repo are ignored. With no row at all, branch protection alone can gate.

**A repo opts in** with branch protection that requires status checks, or with that file when branch protection is
unavailable: merge-check reads the file when GitHub answers 403 (a private repo on a plan with no rules), answers its exact
404 "Branch not protected" (an org repo with no rule, #1139), or protects the branch with no required checks. **Any other
404 does not fall back to the file: merge-check refuses.** With neither opt-in, merge-check has
no gate to judge by and refuses the merge, which is its own rule and not this tool's. `tests/ci/merge-stack/realcheck.test.sh`
runs the real merge-check against a stub gh for the 403, 404 and 200 answers, so this paragraph is pinned to its behaviour.
The other sub-verbs read the
checkout only when a script is there: `verify` runs `bin/lint-conventions.sh`, `tests/lib/check.sh` and `bin/deploy.sh`
from the merged default branch when the repo has them and skips them when it does not. `rehearse` runs none of the combined
tree's code; `--push` hands it to CI.

## The resolver

`bin/gate-merge-stack-resolve.py <file>` resolves a conflicted file (diff3 style: ours, base, theirs) only if every block is one of
three shapes in which both sides only ADDED entries to the base list, and otherwise exits 1 and leaves the file untouched, even when other
blocks in it were resolvable. A file with no conflict block at all (a modify/delete or a binary conflict leaves none) is not
resolved either: it exits 1 (r5 #1). The shapes: a `FILES="…"` word list; a `case "$b" in a|b) continue ;; esac` line; and a closing word
list, plain words ending in `"` with no leading indent. **No line is taken for a comment**: a `#` line inside a here-doc, a
string or a YAML block scalar is data, and a conflict block cannot show which it is, so a block holding a `#` line matches no
shape and stops for a person. It works only on files whose syntax it knows (by extension: `sh bash zsh py yml yaml tsv txt
toml conf cfg awk`; by name: `Makefile`, `.gitignore`, `.gitattributes`; or an extensionless file with an `sh` or `python`
shebang). Any other conflicted file, C or Markdown among them, is refused whole.

`--lines`, which `sync` and `rehearse` pass for a file `contracts/merge-stack-union.txt` declares, resolves a `.txt` or `.tsv`
line list: a block is kept as ours plus theirs' new lines only when neither side lost a line the base had. On any other
extension it is refused: a line list is data, never code. Every entry in that file was audited against that rule; `bin/harbor`
(code) and `contracts/cli.md` (a document) were dropped from it, and git's own `union` driver is not used for any file.

It is Python because it matches multi-line regular expressions, and `doc-graph-generate.sh` and `standard-rename.sh` already run `python3` from `bin/`. Without
`python3` a conflicted file stays for a person.

## Not handled, on purpose

- **Stacked PRs** (a PR based on another PR's branch): consolidate them into one PR per lane first. That was cheaper
  than restacking, and it avoids the force-push auto mode refuses.
- **A real code conflict:** `merge` stops and names the files. Resolve it on the PR branch with new commits, re-run
  step 3, then re-run step 6 (it skips what is already merged).
