---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/skill-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/skill-install.sh, lines 12-31 (before this edit)

```text
WHY THIS EXISTS. Until now the documented mechanism was a hand-typed
`cp -R skills/<name>/. ~/.claude/skills/<name>/`, and skills/README.md records
the measured failure: omit the trailing `/.` and cp -R into an existing
destination silently produces ~/.claude/skills/<name>/<name>/ and leaves the
ORIGINAL files serving. Nothing errors. That trap sat in front of 25 pending
directory renames, which is why a verb had to exist before the surgery.

THREE THINGS IT DOES THAT THE cp DOES NOT:
  1. Verifies byte-identity AFTER writing, with diff -r (generated caches
     excluded), and fails if not.
  2. Refuses to leave a nested <name>/<name>/ behind, and detects a pre-existing
     one from an earlier hand-typed install.
  3. Handles the rename case, which a copy cannot: installing kebab `red-team`
     while PascalCase `RedTeam` is still present leaves BOTH in the listing,
     and the model sees two skills where the repo has one.

DRY RUN IS THE DEFAULT, deliberately. This writes into ~/.claude/skills, an
instruction surface the B8 pin watches; every write here makes the operator
re-pin. A verb that mutates that surface on a typo is worse than the cp it
replaces.
```

## bin/skill-install.sh, lines 40-46 (before this edit)

```text
── TWO PAYLOAD KINDS, ONE GATE (harbor#7) ──────────────────────────────────
Slash commands are flat .md FILES; skills are DIRECTORIES. The nesting refusal
and `--from-old` are directory-shaped and do not transfer — but the part that
actually protects the operator does: dry-run by default, verify after writing,
and refuse the live instruction surface without an explicit --live. That gate
is the reason this file exists, and a second installer would be a second copy
of it, drifting in the direction nobody notices until it matters.
```

## bin/skill-install.sh, lines 76-81 (before this edit)

```text
THE SKILL BOOK IS COMPOSED, NOT COPIED (harbor#1149). The installed book lists every skill installed in the config dir and
the CLIs on the box, so it differs from the tracked copy by design. Copying the tracked one over it drops every row the repo
does not ship (the box's skills, the packs', the CLI table) until the next deploy, and a byte comparison calls the composed
one DRIFTED for ever. bin/skill-catalog.sh install is its one writer and its one judge (`install --check`), so this installer
asks it, and --all installs the book LAST because it lists what the run installed. Without the generator beside this script
(a copy of the tree that lacks it) the book is an ordinary payload.
```

## bin/skill-install.sh, lines 90-100 (before this edit)

```text
── THE EXEC BIT IS PART OF THE PAYLOAD, AND diff -r CANNOT SEE IT ──────────
Measured 2026-09-05 installing `measurement-audit`: the tracked
check-event-volumes.sh is 755, the live copy had been 644 since it was
hand-created, and `cp -R` into an EXISTING file keeps the DESTINATION's mode —
so the copy landed 644 while install_one printed "verified byte-identical" and
state_of went on reporting `current`. `./check-event-volumes.sh` then exits
126. A checker that cannot be run, behind a green install and a green listing:
the same shape as every other defect this workstream is about, one layer down.

Only the skills path needs this. Slash commands are flat .md files that nothing
executes, so the commands path below is deliberately left comparing bytes.
```

## bin/skill-install.sh, lines 113-114 (before this edit)

```text
Generated caches are not payload: a box-only __pycache__ made every re-install
of its skill fail the byte check below, after writing (found by the #702 deploy).
```

## bin/skill-install.sh, lines 180-192 (before this edit)

```text
A CASE-ONLY RENAME IS THE SAME DIRECTORY, and this box's volume is
case-INSENSITIVE (macOS default). `Telos` and `telos` are two strings and one
directory, so the string guard below passes, `install_one` writes into the
directory it is about to delete, and the skill is destroyed — after printing
that it installed successfully (harbor#239).

The suite did not catch it because case 6 asserted only that the OLD name was
gone. On a case-insensitive volume that assertion is satisfied BY the
destruction: the test passed because the skill had been deleted. The missing
half — does the installed skill still exist — is now asserted too.

Every rename this verb actually performs is PascalCase -> kebab-case, so the
untested shape was also the only shape that occurs in practice.
```

## bin/skill-install.sh, lines 198-205 (before this edit)

```text
A SYMLINK IS NOT THE SAME DIRECTORY WEARING ANOTHER NAME, even when it
points at one. `[ -d ]` above follows it, and the probe below is visible
through both paths, so the case-only branch would claim it — and then the
two-step `mv` moves the LINK into the destination DIRECTORY, leaving
`<name>.rename-tmp.<pid>` inside the installed skill while reporting
success (PR #241 review, P2). There is no rename to perform: the link goes
into the backup. Refusing to follow a link here also matches how the marker
walk treats one — a link is writable from outside the thing being governed.
```

## bin/skill-install.sh, lines 213-218 (before this edit)

```text
ASK THE FILESYSTEM, do not compare strings — and not `pwd -P` either, which
returns the spelling you typed rather than the one on disk, so both names
still compare unequal (measured; the first cut of this fix did exactly that
and changed nothing). Dropping a marker in one name and looking for it under
the other is the only check that cannot be fooled, and it needs no `stat`
flavour test — BSD and GNU disagree on the flags for inode/device.
```

## bin/skill-install.sh, lines 227-230 (before this edit)

```text
Same directory: the content is already correct (install_one wrote it), so
only the SPELLING is wrong. Two-step through a temporary name — a direct
`mv Alpha alpha` is a no-op or an error on a case-insensitive volume
depending on the filesystem, and neither is a rename.
```

## bin/skill-install.sh, lines 270-275 (before this edit)

```text
THE RENAME CLEANUP MUST NOT SIT BEHIND THIS EARLY RETURN. It did, and
tests/skill/install/install.test.sh (then bin/) case 6 caught it on the suite's first run: when the
new kebab name is ALREADY current, the function returned before removing the
old PascalCase directory, so both stayed in the listing and the model saw two
skills where the repo has one. That is precisely the failure --from-old
exists to prevent, and it was silent — the run printed "already current".
```

## bin/skill-install.sh, lines 289-295 (before this edit)

```text
── I3 · ASK BEFORE WRITING, NOT AFTER (harbor#117) ───────────────────────
Everything below this line verifies the copy LANDED. Nothing above it asked
whether the copy was SAFE — and the answer lives in the bytes the cp is about
to destroy. skill-collision-verify.sh refuses only when a live file's bytes are in no
commit and no install record (harbor#476, #641): work the repo has never seen.
An ordinary update leaves the live copy an older commit, so this stays silent
for it. The dry run asks too, so a refusal shows before anything is written.
```

## bin/skill-install.sh, lines 358-360 (before this edit)

```text
Carry the source's modes over — `cp -R` did not, for any file that already
existed at the destination — and then CHECK, because a repair that is not
verified is the same promise the byte check above refused to take on trust.
```

## bin/skill-install.sh, lines 378-382 (before this edit)

```text
The dest root may not exist at all — commands/ was absent on this box until this work created it,
which is the whole reason slash commands were unused here. Creating it is part of installing, not
a precondition, for skills/ too: a dry run must work when it is absent (the single most likely first
use), and a dry run exits 1 only for what --apply would refuse, which an absent dir is not.
The creation sits below il_target's live gate, so a refused run leaves no directory behind.
```

## bin/skill-install.sh, lines 425-427 (before this edit)

```text
A RETIRED skill's rows go too: tracked here no longer, and gone from disk. 472 rows of skills retired on 2026-10-26
stayed, and reference-check printed "473 references do not resolve" at every session start. A skill still tracked
but missing on disk keeps its rows (REF-5's real finding), and so does a retired dir still on disk (box-only).
```
