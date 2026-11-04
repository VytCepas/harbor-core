# cu verbs — the ticket CLI's command shapes, and the forms that ask

One register per CLI under `contracts/verbs/` (harbor#1419), the same row shape as `git.md`. `cu` is the
dispatcher in `cu.sh`: every verb is allowed, because `cu` gates itself (it refuses a duplicate title, a close
with unchecked `## Done when`, a bare comment on a client board). What `cu` cannot judge is its own escape hatches,
so a row asks where a flag overrides one of those refusals. Changing what `cu` itself refuses is out of scope here.

**Nothing restates these rows.** `bin/admission-deny.sh` builds the allow and ask rules from the rows marked `allow`
and `ask` (through `bin/gate-verbs.sh rules`), and `bin/admission-remove.sh` takes them back out. An ask
outranks an allow. `tests/admission/verbs/registers.test.sh` fails when a row and its derived rule disagree.
Actor lookup for a planner: `sh bin/gate-verbs.sh --actor cu <verb> [args]` (see `gh.md`).

## Columns

The columns of `gh.md`: spelling, class (`read`, `write`, `gated`), perm (`builtin`, `allow`, `ask`, `deny`,
`classifier`), actor (`app`, `operator`), instead.

## Reads

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `cu help *` | read | allow | app | |
| `cu whoami *` | read | allow | app | |
| `cu where *` | read | allow | app | |
| `cu lists *` | read | allow | app | |
| `cu config *` | read | allow | app | shows, or creates once, the config file |
| `cu ls *` | read | allow | app | |
| `cu mine *` | read | allow | app | |
| `cu find *` | read | allow | app | |
| `cu members *` | read | allow | app | |
| `cu statuses *` | read | allow | app | |
| `cu show *` | read | allow | app | |
| `cu comments *` | read | allow | app | |
| `cu fields *` | read | allow | app | |
| `cu tags *` | read | allow | app | |
| `cu tpl *` | read | allow | app | prints a ticket-body skeleton, writes nothing |
| `cu naming *` | read | allow | app | |
| `cu body *` | read | allow | app | |
| `cu blockers *` | read | allow | app | |
| `cu plan *` | read | allow | app | |
| `cu tree *` | read | allow | app | |
| `cu pairs *` | read | allow | app | |
| `cu twins *` | read | allow | app | |
| `cu hours *` | read | allow | app | |
| `cu daily *` | read | allow | app | |
| `cu started *` | read | allow | app | |
| `cu doctor *` | read | allow | app | |
| `cu api *` | read | allow | app | GET only by design: the verb has no write path |
| `cu dm *` | read | allow | app | |
| `cu notes *` | read | allow | app | |
| `cu note-read *` | read | allow | app | |

## Writes: allowed, `cu` gates itself

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `cu login *` | write | allow | app | stores the personal token in the Keychain |
| `cu new *` | write | allow | app | refuses a title whose thread already has an open ticket |
| `cu intake *` | write | allow | app | one piece of client work, two linked tickets |
| `cu set *` | write | allow | app | a closing status needs `-m` and checked `## Done when` |
| `cu say *` | write | allow | app | a bare comment on a client board is refused by `cu` itself |
| `cu time *` | write | allow | app | refused on a ticket with a client twin |
| `cu untime *` | write | allow | app | removes one logged entry by id |
| `cu assign *` | write | allow | app | |
| `cu tag *` | write | allow | app | a `client:` tag makes the client twin |
| `cu untag *` | write | allow | app | |
| `cu field *` | write | allow | app | |
| `cu link *` | write | allow | app | |
| `cu unlink *` | write | allow | app | |
| `cu attach *` | write | allow | app | |
| `cu note-doc *` | write | allow | app | |
| `cu note *` | write | allow | app | |
| `cu note-set *` | write | allow | app | replaces a page body, and the service keeps no page history |

## Gated: the forms that ask

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `cu say *--done*` | gated | ask | app | the only comment a client board takes besides `--ask`: it tells the client the work is finished |
| `cu say *--ask*` | gated | ask | app | a request of a named person on a client board; `cu` prints a notice because the operator has to be told |
| `cu set *--anyway*` | gated | ask | app | `--anyway` overrides the refusal to close with unchecked conditions; check them instead |
| `cu time *--anyway*` | gated | ask | app | `--anyway` overrides the refusal to log on a ticket with a client twin; log on the client ticket |
| `cu new *--new-anyway*` | gated | ask | app | overrides the duplicate-thread refusal; add a condition to the open ticket instead |
| `cu intake *--new-anyway*` | gated | ask | app | as above |
