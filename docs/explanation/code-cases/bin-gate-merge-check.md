---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/gate-merge-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/gate-merge-check.sh, lines 18-27 (before this edit)

```text
  HARBOR_SCOPE_REPO   owner/name; default comes from the checkout's remote, and
                falling back to THIS SCRIPT'S checkout when cwd is elsewhere.
                NOT a path — bin/drift-renew-check.sh reads the same name as a path;
                a value that is not owner/name is REFUSED here, see repo().
  HARBOR_GATE_BRANCH the protected branch (default: main)
  HARBOR_GATE_REQUIRED_CHECKS
                the local gate's declaration (default: contracts/required-checks.tsv
                beside this script, followed by the private layer's required-checks.tsv
                when gate-required-generate.sh is beside it): repo<TAB>check name, one
                row per required check. Set, it is the only list read
```

## bin/gate-merge-check.sh, lines 29-63 (before this edit)

```text
WHY THIS EXISTS, AND WHY ITS SCOPE SHRANK. #150 specified this as the merge
gate GitHub could not provide, because branch protection needs a paid plan on a
private repo. The plan was bought on 2026-08-06 and protection now enforces, so
this is no longer the gate — it is the BACKSTOP for the day it goes away.

THE LAPSE IS SILENT, which is the whole argument for `--protection`. A private
repo on a free plan does not report "your rules are off"; the protection
endpoint simply answers 403 and every rule stops applying. Nothing in the UI
turns red, no PR complains, and the next merge of a failing branch succeeds
quietly. A subscription is a control with an expiry date and no alarm.

`gh pr checks` IS THE ORACLE, deliberately, rather than a reimplementation over
the check-runs API. It is what GitHub itself scores, and it already encodes the
rule that cost this repo a morning: a CANCELLED check run counts as FAILING
against a required context and never clears. A local reimplementation would
have to rediscover that, and would drift the first time GitHub changed how a
conclusion maps to a verdict. Copies of a fact that lives somewhere else drift
silently while reading correctly.

THE LAPSE HAPPENED (2026-10-05, harbor#1060): protection 403, or requiring
nothing, gates on contracts/required-checks.tsv instead — each listed check
must be on the PR head and pass. Protection that requires checks stays the gate.

EVERY CHECK, NOT ONLY THE REQUIRED ONES — and this is a CORRECTION, made the
first time the tool was pointed at a real merge. It ran with `--required`, and
`main` then required exactly two of roughly thirteen jobs on purpose, so it reported

  ok  #157 — every required check passes (2)

while `recover red-green` sat at `failure`. It was not wrong by its own
definition; it was answering a narrower question than the one being asked.
"Would GitHub let this through" and "is anything red" are different questions
on a repo that requires a subset, and a tool whose whole job is refusing to
merge red must answer the second one by default. `--required-only` keeps the
first available, because knowing what actually BLOCKS is a real question too.
```

## bin/gate-merge-check.sh, lines 75-88 (before this edit)

```text
── THE STRATEGY IS A CHOICE, AND IT WAS HARDCODED (harbor#267) ──────────────
`--merge` MEANS TWO DIFFERENT THINGS in this file, which is the whole reason
this was easy to miss: harbor's `--merge` is "do the merge", and gh's `--merge`
is the merge-COMMIT strategy. The second one was written into the argv below
with no way to choose it, so the squash shape was unreachable through the
sanctioned route — and squash is what 95 of 287 commits on `main` use, 18 of
the last 20. Measured 2026-08-22.

THE DEFAULT DOES NOT MOVE. Both shapes are established here — 29 of the last 80
commits have two parents, and `--subject` exists to give those the conventional
`Merge harbor#N: …` title — so which one this repo should prefer is a convention
decision for the operator, not a side effect of a bug fix. What changes is that
the other two are now reachable, and that the chosen one is PRINTED: a strategy
nobody can see is one nobody notices is wrong.
```

## bin/gate-merge-check.sh, lines 91-96 (before this edit)

```text
`--subject` EXISTS BECAUSE OF THE FIRST REAL USE. Without it `--merge` produces
GitHub's default "Merge pull request #N from <branch>", and this repo's history
is "Merge harbor#N: <what it does>". A gate that costs you the commit
convention is a gate people route around, and a gate nobody uses enforces
nothing — which is the same "a rule with no mechanism is a wish" trap this
whole tool exists to avoid falling into.
```

## bin/gate-merge-check.sh, lines 100-104 (before this edit)

```text
ONE STRATEGY, AND A SECOND ONE IS REFUSED rather than silently overwriting
the first. `--squash --rebase` is a caller who does not know what they want,
and learning that from gh's error AFTER the backstop has already run is
learning it too late — the check would have passed and the merge would then
fail on argument parsing, which reads like the gate broke.
```

## bin/gate-merge-check.sh, lines 131-156 (before this edit)

```text
ONE NAME, TWO MEANINGS — and only one of them can be right here. This file
documents HARBOR_SCOPE_REPO as `owner/name`; bin/drift-renew-check.sh:38 uses the SAME
variable as a FILESYSTEM PATH (`REPO="${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}"`) and its
header tells the operator to set it that way. Measured 2026-08-13 with the
renew-check spelling exported:

  HARBOR_SCOPE_REPO="$HOME/harbor" sh bin/gate-merge-check.sh --protection
  -> PROTECTION ABSENT  $HOME/harbor/main is reachable and carries no rule

Wrong, on the one question this file exists to answer. `gh api
repos/$HARBOR_SCOPE_REPO/branches/main/protection` 404s, and the 404 arm
below correctly means "reachable, no rule configured" — so a nonsense repo id
is indistinguishable from a real lapse. The asymmetry is what makes it a
defect rather than a nuisance: renew-check STANDS DOWN and says so when the
value is the wrong kind, while this file returned a confident wrong answer
about whether the merge gate still exists.

So VALIDATE THE SHAPE rather than rename. Renaming would break the operator's
muscle memory for whichever tool lost, and both headers already document their
own meaning; what was missing is a refusal when the value cannot possibly be
what this file needs. `owner/name` is exactly one slash, no leading slash, and
no whitespace — a path fails all three.

AND FALL BACK TO THIS SCRIPT'S OWN CHECKOUT, because /harbor-merge runs from
whatever cwd the session is in and `gh repo view` needs to be inside a git
remote. Same shape as bin/status-generate.sh:80: the script knows where it lives.
```

## bin/gate-merge-check.sh, lines 181-186 (before this edit)

```text
The three answers are genuinely different and only one of them is fine.
  200  rules exist — report which contexts, so a TYPO is visible too. A
       required context naming a check nobody reports never goes green and
       makes the branch permanently unmergeable, silently.
  403  the plan no longer allows protection on a private repo. THE LAPSE.
  404  the endpoint is reachable and no rule is configured.
```

## bin/gate-merge-check.sh, lines 217-219 (before this edit)

```text
UNKNOWN IS NOT OK. Offline, unauthenticated, rate-limited — none of them
are evidence that the gate is up, and reporting them as fine is how a
backstop becomes decoration.
```

## bin/gate-merge-check.sh, lines 252-253 (before this edit)

```text
Run from a checkout with no list handed in, the rows are core's then the private layer's (gate-required-generate.sh, harbor#1149).
An overlay that does not compose leaves core's rows alone, and says so: a repo with no row has no local gate, which refuses.
```

## bin/gate-merge-check.sh, lines 273-276 (before this edit)

```text
`gh pr checks` exits non-zero when anything is not passing AND when nothing has
reported yet; both must refuse, so the exit status is not the signal — the rows
are. Captured rather than piped so a failing exit does not end the script under
`set -e`.
```

## bin/gate-merge-check.sh, lines 282-284 (before this edit)

```text
The required set is read separately so each row can be LABELLED. A refusal that
does not say whether the red check actually blocks the merge sends the reader
to the settings page to find out.
```

## bin/gate-merge-check.sh, lines 307-309 (before this edit)

```text
`skipping` is gh's word for a job that did not run. It is not a failure and
must not be treated as one, or the tool refuses every ordinary PR the
moment a conditional job exists — CONSTITUTION §2.11.
```

## bin/gate-merge-check.sh, lines 312-314 (before this edit)

```text
on — but it is labelled, because it is a re-run and not a failure
(harbor#675). bin/ci-lost-job.sh owns the read; a link that is not an
Actions job, or an annotation it cannot read, leaves the row unlabelled.
```

## bin/gate-merge-check.sh, lines 330-334 (before this edit)

```text
A REQUIRED CHECK MUST HAVE REPORTED. Missing is not a pass: `gh pr checks
--required` lists only the contexts that exist, so a required check not yet
created reads as "all present checks green" (harbor#1073). Local gate: the
listed names, and `skipping` is no pass either — a listed check is a relay
that runs every time. GitHub gate: its contexts; GitHub itself scores skipped as met.
```

## bin/gate-merge-check.sh, lines 353-355 (before this edit)

```text
NO ROWS IS NOT A PASS. It is the state a PR sits in before anything has
reported, and it is also what a repo with no protection looks like — the
case this tool exists for. Either way there is no verdict to merge on.
```

## bin/gate-merge-check.sh, lines 360-370 (before this edit)

```text
ROWS > 0 and nothing is REQUIRED. That is TWO different situations and a
refusal that cannot tell them apart is not actionable:

  the branch carries no rule          → nothing gates this merge, ever
  the rule exists, nothing reported   → the required run has not got there

`gh pr checks --required` returns empty for both, so the branch rule itself
is the tiebreaker. Measured against #158 while its run was still queued: the
first draft of this arm reported "nothing gates this merge" about a properly
protected branch, which is exactly the kind of confidently wrong refusal that
gets a gate switched off.
```

## bin/gate-merge-check.sh, lines 399-403 (before this edit)

```text
THE OVERRIDE GOES IN THE MERGE COMMIT, not only on the terminal. A warning
printed at the moment of the merge is gone as soon as the scrollback is, and
the question a reader asks six weeks later — "was this merged red, and did
someone decide that?" — is answerable only from the history. `git log` is the
one place that cannot be lost.
```

## bin/gate-merge-check.sh, lines 406-418 (before this edit)

```text
── A REBASE CANNOT CARRY THE RECORD, SO IT IS REFUSED (PR #270 review) ────
The override is only worth anything because it survives the scrollback, and
it survives by riding in a commit body. Read out of the installed
`gh pr merge --help`: `--body` is "Body text for the merge commit", and
`--rebase` replays the existing commits onto the base — it creates no merge
commit at all. So `--force --rebase` printed the promise and wrote it
nowhere: the one path where the guarantee matters most is the one where it
silently evaporated.

REFUSED RATHER THAN DEGRADED. Merging red is the operator's call to make;
making it and leaving no trace is not, and a warning that the trace was
dropped would be read past. `--squash` is fine — a squash produces a commit
and `--body` lands in it — so this refusal is exactly as narrow as the defect.
```
