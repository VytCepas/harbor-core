# hooks/

Two kinds of thing run on an event, and both live here.

- **Git hooks**: the files at this level (`pre-commit`, `pre-push`, …). `git config core.hooksPath hooks` turns them on
  in a checkout (CONTRACTS/README.md).
- **Hook engines** (D-88, harbor#1272): one folder per non-floor Claude Code hook engine, `hooks/<engine>/`, holding
  `<engine>.sh`, its tests and `manifest.tsv`. The floor's guards stay in `bin/`, pinned by hand.

## The manifest

`hooks/<engine>/manifest.tsv` says what a stranger needs to know. Mode and red proof are not here: they are the
engine's rows in `standards/naming/controls.tsv`.

```
key	value
engine	session-title
wire	UserPromptSubmit	-	5
wire	SessionStart	-	5
senses	the title the model wrote for this session
acts-on	the session title, via sessionTitle
findings	none: it prints nothing unless a title file exists
closer	nobody
```

- `engine` is the folder's name. `wire` is `event`, `matcher` (`-` for every tool or source, `@derived` when the
  payload's installer computes it) and `timeout` in seconds (`-` for the harness default), one row per binding.
- `senses`, `acts-on`, `findings` and `closer` are the engine's place in its control loop (`closer nobody` marks an
  open loop).
- `#` lines are comments: the why of a binding (its event, its timeout) sits above the rows it explains.

## Wiring

`runtime-install.sh` copies each engine flat into `~/.claude/bin/<engine>.sh` and writes its wiring with
`bin/deploy-hooks.sh`. `sh bin/deploy-hooks.sh --plan ~/.claude` shows what is wired and what would change. The wiring is rendered from the
manifests, never edited by hand: `--settings` re-renders only harbor's own entries, and an engine whose entries already
match is left as it is.

**Turning one off:** `touch ~/.claude/<engine>.off`, then deploy. A binding you delete from `settings.json` by hand
also stays deleted; add it back by hand to wire it again, and the next deploy keeps it.

## Libraries

An engine sources its libraries (`guard-lib.sh`, `log-lib.sh`, …) from its own directory, as every installed script
does. Deployed, that is `~/.claude/bin/`, beside them. Run from the repo, the engine finds its `manifest.tsv` beside it
and looks in `../../bin` instead: one line, at the place it resolves its directory.
