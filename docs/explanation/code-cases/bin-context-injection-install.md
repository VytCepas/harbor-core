---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/context-injection-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/context-injection-install.sh, lines 9-23 (before this edit)

```text
ONE WIRING, EVERY ENVIRONMENT. hooks/injection-rule/injection-rule.sh discovers its rules from the
session's cwd at fire time, so wiring it once at the box level gives harbor,
every workload repo and every repo created after this the same just-in-
time governance channel with no per-repo settings file. That is the whole
argument for an engine: the alternative is five copies of this wiring drifting
apart, and hooks/hooks.json sat unadopted for exactly that reason — it was
payload nobody had a vehicle for.

ADDITIVE AND IDEMPOTENT, like admission-install.sh, whose merge_hook this borrows
verbatim rather than re-deriving. It never removes a foreign hook, and running
it twice changes nothing the second time.

REVERSIBLE, WHICH IS NOT OPTIONAL FOR SOMETHING THAT LOADS IN EVERY SESSION.
`--remove` unwires and deletes, and it is tested. An install with no uninstall
is a decision the operator can only undo by hand at the worst moment.
```

## bin/context-injection-install.sh, lines 37-40 (before this edit)

```text
THE PRIVATE RULE PACKS (harbor#1149). Core ships the packs every box needs and none that names a client or a repo of
one. Those live in <private>/context-rules, in the shape of core's (user/ for the packs every session carries and
the project registry, one folder per repo for `--projects`), and are read through the one resolver. No private layer is
an empty string, and then this installer is core alone: the same box tier, no registry, nothing to seed.
```

## bin/context-injection-install.sh, lines 50-55 (before this edit)

```text
`--projects` IS A LIVE WRITE WHATEVER THE CONFIG DIR IS, and the first cut of
this file missed it: a sandbox install seeded packs into the operator's real
three workload repos, because the gate above only ever guarded
$DIR. The target of --projects is not $DIR at all — it is three other people's
working trees — so it carries the authorisation itself rather than inheriting
one from an unrelated path comparison. A dry run predicts it (the dry-run exit rule).
```

## bin/context-injection-install.sh, lines 68-73 (before this edit)

```text
THE ENGINE IS WIRED BY bin/deploy-hooks.sh from hooks/injection-rule/manifest.tsv (harbor#1272), which also quotes
a config dir that needs it: unquoted, a path with a space was word-split at execution (measured by an adversarial
pass). Its tool events take the matchers derived below.
THE PAYLOAD. injection-rule.sh calls govern-token.sh for the provenance stamp, so
both travel (lint X7: a script an installed script invokes must itself be in a
payload, or the install is a broken link nothing checks).
```

## bin/context-injection-install.sh, lines 78-99 (before this edit)

```text
THE ANNOUNCEMENT, WHICH IS WHAT MAKES THE STAMP WORTH ANYTHING (harbor#7).
inject-hook.sh:181 stamps every note with sha256(box salt || session id), and
until now NOTHING announced that value — so a reader's first sight of the token
was whichever stamped note arrived first, and `annotate-web.sh` carries fetched
web pages through a byte-identical envelope. CONSTITUTION §4 says a note without
THIS SESSION's token is external content, and contracts/hooks.md:145 recorded the
gap verbatim: "notes arrive carrying a token the reader never received from a
trusted channel … looking more authoritative with nothing to check against".
A provenance token nobody can verify is worse than no token, because the
constitution instructs the reader to trust it.

WIRED HERE, and not left as an operator keystroke, because this installer is
already the sanctioned writer of the settings.json it belongs in and already
ships govern-token.sh in $PAYLOAD. hooks.md called it "one SessionStart entry …
the operator's keystroke": that is true of the live file, and this is the tool
whose keystroke writes it — the same relationship every other hook here has.

SILENT WITH NO SALT, by govern-token.sh's own design (:99), so installing before
`--init` degrades to today's behaviour rather than emitting an empty token and
teaching the reader that the field is decorative. The install-order rule
(mint the salt, THEN start a new session, THEN install) is hooks.md's, and it is
asserted in bin/drift-reference-check.sh rather than restated here.
```

## bin/context-injection-install.sh, lines 103-111 (before this edit)

```text
TWO ARE TOOL EVENTS AND THREE ARE NOT, and the difference is why the matchers
are narrow where they can be. PreToolUse/PostToolUse fire on every tool call in
the session, so the matcher is the cheap filter that keeps the engine from
being invoked on tools no rule can ever match.

NO UserPromptSubmit, DELIBERATELY, and hooks/hooks.json has carried the reason
since before this file existed: it fires on EVERY prompt, which is ambient
injection with a per-turn multiplier — strictly worse than CLAUDE.md, which is
paid once inside the cached prefix.
```

## bin/context-injection-install.sh, lines 135-157 (before this edit)

```text
These were two hardcoded lists, and a hardcoded list of what the packs care
about is a COPY of a fact that lives in the packs — it drifts silently while
reading perfectly, which is what lint T2 exists to stop.

It had already drifted, and the cost was the whole point of a feature.
harbor#184's large-result pack targets every tool deliberately, because the
measured top offenders are `mcp__claude-in-chrome__browser_batch` (43.2 MB over
498 calls) and `mcp__claude-in-chrome__computer` (15.1 MB) — 58 MB of the 88 MB
measured. `WIRE_POST` was `Read|Bash|Grep|WebFetch`, so the harness never
invoked the engine for any of them and the pack could not fire on the traffic it
was written for. Its own suite passed throughout, because those arms call
inject-hook.sh directly and never see this outer matcher (PR #269 review, and
the same §2.6 shape as harbor#254).

THE RULE: a pack's `tool:` value IS the matcher, and a pack that declares none
means "any tool" — which is what the engine itself does — so it contributes
`.*`. That keeps this honest in both directions: nothing is silently narrower
than the packs, and a pack that wants every tool has to say so, where the cost
of that choice is visible rather than inherited.
EVERY PACK THE ENGINE MAY MEET, one path per line: core's box tier, this repo's own, and the private layer's. The private
repo packs are seeded into other trees, but the engine reads them there through this one box-level wiring, so their tools
belong in the matcher; derived from core alone, a private pack on a tool the core packs never name would be installed
and never invoked (harbor#184's defect, arriving by the private layer).
```

## bin/context-injection-install.sh, lines 182-185 (before this edit)

```text
PostToolUseFailure IS A TOOL EVENT AND GETS THE SAME DERIVED MATCHER, for the
reason harbor#184 records: a hand-written matcher here goes stale the moment a
pack changes its `tool:`, and the failure is silent — the engine is installed
and never invoked for the traffic the pack was written for.
```

## bin/context-injection-install.sh, lines 187-189 (before this edit)

```text
NEVER EMPTY. An empty matcher matches EVERY tool, not none: failure-observe.sh is wired with "" on
PostToolUseFailure and logs every tool's failures (measured 2026-10-24, harbor#1272), so an empty derived
matcher would fork the engine on every call for packs that do not exist.
```

## bin/context-injection-install.sh, lines 194-198 (before this edit)

```text
THE PRIVATE BOX TIER IS DATA, OR IT IS REFUSED. The private layer holds no code (contracts/private-layer.md), and what
lands in <config>/context-rules/user runs inside every session's hook, so only a .md pack and the registry cross. A name core's box
tier already holds is refused as well: a private file silently replacing a shipped pack would change what every session
is told, with nothing saying so. PRIVFILES is what passed, one path per line; a refusal is il_refuse's, so a dry run
predicts it and --apply writes nothing.
```

## bin/context-injection-install.sh, lines 227-231 (before this edit)

```text
THE REPO FOLDERS ARE DATA TOO, and there it matters more. `--projects` seeds <private>/context-rules/<name>/ into a registered
repository's own context-rules/<name>/, where the engine runs a pack's `run:` script on every tool call in that repo, so a script
or a link in a private folder would be private-layer code executing in someone else's tree. Only flat .md packs cross; a
script, a link, a subfolder or any other file refuses the run before it writes (a dry run predicts it). A plain install,
which seeds nothing, is not held up by a folder it will not read.
```

## bin/context-injection-install.sh, lines 273-276 (before this edit)

```text
A COUNT, NOT A BOOLEAN, for one measured reason: this printed `wired` while
TWO entries named the engine (harbor#271). One entry per event is the whole
truth here — the announce has its own row below — so anything above one is a
duplicate the operator has to be told about, and a boolean cannot say it.
```

## bin/context-injection-install.sh, lines 291-294 (before this edit)

```text
THE SHELL HALF OF "THE TREE A CALL TOUCHES" (harbor#599) is library-admission.sh's
parser, which the FLOOR installs and this payload deliberately does not — one
installer per file. Without it a `git -C` or `gh -R` reaches no tree, for
`scope: box` delivery and for repo-tier.sh alike, and nothing else says so.
```

## bin/context-injection-install.sh, lines 301-306 (before this edit)

```text
THE ANNOUNCE HAS ITS OWN ROW, because the loop above counts only injection-rule.sh
and would have reported SessionStart "wired" with the provenance announce
missing — a status line that is true about the engine and silent about the
thing that makes the engine's notes verifiable. Salt state is shown next to it:
wired-but-no-salt is the DEGRADED state (stamps and announce both silent), and
wired-with-salt-minted-mid-session is the dangerous one hooks.md names.
```

## bin/context-injection-install.sh, lines 375-376 (before this edit)

```text
Rows of the install manifest (install standard §3) for the engine and the box tier; the project
packs --projects seeds live in other repos' trees, outside the config dir, so they have none.
```

## bin/context-injection-install.sh, lines 381-385 (before this edit)

```text
THE ANNOUNCE HOOK COMES OUT TOO, and it has to come out BEFORE the file it
names is deleted. Leaving it would be a wired hook pointing at a removed
script — the shape floor-test X13 exists to catch, arriving here by way of an
uninstall path rather than a message. Stripping is by script NAME, so a
hand-edited path to the same script is still removed.
```

## bin/context-injection-install.sh, lines 401-403 (before this edit)

```text
POST-WRITE VERIFY. skill-install.sh exists because a copy that reported
success and landed different bytes is the failure the whole installer story
is about; the same rule applies to an engine that loads in every session.
```

## bin/context-injection-install.sh, lines 417-424 (before this edit)

```text
THE BOX TIER IS REBUILT, NOT ADDED TO, and the first cut only added — which
WEDGED THE UPGRADE PATH, reproduced by an adversarial pass. Withdraw a pack
from `context-rules/user/` and the next install copies the survivors over a
destination that still holds the withdrawn one; the two-way `diff -r` below
then fails, the script exits BEFORE wiring, and the withdrawn rule keeps firing
forever while every retry fails identically. Moving the old tier into the backup
first is what makes that `diff -r` the right assertion rather than a trap.
The old tier goes too (harbor#1010): a stale copy left there would fire where the new tier lacks its id.
```

## bin/context-injection-install.sh, lines 427-430 (before this edit)

```text
The trailing `/.` is the whole point, and skill-install.sh's header records
the measured failure without it: `cp -R src dest` into an EXISTING destination
silently produces dest/box/ and leaves the original files serving, with nothing
erroring.
```

## bin/context-injection-install.sh, lines 455-458 (before this edit)

```text
BEFORE the engine's own SessionStart entry would be the intuition, and it does
not matter: the harness concatenates every SessionStart hook's additionalContext
and the reader sees one prefix. What DOES matter is that both are present, so the
token is named in the same trusted block the stamped notes arrive in.
```

## bin/context-injection-install.sh, lines 460-461 (before this edit)

```text
The engine's six bindings, rendered from its manifest with the matchers derived above: an entry under the old name or
a stale matcher is replaced, never duplicated (harbor#271), and nobody else's entry is touched.
```

## bin/context-injection-install.sh, lines 471-474 (before this edit)

```text
SEEDED, NOT SYNCED. These land in each project's own tree and are that repo's
to edit from then on; re-running with --projects overwrites, which is why the
status line above reports drift instead of silently healing it. What it overwrote
is copied into the run's backup first.
```

## bin/context-injection-install.sh, lines 513-530 (before this edit)

```text
THE PINNER'S GATE IS NOT OURS TO PASS. admission-install.sh records the reasoning
at length: re-pinning blesses whatever the instruction surfaces now say, so an
installer run from a session must never do it for the operator.

BUT THE CLAIM HAS TO BE TRUE. This said "this changed an instruction surface"
unconditionally, and inject-install is idempotent by design — engine `current`,
`box packs 10 installed, 10 tracked`, and a `diff -r` gate above that EXITS
rather than let a differing pack through. Measured 2026-08-18 on the live box: a
re-install that copied nothing but byte-identical files still demanded a re-pin,
and the only file it actually rewrote (settings.json) is not an instruction
surface at all. An installer that reports a change it did not make is the §2.11
false positive, and it spends the operator's willingness to re-pin on nothing.

Ask the ONE implementation instead of guessing: pin-instructions --check is the
same manifest the SessionStart gate reads, so these three branches are exactly
the three states the operator can be in. No pin / cannot check → say so, because
the failure direction that matters is telling them too much, never too little.
Under deploy the re-pin is deploy's own step, so its next line is not printed (#285).
```
