# mail and calendar verbs — gmail-read, gmail-write, gcal-read, gcal-write

One register for the four mail and calendar CLIs (harbor#1419), the same row shape as `git.md`. Reading is free;
`gmail-write` can only draft (it has no send, and `discard` deletes only the caller's own drafts); `gcal-write` is
the only thing on the box that can write a calendar, so every verb of it asks: the approval gate is a prompt, not a
reminder.

**Nothing restates these rows.** `bin/admission-deny.sh` builds the allow and ask rules from the rows marked `allow`
and `ask` (through `bin/gate-verbs.sh rules`), and `bin/admission-remove.sh` takes them back out.
`tests/admission/verbs/registers.test.sh` fails when a row and its derived rule disagree.
Actor lookup for a planner: `sh bin/gate-verbs.sh --actor gcal-write add <title>` (see `gh.md`).

## Columns

The columns of `gh.md`: spelling, class (`read`, `write`, `gated`), perm (`builtin`, `allow`, `ask`, `deny`,
`classifier`), actor (`app`, `operator`), instead.

## Reads

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gmail-read labels *` | read | allow | app | |
| `gmail-read search *` | read | allow | app | |
| `gmail-read read *` | read | allow | app | |
| `gmail-read auth *` | write | classifier | operator | one-time OAuth consent, which opens a browser: the operator's |
| `gcal-read calendars *` | read | allow | app | |
| `gcal-read agenda *` | read | allow | app | |
| `gcal-read search *` | read | allow | app | |
| `gcal-read auth *` | write | classifier | operator | one-time OAuth consent, which opens a browser: the operator's |

## Drafts: allowed, never sent

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gmail-write new *` | write | allow | app | a draft, never a sent message |
| `gmail-write reply *` | write | allow | app | a threaded draft; it is refused when a reply already went out, and `--anyway` overrides that, so check the thread first |
| `gmail-write drafts *` | write | allow | app | |
| `gmail-write discard *` | write | allow | app | deletes the caller's own drafts, never a real message |
| `gmail-write auth *` | write | classifier | operator | one-time OAuth consent, which opens a browser: the operator's |

## Calendar writes: ask

| spelling | class | perm | actor | instead |
|---|---|---|---|---|
| `gcal-write add *` | write | ask | app | |
| `gcal-write edit *` | write | ask | app | `edit` patches in place and keeps guests and reminders; delete-then-recreate re-sends every invitation |
| `gcal-write delete *` | write | ask | app | |
| `gcal-write auth *` | write | ask | operator | one-time OAuth consent, which opens a browser: the operator's |
| `gcal-write *` | write | ask | app | the catch-all: a verb added later asks until it has its own row |
