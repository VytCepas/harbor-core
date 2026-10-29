# The private layer - `harbor-private/`, data only

**Seam:** core reads it; nothing in it is code, except `harbor-pack/`, a pack the pack loader installs and gates like any
other (harbor#1273). Shape from `DESIGN.md` (harbor#966 amended, harbor#1149).
The directory is `${HARBOR_SCOPE_PRIVATE:-$PORT_ROOT/harbor-private}`, with `PORT_ROOT` as in
[port-root.md](./port-root.md). `harbor scope install` creates it and never overwrites a file in it.

| File | Format | Read by |
|---|---|---|
| `repos.tsv` | `id` TAB `path` TAB `kind` TAB `remote`; `#` lines and the header skipped | `bin/roots.sh --repos`, `--repo <id>`, `--remote <id>`, `--registry-check`; through `--repo` and `--remote`, `bootstrap.sh` finds a pack's checkout and where to clone it from |
| `harbor.toml` | flat TOML subset (below) | `bin/roots.sh --conf <key>`; `bin/deploy.sh` and `bin/bootstrap.sh` read `components` and `packs` through it |
| `terms.tsv` | client and system terms, in the core `terms.tsv` columns | `bin/lint-name.sh`, the naming overlay (D-85) |
| `leaks.tsv` | the leak gate's patterns, never terms: `id` TAB `kind` TAB `pattern` TAB `note`, kind one of literal, word, domain, email-domain, regex | `bin/lint-leaks.sh` (D-79, D-85; harbor#1149) |
| `leaks-baseline.txt` | one number: the private leak count, which only goes down | `bin/lint-leaks.sh --check`, when the file exists |
| `access/` | account, role and route cards; names only, never a secret; format in [access-card.md](./access-card.md) | `bin/roots.sh --access`, the one resolver; through it `skills/access-ledger/bin/check-routes.sh`, `skills/topology/bin/check-topology.sh`, `context-rules/user/access-route.sh` and lint `doc.urls-cited` |
| `access/register.md` | the identity register: one `## <id>` entry per account, role, app, mailbox or token, each with a `secret:` reference, never a value; created with a header only; format in [access-register.md](./access-register.md) | `bin/access.sh` (`harbor access`), the one reader; through it `bin/secret`, which refuses a ref no entry names |
| `context-rules/` (`inject.d/` until it moves, harbor#1010) | the rule packs that name a client or one of its repos, in the shape of core's `context-rules/`: `user/` (`box/` under `inject.d/`; the `.md` packs every session carries, and `projects.tsv`, the registry: `name` TAB `~/path` TAB `what it covers`), one folder per repo (`<name>/*.md`, seeded into that repo by `--projects`) and `notes.tsv` (their probe rows, in the columns of `fixtures/inject/notes.tsv`); see [`context-rules/`](#context-rules) | `bin/roots.sh --inject` and `--projects`, the resolver; through it `bin/inject-install.sh`, `bin/memory-route.sh`, `bin/access-environment.sh`, `bin/scope.sh`, `tests/hooks/inject-notes-test.sh` (`HARBOR_NOTES_PRIVATE`) and lint `IJ1`..`IJ5`. Absent is core's box tier alone, no registry and nothing to seed |
| `checks.md` | private check rows (client monitors): a fragment in the register's own shape, see [`checks.md`](#checksmd) | `bin/check-registry-generate.sh`; through it `runtime-install.sh`, `install-drift.sh`, `findings.sh`, `lint-conventions.sh` (`drift.launchd-plist`, `audit.finding-lanes`) |
| `controls.tsv` | the `check.<id>` control rows of those checks, in the core `standards/naming/controls.tsv` columns | nothing yet: `bin/lint-name.sh` overlays `terms.tsv` only |
| `jobs/` | private scheduled jobs: the launchd plists of the checks in `checks.md` and in `harbor-pack/checks.md` (a pack ships no plist, harbor#1273), named `com.harbor.<id>.plist` | `drift.launchd-plist` (the plist a row owes) and `renew-check.sh` (built here, installed nowhere). Core has no plist installer either: the operator copies a plist into the LaunchAgents folder, from `jobs/` here and from `launchd/` there |
| `browser-hosts.txt` | hosts `harbor chrome` admits beyond core's allowlist (an operator's own vendor stack, a company's internal UIs and its partners', a client's tools, an operator's own tenants and coursework), in the allowlist's own shape: a line admits the host and its subdomains, under a comment saying why | `bin/browser-agent.sh` (the `goto`/`tab-new` host check) and `context-rules/user/browser-route.sh`, each after the core list. Absent is the core list alone |
| `confinement-hosts.txt` | hosts a confined shell command may reach beyond core's `CONTRACTS/confinement-hosts.txt` (the APIs a workload's tools call), in core's shape: one host per line, `*.` for subdomains, under a comment saying why. Keep it short (#555 decision 11): each new row is an operator `sudo` install | `bin/deploy-confinement.sh`, after the core list, deduplicated. Absent is the core list alone, byte for byte; a row that does not compose, or a file that exists and cannot be read, refuses the install |
| `confinement-paths.txt` | write, deny-write and read rows beyond core's `CONTRACTS/confinement-paths.txt` (a workload tool's cache or config dir, its CA bundle), as `<kind> <path>` with `@PORT_ROOT@` and `@DELIVERABLES@` resolved; paths are resolved paths, since Seatbelt ignores a symlinked spelling | `bin/deploy-confinement.sh`, after core's rows, same refusals. Absent is core's rows alone |
| `citations.md` | the rows of `CITATIONS.md` for hosts core does not name, same row shape | lint `doc.urls-cited` (T7), beside `CITATIONS.md`. Absent is the core ledger alone. A hand-kept ledger: `bin/cite-verify.sh` fetches the tree's URLs, not these |
| `notes/` | free-form markdown, one file per subject, never parsed | the skill or core page that names the file (`BOUNDARY.md` names `notes/boundary.md`, the stubs of D-45, D-55 and D-69 name `notes/repo-names.md`, harbor#1273), by the path its own `SKILL.md` prints through `sh bin/roots.sh --private`: `dev-tracking` (this layer's own pack) reads `notes/dev-tracking.md`. Facts a skill must not carry (a project, a host, an org, a workspace id) live here, and the skill says what to do without them. Absent is no facts, not an error |
| `port-paths-exempt.tsv` | the rows of `CONTRACTS/port-paths-exempt.tsv` for every repo but harbor's own (a client's directory, a sibling's file), in the same columns | `bin/port-paths.sh`, after the core table. Absent, unreadable or no layer is the core table alone, and those lines count again. `PORT_PATHS_EXEMPT`, when set, names the only table read |
| `required-checks.tsv` | the rows of `CONTRACTS/required-checks.tsv` whose repo cannot be named in a public tree (the operator's private repos, another org's): `repo` TAB `check name`, exactly as `gh pr checks` prints it; `#` and blank lines free. It adds a required check for any repo and removes none core lists. **Not a protected path:** core's file is class `ci-gate` and needs the operator's approval to change, an edit here needs none and is read at once by a checkout run, so a row belongs here only when core cannot carry it; `harbor deploy` lists any row the new installed list drops | `bin/gate-required-generate.sh`, which prints core's rows then this file's; through it `runtime-install.sh` (the installed `bin/required-checks.tsv`, which an installed `gate-merge-stack.sh` reads and which has no `roots.sh` to find a layer with), `install-drift.sh`, `merge-check.sh` and `pr-wait.sh` (their default list, run from a checkout) and `gate-merge-stack.sh` (harbor's rows, run from a checkout). Absent, empty or no layer is core's rows alone, byte for byte. A file that does not compose (a row that is not `owner/name` TAB check) or exists and cannot be read (a directory, a dangling link, no read permission) refuses the install and `pr-wait.sh`, and leaves `merge-check.sh` on core's rows with a warning, so a typo never reads as "this repo requires nothing". `HARBOR_REQUIRED_CHECKS`, when set, names the only list read |
| `cli-contracts.tsv` | the contract a sibling repo's CLI on `~/.local/bin` is read through: a header `tool` TAB `repo` TAB `file` TAB `note`, then one row per tool, `-` for none; `repo` is a `repos.tsv` id whose checkout `bin/roots.sh --repo` finds, and a row whose repo is `-` prints its note. A row that cannot be read refuses the whole read (exit 1, or 3 under `--check`). Absent is core's own tools alone; any other tool reads **none yet** | `bin/skill-catalog.sh install` only: the tracked book never reads this layer (harbor#1273) |
| `skill-book-router.tsv` | rows for the "Start here" table of the installed skill catalog: a header `skill` TAB `situation`, then one row per skill; `#` lines skipped. A row for a skill that core's `CONTRACTS/skill-book-router.tsv` already routes replaces that row's text in place; any other is appended after core's rows; a row whose skill is not installed is not printed. A row that cannot be read (wrong header or column count, a skill twice, a name that is not one) refuses the whole read: exit 1, or 3 under `--check`, where 1 means a stale book. Absent is core's rows alone | `bin/skill-catalog.sh install` only: the tracked book never reads this layer |
| `CLAUDE.personal.md` | personal operating rules | the installed `CLAUDE.md` import, once built |
| `harbor-pack/` | a pack in the format of [pack.md](./pack.md), the layer's own: entries that are not harbor logic and belong to no workload repo (harbor#1273). The one directory here that holds code, so it gets the pack loader's gates (no hooks or guards, client-free, committed) | `bin/pack.sh` under the reserved id `harbor-private`, when `packs` lists it. Absent is no pack |
| `evals/` | dated eval plans and records over client data, moved out of core with a README that decodes the estate labels core uses (`evals/topology/`); the operator's skill-fire case files (`evals/skill-fire/`, for `bin/skill-fire.sh --cases`) and `harbor-evals.md`, which decodes the workload labels of core's `EVALS.md` (harbor#1273) | nothing: a record, never installed or read by a tool |

## `repos.tsv`

- `id` is a repo name (`[A-Za-z0-9][A-Za-z0-9._-]*`), unique.
- Exactly four fields. `path` is relative to `PORT_ROOT`: no leading `/`, `~` or `$`, no `..`, `.` or empty
  segment; one trailing `/` is dropped. A row that breaks this, repeats an id, or repeats a path (case
  ignored) refuses the **whole read** (exit 2, the file and line on stderr), because skipping it would
  answer "unknown" for a repo that is only mistyped. A checkout that exists must also resolve, symlinks
  followed, inside `PORT_ROOT`, and not to the same directory as another row.
- A UTF-8 BOM and CRLF line endings (here and in `harbor.toml`) are stripped with a note on stderr.
- `kind` is an `id` in `standards/naming/repo-kinds.tsv`. Only `--registry-check` judges it, so a
  vocabulary edit never breaks a lookup.
- `remote` is a URL with no credentials, or `-`. `bootstrap.sh` clones a missing checkout from it: an `https://` URL, or a github.com
  `owner/repo` (`https://`, `git@github.com:` or `ssh://git@github.com/`; `gh` when logged in, else git over https). `-` means
  `<owner of harbor's origin>/<id>`. Anything else (a `user:token@`, `http://`, `ext::`, a query) refuses the run before any write.
- `--repo <id>` prints the resolved checkout. When a registry exists and lacks the row it is "not registered": exit 1, nothing on stdout.
- `--remote <id>` prints the row's `remote`. No registry, no such row, and a remote of `-` or empty are each exit 1 with nothing on stdout (the caller then applies its own rule); an unreadable registry is exit 2.
- `--get <VAR>` for a `roots.tsv` row on the workspace base (`HARBOR_ORCHESTRATOR`, `HARBOR_FLEET_FILE`, `HARBOR_PROJECT_INIT`) follows the registry: the row's first path segment is a repo id, and the registry's path for it replaces that segment. An id the registry lacks, or no registry, keeps the table's path; an exported override wins over both. A script that needs a sibling's checkout asks for its role this way and names no repo (harbor#966).
- **No registry file:** `--repos` answers from `CONTRACTS/roots.tsv`, and `--repo <id>` prints `PORT_ROOT/<id>` whether or not that directory exists, the old literal, so a box with no layer behaves as before. `harbor scope install --seed-from-projects` writes the registry.

## `harbor.toml`

One `key = "value"` or `key = ["a", "b"]` per line, `#` comments, no tables. Unknown keys, duplicates and
any other shape (a backslash or an empty string inside a value included) are refused (exit 2), so a typo is never read as "unset".

| Key | Meaning | Default |
|---|---|---|
| `packs` | workload repos whose `harbor-pack/` is installed box-wide | unset (exit 1) |
| `components` | `core` plus any of: `yard` (project-init), `fleet` (projects-orchestrator), `prod-guard`, `collector` (installed by root: `sudo sh bin/collector-setup.sh`, never by deploy) | unset = the legacy full set (transitional; the template seeds `["core"]`) |
| `channel` | `main` or `stable` | `main` |
| `deliverables_dir` | where deliverables land | unset |
| `worklog_repo` | the private repo the work log pushes to | unset |
| `mail_account` | the mailbox a `cu` message link opens in (`?authuser=`) | unset: the link carries no authuser and opens the browser's default account. `CU_MAIL_ACCOUNT` and a caller's argument win. `cu` installs by copy, so it reads this one line itself instead of calling `roots.sh` |
| `github_owners` | GitHub owners besides the operator's own account whose issue URLs `ticket-note.sh` counts as the operator's tickets | unset: the operator's account alone. `TICKET_NOTE_GH_OWNERS` replaces the whole list |
| `live_walk_repo` | the `repos.tsv` id of the repo client live sites are walked through, which `harbor chrome` names when it refuses a client host | unset: the refusal says no live-walk repo is set, never a guessed path |
| `browser_live_url` | the storefront `harbor browser --self-test-live` loads, one with a consent banner | unset: that arm is SKIPPED (exit 2), never a pass. `HARBOR_BROWSER_LIVE_URL` wins |
| `confinement_strict` | `"true"` closes the confinement's unsandboxed retry (#555 P4): `deploy-confinement.sh` writes `allowUnsandboxedCommands: false`. The operator's edit, after the P1 week passes #555 decision 10 | unset = `false`: the retry stays open |
| `confinement_credentials` | `"true"` writes the `secret` rows of the confinement paths as `sandbox.credentials` deny (#555 P5) | unset = `false` |
| `confinement_skip` | `"true"` lets a confined Bash call skip the admission rules `controls.tsv` marks `covered` (#555 P3). The operator's edit, after decision 10 (b) passes | unset = `false`: every rule runs on every call |

Keys only a pack's own tools read are that pack's schema: it declares them in `conf-keys.txt` ([pack.md](./pack.md)) and documents them. `roots.sh` still accepts the measurement pack's three for one release, so a box that has not installed the pack does not stop on its private `harbor.toml`.

**A new key reaches a box after the code that reads it.** `roots.sh` refuses a key it does not know, so a harbor checkout that
predates a key cannot read the file: `deploy.sh` stops before it writes anything, `check-exposure.sh` says it could not read it, and `browser.sh` and `ticket-note.sh` read the key as unset.
Before merging a private-layer branch that adds a key, run `HARBOR_SCOPE_PRIVATE=<private checkout> sh <harbor checkout>/bin/roots.sh --conf packs`:
exit 2 and `unknown key` mean that harbor checkout is too old to take it.

## `checks.md`

A markdown fragment, not a TSV: a check row is five free-text cells full of backticks and commands, and the register
it joins is a markdown table that people and `grep` read. A fragment in the register's own row shape composes by
inserting lines, loses nothing and needs no converter in either direction (harbor#1149).

- Sections, each optional, each once: `## Register` (rows exactly as in core `CHECKS.md`: five cells, the id in
  backticks), `## Platforms` (`| id | platforms | why | disable |`, the id bare) and `## Notes` (prose). Blank lines
  and one-line `<!-- ... -->` comments are free; anything else outside a section is refused.
- Core `CHECKS.md` carries `<!-- private:register -->` at the end of its Register table and `<!-- private:platforms -->`
  at the end of its Platforms table. The register rows go in at the first, the platforms rows at the second, the notes
  at the end of the file under `## Private notes`.
- `sh bin/check-registry-generate.sh` prints the composed register. With no layer, or no `checks.md`, it prints core
  unchanged, byte for byte. A fragment that does not parse (a bad row, an id twice or already in core, a register row
  without its platforms row or the reverse, rows with no insertion point) refuses the whole read: exit 2, nothing on stdout.
- **One registry per box.** `runtime-install.sh` installs the composition as `bin/CHECKS.md`, and `install-drift.sh` holds
  that file to the composition at the ref. An installed pack's `checks.md` is the same fragment and joins the same
  composition after the private rows (`--packs`, [pack.md](./pack.md#the-register-one-file-composed)). Nothing reads two registries: a reader opens the composed file, or goes through
  the generator.

## The floor does not read any of it

`guard-*`, `guard-lib.sh` and `floor-*` never open `repos.tsv` or `harbor.toml`: they are POSIX, pinned
per file (B6) and must answer with no I/O they do not control. Anything the floor needs from here is
copied in as a literal and checked equal by a rule, as `ROOT1` does for `PORT_ROOT`.

## `access/`

The access register: one card per system plus the generated `ACCOUNTS.md` and `DISPATCH.md`. `sh bin/roots.sh --access`
prints its directory (`$ACCESS_DIR` when set, else `<private>/access`) and, when there is none (no layer, no `access/`,
or an `ACCESS_DIR` that is not a directory), prints nothing, says why on stderr and exits 1. No reader treats that as a
pass: the route gate exits 2, the topology check says it skipped, the access-failure note stays silent, the lint rule
reports "skipped: no private layer". The floor does not read it.

`access/routes.tsv` is the one file in it that is not a card: the command-to-card table `context-rules/user/access-route.sh`
reads (format in [access-card.md](./access-card.md)). Absent, the access-failure note stays silent.

`access/vocabulary.tsv` is the register's own words (harbor#1273): `kind` TAB `pattern` TAB `card`, a `system` row for each name
`check-routes.sh --coverage` looks for and the card that covers it, a `role` row (card `-`) for each role-directory label an
`identity:` or `account:` must not stop at, beside core's generic ones. A row that cannot be read refuses the run (exit 2).
Absent, `--coverage` says NOT CHECKED (exit 2) and the gate holds core's labels alone.

## `context-rules/`

Core's `context-rules/` holds `user/` (the box tier) and `harbor/` (harbor's own repo rules) and nothing else: the packs
every box needs and none that names a client or another repo. The rest is here, in the same shape. `sh bin/roots.sh
--inject` prints `<private>/context-rules`, or the old `<private>/inject.d` while the layer has not moved (harbor#1010), and
`--projects` the registry, `<rules>/user/projects.tsv` (`box/projects.tsv` under `inject.d/`); with no layer, neither
directory or no registry each prints nothing, says
why on stderr and exits 1, and no reader treats that as a pass: the installer is core alone, `memory-route` stands
down naming where it looked, and lint IJ2 says it did not check.

- **It is data.** `bin/inject-install.sh` copies only `*.md` and `projects.tsv` from `user/` (or `box/`) into
  `<config>/context-rules/user`, where every session's hook reads them. A script, a link, any other file, or a name core's `context-rules/user/` already
  ships is refused (a dry run exits 1, `--apply` writes nothing): a private file never replaces a shipped pack. The
  repo folders are held to the same rule when `--projects` seeds them, since the engine runs a pack's `run:` script in
  the repository they land in: only flat `*.md` files cross, and a script, a link, a subfolder or any other file
  refuses the run.
- **The matcher includes them.** The tool matcher the installer wires is derived from every pack the engine may meet,
  the private repo packs among them, so a private pack on a tool no core pack names is still invoked.
- **`--projects` seeds from here.** The installer's `--projects` step copies `<private>/context-rules/<name>/` (or `inject.d/<name>/`) into the
  project the registry row `<name>` names (the existing `.claude/inject.d` goes to the run's backup first); a folder
  with no row is skipped and says so.
- **`notes.tsv`** carries the probe rows of these packs. `HARBOR_NOTES_PRIVATE=<layer> sh tests/hooks/inject-notes-test.sh`
  runs them beside core's `fixtures/inject/notes.tsv`.
- **Merge order.** The layer holding these packs lands before the core change that removes them from core, or
  a deploy between the two installs a box with neither.
- **The move (harbor#1010).** Moving this folder to `context-rules/` is one private commit: `inject.d/box/` becomes
  `context-rules/user/` with `projects.tsv`, each `inject.d/<name>/` becomes `context-rules/<name>/`, each `NN-x.md` becomes
  `<id>.md` with `order: NN` where order matters, and `notes.tsv` moves with them. Core reads either layout until the
  `dir:inject.d` row's date in `standards/naming/renames.tsv`.

## The tree names no sibling repo

`bin/lint-siblings.sh` counts every occurrence in the tree of another repo's path (`~/port/<x>`, `$HOME/port/<x>`
in any quoting, `$PORT_ROOT/<x>`, `$PORT/<x>`, `/Users/<u>/port/<x>`; `x` not harbor), outside tests, fixtures and
`EVALS-DATA`. `CONTRACTS/lint-siblings-baseline.txt` holds the count and its derivation, and only goes down;
lint `lint.sibling-literals` is red above it. Reach a sibling with `sh bin/roots.sh --repo <id>`.

## The tree names no client, company or account

`bin/lint-leaks.sh` counts occurrences (not files) of what names an entity: the generic patterns in
`CONTRACTS/leak-patterns.tsv` (core count, baseline `CONTRACTS/lint-leaks-baseline.txt`, lint `lint.leaks`), and,
where this layer exists, its `leaks.tsv` rows plus the client and system rows of its `terms.tsv` matched as whole
words, where `_` ends a word as a space does (private count, baseline `leaks-baseline.txt`). Both ratchets count the whole tracked tree, dev-only notes
included; `layers.tsv` never narrows them. `LEAKS_EXPORT=1` is the write gate: it scans a
staging checkout whole, as text, with no exclusions and no `layers.tsv`. `--check` ratchets both, `--zero` is red on any match and
will gate `harbor deploy push`, `--list` gives `file:line:pattern-id`. No mode prints a private pattern's text. An
absent layer is not an error; a malformed file is a finding.
A client whose name is also an English word gets no `terms.tsv` row, which would match it bare: its `leaks.tsv` rows
name it instead, a `domain` row and a case-sensitive `regex` row for its capitalised, upper-case and `-`/`_`/`/`-joined forms.
