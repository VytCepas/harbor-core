# The access register - one list of every identity an agent may use

**Seam:** core ships the format, the reader and the gate; the entries are private data (harbor#1205, harbor#1149,
[private-layer.md](./private-layer.md)). An entry names an account, role, app, mailbox or token, says when to use it
and what it cannot do, and holds a **reference** to its secret. It never holds the secret.

The register is `<access dir>/register.md`; `sh bin/roots.sh --access` is the one resolver of that directory, as for the
[cards](./access-card.md). It extends the card format: the same indented `name: value` block, one block per **entry**
(`## <id>`) instead of one file per system. A card says how to reach one system; an entry says what one identity is.
Cards stay per system; the entry is the identity a card's `account:` line points at.

## An entry

```
## <id>

    kind:     token
    what:     <what it is>
    use-when: <the task it is for, and the one it is not for>
    reaches:  <what it reaches>
    cannot:   <what it provably cannot do>
    grant:    <who granted it, and what>
    secret:   <ref>
    verified: YYYY-MM-DD
```

| Field | Says |
|---|---|
| `## <id>` | kebab-case, `[a-z0-9][a-z0-9._-]*`, unique |
| `kind` | `account`, `role`, `app`, `mailbox` or `token` |
| `what`, `use-when`, `reaches`, `cannot`, `grant` | one non-empty line each, no tab; the card's own words for the same ideas |
| `secret` | the **reference** the value is stored under (`[A-Za-z0-9._-]+`), or `none` when no `bin/secret` item holds it: a browser sign-in, a role, or a credential a tool still reads from outside the seam, whose `what` says where (a migration debt, not a second store). A ref is named by one entry |
| `verified` | one ISO date; `harbor access add` writes today |

Prose between entries is free. An indented `name:` line must sit inside an entry and name a known field; a typo
(`use_when:`) is red, never read as absent.

## A value never goes in the register

Secret values stay in the Keychain (macOS) or `secret-tool` (Linux, WSL2), behind the one seam, `bin/secret`. "One place"
means one register that points to the store, not one file that holds values: a plaintext store would undo the floor's
egress and leak guards. `harbor access check` is red on any line shaped like a credential
(`CONTRACTS/credential-patterns.tsv`), and `add` refuses a field shaped like one.

## bin/secret refuses a ref the register does not name

`bin/secret <verb> <ref>` asks `bin/access.sh has <ref>` first, for every verb that reads or writes a value (`put`, `putfile`,
`adopt`, `import` onto a name, `run`, `withfile`). An unregistered ref is exit 1, a `FAIL` naming `harbor access add` as the fix,
and no store call is made. No reader beside the seam, or a reader that errors, is a refusal: it fails closed. `rm` and `list`
are not gated. No verb prints a value; there is still no `get`.

- **No private layer:** the register is empty, so every ref is refused.
- **Grandfathered refs:** `CONTRACTS/secret-legacy-refs.txt` lists the refs the gate still serves with no entry. It held
  the consumers that predated the register until each was registered in the private layer; what remains is not a
  credential (the `live-verify` probe's absent name, which must pass the gate to reach the store). The list only goes
  down: `harbor access check` names a listed ref that an entry now names. A new ref is never added to it; it is registered.
- The floor (`guard-*`, `floor-*`) never reads the register.

## Commands

```sh
harbor access add <id> --kind K --what T --use-when T --reaches T --cannot T --grant T (--secret REF | --no-secret) \
                       [--value-stdin] [--probe CMD]
harbor access list          # id, kind, secret ref, what
harbor access has <ref>     # 0 registered, 3 grandfathered, 1 neither
harbor access refs          # the registered refs
harbor access check         # well formed, no credential value; exit 2 with no register, never a pass
harbor access stored        # every item bin/secret holds: registered, grandfathered or UNREGISTERED (exit 1)
```

`stored` is the store side of the gate. An item the store holds and no entry or legacy line names is a value
`bin/secret` refuses to every consumer, so whatever reads it is broken while the item still looks present (harbor#1205:
a report's Meta token stored before the gate, in no list, was refused from the gate's merge on). It reads names only
(`secret list`); exit 2 when the store cannot be listed, never a pass. The fix is an entry, or `secret rm` when nothing
reads the item.

`add` writes the entry, **then** stores the value through `bin/secret` (the ref must be registered before the seam admits
it), and puts the old register back if the store fails. The value arrives on stdin with `--value-stdin`, or at
`bin/secret`'s own no-echo prompt on a terminal; it is never an argument. With neither and no terminal, the entry is kept and
the missing value is said. A missing field is asked for on a terminal and is exit 2 otherwise, so a test needs no tty.
`--probe CMD` runs after the store; a failing probe is exit 1 and the entry is kept.

`harbor scope install` creates `register.md` with a header only. A fresh box has no entry, so it can read no credential
until the operator asks for one.

## Credential reads outside the seam

`bin/lint-secrets.sh` (lint `lint.credential-reads`, `CHECKS.md`) counts reads of a credential that do not go through
`bin/secret`: a literal value, a direct `security` or `secret-tool` call, an env variable named `*TOKEN`, `*SECRET`,
`*PASSWORD` or `*API_KEY` in a code line, and an app's id in a code line (a GitHub App id, installation id or client id, a
Google OAuth client id: the identity is a register entry, never a literal in core). A file declaring
`# secret-seam: <why>` in its first 40 lines, or a line carrying `secret-seam:`, is declared.
`CONTRACTS/lint-secrets-baseline.txt` holds the count and only goes down; every hit (`--list`) is a consumer to migrate
onto `secret run <ref>` and a register entry.
