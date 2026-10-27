# The access card - the format of the access register

**Seam:** core ships the format and the checker; the cards are private data (harbor#1149, `CONTRACTS/private-layer.md`).
A card says how to reach one system and as which account. It names accounts, so it lives in
`harbor-private/access/<system>.md` and core holds none.

`sh bin/roots.sh --access` is the one resolver of that directory: `$ACCESS_DIR` when set, else
`<private>/access`. With no private layer it prints nothing on stdout, says why on stderr, and exits 1. Every reader
turns that into a plain "no access register" and never reads or passes against an empty path:

| Reader | With no register |
|---|---|
| `skills/access-ledger/bin/check-routes.sh` (any mode without an explicit `[dir]`) | exit 2, "NOTHING was checked and this is not a pass" |
| `skills/topology/bin/check-topology.sh` | skips resolving a map's card citations and says so on stderr |
| `context-rules/user/access-route.sh` | silent, exit 0 (an advisory pointer; it fails open like every injected note) |
| lint `doc.urls-cited` | "skipped: no private layer" |

The floor (`guard-*`, `floor-*`) never reads the register.

## `routes.tsv`: which card a failing command points at

`context-rules/user/access-route.sh` is the note that quotes a card when a command fails with an auth error. It ships the
mechanism and no table: which command or host belongs to which card names systems, so the table is
`<access>/routes.tsv` (private data, harbor#1149; the card files stay `*.md`, this one is not a card).

    pattern <TAB> card

- `pattern` is an extended regular expression (`grep -E`) matched against the whole command. `@B@` stands for a word
  boundary before a CLI name, so `gh ` does not fire inside "high " nor `cu ` inside "focus ". A pattern holds no TAB.
- `card` is the file name without `.md`: letters, digits, dot, dash, underscore, and not starting with a dot.
- The first matching row wins, top to bottom, so specific rows go above general ones. `#` lines and blank lines are skipped.
- No table, no matching row, or a row naming a card that does not exist is silent: a dead row costs a missed
  pointer, never a failure. Nothing yet checks the table's cards against the register, so a renamed card leaves a dead row until a
reader notices.

## A card

One file per system, `<system>.md`, kebab-case. The fields sit in an indented block under the H1, one `name:` per
line; prose below the block is free-form and unchecked. `check-routes.sh` reads the field list out of its own
`REQUIRED_FIELDS`, which is the definition; this table explains it.

| Field | Says |
|---|---|
| `identity` | the account the vendor authorises, never the role-directory label (a bare label is refused) |
| `account` | repeated, one per account that touches the system: `<account> \| <use> \| <role held> \| <how to connect>` |
| `via` | the tiers that work today, best first, `>`-separated, in rank order: `cli > api > mcp > browser`; `none` for a system measured unreachable |
| `upgrade` | the tier it could reach and the grant that would get it there, or `none` and why this tier is the ceiling; never below `via` |
| `use` | the first move: an exact command or URL, not a placeholder |
| `check`, `expect` | one command that proves the door opens, and what it must print |
| `role-check`, `role-expect` | reads the role held and what it must show; `none - <why not>` keeps the gap visible |
| `grant` | who can grant the access, and what |
| `owner` | `us`, `client`, `vendor` or `unknown` |
| `reaches`, `cannot` | what it reaches and what it provably cannot; a fully blocked route stays valid, because a measured negative stops the next session re-probing a closed door |
| `verified` | one ISO date; older than `ROUTE_STALE_DAYS` (30) is red |

`<use>` in an `account:` line is one of `primary` (use first; a reachable system names at least one), `fallback`,
`avoid`, `none` (measured: no access) or `never` (must not be used here, whatever it holds). Cells are capped at
`ACCOUNT_CELL_MAX` characters so the generated matrix stays readable.

```
# <system> - <what it is>

    identity: <account> via <how>
    account:  <account> | primary | <role held> | <how to connect>
    via:      cli > api > browser
    upgrade:  none - <why this tier is the ceiling>
    use:      <the first command or URL>
    check:    <a command that proves reach>
    expect:   <what it prints>
    role-check: <a command that reads the role>
    role-expect: <what it must show>
    grant:    <who grants it, and what>
    owner:    us
    reaches:  <what it reaches>
    cannot:   <what it provably cannot>
    verified: YYYY-MM-DD
```

## Routing and precedence

The ladder is **cli > api > mcp > browser**: take the leftmost tier the system offers, and drop one only when the tier
above has actually failed, saying so in the turn. The order is enforced, not advised: a card listing tiers out of rank
fails the gate. Each step down loses a property: the tool's confinement (cli to api), least privilege (api to mcp),
and everything an agent can repeat or log (mcp to browser).

Which account to use is decided in this order: a **shared** account when a colleague must inherit the asset, a
**service account** when it runs unattended, otherwise the **operator's own** account, because an audit log that names
a person is worth more than one naming a mailbox. The per-system answer is the `account:` lines, never a second table.

## Generated files and non-cards

`check-routes.sh --accounts` writes `ACCOUNTS.md` (one column per account) and `--dispatch` writes `DISPATCH.md` (what
each system offers, ranked) into the register. The gate regenerates both and fails a stale one; edit a card, then
regenerate. The files that sit beside the cards and are not cards (`README.md`, `INDEX.md`, `CAPABILITIES.md`,
`ROUTING.md`, `DISPATCH.md`, `ACCOUNTS.md`, `ACCOUNT-PRECEDENCE.md`, `ESCALATION.md`, `register.md`) are listed in the checker's
`not_a_card`.

## Commands

```sh
sh skills/access-ledger/bin/check-routes.sh                # structure: every card carries the fields
sh skills/access-ledger/bin/check-routes.sh --run          # substance: run every check (opt-in)
sh skills/access-ledger/bin/check-routes.sh --accounts     # derive ACCOUNTS.md
sh skills/access-ledger/bin/check-routes.sh --self-test    # prove it goes red before trusting green
```

A card never holds a secret: names, roles and the command that proves reach, never a token, key or password.
`register.md` is the identity register that sits beside the cards, [access-register.md](./access-register.md): one entry per account,
role, app, mailbox or token, with a `secret:` reference the one seam, `bin/secret`, checks before it reads or writes a value.
