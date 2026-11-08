---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Set up a member laptop (harbor#1278)

For IT. One setup per laptop, for one named person who is **not** an administrator. Afterwards the agent on that laptop works inside limits it can't change. Format: `contracts/hub.md`.

**This holds only if the member is not an administrator.** An administrator can edit the managed source itself, so the install refuses a member in `sudo`, `admin`, `wheel` or `root`, in a group that is root by another name (`docker`, `lxd`, `incus`, `incus-admin`, `libvirt`, `libvirtd`, `microk8s`, `disk`: `MEMBER_ROOT_GROUPS` in `bin/member-install.sh`), and a member with any sudoers grant of their own. The one line it allows is its own prerequisites rule, from an earlier run. On WSL the first user is in `sudo` by default: `deluser <member> sudo` first.

**Sandboxed commands reach a list of hosts and nothing else.** Data can still leave to a listed host, and there the text guards are all that's left. See [The network](#the-network) before a laptop holds anything that matters.

## What you need before you start

**From the hub admin:**

- the hub repo as `owner/name`
- the `allowed_signers` file holding the signing key
- the pin: a 40-character commit of `harbor-core`. The same value as `core.commit` in the hub policy

**A pin must exist in `harbor-core`.** The member installs from the public export, not from harbor. A commit reaches it only through an export, so a new pin or a hotfix needs an export first.

**On GitHub, once per hub (the admin):**

1. The hub repo is private and owned by an **organisation**. A personal account can't issue the narrow token.
2. Each member is a full org member, at repo role **Read**. Not an outside collaborator, who can't use a fine-grained token. Not Write, which would make them an admin of the hub.
3. Admins hold Write or above, and are listed in signed `approval.approvers`.
4. The organisation allows fine-grained tokens. If it requires approval, a token stays `pending` until an owner approves it.

**On GitHub, per member (the member, with you beside them):**

Create a fine-grained token: resource owner the organisation, repository the hub only, permissions **Issues: read and write** and **Contents: read**. GitHub ties a token to the person who made it, so nobody can make it for them. Note its expiry date: when it lapses, very-high calls stay denied and the board goes quiet.

**On the Claude side (an Owner, in the admin console):**

- Check that **Managed settings** is empty, or carries this policy. A server-managed policy outranks everything below and can't be seen from the laptop before sign-in.
- Turn **Cloud sessions** off, or accept that they sit outside this floor: a device file doesn't reach them.

## macOS and Linux

Copy `bin/member-bootstrap.sh` and the signers file to the laptop, then:

```sh
sudo sh member-bootstrap.sh --pin <commit> --user <member> --hub <owner/name> --login <github login> --signers <file>
```

It asks nothing. It clones `harbor-core` at the pin into `/opt/harbor-core`, installs the prerequisites, writes the managed root and settings, and installs the user tier as the member.

## Windows, with WSL2

1. Install Claude Desktop, version 1.37937.0 or later.
2. On any machine with this repo, print the laptop's script:

   ```sh
   sh bin/member-windows.sh --setup --pin <commit> --user <member> --hub <owner/name> --login <github login> --signers <file> > harbor-setup.ps1
   ```

3. Copy `harbor-setup.ps1` to the laptop. In PowerShell **as administrator**: `powershell -NoProfile -ExecutionPolicy Bypass -File harbor-setup.ps1`.

It asks nothing. It installs WSL and Ubuntu when they are absent, creates the member's Linux user and makes it the distro's default user, then runs the bootstrap inside as root. That stops with exit 3 because root in the distro can't write `C:\Program Files`, which is the point, so the script runs the Windows half itself: the floor under `C:\Program Files\ClaudeCode`, then the settings, then `HKLM\SOFTWARE\Policies\Claude\disableWslSessions` set to 0. It runs the bootstrap again, which reads the Windows folder back byte for byte and carries on, then adds the two desktop shortcuts.

**A first WSL install can need a restart.** The script then exits 3010 and says so: restart Windows and run the same script again. Nothing is lost.

The member's default user matters: a distro with none runs sessions as root, where none of this holds. If `/etc/wsl.conf` already names another default user, the script stops.

If a device refuses WSL sessions: Help > Troubleshooting > Show Logs in File Explorer, then search `main.log` for `[wslPolicyGate] denying WSL session`.

## The network

A member's sandboxed commands reach a list of hosts and nothing else: `MEMBER_NETWORK=allowlist` in `bin/member-managed.sh`, the default by the operator's decision on #1278 (2026-11-07). The list is three parts, composed at install into `sandbox.network.allowedDomains`:

1. `contracts/confinement-hosts.txt`, core's: GitHub, PyPI, the Anthropic API.
2. `contracts/member-hosts.txt`: what normal work needs beyond that, each host under a comment naming its purpose. npm and Yarn, Node.js, Ubuntu's mirrors, GitHub's release and archive downloads. Hosts anyone can publish arbitrary content to, such as `raw.githubusercontent.com`, are left out.
3. Signed policy `hosts`: the hosts this company adds (contracts/hub.md).

`allowManagedDomainsOnly` stays on, so no lower settings file adds a host. The WebFetch tool isn't sandboxed: it follows its permission rules, which hold no allow rule here, so a site is asked about or refused rather than fetched silently, and the managed hook still runs first.

**Why not an open network.** `open`, the other value, composes a managed `WebFetch(domain:*)` that lets sandboxed commands reach any host. It was the default until 2026-11-07 and was reversed because it made the sandbox no wall: `deniedDomains` matches host names only, so with everything else open an agent reaches any host by its IP address, or opens a tunnel, and anything it can read can leave. Setting `open` again is a one-line core commit, and that is the trade it buys back.

### If a site is blocked

A command that needs a host not on the list fails to connect, and the agent says so. The person tells their admin which site it was and what they were doing, through the board or however the company asks for help. They can't add it themselves, and neither can the agent.

The admin adds the host to `hosts` in `policy.json`, then `harbor hub sign`:

```json
"hosts": ["pypi.example-company.com", "*.internal.example-company.com"]
```

Each entry is one host name in lower case, with at most one leading `*.`. A bare `*`, a `*.` over a top-level name such as `*.com`, and any row that would admit a support relay are refused when the policy is checked.

**A new host reaches a laptop when the settings are composed again**, never from a session, which can't change them:

- the install does it after the first policy verifies, so a first install applies the hosts and relay that policy names in the same run
- the updater does it after every update it applies, if IT has scheduled it (`templates/member/`)
- otherwise IT runs the install again on the laptop

Until then the host stays blocked there, even though the signed policy lists it, and the install says so. On WSL the settings sit under `C:\Program Files`, which root in the distro may not be able to write (W4): there the install asks for the PowerShell again, and the updater keeps the old file and says so.

Hosts are read only from a copy root verified itself, and never from a policy whose serial is below the last one applied (`pin.serial` in the managed root).

## Prerequisites

Harbor installs what it needs. The list is `contracts/member-prereqs.txt`, and the install and the session both read it.

`bin/member-prereqs.sh` is root-owned and takes no arguments. It installs that list and nothing else: an argument, a changed list or anything but a plain package name is refused. `/etc/sudoers.d/harbor-member-prereqs` lets the member run exactly that command with no password. At SessionStart, `member-session.sh` calls it when a command on the list is missing. A failure never holds the session: it says so in the session note, and an install still running after 90 seconds is left to finish.

macOS has no package manager to call, so there is no rule there and a session doesn't look: the install checks its tools, and they stay IT's.

## Where work starts

Work belongs in `~/port`. The docs say a WSL session starts in the home folder, and name no setting to change it: `startDirectory` exists for SSH connections only. So:

- the install creates `~/port`, and managed `permissions.additionalDirectories` makes it a working directory from anywhere
- an interactive shell that starts in the home folder moves to `~/port`, through `/etc/profile.d/harbor-member.sh`. A shell opened anywhere else stays where it is
- the **Harbor setup** and **Harbor support** shortcuts on the desktop use `wsl.exe --cd`
- a session that opens in the home folder is told in its context to work in `~/port`

Show the member once: in the session's folder picker, choose `~/port`. Whether Desktop remembers that folder is W10.

## The token

With the member beside you:

```sh
printf '%s' '<token>' | sudo sh /opt/harbor-core/bin/member-install.sh --user <member> --token-stdin
```

Paste it from their browser, and clear your shell history if your shell keeps this line. The value goes to `bin/secret` on stdin, and then the first policy fetch runs.

**On Linux and WSL the member must be logged in, with their keyring unlocked.** The token is stored in their login keyring, which answers only on their own session bus. `sudo` drops the bus address, so the install finds it from the member's uid, at `/run/user/<uid>/bus`, and uses it only when that socket is theirs. It never takes the bus from your own environment. With no session bus there, the install says so, and storing fails with exit 4.

**The install isn't finished until a first policy verifies.** A laptop joined to a hub with no verified policy refuses every Claude Code step, because a hub rule could raise any call. So:

- With no token, the install lands the floor and stops with exit 4, naming the command above.
- With a token but no policy, it stops with exit 5 and says why: the laptop can't reach github.com (a proxy or firewall: a corporate proxy goes in managed `env`, see `contracts/hub.md`, Network env), or the token can't read the hub (Contents read, not expired, approved by the organisation). Fix that, then run `sudo -u <member> -H sh '<managed root>/bin/hub-sync.sh' fetch` and `... check`: both exit 0 when it's done.
- A policy that doesn't verify against `--signers` is exit 1.

**No secret store means no token.** Exit 4 says so, and nothing is written in its place: a plaintext file is what `bin/secret` refuses. The floor is on, but every step is refused until a store exists and the first policy verifies. On WSL this depends on a running Secret Service (harbor#618).

## Check it

The file being on disk proves nothing: a higher source would hide it with no warning. Have the member open a session and run `/status`:

- `Setting sources` says `Enterprise managed settings (file)`
- there is no `Skipped sources` line

If it says `(remote)`, `(plist)` or `(HKLM)`, another policy won and this floor is not in force. `claude doctor` lists any entry that was dropped.

## If it refuses

| It says | Do |
|---|---|
| a higher policy source | Remove it, or carry this policy in it. Writing the file would leave the floor silently absent |
| a file this install did not write | A managed file already exists. Merge by hand or remove it: this install doesn't share one |
| is in the group `sudo` | Take the member out of it. An admin can undo all of this |
| has a sudoers grant | Remove it. `sudo -l -U <member>` lists it |
| not the pinned commit | The pin must be the commit you run from: use the bootstrap |
| below the … already applied | The member's policy is an older signed file than the laptop last applied. Have them fetch (`hub-sync.sh fetch`), then run it again |

## Recovery

The dispatcher blocks a call if it fails, so a broken script stops all work until you act, and invalid JSON in a managed file stops Claude Code starting. Only an administrator can fix either, by design.

1. **Roll back**: run the same command with the previous pin. Moving back is allowed on this path, and each loss is printed as a WARN.
2. **Remove it**: `sudo sh /opt/harbor-core/bin/member-install.sh --user <member> --uninstall`. On WSL it writes a script to run as administrator.

Either works with Claude Code down, because neither needs a session.

## Leaving

Only IT can remove this: a member can't, because the rules are root's. The decision that a person may uninstall at any time now means **through IT**. `--uninstall` revokes the token, removes the hub state and the managed floor, and leaves a plain install with no floor. Then remove the member from the hub repo and delete the token on GitHub.

A failed fetch never does any of this. Policy goes only by a signed `revoked` entry or by you.

## What this floor doesn't reach

| Surface | State |
|---|---|
| Local sessions on Windows | Left on, and they fail closed. A Local session reads the same policy, the managed hook can't run there, and `onFailure: block` refuses every tool call. Tell staff to pick WSL in the environment selector |
| WSL sessions | The governed surface. See the first row below |
| SSH sessions | Off: `sshHostAllowlist` is empty. Over SSH the remote host's settings would apply, not these |
| Cloud sessions | Device files don't reach them. Turn them off in the admin console |
| Cowork | Not covered. Check your Claude Desktop configuration |
| Windows endpoint tools | They can't see processes inside WSL |

## Not verified

No Windows laptop and no root were available when this was built. Tests stub root's tools and run with moved paths, so they prove the commands and the bytes, never a laptop.

| What | Why it matters | Settled by |
|---|---|---|
| Whether a Local session really refuses every tool | The route depends on it: the docs grey out the WSL entry if Local is turned off, so Local stays on (#1278) | W9. One line: `MEMBER_DISABLE_LOCAL` in `bin/member-managed.sh` |
| The PowerShell itself | It has never run. Its payload is proved, its commands are not | The first Windows run |
| Hooks running from `/mnt/c`, and the ledger there | The writer refuses a folder it can write, and `/mnt/c` may report every folder writable, so records may not land | W4 |
| Elevated PowerShell reading `\\wsl.localhost` | If it can't, copy the script to a local admin folder first | The first Windows run |
| Agent reaching distro root through `wsl.exe` | Scripts on `/mnt/c` don't depend on it; the user tier does | W5 |
| The sandbox on stock WSL | `failIfUnavailable` refuses sessions if bubblewrap can't start | W6 |
| The allowlist through the sandbox proxy on WSL: package managers honour the proxy, and the hosts in `contracts/member-hosts.txt` are enough for normal work | Composed and tested as JSON, never run in a session. A missing host blocks work until policy adds it and the install runs again | W6, and the pilot's first week |
| `wsl --install --no-launch` and the restart it can need, as `--setup` drives them | They have never run. Only the text and the distro-side script are tested | The first Windows run |
| The prerequisites helper from a hook, and `sudo` running a file on `/mnt/c` | On WSL a Windows ACL decides who can write that file, not its owner | W5 |
| Desktop keeping a chosen folder, and login shells in a Desktop terminal | If it forgets, the session opens in the home folder and only the context note steers the agent | W10 |
| A keyring in the distro, and writing a logged-out member's macOS Keychain | No store means no token | W7 |
| `sshHostAllowlist: []` turning SSH off | Read from a summary of the docs, not tested | A Desktop run |
| The whole chain on a clean laptop | Plan step 4's done-when | A real laptop |
