---
name: doc-deliverable-contract
description: "Before writing anything a person outside this session will read — a client thread reply, a ticket comment, a recommendation, a proposal — restate the contract as your own constraint: the verb in the ask and what it licenses, the audience and therefore the language, and the word ceiling. Then hit the five moves — locus, elimination, ownership, their currency, termination. USE WHEN replying to a client or account team, answering a thread, writing a recommendation or proposal, drafting a ticket comment, sending findings to anyone, or when a correct analysis needs to become a usable answer. NOT FOR the investigation itself (casefile), or the durable map (topology)."
argument-hint: [what you are about to send, and to whom]
---

# doc-deliverable-contract

## Ideal state

**The analysis is right and the reply is usable.** Both, in the same message.
When this skill has done its job the reader gets one object to change, one
alternative already rejected, a named owner for every action, the impact in
their own terms, and a decision to make — in their language, short enough to
forward without editing.

Two rebukes from the technical department, on two different clients, were about
volume and not accuracy. **Being right is the cheap half.**

## Where this came from

This was `topology`'s §"Deliverable contract" and §"Register" until 2026-08-29.
It moved because it is not topology and never was: a client-communication
standard living inside a mapping skill is advertised by that skill's description,
which promises a map. `EVALS/DS-1-why-answers-diverge.md` measured six of six
agents declining to load `topology` on a task it named — and all six then failed
this axis, which lived in the file they did not open.

**The prose below is moved verbatim, not rewritten.** Every paragraph was bought
by a named, dated incident, and rewriting it would destroy the audit trail that
says which fixture retired which failure.

## Make the contract bind — restate it in the turn, or it will not

**Measured, not asserted.** In the third-party-conversion eval (EV-1) in the data-estate repo (resolved through the repo registry), run 2, four arms carried an identical
120-word budget inside this skill. What varied was only where the constraint was
repeated:

| Where the budget was stated | Words written |
|---|---|
| in this skill only | 247 |
| in this skill, form constrained instead | 237 |
| restated in the request | **118** |
| restated as a failure condition | **92** |

A rule in a background document is decoration. The same rule inside the task binds.
This generalises past length to every contract here — verb reading, language,
audience.

**So the first line of any deliverable work is to restate the contract as your own
constraint**, before drafting: the verb in the ask and what it licenses, the
audience and therefore the language, and the word ceiling for this specific reply.
Then write to it. An agent that skips this step will read the rules below,
agree with them, and violate them anyway — which is exactly what happened to the
author of this file, repeatedly, on the day it was written.

## Deliverable contract — this has failed twice, in writing

**Read the verb in the ask, and obey it.** "Peržiūrėti", "review", "check", "are
we tracking X" license a **report**. They do not license a container change. On
one client the request was two questions and no mandate; container edits were shipped
anyway, and the technical department's first response was to ask why. A correct
answer delivered as an unrequested change is a failed deliverable.

**Write for the thread, not for the file.** Most recipients of a client thread are
not technical. Two separate rebukes from the technical department — 2026-07-30 on
one client and 2026-08-06 on another — were about volume, not accuracy: *"Ar tikrai
buvo būtina pateikti tiek daug AI generated / tech. teksto?"* and *"there is too
much text."* Both times the analysis was right and unusable.

**Language follows the audience, not the analysis.** Internal Lithuanian threads
get Lithuanian. English is for text explicitly destined for the client's own
developers, and only when someone has said so.

So: the evidence and the reasoning go in the `TOPOLOGY.md`, which is where depth
belongs and where nobody is forced to read it. What goes in the thread is the
answer, the recommendation, and what is needed from whom — in the thread's own
language, short enough that a project manager forwards it without editing.

### The five moves, which cost nothing and are the whole difference

**Measured in `EVALS/DS-1-why-answers-diverge.md` in the data-estate repo (resolved through the repo registry), and this is the sharpest result the evals have
produced.** The technical department answered the same object twice, 95 minutes
apart. The first reply scored 2/7 on the axes below; the second scored 7/7. **No
new measurement was required for any of the five it gained.** They are a format,
not a discovery, and they are available on any draft at any moment:

1. **Locus** — one object to change, located precisely enough to act on: the
   admin click path, the id, the file. Not three co-equal objects, not a
   description.
2. **Elimination** — reject at least one plausible alternative and say why it
   fails. Presenting options is not advice.
3. **Ownership** — every action carries a party. Us / the client / their
   developer / a third party.
4. **Their currency** — the impact in the reader's terms. "Campaign optimisation
   is unaffected", "you would get a step count you already have". Not coverage
   percentages.
5. **Termination** — end on a decision the reader must make or a message they
   must send. Not on a finding, not on a menu. And name what is **not** covered.

Six independent agents handed the same facts produced all five spontaneously and
scored 6/7. So this is not a capability you lack — it is a step you skip while
producing evidence instead.

### The sixth: it must read COLD, and this applies to every surface

**The reader has not been in this session.** They have not seen the probe output,
they do not hold the id in their head, and they will not open a second document
to find out what a word means. **Anything a person outside this session opens —
an HTML report, a chart or diagram, a chat message, an email, a ticket comment —
carries its own context or it does not land.** The five moves above are about
what the answer SAYS; this one is about what it ASSUMES, and a reply can score
5/5 on the first and still be unreadable.

The three failures, all of them cheap to fix and none of them visible to the
author, who has the context and therefore cannot feel its absence:

- **A bare identifier.** `123456789` is an ad-platform customer id, an analytics property
  and a transfer config depending on which line you are reading. Say WHICH, and
  say where it was read from — the surface, the account or project, and the
  identity that saw it. A reader who cannot tell which console to open cannot
  act, and treats the whole report as noise. `reconcile-estate.sh` prints the
  type and the origin on every row for exactly this reason, and its self-test
  asserts both, because a convention with no mechanism is a wish.
- **A number with no comparison.** "2% of spend" lands; "72.02 EUR" does not,
  until it sits beside the 16,025.59 EUR it should have been.
- **A picture with no text.** A diagram cannot be grepped, diffed, quoted in a
  ticket or read by someone on a phone, and its defects are invisible in its own
  output. **Every generated diagram gets a markdown companion, written FIRST** —
  see `topology-diagram.sh`, which emits the lookup document before it renders
  and then checks the drawing against it.

**The test is one question, and it is answerable without asking anybody: could a
competent colleague who has not seen this thread act on this, alone, on their
first read?** If answering needs a second document, the deliverable is not
finished — it is a set of notes with a covering sentence.

### Register: the ask picks it, you never do

Two registers exist in the house corpus, and both are legitimate:

| Kind of reply | Words | What it must carry |
|---|---|---|
| **Routine** — a question in a thread, a view, a direction | **≤ 120**, median 79 | the five moves, nothing else |
| **Formal proposal** — asked for as a proposal | **≤ 350** | the five moves **plus** specification, ownership table, timing |

**You do not choose which one you are in. The ask does.** A question in a thread
is routine even when what you found is large. If a draft needs the proposal
register and nobody asked for a proposal, that is a question for the operator
*before* drafting.

An earlier version of this file said "the ceiling is 120 words, there is no
second tier" — that was wrong against the corpus: the single best message in it
is 300 words. But the reason it said so is still live. An agent given a tiered
budget restated it faithfully, judged its own draft to qualify for the higher
tier, and shipped 248 words; an agent given one number with no exception shipped
92 and lost nothing. **A tier you may grant yourself is an escape hatch and it
will be taken, in good faith, with a reasoned justification.** So the tier is
real and the self-promotion is not.

**Length is a symptom, not the disease.** Also measured in DS-1: a 191-word reply
scored the same as a 922-word one and beat a 1,150-word one. Cutting words
without adding the five moves buys nothing. Add the moves first; the length
falls out. Surplus evidence goes in the map, where nobody is forced to read it.

## What this does NOT do

| what you need | load |
|---|---|
| the investigation, and the order the probes run in | `casefile` |
| the durable map where the surplus evidence goes | `topology` |
| the ticket's own title, body and tag standard | the tracker skill |
| sending the thing once it is written | `mail-cal` |
| a **multi-finding status mail** a colleague forwards onward — section set, `P:`/`S:` items, ~500 prose words, Lithuanian register | `mail-cal` → Draft shape **wins over the tiers above** |

## Output

The draft, at the register the ask picked, with the five moves present and the
restated contract visible in your working text before the draft existed. If you
wrote past the ceiling, say which register you took and why — a self-granted tier
is the measured failure mode, so an undeclared one is the defect.
