---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Remote support

How a colleague gets help on their laptop from an admin, with their say-so at every step. The format is in [contracts/hub.md](../../contracts/hub.md), "Remote support".

## If you are asking for help

1. Open **Harbor Support** from the Start Menu. On Linux, run `sh <managed root>/bin/member-support.sh` in a terminal.
2. Read what it says, type what you need (`update`, `fix` or `question`), then type `allow`.
3. Keep the window open. Your admin has been told.
4. When your admin accepts, you see their name. You are asked `Start the session?`. Press `y` to let them in, or `n` to stop.
5. Watch the window. Everything they type appears there as it happens.
6. To end it at any moment, close the window.

### What your admin can see and do

- They work as you, on your account, so **they can read and change anything your account can**: your files, your documents, anything saved under your name. Close anything private first.
- They can't change the company's safety settings. Those belong to the computer, not to your account.
- If they start `claude` in the session, it runs under the same company limits as yours.
- It ends when you close the window, or at the time limit, which you are told at the start.

### What to keep in mind

- The session travels through your company's own support service, and **that service can read what passes through it**. Don't put a password on the screen.
- Anything they start in the session runs as you, and could keep running after it ends. If you didn't see them finish something, ask.
- Nothing listens on your computer until you start this, and nothing stays after it ends: there is no background service and nothing starts by itself.
- Claude can't start this for you, and can't reach the session. It has to be you.

## If you are the admin

You need your own `gh` login, `upterm` at the version in `contracts/support-upterm.tsv`, a key listed in policy, and the company's own relay running (below). Support is off until that relay exists.

### Turn it on

Run the relay first ("Run the relay", below). Then add a `support` key to `policy.json`, and `harbor hub sign`:

```json
"support": {"keys": ["ssh-ed25519 AAAA... you@laptop"], "relay": "wss://relay.example.com",
            "relay_key": "ssh-ed25519 AAAA...", "max_minutes": 60}
```

No `support` key, or one with no `relay` and `relay_key`, means off, and the person is told so in plain words. There is no default relay, and upterm's public one is refused by name. Each line of `keys` is a plain public key, with no options. Any listed key can join a session a person has said yes to, so list only the people who answer these.

### Answer a request

```sh
harbor hub support list --hub owner/name           # who is asking, and why
harbor hub support accept <id> --hub owner/name    # your own gh; the person is asked next, on their own screen
harbor hub support connect <id> --hub owner/name --key ~/.ssh/your-key
```

`connect` works once the person has said yes. Run it in a terminal of your own: it refuses inside Claude Code. `~.` leaves. `HARBOR_HUB_REPO` saves typing `--hub`.

Your acceptance counts only as an approval would: your login in the signed `approval.approvers`, the comment never edited, within `approval.ttl_hours`, on an open request. Someone with only the member's token can't accept.

### What you are trusted with

- You see whatever the member's account can read.
- The session runs as the member, so it can't change the root-owned floor, and a `claude` you start there runs under the managed limits. It isn't a way to do admin work on the laptop: that stays with IT.
- `--no-exec`, `--no-sftp` and `--no-forwarding` are on, so everything goes through the terminal the person is watching. You can't run a command, copy a file or forward a port beside it.
- The board records that a session happened and how it ended, never what was typed.

### The relay

Support runs only through a relay the company runs itself, decided by the operator on #1278 (2026-11-07), replacing upterm's public relay. Know what a relay is trusted with, because the reason holds for any relay:

- **It reads all session traffic.** upterm's relay ends each guest's SSH connection and opens its own to the laptop, so terminal text passes through it in the clear. A relay someone else runs could read client data.
- **It vouches for guests.** The relay tells the laptop which key a guest holds, so a dishonest relay could claim a listed key and join a session the person said yes to.
- **It answers for its own uptime.** If it is down, support is down.

The public relay's host, `public-relay` in `contracts/support-upterm.tsv`, stays in every member's `sandbox.network.deniedDomains` for good, and policy can't name it.

### Run the relay

`relay/` holds what runs it on a small Linux VM: `install.sh`, which installs `uptermd` at the digest pinned in `contracts/support-upterm.tsv` and refuses anything else; `relay.service`, which runs it under systemd as a dynamic, unprivileged user that can reach loopback and no other address, with the host key passed in as a credential; `relay-settings.txt`, uptermd's settings, every listener on loopback; and `proxy.txt`, the Caddyfile that puts TLS on 443 in front of uptermd's websocket listener. Only 443 (and 80, for the certificate) face the internet, because companies often block port 22.

The operator's steps, in order. Each runs in the operator's own terminal; nothing here runs them. The names `harbor-relay`, `relay.example.com`, `PROJECT`, the region and the zone are placeholders to replace.

1. Reserve an address and create the VM (Ubuntu 24.04 on a small machine type):

   ```sh
   gcloud compute addresses create harbor-relay --project PROJECT --region europe-west1
   gcloud compute instances create harbor-relay --project PROJECT --zone europe-west1-b \
     --machine-type e2-small --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud \
     --address harbor-relay --tags harbor-relay --shielded-secure-boot
   ```

2. Open 443 for laptops, and 80 for the certificate:

   ```sh
   gcloud compute firewall-rules create harbor-relay-web --project PROJECT \
     --allow tcp:443,tcp:80 --target-tags harbor-relay --source-ranges 0.0.0.0/0
   ```

3. Point the relay's name at the address, in the company's DNS. The address is:

   ```sh
   gcloud compute addresses describe harbor-relay --project PROJECT --region europe-west1 --format 'value(address)'
   ```

4. Install. From a harbor checkout, copy `relay/` and the pin, then run the install as root on the VM:

   ```sh
   gcloud compute scp --project PROJECT --zone europe-west1-b --recurse relay contracts/support-upterm.tsv harbor-relay:~/
   gcloud compute ssh harbor-relay --project PROJECT --zone europe-west1-b -- \
     'cp ~/support-upterm.tsv ~/relay/ && sudo sh ~/relay/install.sh --host relay.example.com'
   ```

   It installs Caddy from Ubuntu's archive, lands uptermd, makes the host key once, and starts `harbor-relay.service` and Caddy. Run it again to move the version: the host key stays.

5. Read the relay's key, over the same authenticated connection:

   ```sh
   gcloud compute ssh harbor-relay --project PROJECT --zone europe-west1-b -- 'sudo sh ~/relay/install.sh --key'
   ```

   The first line is `relay_key`; the second is its fingerprint, to compare if you read it any other way.

6. Put the relay and its key in `policy.json`, with the admins' keys, as in "Turn it on" above: `"relay": "wss://relay.example.com"`, `"relay_key": "<the first line>"`.

7. Sign it: `harbor hub sign policy.json --key <the hub signing key>`, and push the signed pair to the hub repo.

8. The relay's host goes into the managed settings, so the agent's shell can't reach it. Those are composed again by the updater after each update it applies, if IT scheduled it, or else when IT runs the member install again on the laptop. Until then support refuses to start there and says so.

What this leaves open: uptermd lets any client register a session, because a laptop makes a new key for each session and so can't be listed in advance (`uptermd --authorized-keys`). A stranger can't join a member's session, but can use the relay's bandwidth. A new host key means a policy re-sign and every laptop's install again.

### If it won't start

| The person sees | What it means |
|---|---|
| Remote support is not turned on | No `support` key in the verified policy |
| Remote support is off until your company runs its own support service | The `support` key names no `relay` and `relay_key`. Run the relay, then put both in policy |
| The company settings on this computer could not be read | Among other causes, a policy naming upterm's public relay: `hub-format.sh` refuses it |
| The support program is not installed | The install hasn't landed `upterm`. Run it again. macOS isn't covered: only Linux and WSL have a pinned binary |
| Remote support moved to a new service | The relay in policy isn't in this laptop's `deniedDomains`. Run the updater or the install again |
| This can only be started by you, outside Claude Code | It was started from a Claude Code session |
| No admin answered in time | Thirty minutes passed. The request is closed; ask again |

A check of the whole path against real binaries: `sh tests/member/support/real-upterm.sh`. It runs the relay as `relay/install.sh` lays it out, from its unit's own command line and settings file, checks the unit with `systemd-analyze verify`, and carries a session over the websocket listener. TLS through Caddy and the unit's sandboxing under a real systemd are in `sh tests/member/support/sim-relay.sh`: in docker, a box with systemd as PID 1 runs "Run the relay" step 4 as written, and a second box is the laptop and the admin, through Caddy on 443. It needs docker, as this one does; the relay's name ends in `.local`, so Caddy takes its own CA rather than ACME, and the laptop trusts that CA.
