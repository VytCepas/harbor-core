---
name: access-ledger
description: "Which account to use on each system, the role it holds and what it cannot reach: harbor-private/access/ACCOUNTS.md, generated from the route cards; plus the one-ask access ledger. USE WHEN which account, wrong account, 401, 403, permission denied, Reauthentication failed, do I have access, can I reach X, need access, credentials, token, least privilege."
argument-hint: [system or client]
---

# access-ledger

## Ideal state

**One ask, complete, ordered, and derived from a map rather than from
whatever you just tripped over.** When this skill has done its job the operator
receives a single list where every row names the system, the exact permission or
scope, the person who can grant it, what it unblocks, and the cheapest route to
get it — and after the answer comes back, `harbor-private/access/<system>.md` records
what was actually granted and what it actually reaches.

The measure of success is that nobody is asked twice for the same task.

## Why this exists

Drip-fed asks. In one session the sequence was: ask for Stape, receive it,
discover the Shopify dependency, ask, receive it, discover the Shopify *role*
lacks the one page the task needs, ask again. Three interruptions where one
would have done, and each one arrived looking like the plan had changed. Every
row of that ask was derivable from the flow before any of it was requested.

## The ledger contract

A table, most-unblocking first. Per row:

| field | rule |
|---|---|
| System | the vendor or platform, not the feature |
| Exact grant | the named permission or OAuth scope, not "access" |
| Owner | the person or org who can grant it; "unknown" is a finding |
| Unblocks | the specific task or probe that is stuck without it |
| Route | self-service, internal ask, or client ask — cheapest first |
| Fallback | what we can still answer without it, if anything |

The **Fallback** column is what keeps the ask honest. If a row has a fallback,
say so in the ask — an operator who learns that a request was optional stops
treating the next one as urgent.

## The route card — the book, and the reason it is checkable

The ask above is transient. **`harbor-private/access/<system>.md` is the durable half**,
and until 2026-08-29 it was a diary: eleven route documents, not one carrying a
runnable check, and nothing anywhere running them. A `verified:` claim that
nothing re-runs can only age, so the first thing each session did with a route
was re-derive it by hand — the drip-fed ask, one layer down.

Every route file opens with an indented card under its H1. Indented four spaces,
so it renders as a block and greps as fields:

```
    identity: the account the vendor will actually authorise as
    account:  <account> | primary|fallback|avoid|none|never | <role held> | <how to connect>
    check:    one runnable command that proves reach
    expect:   what a working check prints
    role-check: one runnable read of the ROLE held, or `none - <why no machine can>`
    role-expect: the backticked literal the role read must print
    grant:    the named permission or scope held, not "access"
    owner:    us | client | vendor | unknown
    reaches:  what it can do today
    cannot:   what it provably cannot — measured, not assumed
    verified: YYYY-MM-DD, the day `check:` last returned
```

**Those fields are not a new vocabulary.** `owner`, `check` and `verified` are
the `owner`, `probe` and `verified` cells of a `casefile` pack row. A pack that
re-derives reachability per case pays twice for a fact the book already holds;
a book whose fields do not line up with the pack is a book nobody cites.

- **`identity:` is the account, never the role-directory label.** The label is
  what this box chose, the account is the wall, and the two drift silently. The
  checker rejects a bare label.

  **The illustration for this rule had itself gone stale, which is the sharper
  lesson.** `harbor-private/access/README.md` states, measured 2026-08-01, that `gcx tools`
  authorises as a different account than its label — and that mismatch is the example the whole
  directory is built around. Re-run 2026-08-29: `role=tools account=<the tools account>`.
  The label and the account now agree, so the canonical example of drift has
  drifted. **I copied the 08-01 value into this file the same day I wrote the
  rule against trusting undated in-house claims.** The rule stands; the number
  in it did not, and only re-running the command found that.
- **`cannot:` is required, and a fully blocked route stays valid.** A measured
  negative is the half that stops the next session re-probing a closed door —
  The example platform's card reads `reaches: nothing` and passes. A book that only accepts
  working routes loses exactly the rows that save the most time.
- **A system with no card is a finding, not an absence.** `--coverage` names them.

## Which account, and with what role — `ACCOUNTS.md`

**The book used to answer "how do I reach X" and never "what is this account
for".** A card named its identity in one prose line, so knowing whether `tools@`
was the right account, the wrong one, or one that already held more than enough
meant reading every card. The role a card claimed was text nothing re-read: on
2026-09-23 the Flow UI moved the operator's own account from viewer to admin and the card stayed
green, because its check proved the door opens, never who stands in it.

So a card now carries **one `account:` line per account that touches the
system**, and `check-routes.sh --accounts` turns them round into
`harbor-private/access/ACCOUNTS.md`: one column per account, one table per account, and a blank
cell meaning *not recorded*, which is not the same as *no access*.

- **`primary`** use first; a reachable system must name at least one.
  **`fallback`** only when the primary has failed. **`avoid`** holds access but
  is not the account for this. **`none`** measured to reach nothing. **`never`**
  must not be used here, whatever it holds.
- **`role-check:`** reads the role held, and `--run` fails when it changes. A
  role shown only on a settings page is `open <https URL>`, which an agent reads
  in the browser (`BROWSER`, below). Where nothing can read it, the line says
  `none - <why>` so the gap stays on the page instead of looking covered.
- **An access failure points here by itself.** The box pack
  `inject.d/box/45-access-route-pointer.md` fires on a Bash result carrying a
  401, 403, `PERMISSION_DENIED` or `Reauthentication failed` from a system that
  has a card, and names the account that card says to use.
- **The gate fails a stale `ACCOUNTS.md` or `DISPATCH.md`.** Edit a card, then
  regenerate both:

```sh
A="$(sh ~/port/harbor/bin/roots.sh --access)" && cd ~/port/harbor \
  && sh skills/access-ledger/bin/check-routes.sh --accounts "$A" > "$A/ACCOUNTS.md" \
  && sh skills/access-ledger/bin/check-routes.sh --dispatch "$A" > "$A/DISPATCH.md"
```

## Gate

```sh
sh ~/.claude/skills/access-ledger/bin/check-routes.sh                  # structure: does every card exist
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --run            # substance: RUN every check
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --report         # derive the capability table
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --accounts       # derive which account connects to what
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --coverage "$(sh ~/port/harbor/bin/roots.sh --repo estate)"
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --self-test      # it prints its own count; run it before trusting a green
```

`--report` regenerates the "what we can reach today" table from the cards rather
than restating it. A hand-written capability summary is a copy, and copies drift
while still reading correctly (`DOCTRINE/doc-truth.md`).

**The two halves are separate on purpose, and the first one alone is not enough.**
The default gate asserts a card *has* a check; it never runs one. Measured
2026-08-29 on `harbor-private/access/gcloud.md`: its check was `gcx tools true`, which printed
the expected account and exited 0 **while every `gcloud` and warehouse-CLI command on the
same identity was failing `Reauthentication failed`.** A card can be green over a
dead route. `true` exercises nothing, and the probe must exercise the path the
caller does (Helm №2.6). That is the same headings-not-substance gap
`check-topology.sh` documents, and it gets the same answer: a second mode.

**A `--run` pass means the CARD IS ACCURATE, not that the route works.** Meta's
card passes on `Needs authentication` — the route is dead, and the card says so.
A book that only accepted working routes would drop exactly the rows that stop
the next session re-probing a closed door.

**Three verdicts are neither pass nor fail, and all are honest:** `BROWSER` for a
check that is a URL to look at, `MANUAL` for one a person must run (`ssh`, `say`),
and `UNCHECKABLE` for an `expect:` with no backticked literal to match on. Silence
about what cannot be verified is the failure this whole file exists to end.

**`BROWSER` is an agent's job, not the operator's.** A `check:` or `role-check:`
of the form `open <https URL>` is run through Claude in Chrome: open the URL in a
new tab, compare the page with the expectation `--run` prints beside it, and move
`verified:` to today only on a match. Reading is all it licenses:

- **A login wall is the finding.** Never type a password, pick an SSO consent,
  or tick a terms box to get past one; report the wall and ask the operator to
  sign in, then re-run. Continuing into an account the browser already
  remembers, with no password prompt, is not a sign-in.
- **A page that opens is not a page that works.** LinkedIn's Campaign Manager
  opened without a login wall on 2026-09-24 and still reached no ad account (it
  landed on `/new-advertiser`), so an `expect:` names what the page must show,
  not merely that it loaded.
- **Record what the page settled,** such as the account signed in, the role or
  a status, on the card in the same change. The OpenAI Ads account had been
  "unknown" for three weeks and was one menu click away.

**`--run` executes shell out of a tracked, agent-editable file, so it is opt-in
and never the default gate.** Every command is printed before it runs, and a
check that is not a read is refused unrun. The deny-list is proved *harmless* as
well as effective — a fixture using `>/dev/null 2>&1` must pass, because a guard
that blocks ordinary work gets switched off (Helm №2.11).

**Never state the card count here — run the gate.** This paragraph used to read
"Measured 2026-08-29 after the sweep: 12 cards, structure 12/12, substance 10 run
/ 10 passed / 2 manual." Re-measured **2026-09-01**: 10 route files, **zero**
carried a card, and the default gate exited **1**. The sweep either never landed
or was reverted, and for three days this file reported a green instrument that was
red — the exact flattering-drift failure No.2.12 describes, in the document whose
job is to prevent it. A count in prose is a copy; the gate is the source:

```sh
sh ~/.claude/skills/access-ledger/bin/check-routes.sh            # structure
sh ~/.claude/skills/access-ledger/bin/check-routes.sh --run      # substance
```

As of 2026-09-01 exactly one card exists (`gcloud`, passing both modes); the other
nine files are routes without cards. Systems with no route at all — the ad platforms and connectors the registry lists —
are named by `--coverage`, which is also the only trustworthy count.

## Hard rules

- **Never enter credentials, complete an SSO consent, or create an account.**
  Navigate to the login and hand it over. This holds when the operator supplies
  the details and when they say to go ahead.
- **Read-only by default, and prefer scoping the *server* over scoping the
  tool.** A vendor-issued `read_*` token cannot write no matter what runs it; a
  GET-only wrapper is a convention that a future edit can undo. When only the
  weaker option exists, say which one you got.
- **Least privilege even when "everything" was offered.** Widening later is one
  message; un-granting is a conversation.
- **Credentials go to the Keychain and are read inside a wrapper script**, the
  shape `cu` and `stape` use — an inline Keychain read in a session command is
  blocked by the floor, and a token echoed once is a token in a transcript
  forever.
- **Never a token to stdout, never in a URL, never in a repo.** Header auth
  only.
- **An unscoped key is not an upgrade over a UI seat.** If the vendor documents
  no read-only tier, a key carries billing and deletion — say that plainly
  before recommending it, and prefer a restricted seat or sub-user.
- **Purchases and standing config changes are the operator's.** A container, a
  seat, a plan change: present the cost, do not place it.

## Verified gotchas

- **Permission ≠ scope.** A principal can hold Administrator on a property and
  still get `ACCESS_TOKEN_SCOPE_INSUFFICIENT`, because the token was minted
  without that API's scope. Read the error's `reason` before concluding
  anything about rights.
- **Discriminate the failure.** `401` is key-or-region, `404` is path,
  `403 SERVICE_DISABLED` is the API, `403 ACCESS_TOKEN_SCOPE_INSUFFICIENT` is
  the grant. Collapsing these to "failed" sends you after the wrong fix.
- **Google has closed its default OAuth client for sensitive scopes.** An ADC
  login requesting `analytics.readonly` is refused at the consent screen; it
  needs your own client ID or a service account. Isolate any new login in its
  own `CLOUDSDK_CONFIG` role dir so a failure cannot touch a working one.
- **Read the account, never the role-directory label** — a dir named for one
  identity can authorise as another.
- **A role name explains a permission set.** Before escalating a per-page
  denial, find the role: one collaborator role accounts for every gap at once,
  and the ask becomes "add this permission to this role" instead of a list.
- **One credential often reaches many clients.** Landing in an unrelated
  client's production admin is a mistyped handle away — note the blast radius
  in the ledger rather than discovering it live.

## Output

The consolidated ask to the operator, and — once answered — an updated
`harbor-private/access/<system>.md` stating what is held, by which identity, what it
reaches, what it cannot, and the date it was verified. A negative that was
measured is as valuable as a positive: record it so the next session does not
re-probe a closed door.
