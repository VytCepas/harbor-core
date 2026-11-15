# gh verbs — which `gh` command shapes the agent runs, and which are the operator's

One register per CLI under `contracts/verbs/` (harbor#1419), the same row shape as `git.md`. This one is `gh`:
inside a Claude Code session `gh` acts as the harbor-claude GitHub App (the shim in `bin/access-github-app/gh`), so
some shapes are refused by GitHub or by the classifier for who is asking, not for what they do. The register says
which, so a planner hands those over instead of discovering the refusal in the operator's terminal.

**Nothing restates these rows.** `bin/admission-deny.sh` builds the `permissions.allow` and `permissions.ask` rules
from the rows marked `allow` and `ask` (through `bin/gate-verbs.sh rules`, via `il_verbs` in
`bin/deploy-install-lib.sh`), and `bin/admission-remove.sh` takes the same rules back out.
`tests/admission/verbs/registers.test.sh` fails when a row and its derived rule disagree.

**Who runs a command — the planner's reader.** `sh bin/gate-verbs.sh --actor gh <verb> [args]` prints
`operator` or `app` for the command (exit 0), and `unknown` with exit 3 when no row matches. The longest matching
spelling wins and `operator` wins a tie. `bin/gate-pr-plan.sh` can call it per step to know which steps are the
operator's: `sh bin/gate-verbs.sh --actor gh pr merge 12 -R <owner/repo> --squash` prints `operator`. An `own-org` row
depends on the owner: `--actor gh pr ready 5 -R <owner>/<repo>`, or `--actor --owner <owner> gh pr ready 5`, prints
`app` when the owner is the App's own org (the owner of this checkout's repo slug, or `HARBOR_GATE_VERBS_OWN_ORG`) and
`operator` for any other; with no owner to read it prints `owner?` and exits 4.

## Columns

| Column | Values |
|---|---|
| spelling | The shape in permission-rule syntax: `*` is any text, `<x>` an argument you supply. An `allow` or `ask` row's spelling **is** the rule, so it has no `<x>` and starts `gh <subcommand>`. |
| class | `read`, `write`, or `gated`: refused or held for a person by design. |
| perm | `builtin`: Claude Code already treats it as read-only. `allow`: an allow rule derived from this row. `ask`: an ask rule, always a person. `deny`: a deny entry. `classifier`: no rule, so auto mode's classifier judges it, and outside auto mode it prompts. |
| actor | `app`: the in-session `gh` (the App) may run it, in any org. `own-org`: the App may run it on a repo of its own org and is refused on another org's repo (measured: `pr ready` on another org's repo was refused by the classifier), so there it is the operator's. `operator`: the App is refused in every org, so the operator runs it with their own `gh` (`/opt/homebrew/bin/gh`). |
| instead | What to do when the shape is not yours, or why the row is the way it is. |

## Reads: free

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gh pr list *` | read | allow | app | |
| `gh pr view *` | read | allow | app | |
| `gh pr diff *` | read | allow | app | |
| `gh pr status *` | read | allow | app | |
| `gh pr checks *` | read | allow | app | |
| `gh issue list *` | read | allow | app | |
| `gh issue view *` | read | allow | app | |
| `gh issue status *` | read | allow | app | |
| `gh run list *` | read | allow | app | |
| `gh run view *` | read | allow | app | |
| `gh run watch *` | read | allow | app | blocks until the run ends; it only reads |
| `gh workflow list *` | read | allow | app | |
| `gh workflow view *` | read | allow | app | |
| `gh release list *` | read | allow | app | |
| `gh release view *` | read | allow | app | |
| `gh repo view *` | read | allow | app | |
| `gh repo list *` | read | allow | app | |
| `gh label list *` | read | allow | app | |
| `gh search prs *` | read | allow | app | |
| `gh search issues *` | read | allow | app | |
| `gh search repos *` | read | allow | app | |
| `gh search code *` | read | allow | app | |
| `gh auth status *` | read | allow | app | |
| `gh status *` | read | allow | app | |

## Everyday writes

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gh pr create *` | write | allow | own-org | |
| `gh pr edit *` | write | allow | own-org | retargeting a base is the App's too, on its own org's repos |
| `gh pr ready *` | write | allow | own-org | |
| `gh issue create *` | write | allow | own-org | |
| `gh issue edit *` | write | allow | own-org | |
| `gh pr comment *` | write | classifier | own-org | |
| `gh issue comment *` | write | classifier | own-org | |
| `gh pr review *` | write | classifier | own-org | a comment or a request for changes; an approval is gated below |
| `gh pr checkout *` | write | classifier | app | writes the working tree and a local branch |
| `gh pr reopen *` | write | classifier | own-org | |
| `gh issue reopen *` | write | classifier | own-org | |
| `gh run download *` | write | classifier | app | writes files to the working directory |
| `gh run cancel *` | write | classifier | own-org | |
| `gh workflow run *` | write | classifier | own-org | |
| `gh api *` | write | classifier | app | no allow rule: `-X`, `-f` and `--input` make any call a write; read with the verbs above |

## Gated: the operator's

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gh pr merge *` | gated | classifier | operator | merges are the operator's: run the merge backstop first, then merge pinned to the head with `--match-head-commit` |
| `gh pr review * --approve*` | gated | classifier | operator | the App cannot approve; a second person must |
| `gh pr review --approve*` | gated | classifier | operator | as above, flag first |
| `gh pr close *` | gated | classifier | operator | |
| `gh issue close *` | gated | classifier | operator | |
| `gh run rerun *` | gated | classifier | operator | the App is refused re-runs, so a failed run is re-run by the operator |
| `gh pr update-branch *` | gated | classifier | own-org | in another org's repo the App is refused, so the operator runs it; in the App's own org it is the App's step, as `bin/gate-pr-plan.sh` plans it |
