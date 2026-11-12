---
name: member-setup
description: "Adopt Harbor in an organisation: hub repo, signing key, pinned harbor-core, a setup zip per colleague, releases. USE WHEN onboarding a company or colleague, building a setup zip, raising the hub pin. NOT FOR a project's own CI."
---

# member-setup — Harbor for an organisation

> **Path root:** `~/port/harbor` — every `./`-prefixed path resolves there.

## Ideal end state

- The organisation has a private hub repo with a signed `policy.json` whose `core.commit` is a commit of `harbor-core` that was tested on a pilot laptop.
- Every colleague has a laptop on that pin, with the managed root installed and the member token stored.
- A release reaches them by this chain and no other: merge in harbor, export to harbor-core, merge the export PR (that commit is the pin), raise the hub pin, sign, rebuild the zips.

## Start here

- [./docs/how-to/adopt.md](../../docs/how-to/adopt.md) — the three repos, the setup order and the release flow. Read it first.
- `sh ./bin/hub-pin-upgrade.sh --help` — raises the hub pin on a branch. It refuses a pin not on harbor-core main, a dirty hub, a contract change. It stops before signing.
- `sh ./bin/member-setup-generate.sh --help` — rebuilds every person's setup script, hash and zip at a pin, from the admin's private roster.
- Deeper: `./docs/how-to/hub-admin.md`, `./docs/how-to/member-install.md`, `./docs/how-to/member-support.md`.

## Limits that hold

- **Signing is the admin's alone.** Never sign, never ask for the passphrase, never touch the key. Hand the admin the printed lines.
- Nothing names a person, company or login in the repo. The roster stays private and outside every repo.
- Pushing, merging and sending a zip are the operator's to approve each time.
- A colleague never runs harbor's CI or tests.
