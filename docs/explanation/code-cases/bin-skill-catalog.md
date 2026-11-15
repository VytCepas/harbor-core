---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/skill-catalog.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/skill-catalog.sh, lines 14-20 (before this edit)

```text
TWO BOOKS BECAUSE THERE ARE TWO QUESTIONS (harbor#1149). The tracked book answers "what does THIS repo ship", and it is
the same bytes on every machine: it reads nothing outside the checkout (not the config dir, not ~/.local/bin, not the
private layer), so `--check` is a pure function of the tree and can fail CI. The installed book answers "what can a
session on THIS box reach", which is the tracked skills plus whatever a pack, the private layer or the operator put in
the config dir. It used to be the only book, written INTO the tracked file from the live box, so every client skill
and the operator's address on the box landed in git and in the public export. deploy.sh runs `install --apply --live`
after the packs, so the installed book lists every installed skill; the tracked file is no longer rewritten by a deploy.
```

## bin/skill-catalog.sh, lines 22-33 (before this edit)

```text
WHEN EACH BOOK IS REGENERATED, AND WHY NOT AT SessionStart (harbor#158, decided 2026-10-31). Two triggers, one per book, and
neither is a session event:
  tracked book    by hand, `sh bin/skill-catalog.sh`, after a skill under skills/ is added, renamed or re-described. Lint T9
                  is the detector (advisory, and a pure function of the checkout), and its FAIL line names the command; a
                  DEFECTS section or exit 1/3 (below) is the detector for a skill that cannot be indexed at all.
  installed book  by `deploy.sh`, which runs `install --apply --live` after the packs; lint X8 asks `install --check` whether
                  the installed copy still matches the skills installed beside it. Every route that puts a skill on the box
                  (skills-install, a pack) goes through deploy, so the write happens when the set changes, not when it is read.
A SessionStart hook was weighed and rejected: it would write the operator's instruction surface (which the B8 pin watches) on
every session to fix a staleness that only changes on a deploy; it would race concurrent sessions over one file; and a hook that
fails is silent to the operator, so it detects LATER than X8 does. The cost accepted: a skill hand-copied into the config dir
between deploys is missing from the installed book until X8 reports it (X4 reports the same skill as untracked).
```

## bin/skill-catalog.sh, lines 35-39 (before this edit)

```text
WHY THIS IS GENERATED AND NOT WRITTEN. An index of this many skills maintained
by hand drifts the moment one is added, renamed or hidden, and an index that
lies is worse than no index because it is trusted. Same reasoning that makes
docs/generated/status.md generated and lint rules T1/T2 forbid a hand-typed count — including
in this comment, which said "33 skills" while the box had 36.
```

## bin/skill-catalog.sh, lines 41-45 (before this edit)

```text
DEFECTS ARE LOUD, NOT BLANK (harbor#158). A skill with no frontmatter, no single-line description, no name or a name that is not
its directory's, and two skills that share a directory name (skills/ and vendor/skills/), differ only by case, or declare one
`name:`, are listed in a DEFECTS section above every table. In the tracked book they also fail: the write exits 1 after writing,
`--check` exits 3, so T9 reports "the generator FAILED" with the reason and never offers a regenerate. In the installed book
they warn only: a box with one broken skill must still deploy.
```

## bin/skill-catalog.sh, lines 47-49 (before this edit)

```text
`--check` diffs instead of writing, so a lint rule can flag a stale book. T9 is advisory, so nothing fails
CI on a stale book yet (this header once claimed the opposite, until an adversarial pass pointed out that
nothing anywhere fails on one); the tracked book is deterministic now, so a rule could.
```

## bin/skill-catalog.sh, lines 51-54 (before this edit)

```text
`--check` HAS THREE ANSWERS, NOT TWO (harbor#1149): 0 current, 1 STALE (regenerate it), 3 the generator could not say (a
router row it cannot read, no skills dir to scan). A bad row once exited 1 like a stale book, so T9 and X8 called a
malformed router file STALE and sent the reader to a regenerate that fails with the real error. Every other mode keeps the
install standard's 1 for a refusal (so does the target gate refusing a --dir that names the live dir), and 2 is usage.
```

## bin/skill-catalog.sh, lines 56-64 (before this edit)

```text
WHAT PROBLEM IT SOLVES. `disable-model-invocation: true` removes a skill from
the model's listing ENTIRELY — most skills on this box carry it — so they are
invisible to a session and effectively invisible to the operator, who has to
remember they exist. Listing them costs one `description` line, because the
book is itself a skill: its body loads only when opened.

AND WHY IT CARRIES PATHS, NOT JUST NAMES. A hidden skill cannot be invoked by
the model at all. But a SKILL.md is a markdown file, so a path makes it
readable even when it is unreachable — which is the whole trick.
```

## bin/skill-catalog.sh, lines 66-75 (before this edit)

```text
THE TRIGGERS ARE TASK-SHAPED, NOT META-SHAPED (harbor#173 · A5), and this file
shipped the opposite first. Every trigger in the description below used to ask
ABOUT skills — "what skills do I have", "list skills", "I forgot the name of
that skill" — so the book surfaced when the operator wanted an inventory and
never when a session was doing the work a hidden skill covers. The evidence is
this repo's own: the session that ran a pass^k reliability study by hand had an
`Evals` skill on the box whose triggers include `pass@k`, and it never
surfaced. That is 11,639 B of trigger vocabulary reachable only by asking the
one question nobody asks mid-task. The meta triggers are kept — they were not
wrong, only insufficient.
```

## bin/skill-catalog.sh, lines 83-89 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/skill-catalog.sh, lines 95-98 (before this edit)

```text
Glob order is LC_COLLATE-dependent: under en_US.UTF-8 the list case-folds and
interleaves, under C it does not. Two boxes then generate two different books
from identical input and --check flaps forever, which is how a guard gets
switched off. Pin the collation rather than trusting the caller's environment.
```

## bin/skill-catalog.sh, lines 111-114 (before this edit)

```text
An unrecognised argument must NOT fall through to the write branch. `--chekc`
used to overwrite the very file it was asked to verify and exit 0 — the exact
shape that makes a gate vacuous, since a typo in a hook "passes" by destroying
the evidence.
```

## bin/skill-catalog.sh, lines 135-139 (before this edit)

```text
THE TRACKED BOOK NAMES THE INSTALL PATH, NOT A PATH IT WAS GENERATED FROM. This file used to build every row's path
from the directory it scanned, and a scan of any directory but the live one wrote a scratch path into a tracked file
(measured 2026-09-07: `--check` reported 36 rows differing only in their path prefix, and nothing else would have
caught it). The tracked book scans the checkout and says where an install puts the skills, so there is no path to get
wrong; the installed book scans the config dir it is written into, and says that dir.
```

## bin/skill-catalog.sh, lines 154-156 (before this edit)

```text
Every installed skill is owned by a recorded install: core and vendored skills by a row of the deploy's manifest, a pack's by
that pack's manifest. A dir with neither was put there by hand or by an installer that did not record it, and a row with no dir
is an install that was undone by hand: both are drift, and the second is the one nothing else reports.
```

## bin/skill-catalog.sh, lines 187-190 (before this edit)

```text
The frontmatter ONLY — everything between the opening `---` and the next one.
Scanning the whole file misfiled any skill whose BODY mentioned the key at
column 0, and this generator's own output discusses that key, so the book was
one prose reflow away from classifying itself as hidden.
```

## bin/skill-catalog.sh, lines 211-214 (before this edit)

```text
Truncate on WHOLE WORDS, never a byte offset. `substr()` split multibyte
sequences: awk aborted with a conversion failure under a UTF-8 locale (empty
cell, status discarded by the surrounding $( )) and wrote invalid UTF-8 under
C. Concatenating whole words cannot split a character.
```

## bin/skill-catalog.sh, lines 223-226 (before this edit)

```text
A single word longer than the budget would otherwise leave the cell as
a bare ellipsis, which reads as "this skill has no purpose". Print the
word whole: over-wide beats uninformative, and it still cannot split a
multibyte character.
```

## bin/skill-catalog.sh, lines 231-238 (before this edit)

```text
The purpose, plus the NOT FOR clause that disambiguates confusable siblings.

The first cut stripped everything after `USE WHEN`, which killed `NOT FOR`
too — measured at 33 of 36 skills, 27 of which name a specific sibling. For a
hidden skill the book is the ONLY disambiguator, so it was deleting the one
sentence that prevents picking the wrong tool. It also truncated at the first
full stop, which erased mail-cal's APPROVAL-GATED warning. USE WHEN triggers
go instead: a reader already inside the book does not need them.
```

## bin/skill-catalog.sh, lines 242-251 (before this edit)

```text
THE TRIGGERS ARE WHAT A READER ARRIVES WITH, AND THE BOOK DELETED THEM.
`purpose()` above strips `USE WHEN` on purpose and that is still right for the
tables: a reader already inside a row does not need the trigger phrases. But
it meant the WHOLE book carried none of them — measured 2026-08-28, `grep -i`
for a warehouse, `datalayer` and `red team` each returned zero over the generated
file, while four skill trees name those subjects. Someone looking for the skill
that owns a subject searches with the subject's own vocabulary, so an index
with the vocabulary stripped answers every such search with silence.
The path goes on the SAME LINE as the triggers because grep returns one line,
and a hit that does not carry the path sends the reader back to the top.
```

## bin/skill-catalog.sh, lines 287-290 (before this edit)

```text
contract_for <tool> — where to read before touching it. A tool with no
contract is listed AS A GAP rather than omitted: an absent row reads as "no
such tool", a row saying "none" reads as work.
A sibling's tool is the private layer's cli-contracts.tsv (harbor#1273), read first; core names harbor's own.
```

## bin/skill-catalog.sh, lines 606-614 (before this edit)

```text
A TRUNCATED DIFF THAT DOES NOT SAY IT IS TRUNCATED PRODUCES FALSE
NEGATIVES, and this one did. `head -40` alone hid every row past the
fortieth, so on 2026-09-07 a check of whether two newly-installed skills
appeared in the book came back "absent" — the rows were there, forty lines
further down. Four tool calls were spent on a defect that did not exist,
and the same shape would let a reviewer approve a book missing whatever sat
below the cut. The cap stays (a 200-line diff in a terminal is not read
either); what changes is that the suppressed count is stated, so an
absence found here is known to be provisional.
```

## bin/skill-catalog.sh, lines 619-622 (before this edit)

```text
NAME A COMMAND THAT STILL WORKS AFTER THIS EXITS. The obvious line here
is `diff $OUT $tmp`, and the temp copy is deleted when this exits — a remedy that
cannot run is worse than none, because it costs the reader a round trip
to discover that. The book is tracked, so regenerate and let git show it.
```

## bin/skill-catalog.sh, the commands paragraph (before this edit)

```text
THE BOOK ALSO LISTS COMMANDS, NOT ONLY SKILLS (harbor#1010). Measured 2026-11-02: agents on this box hand-rolled CI polling because no
listing named `harbor event ci` or bin/ci-wait.sh, and one lane idled 7.5 h. The book is the one route to a hidden thing, so it
carries every `harbor <verb>` of bin/harbor's table and every bin/ script contracts/cli.md marks `**Agent-facing.**`, each with a
USE WHEN and the exact invocation from contracts/agent-tools.tsv. Extended in place, not a sibling: one grep over one file answers
"is there a tool for this", and a second generated file would be a second thing to forget to read. A hole (a verb or marked tool with
no row, a row with nothing behind it) is a DEFECT like a broken skill, and `--coverage` is the check lint skill.catalog-covers-tools runs.
```
