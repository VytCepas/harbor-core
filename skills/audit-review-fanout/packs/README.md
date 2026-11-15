# Rule sets for the standards lenses

The three standards lenses (`lenses/naming.md`, `lenses/constitution.md`, `lenses/registration.md`) ship in core and name
no company. A company's or a workload's own rules reach them as **rule-set files**, read by the lens itself:

- one Markdown file per rule set, named `<lens>-<topic>.md`, where `<lens>` is `naming`, `constitution` or `registration`;
- no front matter (the pack loader allows only the keys in `contracts/skill-pack-frontmatter-keys.txt`, and a lens needs none);
- the body states each rule and, where one exists, the command that decides it.

Where they come from, by share (harbor/D-83):

| Share | Ships as | Lands at |
|---|---|---|
| core | this directory (`README.md` is never a rule set) | the installed skill |
| workload | the workload repo's `harbor-pack/skill-packs/audit-review-fanout/<lens>-<topic>.md` (`contracts/pack.md`) | `<config dir>/skill-packs/audit-review-fanout/` |
| hub | the same path inside a hub pack, pinned by the signed policy (`contracts/hub.md`, `harbor pack install --hub`) | `<config dir>/skill-packs/audit-review-fanout/` on each member laptop |

`<config dir>` is `$CLAUDE_CONFIG_DIR`, else `~/.claude`. A workload's naming words need no rule set: `bin/lint-name.sh`
already reads the repo's own registry and the private layer's terms (`standards/naming.md` §13, §14), and the naming lens runs it.
