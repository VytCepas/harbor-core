# Hub and member contract (harbor#1278)

The formats a company install runs on: the hub repo, the member laptop's state, and what crosses between them. `standalone` is unchanged by all of it: every path here is reached only on a box whose managed root holds `harbor-member-mode`.

Validated by `bin/hub-format.sh`; shared code in `bin/library-hub.sh`; vocabulary in `contracts/hub-vocabulary.tsv`; default tiers in `contracts/risk-tiers.tsv`.

## Roles and where each fact lives

| Fact | Where | Why there |
|---|---|---|
| Role, hub repo, member login, home | `<managed root>/member.conf`: root-owned, exactly the lines `hub=<owner/name>`, `login=<login>`, `home=<absolute home>`, written at install inside the floor pin. `hub_env_clean` sets `HARBOR_MEMBER_ROLE`, `HARBOR_HUB_REPO`, `HARBOR_MEMBER_LOGIN` and `HOME` from it and clears `XDG_STATE_HOME`; `member-update.sh` reads it too | Only an admin can write it. A launch environment can beat settings `env`, and a schedule hands the updater PATH alone with no role in root's env, so on a marker box env is never the authority. Managed `env` still carries the three names, for what runs off the marker. Never `harbor.toml`, which sits in the agent's write zone |
| Managed root | The folder holding `harbor-member-mode`; `HARBOR_MEMBER_ROOT` in managed `env` only off the marker | A script finds it from its own path |
| Kill switches on a member box | Pinned to `0` in managed `env`, and cleared by the dispatcher before any guard runs | A `settings` `env` block reaches every hook |
| Floor code | `<managed root>/bin/` | Only an admin can write it. `HARBOR_MEMBER_ROOT` is the one setting that moves it if the Windows test changes the answer |
| Pin state | `<managed root>/floor.pin` (the floor's hash), `core.commit` (the pinned commit), `pin.serial` (the last policy serial applied) and `floor.extra` (what the install placed in `bin/` that isn't core code, such as `upterm`), all written at install and by `member-update.sh` | The updater refuses a lower serial and carries `floor.extra` across a swap; `member-integrity.sh check` fails a floor missing a file it names |
| Signing key | `<managed root>/hub-signers`, OpenSSH `allowed_signers`, principal `hub`, namespace `harbor-hub` | Policy is daily data in a user-owned folder, so its integrity comes from a signature, not ownership |
| Policy, requests, outbox | `HUB_STATE` = `<home>/.local/state/harbor/hub` on a marker box. Off it, `${XDG_STATE_HOME:-$HOME/.local/state}/harbor/hub` | Hooks run as the user, so run-time state can't be root-owned. Write-denied to the agent by managed `Edit` deny and sandbox `denyWrite`, which name this one folder |

`<managed root>`: macOS `/Library/Application Support/ClaudeCode/harbor`, Linux `/etc/claude-code/harbor`, WSL `/mnt/c/Program Files/ClaudeCode/harbor`.

`<managed root>/bin/harbor-member-mode` is an empty file written at install. `library-admission.sh` takes its member branch only when this file sits in the same folder as the running guard, so no `env` value can turn tiering on for a standalone guard in `<cfg>/bin`.

`<managed root>/member.conf` is written at install, three lines:

```
hub=<owner/name>
login=<github login>
home=<absolute home, no trailing slash>
```

`hub_facts` in `bin/library-hub.sh` reads it whenever `library-hub.sh` is sourced beside the marker, however the script was started, and every managed hook entry runs `hub_env_clean` first. `scope-roots.sh --hub` run directly beside the marker reads it the same way, so a role or state folder in env moves no hub clone. A marker with no readable file, a link, a line missing or malformed, or a key given twice is a fault: the role reads `fault` and nothing counts as a member. The dispatcher exits 2 on every call, the post hook and `note` do nothing, and the session start says why.

## Hub repo

A private repo owned by an organisation, members as full org members at role Read, admins at Write or above.

```
policy.json            the signed policy
policy.json.sig        ssh-keygen -Y sign -n harbor-hub
hub-signers            the public key the hub gate checks signatures against
packs/<id>/harbor-pack hub packs (contracts/pack.md), reviewed by the admin
packs/<id>/extension.json
```

The repo's Issues are the board.

## policy.json (schema 1)

Closed keys: an unknown key refuses the file.

| Key | Type | Meaning |
|---|---|---|
| `schema` | int | `1`. A higher number is refused and the last good policy stays |
| `hub` | kebab | The hub's name |
| `serial` | int >= 1 | Must rise. A lower or equal serial than the last good policy is refused, so an old signed file can't be replayed |
| `issued` | UTC time | When signed |
| `core` | `{commit, contract}` | The pinned core: 40-hex commit of `harbor-core`, contract integer |
| `rollout` | `{mode}` | `shadow` enforces `integrity` and `fixed` as `enforce` does and only records what `default` and hub rows and hub hooks would do; `enforce` applies tiers |
| `approval` | `{approvers, ttl_hours}` | Approver logins, ttl 1 to 168 |
| `silent_days` | int 1 to 90 | Days until a member counts as silent |
| `tiers` | object | Control id to tier: re-tier a `default` row. A `fixed` or `integrity` row here refuses that entry at read time |
| `rules` | array, up to 200 | Hub rules, below |
| `packs` | array | `{id, commit}`: hub packs at a pinned commit |
| `hooks` | array | `{pack, path, sha256}`: member hooks an admin approved |
| `revoked` | array of logins | Positive signal for leaving. Nothing else removes policy |
| `support` | `{keys, relay, relay_key, max_minutes}` | Remote support, below. Optional: absent, or with no relay of the hub's own, means support is off |
| `hosts` | array of up to 200 host names | Hosts a member's sandboxed commands may reach beyond `contracts/confinement-hosts.txt` and `contracts/member-hosts.txt`. Each in `allowedDomains` shape: lower case, at most one leading `*.`, two labels or more after it, never a bare `*`. A row that admits a support relay is refused. Applied when the settings are composed again: by the first install once its policy verifies, by the updater after each update it applies, or by IT running the install again (docs/how-to/member-install.md, "The network") |
| `logs` | `{recipient}` | The loader's age X25519 recipient (`age1…`). A laptop seals its logs id and counts to it, and to nothing else; without it the laptop sends none (harbor#1278, the logs payload below) |

### A hub rule

```json
{"id":"prod-bucket","label":"Touches the production bucket","tier":"very-high","target":"cloud",
 "tools":["Bash"],"when":[{"field":"command","op":"contains","value":"gs://prod-"}]}
```

Every condition in `when` must hold. `field`: `command` (normalised), `file_path`, `url`, `query`. `op`: `equals`, `prefix`, `suffix`, `contains`, `word`. No regular expressions, because hub policy is untrusted input to a hook that runs on every call. `value` is 1 to 200 characters, compared case-insensitively. `label` is at most 60 characters and written by the admin, so it isn't member content.

## Tiers and sets

| Tier | Effect on a call |
|---|---|
| `very-high` | Denied until an admin approves that exact call |
| `high`, `medium` | The person is asked; the outcome is logged |
| `low` | Runs; logged |

| Set | Rows | A hub may |
|---|---|---|
| `integrity` | Self-protection: the rules `floor_shadow_enforces` matches | Nothing. Always denied, no approval |
| `fixed` | Credentials leaving the machine, privacy rules | Nothing. Stays `very-high`, in `shadow` too (operator, 2026-11-08) |
| `default` | Everything else | Re-tier |

`contracts/risk-tiers.tsv` lists `integrity`, `fixed` and any row whose default isn't derived. With no row: a `block` control is `very-high`, a `warn` control `high`, a `shadow` or `off` control runs as its mode says. Any policy failure uses the last good policy: never a lower tier.

With no verifying policy on disk, whether files fail or none exist, a marker box is joined and `hub-tier.sh mode` says `bad`: every call is denied with "the company safety settings could not be read" until a session start fetches a signed policy. A hub rule can raise any call, so no core default is a safe floor for what's missing, and nothing user-owned can tell a new laptop from a deleted state folder. So `member-install.sh` doesn't finish without one: no token is exit 4, and a token with no policy that `hub-sync.sh check` verifies is exit 5, each telling IT what to fix. Deleted policy files read the same way later, and so does a revoked member once `harbor hub leave` has dropped the policy, until IT removes the managed files. Core defaults alone are only for a box with no marker.

## The request id

The canonical call is `hub_canon` in `bin/library-hub.sh`: tool name, the fields that matter for that tool, working directory, member. `description`, `timeout` and other fields that vary between identical retries are out. `id = "r-" + first 16 hex of sha256(salt + canonical)`, salt a random per-laptop value in `HUB_STATE/salt`, so a short command on a shared board can't be guessed from its id. A changed call gets a new id.

## The board

**Request issue.** Title `request <id>`. Body, one `key: value` per line, closed vocabulary only, built by the hook:

```
harbor-request: 1
id: r-0123456789abcdef
member: alice
rule: admission.key-material-egress
label: Credentials leaving the machine
tier: very-high
target: credential
core: 0123456789ab
cc: @admin-login
```

**Approval.** A comment whose whole body, trimmed, is `approve <id>`. It counts only if all hold:

1. Its author comes from GitHub's own record, is in signed `approval.approvers`, isn't the member, and has `user.type` `User`.
2. If the permission endpoint answers for this token, it says `admin`, `maintain` or `write`. Refused for the token (403 or 404): the signed list decides. Any other failure denies.
3. It was never edited: `updated_at` equals `created_at`.
4. `created_at + ttl_hours` is later than the `Date` header of the same API response. Never the laptop's clock.
5. The issue is open, and its body's `id` matches.

GitHub unreachable means denied. A label never counts. Consumed once: a mark in `HUB_STATE/used/` at PostToolUse, then the hook comments `used <id>` and closes the issue. The local mark is advisory; expiry bounds replay.

**Heartbeat issue.** Title `heartbeat <login>`, one per member. Each comment is one fenced `json` block holding an array of events.

## Events (schema 1)

Closed keys per kind, checked by `hub-format.sh event`. No field holds free text: a value is an enum, a number, a digest or a kebab id of at most 64 characters. Only harbor's own sender is covered. An agent that reaches the token can still write free text on the board, which is why the token is denied to it.

| Kind | Keys beyond `v kind ts member` |
|---|---|
| `heartbeat` | `core contract floor serial mode refusals asks requests packs`, and `sealed` when the laptop may send its logs payload (below) |
| `refusal` | `rule tier target count` |
| `ask` | `rule tier target outcome count` |
| `request` | `id rule tier target outcome` |
| `check` | `check outcome` |
| `token` | `days_left outcome` |
| `support` | `id reason outcome` |
| `activity` | `tool verb_class verdict count`: tool calls, counted by the dispatcher once per call. **Sealed only** |
| `session` | `outcome count`: session starts (`started`, a resume or compact included) and ends (`ended`). **Sealed only** |

`ts` is coarsened to the hour; for `activity` and `session` it is the day (`T00:00:00Z`), so a count per person is never finer than a day (logging-design D4, D9). `tool`, `verb_class` and `verdict` are vocabulary sets: an `mcp__` tool is `mcp`, a tool the list lacks is `other`, a call that is not a shell command has class `na`, and the class is the floor's own by first verb, never the command. These two kinds wait in `HUB_STATE/tally.jsonl`, apart from the outbox, so a busy day can't crowd a refusal out; a full tally is folded in place. `packs` lists hub pack ids only, never a name the member chose.

### The logs payload (harbor#1278, "Log scope", level 2)

Harbor's BigQuery logs key a laptop by a **random id**, never a login: `<managed dir>/harbor-ids/<account>.id`, 32 hex, made by `member-install.sh` from `/dev/urandom`, root-owned, beside the managed root and outside it, so `--uninstall` leaves it and a reinstall keeps it. It is never rotated and never derived from a login or an e-mail. The person reads it with `harbor hub id`, which only reads; it is how they ask for their data or its deletion (`legal/dpia.md` R12).

**The id and the counts never appear in clear on the board.** The heartbeat may carry one more key, `sealed`: base64 of an age file to the X25519 recipient `logs.recipient` of the signed policy, holding `{v, id, events}` where `events` are this send's `activity` and `session` counts (up to 100). `hub-format.sh board` refuses a comment with either kind in clear, and a `sealed` value that is not an age file to an X25519 key, so a clear id has no field to ride in. The loader opens it with its own identity and drops the GitHub author before staging; nothing links the two afterwards.

**Nothing is counted before the notice receipt.** `<managed root>/notice-received` is written by `member-install.sh --notice-received`, which IT runs once it holds the member's signed receipt of the logs notice, and removed by `--notice-withdrawn`. It is inside the floor hash. Without it the sender keeps no `activity` or `session` count and seals nothing, so no row of that laptop can reach BigQuery; the release-1 board events go on as before (D8). With it but no way to seal (no `age`, no `logs.recipient`), the heartbeat says `check hub-logs-seal failed` and the counts wait.

## Remote support

Consented, visible help for a colleague: `bin/member-support.sh` on the laptop, `harbor hub support` (`bin/hub-support.sh`) for the admin, `docs/how-to/member-support.md` for both. Nothing listens until a person starts it, and nothing persists after it.

**The `support` key.** Closed keys.

| Key | Type | Meaning |
|---|---|---|
| `keys` | 1 to 20 strings | Required. Plain ssh public key lines: no options, one line each. Any listed key can join a session the person has said yes to |
| `relay` | `wss://host[:port]` or `ssh://host[:port]` | The hub's own relay (`relay/`, docs/how-to/member-support.md). No default: absent means support is off. Never the `public-relay` host of `contracts/support-upterm.tsv` or a name under it |
| `relay_key` | a host key, no comment | The relay's host key, as `relay/install.sh --key` prints it. Comes with `relay`, or neither does |
| `max_minutes` | int 5 to 240 | The hard limit on a session. Default 60 |

`--authorized-user github:` is never used, because GitHub's key list can change outside a signature. `relay_key` sits in policy, not in the floor, so a pin moves with its relay rather than with a floor update.

**Own relay only** (operator, 2026-11-07). A relay reads the session and vouches for guests ("What the relay sees", below), so a third party's could read client data and join an accepted session. Support stays off until the hub runs its own. `support_relay` in `bin/library-board.sh` reads no default, and `hub-format.sh` refuses the public relay by name, so the refusal holds on the member's side and the admin's.

**Moving the relay.** A session can't change managed settings, so a new `relay` reaches a laptop only when they are composed again from the verified policy, which writes the new host into `sandbox.network.deniedDomains`: by the updater after an update, or by IT running the install again. Until then `member-support.sh` refuses to start.

**The request.** Title `support <id>`, `id = "s-" + 16 random hex`. Body, six closed lines:

```
harbor-support: 1
id: s-0123456789abcdef
member: alice
reason: fix
core: 0123456789ab
cc: @admin-login
```

`reason` is `update`, `fix` or `question`.

**Comments.**

| Whole body | From | Means |
|---|---|---|
| `accept <id>` | an admin | Counts under conditions 1 to 4 of an approval, and the issue must be open with this exact body. The code is one: `board_signed_comment` in `bin/library-board.sh` |
| `session <id> <session>` | the member | The session string, `[A-Za-z0-9+/=:_-]`, once the person has said yes. It grants nothing alone: a guest needs a listed key too |
| `closed <id>` | the member | The session is over; the issue closes with it |

**Consent, in order.** The person types `allow` after being told what the admin can see and do. An admin accepts on the board. The person sees the admin's login and answers upterm's own `Start the session?`. That question comes once, before the session starts: after a yes, any listed key can join until the limit.

**What upterm is given.** `upterm host` runs with a scrubbed environment and an empty config, because `UPTERM_ACCEPT` or `accept: true` in a user-writable file would skip the question. Keys come only from verified policy. It gets `--no-forwarding --no-sftp --no-exec`, so nothing a guest does happens off the person's screen; `--escape-char none`, so the session can't be detached and left running; `--private-key` with a key made for this session, so none of the person's own keys reaches the relay; and `--known-hosts` holding only the pinned relay key. Never `--accept`. Everything sits in `HUB_STATE/sup.<pid>/` and goes when it ends.

**Ending.** Closing the window, the `max_minutes` clock, the person's no, or the main process dying all stop the session, comment `closed <id>`, close the issue and record the event. A lookout beside the main process holds the clock and survives the window closing, because `upterm host` runs its session in a process of its own that outlives its terminal.

**Keeping the agent out.** No single layer is the wall.

| Layer | Stops | Doesn't stop |
|---|---|---|
| `admission.member-support`, integrity set, `bin/member-support-guard.sh` | A tool call naming `upterm`, `member-support`, `hub-support` or `harbor hub support`, spelled any way a shell reads the same | A name built at run time |
| `sandbox.network.deniedDomains` | The agent's sandboxed shell reaching the hub's relay or the public one by name. No allowed row may admit either | A connection to the relay's IP address under the `open` network: the proxy matches hostnames, which is why the member network is an allowlist. Any other relay the agent stands up itself |
| `member-support.sh` refusals | A session without a terminal, or with an agent in its process tree or environment | An agent that gets a terminal, clears its variables and hides its tree |

**What the relay sees.** upterm's relay ends the guest's SSH connection and opens a second one to the host, so it reads all terminal traffic in the clear, and it mints the certificate that tells the host which key a guest used, so a dishonest relay can claim to hold a listed key. `--authorized-keys` is as good as the relay. Pinning the relay's key says which relay this is, not that it is honest.

**Limits of the session.** It runs as the member. It can't change the root-owned floor, and a `claude` started in it runs under the managed limits. It reads whatever the member's account can read, and a process it starts can outlive it, as any process that account starts can.

## extension.json (schema 1)

Closed keys: `schema`, `id` (kebab), `version`, `harbor_version` (the `[op]N[.M]` grammar of `contracts/pack.md`), `provides` (`skill`, `hook`, `script`), `files` (`{path, sha256}`). A pin may not rise while an extension's `harbor_version` rejects the new contract.

## What runs where

| Moment | Managed hook | Does |
|---|---|---|
| PreToolUse, every tool | `member-dispatch.sh` | One entry, `onFailure: block`. Runs the guards at once and reads their records in table order, applies tiers, consults an approval once, runs hub hooks last. Stdout from a guard or hub hook that opens with `{` and isn't one JSON value is a deny |
| PostToolUse, PostToolUseFailure, Stop | `member-post.sh` | Closes ask records, consumes an approval |
| SessionStart, SessionEnd | `member-session.sh` | Installs a missing prerequisite through `member-prereqs.sh`, fetches and verifies policy, checks floor integrity, sends the batched events. SessionEnd has its own `timeout`, because the default is a shared 1.5 seconds |
| UserPromptSubmit | `hub-approval.sh note` | Tells the person an approval arrived. No network call while no request is open |

Every managed hook starts as `/usr/bin/env -i` with a pinned PATH and `MEMBER_HOOK_ENV` in `bin/member-managed.sh` alone, each passed only when set, then an absolute `/bin/sh`: a settings `env` reaches every hook, so a bare `sh` resolves from a PATH the floor doesn't control, and macOS `/bin/sh` is bash 3.2, which defines an exported function from its environment before the floor's first line. What the floor needs beyond those names it reads from root-owned files: `member.conf`, and the managed settings' `env` (Network env, below). Every entry above runs `hub_env_clean` before anything else.

**Network env.** Before any network call, `hub_net_env` (in `hub_env_clean`, and at source time beside the marker) clears every variable that steers git, curl or TLS: all `GIT_*`, every `*_PROXY` and `*_proxy`, `CURL_HOME`, `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `SSLKEYLOGFILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `OPENSSL_CONF`, `NETRC`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME`. **The one trusted source for a proxy or CA is the managed settings file's `env`**, read from disk, never from the process env: a launch environment can beat settings `env`, and only an admin writes the file. From it come back `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` and `NO_PROXY` in either case, and `SSL_CERT_FILE`, `SSL_CERT_DIR`, `CURL_CA_BUNDLE` and `GIT_SSL_CAINFO` when absolute and naming a file the member can't write. So IT sets a corporate proxy in managed `env`, and `hub-board.sh` keeps a CA from there. The hub fetch also reads no `~/.gitconfig` or system git config (`GIT_CONFIG_GLOBAL=/dev/null`), so `url.*.insteadOf` can't move it.

An approved call gets no `allow`: the dispatcher stays silent so permission rules still apply. Very-high rows never go in `permissions.deny`, because a deny rule can't be approved.

**The Read tool.** `allowManagedPermissionRulesOnly` discards a standalone install's `Read(...)` deny rows, so `contracts/member-guards.tsv` carries a member-only `Read` row to `admission-egress.sh` and those patterns as `read-deny` rows, generated from `bin/deploy-harden.sh` and `bin/admission-deny.sh`, plus the token store: `~/.local/share/secret/**` (bin/secret's ciphertext, and on Linux and WSL its member file store's keys too) and `~/.local/share/keyrings/**` (libsecret's files, kept as a row though the member store no longer uses them), `MEMBER_READ_ROWS` in `bin/member-dispatch.sh`. No standalone writer has those two as Read rows, and a member's `sandbox.credentials` hides only the first, from sandboxed Bash. The `Grep` row is held to the same rows: the folder searched, a folder whose search walks into a `~/` or `//` row (`~`, `/`), and a `glob` that picks out an any-depth row's names (`.env*`, `*.pem`, `secrets/**`). A broad filter (`*`) over a project is not one. A hit is `admission.key-material-read`, a `fixed` row: it waits for an admin. A file is judged as itself, not only by its name: another name for a file that exists under a home- or root-anchored row (a hard link, same device and inode) is that row's hit, and a file that merely has several names is not. The branch needs the marker, so a standalone copy of the guard leaves as it does for any other tool.

**The hub token in the agent's shell.** `admission.hub-token-read`, a `fixed` row of the same guard on a marker box: a Bash call led by `secret-tool` reading the Secret Service, the floor's `secret` naming `hub-token`, or a command that opens the token store's files: a path whose parts match `.local/share/secret` or `.local/share/keyrings`, a glob included, or `hub-token.key` or `hub-token.enc` named from anywhere, since Bash keeps its folder between calls. The floor reads the token from its hooks (`hub_token`), never through a tool call, so nothing of its own meets the row. Like every row that reads command text, it doesn't see a name built at run time; behind it, sandboxed Bash is denied `~/.local/share/secret` by the `sandbox.credentials` row.

**The token store on Linux and WSL (W7).** `bin/secret` beside a member root's `harbor-member-mode` on Linux keeps each value as `<name>.enc` and its passphrase as `<name>.key` in `~/.local/share/secret` (0700, files 0600), never the Secret Service: under WSL's `login -f` start gnome-keyring has no unlocked "login" collection and no prompt to make one, and a hand-unlocked one locks again when the distro idles out. The store needs only `HOME`, so `MEMBER_HOOK_ENV` carries no bus names, and the install's token step runs as the member with no session. At rest it is as strong as the disk; against the agent it is as strong as the rows above. `member-install.sh --store-check` is the store's round trip on a throwaway value, from a hook's `env -i`.

## The resolver (harbor#1278)

`HUB_STATE` holds: `policy.json` and `policy.json.sig` (live), `last-good/` (the same pair), `repo/` (the hub clone, `scope-roots.sh --hub`), `hooks/<pack>/<path>`
(delivered hub hooks), `last-sync` (epoch and result, advisory). `bin/hub-sync.sh` is the only writer of the policy pair.

- **Proof.** A policy counts only if `ssh-keygen -Y verify -f <managed root>/hub-signers -I hub -n harbor-hub` accepts its bytes. `path` re-verifies on every call and prints
  the verified copy with the higher serial, so a one-byte edit falls back to `last-good`, and an older signed pair copied over the live one cannot roll the policy back.
  With no copy verifying, `path` prints nothing and `check` exits 1 (present, none verifies), 2 (none at all): a caller must read 1 as "stricter than the core
  defaults", not as "no hub", and on a marker box 2 as well (see Tiers and sets).
- **Fetch.** Signature first (nothing unsigned is parsed), then `hub-format.sh policy`, then the serial: lower is refused, equal is `unchanged` only for identical bytes.
  Exit 0 updated or unchanged, 1 refused, 3 unreachable. A 401, a 403 and a dead network are all 3 and change nothing.
- **Revoked** is derived, never stored: `state` is `revoked` only when a verified policy lists this login in `revoked`. `harbor hub leave --apply` then drops the hub
  packs, hooks, policy and clone on the agent side; the managed root, the settings and the member's access are IT's step. A pack it can't remove keeps the policy too, so the next
  session tries again, and the session note says which happened.
- **Pin.** `core.commit` and `core.contract` are read at sync and compared with the install stamp and `CONTRACT_VERSION`; a mismatch is shown by `harbor hub status` and
  acted on by IT until the updater is scheduled. `harbor hub pin-check <contract>` refuses a contract any `packs/*/extension.json` rejects. `member-update.sh` lands every row of
  `contracts/member-files.txt` at the pinned commit, verified blob by blob, so the data moves with the code that reads it.
- **What a hub pack carries.** A managed root is flat and holds no register, so `checks.md`, `controls.tsv` and `terms.tsv` are refused by name when the pack installs there.
- **Hub hook paths** in `hooks[].path` are relative to `packs/<pack>/harbor-pack/`; the pack must be listed in `packs`, and the hash is of the file at that pack's pinned commit.
- **The hub's address** comes from `HARBOR_HUB_REPO` alone on a member laptop: `HARBOR_HUB_REMOTE` is ignored beside `harbor-member-mode`, because that URL gets the token.
- **Token.** The ref `hub-token`, read through the sibling `secret` in the managed root (the one function `hub_token`, marked W7), sent only as an `Authorization` header in the fetch child's environment. `hub-sync.sh token` says whether one can be read and prints nothing.
- **Beside the policy.** `hub-sync.sh path` names `policy.json`; `policy.json.sig` sits next to whichever copy it names, because `hub-approval.sh` and `member-update.sh` verify it again.
