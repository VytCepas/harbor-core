# git verbs — the git command shapes that pass on this box, and the ones refused on purpose

This is the one list (harbor#1291). Each row is a git command shape, what lets it
through, and the spelling to use when the shape you were about to type does not
pass. The register has three parts: **reads** (always free), **everyday writes**,
and **forms refused or gated by design**, each of those with the safe alternative.

**Nothing restates these rows.** `bin/admission-deny.sh` builds the `permissions.allow`
and `permissions.ask` rules from the rows marked `allow` and `ask`, so they deploy
with the floor (`sh bin/admission-deny.sh --apply --live`), and `bin/admission-remove.sh`
takes the same rules back out; both read the rows through `il_git_verbs` in
`bin/deploy-install-lib.sh`. `tests/admission/git/verbs.test.sh`
fails when this table, the rules floor-deny writes, its deny entries and
guard-bash's read-only git list (`_git_seg_is_ro`) disagree, and when an allow rule
matches a gated row that no ask, deny or floor block outranks.

## Columns

| Column | Values |
|---|---|
| spelling | The shape, in permission-rule syntax: `*` is any text, `<x>` stands for an argument you supply. An `allow` or `ask` row's spelling **is** the rule, so it has no `<x>`. |
| class | `read`, `write`, or `gated`, meaning refused or gated by design. |
| perm | What decides it at the permission layer. `builtin`: Claude Code already treats it as read-only, so no rule is needed. `allow`: an allow rule derived from this row. `ask`: an ask rule derived from this row, always a person; ask outranks allow. `deny`: a B1 deny entry. `classifier`: no rule, so auto mode's classifier judges it, and outside auto mode it prompts. |
| floor | What guard-bash does with it. `ro`: in its read-only git list, so a read that names a floor surface is not taken for a write. `-`: not on that list. `block:<rule>`: the floor refuses it. `ask:<rule>`: guard-destroy asks. |
| calls | Git segments matching the spelling in the 30 days to 2026-10-17. Rows overlap, so a segment can count on more than one row. |
| refused | How many of those were refused for the git shape itself: by a prompt, the classifier, the floor or a harness check, in calls whose other commands were all free readers (`cat`, `head`, `grep`, `wc` and the like). A refusal caused by a neighbour in the same command is not counted here; see Findings. |
| instead | The spelling to use, or why the row is the way it is. |

`builtin` and `allow` were probed, never assumed: a fresh `claude -p
--permission-mode dontAsk` session, in which anything that would prompt is refused
instead, run once with no settings and once with only the rules derived from this
table. On 2026-10-17, with the box's own user settings plus the derived rules,
every `builtin` and `allow` read row ran without a prompt, `git fetch` ran, and the
three asks probed (`--upl=`, `--discard-changes`, `worktree add -B`) and the
`classifier` reads probed (`git ls-remote`, `git -C`) were refused.

## Reads — always free

| spelling | class | perm | floor | calls | refused | instead |
|---|---|---|---|---|---|---|
| `git status *` | read | builtin | ro | 3660 | 2 | |
| `git log *` | read | builtin | ro | 4981 | 0 | |
| `git diff *` | read | builtin | ro | 3804 | 5 | |
| `git show *` | read | builtin | ro | 3301 | 2 | |
| `git grep *` | read | builtin | ro | 3027 | 1 | |
| `git blame *` | read | builtin | ro | 3 | 0 | |
| `git cat-file *` | read | builtin | ro | 37 | 0 | |
| `git ls-files *` | read | builtin | ro | 679 | 0 | |
| `git ls-tree *` | read | allow | ro | 330 | 0 | |
| `git rev-parse *` | read | builtin | ro | 439 | 0 | |
| `git describe *` | read | builtin | ro | 1 | 0 | |
| `git shortlog *` | read | builtin | ro | 0 | 0 | |
| `git whatchanged *` | read | classifier | ro | 0 | 0 | `git log --raw <args>`: whatchanged takes log's `--output=<file>`, so it gets no allow rule |
| `git merge-base *` | read | builtin | - | 142 | 0 | |
| `git rev-list *` | read | builtin | - | 70 | 0 | |
| `git for-each-ref *` | read | builtin | - | 20 | 0 | |
| `git show-ref *` | read | allow | - | 3 | 0 | |
| `git reflog` | read | builtin | - | 0 | 0 | |
| `git reflog show *` | read | builtin | - | 2 | 0 | |
| `git branch` | read | builtin | - | 8 | 0 | |
| `git branch --show-current` | read | builtin | - | 197 | 0 | |
| `git branch --list *` | read | builtin | - | 24 | 0 | |
| `git branch -a` | read | builtin | - | 45 | 0 | |
| `git branch -r` | read | builtin | - | 29 | 0 | |
| `git branch -vv` | read | builtin | - | 6 | 0 | |
| `git remote -v` | read | builtin | - | 89 | 0 | |
| `git remote get-url *` | read | allow | - | 21 | 0 | |
| `git config --get *` | read | builtin | - | 42 | 0 | |
| `git config --get-all *` | read | allow | - | 4 | 0 | |
| `git config --get-regexp *` | read | allow | - | 7 | 0 | |
| `git config --list *` | read | allow | - | 0 | 0 | |
| `git worktree list *` | read | builtin | - | 383 | 0 | |
| `git stash list *` | read | builtin | - | 99 | 0 | |
| `git stash show *` | read | builtin | - | 2 | 0 | |
| `git check-ignore *` | read | allow | - | 48 | 0 | |
| `git merge-tree *` | read | allow | - | 105 | 0 | writes objects only, never a ref |
| `git name-rev *` | read | allow | - | 0 | 0 | |
| `git version` | read | allow | - | 0 | 0 | |
| `git --version` | read | classifier | - | 33 | 0 | `git version`: a rule has to start with a subcommand, never a flag |
| `git ls-remote *` | read | classifier | - | 232 | 2 | no allow rule: `-u <cmd>` / `--upload-pack=<cmd>` runs a program, and a glob cannot leave it out |
| `git --no-pager <read>` | read | classifier | - | 10 | 0 | `git <read>`: a Bash call has no terminal, so there is no pager to turn off |
| `git -C <dir> *` | read | classifier | - | 10062 | 24 | `cd <dir>` as its own Bash call, then plain `git <args>`. No rule can allow `-C` safely: the `*` after it absorbs `-c core.pager=<cmd>`. `cd <dir> && git <args>` in ONE call always prompts, because Claude Code gates a cd-then-git compound. A subagent's cwd resets between calls, so hand it the repo as its working directory |

## Everyday writes

| spelling | class | perm | floor | calls | refused | instead |
|---|---|---|---|---|---|---|
| `git add *` | write | allow | - | 2021 | 1 | |
| `git commit *` | write | allow | - | 2155 | 0 | `--no-verify` passes too and skips the local hooks; CI's lint C2 still checks attribution |
| `git fetch *` | write | allow | - | 1416 | 0 | writes remote-tracking refs only; `--upload-pack` and a forced `+<refspec>` are asks (below) |
| `git fetch` | write | allow | - | 2 | 0 | |
| `git switch -c *` | write | allow | - | 12 | 0 | |
| `git worktree add *` | write | allow | - | 644 | 0 | prefer `sh <harbor>/bin/worktree.sh new <branch>`, which branches off `origin/main` and links the memory store |
| `sh <harbor>/bin/worktree.sh new <branch>` | write | classifier | - | 0 | 0 | the script lives in an editable checkout, so it never gets an allow rule (the reasoning beside floor-deny's approval-gate rules) |
| `git push *` | write | classifier | - | 1145 | 10 | spell it `git push -u origin <branch>`, in its own Bash call: the floor's force-push rule reads a force flag anywhere after `push` in the whole command. No allow rule, because force, delete, `+<refspec>` and `--no-verify` all live in the arguments |
| `git push --force-with-lease origin <branch>` | write | classifier | - | 24 | 0 | the rewrite-a-branch spelling that passes; the bare force flag is refused (below) |
| `git pull *` | write | classifier | - | 178 | 1 | `git pull --ff-only` |
| `git merge *` | write | classifier | - | 213 | 0 | |
| `git checkout *` | write | classifier | - | 803 | 2 | to make a branch, `git switch -c <branch>`, which is allowed |
| `git stash *` | write | classifier | - | 399 | 0 | push, pop and apply; drop and clear are gated (below) |
| `git rebase *` | write | classifier | - | 161 | 0 | |
| `git reset *` | write | classifier | - | 89 | 0 | `--hard` is gated (below) |
| `git worktree remove <path>` | write | classifier | - | 208 | 2 | `sh <harbor>/bin/worktree.sh retire <name>`, which refuses a dirty, held or unmerged tree |
| `git worktree prune` | write | classifier | - | 26 | 1 | |
| `git branch -D <branch>` | write | classifier | - | 82 | 1 | `sh <harbor>/bin/worktree.sh gc --apply` for merged session branches |
| `git branch -d *` | write | classifier | - | 19 | 0 | |
| `git branch -m *` | write | classifier | - | 29 | 0 | |
| `git rm *` | write | classifier | - | 54 | 0 | |
| `git mv *` | write | classifier | - | 33 | 0 | |
| `git apply *` | write | classifier | - | 74 | 1 | |
| `git cherry-pick *` | write | classifier | - | 28 | 0 | |
| `git archive *` | write | classifier | - | 77 | 0 | |
| `git update-ref *` | write | classifier | - | 31 | 0 | |
| `git init *` | write | classifier | - | 155 | 0 | |
| `git clone *` | write | classifier | - | 90 | 0 | |
| `git config <key> <value>` | write | classifier | - | 247 | 0 | |
| `git config --global *` | write | classifier | - | 58 | 0 | changes every repo on the box |
| `git -c <key>=<value> *` | write | classifier | - | 203 | 0 | `-c` never counts as a read anywhere; in a scratch repo, `git config user.email <x>` once, then plain commits |
| `GIT_EDITOR=true git *` | write | classifier | - | 52 | 0 | an environment prefix matches no rule, so the classifier judges it |

## Refused or gated by design

| spelling | class | perm | floor | calls | refused | instead |
|---|---|---|---|---|---|---|
| `git push --force *` | gated | classifier | block:force-push | 0 | 0 | `git push --force-with-lease origin <branch>` |
| `git push -f *` | gated | classifier | block:force-push | 0 | 0 | `git push --force-with-lease origin <branch>` |
| `git push --force*main*` | gated | deny | block:force-push-protected | 0 | 0 | never: open a PR |
| `git push -f*main*` | gated | deny | block:force-push-protected | 0 | 0 | never: open a PR |
| `git push --force*master*` | gated | deny | block:force-push-protected | 0 | 0 | never: open a PR |
| `git push -f*master*` | gated | deny | block:force-push-protected | 0 | 0 | never: open a PR |
| `git push origin main` | gated | classifier | block:merge-raw | 5 | 0 | push a branch, then `<cfg>/bin/gate-merge.sh <owner/repo> <pr>` |
| `git push origin HEAD:main` | gated | classifier | block:merge-raw | 0 | 0 | push a branch, then `<cfg>/bin/gate-merge.sh <owner/repo> <pr>` |
| `git push --no-verify *` | gated | classifier | - | 1 | 0 | fix what the pre-push hook found; skipping it is refused |
| `git push origin --delete <branch>` | gated | classifier | - | 12 | 1 | leave merged branches to GitHub's delete-on-merge; anything else is the operator's call |
| `git reset --hard *` | gated | classifier | ask:git-reset-hard | 2 | 0 | `git stash push -m <why>` first, or do the work in a fresh worktree |
| `git clean -f*` | gated | classifier | ask:git-clean-force | 4 | 0 | `git clean -n` to list, then remove the named paths |
| `git stash drop *` | gated | classifier | ask:git-stash-drop | 27 | 0 | leave the stash; it costs nothing |
| `git stash clear` | gated | classifier | ask:git-stash-drop | 0 | 0 | leave the stash; it costs nothing |
| `git reflog expire *` | gated | classifier | ask:git-reflog-expire | 0 | 0 | never: the reflog is the recovery net |
| `git worktree remove --force *` | gated | classifier | ask:git-worktree-remove-force | 90 | 0 | `sh <harbor>/bin/worktree.sh retire <name>` |
| `git checkout -- <floor-surface>` | gated | classifier | block:git-write-at-surface | 6 | 0 | edit the surface in its source repo and deploy |
| `git fetch --u*` | gated | ask | - | 0 | 0 | plain `git fetch <remote>`: `--upload-pack=<cmd>` runs a program, and git accepts any unambiguous abbreviation of it, so the ask is on the `--u` prefix |
| `git fetch * --u*` | gated | ask | - | 0 | 0 | as above |
| `git fetch * +*` | gated | ask | - | 5 | 0 | `git fetch <remote>`; a forced refspec can drop a local branch's commits |
| `git switch * --di*` | gated | ask | - | 0 | 0 | commit or stash first: `--discard-changes`, under any abbreviation, resets the tree |
| `git switch * --force*` | gated | ask | - | 0 | 0 | commit or stash first |
| `git switch * -f*` | gated | ask | - | 0 | 0 | commit or stash first |
| `git worktree add -B *` | gated | ask | - | 1 | 0 | `-b <new-branch>`: `-B` resets a branch that already exists |
| `git worktree add * -B *` | gated | ask | - | 3 | 0 | as above |
| `git grep -O<cmd> *` | gated | classifier | ro | 5 | 0 | plain `git grep`: `-O` opens the matches in a program |
| `git diff --output=<file> *` | gated | classifier | ro | 0 | 0 | `git diff <args> > <file>`, where the floor's redirect rules can see the target |
| `git ls-remote --upload-pack=<cmd> *` | gated | classifier | - | 0 | 0 | plain `git ls-remote <remote>` |
| `git -c core.pager=<cmd> <read>` | gated | classifier | - | 0 | 0 | drop the `-c`: it turns any read into arbitrary execution |
| `git -c alias.<x>=!<cmd> <x>` | gated | classifier | - | 0 | 0 | drop the `-c` |
| `GIT_DIR=<dir> git *` | gated | classifier | - | 5 | 0 | `cd <repo>` as its own call, then `git <args>`: an environment prefix matches no rule |

## Findings

Measured 2026-10-17 over the 30 days before, from every session transcript on the
box, main sessions and subagents. These are a dated measurement: re-measure them,
never trust them. Only the counts are kept; no command text is stored.

**Git almost never fails because of git.** 22,559 Bash calls used git, holding
43,065 git segments. 20,641 ran clean. 411 were refused before running, and only
42 of those were refused for the git shape itself:

| Refused before running | calls | for git itself | for a neighbour in the same command |
|---|---|---|---|
| floor guard (`HELM FLOOR [rule]`) | 170 | 15 | 155 |
| auto-mode classifier | 98 | 18 | 80 |
| permission prompt | 93 | 0 | 93 |
| isolated subagent left its worktree | 43 | 9 | 34 |
| harness rm-safety check, other hooks | 7 | 0 | 7 |

- **The neighbours.** `rm -r` in the same call caused 79 refusals (a prompt or the rm
  safety check), floor rules on other commands 155 (`interpreter-at-surface` 32,
  `pipe-to-shell` 23, `python-c-exec` 15, `mutate-onto-surface` 14), and the classifier
  judging another command 80. Keep a git call in its own Bash call when it writes.
- **The floor's force-push rule is the largest git-specific false positive.** It
  refused 10 calls, and 9 of them had no force flag on any `git push`: it reads `-f`
  and `--force` anywhere after `push` in the whole command, prose and heredocs
  included. Not changed here; the register's push row says to push in its own call.
- **`git -C` is 10,062 segments, 23% of all git, and none of it is free.** It is not
  Claude Code's built-in read-only set, and no rule can allow it safely, so every one
  goes to the classifier in auto mode and prompts everywhere else. `cd <dir> && git`
  in one call is gated too. A separate `cd` call followed by plain git passes.
- **Auto mode sometimes classifies reads that are built-in.** 6 of the 18 classifier
  refusals were `git status`, `git diff`, `git show` or `git grep` with only free
  readers beside them, all of which run unprompted in `dontAsk`; 2 were "no verdict".
  An allow rule would take them off the classifier, but `git log/diff/show *` would
  also pass `--output=<file>` under any abbreviation, and `git grep *` a clustered
  `-O<cmd>`, so they stay built-in.
- **Other failures are not permission failures**: 281 non-zero exits that were not
  git errors (mostly a later `grep` or test), 47 git errors, 45 git-hook refusals
  (commit-msg attribution, pre-push), 26 shell traps (a zsh glob that matched
  nothing, `==` in `[`), 13 harness sleep blocks.

**Coverage of this register:** of the 43,065 segments, 21,085 match a built-in read,
6,757 an allow row, 14,436 a classifier row, 166 a gated row and 621 nothing (1.4%).

**Residual, stated plainly.** The ask rows match the spellings git documents and the
abbreviations it accepts for long flags. A clustered short flag (`-qf`, `-fB`) is
not matched by them and reaches the allow rule; the floor guard, not a glob, is the
layer for an adversarial spelling.

**The live box already carried four of the allow rules**, added by hand (`git add`,
`git commit`, `git switch -c`, `git worktree add`). They are derived from here now,
with the asks that the hand-added ones lacked.
