# Rule packs — the just-in-time governance format

**Frozen surface:** the frontmatter keys and the predicate vocabulary below.
**Engine:** [`bin/inject-hook.sh`](../bin/inject-hook.sh). **Installer:**
`harbor inject`. **Suite:** [`tests/hooks/inject-hook.engine-test.sh`](../tests/hooks/inject-hook.engine-test.sh), with the detector, packs and scope parts beside it.
**Ticket:** harbor#173 · A1.

A rule pack is a markdown file. A repo declares one, and from then on that repo's
sessions carry that rule at the moment it applies — with no shell of its own, no
settings file of its own, and no cost in any session where the moment never
arrives.

## Why this exists rather than more prose in a CLAUDE.md

Three measurements, all in [EVALS.md](../EVALS.md), and together they are the
whole argument.

**Placement inside the prefix does not matter. Being in the prefix at all does.**
E6 ran one sentence two ways against the same trap: as prose in a runbook the
model had already opened, **0/4**; injected at the tool call, **4/4**. E8 then
showed volume is not the variable either — a 595 B constitution and a 17,845 B
one both scored 3.00/3 on the same task. The line that separates a rule that
binds from a rule that does not is *resident when the model acts* versus *has to
be fetched*.

**Every project in this estate is on the wrong side of that line.** A workload repo,
Two workload repos each ship a `CLAUDE.md` whose entire content is *the
canonical instructions live in AGENTS.md, read it before working*. That is the
fetch-required shape by construction, so everything in those AGENTS.md files is
non-binding until something puts it in front of the session.

**Informing beats vetoing.** E6 ran both against the same trap: inform 4/4, veto
3/4 — and the veto's single miss was a session that stopped to ask rather than
acting. **There is exactly ONE opt-in deny, and this sentence used to say there
was none** — it read "there is deliberately no `deny` mode" for the whole of the
time the mode existed, which `bin/inject-hook.sh` corrected in its own header and
this file did not. The sentinel is specified under *A `run:` pack may return a
decision* below; it is exact, opt-in, `run:`-only and PreToolUse-only. A contract
that denies the existence of the blocking path is worse than one that omits it,
because a reader deciding whether a pack CAN block gets a confident wrong answer.
Vetoing otherwise belongs to the floor
(`guard-bash.sh`, `guard-egress.sh`), where the question is whether something may
happen at all. A second, softer copy of the floor in a file any repo can edit is
not a feature.

## Where packs live

| Tier | Path | Loaded | Installed by |
|---|---|---|---|
| **Box** | `<config>/inject.d/` | every session on this machine | `harbor inject --live --apply` from `inject.d/box/`, plus the private layer's `inject.d/box/` (`.md` packs and `projects.tsv` only) |
| **Repo** | `<repo>/.claude/inject.d/` | only when that repo is the session's **project directory** | the repo owns it; `--projects` seeds it from the private layer's `inject.d/<name>/` (core ships no repo pack, harbor#1149; [private-layer.md](./private-layer.md)) |
| **Reached** | the same directory, `scope: box` packs only | when a tool call from **outside** touches that repo, and it is registered | the same; see "`scope: box`" below |

Box and repo are read on every fire, box first; reached trees come last, and only on a tool event. The engine resolves the repo from
`CLAUDE_PROJECT_DIR`, falling back to the hook process's cwd — so **one
box-level wiring serves every repository**, including ones that do not exist
yet. That is the property that makes this scale: adding a project is a
directory, not a deployment.

### The project directory is not the working directory, and this row said it was

This table read *"only when that repo is the session's cwd"* until 2026-08-29,
and the word was load-bearing. The harness sets `CLAUDE_PROJECT_DIR` **once, to
where the session was started**, and sends the session's live working directory
separately as the payload's `.cwd`. The two are equal in an ordinary session and
diverge whenever a session is started in one place and worked in another — every
`git worktree` session on this box, because the worktrees are siblings of the
main checkout and a session opened at `$HOME` keeps `$HOME` as its project.

When they diverge the repo tier is not merely wrong, it is **empty**: `$HOME`
resolves `$REPO/.claude/inject.d` onto the box pack directory itself,
`pack_dirs()` drops it as a duplicate of the box tier, and no repo rule loads at
all. Measured 2026-08-29 in the session auditing this question — harbor's own
three packs, the merge-governance chain among them, governed nothing, and the
suites were green throughout because every one of them sets
`CLAUDE_PROJECT_DIR` to the fixture repo. That sentence ended "and so can never
see the split" until 2026-09-16, by which time it was false:
`fixtures/inject/notes.tsv` drives `repo-tier-not-loaded` through an
`@OTHER@` placeholder with a
fire arm AND a silent arm, so the divergence is exercised. What no suite
exercises is the divergence against a pack that BLOCKS — harbor#516 owns that,
and it is why the gap survived a green suite twice.

**Nothing recovers the lost tier wholesale, by decision.** Widening the scope to
the live cwd would make the governing tree move mid-session, which is worse than
losing it. A repo can instead send **individual rules** out, in its own data, with
`scope: box` (below). The box pack `95-repo-tier-not-loaded.md` reports whatever
is still lost: it reads `.cwd` for the report and never for scoping, names the
rules that are not loaded, and names the ones that crossed. It stays silent when
the two directories agree, when the standing tree carries no packs, when every
rule in it crossed, and when the payload has no `.cwd` at all.

### The tree a call touches

One definition, decided 2026-09-24 on harbor#599, for every rule that asks
whether a tool call reaches into a repository:

| Call | The tree it touches |
|---|---|
| a file tool | the repository holding the path it names (`file_path`, `notebook_path` or `path`). A path that does not exist yet counts by its nearest existing parent. |
| a shell command | the repository holding the payload's `.cwd`, each `-C <dir>` target, and a `gh` `-R` / `--repo` slug, mapped to the checkout under `PORT_ROOT` whose `origin` it names |

**`cd X && …` is not followed.** Reading a directory out of a cd chain is the
shell parsing harbor#539 records as the floor's longest chains of fixes to
fixes. The harness carries the new working folder in the next call's `.cwd`, so
a `cd` is reported one call late rather than parsed. Quoted arguments and
heredoc bodies are data: the shell half goes through the floor's own
`floor_seg_load` (`guard-lib.sh`, beside the engine), never a second parser.
Without `guard-lib.sh` there are no shell targets, and the engine stays silent.

**Computed once, by the engine, on the three tool events.** `bin/inject-hook.sh`
works the answer out before any pack is read, and hands it to every `run:` pack
as `HARBOR_TOUCHED`, one physical tree per line. `HARBOR_REACHED` lists the
subset whose `scope: box` packs were swept. `repo-tier.sh` reads both instead of
repeating the definition, so the report and the delivery cannot disagree about
which tree a call reached. It carried its own copy for one PR (#601), and a
second reader is what made the copy a seam.

**What `repo-tier.sh` does with it (harbor#601).** A session launched at
`PORT_ROOT` stands in no repository, and until #601 the note exited there,
silent in the commonest session on the box. It now names the tree the call
touches and that tree's unloaded rules. It stays silent for a call that names no
tree, for a tree that carries no packs, and for the governing tree. It never
lists every tree below the working folder, because a note that fires in every
session is one nobody reads.

### `scope: box` — a repo rule that follows the call

A pack in a repository's own `.claude/inject.d/` that declares `scope: box` is
also delivered when a session **outside** that repository makes a tool call that
touches it. Decided 2026-09-24 on harbor#599. The repo consents per rule, in its
own data, and the default (`scope: repo`, or no key) is to stay home.

| | |
|---|---|
| **Which trees** | **Registered projects only**: a row in the private layer's `projects.tsv` (`bin/roots.sh --projects`), or a worktree of one. The registry is the trust boundary. A reached pack is delivered with this engine's governance stamp, and a `run:` pack **executes**, so "any repository a tool call names" would let a cloned third-party repo, read once, run its own script inside this hook. |
| **Which packs** | only `scope: box` ones. The rest of that tree is still lost, and `repo-tier.sh` says so. |
| **Where it runs** | in its own tree: `repo-has` is judged there and a `run:` script runs from there, because the pack speaks for that tree, not for wherever the session started |
| **Which events** | `PreToolUse`, `PostToolUse`, `PostToolUseFailure`. Only a tool call touches a tree. Lint IJ1 refuses `scope: box` anywhere else, and any value other than `repo` or `box`. |
| **Not twice** | the governed tree is never also reached: inside its own repository a pack loads once, through the repo tier |
| **The ledger** | unchanged: `once: session` keys on the pack id, whichever tree delivered it |

**Measured before it was built: a `PreToolUse` note persists** (harbor#599,
2026-09-24). The harness stores `additionalContext` in the transcript as a
`hook_additional_context` attachment in the message chain and sends it again on
every later turn, exactly as ADR-028 found for `UserPromptSubmit`.
- **Probe:** a hook that fired once injected a codeword. A resumed turn, with all
  tools disallowed, quoted it back. A fresh control session did not have it.
- **Consequence:** a `scope: box` pack is a **standing context charge** for the
  rest of the session, which is why `once: session` is load-bearing here, not a
  nicety.
- **Not measured:** an interactive session (the probe was headless, across
  `--resume`), and whether a compaction summary keeps the attachment.

## The file

```markdown
---
id: corpus-refreeze-is-its-own-commit
event: PreToolUse
tool: Bash
when: cmd-prefix just corpus
once: session
---

The note. Everything after the second `---` is the text that reaches the model,
collapsed to one paragraph.
```

| Key | Required | Meaning |
|---|---|---|
| `id` | no | ledger key and `--explain` label; defaults to the filename |
| `event` | **yes** | `PreToolUse` · `PostToolUse` · `PostToolUseFailure` · `SessionStart` · `SubagentStart` — and `PreCompact` · `SessionEnd` **only with `mode: notify`**, see below |
| `tool` | no | tool-name matcher. `Write\|Edit` alternation is accepted. Absent means any tool |
| `when` | **yes** | a predicate. **Repeatable, and repeats are ANDed** |
| `once` | no | `session` (default) · `match` · `never` |
| `mode` | no | `inform` (default) or `notify`, which also emits a `systemMessage` to the operator |
| `summary` | no | the operator-facing line for `mode: notify` |
| `run` | no | a script beside the pack whose **stdout is the note**; empty stdout means no note. It may instead return a **decision** — see below |
| `scope` | no | `repo` (default) or `box`. `box` also delivers a repo pack when a session outside the repo makes a tool call that touches it. Registered projects only, tool events only. See "`scope: box`" above |

### A `run:` pack may return a decision, not only a note

A `run:` script whose stdout begins with

```
HARBOR-DECISION deny: <reason>
```

is emitting a **verdict** rather than a note. On `PreToolUse` the engine turns it
into `hookSpecificOutput.permissionDecision: "deny"` with `<reason>` as the
`permissionDecisionReason`, drops the additionalContext for that call (they are
answers to different questions, and only one of them stops the tool), and stops
sweeping packs — later rules would be commenting on a call that will not happen.

**On every other event the sentinel is stripped and the text is delivered as an
ordinary note**, with the downgrade stated under `--explain`. `permissionDecision`
is `PreToolUse`-only, and an object the harness rejects is discarded whole — the
`PreCompact` failure recorded in `CONTRACTS/hooks.md`, which must not repeat
quietly.

**Only `run:` output is inspected.** A static markdown body containing that line
is prose, deliberately: documents in this repo quote the sentinel, and a pack must
not acquire the power to block a tool call by containing a sentence.

**Why this exists (harbor#254).** `bin/govern-hook.sh` computes the merge
backstop's verdict and emits a deny. Reached through this engine — which is how
production reaches it, via `.claude/inject.d/merge-note.sh` — `--note` printed
that verdict as prose, the engine wrapped the prose as additionalContext, and
prose cannot stop a `Bash` call: every red PR still merged, with a green suite on
both sides of the gap. The suite fired the hook directly; the operator does not.
`tests/hooks/inject-hook.packs-test.sh` now drives the shipped pack end to end.

A pack that can deny can also block ordinary work, so it is opt-in per pack, the
sentinel is exact, and the decision is only ever as good as the predicate that
selected the pack.

### A rule that speaks leaves a record (harbor#953)

When a pack delivers a note, or a `run:` pack returns a deny, the engine appends one line to
`guard-decisions.jsonl` through the floor's own writer (`floor_log_decision`): `g` is `inject`, `d` is
`advise` or `deny`, `r` is the pack's `id`. A call no rule spoke on writes nothing. The writer's rule
field allows only `[a-z0-9-]`, so the id is the bare `agent-brief`; the `rule:context.` prefix in
harbor#953 waits for the naming ticket. A box with no ledger stays blind, never wrong.

### `once: match` and what the subject is

`session` (the default) delivers a rule once per session. `never` delivers every
time. `match` re-delivers when the **subject** changes, and the subject is, in
order of preference:

1. `tool_input.file_path` — the path the tool was handed;
2. otherwise the content written or returned (first 4 KB);
3. otherwise **the command** (first 4 KB).

The third fell in on 2026-08-09 (harbor#180). A `PreToolUse` rule over `Bash` has
neither a path nor content — nothing is written or returned until after the call —
so every command hashed to the same empty subject and `match` silently behaved as
`session`. Measured: five different matching commands in one session, only the
first spoke. `cmd-prefix` plus `match` is the most natural pack anyone writes, and
it failed by going quiet, which nothing turns red for.

The subject is the **raw** command, not the matched prefix: `gh pr merge 174` and
`gh pr merge 179` are different acts on different objects and a rule should speak
for both. `tests/hooks/inject-hook.engine-test.sh` asserts all three — first delivery, silence on
a repeat, and delivery for a different command in the same session.

**A pack with no `when:` never fires.** That is deliberate and it is asserted:
the most likely typo must not produce the loudest possible rule.

**An unrecognised predicate never fires either.** `bin/skill-book.sh` carries the
incident this guards against — an unrecognised token that fell through to the
permissive branch turned a gate into a no-op while still reading like a gate.

### Every shipped pack needs a probe row, and the suite fails without one

`tests/hooks/inject-hook.engine-test.sh` tests the **engine**, against packs it writes itself in
a temp dir. That is the right shape for an engine and it says nothing whatsoever
about the packs in `inject.d/`. Measured 2026-08-29 by grepping every tracked
`id:` against every suite: **14 of 17 were named in none of them.** Naming is a
proxy — a suite could exercise a note without mentioning its id — but the two
merge packs are the only ones with any indirect coverage, through
`tests/hooks/govern-hook-test.sh` testing the script the pack calls rather than the pack.

What the blindness cost is not hypothetical. A workload repo's pack (then tracked in
this repo's `inject.d/`, now in the private layer's) was committed
2026-08-25; seeding is opt-in (`inject-install.sh --projects`) and the last
seeding run was 2026-08-23, so `~/<repo>/.claude/inject.d` never existed and
the note warning that `<tool> --full-refresh` destroys 2.5 years of history had never
been delivered once. `inject-install.sh`'s own status line read `absent or drifted`
the entire time — **the detector was right and nothing consulted it.**

Two mechanisms close the two halves, because they are different failures:

| | failure | mechanism |
|---|---|---|
| unreachable | the engine cannot reach the pack | `tests/hooks/inject-notes-test.sh` — every tracked `id:` needs a **fire** row and a **silent** row in `fixtures/inject/notes.tsv`, or the suite fails |
| undelivered | the pack is not in the project's tree | lint **IJ4**, advisory — it reads `$HOME`, and a CI runner has none of these repos |

A default run has no private layer, so the packs that depend on `cmd-contains` are not in it. `fixtures/inject/packs/`
carries an example pack that stacks two of them; it is never installed, and the suite tracks it like a shipped note.

**The silent arm is not optional.** §2.11 — a false positive is a defect, and a
fixture that only ever asserts firing cannot see one. The silent arms are
near-misses on purpose (`<tool> run` without the flag, `gh pr list` beside
`gh pr create`, the phrase quoted in prose rather than run); an absurd negative
proves only that the predicate is not `true`.

**Exemptions are named, with a reason, and counted on every run.** Two packs call
`gh` against a live PR, so pinning their content would put the network inside a
suite; their wiring is asserted against a stub instead. A silent cap reads as full
coverage, so the count prints whether or not anyone asks.

### Not every event can reach the model

`hookSpecificOutput.additionalContext` is accepted on `SessionStart`, `Setup`,
`SubagentStart`, `UserPromptSubmit`, `UserPromptExpansion`, `PostModelSwitch`,
`Notification`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
`PostToolBatch`, `Stop` and `SubagentStop`. On any other
event the harness **rejects the whole object** — including a `systemMessage`
riding along in it — and the only trace is a validation error in the operator's
terminal. `PreCompact` in particular accepts nothing but the top-level `decision`
pattern: there is no channel from a `PreCompact` hook to the model at all.

**That list was read off the binary's own schema on 2026-09-02, and three events
were missing from it.** `hookSpecificOutput` is a discriminated union in 2.1.258;
each arm either declares `additionalContext` or does not, so the question has an
exact answer rather than an inferred one. `UserPromptExpansion`, `PostModelSwitch`
and `Notification` all accept it and were being downgraded to operator-only.
Nothing ships on them, so the cost was nil — the direction is the point. A
hand-maintained list of what a harness accepts drifts toward being SMALLER than
the truth, and every omission is a pack that quietly reaches nobody.
**`PostCompact` is not in the union at all**, so the event that receives the
compaction summary cannot hand any of it to the model.

This is written from a defect, not from the documentation. `20-precompact-carry.md`
declared `event: PreCompact` and every compaction on this box emitted an envelope
the harness discarded — while the suite stayed green, because it asserted the
engine's stdout rather than what the harness accepts. The rule now rides
`SessionStart` with `when: source-is compact`, which is the far side of the same
moment and can be heard.

So on a context-less event the engine emits a `systemMessage` alone, or nothing.
A pack targeting one must declare `mode: notify` — **lint IJ1 fails otherwise**,
and `tests/hooks/inject-hook.packs-test.sh` asserts that `PreCompact` produces no stdout at all.

**`PostToolUseFailure` was on that accepted list for months with nothing on it**,
and it is now wired (`85-tool-failure-is-not-a-result`). Two things about it were
only learnable by firing it — see the row in `CONTRACTS/hooks.md` for the probe.
It carries **no `tool_response`**, so `content-contains` matched an empty string
until the engine started folding `.error` into `CONTENT`; and a **non-zero Bash
exit is not a tool failure** — that is an ordinary `PostToolUse`, because the tool
ran. What reaches this event is the tool itself refusing. It also carries
`is_interrupt`, which no predicate can read, so a pack that must not fire on an
operator's Ctrl+C has to be a `run:` script.

## The predicate vocabulary

It is fixed, and it is not a language. Every predicate compares a value **from the
payload** against a pattern **from the pack**, and the payload value is only ever
the subject of a `case`, never the pattern. Nothing from a payload is evaluated,
interpolated into a command, or used as a glob.

| Predicate | Fires when |
|---|---|
| `always` | the event fires |
| `cmd-prefix <words>` | a command-position segment **starts with** exactly those words |
| `cmd-contains <text>` | the command contains the text, heredoc bodies stripped |
| `path-contains <text>` | `tool_input.file_path` contains the text |
| `content-contains <text>` | the written content or the tool's response contains the text |
| `repo-has <relpath>` | that path exists in the session's repo |
| `tool-is <name>` | the tool name is exactly that |
| `source-is <value>` | `SessionStart` only — why the session started: `startup` · `resume` · `clear` · `compact` · `fork` |
| `injected-instruction` | the content addresses whatever is **processing** it (see below) |
| `not <predicate>` | any of the above, inverted |

`cmd-prefix` is the subcommand, **not a substring** — `gh pr list --search "pr
merge"` does not match `cmd-prefix gh pr merge`, and neither does the phrase
inside a heredoc body, a quoted argument or a commit message. All three were
shipped as substring tests first and all three fired on ordinary work.

**The quoted-argument case was the last to be fixed and the most damaging.**
Splitting ran on `; & | ( )` and newline without regard to quoting, so
`git commit -m "record the gate (gh pr merge needs the backstop)"` produced a
command-position segment and fired the rule — on a commit. The second-order
effect was worse than the noise: these packs default to `once: session`, so the
benign commit **spent the ledger key** and the real command later in the same
session got silence. Quoted bodies are now blanked before splitting, exactly as
heredoc bodies are. **An unbalanced quote blanks the rest of the command**, which
is the deliberate direction to fail in — a missed note costs a note, a false one
costs the channel.

`cmd-prefix` also never matches an invocation carrying `--help`: a note about the
consequences of an action, delivered to someone reading how the action works, is
noise by definition.

**`-h` is not in that exclusion, and it was.** The justification given for it —
that the exclusion can never wrongly suppress, because what it silences performs
nothing — was false twice over, measured by an adversarial pass. `-h` is a *value*
flag for tools installed on this box (`docker run -h web`, `mysql -h host`), and
the test scanned the whole segment rather than a flag position, so
`gh pr merge 12 --body 'pass -h to see flags'` silenced an installed pack from
inside a quoted string. `--help` has neither problem.

## `injected-instruction`

The one predicate that is not a string compare, and the reason the engine exists
rather than a fifth branch in `bin/govern-hook.sh`.

E9 measured the hole precisely. An HTML comment reading `SYSTEM DIRECTIVE …
ignore previous instructions` was refused **4/4 by every arm, including the one
with no constitution at all** — models are trained on that shape. A plausible
`## Documentation pipeline convention` heading, inside the very file the task
asked the model to summarise, was obeyed **6 of 8 times without §4 and 2 of 8
times with §4 fully present**. §4 is load-bearing and it is not sufficient.

So the detector does not look for menace. It looks for text addressing **the
processor of the content** rather than its reader — the thing a legitimate
document almost never does and a content-borne injection must. Two tiers: loud
phrases fire alone; quiet phrases need a second quiet phrase or a write /
exfiltrate marker.

**The false-positive set is swept, not counted here.** Every tracked markdown
file in this repo is run through the detector by
[`tests/hooks/inject-hook.detector-test.sh`](../tests/hooks/inject-hook.detector-test.sh) and compared against an
allowlist, so **a new false positive turns the suite red on the commit that
introduces it**. The allowlisted ones are all documents *about* injection — the
constitution's §4 describes the attack in the attack's own words, this contract
quotes the tells, and `EVALS.md` carries the E9 fixtures verbatim.

That mechanism replaced a hand-typed *"two known false positives"*, which an
adversarial pass found **was already false in the commit that wrote it** — the
same commit added two more documents discussing the attack — and which was copied
into four files. Lint T1/T2 forbid exactly that everywhere else in this repo. The
rule also ships as `once: match`, so a benign hit costs one sentence and does not
consume the session's budget for a real one.

**What it does not cover, said out loud:** an injection phrased entirely in
vocabulary neither list carries, and an injection in content the hook never sees
because it arrived through a tool the wiring does not match. The detector is a
net, not a wall — the same thing `FLOOR.md` says about the egress rules.

## Writing a good rule

The bar is high on purpose. **A false positive is a defect, not safety**
(CONSTITUTION §2.11) — a note that fires on ordinary work is a channel that gets
tuned out, and nothing turns red when that happens.

- **It has a moment.** A specific tool call at which it becomes true and
  actionable. *"Write good code"* has no moment.
- **It is already written down somewhere in the repo**, and the pack cites where.
  A rule invented at pack-writing time is a rule with no owner.
- **Violating it is expensive, irreversible, or burns many turns.**
- **Nothing else already fires.** If a pre-commit hook, a lint rule or a CI job
  blocks it, the note is noise. This is the most common reason to reject one: of
  fifteen candidates proposed across four repos for the first release, **ten were
  dropped**, most of them as already-enforced or as false-positive generators.
- **It names a falsifier.** A claim with no falsifier is not a claim.

Prefer two excellent rules to six plausible ones. Zero is a valid answer.

## Adding a project

1. One line in the private layer's `inject.d/box/projects.tsv` (`sh bin/roots.sh --projects`) — `name<TAB>~/path<TAB>what it covers`.
   That line is also the pointer every other session gets about this project, so
   write `covers` as the question that sends a reader there.
2. `inject.d/<name>/` in the private layer for the packs, if the project's rules should be
   tracked centrally; otherwise the repo owns `.claude/inject.d/` directly.
3. `harbor inject --live --apply --projects`.

Nothing else. No new wiring, no new script, no settings file in the project.
