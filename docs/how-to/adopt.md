---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Adopt Harbor in an organisation (harbor#1278)

The start page for the admin of a company that wants every colleague's laptop to run Harbor inside limits the agent can't change. Read this first. The other pages go deeper.

## The three repos

| Repo | Public? | What lives there |
|---|---|---|
| `harbor` | no, the development source | the code, the suites, CI, the release tools. Colleagues never touch it |
| `harbor-core` | yes | the export of `harbor` that laptops install from. A commit of it is the **pin** |
| `<org>/<hub-repo>` | no, the organisation's own | the signed `policy.json`, `hub-signers`, the packs, and the board (Issues) |

```
  harbor  --(harbor deploy push: one snapshot, gated)-->  harbor-core
                                                              |
                                          merge the export PR = the pin
                                                              v
  admin laptop: signing key  --signs-->  <org>/<hub-repo>/policy.json
                                              (core.commit = the pin)
                                                              |
                    laptops read it at session start; the setup zip installs the pin
                                                              v
                         colleague laptop (managed root + the law)
```

## What lives where

- **The signing key** is with the admin only. Never in a repo, never on a laptop.
- **`hub-signers`** is the public half. It is in the hub repo and also on each laptop, root-owned.
- **On a Windows laptop** the managed root is `C:\Program Files\ClaudeCode`. The law is there.
- **Inside WSL** the same law is also at `/etc/claude-code/CLAUDE.md`.
- **The roster** (who gets a setup: Linux user and GitHub login) is the admin's private file. It is in no repo.

## Setup, in order

1. **Organisation and hub repo.** Create a private repo owned by the organisation and let colleagues read it. [hub-admin.md](hub-admin.md), sections 1 and 2.
2. **The key.** Make the signing key with a passphrase and `hub-signers`. [hub-admin.md](hub-admin.md), section 3.
3. **The policy.** Edit `policy.json` from the scaffold in `templates/hub/`, set `core.commit` to a harbor-core commit, sign it, merge it. [hub-admin.md](hub-admin.md), section 4.
4. **One setup zip per person.** `sh bin/member-setup-generate.sh --help`. It uses the pin's own `member-windows.sh`, so the script is the code the laptop will run. Send the zip, then its hash in a second message.
5. **The colleague opens the zip in Claude Code.** The folder holds the instructions the agent follows. The person only answers its questions.
6. **IT finishes the token.** The member's GitHub token is made with the person present. [member-install.md](member-install.md).

Support afterwards: [member-support.md](member-support.md). Law of the member laptop: `contracts/member-law.md`.

## Release flow

1. Merge in `harbor`.
2. `sh bin/deploy-push.sh <clone of harbor-core>` writes one snapshot commit on an export branch. Push it and open the export PR.
3. Merge the export PR. Its merge commit on `main` is the new **pin**.
4. `sh bin/hub-pin-upgrade.sh --pin <sha> --hub <hub checkout> --core <core checkout>` raises the pin on a branch and stops.
5. **The admin signs**, verifies, pushes and merges the hub PR, and raises the hub's `HARBOR_HUB_CORE_SHA` variable. Nobody else signs. The script prints the lines.
6. `sh bin/member-setup-generate.sh --pin <sha> ... --roster <private roster>` rebuilds every zip. Send the zips that changed.

Laptops pick up the new policy at their next session. The floor code changes only when the updater runs or IT reinstalls ([hub-admin.md](hub-admin.md), section 4).

## What colleagues never run

- **Not harbor's CI or tests.** The pre-push gate is local to the development repo. A colleague has no clone of it.
- **`member-update.sh` runs git with hooks off,** so no repo hook runs from a fetched tree.
- **Hub packs skip the leak and gitleaks gates on a laptop** (`bin/pack.sh`, R21). Those gates run in the hub's own CI, before the admin signs.

## Which page when

| You want to | Page |
|---|---|
| run the hub, keys, roles, the board | [hub-admin.md](hub-admin.md) |
| set up one laptop | [member-install.md](member-install.md) |
| help a colleague remotely | [member-support.md](member-support.md) |
| know what binds a member | `contracts/member-law.md`, `contracts/hub.md` |
