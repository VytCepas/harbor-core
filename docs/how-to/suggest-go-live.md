---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Take suggestions live

Turns on the one plain line a person sees when Harbor has a better way for a job (harbor#1485). Both packs ship in shadow: they record, and nobody sees a line. Run the steps in order on the box that will go live.

## Before you start

- `context-rules/user/suggest-tool.tsv` holds the jobs the operator named. It ships with no rows, so nothing can fire until then.
- `sh bin/eval-suggest-replay.sh --days 14` shows no false match for any row.
- Three days have passed in shadow on this box. `sh bin/admission-observe-report.sh --shadow` lists what would have spoken, as `inject/suggest-tool-<row>`.

Company rows are not part of this: nothing reads them yet, and their delivery lands with harbor#1278.

## 1. Run the two root commands

An admin runs these once at install, and again at each panel upgrade.

```sh
sudo sh bin/scope-managed-mods.sh
sudo sh bin/deploy-confinement.sh
```

The first puts the Harbor pane where a managed mod loads from. The second lets a confined session write the state folder, `~/.local/state/harbor/suggest`. Start a new session afterwards.

## 2. Check the Desktop app

In the Code tab of the Desktop app, in a new session:

1. Type `/status-pane`. The Harbor pane opens with a Suggestions section. Press **scan**: it lists up to three candidates, or says no repeated job was found.
2. Ask the agent to print `CLAUDE_CODE_ENTRYPOINT`. If it is not `claude-desktop`, change `surface_can_load` in `context-rules/user/suggest-tool.sh` to the value you saw, through a PR. Until it matches, intro and mod rows stay silent.

## 3. Check the confined stop

Ask the agent to run these in a confined session, without leaving the sandbox:

```sh
sh <config>/bin/status-suggest.sh stop go-live-check --origin agent
sh <config>/bin/status-suggest.sh status --json
sh <config>/bin/status-suggest.sh start go-live-check --origin agent
```

It passes when each command exits 0 and `status --json` lists `go-live-check` under `stopped`. An exit of 1 that says `cannot write` means the write row is missing: repeat step 1. One that says `refused` means the tool found a link or a stray file in the state folder and touched nothing: see what put it there, then delete that one entry.

## 4. Flip the switch

1. In a PR, change `context.suggest-tool` and `context.suggest-start` in `standards/naming/controls.tsv` from `shadow` to `warn`.
2. Run `sh bin/standard-vendor.sh .`, which refreshes the vendored copy, and commit it.
3. Merge the PR, then install the new register from the updated checkout:

```sh
harbor deploy --only runtime --apply --live
```

Table rows travel with the packs, so a PR that also changes rows needs `--only runtime,inject`.

## 5. Confirm it

In a new Desktop session, do a job that has a row. One line appears, once, and the pane's Suggestions section shows it as the last line shown. This is the check that a Desktop session displays the line; no test can make it for you. `sh bin/admission-observe-report.sh --advise` then lists `inject/suggest-tool-<row>`.

## Going back

A person turns everything off with **turn off** in the pane, or by telling the agent. For the whole box, put both rows back to `shadow` the same way as step 4.
