# Approval gate — the operator approves protected merges and deploys with a click

**Status:** harbor#1018, PR A of the ship contract (`~/Deliverables/2026-10-06-night-stack/SHIP-CONTRACT.md` v1.2).
It is stacked on #1126 (`harbor merge-stack`), whose CI wait it shares. PR B (#1128), the runner `bin/deploy-fleet.sh`,
calls the CLI below. Suites: `tests/gate/approval/` and `tests/admission/bash/gate.test.sh`.

## The policy (the operator, 2026-10-06)

1. Nothing red is merged, by anyone, through any route this adds. No override flag exists on the agent's path.
2. A change touching a **protected** path is merged or deployed only with the operator's approval.
3. Claude merges anything else on green CI for the exact head, and deploys it.
4. The approval is a **click** in Claude Code's own permission dialog, in the terminal or in Remote Control. It is
   never a command the operator types, and the agent cannot give it.

Harbor's register is `.agents/protected-paths.tsv`. Its `persistent-job` rows (`launchd/**`, `systemd/**`, and any
`*.plist`, `*.service` or `*.timer`) apply the standing rule that a recurring job needs the operator's explicit yes.
A change that adds or alters a job is never applied unattended; it waits in the queue for the click. That includes
the E2 dispatcher's `com.harbor.event.dispatch`. The installers that load jobs are protected as `installer` rows.

The register's tail is **derived, not kept by hand** (`bin/gate-register-derive.sh`):

- every file an installer ships into the config dir, read from the installers' own payload lists;
- every script an installer wires as a hook or statusline;
- everything those and the gate tools source or call, followed to a fixpoint.

`classify.test.sh` fails when the block is stale. It over-reaches on purpose: a script that only names another one
in a code line counts as calling it.

The classifier ignores case, so `Bin/admission-bash.sh` is protected. On a case-insensitive disk it *is*
`bin/admission-bash.sh`.

## What actually holds, and what does not

These are text rules and guards, and they stop mistakes and casual paths. They cannot stop a session that is
*trying* to get around them: it runs as the operator, with the operator's GitHub token, and a script it writes and
runs is invisible to every guard. The adversarial review of 7c23e59 (DO NOT MERGE) showed both.

- **The wall for "nothing red merges" is server-side branch protection** (required checks, `enforce_admins`). The
  account lapsed to Free on 2026-10-05 (HTTP 403); the operator re-bought Pro on 2026-10-08 and set `enforce_admins`
  plus four required checks (`conventions linter`, `conventions linter suite`, `security-floor suite`, `suites`).
- **Claude has its own GitHub identity** since 2026-10-08: the private GitHub App `harbor-claude-vytcepas`
  (contents, pull requests and issues write; actions, checks and statuses read; no workflows, no administration),
  with 1-hour installation tokens. In a Claude session (`CLAUDECODE=1`) a `gh` shim and a git credential helper use
  it; everywhere else `gh` and git are the operator's. The operator stays the author of every commit. A squash is
  authored by the PR's opener, so an App-opened squash lands as the bot (#1154); harbor's ship.conf therefore sets
  `method merge-commit` (#1160), which keeps the branch's own commits, and their author, on `main`.
- **Two installations, routed by repo owner** since 2026-10-13 (#1225): the App is public so a second organisation
  could install it, and the shim and helper pass that account to `mint-token.sh <account>` when the target is
  an owner listed in `~/.config/harbor-app/orgs.tsv` (`owner<TAB>account`; the target is `-R`,
  `gh repo <verb> OWNER/REPO`, a URL, an `api` path, else the cwd's origin). Every other owner, and a box with
  no table, keeps the default installation. The table names real organisations, so core ships none: it lives in
  the private layer as `harbor-app/orgs.tsv` and `access-github-app-install.sh` copies it. Gap: an HTTPS `git clone`
  outside a repo sends no owner; `gh repo clone` does. The three scripts live in `bin/harbor-app/`, tested by
  `tests/access/github-app/routing.test.sh`, and are installed by `bin/access-github-app-install.sh` from the operator's
  terminal. It **copies, never links**: a session can edit the checkout, and a shim that drops `GH_TOKEN` falls
  through to the operator's own login.
- **`.github/CODEOWNERS` is derived from the register** (`bin/gate-codeowners.sh`) and code-owner review is required,
  so a protected PR the App opens waits for the operator's approving review on GitHub. That holds only while the
  App, not the operator's login, opens the PR: the operator cannot approve their own PR.
- **The ancestry proof** in `gate-approve.sh` (below) is a check, not a wall. It refuses every launch shape the
  reviews tried (globs, eval, functions, scripts, aliases) and reads only system tools, so a shim earlier on PATH
  cannot lie to it (review 2 of #1127). It still runs as the operator, so a session that rewrites a user-writable
  binary the gate calls (`gh`, `jq` under Homebrew), or that skips the tool and calls `gh` from a script, is not
  stopped by it. Only branch protection stops those.
- **What is still local:** the operator's own token stays in this Mac's keychain. Settings deny rules refuse the
  obvious routes back to it (`gh auth token`/`switch`, unsetting `CLAUDECODE`, keychain reads); they are pattern
  rules, so a refusal, not a wall.
- **A deploy can now run without a terminal, but only as the runner's child.** `deploy.sh --unattended` (built
  2026-10-17 on the operator's explicit ask, after the classifier refused it twice as a weakening) is what
  `.agents/ship.conf`'s `apply` runs. A session still cannot type it: guard-bash's `deploy-raw` refuses every
  spelling, and its env checks (`SHIP_UNATTENDED=1`, an empty `$SHIP_SNAPSHOT`) are an accident gate, not a wall.

## The ancestry: how the tool proves the click launched it

Measured live on 2026-10-07 (Claude Code 2.1.290, macOS, zsh) by running a harmless script as a plain Bash-tool command:

- **The tool's parent** is the Bash-tool shell, with argv
  `/bin/zsh -c source <cfg>/shell-snapshots/snapshot-zsh-<n>-<id>.sh 2>/dev/null || true && setopt NO_EXTENDED_GLOB
  NO_BARE_GLOB_QUAL 2>/dev/null || true && { \builtin unalias -- 'unsetenv'; \builtin unset -f -- 'unsetenv'; }
  >/dev/null 2>&1 || true && eval '<the command, with each ' as '"'"'>' < /dev/null && pwd -P >| /tmp/claude-<hex>-cwd`.
- **That shell's parent** is the `claude` process, with argv `claude`. Its executable,
  `~/.local/share/claude/versions/<v>`, is signed `Developer ID Application: Anthropic PBC (Q6L2SF6YDW)`, identifier
  `com.anthropic.claude-code`.

`gate-approve.sh` requires exactly that, or it refuses:

- the parent is zsh or bash, sourcing this config dir's snapshot;
- before the command, only the measured setup steps run;
- the text inside `eval '…'` is exactly the canonical command;
- nothing runs after the command but `pwd -P >| …-cwd`;
- the grandparent is `claude`, started with none of `-p`, `--settings`, `--plugin-dir`, `--permission-prompt-tool`,
  `--dangerously-skip-permissions`, `--permission-mode`, `--allowedTools`, `--mcp-config` or `--agents`;
- on macOS that process is Anthropic's signed binary (`codesign --verify --strict` with a designated requirement). On
  Linux, its `/proc/<pid>/exe` must be under this account's `~/.local/share/claude/versions/`, which is weaker because
  that directory is writable.

What each check rules out:

- A glob, `eval`, a function, a git alias, make, `sh file`, a wrapper, a compound, or a second line changes the text
  inside `eval '…'`, or puts another process between the tool and the shell.
- A fake `claude` (`exec -a claude`) fails the signature check.
- A nested `claude -p --settings …` fails the flag check.

`tests/gate/approval/ancestry.test.sh` runs the review's 40 bypass shapes against the installed tool, in a process tree
shaped like the real one, and each check has a mutant that goes red.

The check applies only when the tool runs from this account's own `~/.claude`. A sandbox install acts with nothing a
direct `gh` call lacks, so it is not checked there.

**Limits, said plainly:**

- The shape is Claude Code's internal argv. A release that changes it makes `gate-approve.sh` refuse, which fails
  closed and names what it saw. The fix is a new measured shape here.
- A nested interactive `claude` driven through a fake terminal (`script`) would be a real, signed, flagless session.
  Its dialog could be answered by the driving script. No guard sees that when it is built in a script file.
- `gate-merge.sh` has no ancestry check. It merges nothing protected, so its routes need none.

## How a click becomes the approval

- `permissions.ask` names the **installed** `~/.claude/bin/gate-approve.sh`. An ask rule always prompts, in auto
  mode too. Neither the classifier nor a PreToolUse `allow` can override it. Under `claude -p` with no host, the
  call is denied.
- Rules match text, so they are not a boundary. guard-bash's `gate-noncanonical` rule refuses any run of a gate tool
  that is not the exact text its rule names. That covers `sh <path>`, `sh -c`, `env`, `xargs`, `find -exec`, `nohup`,
  `timeout`, a compound, `~`, `..`, another directory and the checkout copy. Copying or linking a gate tool is
  refused too.
- The tool checks this itself as well. It runs only from `<cfg>/bin`, physically, and refuses to run as a copy or
  through a symlink.
- A session cannot write `<cfg>/bin`: the B1 deny, guard-bash and guard-selfedit all refuse it. So it cannot change
  what the approved command does. The gate's files are recorded in the install manifest but not content-pinned,
  because B6 blocks every session over a pinned file with no kill-switch line.
- The rules never name a checkout or a `~/.local/bin` link, because a session can edit both.
- `merge-raw` and `deploy-raw` refuse the routes that would skip the gate inside a session. They stop mistakes; the
  wall is branch protection, above.
  - `gh pr merge`, in any argument order, and a `gh alias set` whose expansion merges, calls the API or pushes.
  - `gh api` with a write method (`-X`/`--method`, any case and spelling, or fields) on `pulls/N/merge` (with `?…` or a
    trailing `/`), `merges`, `git/refs/…` or `repos/o/r`. Also `mergePullRequest`, `enablePullRequestAutoMerge`,
    `mergeBranch`, `updateRef(s)`, `createCommitOnBranch`, and a graphql query read from a file.
  - `curl`, `wget`, `http` or `xh` writing to GitHub's REST API host.
  - `gh repo edit --default-branch`.
  - `git push` to `main`/`master` or `--all`/`--mirror`. A repo that wires its own branch guard adjudicates its branches
    (B5).
  - `gate-merge-check.sh --merge` (and so its `--force`) and `merge-stack merge`.
  - `deploy.sh --apply[=…]`, `harbor deploy|install|uninstall|skills|inject|constitution|restore --apply`, and any
    installer, `sec0-harden`, `floor-deny`, `floor-uninstall`, `restore` or `pin-instructions` run with `--live` and a
    write. A sandbox `--dir` install stays open.
  - A person in a terminal is unaffected, because guards run only on tool calls.
- `approved-raw` refuses `--approved` on the runner (`deploy-fleet.sh deploy … --approved`, `harbor ship deploy …
  --approved`) in every spelling (contract §5a.4). gate-approve.sh runs the runner as its own child, which no guard
  sees. It writes a one-shot token, `<cfg>/.helm-approvals/approved/<queue id>`, first and removes it after. The
  runner must refuse `--approved` unless that token exists, and must consume it. Only the click can write the token,
  because a session cannot write `.helm-approvals`.
- Before it acts, `gate-approve.sh` also checks these, and refuses if any fails or cannot run (jq, gh, awk or ps
  missing, or jq broken):
  - the ancestry, above;
  - the ask rule is in settings.json;
  - bypass mode is disabled;
  - there is no PermissionRequest hook at all. Harbor wires none, so its allow-list is empty and nothing is trusted by
    path prefix. That covers user, user-local, project and project-local settings, and every `.json`, `.js`, `.mjs` or
    `.ts` under `<cfg>/plugins`, `<cfg>/dev-mods` and `<cfg>/mods`, where any `PermissionRequest` or `tool.check` refuses;
  - no settings file changed after the Claude Code session started, because hooks are read at start.

## The CLI (the surface PR B builds on)

| Command | Rule | Does |
|---|---|---|
| `bin/gate-classify.sh <repo-root> [path…]` (or stdin) | none | contract §2. Prints `PROTECTED<TAB>path<TAB>class` for each protected path. Exits 0 when none is protected, 1 when one is, 2 when the manifest names an absent register. Judge both paths of a rename |
| `<cfg>/bin/gate-merge.sh <owner/repo> <pr>` | allow | The unattended merge. Refuses while the kill switch exists, and for a repo whose default branch has no `.agents/ship.conf`. The manifest and register are read from GitHub at the default branch, never from a local checkout. A protected PR is queued and its approve command printed on stdout (exit 1). Otherwise it merges through merge-stack, pinned to the head it classified |
| `<cfg>/bin/gate-approve.sh merge <owner/repo> <pr> <head-sha>` | **ask** | Merges what was clicked. The head must still be `<head-sha>`, then merge-stack merges on a plan pinned to it (`pr N head <sha>`, §5b.10): every workflow green on that head, merge-check, and `--match-head-commit`. Any other head is needs-rebase. Red is refused even when approved |
| `<cfg>/bin/gate-approve.sh deploy <owner/repo> <sha>` | **ask** | The default branch must still be `<sha>`. Then it writes the token and runs the runner: `<cfg>/bin/deploy-fleet.sh deploy <owner/repo> --sha <sha> --approved` |
| `<cfg>/bin/gate-queue.sh add <merge\|deploy> <owner/repo> <sha> [<pr>] --reason <text>` | allow | **The only queue writer** (§5b.9). It queues an approval, prints its id, and stores the exact approve command in the row. A merge takes its `<pr>` and a deploy none. Unattended code calls this and **never** gate-approve: a pending prompt stops a session until someone answers it |
| `<cfg>/bin/gate-queue.sh list [--json]` | allow | The open rows, each with the command to run |
| `<cfg>/bin/gate-queue.sh close <id> <answer>` | allow | Closes a row, for example after the operator clicked No (a refused call never runs, so it cannot close itself) |

- **Queue:** `~/.local/state/harbor/approvals/queue.jsonl`.
  - An open row is `{id, ts, kind, repo, pr?, sha, reason, command}`. A close row is `{id, ts, closed, outcome}`.
  - The id is `<kind>-<owner>_<name>[-<pr>]-<sha12>`, for example `merge-VytCepas_harbor-1123-cd8bd19a1b2c` or
    `deploy-VytCepas_harbor-cd8bd19a1b2c` (§5a.2).
  - Each open emits `approval.open` with subject = id, a 24h `deadline_ts` and a title. A completed approval, or
    `close`, emits `approval.close` (§5a.3).
  - `contracts/obligation-kinds.tsv` folds them as kind `approval`, so they count in `⧗N`. Its reconcile source,
    `approval-queue`, also closes an id the queue file closed.
- **Ledger:** `<cfg>/.helm-approvals/ledger.tsv`, one row per decision: `time, action, args, sha256(args), outcome`.
  The click's one-shot tokens live beside it in `approved/`.
- **Required checks:** each repo's own `.agents/required-checks.tsv`, read from GitHub (§5a.6). Without one,
  merge-check falls back to branch protection, and refuses when nothing gates. Harbor ships its own, a copy of its
  rows in `contracts/required-checks.tsv` that must be kept in step.
  - The actions are `merge-auto`, `approve-merge` and `approve-deploy`.
  - It is an integrity file (contracts/control-plane-state.md), so a session cannot write it.
- **Kill switch:** `touch ~/.claude/.harbor-autoship.off`. While it exists, `gate-merge.sh` refuses, and so must
  every unattended deploy (the runner checks it). An operator's approval is not unattended, so it still runs.

## What the runner (PR B) must do to match

- Be installed at `<cfg>/bin/deploy-fleet.sh` beside the gate tools. A content pin would need a kill-switch line, or
  B6 blocks every session.
- Call `<cfg>/bin/gate-classify.sh` and `<cfg>/bin/gate-queue.sh add`, by those names (§5a.1, §5b.9). It never
  appends to `queue.jsonl` or emits approval events itself.
- Refuse `--approved` unless `<cfg>/.helm-approvals/approved/<queue id>` exists for exactly this repo and sha, is younger
  than 10 minutes (it holds its UTC write time), and is deleted on use. Refuse `--approved` under `SHIP_UNATTENDED=1`.
  The age limit closes a replay of a token a killed approval left behind.
- Add its allow rule through floor-deny, like the ones below.
- Own the kill-switch check, auto-restore, no retry and the per-repo deployed sha.
  - **Keep the deployed-sha state where a session cannot write it** (under the config dir, like the ledger). A sha
    in `~/.local/state` can be moved by a session, and then a protected change would look already deployed.

## The settings lines

`admission-deny.sh` adds these, append-only, on the floor component's deploy. It writes `$HOME` expanded, because a
Bash rule matches text and the guard admits only the physical path:

```
permissions.ask:   "Bash($HOME/.claude/bin/gate-approve.sh *)"
permissions.allow: "Bash($HOME/.claude/bin/gate-merge.sh *)"
permissions.allow: "Bash($HOME/.claude/bin/gate-queue.sh *)"
permissions.deny:  "Edit(~/.claude/.helm-approvals/**)"
```

`floor-verify --live` fails when the ask rule is missing, or when a PermissionRequest hook Harbor does not own is
present in `settings.json` or `settings.local.json`.

## The PermissionRequest gap, tested live

`tests/gate/approval/permission-request-probe.sh` ran 2026-10-06 on Claude Code 2.1.292 (`claude -p`,
`--permission-mode default`, one `--settings` file per arm):

| arm | the call ran | the hook ran |
|---|---|---|
| control: an ask rule on the command | no ("Awaiting permission") | no |
| treatment: the same, plus a PermissionRequest hook answering `allow` | **yes** | yes |

**A PermissionRequest hook can answer an ask-rule prompt.** So the gap is closed by refusal: gate-approve.sh will
not act while a hook outside Harbor exists in any settings file it can see, and floor-verify reports one.

What the probe cannot prove:

- the interactive and Remote Control dialogs, which it never shows;
- a hook from a plugin, or a project dir other than the cwd and `CLAUDE_PROJECT_DIR`;
- `--settings` on the session's own command line;
- a mod's `tool.check` (#940).

## Residual risks

- **No branch protection** (above). Every route a script can take to GitHub stays open until the operator restores it.

- **Mods, until #1022.** A user mod can approve an ask prompt, and even a deny, unless managed settings forbid user
  mods (#940). The fix is #1022's managed-settings lockdown, one `sudo` by the operator. This PR cannot close it.
- **`sudo`, after #603.** Once the floor moves under `sudo`, a protected deploy needs `sudo`, which a click cannot
  give.
- **Indirection no text guard sees.** A script the session writes and then runs (`sh /tmp/x.sh`) can call
  `gh pr merge` or a copy of a gate tool. The guards read command text, not file contents. The auto-mode classifier
  and the gate tool's own path check are the remaining walls.
- **Settings the tool cannot see.** These are a PermissionRequest hook passed with `--settings` at launch, one in a
  project dir that is neither the cwd nor `CLAUDE_PROJECT_DIR`, and a plugin hook outside `<cfg>/plugins`. Proposed
  next: a guard rule refusing any write of a `PermissionRequest` key into a settings file.
- **The register on a box that never deploys.** The gate reads the register from GitHub, so it follows merges at
  once. The installed tools change only when the floor is deployed.

## Gates this changes

- **guard-bash:** the four new rules above. Before this, a session's `gh pr merge` on a green PR reached the
  classifier. Now the floor refuses it, and `gate-merge-check.sh --merge --force` cannot be reached from a session.
- **floor-deny:** adds `permissions.ask`, two `permissions.allow` entries and one deny. The sec0 baseline pin covers
  `permissions` whole, and floor-deny re-pins after it writes.
- **floor-install / floor-uninstall:** install and remove the gate's files. Uninstall also removes the gate's ask and
  allow rules, which name the files it deletes.
- **floor-verify:** two new FAIL conditions.
- **merge-stack:** unchanged. Every gate merge goes through it, installed beside the gate tools. The plan's
  `checkout` is the gate's own temp tree of what GitHub holds on the default branch (the manifest, the register and
  `.agents/required-checks.tsv`).
- **status-obligations:** a new kind `approval` (`approval.open` / `approval.close`) and a new reconcile source,
  `approval-queue`. Every other kind folds as before.
- **naming registry:** `ship` changes from a legacy alias of `workload` to a codename. It is allowed on path, env,
  check-id and command (§5a.8).
- **deploy.sh `--unattended`: built in a later PR** (harbor#1018, 2026-10-17), to contract §6's narrow exception.
  It is a usage error without `--apply`, without `SHIP_UNATTENDED=1`, or without `$SHIP_SNAPSHOT` naming an empty
  file, and with `--uninstall`, `--prune` or `--accept-loss`. It skips the in-session refusal and the install
  `[y/N]`, writes the snapshot path to `$SHIP_SNAPSHOT` before the first install, and answers No to every other
  question: the restore stays the runner's (`restore`), and the B8 re-pin stays the operator's. B8 drift is an
  advisory in `floor-verify`, so a declined re-pin does not roll a deploy back. The terminal path is unchanged.
  The flag is kept out of every printed fix, so no fix line hands a person a flag they cannot use. The cases and
  their mutants: `tests/deploy/deploy/deploy.test.sh`, section `--unattended`.

## Recorded on #1018

\#1018 designed an org-tier mod. The operator chose the native `ask`-rule mechanism instead (2026-10-06). The click
therefore no longer waits on #1022. The mod risk stays as the first residual above.
