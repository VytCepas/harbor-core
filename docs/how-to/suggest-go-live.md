---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Take suggestions live

Turns on the session-start pointer that tells the agent how a person stops a suggestion (harbor#1485). The pack ships in shadow: it ticks the counter and nobody sees the pointer. The per-call suggestion rule was retired on 2026-11-27 (U6, 2026-11-27): no rule shows a person a line today. Run the steps in order on the box that will go live.

## Before you start

- Three days have passed in shadow on this box. `sh bin/admission-observe-report.sh --shadow` lists what would have spoken.

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

## 3. Check the confined stop

Ask the agent to run these in a confined session, without leaving the sandbox:

```sh
sh <config>/bin/status-suggest.sh stop go-live-check --origin agent
sh <config>/bin/status-suggest.sh status --json
sh <config>/bin/status-suggest.sh start go-live-check --origin agent
```

It passes when each command exits 0 and `status --json` lists `go-live-check` under `stopped`. An exit of 1 that says `cannot write` means the write row is missing: repeat step 1. One that says `refused` means the tool found a link or a stray file in the state folder and touched nothing: see what put it there, then delete that one entry.

## 4. Flip the switch

1. In a PR, change `context.suggest-start` in `standards/naming/controls.tsv` from `shadow` to `warn`.
2. Run `sh bin/standard-vendor.sh .`, which refreshes the vendored copy, and commit it.
3. Merge the PR, then install the new register from the updated checkout:

```sh
harbor deploy --only runtime --apply --live
```

## 5. Confirm it

In a new Desktop session, the agent is told the stop route once. `sh bin/admission-observe-report.sh --advise` then lists `inject/suggest-start`.

## Going back

A person turns everything off with **turn off** in the pane, or by telling the agent. For the whole box, put the row back to `shadow` the same way as step 4.
