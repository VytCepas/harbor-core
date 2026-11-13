---
kind: how-to
owner: @VytCepas
status: unreviewed
---

# Run a company hub

For the admin who stands up the hub repo of a company install (harbor#1278), keeps it, and answers its board. The format is `contracts/hub.md`. Nothing here is switched on for you: the workflows are patches an operator applies, and the updater's schedule needs its own yes.

## What you are running

One private repo owned by the company's GitHub organisation. It holds the signed `policy.json`. Its Issues are the board: one `request <id>` issue per call that waits for an admin, and one `heartbeat <login>` issue per member that the laptops post batched events to. Laptops read the policy at session start and check its signature against a key IT installed, so the repo's permissions are not what keeps a forged policy out: the key is.

## 1. Create the repo

1. In the organisation, create a **private** repo, for example `harbor-hub`. Make it from the scaffold: copy `templates/hub/` of harbor into a new folder, `git init`, commit, push. The scaffold's `README.md` repeats the first-day steps below.
2. Do not add anything the gate does not know. `sh bin/hub-gate.sh <folder>` refuses a file that is not a policy, key, pack or description, which is how a member list or a note with a client's name stays out. It also runs `bin/pack.sh`'s own install refusals over every `packs/<id>/` (front matter, a skill or command named like core's, a symlink, a register file), so a pack every laptop would skip is red before you sign it.
3. Set the repository variables and secret the gates and workflows read (`patches/hub/hub-gates.patch.md` lists them): `HARBOR_CORE_REPO`, `HARBOR_HUB_CORE_SHA`, `GITLEAKS_SHA256`, the secret `HUB_LEAKS_TSV` (the company's own names), and `HUB_MEMBERS` (the logins you expect).

## 2. Roles

| Who | Role on the hub repo | Why |
|---|---|---|
| Every member | **Read**, as a full organisation member | Read can open issues and comment on its own, and cannot apply labels or edit others' comments. Policy is public inside the company, so Read is enough to pull it |
| Admins | **Write** or above | An approval counts only from a login in the signed `approval.approvers` list, and, where GitHub answers the permission question, a role of write or above |

Keep every member at Read. A member at Write could label, edit and close what they should not, and the board's checks assume members can't. Do not add outside collaborators: on a private repo they are billed, and the narrow token the laptops use can't be given to a collaborator.

Everyone with Read can read everything in the repo: the policy, every request and every heartbeat. Staff are told so (section 8).

## 3. The signing key

The policy is daily data in a folder the member's own user can write, so its integrity comes from a signature, not from file ownership.

```sh
ssh-keygen -t ed25519 -C hub -f hub-key                      # asks for a passphrase: give one
printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 hub-key.pub)" > hub-signers
ssh-keygen -Y sign -f hub-key -n harbor-hub policy.json     # writes policy.json.sig; asks for the passphrase
```

- `hub-key` is the private key: keep it, and its passphrase, in the company password manager or on a hardware token, never in the repo, never on a member's laptop. Signing is always done by a person, so the passphrase costs nothing; a key without one signs for whoever copies the file.
- `hub-signers` is public. Commit it to the hub (the gate checks the signature against it) **and** give it to IT: it goes to each laptop as `<managed root>/hub-signers`, root-owned, so a member cannot swap the key.
- Principal `hub`, namespace `harbor-hub`: the laptops check exactly that. A signature made under another namespace does not verify.
- To rotate the key: sign the next policy with the new key and have IT install the new `hub-signers` on every laptop first. A laptop with the old file refuses the new policy and keeps its last good one.

## 4. Change the policy, and raise the pin

Every change: edit `policy.json`, **raise `serial`**, set `issued`, sign again, open a pull request. A serial that does not rise is refused by the gate and by every laptop, so an old signed file can't be replayed.

To raise the pin (`core.commit` and `core.contract`):

1. Test the harbor-core release on a pilot laptop first. The pin is a commit you tested, not the latest.
2. Set `core.commit` to the 40-hex commit and `core.contract` to that commit's `CONTRACT_VERSION`. A pin may not rise while a pack's `harbor_version` rejects the new contract.
3. Raise the repository variable `HARBOR_HUB_CORE_SHA` to the same commit by hand, so the gate that judges the next change is the release you tested.
4. Sign, and merge.

The policy reaches laptops at session start. The floor code under the managed root changes only when `bin/member-update.sh` runs there, or IT reinstalls. The updater verifies the policy signature itself, refuses a serial lower than the last applied, refuses a commit whose contract is not the pinned one, checks the floor with `member-integrity.sh`, and rolls back on any failure. Its schedule (`templates/member/`) is a template that nothing installs: it needs your explicit yes, as a recurring job that rewrites root-owned code. Until then, every release needs IT on every laptop, and laptops run the new policy over the old floor in between.

To remove a person: add the login to `revoked`, sign, and have IT remove the laptop's managed files. A revoked login stops being expected in the digest. Nothing else removes policy from a laptop, and a failing token is read as "hub unreachable", not as leaving.

## 5. Notification setup for blocking requests (F24, R18)

A very-high request opens an issue that mentions the admins in its body (`cc: @login`). A mention is the one route that mails an admin without watching the whole repo. A watch on the repo mails everything, buries the blocking requests under heartbeats, and breaks the promise that the rest arrives in the daily digest.

Each admin, once:

1. GitHub, Settings, Notifications: email on, to an address read every day, for participating and @mentions (GitHub's wording for the setting may differ; the point is that a mention mails you). The organisation's repos can be routed to a company address.
2. **Do not Watch the hub repo.** Leave it unwatched, so only mentions and threads you take part in reach you.
3. Check it: ask a pilot member to trigger a very-high request (or open an issue yourself with `cc: @your-login` in the body) and confirm the mail arrives and how long it took.

GitHub promises no delivery time, so "at once" is best effort. The request's issue title is `request <id>`; the body names the rule and the label, never the call.

The daily digest also mentions the admins, so a mail arrives every morning. **A morning with no digest mail is an outage, not a quiet day**: open the Actions tab, then see section 9.

## 6. What Free versus Team changes (R14)

| | GitHub Free (private repo) | GitHub Team |
|---|---|---|
| The gates run | Yes, if Actions is enabled and minutes remain | Yes |
| A red gate can stop a merge or a push to `main` | **No**: protected branches on a private repo are listed under Team, not Free | Yes: require the check `hub gates`, include admins |
| What keeps a bad policy off the laptops | The **signature**: an unsigned or edited policy fails on the laptop whatever the board shows. A bad but correctly signed policy gets through | The same, plus the branch rule, so the gate sees a change before it is signed into `main` |
| Cost | No seat cost | Every organisation member is a paid seat, including non-technical staff |

On Free, treat the gate as a check you run before you sign (`sh bin/hub-gate.sh`), and sign only what passed. Whether Free allows this private-repo setup in full was not confirmed from GitHub's pages when this was written: read the plan page and the repo's Settings, Branches, before you rely on either column.

If Actions minutes run out and the organisation has no payment method, GitHub blocks usage and every scheduled job stops without a message. Two short jobs a day are far under the included minutes; the watchdog and the missing digest mail are how you would find out otherwise.

## 7. Apply the workflows

The four workflows are files in `patches/hub/`: `hub-gates`, `hub-digest`, `hub-silent`, `hub-watchdog`. Each says what to create, what to check afterwards, and what failure to watch for. An operator applies them by hand to the hub's `.github/workflows/`; they are never applied for you. The three that run on a schedule (digest, silent, watchdog) are recurring jobs and each needs its own yes.

## 8. Tell staff what the board shows

Say this before the pilot, in your own words, and again to each new member:

- The hub is a repo every member can read. It shows: **who** was blocked or asked, **which rule**, **how many times**, **what software version** each laptop runs, and **when each laptop last checked in**.
- Harbor's own sender never sends commands, file contents, file names, prompts or anything a person typed. Its fields are a fixed list of words, numbers and ids, not free text, and it drops anything outside the list. Anything that reaches a member's board token can still write text to the board by hand; the token is kept from the agent for that reason, and it is a known limit.
- A request for a very-high action names the rule (for example "credentials leaving the machine"), not the call, and waits for an admin to approve that exact call.
- The admins see every member's events, and so does every member. A person who is silent for a few days is mentioned to the admins; it does not say why.
- A person with administrator rights on their own laptop can remove all of it. That is a known limit, not a promise either way.

## 9. When the digest or a member goes quiet

| You see | It means | Do |
|---|---|---|
| An issue `digest missing` | No digest was posted in the last 26 hours: the schedule was dropped, Actions is out of minutes or disabled, or the digest job failed | Open Actions, read the last `hub-digest` run, run it by hand |
| No digest mail and no issue | The digest and the watchdog both stopped, or your mail setting changed | Open Actions; check section 5 |
| `silent <login>` | No valid heartbeat from that member for `silent_days` days. A laptop that is off, a holiday, an expired token and a stopped harbor look the same | Ask the person; do not infer |
| Everyone silent on one morning | An outage on the hub side, or a bad policy every laptop refused | Read the digest of the same morning and the last run of every workflow before writing to anyone |
| `invalid-comments` above zero in the digest | Something posted to a heartbeat issue that was not a valid event, or a comment on a member's issue by someone else | Open the heartbeat issue; the invalid comment is counted, never shown in the digest |

## 10. Members' own tools (harbor#1278)

Each colleague's own skills, agents and commands live in a private repo `<org>/tools-<login>`, in the hub's own organisation. The person writes it, you read it. Their laptop keeps `~/.claude/skills`, `agents` and `commands` in step with it: a pull at session start, a push at the end of a turn (`bin/member-tools.sh`, check `member.tools-sync`). Hooks and settings never sync; a name a hub pack or core skill holds is skipped and told to the person.

### Create a colleague's repo (one command each)

```sh
harbor hub tools create <login> --hub <org>/<hub repo> --policy policy.json     # or --admin <login> for each reader
```

It makes `<org>/tools-<login>` private, gives the person write and every admin read (`--policy` takes the approvers of the signed policy), and refuses where the organisation's default repository permission is not `none`, because every member would then read every personal repo. Fix that once, as an owner: `gh api -X PATCH orgs/<org> -f default_repository_permission=none`. It is safe to run twice. Check: `gh api repos/<org>/tools-<login>/collaborators --jq '.[] | [.login, .role_name] | @tsv'`.

### The token: today's member token cannot reach it

The token in the install guide (`docs/how-to/member-install.md`) names **the hub only**, with Contents read. GitHub gives a fine-grained token no access to a repo outside its list, so with that token the personal repo answers as missing, and the sync does nothing (it says so and changes nothing). The member's token needs, in one token, resource owner the organisation, **repositories: the hub and `tools-<login>`**, permissions **Issues: read and write** and **Contents: read and write**. Contents write on the hub stays harmless while the member is at **Read** on it (section 2): a token never exceeds its person's role. GitHub ties a token to the person, so you cannot edit it for them: with the member beside you, they open the token in GitHub, Settings, Developer settings, Fine-grained tokens, add the repository and the permission, and save. Where the organisation requires approval, you approve the changed request as an owner (Organization settings, Personal access tokens, Pending requests; the REST route is `POST /orgs/<org>/personal-access-token-requests/<id>` with `action=approve`, written from memory of GitHub's docs and not run). No new secret is stored: the laptop reads the same `hub-token`, which the floor already keeps from the agent. A token that lapses stops the sync and the board together.

### Take a proposed tool into the hub

A member's agent runs `member-tools.sh propose skills/<name>`, and the laptop opens an issue on the hub repo `tool proposal skills/<name> from <login>` naming `<org>/tools-<login>` and the commit. It writes nothing else to the hub. Only a skill can move to a hub pack. You:

1. Read the skill at that commit: `gh repo clone <org>/tools-<login> /tmp/tools-<login> -- --no-checkout && git -C /tmp/tools-<login> checkout <commit>`.
2. Copy it into a pack and run the gate: `harbor hub tools admit skills/<name> --hub-dir <hub checkout> --pack <pack id> --from /tmp/tools-<login>`. It lists the file in `extension.json` and runs `bin/hub-gate.sh`; a red gate (a `hooks:` key, a front-matter key outside the allowlist, a core name, a symlink, a leak, a secret) puts the checkout back and exits 1. Tell the colleague what it said.
3. List the pack's commit under `packs` in `policy.json`, raise `serial`, `harbor hub sign`, open the pull request, merge.

Once the pack is signed in, the laptops install the hub's copy and the personal one is skipped by name; the person may delete theirs.

### Staff are told

The repo is readable by the admins. Say so with section 8.

## 11. Connectors: a service a colleague's API key may reach (harbor#1278, control `member.connectors`)

A colleague's agent never holds an API key. A key reaches **one MCP server** that Claude Code starts itself, through the managed launcher, and the agent calls that server's tools. You declare the server once, in the signed policy.

1. **Install the server as root, in a folder named for the connector.** Each connector has its own folder `/opt/company-mcp/<name>/`, where `<name>` is the connector's `name` in the policy. The folder and every folder above it must be owned by root and not writable by the colleague; the launcher checks that for the path **as written, at every link hop, and after resolution**, and checks every absolute word of `command` the same way (a link whose own folder the colleague can write is refused even when its target is root's). `command` is a closed grammar, the same at all three layers. **`command[0]`** is an absolute path: a file inside that folder, or `bun`, `node` or `python3` (written or resolved name) **written as a file directly in `/usr/bin`, `/usr/local/bin` or `/bin`, or inside the connector's folder**: an interpreter reached through a link anywhere else (a `~/venv/bin/python3` that leads to `/usr/bin/python3`) is refused though its target is root's, because the link's folder is the colleague's to write and a swap would run another program with the key. For an interpreter the rules always apply: `bun` needs `--no-install` as the next word, then an entry file inside the folder; `node` and `python3` need the entry file inside the folder as the next word. **Every later word** is exactly one of: (a) an absolute path that, links followed, is inside the folder; (b) a plain token, with no `/` and not starting with `.` or `-`; (c) a flag `--name` or `--name=value`, the value having no `/` and not starting with `.`. Nothing else: `-x`, `./x`, `home/x`, `--cwd=/x` are refused. The flags `-e -m -c -r -p --require --import --preload --eval --print` stay refused, as do a shell, `bunx`, `deno`, and `x`, `run`, `install`, `add`, `pm`, `create` after `bun`. A relative word would be resolved against `/` (the launcher runs the server in `/`), so the launcher also refuses a plain token or flag value that names something that exists there (`tmp`, `etc`, `home`). `hub-format.sh` refuses it when you sign, the composer when it writes `managed-mcp.json`, and the launcher when it starts. A wrapper (`env`, `setsid`, `stdbuf`, `taskset`, `flock`, `nohup`), a package runner (`npx`, `bunx`, `uvx`, `pipx`) or a shell would load code from a place the agent can write (`~/.cache/uv`, `~/.bun`, `node_modules`, a file under its home) and run it with the key, so none is accepted.

   **The jail (the class, not one path at a time).** Whatever the command says, the launcher starts the server inside a bubblewrap view (`bwrap`, Linux and WSL) that contains only the root's own trees, read-only: `/usr`, `/bin` `/sbin` `/lib*`, `/etc`, the connector's folder `/opt/company-mcp/<name>/`, a private `/proc` in its own process namespace, `/dev`, and an empty `/tmp`. There is no `/home`, `/root`, `/mnt`, `/var`, `/run/user` or `/dev/shm`, so a file the colleague planted (a venv's `home =` standard library, a `NODE_PATH` or `sys.path` entry, a plugin folder, `~/.cache`, a file in `/tmp`) does not exist for the server to load. The network is shared. The server's working folder is `/` and `HOME` and the `XDG_*` folders are `/`. **A server can therefore use only files under `/usr`, `/etc` and its own folder**, and writes only to its own empty `/tmp`: ship everything it needs in its folder. **At every start the launcher also scans the bound trees as the member** (`find -writable` over `/usr`, `/etc` and the connector's folder, `/etc/claude-code` excepted because it is masked) **and refuses, naming the path, if anything in them is writable by the colleague**: a laptop where `/usr/local` was handed to the user (`npm -g`, Homebrew, `pip`) would put their code inside the view. Fix such a laptop's ownership, or ship the connector's own copy in its folder. **Without a working bwrap the server does not start** (the launcher refuses; it never runs bare), the same stance as the member sandbox. On macOS there is no bwrap: the launcher uses Seatbelt (`sandbox-exec`) with a deny-list of `/Users`, `/Volumes` and the temporary folders, which is weaker than the Linux view and was not exercised by the suites. The view is derived, not listed by guess: the sim finds with `find -writable` that nothing under the bound trees is writable by the member, and lists the places it leaves out.

   **Recommended pattern for a TypeScript or Python connector.** Install it as root into its folder with its dependencies installed there, as root. For TypeScript declare `["/usr/local/bin/bun", "--no-install", "/opt/company-mcp/acme/src/index.ts"]`: **`--no-install` is required** for `bun`, because without it bun fetches a missing package into `~/.bun`, which the colleague can write. `node` and `python3` need no equivalent flag: neither fetches a package by itself, and `-m`, `-c`, `-e` and `-r` are refused. **The server runs with its working directory `/` and `HOME` and the `XDG_*` folders set to `/`**, root-owned places, so it reads no `bunfig.toml`, `.env`, `.npmrc` or `~/.config` of the colleague's. That was proved with bun 1.4.4 on Linux: bun reads `bunfig.toml` (and its `preload`) and `.env` from the working directory and nowhere else it was tried (not `$HOME`, not `XDG_CONFIG_HOME`, not beside the entry file), and `--no-install` makes a missing package an error. A server that needs a writable `HOME` must keep its state elsewhere, in a folder you make for it. **Python.** A python that finds a `pyvenv.cfg` beside it, or one folder up, loads that venv's `site-packages`, and a `.pth` file there runs code. The launcher refuses an interpreter with a `pyvenv.cfg` beside it or one folder up, **unless the interpreter is inside the connector's folder** (and so root-owned): ship Python dependencies as an admin venv there, `/opt/company-mcp/<name>/venv/bin/python3` with its `pyvenv.cfg`, created and owned by root. The `home =` line of that `pyvenv.cfg` must be `/usr/bin`, `/usr/local/bin` or `/bin` (the base python's folder): a base python anywhere else, such as one `uv` installed under the colleague's home, would load its standard library from there, and the launcher refuses it. The launcher cannot judge code a server loads at run time, but the jail above means a `NODE_PATH`, a `sys.path` entry or a plugin directory under the colleague's home does not exist for the server; keep what it loads in its own folder.

2. **Add a row to `connectors` in `policy.json`**, raise `serial`, `harbor hub sign`, open the pull request, merge (section 4):

   ```json
   "connectors": [
     {"name": "acme", "ref": "acme-crm", "env": "ACME_API_KEY", "service": "Acme CRM",
      "command": ["/opt/company-mcp/acme-server", "--stdio"]}
   ]
   ```

   `name` is the server's name in Claude Code. `ref` is the store name of the key: lower case, never `hub-*` (the hub token), one ref per row. `env` is the variable the server reads its key from; names that steer a program (`PATH`, `LD_*`, `NODE_*`, `*PROXY*`) are refused. `service` is the words the colleague sees when they enter the key. `command` is the server: an absolute path first, no `..`, no `${`. `hub-format.sh` refuses a row that breaks any of this, and the laptop composes it again.
3. **It reaches a laptop** at the next install or update (`member-update.sh`): `<managed root>/connectors.json` (what the launcher believes) and `managed-mcp.json` beside the managed settings (`/etc/claude-code/managed-mcp.json` on Linux and WSL), both root's. Until then nothing changes.
4. **Tell the colleague** to enter the key (docs/how-to/member-install.md, "A colleague's API key").

**This takes exclusive control of MCP on the laptop (Claude Code's `managed-mcp.json`).** While any connector is declared, servers a person adds, project `.mcp.json` servers and plugin servers do not load, and `allowedMcpServers` stops mattering for them. **claude.ai connectors keep loading:** the install and the updater set `allowAllClaudeAiMcps: true` in the managed settings whenever the policy declares a connector (operator decision, 2026-11-12), and leave it unset otherwise. With no `connectors` row neither file is written, the key is absent and MCP is as it was.

To remove a connector: drop its row, raise `serial`, sign, merge, and have the colleague run `harbor access revoke <ref>` or ask you to remove the key at the service. The old key stays in their store until they do.
