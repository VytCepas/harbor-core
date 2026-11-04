---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-self-edit.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-self-edit.sh, lines 4-17 (before this edit)

```text
Blocks an agent from editing the Helm floor's OWN control surfaces inside the
active config dir: settings.json, the guard scripts (bin/guard-*.sh,
bin/floor-*.sh, bin/library-admission.sh), the hooks tree, the integrity pins
(.sec0-baseline.sha256 and the integrity rows of contracts/control-plane-state.md)
and deploy's snapshots under backups/. Everything else — user files, and
notably the rest of ~/.claude — is ALLOWED (matches upstream's "you may edit
~/.claude freely" stance; we protect only the floor's teeth, not the whole
dir). Pure POSIX, zero Bun/node. FAIL-OPEN on any parse error: the
un-swallowable permissions.deny layer (B1) is the backstop.

Provenance: ports the SYSTEM/USER classification of upstream
containment-zones.ts / system-file-guard-core.ts @ a4e8e74 (v7.1.1), narrowed
to the floor's self-protection concern (the upstream content-egress scanner
is B4's job, not this guard's).
```

## bin/admission-self-edit.sh, lines 31-32 (before this edit)

```text
Every path this edit would touch (Write.file_path, Edit.file_path,
MultiEdit uses file_path too). Empty ⇒ nothing to judge ⇒ allow.
```

## bin/admission-self-edit.sh, lines 36-38 (before this edit)

```text
Resolve to the physical target before classifying: ./ , // and bin/../ all
reached the real settings.json (verified same inode) while string-matching
the protected globs reported "not protected" (red-team 2026-07-24).
```

## bin/admission-self-edit.sh, lines 40-42 (before this edit)

```text
The digest subject is the RESOLVED path, not the raw one: ./x, //x and
bin/../x are the same target, and a recurrence count that treats them as three
different things cannot answer "is this the same block again?".
```

## bin/admission-self-edit.sh, lines 46-53 (before this edit)

```text
Protected surfaces, relative to the config dir. Match on the un-resolved ABS
against the config dir prefix (both live and sandbox: $CFG is whichever is
active; the B1 deny array independently pins the LIVE ~/.claude surfaces).
Both the ACTIVE config dir and the LIVE one: a sandbox session must not be
able to reach out and rewrite the live floor. The ROOTS are resolved
physically too — comparing a resolved target against an unresolved root
silently misses everything whenever the root sits under a symlink (macOS
/var → /private/var is the everyday case).
```

## bin/admission-self-edit.sh, lines 55-56 (before this edit)

```text
harbor#787 — each root in BOTH spellings, as guard-deliverables does for HOME: floor_norm_path
resolves only an existing parent, so a Write into a new backups/<snapshot>/ keeps the raw prefix.
```

## bin/admission-self-edit.sh, lines 62-65 (before this edit)

```text
Case-folded comparison: APFS is case-INSENSITIVE by default, so
`Settings.json` reaches the very same inode while a POSIX `case` glob (which
is case-SENSITIVE) reports "not protected" — a one-character bypass, verified
end-to-end (red-team pass 2).
```

## bin/admission-self-edit.sh, lines 67-67 (before this edit)

```text
The four roots are folded in one fork, not four (harbor#787 doubled them).
```

## bin/admission-self-edit.sh, lines 79-80 (before this edit)

```text
The instruction-surface pin (B8). Leaving it writable would let a
session inject into CLAUDE.md and then re-pin over its own tracks.
```

## bin/admission-self-edit.sh, lines 82-83 (before this edit)

```text
guard-apiroute's allow list. Writable, it would let a session allow
the API reroute it was about to make.
```

## bin/admission-self-edit.sh, lines 85-86 (before this edit)

```text
guard-apiroute's accepted copies: the baseline a reroute is judged
against. Writable, a session could bless its own reroute.
```

## bin/admission-self-edit.sh, lines 88-97 (before this edit)

```text
CONST-1 (harbor#44) — the constitution itself, the thing the pin above
records. Protecting the record while leaving the record's SUBJECT
writable was the gap: the comment above reasoned about "a session
inject into CLAUDE.md" and then did not stop one. admission-bash.sh's FILES
arm closed the shell-redirect channel; this closes the cheaper one,
because Write/Edit/MultiEdit needs no shell at all.
Anchored on $CFG/$LIVE only, and floor_config_dir() resolves solely to
CLAUDE_CONFIG_DIR or ~/.claude — so a GOVERNED REPO's own CLAUDE.md,
which every Harbor-managed project has, stays writable. That is the
discriminating case, and recover/floor-test assert it green.
```

## bin/admission-self-edit.sh, lines 101-102 (before this edit)

```text
harbor#779 — the rest of contracts/control-plane-state.md's integrity rows; lint F14 holds this list to it.
A directory is refused by its own name too, so a file there cannot stop its writer's mkdir.
```

## bin/admission-self-edit.sh, lines 109-109 (before this edit)

```text
harbor#1044 review r3 #1 — the event dispatcher's gates: rules, ledger, spend record, spawn.on.
```

## bin/admission-self-edit.sh, lines 124-125 (before this edit)

```text
The MESSAGE interpolates $ABS — a payload-derived path. That is exactly why
the record carries the rule id passed here and never the message text.
```

## bin/admission-self-edit.sh, lines 130-133 (before this edit)

```text
A FLOOR SWITCH WRITTEN INTO ANY SETTINGS FILE (harbor#482). A settings.json `env`
block reaches every hook (library-admission.sh, FO-03), and a project's own
.claude/settings*.json is deliberately writable, so either switch planted there
would open every later session in that project. Only the two names are refused.
```
