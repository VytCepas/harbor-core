---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/drift-reference-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/drift-reference-check.sh, lines 17-55 (before this edit)

```text
WHY IT EXISTS, WITH THE THREE FINDINGS THAT MADE THE CASE. Lint K1 and T3
validate references in the REPO. Nothing validated the copy that actually
runs, and the two are not the same file: `~/.claude/CLAUDE.md` is loaded into
every session, while `bin/lint-conventions.sh` reads `policy/constitution.md` out of
a checkout that the harness never opens. On 2026-08-03 a survey of the live
box found, with K1 green the whole time:

  1. The installed constitution cites `./docs/explanation/…`, `./contracts/…`,
     `./docs/explanation/admission-baseline.md` and `./docs/generated/status.md`. None of those directories or files are
     deployed under the config dir, so the document that says "if you find a
     citation that does not resolve, that is a defect in this file" carried a
     pile of them — on the surface where it is actually read.
  2. `context-resolve.sh` was wired at SessionStart TWICE. harbor#95 fixed the
     two installers so they can no longer CREATE a duplicate, and its WIRE-1
     assertion proves that from an empty settings.json — but nothing looks at
     a box that already had one, and this box did. The installers are
     append-only by design; the residue outlived the fix.
  3. The constitution stated the egress scanner was "built and not installed"
     while it was installed, wired under two matchers, and blocking.

All three are one class: a claim about the installed surface, checked against
the repo. This tool checks the installed surface against itself.

WHAT IT DOES NOT DO. It never repairs anything. Every surface it reads is one
`admission-self-edit.sh` protects (settings.json, bin/, the pins) — a tool that
could fix these findings would be a tool that can disable the floor, so this
one reports and hands the operator a command. It also does not compare live
against repo: that is lint X2's job, and two rules answering one question is
the drift class the T rules exist for. X2 asks "does the deployed copy lag?";
this asks "does the deployed surface hold together on its own?"

PERMISSIONS.DENY IS DELIBERATELY OUT OF SCOPE. A deny glob naming a path that
does not exist is fail-SAFE, and matching globs against a filesystem to decide
whether a rule is "used" manufactures false positives — which get guards
switched off (CONSTITUTION №2.11). Absence of a deny is B1's own concern.

Deliberately one file (docs/explanation/modularity.md): `lint-module-shape.sh --seam` reads it "real but
PRIVATE — leave it one file" (2026-10-02, 0 symbols with two outside callers). The REF rules
share one walk of the installed surface; split, each would walk it again.
```

## bin/drift-reference-check.sh, lines 58-64 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/drift-reference-check.sh, lines 101-102 (before this edit)

```text
RESOLVED FROM THIS SCRIPT'S OWN DIRECTORY, the extractor and log-lib both: the tree under
inspection may be hostile (audit-triage.sh, audit-triage-run.sh). No dirname: B9's PATH has none.
```

## bin/drift-reference-check.sh, lines 124-126 (before this edit)

```text
Every report loop below reads a here-document, and a shell that cannot create one's temp file runs them on
nothing and reports clean (seen in a sandboxed subagent, 2026-10-27). `read` is a builtin, so a PATH with no
coreutils still probes. Refused, never read as a pass.
```

## bin/drift-reference-check.sh, lines 138-139 (before this edit)

```text
An absent config dir is an ANSWER, not a misuse — the same argument
admission-verify.sh:44 makes. Nothing is installed, so nothing dangles.
```

## bin/drift-reference-check.sh, lines 147-149 (before this edit)

```text
B9: a missing jq must never read as a clean run. `admission-bash.sh` exited 0 on
'rm -rf /' for exactly this reason. Loud, and exit 1 — not 0, and not 2, which
a caller would filter out as "I typed it wrong".
```

## bin/drift-reference-check.sh, lines 158-174 (before this edit)

```text
── the declared-root reader (harbor#462) ─────────────────────────────────────
THE DECLARED ROOT. One line, human-visible, exactly parseable, one copy of the
fact — the format and the argument for it are at REF-5 below:

    > **Path root:** `~/port/harbor` — every `./`-prefixed path in this document…

The root is the FIRST backticked token after the literal `**Path root:**`, so a
declaration line may carry as much prose as it likes afterwards without the
parse drifting. `~/` is expanded here because a document written for a human
says `~/port/harbor` and a filesystem test needs $HOME; nothing else is expanded, so
no shell ever sees this string.

It prints NOTHING when there is no declaration, and the caller treats that as
the fallback case rather than as an error — REF-8 is what makes the fallback
visible. A malformed declaration (the marker with no backticked token) also
prints nothing and is therefore reported by REF-8 as undeclared, which is the
honest reading: a root nobody can parse is a root nobody declared.
```

## bin/drift-reference-check.sh, lines 189-202 (before this edit)

```text
WHERE ONE CITATION RESOLVES, and the ONLY place that question is answered —
REF-5 and REF-9 both call this, for the same reason doc-cited-paths.awk is one
file: two copies of a resolution rule is how one of them drifts out of step
with the declaration it prints.

THE DECLARED ROOT BINDS `./` AND NOTHING ELSE, because that is what the
declaration the tool prints actually promises: "every `./`-prefixed path in
this document resolves there". The first cut applied the root to every
relative citation, which was latent for CLAUDE.md — all ten of its citations
are `./`-prefixed, verified 2026-09-06, so no behaviour changed there — and
WRONG the moment REF-9 arrived, because a skill mixes the two forms in one
file: `references/pitfalls.md` ships beside SKILL.md and must resolve against
its own directory, while `./contracts/cu.md` means the repo. Binding both to
one base breaks whichever form the base is not for.
```

## bin/drift-reference-check.sh, lines 229-230 (before this edit)

```text
The command that installs <component>'s part of this dir: through deploy on the live box, the one
live entry (install standard §4), and the installer itself, --dir spelled, anywhere else (harbor#809).
```

## bin/drift-reference-check.sh, lines 244-255 (before this edit)

```text
── THE DENOMINATOR (harbor#467) ─────────────────────────────────────────────
REF-5 printed `every hook, pin and citation on the installed surface resolves`
over a constitution from which it had extracted ZERO citations, and that line
was believed for the 34 days the tool existed. "0 findings" and "0 items
examined" are the same output and opposite facts, so a report carrying only
findings is unfalsifiable from outside it: nothing in the output distinguishes
a clean surface from a checker that never looked at one.

So every extracting rule below records WHAT IT EXAMINED, the reporter prints
that on a clean run as well as a dirty one — a clean run is precisely where an
unread denominator does its damage — and REF-10 turns "I extracted nothing
from a document that plainly cites things" into a finding rather than a pass.
```

## bin/drift-reference-check.sh, lines 262-277 (before this edit)

```text
DELIBERATELY BROADER THAN THE EXTRACTOR, and consulted ONLY where the
extractor returned zero. `doc-cited-paths.awk` knows two dialects; this knows "a
token with a slash and a file extension", which is what a citation looks like
in a dialect nobody has taught the tool yet — the bare-prose one included.
Breadth is safe here BECAUSE of the zero guard: it can only ever speak about a
document the real extractor found nothing in, so it can neither inflate a
count nor block ordinary work (CONSTITUTION No.2.11).

WHAT IT CANNOT SEE, said out loud rather than left implied: PARTIAL blindness.
An extractor that finds nine citations and misses a tenth written in a dialect
it does not know still reports nine, and this rule stays silent. Closing that
would need a second extractor as good as the first — the thing that does not
exist, and the reason #467 is about the zero and not about the shortfall.

URLs are blanked before the test because REF-5 scopes them out deliberately: a
document whose only reference is `https:\/\/…` has not defeated the extractor.
```

## bin/drift-reference-check.sh, lines 288-299 (before this edit)

```text
Every absolute path inside a hook command string. A command is not one path:
`/bin/sh …/admission-hook.sh …/admission-bash.sh` names the wrapper AND the scanner,
and the wrapper existing tells you nothing about the scanner. Splitting on
whitespace is correct here and would not be for arbitrary input — these are
strings the installers wrote, and a config dir containing a space is already
broken for every hook the harness spawns.

awk, not grep, and the reason is not style. On the operator's Mac `grep` is a
ugrep wrapper carrying `-I --ignore-files`, so it silently skips binary AND
gitignored files. A missed line here produces FEWER findings — a false CLEAN —
and this whole tool exists to stop exactly that shape of lie. Nothing in this
script may rest a negative on a `grep` whose flags it does not control.
```

## bin/drift-reference-check.sh, lines 302-312 (before this edit)

```text
── settings.json must PARSE before any rule claims to have read it ──────────
Found by review 2026-08-03, and it is this tool's own failure mode aimed at
itself: every settings rule below runs `jq … "$S" 2>/dev/null`, so a malformed
file made jq exit non-zero, sent its complaint to /dev/null, produced no rows,
and the run reported `"clean": true` with exit 0. REPRODUCED with a settings.json
containing `{bad`. Three rules silently did not run and the tool said the
surface was fine.

The B9 guard above covers a MISSING jq and missed an UNREADABLE file — the same
lesson, one layer in. "I could not look" must never render as "there is nothing
to see", which is the whole reason this script exists.
```

## bin/drift-reference-check.sh, lines 324-326 (before this edit)

```text
What breaks: the harness spawns the hook, `sh` reports "No such file", and the
hook's exit status decides the event. For a PreToolUse guard that is a floor
with a hole; for SessionStart it is noise the operator learns to ignore.
```

## bin/drift-reference-check.sh, lines 332-335 (before this edit)

```text
`_n` is a COUNT ROW, not a finding (harbor#467). The loop runs in a
pipeline subshell, so a shell variable incremented here would be lost
at the `done`; carrying the denominator out through the same file the
findings travel in keeps one pass and cannot drift from what was read.
```

## bin/drift-reference-check.sh, lines 350-372 (before this edit)

```text
THE PREDICATE IS THE WHOLE RULE, and the obvious one is wrong. `admission-egress.sh`
is wired twice at PreToolUse ON PURPOSE — once for the write tools, once for
the web/MCP channel — so "the same command appears twice in one event" reports
the fix as a defect. floor-test.sh's WIRE-1 works around that by `grep -v`-ing
guard-egress out of its comparison, which would also hide a genuine duplicate
of it.

What actually makes two wirings a duplicate is that they carry the same
command under an EQUIVALENT selector, and a missing `matcher` key is the same
selector as `""` — which is exactly the shape harbor#95 was about: one
installer wrote `{hooks:[…]}`, the other `{matcher:"",hooks:[…]}`, neither
dedupe could see the other, and both selected every event.

What breaks: the hook runs twice per event. Invisible for a recorder; for
context-resolve.sh, which emits additionalContext, it injected the notice into
the session twice.

THE REPAIR, because this tool reports and never fixes — and a finding with no
route to a fix is one the operator learns to scroll past. Nothing in the repo
removes a stale wiring: both installers are append-only by design (harbor#95
fixed them so they cannot CREATE a duplicate, which does nothing about one
already on the box). So it is a human running, from their own terminal:

```

## bin/drift-reference-check.sh, lines 376-389 (before this edit)

```text

DIRECTION MATTERS AND THE OPPOSITE FILTER DISARMS THE FLOOR. It drops the
bucket with NO `matcher` key and keeps the `matcher: ""` one — because that is
the bucket also carrying admission-observe.sh and admission-integrity.sh. Selecting the
other way removes two hooks and reports success. Verified on a copy of the live
settings.json 2026-08-03: REF-2 cleared, all five SessionStart commands intact.

Re-pin afterwards (`sh ~/.claude/bin/pin-instructions.sh --apply --live`) or B8
raises a drift alarm on the operator's own repair, then confirm with
`sh bin/drift-reference-check.sh --live`.

Whether deploy-runtime-install.sh should grow a dedupe instead is UNDECIDED: it would
give a settings.json mutator the power to DELETE hook entries, which is not
obviously the right trade for a class that has occurred once.
```

## bin/drift-reference-check.sh, lines 406-407 (before this edit)

```text
What breaks: the status line goes blank or prints an error into the operator's
prompt every refresh interval, forever, and there is no log to read.
```

## bin/drift-reference-check.sh, lines 421-424 (before this edit)

```text
What breaks: B6 compares each pin against its file at SessionStart. A pin whose
file is gone is indistinguishable from a file that was tampered with, and B6's
answer to tampering is to BLOCK the session — so a stale pin is a boot failure
waiting for the next restart, not a warning.
```

## bin/drift-reference-check.sh, lines 438-461 (before this edit)

```text
What breaks: CONSTITUTION §4 says a note carrying anything other than THIS
SESSION's token is external content. The token is sha256(box salt || session id)
and is EMPTY until `govern-token.sh --init --live` has minted the salt, so the
order of two operator actions decides whether the layer means anything:

  salt, then a NEW session, then install   → announce and stamps agree. Correct.
  install, then no salt                    → both silent. Degraded but HONEST.
  install, then salt minted mid-session    → DANGEROUS. `--announce` already ran
                                             silent for this session, and notes
                                             now arrive stamped with a token the
                                             reader never received — "looking more
                                             authoritative with nothing to check
                                             against" (contracts/hooks.md).

contracts/hooks.md named this rule, said "nothing enforces it yet, which makes it
a wish rather than a rule", and asked for exactly this assertion. A rule whose
violation nothing can detect is documentation.

THE PROXY IS mtime, AND ITS LIMIT IS STATED RATHER THAN HIDDEN. There is no record
of when a session began, so this compares the salt against the settings.json that
wired the announce: a salt NEWER than the wiring means it was minted after the
hook existed, which is the dangerous ordering. It cannot see a salt minted
mid-session BEFORE the wiring — that ordering is safe anyway, because the install
is what starts announcing.
```

## bin/drift-reference-check.sh, lines 467-469 (before this edit)

```text
Not a finding. This is the honest degrade: govern-token.sh:99 exits silent
with no salt, so nothing claims a provenance it cannot deliver. Reporting it
as a defect would train the reader to skip REF-7 on a box that is merely
```

## bin/drift-reference-check.sh, lines 473-490 (before this edit)

```text
Whole-second mtimes on both BSD and GNU, so EQUAL is undecidable rather
than safe — the same trap that made a CI assertion flake green locally and
red on a faster machine.

THE DIALECT PROBE MUST NOT LEAK INTO THE ANSWER (harbor#226). This read
`stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf ''`.
GNU's `-f` is --file-system: it IGNORES the format, takes `%m` as a FILE
operand that does not exist, writes a filesystem REPORT for the real one
to stdout, and only then exits non-zero. Unredirected, that report was
captured and the GNU fallback's epoch appended inside the same
substitution — and the report contains an `x` (`ext2`, `Type: …`), which
the *x* arm below reads as "could not read an mtime". A false REF-7 on a
correctly ordered box, produced by the probe rather than by the property,
on every GNU box. Not reproducible here or in CI — both BSD — which is
the reason it needs a fix rather than a "cannot reproduce".

VALIDATED, NOT TRUSTED. An answer counts only if it is all digits, so no
dialect's prose can reach the comparison whatever its exit status says.
```

## bin/drift-reference-check.sh, lines 494-521 (before this edit)

```text
A ONE-SESSION HAZARD MUST NOT BE A PERMANENT FINDING (harbor#226). The
ordering costs something only in the session where the salt appeared
mid-flight: from the next SessionStart on, the announce runs with the salt
in place and the token is delivered. Both mtimes are frozen, though, so
the comparison alone reports that spent hazard forever — a verdict that
cannot go green, which is harbor#211's shape one tool over and the class
§2.11 calls a defect, because a check that is always red gets skipped.

NOT FIXED WITH A MARKER FILE. govern-token.sh:32 states "THE HOOK NEVER
WRITES" and argues it: the token is derived rather than stored precisely
so concurrent sessions cannot collide or fork a shared file, on a box
whose `hostname` has already forked host-sharded ledgers. Buying this
verdict with a per-session write would trade a real property for a
cosmetic one.

SO THE EVIDENCE IS ONE THE CONFIG DIR ALREADY CARRIES. Claude Code writes
$CFG/sessions/<pid>.json per process (context-peers.sh:9). A record NEWER
than the salt means a session has begun since it was minted, so that
session's announce ran with the salt present and the window is shut —
which is exactly what the remedy below tells the operator to do.

mtime, NOT the JSON. Those records are heterogeneous on this box, measured
rather than assumed: some carry `startedAt` as epoch milliseconds, others
only `procStart` as a `Sun Aug 16 12:29:11 2026` string. A check resting on
an undocumented shape is one upstream edit away from silently passing.

NO SESSIONS DIRECTORY MEANS NO EVIDENCE, AND NO EVIDENCE KEEPS THE FINDING.
This is a reporter, so the conservative direction is to report.
```

## bin/drift-reference-check.sh, lines 553-610 (before this edit)

```text
The K1 analogue for the surface that is actually read. K1 fails the build when
a path cited in policy/constitution.md goes missing from the REPO; this asks the same
question of the deployed copy, where the answer is different, because the repo
ships docs the installers do not deploy.

What breaks: the constitution instructs the reader to follow its citations and
says an unresolvable one is a defect to report. Every dead link teaches the
reader that parts of that document are inert — which is the failure the
document itself names, one layer down.

THIS RULE WAS BLIND FOR ITS ENTIRE EXISTENCE AND THAT IS WHY IT IS REWRITTEN
(harbor#462). It extracted `](target)` markdown links only. Commit 8b50867 —
the SAME commit that created this file, 2026-08-03 — migrated policy/constitution.md
from 16 markdown links to 13 backticked `./path`s, on the reasoning written
into lint K1's comment: "plain text, which cannot dangle anywhere". K1 was
given a second arm to read the new form. This rule was not.

The premise was false. A backticked `./docs/explanation/grilling.md` dangles exactly
as hard as a link to it. What the migration changed is that the only
instrument aimed at the installed surface stopped being able to SEE the
citations, so its finding count went 12 -> 0 and READ LIKE A REPAIR. Measured
2026-09-06: 0 paths extracted from a 21,552-byte CLAUDE.md carrying 10, all 10
dead, "every hook, pin and citation on the installed surface resolves", exit 0.

So the extractor is no longer written here. It is bin/doc-cited-paths.awk, run by
this rule and by K1, because two copies is what let one dialect change slip
past one of them. RESOLVED FROM THIS SCRIPT'S OWN DIRECTORY, never from the
tree under inspection — audit-triage.sh's header argues that at length: a
hostile copy in an inspected tree would otherwise choose what this rule can see.

THE DECLARED ROOT IS THE OTHER HALF, and without it this rule can only ever be
permanently red. `./docs/explanation/grilling.md` is not WRONG — it is unrooted, and
three roots are in play on this box (the repo, a skill's own directory, the
installed config dir). Nothing declared which one a citation meant, so a
reference that works from one place is silently dead from another. A document
may now say so in one line, and this rule resolves against what it says:

    > **Path root:** `~/port/harbor` — every `./`-prefixed path in this document
    > resolves there, never against the directory this copy is installed into.

EXACTLY-PARSEABLE AND HUMAN-VISIBLE, one copy of the fact. The root is the
first backticked token after the literal `**Path root:**`, `~` expanded. A
declaration naming a root that does not exist is a finding, not a pass — that
is the shape where "I could not look" renders as "there is nothing to see".

NO DECLARATION IS ALSO AN ANSWER, and a quiet one: the document falls back to
resolving against its own directory, which is the pre-2026-09-06 behaviour and
is correct for a document that ships beside what it cites. REF-8 is what makes
the fallback visible rather than assumed.

Anchors, URLs and mailto are skipped: a `#section` link is intra-document, and
a URL's liveness is doc-cite-verify.sh's job and needs a network.

A FRAGMENT IS NOT PART OF THE PATH. `[details](.\/A.md#section)` was tested for
a literal file named `A.md#section` and reported as dead even where `A.md`
exists — reproduced against a fixture. The fragment is stripped before the
filesystem test and kept in the report, so the operator sees what the document
actually says.
```

## bin/drift-reference-check.sh, lines 613-615 (before this edit)

```text
B9's rule one layer in: a missing extractor must never read as a clean
citation sweep. This is the tool's own "I could not look" case and it is
louder than a finding, because every path below it would silently be zero.
```

## bin/drift-reference-check.sh, lines 625-630 (before this edit)

```text
THE DENOMINATOR IS THE EXTRACTOR'S OUTPUT, not the subset that reaches the
filesystem (harbor#467). A document whose only reference is a URL has NOT
defeated the extractor — the tool saw it and scoped it out on purpose —
and counting the post-skip subset would make that document read as blind.
Extracted once into a file rather than twice into a pipe: two passes are
two answers, and the one the report prints must be the one REF-5 used.
```

## bin/drift-reference-check.sh, lines 642-645 (before this edit)

```text
WHAT REF-8 NEEDS, COMPUTED WHERE THE ANSWER EXISTS. Not "are there ./
citations" — that is true of every correct document that ships beside what
it cites — but "did a ./ citation actually FAIL". Counted from REF-5's own
findings so the two rules cannot disagree about the same file.
```

## bin/drift-reference-check.sh, lines 653-658 (before this edit)

```text
The reference graph's `deploys_to` edges that end on a file this config dir does not hold: the install
manifest says a file was installed and it is gone. `doc-graph-generate.sh --dangling` owns the definition (it reads the
manifest alone, no tree scan, so this stays cheap); this folds each row into REF-5 beside the dead citations,
since both are "a reference on the installed surface that resolves nowhere". doc-graph-generate.sh is found beside this
script or in the harbor checkout, never in the tree under inspection (the same rule as EXTRACT above); with
neither the count says 0 examined, which is not a pass.
```

## bin/drift-reference-check.sh, lines 664-665 (before this edit)

```text
Held in a variable, not a temp file: an unwritable TMPDIR made the file's 473 rows read as none (2026-10-27).
graph-gen exits 0 clean or 1 with dangling rows; anything else judged nothing, and says so as a finding.
```

## bin/drift-reference-check.sh, lines 682-710 (before this edit)

```text
harbor#462's actual finding, and the reason REF-5 above could be "fixed" for
three years without the defect moving: `./docs/explanation/grilling.md` is not a wrong
path, it is an UNROOTED one. The constitution is authored in a tree where `./`
works and installed in one where it does not, so every citation in it is green
at the source and dead at the only place anyone reads it. Nothing in the text
said which tree it meant, so each reader resolved against wherever they were
standing and got a different answer.

What breaks: silently, and in the direction that reads as health. A session
following §"Context sufficiency" to `./docs/explanation/grilling.md` gets nothing, so
what actually binds is the one-paragraph summary in the constitution — weaker
than the doctrine it replaced and sitting next to an escape clause.

WARN-SHAPED, NOT CRIT, and deliberately so: a document that ships beside what
it cites needs no declaration, and demanding one everywhere would fire on every
correct README on the box. It fires only where the fallback is doing real work
— a config-dir document citing ./paths that DO resolve there is silent, because
nothing is at risk; one whose citations resolve only by luck is what this names.
THE PREDICATE IS A FAILURE, NOT A HABIT, and the first cut of this rule got
that wrong in the direction that matters. It fired whenever a document cited
any ./path without declaring a root — which is true of every correct README
that ships beside what it cites, and the suite caught it immediately: five
green assertions went red, including "the clean fixture is clean". That is
§2.11 exactly, and a rule that fires on correct documents is one the operator
mutes, after which it cannot carry the finding it was built for.

So it speaks only where the missing declaration is doing real damage: a ./
citation that FAILED, in a document that never said which root it meant. All
resolving means nothing is at risk and this stays silent whatever the dialect.
```

## bin/drift-reference-check.sh, lines 719-767 (before this edit)

```text
REF-5 generalised from one document to the corpus beside it, and the reason it
is a separate rule rather than a wider REF-5 is that the two have different
blast radii: the constitution is charged to every session, a skill is read when
its subject comes up. Same extractor, same resolver, same declared-root rule.

WHY IT EXISTS: harbor#462 was filed as ten dead pointers in one file, and the
constitution was fixed first because it is the largest single item in the
context budget. That framing was too narrow. Measured 2026-09-06 across 46
installed skills and 539 markdown files, with REF-5's own resolver: THREE
citations are dead at the point of use, and all three are the same defect —

  skills/dev-tracking/SKILL.md   ../../contracts/cu.md
  skills/test-strength/SKILL.md  ../../contracts/prove-targets.md
  skills/test-strength/SKILL.md  ../../docs/explanation/verification-expanded.md

— a skill escaping its own directory to reach a repo document the installer
does not deploy. Green from the repo, dead from ~/.claude/skills/<name>/. The
third one is the sharpest: test-strength is the skill whose whole subject is
gates that cannot fail, and its pointer to the contract listing the declared
prove-targets handed the reader nothing.

RELATIVE CITATIONS ONLY, and this is the false-positive line (§2.11). An
absolute `/x` is already rooted, so the ambiguous-root question this rule asks
does not apply to it — and the vendored corpus is full of web-absolute paths
that are not filesystem paths at all: `/favicon.png` inside
fabric/Patterns/create_markmap_visualization/system.md is the recorded case.
Reporting that as a dead file reference would be a rule the operator mutes,
and a muted rule protects nothing. Config-owned absolutes are REF-1's and
REF-4's job, where the tool knows what the path is FOR.

ONE AWK PROCESS, NOT ONE PER FILE. 539 files at one exec each measured 687 ms
against 135 ms for a single WITHFILE pass, and this rule is most of what the
check costs — a check that gets slow enough to notice is a check someone moves
off the session path. The measured total belongs to docs/reference/checks.md's row and is
deliberately not restated here: this comment said `0.22 s` while that row said
0.31 s, which is the copy-drift CONSTITUTION "derive it" exists to stop.

NOT skills/synced/, AND THIS IS AN OWNERSHIP LINE, NOT A PATTERN. The harness
writes that tree itself — account-synced skills, one `<bucket>/manifest.json`
per sync, surfaced in the listing as `anthropic-skills:*` — and rewrites it on
every sync, so no edit made on this box survives to repair a finding there. It
arrived after this rule was written and was scanned by default. Measured
2026-09-17: its first run here produced REF-9's only two findings, both the
`[Source](URL)` citation TEMPLATE deep-research hands its subagents, where
`URL` is a placeholder and not a file. A red nobody on this box can act on is
the §2.11 defect, not caution. The tree is COUNTED and not examined, so the
exclusion is visible on every run rather than silent. A per-tree owner field
would let this line read a registry instead of naming a path (harbor#527);
until one exists, this path is the only such exclusion.
```

## bin/drift-reference-check.sh, lines 779-782 (before this edit)

```text
Both halves of REF-9's denominator (harbor#467): how many rows came back,
and how many files they could have come from. The second is what makes the
first readable — `0 citations` over 0 files is an empty skills tree, and
`0 citations` over 539 files is a broken extractor.
```

## bin/drift-reference-check.sh, lines 791-793 (before this edit)

```text
The declared root is read once per document, not once per citation: a
skill carrying twelve references would otherwise re-parse its frontmatter
twelve times, and the answer cannot change between them.
```

## bin/drift-reference-check.sh, lines 818-828 (before this edit)

```text
harbor#467, and the rule the 34 days of green actually needed. Every rule above
asks "does what I found resolve"; this one asks the question none of them can,
which is "did I find anything at all". They are not the same question and the
output cannot tell them apart: a gate over a document full of citations it
cannot parse prints the identical clean line as a gate over a document with
none, and the operator has no way in from the outside.

The predicate is deliberately asymmetric — the real extractor decides there is
a problem by returning zero, and `_looks_cited` only decides whether that zero
is suspicious. Neither can fire alone, which is what keeps a broad probe from
becoming a false positive (see _looks_cited for what that costs).
```

## bin/drift-reference-check.sh, lines 834-837 (before this edit)

```text
Only reached when the corpus produced zero rows, so the cost of this second
pass is paid exclusively in the broken case.
The same corpus REF-9 read, or this could name a synced file as proof the
extractor went blind on a file the extractor was never given.
```

## bin/drift-reference-check.sh, lines 845-862 (before this edit)

```text
REF-5 is guarded on `[ -f "$DIR/CLAUDE.md" ]`, so until this rule existed the
absence of the constitution was the quietest possible state: zero findings,
exit 0, "every hook, pin and citation resolves". A checker whose clean result
is indistinguishable from "there was nothing to check" is the exact failure it
was built to catch, and it shipped that way on 2026-08-03 — found the same day
by an adversarial pass, which also found `harbor verify` green on the same box
for the same reason (admission-verify.sh now carries the B8 half of this).

THE PREDICATE IS `settings.json`, NOT the directory. An empty or absent dir is
answered above: nothing is installed, so nothing dangles. A dir carrying
settings.json is a CONFIGURED box, and a configured box with no CLAUDE.md is
not "unused" — it is governed by hooks and guards while loading no doctrine.

BEFORE WIRING THIS INTO floor-verify OR A GATE, READ THIS: test-sandbox-make.sh:69
aborts when floor-verify fails, and it never writes a CLAUDE.md into a
sandbox. This rule is correct FOR A SANDBOX — doctrine genuinely is not
loaded there — so anything that turns it into a hard failure must give
sandboxes a constitution first, or it breaks every sandbox build (№2.11).
```

## bin/drift-reference-check.sh, lines 932-935 (before this edit)

```text
THE DENOMINATOR IS PART OF THE VERDICT, never a --verbose extra (harbor#467).
Printed on a clean run as well as a dirty one, because a clean run is exactly
where "0 findings" and "0 items examined" become indistinguishable, and that
is the state this tool spent 34 days in.
```
