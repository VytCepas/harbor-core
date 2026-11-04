---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/lint-port-paths.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/lint-port-paths.sh, lines 15-24 (before this edit)

```text
WHY ONE SCRIPT FOR BOTH. harbor#619's last acceptance criterion is "No script
or config names a pre-move repo path". A checklist cannot close that; a
re-runnable scan can, and the same scan that enumerates the work before the
move proves the absence after it. Run it now, fix what it lists, run it again.
It graduated here from ~/Deliverables/2026-09-22-r2-workspace-root/ (harbor#629)
so that it cannot regress unnoticed; its suite is tests/lint/port-paths/port-paths.test.sh.

DELIBERATELY ONE FILE (lint G1, docs/explanation/modularity.md): the surface list and
the matcher are one contract — splitting them puts the question and the answer
in two files that drift.
```

## bin/lint-port-paths.sh, lines 26-50 (before this edit)

```text
THE MATCH. A repo path is (~|$HOME|<home>)/<repo> followed by a separator or
end. The prefix alternation matters: SKILL.md files write ~/<repo>, shell
defaults write $HOME/<repo>, and plists must write the absolute form because
launchd expands nothing. Matching the bare repo NAME would be useless —
"harbor" appears in every com.harbor.* launchd label and every .helm-* filename.

GREP IS UGREP HERE, and the config dir IS A GIT REPO, so a plain `grep -r` over
it SKIPS every gitignored file and reports a false absence. Every scan below is
therefore a `find` that builds an explicit file list, piped to grep one file at
a time. Never replace this with `grep -r`.

NOT COVERED, on purpose: eval fixtures and historical run logs
(harbor evals/, skills/*/EVALS/) carry literal paths that are a record of
a past run, not live configuration. Rewriting them would falsify the record.

THE EXCLUSION PATHSPEC IS LOAD-BEARING AND WAS WRONG. `:!skills/*/EVALS`
READS correctly and excludes NOTHING: a git pathspec carrying a wildcard is
fnmatched against the WHOLE path, and that pattern has no trailing `/*`, so
`skills/topology/EVALS/RUN-2026-08-30/returns.jsonl` never matches it. The
form that fires is `:!*/EVALS/*`. Measured 2026-09-23: the broken spelling
inflated CODE by 61 rows, every one of them a historical eval record that
must NOT be rewritten — a gate demanding 61 falsifications of a past run is a
gate that gets switched off (CONSTITUTION No.2.11). --selftest now asserts the
exclusion fires, because the failure is invisible in the output: the rows look
exactly like real findings.
```

## bin/lint-port-paths.sh, lines 53-54 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140): the text is the first header
paragraph, read out of THIS file, so it cannot drift from what the script is.
```

## bin/lint-port-paths.sh, lines 77-81 (before this edit)

```text
EVERY SCAN READS THE PHYSICAL HOME, $PORT, never $HOME_DIR/<repo>. Until
2026-09-23 this read the repos at their old addresses, which after phase A are
bridges — and phase C deletes the bridges. Every scan here is guarded by
`[ -d … ] || continue`, so on the day the gate matters most it would have
looked at nothing and reported CODE=0. Measured by reading, before phase C ran.
```

## bin/lint-port-paths.sh, lines 85-108 (before this edit)

```text
THE REPOS ARE DERIVED FROM $PORT, NEVER LISTED. The Deliverables copy carried a
hand-written list of thirteen names, and a hand list of what lives in a
directory went stale within the hour during the move: repos arrive, worktrees
come and go, and a name missing from the list is a repo whose old address is
never matched — a silent green. So the list is read off the directory:

  a directory directly under $PORT with a `.git` is a repo          (<repo>)
  one without, holding repos one level down, is a container        (<root>)
  a sibling worktree, `<repo>-wt-<name>`, is neither — it is a second view of
  a repo already counted, so scanning it would count every row twice, and its
  name is not an address anything was ever moved from.
  SO IS A WORKTREE WITH ANY OTHER NAME (harbor#629). Measured 2026-09-24:
  another session created ~/port/<repo>-<topic> with `git worktree add`, the
  name matched no `-wt-` rule, and it was scanned as a repo of its own — away
  from the measurement repo's exemption rows — turning --verify RED with 8 CODE and 41 DOC
  rows that repo itself had already settled. The name was a convention; the
  STRUCTURE is the fact: a `.git` FILE whose common directory lies under $PORT
  is a view of a repo counted here. One whose repository lives elsewhere is
  still scanned — that is how a branch is measured before it merges (case 17).

TARGETS are what 1b scans (relative to $PORT: <repo>, <root>/<repo>, …); NAMES are
the first path components — the names a pre-move literal carries (<root>, not
<root>/<repo>). Names are dropped into an ERE unescaped: repo names are
[A-Za-z0-9_.-], where the only metacharacter, `.`, over-matches — the safe side.
```

## bin/lint-port-paths.sh, lines 141-152 (before this edit)

```text
One alternation, built once: (~|$HOME|<home>)/(repo)(separator|end). The tail
group is what refuses a LONGER name — ~/harborage, ~/zorbcorpal — and what
refuses a sibling worktree's address (~/zorbcorp-wt-x), because `-` is not a
separator. --selftest proves both.

A FULL STOP ENDING A SENTENCE IS A SEPARATOR; one starting a suffix is not.
`.` sits in the name class so that ~/harbor.md and ~/harbor.bak stay unmatched,
and until 2026-09-23 that also hid every path that ends a sentence — "moved
out of ~/harbor." Measured that day against the same exemption table: nine
rows this box had never shown, five in harbor's tracked files and one CODE.
So `.` counts when whitespace, end of line, or a closing quote, backtick or
parenthesis follows it.
```

## bin/lint-port-paths.sh, lines 158-191 (before this edit)

```text
CODE or DOC. A gate that demands every prose mention of a repo be rewritten
lists every README line, and a guard that blocks ordinary work gets switched off
(CONSTITUTION No.2.11) — so only CODE gates. DOC is a real follow-up list
(harbor#629) and is reported separately, never as a blocker.

The shell-comment rule is the one from memory `guard-satisfied-by-its-own-comment`
read backwards: a path inside a `#` comment cannot break anything at runtime,
exactly as a rule inside a comment cannot enforce anything. Four refinements,
each from a run that got it wrong:
  A SHEBANG IS CODE. `#!/Users/…/.venv/bin/python` begins with '#', and the
  comment rule would file the one line that decides which interpreter runs as
  documentation. Found by reading, 2026-09-23, before the venv scan ran.
  THE OTHER REPOS COMMENT IN OTHER LANGUAGES. Scanning them (1b) put 3 JavaScript
  `//` lines and 3 `--` SQL comments into CODE on the first run — every
  one prose. Scoped by extension, because `--` opening a line of a SHELL script
  is an argument continuation, and that is code.
  A PATH ROOT IN MARKDOWN IS CODE (harbor#653). A `**Path root:**` line is
  parsed, not read: drift-reference-check.sh REF-5 takes its first backticked token
  as the root every `./` citation in the document resolves against. Filed as
  DOC, the installed constitution's `~/harbor` root sat under a green gate on
  2026-09-23 while REF-5 reported all 11 of its citations resolving nowhere.
  Scoped to .md: the same text in a shell comment documents the format.

EXEMPT. A row the operator decided to keep, listed with its reason in
contracts/port-paths-exempt.tsv. Matched per LINE (file relative to $PORT, plus
fixed text on the line), so a new literal in an exempted file is still counted.
ONE widening, for DOC only: text `*` exempts a whole file, because a dated
record (an archive, an audit, a run log) is history in every line, and listing
its lines one by one would be a copy of the file. A `*` row never exempts
CODE — a file of records that grows an executed path must show.
  `@HOME@` in a row's text stands for this box's home directory, rendered when
the table is read. The table is TRACKED, and lint HP1 refuses a tracked file
that names its author's home, which the rows quoting a plist or a provenance
stamp otherwise have to (harbor#602); the same placeholder floor-equiv renders.
```

## bin/lint-port-paths.sh, lines 193-207 (before this edit)

```text
CLASSIFY, EXEMPT AND FORMAT ARE ONE awk PROGRAM, RUN ONCE OVER EVERY ROW. The
Deliverables copy did all three as shell pipelines per row — about twenty
processes a row, and is_exempt() re-read the whole table for every one — so
the cost was rows x table. Measured 2026-09-23 on this box: its --verify, which
also ran the whole scan twice, took 126 s; this one scans once, in about 12 s,
and on one table the two inventories were byte-identical row for row (before
the full-stop change to the matcher above). Here the table is read once and a
row costs no process at all. The shell functions classify()
and is_exempt() below are one-row wrappers over THIS program, so --selftest
exercises the code the scan runs rather than a copy of it.

LC_ALL=C, because macOS awk (20200816) is byte-based in substr() and dies on a
regex over a lone UTF-8 continuation byte. trunc() counts CHARACTERS itself —
a byte in \200-\277 continues one — which is what `cut -c1-120` did, so the
literal column is unchanged and never ends in half a character.
```

## bin/lint-port-paths.sh, lines 209-211 (before this edit)

```text
The rows that name a client's directory are the private layer's own (harbor#1149), a table in the same
columns beside the core one. PORT_PATHS_EXEMPT names the only table read, so a suite's fixture stays
hermetic. An absent or unreadable overlay, or no layer, is the core table alone: those rows then count again.
```

## bin/lint-port-paths.sh, lines 238-247 (before this edit)

```text
AN INSTALLED COPY IS JUDGED BY THE ROWS OF ITS SOURCE (harbor#629). $CFG/skills
and $CFG/bin are what skills-install and runtime-install ship out of harbor
skills/ and bin/, so a line the operator kept in the source is the same line,
kept for the same reason, in the copy. Before this, the table matched only
paths under $PORT, and on 2026-09-23 all 46 DOC rows reported for the config
dir were lines already exempted in harbor — a DOC count 85% phantom, which is
how a count stops being read. Those two subtrees map, and so does CLAUDE.md,
which constitution-install ships out of harbor policy/constitution.md (harbor#653):
settings, .claude.json and MEMORY/ are not copies of anything. NO
APOSTROPHES in this program: it is one single-quoted shell string.
```

## bin/lint-port-paths.sh, lines 303-317 (before this edit)

```text
harbor's tracked files, through ONE pathspec — scan 1 and --selftest both call
this, because a selftest that asserted its own COPY of the pathspec would stay
green while the scan's spelling broke, which is the exact defect above.
  registries/coverage-incidents.tsv is excluded for the EVALS reason: it is a dated sweep
  (its own header says "Swept 2026-09-22"), and its evidence column quotes code
  and handoff notes as they read that day. Rewriting a quote to make a gate
  green falsifies the record the gate exists to protect.
  THIS INSTRUMENT'S OWN FILES are excluded for the same reason: the script's
  selftest vectors, its suite's fixtures and the exemption table ARE pre-move
  literals, quoted as data; scanned, they turn the gate red on its own test
  data (suite case 8). The cost, named: a real pre-move default written here would
  go unseen here — its defaults derive from PORT_ROOT and HOME instead.
  ONE LIST, applied to every repo scan (1b too): harbor-core mirrors these files and the private layer keeps its own
  exemption table, and scanned there they were 157 of 159 CODE rows on 2026-10-27, the gate red on its own data. The
  suite split into tests/install/port-paths/ is listed beside the file it came from.
```

## bin/lint-port-paths.sh, lines 324-330 (before this edit)

```text
--selftest. The two load-bearing parts are the regex and classify(); everything
else is a file list. Each case below was watched FAIL on a deliberate mutant
(CONSTITUTION No.2.10): dropping the trailing separator group from PAT makes
"harborage" and "com.harbor.audit.triage" match, and removing the '#' arm of
classify() turns the commented case CODE. The matcher is built from FIXED
names here, not from $PORT, so the cases test the construction and do not
depend on which repos this box happens to hold.
```

## bin/lint-port-paths.sh, lines 351-354 (before this edit)

```text
These three are the ONLY cases that exercise the trailing separator group.
The three above do not: they have no ~/ or $HOME/ prefix, so they fail on the
prefix alternation whatever the tail does. Measured — a mutant that deleted
the separator group passed all 12 tests until these were added.
```

## bin/lint-port-paths.sh, lines 359-360 (before this edit)

```text
The full stop. The first two were MISSED before 2026-09-23; the last two
are why `.` is still a name character everywhere else.
```

## bin/lint-port-paths.sh, lines 380-382 (before this edit)

```text
EXEMPTIONS are per line. Against a scratch table, so the live one's rows
neither help nor hurt: the exact line is exempt; another line in the SAME
file, and the same text in ANOTHER file, are not.
```

## bin/lint-port-paths.sh, lines 395-397 (before this edit)

```text
The installed copy of harbor/skills/demo/SKILL.md is judged by that row; a
different line in the copy is not; and a config-dir file outside skills/ and
bin/ is a copy of nothing, so no harbor row can reach it.
```

## bin/lint-port-paths.sh, lines 401-402 (before this edit)

```text
The installed constitution is policy/constitution.md shipped by constitution-install,
so it takes that file's rows; a MEMORY/ document is a copy of nothing.
```

## bin/lint-port-paths.sh, lines 407-411 (before this edit)

```text
The EXCLUSION, asserted through harbor_grep — the function scan 1 runs, never
a copy of its pathspec. Not a pure-function test like the two above, so it
SKIPS loudly rather than failing where harbor is absent — but where harbor IS
present this is the only thing standing between a wrong pathspec and 61
phantom rows, and the wrong pathspec reads correctly.
```

## bin/lint-port-paths.sh, lines 426-433 (before this edit)

```text
--verify. The inventory is the input to the count, not the deliverable: run it
once, count it, and give back only the verdict. Printing every row and then a
verdict buries the verdict, which is the whole point of a gate. (The
Deliverables copy ran the whole scan twice here, once into /dev/null.)

A SCAN THAT DIED IS EXIT 3 (D-29 UNCHECKED), NEVER A COUNT. Through a pipe the inventory's exit
status was lost, so a scan that aborted half-way under `set -e` would have
counted the rows it got to — possibly none — and printed a green.
```

## bin/lint-port-paths.sh, lines 445-449 (before this edit)

```text
A STALE exemption — its line is gone — is reported, never silently kept: a
rule that can no longer match anything is how a list of reasons rots.
A WHOLE-FILE `*` row is stale when its file names no pre-move path at all.
The Deliverables copy searched such a file for a literal `*`, which any
markdown file with one bold word satisfies for ever.
```

## bin/lint-port-paths.sh, lines 458-460 (before this edit)

```text
The file of the row AND the installed copy the scan maps onto it (FINISH_AWK: skills/, bin/, CLAUDE.md):
a skill retired from the tree but still installed kept its row live, and was reported stale (2026-10-27).
No apostrophe in a comment here: inside $( ) bash 3.2 reads one as an open quote.
```

## bin/lint-port-paths.sh, lines 498-501 (before this edit)

```text
0 · NOTHING DERIVED IS A CODE ROW, never an empty scan. With no repo under
    $PORT there is no name to match, so every scan below would look at nothing
    and the gate would read green on the day PORT_ROOT points at the wrong
    directory.
```

## bin/lint-port-paths.sh, lines 507-511 (before this edit)

```text
Every scan writes RAW rows into one file, and finish() classifies them in one
pass at the end. A file and not a pipe: a brace group redirected to a file
runs in THIS shell, so a scan that fails under `set -e` stops the script with a
non-zero exit that --verify turns into exit 3 — through a pipe, awk's 0 would
have been the only status anyone saw.
```

## bin/lint-port-paths.sh, lines 516-522 (before this edit)

```text
1 · harbor's tracked files. git grep sidesteps the ugrep gitignore problem
    entirely: it reads the index, not the working tree's ignore rules.
    A MISSING CHECKOUT IS A CODE ROW, never a silent skip: this is the scan
    that covers the most literals, and "looked at nothing" must not read as
    "found nothing". `-e`, not `-d`: a WORKTREE's `.git` is a file, and the
    Deliverables copy's `-d` printed NO CHECKOUT for a PORT_ROOT whose harbor
    was a worktree, so a branch could not be measured before it merged.
```

## bin/lint-port-paths.sh, lines 532-537 (before this edit)

```text
1b · every OTHER moved repo's tracked files. Not scanned at all until
     2026-09-23, when a sweep found 74 CODE literals across five workload
     repos — justfiles, scripts and configs that
     name ~/<repo>/bin/gcx or ~/<repo> and work today only through a bridge.
     A target git cannot read — a worktree whose admin directory is gone — is
     a CODE row for the same reason a missing harbor checkout is.
```

## bin/lint-port-paths.sh, lines 545-546 (before this edit)

```text
   estate's dated audits (docs/reports/, AUDITS/ before its October 2026 rename) are excluded for the EVALS reason: a dated
   audit's findings.json quotes the paths it measured on that day.
```

## bin/lint-port-paths.sh, lines 560-566 (before this edit)

```text
2b · the installed constitution and the top-level MEMORY documents (harbor#653).
     CLAUDE.md is what every session loads, and a stale `**Path root:**` in it
     turns every `./` citation into a dead one. The green of 2026-09-23 read
     bin/ and skills/ and never opened it. MEMORY/ is read at depth 1 only: its
     WORK/ and USAGE/ subtrees are session logs that quote paths as they were
     (the EVALS reason). Its other subtrees were not examined when this landed,
     so widen this when one is shown to be read as live instruction.
```

## bin/lint-port-paths.sh, lines 570-575 (before this edit)

```text
3 · settings and Claude Code's own per-cwd state. `.claude.json` is NOT inside
    the config dir: with CLAUDE_CONFIG_DIR unset — every live session on this
    box — Claude Code keeps it beside the dir, at $HOME/.claude.json, and that
    is the file remove-bridges.sh carries over in phase C. It is therefore
    named through $HOME_DIR and not through $CFG; D1's concern, a config dir
    hardcoded instead of resolved, does not apply to a file outside it.
```

## bin/lint-port-paths.sh, lines 579-581 (before this edit)

```text
4 · fleet discovery. Gitignored by design (.gitignore:68), so it has NO version
    history — and po#305 measured that register() silently drops two fields and
    every comment. Edit it by hand, never by tool.
```

## bin/lint-port-paths.sh, lines 583-585 (before this edit)

```text
    The root line names $HOME itself, which PAT cannot see — it carries no
    repo name. Scanning $HOME at depth 1 after phase C finds zero projects and
    raises no error (roots.tsv, HARBOR_SCOPE_FLEET_FILE), so it is checked by value.
```

## bin/lint-port-paths.sh, lines 605-626 (before this edit)

```text
7 · git worktree admin files. Two per worktree, both absolute: the worktree's
    `.git` file and the owner's `.git/worktrees/<n>/gitdir`. A row only when a
    pointer NAMES a pre-move path. Until 2026-09-23 this printed one row per
    worktree whatever the pointers said — a pre-move enumeration, which after
    the move reported 17 phantom rows for pointers `git worktree repair` had
    already fixed, and would have kept the gate red forever.
    `repair` leaves a pointer alone while it still RESOLVES, and through a
    bridge it does: measured 2026-09-23, ~/.local/lib/<tool>/.git still named
    the old address after repair and was fixed by hand. That is the case this
    finds. The owners are every derived target, not a hand list: the
    Deliverables copy named six, and four more repos had grown worktrees by the
    time it graduated. A target with no worktrees costs one `git` call.
    `|| continue`, NEVER `[ -f … ] && scan`: the loop's last body command is
    its status, a pipeline's last element runs in a subshell, and under
    `set -e` a `while` that ends on a false test takes the whole script down.
    The Deliverables copy had the `&&` form and survived only because each of
    its six owners happened to list a worktree last; derived owners include a
    repo with none (the main checkout's `.git` is a directory), and the first
    run died there.
    `-e`, not `-d`: a target that is itself a worktree (PORT_ROOT pointed at a
    branch under review) has a `.git` FILE, and `git worktree list` answers
    from it just the same.
```

## bin/lint-port-paths.sh, lines 641-646 (before this edit)

```text
8 · virtualenvs inside a moved repo. A venv is not relocatable: its activate
    scripts, console-script shebangs and editable-install .pth files carry the
    absolute path it was built at. Measured 2026-09-23: five venvs (three workload repos and
    the two Harbor tools) name the old
    address in 76 bin/ files, and work today only through a bridge. The fix is
    a rebuild (`uv sync` against the lock), not a rewrite of this list.
```
