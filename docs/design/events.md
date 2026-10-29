# Events — a local bus agents can wait on

**Status:** E1 of the Events milestone (harbor#1043). PR 1 lands the bus: `bin/event-bus.sh`, the
`harbor event` verb, its suites under `tests/event/bus/`, and the `event.retention` row in
[docs/reference/checks.md](../../docs/reference/checks.md). PR 2 adds the producers below (harbor#1051 PR 1 adds the tool and agent ones); the CI waits that
move onto `wait` (PR 3) are not built yet. E2 (harbor#1044), the dispatcher that reacts to events, is
[below](#e2--reacting-harbor1044); it ships inert. Design origin: the operator's research brief of 2026-10-05, adapted here to the
standard names (#949) and to the night-stack contract of 2026-10-06.

**The security floor never depends on the bus.** No guard reads it, and a broken bus cannot fail a
hook, a commit or a CI job.

## The shape

One append-only JSONL file per UTC day, one POSIX `sh` tool, no daemon:

```
producers (hooks, git, runners) ──emit──▶ events/YYYY-MM-DD.jsonl ──▶ wait · since · tail
```

- **Where:** `${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}/`, the date in UTC. Outside every
  synced or pushed tree, because events carry repo names. Dir `0700`, files `0600`.
- **Followers sleep on `tail -F`**, which waits on kqueue (macOS) or inotify (Linux): no polling.
- **Offsets, not acks.** A consumer keeps a byte offset per day file and resumes from it.

Rejected for the bus, from the brief: launchd `WatchPaths` as the trigger (its man page calls it
race-prone and it throttles), SQLite (one writer, no push wake-up from `sh`; the upgrade if atomic
claims are ever needed), NATS JetStream and Redis (a daemon this does not need), ntfy (not a log).

## The record

One JSON object per line, UTF-8, `\n`-terminated, at most 4096 bytes with the newline. Keys in
this order:

| key | value |
|---|---|
| `id` | `<ts compact>-<pid>-<4 hex>`, e.g. `20261006T013000Z-12345-a1f3`. Consumers dedupe on it |
| `ts` | UTC, `YYYY-MM-DDTHH:MM:SSZ` (#1001) |
| `src` | the producer: `hook.stop`, `hook.subagent-stop`, `hook.post-tool-use`, `git.post-commit`, `git.post-merge`, `cli`, `status.obligations`. Default `cli` |
| `kind` | dotted lower case, from the table below |
| `subject` | what the event is about; a terminal event repeats its start event's subject verbatim |
| `repo` | the repo's name, or `""`. Default: the git common dir's parent, so a linked worktree reports its repo, not its worktree directory |
| `cause` | the id of the event that triggered this producer, or `""` (the E2 loop guard reads it) |
| `data` | an object of the allowlisted keys only (the night-stack contract §3a.2): `title`, `link` (https only), `session_id`, `deadline_ts`, `tool`, `closes_on`, `evidence` as strings, `exit` as a number. `emit` parses `--data` with `jq -c` and drops every other key and every value of the wrong type, so command text, file contents and `~/.claude` paths have no key to travel in (DE-16, the constitution's privacy rule) |

**The line cap.** Over-cap `data` becomes `{"truncated":true}`. `--data` that is not exactly one
JSON object becomes `{"invalid":true}` and `emit` warns; with no `jq` on the box it becomes `{}`,
never the unread input. Subject, repo, cause and src that are over the cap together are refused
before they are escaped, so a huge subject costs nothing. Invalid UTF-8 in them is dropped
(`iconv -c`). A torn line is never the fallback.

**A fragment is never glued to.** If a write was cut short (a full disk), the day file ends
mid-line; the next `emit` writes a newline first, so its own line stands alone. Readers print only
lines that start `{"id":"` and end `}`, and step over the fragment; a consumer should still skip a
line it cannot parse.

**One write per event.** `emit` builds the line in one `awk` and appends it with one `printf` to a
file opened `O_APPEND`; a line under the cap fits one stdio buffer, so it leaves in one `write()`.
POSIX does not promise atomic appends to a regular file, so this is a measured property, held by
`tests/event/bus/concurrency.test.sh`. Measured 2026-10-06 on macOS: the shell's own `printf`
(bash 3.2 as `/bin/sh`) tore 1 line in 320 near-cap concurrent emits; the `awk` write tore none.
The suite now runs 12 writers × 50 near-cap emits, where the shell-`printf` append tore lines in
3 runs of 3.

## Kinds and subjects

**The register is [contracts/event-kinds.tsv](../../contracts/event-kinds.tsv)** (harbor#1367): every kind, its shape
(start, terminal or point), its subject and the file that emits it. It replaced the table that stood here, because a
prose table let two presets and the `ci` obligation listen for `ci.job.done` while nothing emitted it. Lint
`event.kind-registered` holds it to the code: an emitted kind with no row, a row whose emitter never names it, and a
preset listening for a kind nothing emits are each red.

A start and its terminal share the subject verbatim, so the obligations ledger (#1050) pairs them
without guessing. `emit` checks only the shape of a kind (dotted lower case), not membership.

## Producers (PR 2)

| producer | fires on | emits | subject | `src` |
|---|---|---|---|---|
| `bin/event-hook.sh` | Claude Code `SessionStart` (not `source=compact`) | `session.start` | `session_id` | `hook.session-start` |
| `bin/event-hook.sh` | Claude Code `SessionEnd` | `session.stop` | `session_id` | `hook.stop` |
| `bin/event-hook.sh` | Claude Code `SubagentStop` | `agent.done` (`data.session_id` = the owner) | `agent_id` | `hook.subagent-stop` |
| `bin/event-hook.sh` | Claude Code `SubagentStart` | `agent.spawn` (`data.session_id` = the owner) | `agent_id` (else `<session_id>:<tool_use_id>`) | `hook.subagent-start` |
| `bin/event-hook.sh` | `PostToolUse` on `Monitor`, `ScheduleWakeup` (not `stop: true`), `CronCreate`, `Workflow`, and `Bash` with `run_in_background: true` | `tool.background.start` (`data` = `session_id`, `tool`) | `<session_id>:<tool_use_id>` | `hook.post-tool-use` |
| `bin/event-hook.sh` | `PostToolUse` on `Skill` | `skill.call` (`data` = `session_id`) | the skill name | `hook.post-tool-use` |
| `bin/event-hook.sh` | `PostToolUse` on `Read` of `*/memory/*.md`, `MEMORY.md` or `INDEX-FULL.md` | `memory.read` (`data` = `session_id`) | the basename | `hook.post-tool-use` |
| `bin/event-hook.sh` | `PostToolUse` on `Bash` whose command's last simple command is `gh pr create` and whose stdout ends in one github.com pull URL | `pr.opened` (`data` = `session_id`, `link`) | `<owner>/<repo>#<n>` | `hook.post-tool-use` |
| `hooks/session-state/session-state.sh` | Claude Code `Stop`, when the session's state changed | `session.state` (`data` = `session_id`, `title`, `evidence`) | `session_id` | `hook.session-state` |
| `hooks/session-state/session-state.sh` | Claude Code `Stop`, when `event.session-save-now` is on and the nudge is sent | `session.save-now` (`data` = `session_id`, `title`) | `session_id` | `hook.session-state` |
| `hooks/post-commit` | `git commit`, `--amend`, a single `cherry-pick` (not a rebase or a multi-commit sequence: those replay commits that already have an event) | `git.commit` | the new sha | `git.post-commit` |
| `hooks/post-merge` | `git merge`, fast-forward or not (not `--squash`) | `git.merge` | the sha HEAD ends at | `git.post-merge` |

- **`session.stop` rides `SessionEnd`, not `Stop`.** `Stop` fires at the end of every turn (measured on
  Claude Code 2.1.291: two `Stop` and one `SessionEnd` in one two-turn session), so wiring it there
  would close a session at every reply. The `src` stays the contract's `hook.stop`.
- **The hook reads ids and nothing else.** It takes `hook_event_name`, `session_id`, `agent_id` and
  `source` from the payload, each checked against `[A-Za-z0-9._:-]` and 128 bytes; a prompt, a command, a
  transcript path or `last_assistant_message` never reaches an event, and `data` carries only §3a keys.
- **Wiring.** `bin/floor-install.sh` copies `event-hook.sh` and `event-bus.sh` into the config dir (not
  content-pinned: nothing depends on them) and wires the hook once per event, standalone and fail-open.
  `floor-uninstall.sh` removes both. The git hooks run where `git config core.hooksPath hooks` is set, as
  for the other hooks (contracts/README.md); a merge commit fires `post-merge` only, not `post-commit`.
- **Off:** `touch <bus dir>/producers.off`; remove it to turn the producers back on.
- **Never a cost to the caller.** Every path exits 0 and prints nothing, with the bus dir unwritable, a
  file in its place, `event-bus.sh` or `library-log.sh` missing, or a garbage payload
  (`tests/event/producer/failsafe.test.sh`). One emit is about 50 ms on the dev box.
- **Bounded.** Reading the payload and the emit each get `HARBOR_EVENT_BUS_TIMEOUT` seconds (default 2,
  1 to 60); a hung `event-bus.sh` is killed with its children, a stdin that never closes is abandoned,
  a closed stdin exits 0, and the hook returns 0 (`tests/event/producer/tools.test.sh`). With `perl` on the
  box the bus runs as its own process-group leader and the kill takes the group, double-forked children
  included; without it only direct children are killed, a documented limit (the real bus does not
  double-fork). The git hooks'
  `hook_event` (`hooks/lib.sh`) has the same bound. `SessionEnd` hooks share a 1.5 s budget in Claude Code
  itself, which a healthy emit is far inside.
- **The tool producers' matcher** is `Monitor|ScheduleWakeup|CronCreate|Workflow|Bash`, so the hook does
  not run on a Read, an Edit or a Grep. Bash is in it because `run_in_background` is not something
  Claude Code's `if` filter can match; the script tests it, and `gh pr create`, itself. Every field it
  reads comes from the region it belongs to: the background flag and the command from `tool_input`, the
  PR URL from `tool_response`, the call id from the end of the payload. A URL written in the command is
  never the PR. `pr.opened` needs both halves (harbor#1114): the `command` key alone, with `gh pr create`
  as its LAST simple command (a quote-aware split on `;`, `&&`, `||`, `|`, newline; so `gh pr create | tee`
  or `gh pr create && cat f` is a deliberate miss, since the output is then not gh's), and the result's
  `stdout` ending in one whole pull URL with no "already exists" in the response.
- **No terminal event exists for a background tool.** Claude Code (2.1.291, hook reference) has no hook
  for a background Bash, Monitor, Workflow or wakeup finishing: the model is told in-band, hooks are not.
  `TaskCompleted` is for agent-team tasks, not these. So `tool.background.done` has no producer; the
  row is closed by the session ending (the fold abandons it on `session.stop`), by the kind's default
  deadline, or by the reconciler. `Stop` and `SubagentStop` payloads carry a `background_tasks` snapshot
  that a later PR could reconcile against; it is not used here. A foreground Bash that Claude Code moves
  to the background at its timeout has `run_in_background: false` and opens no row.
- **The ledger opens a row only for the tools whose lifetime matters** (harbor#1049). With no done event a
  background row closes only at its deadline or with its session, so a plain background Bash read as `⧗149`
  of rows nobody could close. The register's `opens_when` column (`tool=Monitor|Workflow|CronCreate|ScheduleWakeup`)
  makes the fold skip the rest; the bus still records every start, and clearing the cell restores them.
- **`agent.spawn` can fire again for one `agent_id`** (a resumed subagent, an agent-team teammate handling a
  new message); the consumer dedupes on the subject.
- **`agent.done` repeats per `agent_id` too, and the producer cannot tell why.** `SubagentStop` fires on every stop,
  interim ones and resumes included, and also for Claude Code's own internal agents (prompt suggestions, `/btw`)
  that never had a `SubagentStart`. Its payload (2.1.292 hook reference) has no final-versus-interim field:
  `stop_hook_active` only says a stop hook is already continuing the turn. So the producer emits all of them and
  the fold dedupes: the first done closes the row, later ones are no-ops, and a new `agent.spawn` opens it again.
- **Not here:** a `claude agents` dispatch (it is an ordinary Bash call; not told apart from one). A new Claude Code
  producer is one `case` arm in `event-hook.sh` plus one row in `floor-install.sh`'s wiring table.
- **Elsewhere (harbor#1367):** `ci.job.*` from the runner job hook through `ci-governor listen` (or the hook itself on a
  host runner), and `pr.merged` / `pr.closed` from the obligations reconcile, which is what sees GitHub merge a PR.

## The tool

```
event-bus.sh emit <kind> <subject> [--src S] [--repo R] [--cause ID] [--data JSON]
event-bus.sh wait '<grep -E pattern>' --timeout N [--since-offset F] [--consumer NAME]
event-bus.sh since <offset-file> [--consumer NAME]
event-bus.sh tail [N]
event-bus.sh prune
```

`harbor event <verb>` runs the same. Exit codes:

| verb | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `emit` | **always**, printing the id when written; any failure is a `FAIL` + `fix` on stderr | — | — | — |
| `wait` | a match, the line on stdout | — | usage | the deadline passed |
| `since` | the new lines on stdout | the offsets could not be rewritten | usage | — |
| `prune` | every expired file is gone | one survived | — | — |

**The offset file** holds one row per consumer per day file: `<consumer> <YYYY-MM-DD> <bytes>`,
rewritten atomically. A day file with no row is read from its start, so a new consumer replays the
retained history; a day file pruned away drops its row. `since` prints before it advances: a reader
killed mid-read re-reads, never skips (at-least-once), which is why consumers dedupe on `id`.
Consumers may share one offsets file: each rewrites only its own rows, re-reading the others' under
a `mkdir` lock (`<offset-file>.lock`), so none moves another's offsets. One reader per consumer
name: two readers under the same name are not prevented and would read the same lines twice.

**`wait`** scans by offsets, then blocks on a fifo fed by two writers: `tail -F` on today's file
from the byte the scan stopped at, so nothing that lands in between is missed, and one timer for
`min(deadline, next UTC midnight + 1s)`. Every wake rescans every day file by offsets; the midnight
wake re-arms the follower on the new day's file, so a wait spanning midnight sees the new file
within a second; an event written late to the old file is found at the next wake. Without
`--since-offset` it starts at the end of every older file and at the last complete line of today's.
It reads `--since-offset` and never moves it. A `wait` killed with SIGKILL cannot clean up: its
`tail -F` lives on until the next line lands in that file, then dies on the closed pipe.

## Robustness rules, each a test

| rule | where it is held |
|---|---|
| Every wait has a deadline; at it, exit 3 and one line saying what was awaited. A lost event is a report, never a hang | `wait.test.sh` (each wait under a watchdog) |
| Producers never fail callers: `emit` exits 0 on every path, errors to stderr only | `emit.test.sh` |
| A torn last line is never read: `since` and `wait` stop at the last newline and read the line once it is whole | `since.test.sh`, `wait.test.sh` |
| Offset resume: no line lost, none doubled; consumers sharing one offsets file never move each other; the file is replaced, never rewritten in place | `since.test.sh` |
| `--data` cannot add or override a record key, and carries only allowlisted keys of the right type | `emit.test.sh` |
| A line is never glued onto a fragment; invalid UTF-8 never reaches the file; a closed stdout is still exit 0 | `emit.test.sh` |
| A finished `wait` leaves no follower and no timer running | `wait.test.sh` |
| Concurrent emits leave only whole lines, every id unique | `concurrency.test.sh` |
| Retention: a day file dated more than 14 days before today goes; every younger one stays | `prune.test.sh` |
| A wait across UTC midnight follows the new day's file | `wait.test.sh` |
| The bus lives under `~/.local/state/harbor/events/` unless `HARBOR_EVENT_DIR` says otherwise | `emit.test.sh` |

**Retention** is `event.retention` in docs/reference/checks.md. It rides the first `emit` of each UTC day rather
than a schedule, because a recurring job needs the operator's yes and the bus already has a writer
that runs daily; `prune.off` in the bus dir turns it off.

**Test-only clock.** `HARBOR_EVENT_BUS_SKEW=<seconds>` shifts the tool's clock, so a suite can stand at
23:59:58 UTC and cross a midnight in two seconds.

## E2 — reacting (harbor#1044)

```
bus ──since/wait──▶ event-dispatch.sh dispatch ──▶ rule handler (argv)  ──emit (cause inherited)──▶ bus
                         │ offsets · ledger           └▶ --spawn: claude -p ──agent.result (cause)──▶ bus
                         └ rule.backstop ──▶ bus
session prompt ──UserPromptSubmit──▶ event-dispatch.sh pull --hook ──▶ one line, or nothing
```

`bin/event-dispatch.sh` is one POSIX `sh` tool; `harbor event dispatch|on|pull|subscribe` reach it through
`event-bus.sh`. The operator's gates are `{cfg}/.helm-dispatch/`: `rules/`, `ledger`, `spend/`, `spawn.on`, an
integrity path the floor refuses to a session (below). Its place on the bus is `<bus dir>/dispatch/`:
`offsets`, `results/`, `sessions/`, the lock and the off switches.

### Operator decisions (2026-10-07)

1. **Spawn auth:** as the operator, through OAuth, with `--setting-sources user`. Never `--bare` with an
   API key; the agent starts from `env -i` with an allowlist (`HOME USER LOGNAME SHELL TMPDIR LANG
   CLAUDE_CONFIG_DIR`, the bus knobs, `PATH`), so no `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN` or `GH_TOKEN`
   reaches it and OAuth is the only route. OAuth needs no variable: macOS reads the login keychain as `$USER`,
   keyed to `CLAUDE_CONFIG_DIR` when set; Linux reads `~/.claude/.credentials.json` (code.claude.com/docs,
   "Authentication", "Credential management"). Read from the docs and the binary, not run.
   `user` keeps the floor's hooks (they live in user settings) and leaves out project and local settings.
2. **Caps:** $0.25 per spawned agent, $5 per UTC day, enforced by the dispatcher from `total_cost_usd`.
3. **Orchestrator:** a standing `claude --bg` session subscribes; projects-orchestrator does not change.
   It waits on `subscribe`, which is refused until the socket is verified (below).
4. **Ships inert.** Merging and deploying change nothing at runtime. `deploy-runtime-install.sh` copies
   `event-dispatch.sh` into the config dir and nothing runs it: no installer loads the launchd plist, writes a
   rule, creates `spawn.on` or wires the catch-up hook. Each is a step the operator takes (opting in, below).

### The follower

- **Its position is the bus offset** (`dispatch/offsets`, consumer `dispatch`), and it moves only after a batch
  is acted on: a batch is read into a copy of the offsets, every line is acted on, and only then is the copy
  committed. Killed anywhere in between, the batch is read again.
- **The ledger is the commit for each (event, rule).** One TAB line per decision (`wall`, the event's epoch, the
  event id, the rule, the outcome, the subject, the dollars). A pair with a line is never acted on again, so a
  re-read doubles nothing. A handler killed before its line is written runs again on the restart: the one
  at-least-once window, the handler's run itself, which is why a handler gets the event id. A spawn has no
  such window: its `reserved` line, at $0.25, is written before the agent starts and settled to `done:<exit>`
  and the real cost after, so a dispatcher killed mid-spawn keeps the spend counted and never spawns it again.
- **A first start reads nothing old**: with no offsets file it begins at the end of the bus, so installing
  it never fires a rule on 14 days of history.
- **It wakes on the bus** (`event-bus.sh wait`, `tail -F`), not a timer, and at least hourly, sooner when a
  rule's backstop is due. The wait runs in the background so a SIGTERM (launchd's bootout) is handled at once.
- **One follower per bus**: a kernel `flock` on `dispatch/dispatch.lock`, held on an fd for the dispatcher's
  life and closed for every child; a second is refused (exit 1). The kernel drops it when the holder dies,
  so there is no stale lock to break. `dispatch/dispatch.pid` names the holder, written whole after the lock is
  held. Only the holder prunes or rewrites the ledger. No `perl`, no lock, no follower.
- **Off:** `touch dispatch/dispatch.off`; it exits 0 within about a second, asleep, or mid-batch before its next
  event (the rest of the batch is left uncommitted and runs once on the next start), and launchd (`KeepAlive`
  `SuccessfulExit=false`) leaves it down. A crash, any other exit, is restarted after 10 s.
- **A missing dependency leaves it down, and says so where the operator looks.** No `jq`, no `perl` (so no
  lock), or a bus beside it that does not pass `HARBOR_EVENT_CAUSE` on: one `[check:event.dispatch] NOT
  FOLLOWING: <what>` line, a receipt `cache/event-dispatch-state.json` with `status` `down` and the reason, and
  exit 0, because `SuccessfulExit=false` restarts every non-zero exit every 10 s and a missing tool does not
  come back on its own. pulse's `dispatch` row reads the receipt: `down` is crit, so pulse-notify raises a
  desktop notification on the change (a checks.log line alone scrolled out of the console's 40-line panel
  within an hour, review r3 #4). The receipt also says `following` (with the pid, which pulse checks is alive),
  `off` or `stopped`. `dispatch --once` (a person, a suite) gets 4 instead and writes no receipt.
- **The bus is asked, not versioned, and asked again.** One `emit` into a scratch dir with `HARBOR_EVENT_CAUSE`
  set, and the line must carry it: at start, again whenever the installed `event-bus.sh`'s bytes change (its
  `cksum`, compared before every batch and every fire), and unconditionally before every spawn. A failure
  stops the batch uncommitted, so those events run once the bus passes again. floor-install also writes
  `{cfg}/bin/event-bus.sh`, and one from a checkout without #1044 under a running follower made a
  self-triggering rule run 30 times in 12 s (review r3 #3). A probe that could not write anything (a full disk,
  an unwritable dir) is not an old bus: it exits 1 with that reason, and launchd tries again.
- **Only the installed copy follows, with its own config dir, and never from a session.** `dispatch` refuses a
  copy that is not `{cfg}/bin/event-dispatch.sh` with its runtime-install manifest row, and that copy uses the
  `{cfg}` it was installed into: a `CLAUDE_CONFIG_DIR` naming another dir is refused (review r3 #1 ran an
  arbitrary handler, with the kill switch on, from a dispatcher pointed elsewhere). With `CLAUDECODE` set, which
  Claude Code sets for every tool command, `dispatch` and every rule write (`on`, `--preset`, `--off`) exit 4;
  `on --list` is a read and runs.
- **An event id is a file name only in the emit format's charset.** An id outside `[A-Za-z0-9._-]`, or with
  `..`, is one `skip:bad-id` ledger line and nothing else (review r3 #8: `../` in a raw line's id wrote a
  result file outside the state dir).
- **The kill switch.** While `{cfg}/.harbor-autoship.off` (SHIP-CONTRACT §4), or the same file in the live
  `~/.claude`, exists, no handler and no agent runs: each (event, rule) is a `skip:autoship-off` ledger line, so
  lifting it replays no backlog, and the first of a UTC day is a `[check:event.dispatch]` line. One already
  running when it appears is stopped: the deadline watchdog looks for it every second and kills the run's
  process group (TERM, then KILL 2 s later), the pair is recorded `killed:autoship-off` and an agent keeps its
  spend counted (review r3 #2: both a handler and an agent finished their action under the switch).

### Rules

```
harbor event on '<grep -E pattern>' --id event.<object> [--debounce S] [--rate N] [--backstop S]
                 -- sh {cfg}/bin/<allowlisted script>   |   --spawn '<prompt>' [--tools Read,Grep,Glob] [--cwd DIR]
harbor event on --preset <id> | --list | --off <id>
```

- **A rule exists only with its docs/reference/checks.md row.** `on` refuses an id with no register row, a row whose
  schedule cell does not name, in backticks, every dotted kind the pattern names, and a row without
  `` `harbor event on --off <id>` ``. The pattern is exactly `"kind":"<kind>"` or `"kind":"(<kind>|<kind>…)"`,
  so the named kinds are all it can match (review r3 #10: `"kind":"probe\.go"|.` fired on every event). The
  register and the presets are read only from `{cfg}/bin/docs/reference/checks.md` and `{cfg}/bin/event-rules.tsv`, which
  runtime-install ships as DATA, and only while their bytes are the blob its manifest records: never a working
  tree, whose checked-out branch decided whether a preset was valid (review r3 #5). `{cfg}` is spelled one way
  at `on` and at load, a trailing `/` dropped.
  So "every rule is a docs/reference/checks.md row naming its trigger and its disable" is enforced where a rule is made, and
  `tests/check/schedules/schedules.test.sh` holds the shipped presets to it.
- **And again on every load.** A rule file is re-checked each time the dispatcher reads it: its id against its
  file name, `kind` (`cmd` or `spawn`), the tools allowlist, the numbers, its register row and its handler. A
  file edited or written by hand after `on` is refused the way `on` would refuse it: it runs nothing, gets no
  backstop, is a `refused` ledger line, one `[check:event.dispatch]` line a day, and `REFUSED: <why>` in `--list`.
- **A handler is an installed Harbor script, and nothing else.** A cmd rule's argv is exactly
  `sh {cfg}/bin/<script>`, where `<script>` is on the dispatcher's `HANDLERS` allowlist (the handler scripts of
  `contracts/event-rules.tsv`, held equal by `registry.test.sh`) and the file's git blob is the one
  `runtime-install` recorded for it in `{cfg}/.harbor-manifest`. `on` refuses anything else (exit 4) and every
  load refuses it again, so a rule file edited by hand, or a script edited after `on`, runs nothing. A denylist
  cannot hold: review r2 reached an agent through an absolute path, a script, a PATH edit, a copied binary,
  `npx … claude-code` and `node cli.js`, all of which are now simply not `sh {cfg}/bin/<allowlisted>`. An agent
  runs only as a `--spawn` rule, under `spawn.on`, the caps and the reservation. Behind that, a refusing `claude`
  still sits first on a handler's `PATH` (exit 126). The hash covers the handler script, not the installed
  siblings it calls; whoever can rewrite those can rewrite the dispatcher too.
- **No rule ever approves.** A handler word or script that names `gate-approve.sh`, or a `--spawn` prompt that
  does, is refused at `on` and on every load, whatever the trigger (SHIP-CONTRACT §4, §5a.4); an event whose
  text names it, which would land in the prompt, is `skip:names-gate-approve`. The test is per word, case-blind,
  separators dropped (`GATE-APPROVE.SH`, `gate_approve.sh`), and a word with a glob character or one cut off at
  a separator (`gate-appr*.sh`, `gate-`) is matched as a glob against the script's spellings (review r3 #9).
  The real control stays the tool list: a spawned agent cannot run anything.
- **The guards, in order, each recorded in the ledger:** idempotent by event id; the **loop guard** refuses
  an event whose `cause` chain is 3 deep (`HARBOR_EVENT_MAX_DEPTH`) or passes through an event this same
  rule fired on (its own output coming back round); **debounce** per (rule, subject), leading edge, by the
  events' own `ts` (default 60 s); **rate** per rule, fires in the rolling hour (default 6, at most 60).
- **The handler** runs from its argv, never a shell string: the event reaches it as `HARBOR_EVENT` (the
  line), `HARBOR_EVENT_ID`, `_KIND`, `_SUBJECT`, `_RULE` and on stdin, under `env -i` and the same allowlist as an
  agent, so no key or token reaches it either, plus `SHIP_UNATTENDED=1`: a handler is unattended by definition,
  so the ship contract's unattended refusals see it. It runs under `/bin/sh`, from HOME unless `--cwd`. It is killed after
  `HARBOR_EVENT_HANDLER_TIMEOUT` seconds (600) with its process group. Its exit code is in the ledger, and a
  non-zero one is a `[check:<rule>]` line in `cache/checks.log`.
- **`cause` is inherited.** The dispatcher sets `HARBOR_EVENT_CAUSE` to the event's id, and `event-bus.sh emit`
  defaults `--cause` to it, so whatever a handler emits, or a session it starts, chains back without the
  handler passing anything: the loop guard does not depend on a handler's manners.
- **A backstop** (`--backstop S`, 0 or at least 300) puts `rule.backstop` with the rule's id as subject on the
  bus when the rule has not fired for S seconds; only that rule is handed it.

### The spawner

A `--spawn` rule runs, from its argv:

```
ENABLE_CLAUDEAI_MCP_SERVERS=false claude -p '<prompt + the event, marked as data>' --model haiku \
  --tools Read,Grep,Glob --strict-mcp-config --permission-prompts none --max-turns 5 --max-budget-usd 0.25 \
  --output-format json --setting-sources user
```

- **Off until `{cfg}/.helm-dispatch/spawn.on` exists.** Without it the event is recorded `skip:inert` and nothing
  runs.
- **Its own empty directory.** Without `--cwd` the agent starts in a new `mktemp -d` under `dispatch/work/`,
  removed after, never HOME: the event in its prompt is untrusted. It gets `SHIP_UNATTENDED=1` like a handler.
- **Narrow tools.** `--tools` is refused unless every name is `Read`, `Grep` or `Glob`: a spawned agent reads
  and proposes, and never promotes a guard or a rule. Anything that would prompt is denied. `--tools` names
  only built-in tools, so `--strict-mcp-config` with no `--mcp-config` loads no MCP server ("Only use MCP
  servers from --mcp-config, ignoring all other MCP configurations", `claude --help`, 2.1.292), and
  `ENABLE_CLAUDEAI_MCP_SERVERS=false` loads no claude.ai connector (a string the 2.1.292 binary carries; the
  help does not list environment variables).
- **Caps.** Before a spawn the day's spend plus $0.25 must stay within $5, else `skip:cap`, and the first
  refusal of the UTC day is one `[check:event.dispatch]` line. The day's spend is its own append-only record,
  `.helm-dispatch/spend/<UTC day>`: a `reserve` line before the agent starts, a `settle` line with its
  `total_cost_usd` after, a key's settle replacing its reservation. Nothing rewrites it, so truncating the
  ledger no longer resets the cap (review r3 #1: six `: > ledger` let $6.50 through). Beside it `<day>.n` holds
  the size the dispatcher last wrote, and the follower remembers it too: a record shorter than that, or gone
  while its mark stands, makes the day count as fully spent, with a checks.log line that says it was cut. After it, the cost recorded is the
  agent's own `total_cost_usd`; a result with none counts as $0.25, and one over $0.25 is a `[check:<rule>]`
  line. `--max-budget-usd` can let one agent end slightly over, which is why the reservation is the full cap.
- **The result** is `dispatch/results/<event id>.<rule>.json`, and `agent.result` goes on the bus with subject
  `<rule>:<event id>`, `cause` the event, and `data` = `title` (the rule), `session_id`, `exit`, `evidence`
  (the result file's path under the bus dir). The answer text never enters the bus (the §3a allowlist).
- **Never run here.** The argv was checked against `claude --help` on 2.1.292, and the suites run a stub; no
  real spawn was made to build this.

### Catch-up: `pull`

`harbor event pull --session ID [--repo NAME]` prints one line of the repo's events since that session's
last call, e.g. `events in harbor since your last turn (2): git.merge 3f2a1c9, pr.opened VytCepas/harbor#12`,
naming four and counting the rest, at most 400 bytes. It prints **nothing, 0 bytes**, when there is nothing;
its own session's events (subject or `data.session_id`) are left out; a session's first call starts at the
end of the bus, its offsets set from each day file's size, so a large day costs that call nothing. `pull --hook` is the same as a `UserPromptSubmit` hook: it reads `session_id` and `cwd` from
the payload, and it is bounded, `HARBOR_EVENT_BUS_TIMEOUT` (2 s) for the payload, again for `git rev-parse`
and again for the read, and exits 0 on every path, printing nothing on any failure. `dispatch/pull.off` silences it.

`sh bin/context-budget.sh` cannot see it: its rows are the always-on surface and the SessionStart
injection, and it has no row for a per-turn hook. Its DELIBERATE SURFACE read 42,495 bytes on this branch
with or without the hook, because nothing wires it. The 0-bytes-when-empty property is measured in
`tests/event/dispatch/pull.test.sh` instead (`wc -c` of the output). Wired, the hook costs 0 bytes on a turn
with no news and at most 400 on one with news, every turn after; that is the per-turn multiplier
`contracts/hooks.md` refuses `UserPromptSubmit` for, which is why it is opt-in and not installed.

### The messaging socket

`subscribe` is **refused, exit 4, as unverified**. What is known, read off the Claude Code 2.1.292 binary on
2026-10-07 and never exercised:

- `CLAUDE_CODE_MESSAGING_SOCKET` is a Unix socket, `/tmp/cc-socks/<pid>.sock`, mode `0600` in a `0700` dir;
  `CLAUDE_CODE_MESSAGING_TOKEN` is the session's token; `--messaging-socket-path` sets the path.
- The binary's own help string gives the wire: newline-delimited JSON, an auth line, then a user message:
  `{"type":"auth","token":"<token>"}` then `{"type":"user","message":{"role":"user","content":"..."}}`,
  e.g. through `socat - UNIX-CONNECT:<socket>`. A connection that sends no complete line within 30 s is closed.
- A sender authenticates with the RECEIVING session's key, which the receiver publishes to a session
  registry directory; where that is, and how a peer reads it, was not established. "Auth is optional on this
  platform" appears for a receiver that could not publish its key.
- Messages from peers arrive wrapped in a tag with `from`, `from-session` and `hop-chain` attributes.

Why not probed: the only live socket on hand was the operator's own session, and a "hello" written to it is a
turn in that session; a scratch session is a real spawn, which this lane does not make. The probe that would
settle it, in a scratch session the operator starts: `claude --bg`, then from another shell the two lines
above to its socket with its token, and see whether an idle session takes a turn. Two cautions for whoever
builds it: a delivered event becomes user-turn text in a live session, so it must carry only bus fields, never
`data` a producer did not allowlist; and the orchestrator's subscription (decision 3) waits on this.

### fleet-snapshot and pulse

`contracts/event-rules.tsv` ships two presets, **neither on**: `event.fleet-snapshot` runs
`status-fleet-snapshot-refresh.sh` on `session.start`, `session.stop`, `pr.opened`, `pr.merged`, `git.merge` or
`ci.job.done`, and `event.pulse` runs `alert-notify.sh` on `ci.job.done`, `obligation.open`,
`obligation.close` or `git.merge`, each with an hourly backstop. Their 300 s and 900 s launchd timers are
untouched; moving one is the operator's: install the preset, then boot out its timer.

### The operator's gates, and who can touch them

`spawn.on`, the rules, the ledger, the day's spend record and the kill switch are the operator's controls, and
review r3 #1 wrote every one of them from a session. They are now refused to a session where Harbor's floor
refuses anything:

- `{cfg}/.helm-dispatch/` is an integrity row of `contracts/control-plane-state.md`, so guard-bash (every write verb
  `FILES` models, `touch` and a `cd` into the dir included), guard-selfedit (Write, Edit) and the B1 deny list
  (`Edit(~/.claude/.helm-dispatch/**)`) refuse it, and lint F14 holds the three layers to the row.
- `{cfg}/.harbor-autoship.off` is in guard-bash's `FILES`: deleting or moving it lifts the switch. Write and
  Edit cannot delete a file, so guard-selfedit has no entry for it. Creating it is refused to a session too, as
  every write to a `FILES` name is; the operator engages it from a terminal.
- Starting the follower and writing a rule are refused by argv (`event-dispatch-operator`): the script by any
  path, `event-bus.sh dispatch|on` and `harbor event dispatch|on`; `on --list` and every other bus verb stay
  open. The script refuses the same acts itself when `CLAUDECODE` is set, which covers a script a session wrote.
- **Residual.** A session that writes a script which does the write itself, and unsets `CLAUDECODE` first, is
  harbor#114's general residual (docs/explanation/admission-baseline.md): the guards read command text. What stays fail-closed behind that is
  the spend record's size mark and the per-load re-checks of every rule.

### Opting in (the operator's steps)

1. Deploy as usual: `event-dispatch.sh` lands in `~/.claude/bin`, and nothing runs it.
2. The follower: render `launchd/com.harbor.event.dispatch.plist` into `~/Library/LaunchAgents/` (a template: its
   home paths are placeholders that `sh bin/deploy-launchd-render.sh <plist> > ~/Library/LaunchAgents/<plist>` fills from
   `contracts/roots.tsv`, as for every plist there), bootstrap it in `gui/$(id -u)`, and see `launchctl list | grep event.dispatch`.
3. A rule: `harbor event on --preset event.fleet-snapshot` (or write a docs/reference/checks.md row, then `harbor event on`).
4. Spawning, only for `--spawn` rules: `touch ~/.claude/.helm-dispatch/spawn.on`, from your own terminal.
5. Catch-up: add a `UserPromptSubmit` command hook,
   `/bin/sh "$HOME/.claude/bin/event-dispatch.sh" pull --hook`, to `~/.claude/settings.json`.
6. fleet-snapshot or pulse on events: step 3 with its preset, then boot out its timer.

Off again, in reverse: remove the hook, `rm ~/.claude/.helm-dispatch/spawn.on`, `harbor event on --off <id>`, boot out
`com.harbor.event.dispatch` and remove its plist (docs/reference/checks.md `event.dispatch`).

### E2 robustness rules, each a test

| rule | where it is held |
|---|---|
| Killed mid-batch with a handler running, it resumes: no event lost, none doubled; the offsets did not move | `tests/event/dispatch/resume.test.sh` |
| `dispatch.off` mid-batch stops before the next event; a bus that drops the cause, no jq or no perl: refused (4 `--once`, 0 as the follower) with a `NOT FOLLOWING` line and a `down` receipt pulse reads as crit; a bus swapped under a running follower stops it before the next fire; a probe that cannot write is exit 1 with that reason | `resume.test.sh`, `tests/alert/probe/probe.test.sh`; the installed pair: `tests/deploy/runtime-install/runtime-install.test.sh` |
| The operator's gates: `.helm-dispatch/` and the kill switch refused to a session's writes, and starting the follower or writing a rule refused by argv; the script refuses both inside a session, outside its install, and with another `CLAUDE_CONFIG_DIR`; the cap survives six ledger truncations; a cut spend record fails closed | `tests/admission/bash/state.jsonl`, `bash.floor-surface.jsonl`, `bash.exec.jsonl`, `selfedit.jsonl` (rows `ed1044-*`); `spawn.test.sh` |
| The kill switch stops a handler (and its child) and an agent already running within 6 s, recorded `killed:autoship-off`; the live `~/.claude` switch holds too | `spawn.test.sh` |
| The register and presets are read only as installed, hash-checked data, never `~/port/harbor`; a trailing `/` in `CLAUDE_CONFIG_DIR` loads the same; both presets install in a sandbox runtime-install | `registry.test.sh`, `tests/deploy/runtime-install/runtime-install.test.sh` |
| A first start fires nothing on history; a running follower wakes on a new line; one follower per bus, with 12 started at once past a dead holder's leftovers, and the ledger intact; TERM and `dispatch.off` stop it, asleep or not | `resume.test.sh` |
| A rule is refused without its docs/reference/checks.md row, its trigger in it, or its disable command, at `on` and at every load (tools, kind, id) | `rules.test.sh`, `registry.test.sh`, `tests/check/schedules/schedules.test.sh` |
| Idempotent by event id; debounced per (rule, subject); the loop guard (own output, depth 3); rate per rule; backstop | `rules.test.sh` |
| Inert without `spawn.on`; the exact argv; `env -i` and the allowlist, no key or token; `agent.result` with its cause; $5 a UTC day; a missing cost is the cap; an overrun is an alarm; a `--` handler is only `sh {cfg}/bin/<allowlisted>` with its recorded bytes (every r2 probe form refused); its own empty cwd; `SHIP_UNATTENDED=1`; the kill switch; no rule approves; a spawn killed four times ran once and kept its reservation | `spawn.test.sh`, `registry.test.sh` |
| One line or 0 bytes; this repo only; never the session's own; a first offset without reading the bus; as a hook, exit 0 and silent on a garbage payload, a hung bus, a hung git, an open stdin, a missing library | `pull.test.sh` |
| `subscribe` is refused as unverified; `harbor event` routes the E2 verbs; the plist is the KeepAlive follower | `registry.test.sh` |

### Not verified (E2)

- The socket protocol (above), and so `subscribe` and the orchestrator's subscription.
- A real `claude -p` spawn: the argv's order and the JSON's `total_cost_usd`, `session_id` and `is_error`
  fields are from `claude --help` and the documented result shape, run here only against a stub.
- Whether launchd's bootout kills a running handler before its 10 s grace ends; the TERM trap kills the
  handler's process group, and a SIGKILL leaves the handler running (it is then re-run on the restart).
- **The claude → hook half of the cause.** A spawned agent's own session events reach the bus through its
  user hooks (`event-hook.sh`), which pass the cause on only if Claude Code hands a command hook its own
  environment. Read off the 2.1.292 binary, not run: the command-hook runner builds the child's env as
  `{...ss(), …, CLAUDE_PROJECT_DIR: …}`, and `ss()` starts from `process.env`. `spawn.test.sh` holds the other
  half with the real `event-hook.sh` and bus: a stub that runs the hook as Claude Code would, and the agent's
  `session.start` carries the event that spawned it, so the loop guard skips it. The first real spawn should
  check that line on the bus.

### Follow-ups (review r3, LOW, not fixed in #1044)

- **The hash reaches one hop (r3 #6).** *Exposure:* the `event.fleet-snapshot` preset's handler is hash-checked,
  but the ~10 sibling scripts it runs are not, nor `~/.local/bin/projects-orchestrator`, which no manifest
  records and a session can rewrite (guard-bash refuses neither a Write to it nor `uv tool install --force`).
  The preset also makes credentialed `gh` calls, including runner-switch's `HARBOR_RUNNER` variable path, with
  `SHIP_UNATTENDED=1`, and a planted absolute-path `claude` there passes the noclaude shim. The same reach
  already exists through `com.harbor.fleet-snapshot` every 300 s; the dispatcher adds event-timed runs, not
  reach. *Proposed fix:* before each fire, verify every runtime-install manifest row in one
  `git hash-object --stdin-paths` call and refuse on any mismatch; record projects-orchestrator's bytes in a
  manifest (or have the preset call a read-only refresh mode that runs no orchestrator and no gh write); and
  say in docs/reference/checks.md which writes the preset makes.
- **The check-to-exec window is the whole run (r3 #7).** *Exposure:* `/bin/sh` reads a handler script as it
  runs, so bytes appended in place after the hash check run in that same run (the next load refuses the
  file). Writing them needs `{cfg}/bin`, which every floor layer refuses to a session. *Proposed fix:* copy the
  handler into a private 0500 file under the state dir, hash the copy, and run the copy, so what runs is
  exactly what was checked.

## Deferred

- **E3 — off the box.** One Pub/Sub topic the laptop pulls (no public endpoint) for warehouse job
  completions, Cloud Build, budgets and webhooks through a relay, and an allowlisted outbound
  projection. Nothing leaves the box until then, and then only that projection.

## Not verified

- That `tail -F` from a byte offset behaves the same under BusyBox; the targets are BSD and GNU.
- Wall-clock deadlines across a system sleep: the timer is `sleep`, and a laptop that sleeps
  through a deadline returns after it wakes.
- Two `since` readers sharing one consumer name; it is documented as unsupported, not prevented.
- SIGINT, and SIGKILL in the middle of `since` (the offsets then stay where they were, by design,
  but no test kills it there).
