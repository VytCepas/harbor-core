# Your hub

The company's Harbor hub (harbor#1278). Members read the signed `policy.json` from here; their very-high requests and heartbeats land in this repo's Issues.

Everyone with access to this repo, members included, can read all of it: the policy, every issue and every event. Nothing private belongs here.

## What is in it

| Path | What |
|---|---|
| `policy.json` | The signed policy (the format is `contracts/hub.md` in harbor-core). Starts in `shadow`: it records and enforces only integrity. |
| `policy.json.sig` | Its signature, made with the hub key. Absent until you sign: an unsigned hub fails the gate and no laptop would take it. |
| `hub-signers` | The public half of the hub key. Absent until you add it. |
| `packs/<id>/` | Hub packs you reviewed. Empty to begin with. |
| `CODEOWNERS` | Puts the policy, key and workflows under the admins. |

The workflows are not here. They are patches an operator applies by hand (`patches/hub/` in harbor), because an agent may not write `.github/workflows`.

## First day

1. Replace the starter values in `policy.json`: `hub`, `core.commit` (a harbor-core commit you tested), `approval.approvers` (admin logins), `issued`.
2. Make the key and sign. The private key never enters this repo.

   ```sh
   ssh-keygen -t ed25519 -N '' -C hub -f hub-key
   printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 hub-key.pub)" > hub-signers
   ssh-keygen -Y sign -f hub-key -n harbor-hub policy.json
   ```

   Keep `hub-key` (and put `hub-signers` where IT installs it on laptops). Commit `policy.json`, `policy.json.sig`, `hub-signers`.
3. Every later change to the policy: raise `serial`, set `issued`, sign again.
4. Run `sh bin/hub-gate.sh <this folder>` from a harbor checkout before you push.

The full walk-through, including roles, notifications and what to tell staff, is `docs/how-to/hub-admin.md` in harbor.
