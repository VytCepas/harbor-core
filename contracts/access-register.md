# The access register - one list of every identity an agent may use

**Seam:** core ships the format, the reader and the gate; the entries are private data (harbor#1205, harbor#1149,
[private-layer.md](./private-layer.md)). An entry names an account, role, app, mailbox or token, says when to use it
and what it cannot do, and holds a **reference** to its secret. It never holds the secret.

The register is `<access dir>/register.md`; `sh bin/scope-roots.sh --access` is the one resolver of that directory, as for the
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
| `secret` | the **reference** the value is stored under (`[A-Za-z0-9._-]+`), or `none` when no `bin/secret` item holds it: a browser sign-in, a role, or a credential held outside the seam. A token or app with `none` and no `held` is a migration debt, not a second store. A ref is named by one entry |
| `verified` | one ISO date; `harbor access add` writes today |

Optional, and checked when present (the lifecycle, below):

| Field | Says |
|---|---|
| `check`, `expect` | together or not at all. One read-only command that proves the credential works now, and what it must print as backticked literals: the card's `check:`/`expect:` grammar, run by the same classifier (`check-routes.sh --probe`), so a write is refused unrun and a browser check is never a pass |
| `expires` | the calendar date the vendor says it stops working |
| `renew` | one line: where, and as which account, a new value is minted |
| `revoke` | one line: where the old value is retired at its source |
| `rotated` | the day a value was last stored by `add` or `rotate`; written by them |
| `revoked` | the day the entry was retired; written by `revoke`. Its presence, whatever its value, refuses the ref |
| `held` | with `secret: none` only: where the value lives outside the seam, and why that is by design rather than a debt (a CI secret, a per-job or per-runner token, a key the confinement denies to every session). `status` reads it as `held`, not `unmanaged` |

Prose between entries is free. An indented `name:` line must sit inside an entry and name a known field; a typo
(`use_when:`) is red, never read as absent.

## A value never goes in the register

Secret values stay in the Keychain (macOS) or `secret-tool` (Linux, WSL2), behind the one seam, `bin/secret`. "One place"
means one register that points to the store, not one file that holds values: a plaintext store would undo the floor's
egress and leak guards. `harbor access check` is red on any line shaped like a credential
(`contracts/credential-patterns.tsv`), and `add` refuses a field shaped like one.

## bin/secret refuses a ref the register does not name

`bin/secret <verb> <ref>` asks `bin/access.sh has <ref>` first, for every verb that reads or writes a value (`put`, `putfile`,
`adopt`, `import` onto a name, `run`, `withfile`). An unregistered ref is exit 1, a `FAIL` naming `harbor access add` as the fix,
and no store call is made. No reader beside the seam, or a reader that errors, is a refusal: it fails closed. `rm` and `list`
are not gated. No verb prints a value; there is still no `get`.

- **No private layer:** the register is empty, so every ref is refused.
- **Grandfathered refs:** `contracts/secret-legacy-refs.txt` lists the refs the gate still serves with no entry. It held
  the consumers that predated the register until each was registered in the private layer; what remains is not a
  credential (the `deploy.live-verify` probe's absent name, which must pass the gate to reach the store). The list only goes
  down: `harbor access check` names a listed ref that an entry now names. A new ref is never added to it; it is registered.
- The floor (`guard-*`, `floor-*`) never reads the register.

## Commands

```sh
harbor access add <id> --kind K --what T --use-when T --reaches T --cannot T --grant T (--secret REF | --no-secret) \
                       [--value-stdin] [--probe CMD]
harbor access list          # id, kind, secret ref, what
harbor access has <ref>     # 0 registered, 3 grandfathered, 4 revoked, 1 neither
harbor access refs          # the registered refs
harbor access check         # well formed, no credential value; exit 2 with no register, never a pass
harbor access stored        # every item bin/secret holds: registered, grandfathered, REVOKED or UNREGISTERED (exit 1)
harbor access status [-v] [id...]          # stored, alive, in date: what is wrong and since when (exit 1 on a red)
harbor access rotate <id> [--value-stdin] [--locked]  # a new value, kept only if the entry's check passes on it
harbor access revoke <id>                  # refuse the ref from now on, then remove the stored value
```

`add` also takes `--check CMD --expect T`, `--expires DATE`, `--renew T`, `--revoke T` and `--held T` (with `--no-secret`), each one line and scanned
for a credential shape like every other field.

## Lifecycle: one controller for store, renew and retire

The register is the one place a credential's life is managed, so renewing a key is one command and nothing is
hand-edited:

- **`status`** reads; it never writes the register. Per entry, the worst state wins. Red, which exits 1, covers four
  cases: a ref missing from the store, a `check` that fails or times out (30s, `PROBE_TIMEOUT`) or is refused as a
  write, an `expires` in the past, and a revoked ref still stored. A warning is an `expires` within 14 days. A gap,
  which does not exit 1, covers three cases: a stored ref with no `check` (`unprobed`), a token or app the seam does
  not hold and no `held:` explains (`unmanaged`, the migration debt; with `held:` it is `held`), and a stored ref with no `renew`/`revoke` recipe. By default it prints the reds and
  warnings, each with the day it was first seen, then one tally line that counts every state. `-v` prints every
  entry. The first-seen days live in a state file outside git (`$XDG_STATE_HOME/harbor/access-status.tsv`), so a
  standing red reads as old rather than new. The probe's output is never printed, because a failing CLI can echo the
  credential it was handed. Exit 2 when the store or the register cannot be read: that is never a pass.
- **`rotate <id>`** needs the entry's `check`/`expect`. `bin/secret rotate` holds the old value for the length of one
  probe, stores the new one, and runs the check with no stdin and its output discarded. On a pass it keeps the new
  value, dates `rotated:` and `verified:` today, and prints the entry's `revoke` recipe: retiring the OLD value at its
  source is the operator's last step, and outside this box. On a fail or an interrupt it puts the old value back
  through `store()`, proven by sha256, and exits 1. A put-back that itself fails is exit 4 and says so. With no
  readable old value, the new one is removed instead.
- **`revoke <id>`** writes `revoked:` first and removes the stored value second. A failure between the two leaves a
  refused ref, never a live one. `has` returns 4 for a ref any revoked entry names, before the legacy list is read,
  so a grandfathered ref cannot come back through it. `rotate` refuses a revoked entry. A ref is re-issued by deleting
  its `revoked:` line, which is a deliberate edit, or by a new entry.
- **One writer at a time.** `add` and `revoke` take `<register>.lock` (an atomic `mkdir`) and fail after 30s with the
  `rmdir` that clears a lock left by a killed writer; they never break it silently. `rotate` takes it only to date the
  entry after the value is kept, so a busy register costs it the dates, with a warning, never the rotation. `rotate` and
  `revoke` refuse a register that does not parse cleanly, and `revoke` removes the value only once `has` says 4.
- **`--locked`** (`rotate`) stores the new value with `-T ""`, as `secret put --locked` does. Without it the value is
  stored unlocked, so a locked item must be rotated with the flag.
- **Linux:** `secret list` fails loudly on an unreadable macOS keychain. On libsecret, an unreachable Secret Service
  still lists empty. That case is not yet measured, and until it is, `status` reads it as every ref MISSING.
- **Not covered:** a credential with no entry at all. `lint.credential-reads` counts those, and `status` cannot see
  them. Neither can a `check` that passes on a CLI's own cached login while the stored item is bad: write the `check`
  so it reads through the entry's ref.

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

`bin/lint-secrets.sh` (lint `lint.credential-reads`, `docs/reference/checks.md`) counts reads of a credential that do not go through
`bin/secret`: a literal value, a direct `security` or `secret-tool` call, an env variable named `*TOKEN`, `*SECRET`,
`*PASSWORD` or `*API_KEY` in a code line, and an app's id in a code line (a GitHub App id, installation id or client id, a
Google OAuth client id: the identity is a register entry, never a literal in core). A file declaring
`# secret-seam: <why>` in its first 40 lines, or a line carrying `secret-seam:`, is declared.
`contracts/lint-secrets-baseline.txt` holds the count and only goes down; every hit (`--list`) is a consumer to migrate
onto `secret run <ref>` and a register entry.
