---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-deliverables.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-deliverables.sh, lines 4-54 (before this edit)

```text

THE RULE IT ENFORCES. A NEW document written for a human to read — .html, .md,
.pdf, .docx, .pptx, .csv, .rtf, .txt — belongs in

    ~/Deliverables/<YYYY-MM-DD>-<slug>/<file>

and never loose in $HOME, ~/Desktop, ~/Documents or ~/Downloads.

WHY IT EXISTS. Measured 2026-09-02 on this box: 14 loose .html deliverables
sitting in $HOME and 4 in ~/Documents, written by sessions between 2026-08-25
and 2026-09-01 — every one a report or a draft, opened once and never filed.
The convention existed only as habit: the auto-memory
drafts-and-deliverables-must-be-clickable says WRITE the file and open it, and
says nothing about WHERE, so each session picked a directory and the estate
scattered. CONSTITUTION, "Fix the system, not your notes": a rule with no
mechanism is a wish, and a preference that belongs in a guard is a missed
system patch when it goes into an assistant's scratch memory instead. This is
the mechanism; the memory and the constitution line are the statement of it.

POSTURE: deny, and NARROW. THREE conditions must ALL hold before it fires:

  1. the extension is a document class (an image is not — a screenshot dropped
     on the Desktop is ordinary macOS work and blocking it is a §2.11 defect
     factory);
  2. the target sits DIRECTLY in $HOME, or anywhere under ~/Desktop,
     ~/Documents or ~/Downloads — the four places a session picks when it has
     not been told where to write;
  3. the file DOES NOT ALREADY EXIST.

(3) is what keeps this off ordinary work, and it is the condition doing the
real §2.11 labour: rewriting or editing a document the operator ALREADY keeps
in ~/Documents is their filing, not a session's scatter, and a guard that
blocks it gets switched off. A path inside a git repo parked under one of
those directories is exempt for the same reason — that is project content,
and the repo is already the folder of its own.

WHAT IT DOES NOT CLAIM. This is a filing convention with teeth, NOT a security
boundary, and the residuals are the ordinary ones: a runtime-assembled path, a
python/node process writing through its own API, an interpreter the flat
scanner cannot follow. It raises the cost of scattering to "notice the deny and
use the right path"; it does not make scattering impossible, and the migration
manifest is what makes a slip visible after the fact.

STANDALONE, NOT WRAPPED IN admission-hook.sh, and deliberately NOT in
guard-integrity's floor MINIMUM — exactly like guard-cloud and guard-destroy.
admission-hook.sh's contract is fail-CLOSED: any guard it wraps that cannot reach a
verdict DENIES THE CALL. Fail-closed is correct for the security floor and
wrong for a filing convention: a broken tidiness rule must never be able to
stop a session from writing code. So a failure here is a failure to file, not
an outage, and the wiring records that choice rather than leaving it to be
inferred.
```

## bin/admission-deliverables.sh, lines 66-67 (before this edit)

```text
The document classes. Extensions only — the whole rule is about where a file
LANDS, and the harness gives a path long before it gives content.
```

## bin/admission-deliverables.sh, lines 70-83 (before this edit)

```text
HOME RESOLVED PHYSICALLY, ONCE. floor_norm_path returns a physical path, and
comparing a physical target against an unresolved root silently misses
everything the moment a root sits under a symlink — the failure guard-selfedit
records for $CFG/$LIVE, and macOS /var → /private/var is the everyday case.

BOTH SPELLINGS ARE ROOTS, and the suite is what proved that necessary.
floor_norm_path resolves physically only when the target's PARENT EXISTS; for a
path whose parent does not exist yet — which is every "write a report into a
folder that is not there" — it falls back to a lexical collapse and keeps the
UNRESOLVED prefix. So a home behind a symlink matches the physical root for an
existing directory and the raw one for a new directory, and a guard holding
only one of them is blind to exactly half its own subject. Measured here: with
HOME under macOS's /var → /private/var, `~/Documents/a/b/deep.html` classified
ALLOW while `~/Documents/plan.pdf` denied.
```

## bin/admission-deliverables.sh, lines 86-90 (before this edit)

```text
The raw spelling is COLLAPSED, not taken verbatim: floor_norm_path's lexical
fallback runs floor_collapse_dots over its result, so a $HOME carrying `//` or
`/./` — which macOS hands out routinely, TMPDIR ends in a slash — would be
compared against a target that no longer spells it that way. Same defect as
comparing an unresolved root, one layer of normalisation to the left.
```

## bin/admission-deliverables.sh, lines 98-104 (before this edit)

```text
The Write arm and the Bash arm ask the same question about a path, so they ask
it in the same function. Two spellings of one rule is the drift
docs/explanation/modularity.md is about, and here it would be invisible: the arms would
answer differently only for the paths nobody tested.

Returns 0 iff <path> is a NEW loose document, and sets LOOSE_KIND to the rule
that fired. Fails OPEN on anything it cannot resolve.
```

## bin/admission-deliverables.sh, lines 110-111 (before this edit)

```text
An unresolved glob or substitution is not a path yet. Judging one would deny
`ls ~/*.html` — a READ — on the strength of a filename that does not exist.
```

## bin/admission-deliverables.sh, lines 115-115 (before this edit)

```text
A dotfile is configuration, never a deliverable (~/.zshrc, ~/.gitconfig).
```

## bin/admission-deliverables.sh, lines 118-119 (before this edit)

```text
1 · document class. Case-folded: APFS is case-INSENSITIVE, so `REPORT.HTML`
reaches the same inode a case-sensitive match would call untouched.
```

## bin/admission-deliverables.sh, lines 124-124 (before this edit)

```text
2 · location
```

## bin/admission-deliverables.sh, lines 136-142 (before this edit)

```text
The deliverables ROOT itself. A bare file here is the same scatter one
level in — the shape the operator chose is a dated folder PER deliverable,
so its siblings (the .md source, a chart, a screenshot) have somewhere to
live.
THE ROOT'S OWN INDEX IS NOT SCATTER. MANIFEST.md — the old→new record the
migration writes — and a README live at the root by design, and a rule that
forbids its own record is a rule that cannot be written down.
```

## bin/admission-deliverables.sh, lines 152-152 (before this edit)

```text
3 · already there ⇒ the operator's own filing, not this session's scatter
```

## bin/admission-deliverables.sh, lines 155-155 (before this edit)

```text
4 · inside a git repo ⇒ project content. Walk up to $HOMEP, never past it.
```

## bin/admission-deliverables.sh, lines 168-169 (before this edit)

```text
The path it SHOULD have used. A deny that names only what is wrong costs the
reader a decision; this one is copy-pasteable.
```

## bin/admission-deliverables.sh, lines 196-198 (before this edit)

```text
The digest subject is the RESOLVED path, for guard-selfedit's reason: ./x,
//x and bin/../x are one target, and a recurrence count that treats them as
three cannot answer "is this the same block again?".
```

## bin/admission-deliverables.sh, lines 210-223 (before this edit)

```text
NO floor_heredoc_inert_only VETO HERE, DELIBERATELY, AND IT IS THE ONE
CHOICE THAT DECIDES WHETHER THIS ARM SEES ANYTHING AT ALL. That veto exits
the guard for the WHOLE call when a heredoc opener is `cat`/`tee` and not an
interpreter — which is precisely `cat > ~/report.html <<'HTML' … HTML`, the
single most common way a session writes a document from the shell. Consulting
it would have left this arm blind to its own main case while every test that
used a one-line redirect still passed.

harbor#716: floor_bash_targets strips a body from DATA only, and its home-expanded
variant still carried it, so document bodies go BEFORE it. The opener line is
still judged (`cat > ~/report.html <<'HD'`), and a body fed to a shell is kept.
harbor#782: floor_hd_unwrap_doc_bodies also drops a body behind a compound
opener (`mkdir … && cat > f <<EOF`) or the `git commit -m "$(cat <<EOF)"`
argument form; `sh -c "$(cat <<EOF)"` still runs the body and is kept.
```

## bin/admission-deliverables.sh, lines 228-236 (before this edit)

```text
WRITE POSITION, NOT MERE MENTION. `cat ~/report.html` is a read and
`open ~/x.pdf` is a read; only a destination is judged. Four shapes:
  · a redirection target
  · the operand of a verb that WRITES its argument (tee, touch, install…)
  · the LAST operand of a copy/move or of a converter whose output comes
    after its input — the destination, never the source (the P12-argv-fp
    distinction floor_seg_operand_under records), trailing redirects allowed
    (harbor#714, #785). The converters left the verb-then-path shape because
    that path is their INPUT.
```

## bin/admission-deliverables.sh, lines 252-253 (before this edit)

```text
A newline-delimited list of paths: IFS is set to newline alone so a
directory with a space in it stays one candidate.
```
