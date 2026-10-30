# The credential boundary — why the identity is the wall and the rule is the warning

Recorded 2026-07-31 from [harbor#57](https://github.com/VytCepas/harbor/issues/57),
where the policy and its reasoning had been sitting in an issue while the tools that
implement it — `bin/gcx`, `bin/gtm`, `skills/gtm` — landed in the tree with no
document naming what they are for.

## The rule that does not bend

**No agent changes an IAM binding or a GTM publish permission. Ever.**

Operator decision, 2026-07-29. What makes it binding rather than cautious is *who
else is affected*: **the cloud identities are shared with other people.** A binding
change is therefore not a change to this operator's access — it silently changes what
colleagues can do, without their knowledge or consent.

That is not a blast-radius judgement an agent is positioned to make at any confidence
level, and *"the operator asked"* does not fix it, because the affected parties are
not in the conversation. An agent that is certain is still an agent deciding for
absent third parties.

## Why a guard cannot be the answer here

Both guard corpora say it of themselves. [docs/explanation/admission-baseline.md](./admission-baseline.md) puts it as *"the
real security boundary remains credential separation and the OS sandbox, exactly as
project-init's `prod_guard` says of itself."*

A regex over a command string **raises the cost of an accident**. It cannot stop a
determined path, and it cannot stop a spelling nobody modelled. Three measured gaps
in `prod_guard`'s deny table make that concrete rather than theoretical: it catches
`gcloud … delete` but **not** `gcloud storage rm -r`, **not** `bq rm -r -f <dataset>`,
and **not a single IAM-mutation verb**. Each is one unmodelled spelling away from the
same outcome.

An identity without `bigquery.datasets.delete` has no unmodelled spelling.

**A second instance of the same lesson, measured 2026-07-30** (harbor#61): B1's
`Edit(//**/.github/workflows/**)` deny — described in two places as the control that
makes keeping `workflow` scope on the gh token safe — binds the **file tools only**.
`Edit` on a workflow file is refused; `git apply` on the same file succeeds seconds
later, because Bash is mediated as a command surface rather than a path surface. The
rule was real and its coverage boundary was narrower than the sentence describing it.
Identity would not have had that gap.

So the order is: **the identity is the wall, the rule is the warning.** Defence in
depth, with the load-bearing layer named correctly.

## What the tree already implements

- **`bin/gcx`** gives per-role `CLOUDSDK_CONFIG` directories under
  `~/.config/gcloud/identities/`, nested inside the prefix `permissions.deny` already
  covers, so adding an identity needs no deny edit. The **ambient** default is
  deliberately the lower-privilege one, so a forgotten role selector lands on the
  harmless identity rather than the powerful one.

  **A role name is a label; only the account carries authority — and the two drift
  silently.** Found 2026-07-31: `gcloud auth login` run with `CLOUDSDK_CONFIG`
  pointed at a role dir **adds a second account to that dir and makes it active**.
  A login intended for `tools@` left `analytics@` active in the `tools` dir, and
  every subsequent `gcx tools …` ran as `analytics@` while still printing
  `role=tools`. Nothing in the output said so, and an hour of read-only work went
  out under an identity nobody had chosen. On the project in question *both*
  accounts happened to be `roles/owner`, so the privilege ordering above did not
  hold there either — the ambient-is-lesser argument is a property of the accounts,
  not of the mechanism, and must be re-checked per project.

  So gcx now prints `role=X account=Y` on every invocation, and a role dir may
  declare `expected-account`, which it refuses to run against a mismatch (exit 78,
  naming both accounts and the fix). Disclosure is unconditional; the pin is
  additive so unpinned roles do not start failing closed. `GCX_QUIET=1` silences
  the banner but **not** the pin — a quiet flag that also disables enforcement is
  how a control gets switched off by accident, and `tests/cli/gcx-test.sh` pins exactly
  that case. Two traps worth naming: the pin is inert until an
  `expected-account` file actually exists, and removing a stray account from a role
  dir must **never** use `gcloud auth revoke` — that revokes server-side and kills
  the same account's credential in every other role dir.
- **`bin/gtm`** is read-only by construction and mints its token into an anonymous
  pipe — never stdout, never argv, never disk.
- **`skills/gtm`** carries the prohibitions as ambient text, which is why it stays an
  ambient skill while capability skills were demoted to invoked-only: an unloaded
  rule is not a rule.

None of that is the boundary. All of it is the warning layer, correctly built.

## What only humans can do, and what is still undone

These are the boundary, and every one of them is a **human** task. harbor#57 holds
the live checklist; this file records why it is not an agent's to execute:

1. **BigQuery** — deny the everyday `gcx` identity `bigquery.tables.delete` and
   `bigquery.datasets.delete` on client production datasets; keep destructive rights
   on a role that is not the ambient one.
2. **GCS** — the same split for `storage.objects.delete` / `storage.buckets.delete`.
3. **GTM** — container **Publish** on a human account only. No identity reachable
   from an agent session holds Publish. This is what actually satisfies "nothing gets
   published without my click": a Bash-layer rule cannot, because a publish is an
   HTTPS call and `PreToolUse(Bash)` sees only `curl`.
4. **The service-identity question** — if agent-driven work needs any write path to
   production, it belongs to a dedicated service account with a named, reviewed role,
   not to a shared human identity whose permissions are load-bearing for colleagues.

## The downscoped-token route — measured, and closed (harbor#194 item 5)

The strongest agent-side lever *in principle*, and the reason harbor#194 listed it
above building more rules: exchange the ADC token via STS for a downscoped one
carrying a **Credential Access Boundary**, so the *token* cannot delete regardless
of the identity's IAM. No IAM change, no owner change, no effect on colleagues —
the "identity is the wall" principle applied at a layer this box fully controls.

**It does not exist for BigQuery.** Google's IAM documentation states it flatly:

> Credential Access Boundaries are only available for Cloud Storage. Other Google
> Cloud services don't support this feature.

— <https://docs.cloud.google.com/iam/docs/downscoping-short-lived-credentials>

So the route is closed for item 1 of the human list above, and open only for item
2, where it would duplicate an IAM split that has to happen anyway. It does not
supersede the confirm-not-block rule, and nothing here should be designed around
it again. **Read from the documentation, not probed:** minting credentials to
measure a limitation the vendor states categorically is cost without an answer,
and this is marked rather than dressed up as a live measurement.

## Bypass mode — the control that was working, now locked rather than promised

harbor#194 measured that the only layer which actually refused a `bq rm`-equivalent
REST `DELETE` was Claude Code's own auto-mode classifier — a model judgement,
absent in bypass mode — and proposed recording "no bypass-mode session while cloud
ADC is reachable" as **policy**. A policy is a wish; this one has a mechanism, and
two:

- `permissions.disableBypassPermissionsMode: "disable"` (SEC-0), which no scope or
  CLI flag can override, so the box cannot enter bypass mode at all.
- `floor_no_human` (`bin/guard-lib.sh`), which escalates an ask-tier cloud verdict
  to a hard **deny** whenever no human can answer the prompt — an autonomous
  `permission_mode`, a transcript under `/subagents/`, or an `agent_type` naming a
  subagent or workflow agent. That closes the gap the policy could not: an `ask`
  issued from a Task subagent auto-approves, which is exactly where an unattended
  agent does damage.

Neither replaces the identity split. Both raise the cost of the accident, which is
all a harness layer was ever able to do.

## Falsifier

If someone demonstrates a destructive BigQuery or GCS path that the everyday `gcx`
identity can still execute after the split lands, the boundary is not in place —
**regardless of what the pattern rules catch.** That is the only test this document
accepts, and it is deliberately not satisfiable by adding another rule.
