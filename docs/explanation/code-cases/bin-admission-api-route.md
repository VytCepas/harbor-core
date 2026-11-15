---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-api-route.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-api-route.sh, lines 6-61 (before this edit)

```text

WHAT HAPPENED. 2026-09-17 20:58Z: a subagent probing `--help` across a
scaffolded project ran its `setup_models.sh`, which ignores its arguments and
installed claude-code-router 3.1.0. The router's first run backed up
~/.claude/settings.json and wrote `apiKeyHelper` and
`env.ANTHROPIC_BASE_URL=http:\/\/127.0.0.1:3456` (plus two sibling URLs) into it.
Claude Code reloads settings live, so from 20:59:00Z every request from the
session, its four subagents and the permission classifier went to a port
nothing listened on — "Connection refused" — until a person restored the file
by hand the next morning.

WHY A COMMAND GUARD IS NOT ENOUGH. The command the floor saw was
`python3 help_probe.py <dir>`. Nothing in its text names the write, so
guard-bash (which refuses the router and its installer BY NAME) cannot be the
whole answer. This hook reads the RESULT instead of the command.

WHAT IT DOES. After every shell or file tool call, and at session start, it
reads the settings files Claude Code loads — the config dir's settings.json and
settings.local.json, and the project's .claude/ pair — for the keys that decide
WHERE requests go and HOW they authenticate, and holds each file against the
copy of it this guard last ACCEPTED:
  - FIRST SIGHT. Whatever the file already says becomes its accepted copy,
    route keys included, and is never rewritten: it predates anything this
    guard watched, and deleting an operator's existing credential or proxy on
    the first run would itself lock Claude Code out (Codex, harbor PR #547). A
    route key found then is reported once, so a stale reroute is not kept in
    silence.
  - ACCEPTED BEFORE. A route key ADDED since, or pointed at a new value, is put
    back by restoring the accepted copy byte for byte. A key the file dropped
    is not a reroute, and any other change is accepted.
  - SEEN ABSENT, NOW PRESENT. The file arrived under watch, so every route key
    in it is new: those keys are deleted with jq and the rest is kept.
The rerouted copy is kept beside the file as evidence, and the tool call is
answered with a block reason naming the keys, so the agent that ran the
command learns what it did before its next request leaves the machine.

THE ACCEPTED COPIES ARE A TRUST ANCHOR: a session that could write one could
bless its own reroute, and one that could DELETE them could make its reroute a
first sight. So they live in $CLAUDE_CONFIG_DIR/.helm-apiroute/, not in cache/
(which is anyone's to wipe: 'rm -rf ~/.claude/cache' in the same call as a
reroute had it baselined, measured), and guard-selfedit and guard-bash protect
that directory like the allow list below.

NOT A BAN ON GATEWAYS. An operator who wants one lists the key names, one per
line, in $CLAUDE_CONFIG_DIR/.helm-apiroute-allow. guard-selfedit and
guard-bash protect that file, so a session cannot allow itself.

KEYS, NEVER VALUES, in every message: an ANTHROPIC_AUTH_TOKEN value is a
credential. Values are compared inside jq and never printed. Registered in
docs/reference/checks.md as `admission.api-route`; every repair is stamped `[check:admission.api-route]` in
$CLAUDE_CONFIG_DIR/cache/checks.log.

FAILS OPEN. An error in this hook must never stop a session doing ordinary
work, so every path exits 0; only the message on stdout carries a verdict.
`-u` without `-e`, for that reason: a failing command inside a repair must
fall through to the next step and the report, never abort the hook.
```

## bin/admission-api-route.sh, lines 69-71 (before this edit)

```text
ONE jq for both payload fields. This runs after every shell and file call and
a spawn costs ~4 ms on this box (measured), so the common path is held to a
handful of them: the first draft spawned ~30 and cost 120 ms a call.
```

## bin/admission-api-route.sh, lines 76-79 (before this edit)

```text
The project whose .claude/ settings Claude Code loaded is the one it was
launched in, which the harness names in CLAUDE_PROJECT_DIR. The payload cwd
follows a `cd` inside the Bash tool, so it is only the fallback — the order
floor_in_repo uses.
```

## bin/admission-api-route.sh, lines 85-86 (before this edit)

```text
The keys that pick Claude Code's endpoint, provider, proxy or credential. Env
keys are read under `.env`; `apiKeyHelper` is top-level.
```

## bin/admission-api-route.sh, lines 91-92 (before this edit)

```text
routes_only — key names on stdin, kept only if they are route keys and not on
the operator's allow list; printed space-separated.
```

## bin/admission-api-route.sh, lines 99-101 (before this edit)

```text
key_names <file> — the route-key names the TEXT of <file> sets. It stands in
for jq when jq is missing or cannot parse a file caught half-written, so a
write is never missed for want of a parser.
```

## bin/admission-api-route.sh, lines 106-106 (before this edit)

```text
route_keys <file> — every route key <file> sets.
```

## bin/admission-api-route.sh, lines 116-118 (before this edit)

```text
added_keys <file> <accepted> — the route keys <file> sets that <accepted> does
not set to the same value: added, or pointed somewhere new. Without a parse of
both it compares names, so a new key is still caught and a changed value is not.
```

## bin/admission-api-route.sh, lines 136-138 (before this edit)

```text
in_step <file> <copy> — the two mtimes are equal. find, not test's -nt/-ot,
which POSIX lacked before 2024 (harbor#811): an operand prints only when it is
no newer than either, so both print only when equal. -L follows a symlink.
```

## bin/admission-api-route.sh, lines 145-149 (before this edit)

```text
accept <file> <copy> — make <file>'s bytes the accepted state. `cp -p` carries
the mtime across, so "in step" is an mtime test (one find), and a copy is made
only when the file really changed. Once a copy exists, a file jq cannot parse
never replaces it: a half-written copy restored later would break the very
settings it was kept to repair.
```

## bin/admission-api-route.sh, lines 160-162 (before this edit)

```text
mark <path> — record that a settings file was ABSENT when this guard looked,
so one that appears there later is known to have arrived under watch. `: >` is
a shell builtin: once its directory exists, a marker costs no spawn.
```

## bin/admission-api-route.sh, lines 169-169 (before this edit)

```text
stamp <file> <keys> <action> — the registry line every verdict carries.
```

## bin/admission-api-route.sh, lines 182-183 (before this edit)

```text
The project directory is often $HOME, where `$PROJ/.claude` IS the config dir:
one file, one check.
```

## bin/admission-api-route.sh, lines 207-208 (before this edit)

```text
FAST PATH: the route keys are JSON keys, so a file whose text never names one
cannot set one. One grep across every file decides which need the full read.
```

## bin/admission-api-route.sh, lines 224-225 (before this edit)

```text
A file that names no route key cannot have added one, and one
byte-identical to its accepted copy has changed nothing.
```
