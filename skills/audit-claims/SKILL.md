---
name: audit-claims
description: "A fresh-context verifier checks each claim of an answer against its source before it ships. USE WHEN an answer carries a number, an exists/absent, a recommendation or a done, or leaves the session. NOT FOR a code diff (audit-review-fanout)."
architecture: decision-check analysis research
---

# audit-claims — a second reader who did not write the answer

**Done looks like:** every claim in the answer that ships was marked SUPPORTED by a verifier
that re-opened its source. An unsupported claim was either cut or says "not verified" in its own
sentence. A contradicted claim was corrected from the verifier's quote. The reply ends with one
line: `claims: N checked, S supported, U cut or marked, C corrected`.

Why a second reader: a writer re-reading their own answer finds what they meant, not what they
wrote, and judges favour their own output (research cited in harbor#542). A reader with a fresh
context gets the claims and the sources and nothing else, so it checks the text. It lowers the
error rate and certifies nothing: the evidence is still the writer's to produce (CONSTITUTION №2).

**Architecture:** this skill is the `decision-check` architecture of `contracts/agent-architectures.tsv`
(one `verify` agent, the parent as producer), and the verify step of `analysis` and `research`.
The register holds the roles, tiers and stop rule; this file holds the method.

## When it is required

| Required | Not required |
|---|---|
| A number, a count, a date, a version | A reply that relays one tool's output verbatim |
| A yes/no or exists/absent about a system: **negatives most of all**, because "there is no X" closes on one missed search | A question back to the operator |
| A recommendation or a decision brief | An acknowledgement |
| A "done", "merged", "deployed" | Work in progress that is not yet an answer |
| Anything leaving the session: a client reply, a ticket, a PR body, a report | |

Skipping a required check, for time or cost, is allowed only when the reply says so in words:
"not independently verified".

## 1. The claim sheet

Write it to a file in the scratchpad before spawning anything. One line per **atomic** claim (one
subject, one predicate: "the snapshot is 733c498f" and "it lags 14 files" are two lines), each
with its source: `file:line`, a read-only command to re-run, a URL, or an issue or PR number. A
claim with no source goes in as `source: none`. That is the writer admitting it, and it is not
the verifier's job to rescue it.

## 2. The verifier

One Agent call, `subagent_type: general-purpose`, `model: opus`, `effort: high`: the `verify` role
in `contracts/agents.tsv`, whose row goes into the brief. **Never a fork:** a fork inherits the
writer's context, and its blind spots with it. A rule that lives only in a skill is not followed,
so the brief restates every one of these:

- the claim sheet's path; read-only, change nothing;
- re-open every source yourself: read the lines, re-run the command, fetch the URL. A quote the
  writer pasted is a claim, not evidence. Never re-run a command that writes (a deploy, a push, a
  `gh` mutation): read its log or the remote state instead;
- for a negative claim, search for the thing under more than one name and in more than one place
  before calling it SUPPORTED;
- judge truth only: not style, not completeness;
- reply with only a JSON array `[{"claim", "verdict", "evidence", "source"}]`, where `verdict` is
  SUPPORTED, UNSUPPORTED or CONTRADICTED and `evidence` is the quoted line or output.

## 3. Apply the verdicts

- **SUPPORTED:** keep it.
- **UNSUPPORTED:** cut it, or keep it with "not verified" in the same sentence.
- **CONTRADICTED:** replace it with what the evidence says. If that changes the conclusion, the
  reply leads with the new conclusion.

Never argue a verdict down in prose. If you think the verifier is wrong, add the source that
proves it to the sheet and run the verifier again on that claim.

## Limits

- **Same model, shared blind spots.** A claim that both writer and verifier get wrong stays
  wrong.
- **It checks what was written, not what was left out.** An omission passes.
- **Not yet measured.** harbor#1478 records the trial against past answers known to be wrong and
  known to be right. Until that result exists, this is a method, not a guarantee.
