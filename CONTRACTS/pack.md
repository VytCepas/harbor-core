# The pack loader - `harbor pack`

**Seam:** a workload repo's `harbor-pack/` folder -> the config dir. `bin/pack.sh` is the only reader and writer
(harbor#1149, D-80, D-84). `harbor deploy` runs it (below); `harbor pack` runs it by hand.

Dependency direction: private -> workload/pack -> core. Core names no pack and no repo; `harbor.toml` `packs`
([private-layer.md](./private-layer.md)) lists the repo ids, and `roots.sh --repo <id>` resolves each checkout.
One id is reserved: `harbor-private` is the private layer's own `harbor-pack/`, its checkout the directory
`roots.sh --private` resolves, never a `repos.tsv` row, so `HARBOR_SCOPE_PRIVATE` moves the layer and its pack
together and a second spelling of the layer's path cannot drift from the first (harbor#1273).

## Verbs

| Command | Does |
|---|---|
| `harbor pack list (--live \| --dir PATH)` | installed packs (repo, name, version, commit, file count); listed ones not installed |
| `harbor pack install [<repo-id>...] [--apply] (--live \| --dir PATH)` | no id = every `packs` entry. Dry run unless `--apply` |
| `harbor pack remove <repo-id>... [--apply] (--live \| --dir PATH)` | deletes exactly what install wrote |

The target is chosen as every installer chooses it (`bin/install-lib.sh`): `--live` or `--dir PATH`, never
`CLAUDE_CONFIG_DIR`, and the live dir refused through `--dir`. Tests run on a throwaway `--dir`.

## `harbor-pack/`

```
pack.toml   name, version, harbor_version, description - all four, each a quoted string (flat TOML, D-81)
skills/<name>/...   bin/<file>   shims.tsv   conf-keys.txt   terms.tsv   context-rules/user/<file>.md (or inject.d/<file>.md until harbor#1010's date)   checks.md   controls.tsv   skill-packs/<core skill>/<name>.md   tests/ (never installed)   README* (ignored)
```

`checks.md` is a check-register fragment in exactly the shape of the private layer's [`checks.md`](./private-layer.md#checksmd):
`## Register`, `## Platforms` and `## Notes`, each optional, rows as in core `CHECKS.md`. `controls.tsv` (optional, and only
with a `checks.md`) is the `check.<id>` control rows of those checks in the core `standards/naming/controls.tsv` columns:
its header is core's, and every row's id is `check.<id>` of a register row in the same `checks.md`. A `checks.tsv` is retired
and refused by name. A pack ships no launchd plist: a scheduled check's plist is installed by the operator from where its repo keeps
it (the private layer's own pack: the layer's `jobs/`), and `drift.launchd-plist` does not read pack rows (harbor#1273).

`conf-keys.txt` (optional) declares the `harbor.toml` keys the pack's own tools read (#949): one key per line, `#` comments,
`[a-z][a-z0-9_]*`. Install puts it at `conf-keys.d/<repo-id>.txt`, and `bin/roots.sh --conf` accepts those keys beside core's
own (`roots.sh --conf-keys`), so core names no pack's key. Install refuses a core key, a key another installed pack declares,
and a malformed line; remove takes the keys back with the pack. Three keys core once read left it one release after
their pack declared them (#1273): with no pack installed, `roots.sh --conf <key>` refuses them (exit 2).

`terms.tsv` (optional) registers the workload's own system terms (harbor#950): core's `standards/naming/terms.tsv` header,
then one row per system, class `system` alone. Install puts it at `terms.d/<repo-id>.tsv`, and `bin/lint-name.sh` reads it
beside the private layer's overlay, so a system's env prefix and short name are known on the box while core's register names
no workload. Install refuses another header, another class, a term core already has, one another installed pack declares,
and a malformed id; remove takes the rows back with the pack. A system named here is public, since the pack is client-free; a
private system goes in `harbor-private/terms.tsv` instead, whose rows are leak patterns, so a pack naming one is refused.

`shims.tsv` (optional) puts the pack's commands on the operator's PATH: a header row `name` TAB `rel`, then one row per command,
`rel` a `bin/<file>` this pack installs. `bin/shim-install.sh` links `~/.local/bin/<name>` to the installed copy, so core's own
`CONTRACTS/shims.tsv` names no pack command and a box with no pack links none. Install refuses a row whose file the pack does
not install, a name core's table owns, a name listed twice, a name outside `[A-Za-z0-9._-]`, and a missing header.

`harbor_version` is a comma-separated AND of `[op]N[.M]`, op one of `>= <= > < =` (none means `=`). It is compared
with core's `CONTRACT_VERSION` in `bin/harbor` read as `N.0`. Only files git tracks at `HEAD` are installed.

## Refusals

A refused pack is **skipped by name** (`skipped <id>: <reason>`), nothing of it is written, the other packs still
install, and the run exits 1 so the skip is seen. Dry runs refuse the same way.

1. a `hooks/` directory or a `guard-*` file anywhere in the pack, matched case-insensitively (also any symlink, any path
   outside `[A-Za-z0-9._/-]`), and any installed `.md` whose front matter is not canonical: a BOM or an opener other than exactly `---`, no closing `---`, or a
   top-level line that is not `key: value` with a key in [pack-frontmatter-keys.txt](./pack-frontmatter-keys.txt) (never `hooks`);
   the leak gate also reads tracked files a `.gitignore` matches;
2. an inject pack with `run:` (it could deny, [inject.md](./inject.md)), a nested one, or a non-`.md` file in `context-rules/user/` (or `inject.d/`), or any other `context-rules/<scope>/`;
3. a `bin/` name equal to a core `bin/` file (with or without `.sh`, any case) or a `harbor` verb; a skill named like a core skill;
   a `skill-packs/` entry that is not [a pack for a core skill](#adding-packs-to-a-core-skill);
4. a dirty checkout (any change or untracked file under `harbor-pack/`) or an unpinned one (no git, or no commit);
5. a `harbor_version` core does not satisfy, or one that is not a constraint;
6. a `checks.md` that does not compose into the register beside core, the private layer and every other installed pack
   (a bad row, a register row with no platforms row, an id already in core or in another source: `check-registry-generate.sh`
   exits 2 on it, and the pack is skipped with its first FAIL line), or a `controls.tsv` that breaks the rule above.

Also refused: a repo id not listed in `packs`; a pack the leak gate flags (install stages exactly the files it will write
from `HEAD`, gates that copy with `LEAKS_EXPORT=1 bin/lint-leaks.sh --list`, tests and fixtures and binary files included,
and installs from the staged copy; a pack is client-free); and any target path that exists
and is not this pack's own manifest entry, so install never overwrites a core file, another pack's, or the operator's.
The one exception is the move below: a core skill core no longer ships, unchanged since core wrote it.

## Where things land

| Pack | Target |
|---|---|
| `skills/<s>/...` | `skills/<s>/...` |
| `bin/<f>` | `bin/<f>` (mode kept: executable or not) |
| `context-rules/user/<f>.md`, or `inject.d/<f>.md` | `context-rules/user/pack-<name>--<f>.md` |
| `skill-packs/<s>/<f>.md` | `skill-packs/<s>/<f>.md`, beside `skills/`, never inside it |
| `shims.tsv` | `shims.d/<repo-id>.tsv`, one file per pack; `shim-install.sh` reads them (`--live`: `~/.claude/shims.d`; `--dir`: `HARBOR_PACK_SHIMS_DIR`) |
| `checks.md` | `checks.d/<repo-id>.md`, one file per pack |
| `controls.tsv` | `checks.d/<repo-id>.controls.tsv` |

## Adding packs to a core skill

A core skill can read *domain packs* (`skills/topology/packs/`: one markdown file per domain, front matter the checker reads).
A workload repo adds one without claiming the skill: `harbor-pack/skill-packs/<core skill>/<name>.md`, installed at
`<target>/skill-packs/<core skill>/<name>.md`. It is **outside `skills/`** on purpose. A file a pack wrote inside a core skill's
own directory is a box-only file to `harbor skills` (`skills-install` refuses a skill whose installed copy holds files the repo
does not, and `--accept-loss` moves them away), so every core update of that skill would remove the pack or stop. A directory
of its own has no owner but the pack, and `skills/` stays what core tracks.

Install refuses an entry when:

- the skill is not a core skill with a `packs/` directory (core names the skills that read packs by keeping that directory;
  the match is exact, so `Topology` is not `topology`);
- core's `skills/<skill>/packs/` already holds a file of that name. A pack in two places is a duplicate, and the reader refuses
  it too (below);
- it is nested, is `README.md`, is not `.md`, or sits at `skill-packs/` itself;
- its front matter has a key outside [skill-pack-frontmatter-keys.txt](./skill-pack-frontmatter-keys.txt). That list is the
  keys the checker reads, because these files are data for a checker and the harness never loads them; it is not the general
  list above, and `hooks` is refused in both.

**The reader** is `skills/topology/bin/pack-path.sh`, sourced by `check-topology.sh` and by casefile's `check-pack.sh`. The
search path is the skill's in-tree `packs/`, then each directory in `TOPOLOGY_PACK_PATH` (colon-separated), then
`<config dir>/skill-packs/<skill>/`, found from the script's own place (`skills/<skill>/bin/../../../skill-packs/<skill>`), so
it names no home path and works in a config dir and in a test tree alike. Directories that do not exist are skipped, and a
directory reached twice (a symlink) counts once. `TOPOLOGY_PACK_DIR`, when set, is the one directory searched and nothing else.
A pack name found in two directories is a finding: `--pack`, `--detect`, `--packs` and the substance half exit 1 naming both
files, and none of them picks one.

## The install manifest

`<target>/.harbor-packs/<repo-id>.tsv`: `# repo|name|version|commit <value>` header rows, then `F<TAB><relpath>` for
each file written and `D<TAB><relpath>` for each directory install created. Install is idempotent: it rewrites its own
files, deletes ones an older install wrote and the new one drops, and keeps the `D` rows. Remove deletes the `F`
files, then the `D` directories deepest first when empty, then the manifest; a file the operator added beside them
stays, and so does its directory. It writes no backup or log into the target, so install then remove leaves the
target byte-identical.

## The register: one file, composed

`bin/check-registry-generate.sh --packs <config dir>/checks.d` composes core `CHECKS.md`, then the private layer's rows, then
each installed pack's by repo id, into the ONE `bin/CHECKS.md` (notes under `## Private notes` and `## Pack notes: <repo-id>`).
An id twice across core and any fragment refuses the whole read: exit 2, nothing on stdout. Three writers keep the installed
file equal to that composition: `runtime-install.sh` (it passes the target's `checks.d`, so reinstalling the runtime keeps a
pack's rows), `pack.sh` (install and remove recompose it when a pack carried a `checks.md`, and only when the target already
has a `bin/CHECKS.md`; otherwise the next runtime-install composes it) and `install-drift.sh` (it holds the file to the
composition with the target's `checks.d`, and does not count a file a pack manifest owns as `unsourced`).

## `harbor deploy`

`harbor.toml` `packs = ["<repo-id>", ...]` is the list. Deploy's `packs` component runs `bin/pack.sh install` for it, after
`inject` (inject-install rebuilds `context-rules/user` from scratch and so drops a pack's notes, which is why `--only inject` re-runs
the packs too) and before the skill catalog, which is generated from the skills the box then holds, a pack's included. No
`packs` key, or an empty one, means no packs: one note, and `pack.sh` is not run. A pack `pack.sh` refuses fails the dry run's
preflight and an apply's install, and the failure line carries `skipped <repo-id>: <reason>`, with the pack's own fix line
relayed. Deploy's snapshot covers `checks.d`, `skill-packs` and `.harbor-packs`. A box-tier note a pack's manifest owns is not counted as
"bytes in no commit" by the preflight.

`harbor deploy --only floor --uninstall` removes every installed pack (`pack.sh remove`), writes the installed skill catalog
again without their skills (`skill-catalog.sh install`), and fails its verify if a manifest in `.harbor-packs` or a fragment in
`checks.d` is left, so no pack row survives in the register or the book. The book a pack's skills appear in is the
installed one: the tracked `skills/skill-catalog/SKILL.md` lists only the skills the repo ships and a pack never reaches it.

## A skill that moves from core to a pack

`skills-install` never deletes a skill core no longer tracks, so after the core change merges, the box still holds core's
copy. The pack takes it over: a `skills/<s>/` file core's `.harbor-manifest` names, whose skill is in neither `skills/` nor
`vendor/skills/` of core, and whose bytes are still the blob that manifest recorded, is overwritten by the pack and its row
leaves core's manifest (the dry run says `taking over N file(s) core no longer ships`). A file edited since core wrote it,
or one no manifest names, is the operator's and still refuses (`already exists in the target and is not this pack's`).
The box then holds the same skill names it held before; only the files' source changed.

### Merge and deploy order for the business-skills move

The order matters, because core refuses a pack whose skill shadows a core skill, and deploy turns that refusal into a
preflight FAIL. Out of order, every `harbor deploy` is blocked.

1. Merge the pack branches in their own repos (the measurement pack, then the mail-and-calendar pack) and check the
   measurement pack out in its live checkout.
2. Merge the core change (this one) and let the live checkout pull it.
3. Nothing to move: the pack takes over core's unchanged copy (above). A skill file edited on the box refuses by name;
   move that one out of the config dir, or keep the edit in the pack's repo first.
4. Re-point the `*-v19-check` link in `~/.local/bin` (see below), merge the private `packs` manifest, then
   `harbor deploy`.

### A command that moves with its skill

The `bin/*-v19-check` consent-check script left core with its skill, and its `CONTRACTS/shims.tsv` row went
with it. The live link in
`~/.local/bin` points into the core checkout, so it dangles once the checkout pulls step 2. `shim-install` does not
report it (its unmanaged-link check matches `$HOME`-relative targets against a prefix that does not cover `port/`).
After step 2, repoint the link at the pack repo's copy of the script, or remove it; the pack repo's tree owns the target.
