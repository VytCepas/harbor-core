# clean

Everything cited exists or is not a path.

- Link: [the tool](bin/tool.sh) and a section link [intro](#intro) and [site](https://example.org/a/b.md).
- Span: `bin/tool.sh`, with a line suffix `bin/tool.sh:12`, a directory `bin/` and a word in a command `sh bin/tool.sh --help`.
- A bare name is prose, not a path: `GONE.md`, and so is a dotted name `permissions.deny`.
- Not repo paths: `~/.claude/gone.md`, `/etc/gone.conf`, `bin/*.sh`, `<system>/x.md`, `a/b` and `and/or`.

```sh
sh bin/gone-in-a-fence.sh
```
