---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/context-budget.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/context-budget.sh, lines 16-32 (before this edit)

```text
THE VERDICT IS A RECORDED PRIOR MEASUREMENT, NOT A CEILING (harbor#183). The
24,000 B ceiling was the gate for a year and its own definition called itself
"a round, arguable number rather than a derived one"; #183 measured the three
things it could have protected — capacity, cost, dilution — and found none of
them. Regrowth is the real concern, and regrowth needs a prior number.

Upstream's words: "backpressure against always-on context re-accretion. Without
a ceiling those files regrow: memory proposals auto-append, ISAs accrete, rules
stack."

Harbor is about to do exactly that. C1 puts policy/constitution.md into
~/.claude/CLAUDE.md, L2 (harbor#43) adds TELOS + IDENTITY, D adds memory
injection — all always-on, none of them bounded by anything. Upstream hit this
wall and built a ceiling; Harbor had not noticed the wall existed.

Every byte here is spent before the user's first word, in every session,
forever. That is the most expensive kind of byte in the system.
```

## bin/context-budget.sh, lines 35-41 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/context-budget.sh, lines 67-72 (before this edit)

```text
THE BASELINE, AND WHY IT IS A FILE AND NOT A NUMBER IN THIS SCRIPT (harbor#183).
A recorded prior measurement is the one denominator that is not invented. It
lives in the repo so that growth is a DIFF with a reason in the commit message —
which is what "backpressure against re-accretion" actually needs, and what a
constant in a variable can never give.

```

## bin/context-budget.sh, lines 73-75 (before this edit)

```text
WHERE IT LIVES (harbor#1275, harbor#1149): the user's state directory, never the checkout. A harbor-core clone has no
registries/context-baseline.tsv, and a file written at its root is one `git add -A` away from a PR. An in-tree file is only a SEED:
read while the state file is absent, and copied there before the first --record, so nothing is ever written into the tree.
```

## bin/context-budget.sh, lines 83-110 (before this edit)

```text
Ceiling in bytes. NO LONGER THE VERDICT (harbor#183), AND SINCE 2026-09-20 NO
LONGER ANOTHER TOOL'S BASIS EITHER (harbor#316). It used to govern exactly one
thing — memory-store-check.sh's index allowance, `ceiling - (spent - index)` — and that
coupling is now cut: store-check derives its bound from the index's own pointer
count. What this number still does is set the percentage and the OVER/headroom
line THIS tool prints, and nothing else in the repo reads it.

SO ITS HONEST STATUS IS "A RECORDED PRIOR MEASUREMENT WITH A CONSUMER OF ONE",
and that is worth stating rather than leaving a 40,000 that reads like a bound
somebody chose. Its own first comment admitted the problem: "deliberately a
round, arguable number rather than a derived one". The backpressure that
actually works is `--check` against registries/context-baseline.tsv, which is a diff with a
reason in a commit; this constant is the legacy headline beside it.

THE ARITHMETIC BEHIND 40,000, KEPT BECAUSE IT IS WHERE 150 CAME FROM. On
2026-08-28 the non-index always-on surface measured 19,381 B (constitution plus
ambient descriptions) and the index was a routing table of one pointer per note,
133 notes at a 139 B mean. Allowing 150 B a pointer gives 19,950 B plus ~600 B
of section structure: 19,381 + 20,550 = 39,931, taken to 40,000. memory-store-check.sh
now applies that 150-and-600 directly to the file it was always about, which is
why this paragraph stays here as the provenance of those two numbers.

AND #316 SHOWED WHY THE OLD COUPLING HAD TO GO, rather than the ceiling being
re-guessed again: counting the plugin, command and injection surfaces added
19,494 B that every session was already paying, the derived allowance fell from
9,477 B to 799 B, and store-check began demanding a five-pointer index. Nothing
about the memory store had changed. A bound that moves because a different
surface was measured more honestly is pointed at the wrong thing.
```

## bin/context-budget.sh, lines 115-124 (before this edit)

```text
THE WHOLE `description:` VALUE, NOT ITS FIRST LINE. The harness lists the
description its author wrote, and YAML lets that be a block scalar running over
many lines. Reading only the first line undercounts exactly the expensive case:
`pr-review-toolkit`'s `code-simplifier` carries three worked `<example>`
transcripts under `description:`, which a first-line read prices at 14 B against
a true 2,348. NO SKILL ON THIS BOX USES THE BLOCK FORM TODAY — measured
2026-09-20, first-line and full-value totals are both 7,991 B — so this changes
no number that was ever reported and removes the trap for the next author who
writes one. It is shared with the plugin-agent row below, where the block form
is already in use, so the two surfaces cannot be measured by two rules.
```

## bin/context-budget.sh, lines 134-143 (before this edit)

```text
── THE DEPLOY RATCHET (--ratchet) ──────────────────────────────────────────
A ratchet, not a cliff: refuses only GROWTH past the number in registries/context-ratchet.tsv, which is checked in, so a deliberate
raise is a one-line edit whose commit says why. WHAT IT COVERS IS WHAT THIS CHECKOUT CONTROLS AND NOTHING ELSE:
policy/constitution.md (what deploy installs as CLAUDE.md, so the NEW text is measured, not last deploy's) plus the descriptions of
the ambient skills in skills/ and vendor/skills/. It reads nothing from ~/.claude, so the answer is a pure function of the
tree: the same on CI and on the box, and a deploy cannot go red because of something it did not write.
LEFT OUT ON PURPOSE (CONSTITUTION §2.11, a false positive gets the guard switched off): the per-project memory index is
model-authored and changes between sessions, so a deploy-time gate on it would fire on ordinary work (memory-store-check.sh
bounds it); plugin and slash-command descriptions are installed by the operator, not by deploy; the SessionStart
injection moves by ~10 KB with the caller's directory and with the live packs. All three stay in the report above.
```

## bin/context-budget.sh, lines 179-181 (before this edit)

```text
A CHECK THAT PRINTS A TABLE IS A CHECK NOBODY READS IN CI. The rows are emitted
as the measurement runs, so --check and --record keep fd 3 for their one line
and send the report to /dev/null rather than buffering it.
```

## bin/context-budget.sh, lines 194-194 (before this edit)

```text
── the root constitution ───────────────────────────────────────────────────
```

## bin/context-budget.sh, lines 201-204 (before this edit)

```text
── ambient skill descriptions ──────────────────────────────────────────────
Only AMBIENT skills cost per-session: the harness lists their description so
the model can match on it. `disable-model-invocation: true` keeps a skill out
of that listing entirely, which is why I1-ext put seven skills in that tier.
```

## bin/context-budget.sh, lines 218-236 (before this edit)

```text
── plugin agent and command descriptions (harbor#316) ──────────────────────
THE MOST EXPENSIVE ALWAYS-ON ROWS ON THIS BOX WERE ON A SURFACE THIS FILE DID
NOT NAME. Before 2026-09-20 there was no occurrence of `plugin`, `agent`,
`command` or `mcp` anywhere in this script — an undeclared blind spot, not a
declared exclusion, which is the distinction that matters when a reader is
deciding whether a missing number means "zero" or "never looked".

A subagent's `description:` is listed in EVERY session's prefix so the model can
match a task to it, exactly like an ambient skill's. Measured 2026-09-20:
`pr-review-toolkit` charges 6,360 B a session for six roles with TEN all-time
invocations, four of them fired once each on one day. Five of the six are more
expensive per use than any ambient skill on the box.

RESOLVED FROM `installed_plugins.json`, NEVER BY GLOBBING THE CACHE. The cache
holds 17 version directories for this one plugin and the harness de-duplicates
to one; a glob would charge the prefix four to seventeen times over and the row
would be the loudest wrong number in the report. The register says which path is
installed, and only `scope: user` entries are charged — a `scope: project` entry
is another repo's session, not this one's.
```

## bin/context-budget.sh, lines 240-244 (before this edit)

```text
`tr ',' '\n'` FIRST, so the parse does not depend on the writer's formatting.
The harness pretty-prints this file today and a line-based awk read it fine —
until the suite handed it the same JSON on one line and the row silently
reported 0, which is a wrong number wearing the costume of an absent surface.
Splitting on commas makes every `"key": "value"` its own record either way.
```

## bin/context-budget.sh, lines 260-263 (before this edit)

```text
── local slash-command descriptions ────────────────────────────────────────
Same listing, same prefix, authored here rather than vendored. Small today
(556 B over five commands, 2026-09-20) and counted because the reason it is
small is that nobody has written many, which is not a property of the surface.
```

## bin/context-budget.sh, lines 273-304 (before this edit)

```text
── the cwd-keyed auto-memory index ─────────────────────────────────────────
THE LARGEST ALWAYS-ON ITEM WAS THE ONE THIS TOOL DID NOT MEASURE. Until now
the file had zero references to projects/*/memory, so it reported 22,035 B —
91% of ceiling with headroom — while the true figure was 32,506 B, 135% and
over. A ceiling that undercounts by 10 KB is not a loose ceiling, it is a
ceiling pointed at the wrong surface, and every decision priced off it (which
skills to trim, whether a hook's per-fire cost beats CLAUDE.md's one-time
cost) was priced against a number that was wrong by more than the entire
ambient skill surface.

MEASURED, NOT ASSUMED. The claim "this loads in every session" is behavioural
and was verified behaviourally: on 2026-08-07 a session whose cwd was
~/harbor-unify carried the ~/.claude/projects/-Users-someone/ index in its
own prefix, delivered as `user's auto-memory, persists across conversations`.
That is one observation of the harness doing it, not a reading of a doc.

THE KEY IS THE CWD PATH WITH `/` → `-`, AND THERE IS NO WALK-UP. The first cut
climbed to the nearest ancestor with a store, on the strength of an observation
that turned out to be a misreading: a session "whose cwd was ~/harbor-unify"
carried the `-Users-someone` index, but that session's working directory was
`$HOME` — a DIRECT slug hit, needing no climb. The walk was invented to explain
something that never happened.

FALSIFIED BEHAVIOURALLY, which is the only way this could have been settled. A
real session started in a workload repo was asked whether it carried an auto-memory index
and answered ABSENT, listing exactly what it did carry. Meanwhile this tool,
walking up, was charging that session 10,908 B for a file it never loads. The
walk made the budget OVERCOUNT by the largest single item on the box, in every
repo — the mirror image of the undercount it was added to fix.

So: direct slug match only, and the resolved path is PRINTED rather than
summarised, because that is what makes this row falsifiable at a glance.
```

## bin/context-budget.sh, lines 314-339 (before this edit)

```text
── THE WORST CASE, NOT THE LOCAL ONE (harbor#243) ──────────────────────────
The row above is honest and the verdict built on it was not. The index is
cwd-keyed with NO WALK-UP, so a session started in a repo that has no store is
charged nothing for one — and lint X3 runs where CI runs, inside this checkout.
It therefore measured the CHEAPEST POSSIBLE SESSION and reported a reassuring
percentage about it: 91% with headroom from ~/harbor, 186% and over from $HOME,
same tool, same minute. That is a check that passes because it looks in the
place where the condition cannot occur, and it contradicted harbor#183 — the
ticket whose whole subject is the overage — while looking more authoritative
than the ticket, because it is automated and the ticket is prose.

So the VERDICT is the worst case: the largest store on the box, whichever cwd
owns it, because that is a session someone actually starts. The local row stays
because it is the true answer to "what does THIS session cost". `SPENT EVERY
SESSION` keeps its exact shape, and its last reader went away in harbor#316 —
memory-store-check.sh no longer parses it — so the shape is now held by this tool's own
suite rather than by a consumer. Kept deliberately: it is a stable line other
things have been built on before and the suite is where that promise now lives.

BOUNDED ON PURPOSE: the scan covers the memory index only, not the repo-scoped
surfaces below. A store is named by a SLUG (`/` -> `-`) and the mapping does not
invert — `-Users-someone-harbor-ci` is `~/harbor-ci` or `~/harbor/ci` and
nothing here can tell which — so charging a decoded cwd's CLAUDE.md would be a
guess. The worst case is therefore a LOWER bound on the worst case, which is the
right direction for a ceiling to be wrong in, and it is said here rather than
discovered later.
```

## bin/context-budget.sh, lines 354-371 (before this edit)

```text
── repo-scoped surfaces, which DO load and were never counted ──────────────
`.claude/rules/*.md` every one of the 19 on this box declares
`alwaysApply: false` with a `globs:` predicate, and a review reading that
frontmatter concluded they cost nothing. They cost 6,450 B in one workload repo. Measured
the only way that settles it: a fresh headless session started in that repo, asked
with no file reads whether the rules were present, quoted BOTH of them
verbatim and then listed all three by name.

So the frontmatter is inert here — a file that declares itself conditional
loads unconditionally. Documentation refutes documentation; only measurement
refutes behaviour, and the flag is documentation about behaviour.

Repo `CLAUDE.md` is in the same position: injected in that session.
AN `@path` IMPORT IS COUNTED (harbor#1010 PR 2, #1013, D-72). It was left out while "whether the harness
reads it" was unmeasured. Measured 2026-10-28, ONE billed headless session (`claude -p`, no tools, a fixture
dir whose CLAUDE.md holds a bare `@AGENTS.md` and whose AGENTS.md holds one unguessable token): asked with no
file read whether AGENTS.md was in its context, it quoted the token verbatim. The import loads, so it is charged.
Only a bare line `@<relative path>` of the repo's own CLAUDE.md is followed, one level, a file once.
```

## bin/context-budget.sh, lines 387-413 (before this edit)

```text
── the SessionStart injection (harbor#316) ─────────────────────────────────
THE TOOL'S OWN HEADLINE IS "what this session costs before the first word", and
the injection is delivered into the prefix before the first word — as
`attachment.type=hook_additional_context` on a transcript's record 9. It was
never counted. #316 put the omission at 11,389 B.

ASK THE INJECTOR, DO NOT RE-IMPLEMENT ITS DISPATCH. Which packs fire for
SessionStart is decided by frontmatter predicates in inject-hook.sh, and a
second copy of that logic here would be a copy that drifts while reading
correctly — the thing docs/explanation/doc-truth.md is about. So this feeds the engine a
real SessionStart payload and measures what comes back: same path the session
takes, which is CONSTITUTION §2.6. The probe writes nothing on a box whose
governance salt already exists, and creates only that salt on one that has not
run a session yet.

AND THE ANSWER DEPENDS ON THE DIRECTORY, BY SEVEN TIMES. Measured 2026-09-20:

    $HOME                      11,804 B      ~/harbor      1,660 B
    ~/Deliverables/<a folder>   2,172 B      ~/<repo>      1,666 B

`context-rules/user/repo-skills.sh` emits 9,682 B at home and ZERO inside a governed repo.
So the largest single injected item on the box — the index to the 38 skills the
model cannot see — reaches only sessions started outside a repo, which is the
opposite of where the memory index lands, and both are invisible to a reader of
the old report. The local row is what THIS session pays; the verdict takes the
worst case, for the reason harbor#243 gives about the memory index: lint X3 runs
from inside this checkout, which is the cheapest directory on the box.
```

## bin/context-budget.sh, lines 418-424 (before this edit)

```text
`CLAUDE_CONFIG_DIR="$CFG"` IS LOAD-BEARING, NOT TIDINESS. inject-hook.sh reads
its packs from that variable, so without it the probe measures the LIVE box
from inside a fixture — which is how this first shipped and how the suite
caught it: two under-ceiling cases went OVER because a synthetic config dir
was charged ~/.claude's 11 KB of packs. It is also what makes the shadow-dir
method work, the one that measures a proposed demotion without a single write
to the live instruction surface.
```

## bin/context-budget.sh, lines 429-444 (before this edit)

```text
ONLY FOR THE LIVE CONFIG DIR, AND THE REASON IS A PROPERTY OF THE INJECTOR.
`CLAUDE_CONFIG_DIR` does NOT isolate this surface: inject-hook.sh loads packs
from two tiers, and when the second — `$REPO/context-rules/<repo>`, where REPO
falls back to the probed directory — resolves under $HOME, the LIVE packs load
whatever $CFG says. Measured 2026-09-20: an empty config dir still returned
11,791 B at $HOME. So a shadow-dir run would charge the fixture the real box's
injection, which is how the suite caught this: two under-ceiling cases went
OVER by ~11 KB they do not own. It also means the shadow-config-dir method that
falsified the skill demotions does NOT isolate the injection — only the
constitution and the skill listing. Said here because the next person to reach
for that method will assume it isolates everything.
`LIVE_DIR=` is lint D1's sanctioned idiom for NAMING the live dir rather than
reading state through a hardcoded path, and naming it is the entire operation
here: nothing is read from it, it is only compared against $CFG so the probe can
refuse. Physically, because /tmp and /private/tmp are one directory and two
strings — the same reason D2 exists.
```

## bin/context-budget.sh, lines 453-455 (before this edit)

```text
The worst case is a session started where no repo governs — the case that
carries the full hidden-skill listing. Probed rather than asserted, and named
in the report so the claim is falsifiable at a glance.
```

## bin/context-budget.sh, lines 465-481 (before this edit)

```text
── what L2 and D WILL add — projected, and counted separately ──────────────
THESE ARE NOT SPENT YET, and calling them `live` made this tool cry wolf. When
harbor#43's content landed on 2026-07-31 the four files appeared and X3 jumped
from 96% to 133% — over by 8 KB that no session pays, because NOTHING INJECTS
THEM: the SessionStart hooks are session-verdicts and
context-resolve, and neither reads TELOS or IDENTITY. The telos skill
loads its corpus on invocation, which is the invoked-only cost this tool already
treats as free.

That is the built-vs-running conflation docs/generated/status.md exists to stop, reproduced in a
different tool — and a ceiling that reports bytes nobody is spending gets raised
or ignored, which is CONSTITUTION §2.11's false positive.

So: two totals. The ceiling binds what is SPENT; the projection is the
backpressure upstream built this for, printed next to it and never mistaken for
it. BELIEFS.md is here too — it was missing while its three siblings were listed,
so the projection understated itself.
```

## bin/context-budget.sh, lines 493-496 (before this edit)

```text
The worst case swaps THIS cwd's index for the largest one on the box. Where
this cwd already owns the largest store — or the box has none at all — the two
numbers are equal and the verdict says so by naming this cwd, so a box with no
stores still reports a real measurement rather than a silent 0%.
```

## bin/context-budget.sh, lines 497-525 (before this edit)

```text
── THE DELIBERATE SURFACE, WHICH IS THE HALF A BASELINE CAN BIND ───────────
harbor#183 asked what a byte CEILING protects, and the answer measured out to
nothing: capacity is refuted arithmetically (this surface is ~11k tokens, 1.1%
of a 1M window), cost is refuted by harbor#184 (~$190/yr, ~3% of the bill, and
it says outright the ceiling is not a cost lever), and dilution is refuted by
E8, where 595 B and 17,845 B both score 3.00/3 — "volume is free".

What the tool WAS built for is in its own header, quoting upstream:
"backpressure against always-on context re-accretion … those files regrow". The
concern is REGROWTH, and regrowth needs no invented absolute — it needs a prior
measurement. So the gate becomes T1's mechanism applied to this surface: a
recorded baseline that must match, and changing it is a commit that says why.

THE SPLIT IS THE WHOLE DESIGN. Only the DELIBERATE surface is baselined —
CLAUDE.md plus ambient skill descriptions plus repo-scoped files — because
those change only when somebody deploys something. The memory index is excluded
and deliberately so: it changes every time a memory is written, so baselining it
would fire on ordinary work within a day, and §2.11 makes that the defect rather
than the safety. memory-store-check.sh already owns the index, with its own bound.

THE INJECTION IS EXCLUDED FROM THE BASELINE FOR THE SAME REASON, AND IT IS A
DIFFERENT ONE FROM "it changes often": it changes with the CALLER'S DIRECTORY,
by 10 KB. A baselined number that moves when the tool is invoked from somewhere
else is not a baseline, it is a report about the caller — the defect harbor#243
already recorded against the verdict. It is charged to SPENT and to the WORST
CASE, where it is true, and kept out of the row a commit has to justify.
Plugin and command descriptions are NOT excluded: they are the same in every
directory, and a plugin that auto-updates its agent descriptions has changed
the prefix of every future session, which is precisely what a baseline is for.
```

## bin/context-budget.sh, lines 530-538 (before this edit)

```text
RESOLVE THE SYMLINK OR THE LABEL LIES. `memory-route.sh` routes governed repos
to the ONE $HOME silo by symlink — 25 of 200 store directories are links and
the 200 MEMORY.md files have 3 distinct inodes (measured 2026-09-20). The
loop above takes the first slug of equal size, so it reported
`-Users-someone-.local-lib-<tool>` for a file that IS `-Users-someone`.
That mattered little while the worst case was one surface; it matters now that
it is paired with the injection probed at $HOME, because a reader has to be
able to see that both maxima land in the SAME session and the compound is a
directory someone actually starts in, not two unrelated maxima added together.
```

## bin/context-budget.sh, lines 546-549 (before this edit)

```text
── THE BASELINE VERDICT (harbor#183) ───────────────────────────────────────
--check fails when the DELIBERATE surface no longer matches the last recorded
row; --record appends today's measurement. Placed before the report so both
modes exit having said one thing, not two.
```

## bin/context-budget.sh, lines 561-565 (before this edit)

```text
INSTRUMENT IDENTITY (harbor#585). A byte count means nothing without the ruler:
#316 widened the scope and the +7,018 B it brought in read as regrowth, because
the row recorded a number and not what produced it. Identity = the surface set
counted into `deliberate` + a digest of the two measuring functions, so a scope
change and a method change both change it, and neither needs a human to remember.
```

## bin/context-budget.sh, lines 575-577 (before this edit)

```text
THE REASON IS NOT GENERATED. A row whose "why" this script wrote would be a
machine restating the number in the column beside it, which is the copy T2
exists to stop. It writes a placeholder that is obviously unfinished.
```

## bin/context-budget.sh, lines 589-591 (before this edit)

```text
THE KIND IS THE FINDING'S SUBJECT, NOT ITS MESSAGE (harbor#585, contracts/finding.md). One
subject for every failure filed an instrument change and regrowth as the same finding, so
accepting one silenced the other. Printed only under --kind, last, on its own line.
```

## bin/context-budget.sh, lines 635-641 (before this edit)

```text
THE `ceiling <n>` TOKEN IS AN INTERFACE, NOT A VERDICT. memory-store-check.sh seds this
exact line to derive the memory index's allowance, and a first cut of harbor#183
replaced the token with prose — which made store-check print "No verdict on
size: the allowance is derived … and it did not yield one". It degraded honestly,
which is the only reason that was a five-minute regression instead of a silent
wrong bound. The annotation goes AFTER the number, where store-check's trailing
`.*` absorbs it.
```

## bin/context-budget.sh, lines 645-654 (before this edit)

```text
THE ROW THAT USED TO BE HERE IS GONE, AND WHY IT WENT IS THE POINT. A first cut
of #316 printed "the index allowance this leaves store-check", because counting
the plugin, command and injection surfaces dropped `ceiling - (spent - index)`
from 9,477 B to 799 B and would have made store-check demand a five-pointer
index — §2.11's false positive, arrived at by measuring something ELSE more
honestly. memory-store-check.sh no longer uses that arithmetic (harbor#316, second
half): its allowance is `always-on pointers x 150 + 600`, derived from the index
it is measuring. So this tool has nothing to warn about, and a row describing
another tool's formula would now be a copy of something that is no longer true.
Removing it in the same change is the doctrine that produced the change.
```

## bin/context-budget.sh, lines 658-661 (before this edit)

```text
THE VERDICT IS THE WORST CASE (harbor#243). It used to be $total, which made
the answer depend on the directory the tool was invoked from — and the one
caller that runs unattended, lint X3, is invoked from the cheapest directory on
the box. A number that changes with the caller's cwd is not a ceiling.
```
