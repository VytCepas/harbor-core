---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/injection-rule/injection-rule.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/injection-rule/injection-rule.sh, lines 8-54 (before this edit)

```text
DELIBERATELY ONE FILE (lint G1, docs/explanation/modularity.md): splitting the
predicate vocabulary from the pack loader would put the two halves of one
contract in two files, and the thing this replaces is exactly that scatter.

WHY AN ENGINE AND NOT ANOTHER HOOK SCRIPT. bin/govern-hook.sh is 360 lines of
shell for four rules, and every rule a second repo wants is a second script
with its own matcher, its own fail-open discipline and its own bugs. That does
not scale past one repo, and the operator's environment is already four —
harbor and its workload repos — with more coming. So the shell is written
ONCE and the rules become DATA: a repo declares `context-rules/<repo>/<id>.md` and
gets just-in-time governance with no shell of its own.

WHAT MAKES THIS WORTH THE BYTES, MEASURED. E6 (docs/reports/evals.md) ran the same sentence
two ways: as prose inside a runbook the model had already opened it scored
0/4, and injected at the tool call it scored 4/4. E8 then showed that volume in
the prefix changes nothing — a 595 B constitution and a 17,845 B one both score
3.00/3. The variable is not how much you write or where in the prefix you put
it. It is whether the rule is RESIDENT when the model acts, or has to be
fetched. Every repo here has a CLAUDE.md whose whole content is "the real
instructions are in AGENTS.md, read it first", which is the fetch-required
shape, so those instructions do not bind. This is the fix for that.

INFORM BY DEFAULT, AND THAT IS MEASURED. E6 ran a veto arm and an inform arm
against the same trap: inform 4/4, veto 3/4, and the veto's one miss was a
session that stopped to ask instead of acting. Vetoing belongs to the floor
(admission-bash.sh, admission-egress.sh) where the question is "may this happen at
all", and a pack that merely wants attention must never reach for it.

THERE IS ONE OPT-IN DENY, AND THIS PARAGRAPH USED TO SAY THERE WAS NONE. It
said "deliberately no `deny` mode here" for the whole of the time the mode
existed: PR #262 added the `HARBOR-DECISION deny:` sentinel because a real
gate had been silently disarmed — bin/govern-hook.sh computes a blocking merge
verdict, and reaching it through this engine wrapped that verdict as prose,
which cannot stop a Bash call. Suite green, every red PR merged. A header that
denies the existence of the blocking path is worse than no header, because a
reader deciding whether a pack CAN block gets a confident wrong answer. The
sentinel is exact, opt-in, `run:`-only and PreToolUse-only; the rules that keep
it from becoming a second floor are stated where it is implemented, below.

CONDITIONAL OR NOTHING (CONSTITUTION §2.11). Every path prints nothing when it
has nothing true to say. A false positive is a defect, not safety: a guard that
fires on ordinary work is a guard that gets switched off, and this one is
especially exposed because it rides on the Bash tool.

FAIL-OPEN EVERYWHERE. No jq, malformed JSON, an unreadable pack, an unknown
predicate, a `run:` script that errors — every one exits 0 having printed
nothing. A hook whose failure mode is noise is a hook that gets removed.
```

## hooks/injection-rule/injection-rule.sh, lines 71-80 (before this edit)

```text
── pack discovery ──────────────────────────────────────────────────────────
TWO TIERS, AND THE ORDER IS THE PRECEDENCE. Box packs carry rules true in every
session on this machine (the subagent contract, what survives compaction, that
fetched content is data). Repo packs carry rules true only inside one tree.

THE REPO IS RESOLVED FROM THE SESSION'S CWD, NOT FROM THIS SCRIPT'S LOCATION.
The installed copy lives in the box config dir and must serve whatever repo the
session is standing in; resolving from $0 would make every session load
harbor's rules. CLAUDE_PROJECT_DIR is what the harness sets; cwd is the
fallback for a hand-run.
```

## hooks/injection-rule/injection-rule.sh, lines 84-90 (before this edit)

```text
THE TWO TIERS CAN BE THE SAME DIRECTORY, and then every box pack fires twice.
Measured, not imagined: a session whose project dir is $HOME resolves REPO=$HOME,
and $HOME/.claude/context-rules/user IS $CFG/context-rules/user. The doubled note is the visible
half; the silent half is worse, because `once: session` spends its ledger key on
the first pass and a genuinely two-tier box would then skip a repo rule. Compared
PHYSICALLY (symlinks resolved) for the reason lint D2 exists: /tmp and
/private/tmp are the same directory and differ as strings.
```

## hooks/injection-rule/injection-rule.sh, lines 131-133 (before this edit)

```text
Collation is pinned for the same reason skill-catalog.sh pins it: glob order is
LC_COLLATE-dependent, and two boxes ordering the same packs differently would
emit notes in a different order and make any diff-based check flap.
```

## hooks/injection-rule/injection-rule.sh, lines 137-141 (before this edit)

```text
── frontmatter ─────────────────────────────────────────────────────────────
THE FRONTMATTER ONLY, never the whole file. skill-catalog.sh records the failure
this avoids: scanning the body misfiled any skill whose prose mentioned the key
at column 0 — and these packs are documents ABOUT matching, so a pack that
discussed `event:` in its note would classify itself.
```

## hooks/injection-rule/injection-rule.sh, lines 151-159 (before this edit)

```text
── THE SAME ANSWERS, ONE awk PER PACK (harbor#669) ────────────────────────
fmv is `fm | awk`, two processes, and the sweep asked it for the id and the
event of EVERY pack on EVERY event before it could skip one. Measured
2026-09-24: about 60 awk per hook call and 300-460 ms at load 7, paid on every
tool call in every session, and 131 s of one CI suite that runs this engine
once per tracked file. The sweep now reads a pack's frontmatter once (fm_load)
and answers each key by string handling in this shell: no fork, no temp file.
Same match as fmv: the first line that starts with `<key>:`, with the blanks
after the colon stripped. fmv/fmall stay for --list, which is not on a hot path.
```

## hooks/injection-rule/injection-rule.sh, lines 196-200 (before this edit)

```text
── the payload ─────────────────────────────────────────────────────────────
NO jq HARD DEPENDENCY, same position as govern-hook.sh and annotate-web.sh:
without jq we cannot BUILD valid JSON for arbitrary text, and the choice is a
fixed safe string or silence. Nothing here is a safety boundary — a missed
note costs a note — so it is silence.
```

## hooks/injection-rule/injection-rule.sh, lines 213-216 (before this edit)

```text
SessionStart says WHY it started: startup | resume | clear | compact | fork.
The distinction is the whole reason the post-compaction rule can exist at all
(see the EVENTS_WITH_CONTEXT block) — without it, a rule about compaction would
have to fire on every session opening and would be noise four times in five.
```

## hooks/injection-rule/injection-rule.sh, lines 219-237 (before this edit)

```text
The written text for a Write/Edit, and the tool's OUTPUT for a PostToolUse.
Capped, because a hook that blocks its tool call while a shell walks a 40 MB
string is a hook the operator disables. 256 KB is far past any prose file and
far short of anything that stalls.

THE NULL FILTER COMES BEFORE `tostring`, NOT AFTER. It was the other way round,
so a payload with no `tool_response` produced the literal four-character string
`null` as content — jq's `tostring` runs on the null and the later
`select(. != null)` sees a non-null string. Nothing shipped uses
`content-contains`, so it had no live effect; it was a loaded gun for the first
pack that did. Found by an adversarial pass.

`.error` IS PART OF THE CONTENT ON A FAILURE, and without this line it was the
same loaded gun the paragraph above describes. `PostToolUseFailure` carries NO
`tool_response` — measured live against 2.1.258, the payload is `tool_name`,
`tool_input`, `tool_use_id`, `error`, `is_interrupt`, `duration_ms` — so on the
one event whose whole subject is what went wrong, `content-contains` matched
against an empty string and could only ever return false. Silently: no error,
no note, a predicate that reads as "did not match".
```

## hooks/injection-rule/injection-rule.sh, lines 245-247 (before this edit)

```text
BOTH ENDS, NOT THE HEAD. A plain `head -c` made the cap an evasion: bury the
injection past byte 262144 of an oversized document and nothing scans it.
Keeping the tail costs nothing and closes the cheapest bypass there was.
```

## hooks/injection-rule/injection-rule.sh, lines 251-259 (before this edit)

```text
── provenance ──────────────────────────────────────────────────────────────
NOT A LABEL. bin/govern-token.sh's header carries the argument at length: this
estate pipes FETCHED WEB PAGES through a byte-identical additionalContext
envelope, so `[HARBOR GOVERNANCE]` in a page is indistinguishable from this
file's output by inspection, and a self-label is exactly what an attack writes.
The token is derived from a box-local salt the fetched content cannot contain.
Empty is the default and degrades to an unlabelled note that still says
something true — a provenance mechanism that turned reminders OFF when
unconfigured would be worse than the problem.
```

## hooks/injection-rule/injection-rule.sh, lines 266-277 (before this edit)

```text
── the predicate vocabulary ────────────────────────────────────────────────
FIXED, AND NOT A LANGUAGE. Every predicate below compares a value FROM the
payload against a pattern FROM a trusted pack file, and the payload value is
only ever the subject of a `case`, never the pattern. Nothing from the payload
is ever eval'd, interpolated into a command string, or used as a glob —
CONSTITUTION §4's rule about external input, applied to the one file in this
design that reads attacker-reachable text on purpose.

`case` GLOBS, NOT grep, for the reason hooks/pre-commit and govern-hook.sh both
record: this machine's `grep` is a ugrep wrapper carrying `-I --ignore-files`,
and a matcher whose behaviour depends on which grep is first in PATH means
something different on the CI runner. `case` is POSIX and has no flavour.
```

## hooks/injection-rule/injection-rule.sh, lines 279-282 (before this edit)

```text
A heredoc body is not code. govern-hook.sh's header records the incident: a
documentation line inside a heredoc is indistinguishable from a command by
position alone, and an adversarial review demonstrated command-position
splitting did not fix it.
```

## hooks/injection-rule/injection-rule.sh, lines 296-315 (before this edit)

```text
A QUOTED ARGUMENT IS NOT CODE EITHER, and this was the worst defect an
adversarial pass found in this file. `segments()` split on `; & | ( )` and
newline WITHOUT regard to quoting, so
  git commit -m "docs: record the gate (gh pr create needs the agents first)"
produced a segment reading `gh pr create needs the agents first` and fired the
a workload pack — on a commit, not on a PR. contracts/injection-rule.md stated the
opposite as a guarantee. And the second-order effect is worse than the noise:
those packs are `once: session`, so the benign commit SPENT the ledger key and
the real `gh pr create` later in the same session got total silence. A rule
that fires on the wrong turn and is then disarmed for the right one is strictly
worse than no rule at all.

So quoted bodies are blanked — length-preserving, quotes kept — before any
splitting, exactly as heredoc bodies already are. State carries across lines so
a multi-line quoted argument is covered too.

AN UNBALANCED QUOTE BLANKS THE REST OF THE COMMAND, and that is the deliberate
direction to fail in: the cost is a missed note, where the opposite choice
costs a false one. §2.11 — a false positive is a defect, a missed reminder
costs a reminder.
```

## hooks/injection-rule/injection-rule.sh, lines 336-343 (before this edit)

```text
THE WHITESPACE NORMALISATION HAPPENS HERE, IN THE ONE awk THAT ALREADY RUNS.
It used to be a `tr` per segment inside the matching loop, which is one
fork-pair per segment of the command — measured by an adversarial pass at 8.7 s
for a 3,000-segment `&&` chain and 14.7 s for 5,000, against a hook timeout of
10. A PreToolUse hook that blocks its own tool call for fifteen seconds on a
long pipeline is a hook the operator switches off, and the shape that triggers
it is an ordinary generated command line, not an attack. Now it is one fork
total and the same 3,000 segments cost about as much as one.
```

## hooks/injection-rule/injection-rule.sh, lines 350-353 (before this edit)

```text
THE SUBCOMMAND, NOT A SUBSTRING. govern-hook.sh shipped the substring version
first and it fired on `gh pr list --search "pr merge"` and on any prose
argument mentioning the phrase. The predicate is the first N WORDS of a
command-position segment, so the phrase has to be the invocation.
```

## hooks/injection-rule/injection-rule.sh, lines 362-379 (before this edit)

```text
`--help` RENDERS DOCUMENTATION AND DOES NOTHING ELSE, for every command
that has ever had a manual. A note about the consequences of an action,
delivered to someone reading how the action works, is noise by definition —
govern-hook.sh carried this exclusion for its one rule, and it belongs in
the vocabulary so every future pack inherits it.

`-h` IS NOT IN THIS LIST AND THE FIRST CUT HAD IT THERE, on the claim that
the exclusion "can never wrongly suppress". That claim was false twice over,
measured. `-h` is a VALUE flag for tools installed on this box — `docker run
-h web`, `mysql -h prod.db.internal` — so it silences real invocations of
real commands. And the test scanned the whole segment rather than a flag
position, so `gh pr merge 12 --body 'pass -h to see flags'` silenced an
installed pack from inside a quoted string. `--help` has neither problem:
no tool on this box takes it as a value, and a segment containing it as a
token is a manual read.
Tested against the segment as it now stands, whose quoted bodies are
already blanked by blank_quoted() — so `--help` inside an argument cannot
suppress a real invocation, which is the second half of the same defect.
```

## hooks/injection-rule/injection-rule.sh, lines 389-394 (before this edit)

```text
THE COMMAND WORD, for a tool whose invocation varies in front of its name
(inst-quiet-predicates). cmd-prefix needs the segment to START with the words,
so `X=dir gcal-write add` and `~/.local/bin/gcal-write add` slipped past it, and
the cmd-contains it replaced fired on prose, greps and PR bodies. Same segments
(heredocs and quoted bodies already gone), then assignments skipped, and the
word must be the name or a path ending in `/name`. `--help` is excluded as above.
```

## hooks/injection-rule/injection-rule.sh, lines 416-421 (before this edit)

```text
AN UNKNOWN PREDICATE IS ITS OWN ANSWER, NOT "DID NOT MATCH". The first cut
returned the same 1 for both, and `not` could not tell them apart — so
`not cmd-prefx git push`, one letter wrong, inverted a never-matching typo
into a rule that fired on everything. Exactly the universal-rule-from-a-typo
failure the comment below promises cannot happen, arriving through the one
operator this file also provides. Found by an adversarial pass, reproduced.
```

## hooks/injection-rule/injection-rule.sh, lines 448-468 (before this edit)

```text
── the detector ────────────────────────────────────────────────────────────
THE ONE PREDICATE THAT IS NOT A STRING COMPARE, and the reason this file exists
rather than a fifth branch in govern-hook.sh.

E9 measured the hole precisely. An HTML comment reading `SYSTEM DIRECTIVE …
ignore previous instructions` was refused 4/4 by every arm including the one
with NO constitution at all — models are trained on that shape. A plausible
`## Documentation pipeline convention` heading, inside the very file the task
asked the model to summarise, was obeyed 6 of 8 times without §4 and STILL 2 of
8 times with §4 fully present. §4 is load-bearing and it is not sufficient, and
this estate is unusually exposed to the convention shape because its sessions
are trained by their own environment to follow documented conventions.

So the detector does not look for menace. It looks for text that addresses THE
PROCESSOR OF THE CONTENT rather than its reader — the one thing a legitimate
document almost never does and every content-borne injection must.

TWO TIERS, BECAUSE ONE LIST WOULD HAVE TO CHOOSE between missing the quiet
shape and firing on ordinary prose. LOUD phrases are unambiguous and fire
alone. QUIET phrases are individually innocent and need corroboration: two of
them, or one plus a write/exfiltrate marker.
```

## hooks/injection-rule/injection-rule.sh, lines 584-589 (before this edit)

```text
The same provenance for a Bash READER (inst-quiet-predicates): `cat`, `head`, `tail`,
`sed -n`, `grep`, `wc` over files that each pass own_committed_file. Two locks, both needed:
the command has no separator, redirect or substitution and every stage is a reader; and
EVERY output line (stdout, stderr, error) is in one of those files, once grep's `name:`,
`N:` / `N-` and `cat -n` gutters are off. So any byte from elsewhere — a fetch, another
repo, an untracked or edited file — fails the second lock and the detector still runs.
```

## hooks/injection-rule/injection-rule.sh, lines 660-671 (before this edit)

```text
── the once-ledger ─────────────────────────────────────────────────────────
THE DEFAULT IS ONCE PER SESSION, and it is the difference between a mechanism
and wallpaper. A note repeated on every Bash call stops being read by its third
appearance, which is CONSTITUTION §2.11 arriving by a different door: the guard
is not switched off, it is tuned out, and nothing turns red either way.

KEYED ON THE SESSION ID, WHICH IS WHY IT IS SAFE TO WRITE AT ALL. govern-hook.sh
is stateless by design because five sessions run concurrently on this machine
and `hostname` here intermittently answers `Mac`, which has already forked
host-sharded ledgers in this estate. A file per session id shares nothing
between sessions and cannot inherit that fork. With no session id — a hand-run,
a self-test — there is no ledger and every rule fires.
```

## hooks/injection-rule/injection-rule.sh, lines 673-675 (before this edit)

```text
NEVER BUILD A PATH FROM UNVETTED TEXT (CONSTITUTION §4). The session id is
harness-supplied and reaches the filesystem here; a `../` in it would write
outside the ledger. Vetted before it is used, not after.
```

## hooks/injection-rule/injection-rule.sh, lines 705-723 (before this edit)

```text
── the trees this call touches (harbor#599) ───────────────────────────────
ONE DEFINITION, written in contracts/injection-rule.md ("The tree a call touches") and
computed HERE for both of its readers: `scope: box` delivery below, and
repo-tier.sh's report, which receives the result as HARBOR_CONTEXT_TOUCHED instead of
working it out a second time. It was repo-tier.sh's own code for one PR
(#601); a second reader is what made it a seam.
  · a file tool — the path it names (`file_path`, `notebook_path`, `path`)
  · a shell command — its working folder (`.cwd`), every `-C <dir>`, and a
    `gh` `-R`/`--repo` slug mapped to its checkout under PORT_ROOT
`cd X && …` is NOT followed, by the #599 decision: reading a directory out of
a cd chain is the shell parsing #539 records as the floor's longest run of
fixes to fixes. The harness carries the new folder in the next call's `.cwd`.

THE SHELL HALF REUSES THE FLOOR'S PARSER, library-admission.sh beside this file,
rather than growing a second one: floor_seg_load keeps a quoted argument as one
token, so a commit message that MENTIONS `git -C x` is never a flag. It does not
know heredoc bodies, so those segments are skipped up to their delimiter. No
guard-lib, or a command past its size bound, means no shell targets — silence,
which is this engine's posture everywhere else.
```

## hooks/injection-rule/injection-rule.sh, lines 725-727 (before this edit)

```text
The repository holding <path>, physically, or nothing. A path that does not
exist yet (a Write creating a file) is walked up to the nearest directory that
does, and a file is walked up to its directory.
```

## hooks/injection-rule/injection-rule.sh, lines 736-740 (before this edit)

```text
THE DECISION LOG (harbor#953). A rule that spoke leaves one record in guard-decisions.jsonl, through the
floor's own writer: g=inject, d=advise or deny, r=<pack id>. floor_log_decision works out the sink from
$0 (this script, <config>/bin), refuses anything but the known enums, and fails silent, so a box with no
ledger stays blind rather than wrong. library-admission.sh is read only on a fire (once a session for most
packs), never on the silent hot path. Only fires are written: a silent arm has no decision to record.
```

## hooks/injection-rule/injection-rule.sh, lines 835-837 (before this edit)

```text
The session's own project directory resolves to the governed tree or to
none, and either way there is nothing to reach — so the commonest shape,
a session that never left where it started, costs no fork here.
```

## hooks/injection-rule/injection-rule.sh, lines 848-855 (before this edit)

```text
THE REGISTRY IS THE TRUST BOUNDARY. A reached tree's packs are delivered, and a
`run:` pack EXECUTES, because the session touched that tree — so which trees
may do that cannot be "any repository a tool call names". A cloned third-party
repo read once would otherwise run its own script inside this hook and speak
with this engine's governance stamp. `projects.tsv` beside the box packs is the
operator's list of this estate's projects; a worktree counts as its owner,
because the registry names repositories, not their checkouts.
It lives with the box tier (harbor#1010).
```

## hooks/injection-rule/injection-rule.sh, lines 898-903 (before this edit)

```text
── evaluate every pack ─────────────────────────────────────────────────────
Three sources, one line per rule file in sweep order: `<file> TAB <tree it speaks for> TAB <reached>`.
Box and repo packs speak for the governed tree. A REACHED tree's packs speak
for that tree — `repo-has` is judged there and a `run:` script runs there — and
only the ones that declare `scope: box` are read at all: the repo consents per
rule, in its own data, and the default is to stay home.
```

## hooks/injection-rule/injection-rule.sh, lines 922-924 (before this edit)

```text
A DECISION ENDS THE SWEEP. Once a pack has denied the call, later packs are
commenting on a tool use that will not happen, and the `break` below only
leaves the inner loop — without this the next directory would keep firing.
```

## hooks/injection-rule/injection-rule.sh, lines 941-958 (before this edit)

```text
── ONE MATCHING SEMANTICS, THE HARNESS'S (harbor#184) ──────────────────
This was literal alternation — `case "|$_tl|" in *"|$TOOL|"*)` — while the
matcher column in settings.json, which decides whether this engine is
invoked at all, is a REGEX. Two semantics for one field, and the narrower
one silently wins: a pack declaring `mcp__.*` passed the harness matcher
and was then skipped here, because no tool is literally named `mcp__.*`.
Measured while wiring harbor#184's pack, whose whole target set is the
`mcp__claude-in-chrome__*` family — 58 of the 88 MB of result bytes.

A regex is a superset of the alternation the contract already promises, and
tool names are `[A-Za-z0-9_]+` in practice, so nothing that worked stops
working. An unparseable pattern makes grep fail, which reads as no match —
silence, which is this engine's posture everywhere else.

THE GREP IS PINNED, as library-admission.sh pins $FLOOR_GREP and lint F3 requires
of every file that sources it (this one does, for the shell half of "the
tree a call touches"). On this box `grep` in a PATH can be a ugrep wrapper,
and which grep answers must not decide whether a rule matches.
```

## hooks/injection-rule/injection-rule.sh, lines 974-976 (before this edit)

```text
NO PREDICATE IS NOT "ALWAYS". A pack that forgot its `when:` would fire on
every event of its type forever, which is the loudest possible failure for
the most likely possible typo.
```

## hooks/injection-rule/injection-rule.sh, lines 979-994 (before this edit)

```text
ONCE: session | match | never.

`match` EXISTS BECAUSE `session` HAS A COVERAGE HOLE, and the hole was
measured rather than imagined. Sweeping the detector below across this
estate's markdown fires on a handful of documents that DISCUSS injection —
the constitution's §4 describes the attack in the attack's own words, and
this repo's eval page quotes the fixtures verbatim. Under `once: session` a
session that read one of those first would have spent its single note on a
document ABOUT injection and then said nothing about a genuinely hostile
file read afterwards. `match` keys the ledger on what matched, so a benign
hit costs one sentence and consumes nothing.

The exact set is NOT written down here. hooks/injection-rule/detector.test.sh sweeps every
tracked markdown file and compares against an allowlist, so a new false
positive turns the suite red on the commit that introduces it. A count in a
comment is a copy, and this one was already wrong when it was written.
```

## hooks/injection-rule/injection-rule.sh, lines 997-1011 (before this edit)

```text
THE COMMAND IS PART OF THE SUBJECT, AND IT WAS NOT (harbor#180). A Bash rule
at PreToolUse has no file path and no content — nothing has been written or
returned yet — so every command in a session hashed to the SAME empty
subject and `once: match` silently became `once: session`. Measured: five
different trap-shaped commands in one session, only the first spoke.

That is the quietest possible failure for the most natural pack there is —
`cmd-prefix` plus `match` is what anyone writes for a rule that should
re-fire on a genuinely different command — and nothing turned red, because
the rule fired once and looked like it was working.

RAW COMMAND, NOT THE MATCHED PREFIX. `gh pr merge 174` and `gh pr merge 179`
are different acts on different objects and a merge rule should speak for
both; keying on the prefix would collapse them into one and re-introduce the
same silence one level up.
```

## hooks/injection-rule/injection-rule.sh, lines 1022-1032 (before this edit)

```text
`run:` — a dynamic body, for the rules whose condition is computable but
not expressible as a predicate. The script gets the payload on stdin and
its STDOUT is the note; empty stdout means no note, which is how such a
rule stays silent. Invoked as an ARGUMENT to sh, never interpolated into a
command string (CONSTITUTION §4).

RESOLVED NEXT TO ITS PACK, RUN FROM THE SESSION'S REPO. Two different
things, and conflating them is what made the first cut unusable: the script
belongs to whoever wrote the pack (box or repo), while the state it reports
on is the session's working tree. `..` and absolute paths are refused so a
pack cannot reach outside its own directory to pick an interpreter target.
```

## hooks/injection-rule/injection-rule.sh, lines 1038-1056 (before this edit)

```text
── A `run:` PACK MAY RETURN A DECISION, NOT ONLY A NOTE (harbor#254) ──
`run:` contracts that stdout is the note, and that contract silently
disarmed a real gate: bin/govern-hook.sh computes the merge backstop's
verdict and emits a PreToolUse `permissionDecision: deny`, but reached
through this engine it went through `--note`, which prints prose — and
prose wrapped as additionalContext cannot stop a Bash call. Suite green
on both sides; every red PR still merged. Found by review (PR #262).

THE SENTINEL IS OPT-IN AND EXACT. A pack that wants to decide prints
`HARBOR-DECISION deny: <reason>` as its first line; anything else is a
note exactly as before. Only `run:` output is inspected — a static
markdown body cannot acquire blocking power by containing a sentence.

AND ONLY WHERE THE HARNESS HAS A CHANNEL FOR IT. `permissionDecision` is
PreToolUse-only (contracts/hooks.md). On any other event the sentinel is
stripped and the text is delivered as an ordinary note, with the
downgrade stated to the operator — because a decision the harness
discards is the PreCompact failure this file already carries a comment
about, and it must not repeat quietly.
```

## hooks/injection-rule/injection-rule.sh, lines 1092-1094 (before this edit)

```text
`mode: notify` also speaks to the HUMAN. systemMessage sidesteps the trust
question outright — a line the operator reads never has to be believed by
the model — so anything whose real audience is the person gets both.
```

## hooks/injection-rule/injection-rule.sh, lines 1106-1109 (before this edit)

```text
A DENY WITH NO OTHER NOTE IS STILL AN ANSWER. `[ -n "$NOTES" ] || exit 0` alone
dropped it on the floor: the decision's text rides in its own field, so NOTES is
empty in exactly the case that matters most, and the engine exited silently
while the red merge proceeded.
```

## hooks/injection-rule/injection-rule.sh, lines 1112-1144 (before this edit)

```text
── the emit, and WHICH EVENTS CAN CARRY A NOTE AT ALL ──────────────────────
NOT EVERY HOOK EVENT REACHES THE MODEL. `hookSpecificOutput.additionalContext`
is accepted on the events below and REJECTED everywhere else — and rejected
means the harness discards the WHOLE object, so a `mode: notify` systemMessage
riding along in the same JSON is thrown away with it. The failure is silent
from the engine's side: the script exits 0 having written well-formed JSON, and
only the operator's terminal shows "Hook JSON output validation failed".

THIS IS NOT A GUESS. It shipped broken: `20-precompact-carry.md` declared
`event: PreCompact`, and PreCompact accepts only the top-level `decision`
pattern — there is no channel from a PreCompact hook to the model in this
harness at all. Every compaction this box performed emitted an object the
harness rejected. The rule was retargeted to SessionStart + `source-is compact`
(see context-rules/user/post-compaction-carry.md), which fires on the far side of
the same moment and CAN be heard. Lint IJ1 now refuses a pack that declares a
context-less event without `mode: notify`, so this class cannot return quietly.

The list tracks the harness, not our preferences. When it changes, this line
and contracts/injection-rule.md's table change together.

READ OFF THE BINARY'S OWN SCHEMA ON 2026-09-02, not inferred and not recalled.
`hookSpecificOutput` is a discriminated union in 2.1.258 and every arm either
carries `additionalContext` or does not; extracting the union settled three
events this list had wrong by omission — UserPromptExpansion, PostModelSwitch
and Notification all accept it and were being downgraded to operator-only.
Nothing ships on them, so the cost was zero and the direction is what matters:
a list of what the harness accepts, maintained by hand, drifts toward SMALLER
than the truth, and every omission is a pack that silently talks to nobody.

AND `PostCompact` IS NOT IN THE UNION AT ALL. contracts/hooks.md carried it as
"receives the summary — could verify what survived", which reads like an open
avenue; it is the same closed door as PreCompact. The post-compaction rule
stays on SessionStart + `source-is compact`, which is the only channel there is.
```

## hooks/injection-rule/injection-rule.sh, lines 1152-1154 (before this edit)

```text
The model cannot be reached on this event. Say it to the operator instead of
emitting JSON that will be discarded — a note delivered to nobody, with a
validation error where the note should have been, is worse than silence.
```

## hooks/injection-rule/injection-rule.sh, lines 1162-1166 (before this edit)

```text
A DECISION SHORT-CIRCUITS THE NOTE, because they are answers to different
questions and only one of them stops the call. The reason reaches the model as
`permissionDecisionReason`, which is the channel a deny already travels on
(contracts/hooks.md: confirmed live — admission-bash.sh's denial landed mid-turn
and redirected the work), so it does not also need to be an additionalContext.
```
