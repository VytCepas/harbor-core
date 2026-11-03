---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-deny.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-deny.sh, lines 11-16 (before this edit)

```text
Extends the SEC-0 read-deny set with EDIT coverage of the same
credential stores, workflow-file protection, and harness-layer protection of
the live config surfaces (defense-in-depth above the B2 hook — deny is
additive, evaluated before hooks, and un-swallowable in every mode).
Append-only by default: --apply never removes or rewrites an existing entry.
Recomputes the .sec0-baseline.sha256 pin with the SAME recipe as deploy-harden.sh:82.
```

## bin/admission-deny.sh, lines 18-36 (before this edit)

```text
DELIBERATELY ONE FILE (docs/explanation/modularity.md), and G1 asked, so: every mode here
writes the same settings.json and re-pins with the same two hashes. Splitting
--apply, --repin, --withdraw and --prune-inert into separate scripts would put
four copies of the pin recipe in four files, and the failure that recipe exists to
prevent — B6 blocking every session on a hash computed a different way — is
exactly what divergent copies produce. The blast radius is the deny list either
way; keeping it in one file keeps the write path in one place.

NOTE the deliberate frictions (plan of record, harbor#3 + REVIEW F-findings):
• Edit(//**/.github/workflows/**) blocks ALL in-session workflow-file
  edits — the gh token keeps `workflow` scope (F-finding: dropping it breaks
  CI pushes without stopping dispatch), so the file surface is the control.
  Legit CI edits: lift the entry in an unguarded session, or edit outside.
  MEASURED 2026-07-30 (harbor#61): this entry binds the FILE TOOLS only. `Edit`
  on a workflow file is refused and `git apply` on the same file succeeds, and
  admission-bash.sh — which would close the shell path — is not installed. Keep the
  entry; stop calling it sufficient.
• deny is NOT bypassed by HARBOR_ADMISSION_DISABLE — that env only stands down the
  B2-B6 hook layer. Deny entries change only by editing settings.json.
```

## bin/admission-deny.sh, lines 85-88 (before this edit)

```text
Atomic write, VERIFIED. A bare `jq . >tmp && mv` cannot fail loudly under
set -eu: a failing left side short-circuits the && and execution continues, so
the script printed "APPLIED." while settings.json was untouched and a
settings.json.tmp.NNNN was orphaned (red-team pass 8).
```

## bin/admission-deny.sh, lines 111-186 (before this edit)

```text
The B1 additions. Edit mirrors SEC-0's Read stores 1:1; the ~/.claude
entries protect the LIVE surfaces from any session (sandbox included) at the
harness layer — B2 protects the running session's own CLAUDE_CONFIG_DIR at
the hook layer. Read(~/.claude/.helm-log-token) closes a SEC-0 gap: the G1
token file was minted after the read-deny set was pinned.

"1:1" WAS A CLAIM, NOT A FACT, FOR SEVEN OF NINETEEN PATHS (harbor#88). This
comment has said "mirrors SEC-0's Read stores 1:1" since the file was written,
and lint rule D5 now makes it true instead of aspirational. It was not: the
twelve `~/`-anchored stores had Edit twins and the six `//**/` PROJECT
credential globs — .env, .env.*, secrets/**, *.pem, id_rsa, id_ed25519 — plus
gcalcli had none. What that cost, measured by FIRING it rather than reading:

  Write  at <path>/.github/workflows/probe.yml  → REFUSED   (an Edit deny)
  Write  at <path>/.env                         → CREATED   (a Read deny)
  Edit   at <path>/.env                         → REFUSED   (a Read deny)

So an agent could not READ a project's .env or a stray private key, and could
OVERWRITE either one. The permissions reference states both halves: a Read deny
also blocks the Edit tool "including creating a new file there", but "Write and
NotebookEdit aren't covered, so add an `Edit` deny rule for paths no tool may
change" (code.claude.com/docs/en/permissions, read 2026-08-02, v2.1.208+).

THE TWINS COST NOTHING IN FRICTION, which is why they are safe to add wholesale:
the Edit TOOL is already refused on every one of these paths by the Read deny —
fired above — so the only behaviour that changes is Write and NotebookEdit,
which had no legitimate use on a file the same session is forbidden to read.

This is harbor#88's finding, in the half of the list the ticket did not look at.
The ticket's own example — `.github/workflows/**` being denied for Edit and "not
Write" — is not a gap at all: `Edit(path)` covers every file-editing tool, and
adding `Write(path)` beside it would emit an entry the harness accepts and never
consults, which is the inert class lint D4 forbids and `--prune-inert` removes.

ANCHORING IS LOAD-BEARING (harbor#53). Read/Edit/Write patterns are gitignore
syntax against an ANCHOR, and these live in USER settings:
  //path   filesystem root      — the only form that matches every project
  ~/path   home directory
  /path    the SETTINGS SOURCE — in user settings that is ~/.claude, NOT /
  path     the current directory — whatever dir the session happens to be in
`Edit(**/.github/workflows/**)` shipped here bare-relative, so it was anchored
at the SESSION WORKING DIRECTORY: it protected workflow files in whatever repo
the session happened to be anchored to and no other, while deploy-harden.sh:150
reasoned about it as an unconditional control compensating for the gh token's
`workflow` scope. Both halves were proven by FIRING it, not by reading: an Edit
outside the anchor went through, an Edit on this repo's own governance.yml was
blocked. cwd is not a boundary anyone chose, which is the whole argument for
`//`. `Edit(/mnt/c/Users/**)` was worse and simpler — a single leading slash
anchors at the settings source, so it resolved to ~/.claude/mnt/c/Users/** and
could never fire anywhere. A new cross-project entry uses `//` or `~/`;
floor-test.sh asserts it (see harbor#54).
NO `Write(<path>)` ENTRIES — they are accepted and never consulted (2026-07-30).
Every one of these paths shipped as an Edit/Write PAIR, on the reasonable-looking
assumption that the two tools need separate rules. The harness says otherwise, in
its own words, at every session start:

  "Permission deny rule: Write(~/.ssh/**) is not matched by file permission
   checks — only Edit(path) rules are. Use Edit(~/.ssh/**) instead (Edit rules
   cover all file-editing tools)."

and the permissions reference (code.claude.com/docs/en/permissions, read
2026-07-30, v2.1.210+) states the rule directly: "Claude Code checks file
permissions against `Edit(path)` and `Read(path)` rules only. If you write a
path rule for `Write`, `NotebookEdit`, `Glob`, or the legacy `MultiEdit` tool
instead, Claude Code accepts the rule but never consults it".

WHAT WAS AND WAS NOT LOST. Nothing: every removed `Write(p)` had an `Edit(p)`
twin, and the Edit rule covers every file-editing tool — verified by firing it,
not by reading, when a `Write` tool call at an absolute path was refused by
`Edit(//**/.github/workflows/**)`. So this removes 24 inert entries and no
protection. A bare `Write` with NO path is a different thing and IS consulted at
the tool level; the docs say so and this list has none.

The pairing is what made it invisible: a half-inert list where the live half
does the work reads as a working list. The live config still carries these
entries because admission-deny.sh is append-only — `--prune-inert` removes them.
```

## bin/admission-deny.sh, lines 257-277 (before this edit)

```text
── WITHDRAWN (harbor#58) ────────────────────────────────────────────────────
Entries the operator has DECIDED against. This is data, not a comment, and that
is the whole fix: from 2026-07-29 until 2026-07-30 the fork-bomb withdrawal below
lived as prose saying "do not re-add this", which is a wish. Nothing stopped a
future edit — or a future session reading the corpus and being helpful — from
putting the entry back in ADD, and nothing removed it from a config that still
carried it.

Now: --apply SUBTRACTS this list from ADD, so re-adding an entry to ADD cannot
resurrect it; `--withdraw` REMOVES these entries from the target settings.json
and re-pins; and floor-test asserts the two lists never intersect.

ADDING TO THIS LIST IS A SOURCE EDIT ON PURPOSE. CONSTITUTION says encoding a
fix is a human-gated act, so there is deliberately no `--withdraw <entry>` that
takes an argument: the record has to exist in the tree, reviewable, before the
tool will act on it. A withdrawal you can perform from the command line is a
withdrawal with no memory, which is the defect this closes.

"Bash(:(){ :|:& };:)" — the fork-bomb glob — was in ADD, was applied live, and
the operator removed it from settings.json by hand. Append-only meant the next
--apply would put it back, silently overruling a decision already made.
```

## bin/admission-deny.sh, lines 281-339 (before this edit)

```text
CANDIDATES, NOT WITHDRAWN — the operator has not decided, so the tool must not
act. Six bare-relative Read entries in the live config (`Read(**/.env)` and its
five siblings) are now redundant subsets of the `//`-anchored versions
deploy-harden.sh writes. They are WORKING rules — a deny rule with a single
directory segment matches at any depth under the cwd — so --prune-inert refuses
them by design, and removing a working rule is exactly the act that needs a
person. Move a line up into WITHDRAWN to decide it.
BASH DENIES AT THE HARNESS LAYER (coverage sweep, 2026-07-26). Until now
permissions.deny held Read/Edit/Write entries ONLY — verified: zero `Bash(`
entries live or in this list — so the floor's entire answer to 'rm -rf /' was
admission-bash.sh, which is a text scanner with acknowledged residuals AND is not
installed. These cost nothing, are evaluated by the harness BEFORE any hook
runs, cannot be swallowed by a broken guard, and are independent of the install
decision that twelve adversarial passes have not settled.

They are GLOB matches on the command string, not a parser, so they catch the
literal spellings and nothing cleverer — 'rm -rf $(echo /)' walks past them.
That is fine and is the point: this layer is the un-swallowable floor under the
scanner, not a replacement for it. docs/explanation/admission-baseline.md's layering already says B1 is the
only layer the model cannot argue with; it simply had no Bash entries in it.

EXTENDED 2026-07-26 by diffing upstream's own permissions.deny
(Upstream/install/settings.system.json @ a4e8e74, 42 entries) against this list.
That diff had never been run: the first twelve globs here were written from
scratch while a curated list sat in the tree the whole build harvests from.
Eight classes were missing outright, one of them badly:

  curl|wget PIPED TO A SHELL — the most common real-world compromise shape
  there is, and docs/explanation/approach.md:33 has said "never `curl | bash`" since day one
  with NOTHING enforcing it. policy/constitution.md § "a rule with no mechanism is a
  wish", found in Harbor's own approach document.

EXTENDED 2026-08-25 (harbor#306) — `diskutil` erase/reformat/zero/random/
partition/apfs-delete. mkfs and 'dd of=/dev/*' were here and diskutil was not:
the same irreversible physical wipe, one spelling missing, and QA-PLAN's R9 row
signed the guards' jq fail-open off as acceptable *because B1 is the backstop*.
For this tier B1 was empty, so the documented backstop did not exist — the whole
of harbor#306. admission-destroy.sh's own header already noted the gap one layer up
("guard-bash blocks mkfs and dd but not diskutil — same class, one spelling
missing") and closing it there left this layer still open.

THIS IS THE LAYER THAT MATTERS FOR THE MODES A GUARD CANNOT COVER. The
floor_seg_degraded backstop added to admission-destroy.sh/admission-cloud.sh handles an
unparseable call, but two failure modes never reach a guard at all: with jq
absent the guard exits before any rule (CMD reads empty), and a DELETED guard
file exits 127, which is not a deny. Both were measured as allows. permissions
.deny is evaluated by the harness before any hook runs and cannot be swallowed
by a broken guard, which is exactly the property those two modes need.

GLOBS, NOT A PARSER, and deliberately so — 'sudo diskutil eraseDisk' walks past
these just as 'rm -rf $(echo /)' walks past the entries above. That is the stated
division of labour for this layer: the un-swallowable floor under the scanner,
catching the literal spellings, with admission-destroy.sh covering the clever ones.

Also added: raw disk writes via REDIRECT (`* > /dev/disk*`) — the dd form was
covered and the redirect form was not; 'rm -rf ~/.claude' and `~/.claude/*`,
i.e. deleting the floor's own home, which nothing denied; 'rm -rf .git';
chmod 777 on $HOME/~ (only `/` and `/*` were covered); and the `master`
spellings of the force-push guard.
```

## bin/admission-deny.sh, lines 342-369 (before this edit)

```text
── THE `~<user>` SPELLING OF $HOME (pass 13) ───────────────────────────────
Measured on the live config before this: 80 deny entries, ZERO matching
`~[a-z]`. 'rm -rf ~' and 'rm -rf $HOME' were both denied and 'rm -rf ~someone'
was not — the same directory, a third spelling, and the gap sat in the one
floor layer that is actually installed on this machine (docs/explanation/admission-baseline.md: B2's hooks
are built, not wired; B1 is evaluated by the harness before any hook runs).

WHAT THIS LAYER CAN EXPRESS. Bash deny entries are GLOB matches over the
command string — a wildcard and nothing else. The general shape has exactly one
glob spelling, `Bash(rm -rf ~*)`, and it is unusable: `~*` also matches
'rm -rf ~/proj/node_modules', so it would refuse ordinary work in every project
on the machine. A guard that blocks ordinary work gets switched off, and a
disabled guard protects nothing (CONSTITUTION No.2.11) — so the general shape
does NOT belong here.

WHAT IT CANNOT, said plainly rather than papered over: this layer cannot deny
'rm -rf ~someoneelse', because it cannot enumerate accounts it has never seen,
and it cannot express "a tilde, then a name, then the end of the word" at all.
Both are covered one layer up, in admission-bash.sh, where TILDE_USER is a regex
that can require exactly that — and only there.

So B1 carries the names it can RESOLVE, computed at apply time. A hardcoded
"someone" would be correct on this machine and quietly wrong on the next,
which is the failure mode this file already documents for anchoring: a rule
that reads fine and matches nothing. `id -un` and the basename of $HOME are
both consulted because they can differ, and `unique` folds them when they do
not. A name carrying anything glob- or shell-significant is skipped rather than
quoted into an entry nobody could reason about.
```

## bin/admission-deny.sh, lines 384-386 (before this edit)

```text
ADD MINUS WITHDRAWN, and the subtraction happens HERE rather than being trusted
to whoever edits ADD. Belt and braces on purpose: the lists are far apart in this
file, and "someone will notice the comment" is what failed for a day.
```

## bin/admission-deny.sh, lines 392-396 (before this edit)

```text
THE APPROVAL GATE'S RULES (harbor#1018, docs/design/approval-gate.md). `ask` makes every gate-approve.sh call show
Claude Code's own dialog, in auto mode too, and no allow rule or PreToolUse allow can override it; the allow rules
let the unattended merge and the queue run without the classifier. Each names the INSTALLED copy under this
config dir, which the floor guards, never a checkout or ~/.local/bin link a session can edit; guard-bash refuses
every other spelling of these tools. Added like the deny entries: append-only, never rewritten.
```

## bin/admission-deny.sh, lines 404-411 (before this edit)

```text
THE VERB REGISTERS (harbor#1291, #1419). contracts/verbs/*.md hold one list of command shapes per CLI, and these
rules are DERIVED from their `allow` and `ask` rows rather than copied here, so a register cannot say one thing
while settings.json does another; tests/admission/git/verbs.test.sh and tests/admission/verbs/registers.test.sh hold
each register and these rules to one another. Append-only like everything above. A row whose spelling does not
start `<cli> <subcommand>` is skipped, never trusted: a leading flag or wildcard (`git -C * log *`) lets the `*`
absorb `-c core.pager=<cmd>`, which is how a read becomes arbitrary execution. Run from an installed copy with no
contracts/ beside it, nothing is derived and nothing is removed. The reader is install-lib's il_verbs, because
floor-uninstall takes the same rules back out.
```

## bin/admission-deny.sh, lines 429-438 (before this edit)

```text
── --repin (harbor#58) ──────────────────────────────────────────────────────
The act that had no tool. B1 is append-only, so the ONLY way to re-pin after
the operator deliberately edits settings.json was --apply, which also puts
back whatever they removed. That made a deliberate withdrawal unrepinnable:
leave the pin broken (and B6 would then block every session) or run a command
that silently reverses your own decision. Neither is a choice.

A re-pin BLESSES whatever is in settings.json right now, so it must never be
blind: it prints the entries B1 would add and does not add them, which is the
operator seeing exactly what they are signing. Writes two hashes, nothing else.
```

## bin/admission-deny.sh, lines 465-474 (before this edit)

```text
── --withdraw (harbor#58) ──────────────────────────────────────────────────
Removes every WITHDRAWN entry that is present in the target settings.json, then
re-pins. This is the act --prune-inert deliberately refuses: pruning deletes
syntax that cannot protect anything, while this deletes a rule that WORKS
because a person decided it should not.

THE SAFETY IS THAT IT TAKES NO ARGUMENT. It can only remove what the tree already
records, so the reviewable edit comes first and the command second. An operator
who wants a different entry gone edits WITHDRAWN and re-runs — which leaves a
diff, survives the next --apply, and cannot be done by accident at 2am.
```

## bin/admission-deny.sh, lines 505-517 (before this edit)

```text
── --prune-inert (harbor#58, second half) ──────────────────────────────────
REMOVES deny entries the harness accepts and never consults: a PATH rule for
Write, NotebookEdit, MultiEdit or Glob. This is the only removal this tool will
ever do, and it is safe for one narrow reason — such an entry cannot be
protecting anything, by the harness's own statement, so removing it changes no
verdict. It is not a general withdrawal tool: --repin blesses an operator's
manual removal, this prunes provably-dead syntax, and neither can delete a rule
that works.

PROTECTION-PRESERVING BY CONSTRUCTION: a `Write(p)` whose `Edit(p)` twin is
missing gets the twin ADDED before the Write is dropped, so a config that
depended on the dead entry ends up better protected, not worse. A bare tool name
with no path (`Write`) IS consulted at tool level — never touched.
```

## bin/admission-deny.sh, lines 526-532 (before this edit)

```text
Twins to add. EVERY unconsulted class has a documented replacement, and the
first cut of this only converted Write — so a `NotebookEdit(p)` or `Glob(p)`
would have been deleted with nothing put in its place, silently discarding
protection someone had asked for. That is the defect this whole mode exists to
repair, committed by the repair. From the permissions reference: "Use
`Edit(docs/**)` in place of `Write(docs/**)`, `NotebookEdit(docs/**)`, or
`MultiEdit(docs/**)`, and `Read(docs/**)` in place of `Glob(docs/**)`."
```

## bin/admission-deny.sh, lines 564-566 (before this edit)

```text
A prune changes the deny list, so both pins are stale by our own hand — same
recipe as the --apply and --repin arms, or B6 blocks every session on a hash
that was never wrong.
```

## bin/admission-deny.sh, lines 591-594 (before this edit)

```text
Print a command the accident gate ACCEPTS (harbor#51). The hint used to echo
"$DIR --apply" unconditionally, which for the live dir is the one shape the
gate refuses — so the tool taught the operator to run a refused command, and
the shortest way to make it work is to delete the gate.
```

## bin/admission-deny.sh, lines 602-605 (before this edit)

```text
The floor's TEETH alone (deny + mode locks). B6 blocks a session only on
this; plugin/marketplace drift is reported, never blocking, because those
are ordinary user state and a fail-closed gate over them locks the operator
out with no in-session escape (red-team pass 3).
```
