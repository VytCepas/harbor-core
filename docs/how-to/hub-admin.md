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
2. Do not add anything the gate does not know. `sh bin/hub-gate.sh <folder>` refuses a file that is not a policy, key, pack or description, which is how a member list or a note with a client's name stays out.
3. Set the repository variables and secret the gates and workflows read (`patches/hub/hub-gates.patch.md` lists them): `HARBOR_CORE_REPO`, `HARBOR_CORE_SHA`, `GITLEAKS_SHA256`, the secret `HUB_LEAKS_TSV` (the company's own names), and `HUB_MEMBERS` (the logins you expect).

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
ssh-keygen -t ed25519 -N '' -C hub -f hub-key
printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 hub-key.pub)" > hub-signers
ssh-keygen -Y sign -f hub-key -n harbor-hub policy.json     # writes policy.json.sig
```

- `hub-key` is the private key: keep it in the company password manager or on a hardware token, never in the repo, never on a member's laptop. Protect it with a passphrase if you can sign interactively.
- `hub-signers` is public. Commit it to the hub (the gate checks the signature against it) **and** give it to IT: it goes to each laptop as `<managed root>/hub-signers`, root-owned, so a member cannot swap the key.
- Principal `hub`, namespace `harbor-hub`: the laptops check exactly that. A signature made under another namespace does not verify.
- To rotate the key: sign the next policy with the new key and have IT install the new `hub-signers` on every laptop first. A laptop with the old file refuses the new policy and keeps its last good one.

## 4. Change the policy, and raise the pin

Every change: edit `policy.json`, **raise `serial`**, set `issued`, sign again, open a pull request. A serial that does not rise is refused by the gate and by every laptop, so an old signed file can't be replayed.

To raise the pin (`core.commit` and `core.contract`):

1. Test the harbor-core release on a pilot laptop first. The pin is a commit you tested, not the latest.
2. Set `core.commit` to the 40-hex commit and `core.contract` to that commit's `CONTRACT_VERSION`. A pin may not rise while a pack's `harbor_version` rejects the new contract.
3. Raise the repository variable `HARBOR_CORE_SHA` to the same commit by hand, so the gate that judges the next change is the release you tested.
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
