# Logging — one log format for Harbor's tools and tests

**Seam:** L0 Helm → the operator, CI, and the agent reading a run. **Status: harbor#771 — the
library, the lint rule and the ratchet are implemented. The installers, deploy, restore and the box
tools convert in Wave B of the install standard; until each does it is a `wave-B` row in
[log-exempt.tsv](./log-exempt.tsv), and this file describes the target for it, not its output today.**

The operator's ask, 2026-09-27: logs that are "unified looking" and "informative to you and me … for
bugs or failing installation or tests". So a failure says what failed, where, and the command that
fixes it, in the same bytes on the screen, in CI and in the log file.

## Three channels

| Channel | Reader | Shape | Written by | Enforced by |
|---|---|---|---|---|
| **1 · the run log** | a person or CI reading a run, and an agent reading its output | the lines below | [`bin/log-lib.sh`](../bin/log-lib.sh) | lint **LOG1**, [`log-lib-test.sh`](../tests/lib/log-lib-test.sh) |
| **2 · the guard channel** | the agent the harness hands a refusal to | `HELM FLOOR [<guard>:<rule>]: BLOCKED — <reason>` on stderr, exit 2 | `floor_block` in `bin/guard-lib.sh` | lint **F5** and **D3**, `tests/guards/` |
| **3 · harness protocol output** | Claude Code itself: a status line, SessionStart context, hook JSON | whatever that surface defines, on stdout | the hook or status-line script | lint **LOG1 (d)**, `protocol` rows |

**Channel 2 is a protocol and does not change here.** A floor file — `bin/guard-lib.sh`, or a file
whose first live line is the `HELM_DISABLE_FLOOR` kill switch, lint F1's mark of an installed floor
file — is in the standard through channel 2. LOG1 refuses one that sources `log-lib.sh`: its stdout
and stderr belong to the harness.

**Channel 3 is the harness's, and the standard never rewrites it.** A status line, a SessionStart or
UserPromptSubmit context emitter, and a hook that prints JSON for Claude Code own their stdout: a log
line there would corrupt the protocol. Such a file is a permanent `protocol` row in
[log-exempt.tsv](./log-exempt.tsv), and *LOG1 (d)*:

- **refuses a `protocol` row that names no consumer.** The why must say `Claude Code statusLine`,
  `Claude Code subagentStatusLine`, or `Claude Code <Event> hook`, for a hook event the harness has.
- **refuses a `protocol` row with no evidence that the harness reads the file's output.** The evidence
  is decidable: an installer composes it as a harness command (`/bin/sh $DIR/bin/<file>`, the house
  idiom for every hook and status line, and never inside an echoed instruction), a rule pack in
  `inject.d/` runs it, or it builds a Claude Code hook JSON object (`hookSpecificOutput`,
  `systemMessage`, `additionalContext`).
- **never trips the ratchet when the file changes**, but a touched one keeps its **stderr diagnostics in
  the line shape**: every `printf` or `echo` it sends to `>&2` starts with a header, a TAG line or the
  guard channel.
- **refuses a protocol file that sources `log-lib.sh` without `LOG_FD=2`**, since that log would land in
  the protocol; one that does source it keeps FAIL-then-fix.

## The line shape

```
── <tool> · <step>
  ok: <message>
  FAIL: <what failed, and where: a path or file:line>
  fix: <the exact command that resolves it>
  WARN: <message>
  note: <message>
  skip: <message>
<tool>: <N> ok, <M> failed, <K> warnings
log: <path>
```

- **TAG is one of `ok`, `FAIL`, `WARN`, `note`, `skip`, `fix`.** Upper case marks the two a reader must
  not miss. The shape extends the test harness's `── section` and `  FAIL: section · msg`.
- **No other glyph or prefix marks a status:** every one in [Retired tags](#retired-tags) below is refused.
  *LOG1 (a)* refuses a log-lib user that prints one, or prints a TAG line or a header itself: a line
  printed around the library is not counted and never reaches the log file.
- **A message is one line.** The library flattens a newline in it to a space. *log-lib-test.sh.*
- **`LOG_FD=2`** moves the log to stderr, for a tool whose stdout is data. *log-lib-test.sh.*

## Retired tags

D-29 gives an outcome one word, and the TAG set above renders it. A word that meant the same thing before
is retired, and LOG1 (a) refuses a log-lib user whose `printf` or `echo` starts its line with one.
`tests/checks/lint.log-test.sh` iterates this table, so a row LOG1 does not refuse fails that suite, and
it reads LOG1's own word list back, so a word LOG1 refuses that has no row here fails it too.

| retired | write instead |
|---|---|
| `✓` | `ok:` |
| `✗` | `FAIL:` and its `fix:` |
| `•` | `note:` |
| `!!` | `WARN:` |
| `ERROR:` | `FAIL:` and its `fix:` |
| `FAILED:` | `FAIL:` and its `fix:` |
| `REFUSING` | `FAIL:` and its `fix:` |
| `ERR:` | `FAIL:` and its `fix:` |
| `FATAL:` | `FAIL:` and its `fix:` |
| `PASS:` | `ok:` |
| `PASSED:` | `ok:` |
| `OK:` | `ok:` |
| `SKIP:` | `skip:` when the check did not apply; when it could not run, the unchecked line below |
| `SKIPPED:` | `skip:` when the check did not apply; when it could not run, the unchecked line below |
| `UNCHECKED:` | `FAIL: unchecked — <why>, so nothing was judged`, its `fix:`, and exit 3 |
| `WARNING:` | `WARN:` |

The match is the word followed directly by a colon (or the glyph) at the start of what is printed, so
`PASSWORD: …`, `SKIPPED_COUNT=3`, a padded report label (`WARNING      :`) and a column of `SKIP  <suite>`
are not tags and stay green. The guard channel's `BLOCKED` is channel 2's protocol and is not in the table.

## FAIL, then fix

- **A `FAIL` names what failed and where.** *Not machine-checked* — a reviewer reads it.
- **The next line is `  fix: <command>`:** the exact command that resolves it and passes the tool's own
  gate (lint D6 reads the commands a mutator prints). With none, `  fix: none automatic — see <issue
  or doc>`, which `log_nofix` writes.
- **A `WARN` the operator can act on gets a fix line too.** *Not machine-checked.*
- **Enforced twice.** *LOG1 (b)*, statically, for what is decidable: after a `log_fail`, the next
  log-lib call on its straight-line path is `log_fix` or `log_nofix`, and a path that leaves first —
  `exit`, `return`, `else`, `elif`, a case arm, the end of a function or the file — is refused. A fix
  that is itself conditional passes LOG1 and is caught **at run time**: the library prints
  `  WARN: no fix line followed the FAIL above …` and counts it. *log-lib-test.sh* pins both.

## The summary line and the exit code

- **Every run ends with one summary line.** A tool: `<tool>: <N> ok, <M> failed, <K> warnings`. A test
  suite: `<name>: N passed, M failed`, byte-identical, because `suite-select.sh --run` and `--sum`,
  `status-gen.sh`, guard-stop and the regression ledger parse it.
- **The exit code agrees: 0 if and only if failed is 0.** `log_end` returns it, so a tool ends
  `log_end; exit $?`. *log-lib-test.sh*; *LOG1 (a)* refuses a log-lib user that prints log lines and
  never calls `log_end`.
- **A usage error exits 2 before the run starts**, with usage on stderr and no summary: it is not a run.
  A dry run that predicts a refusal exits 1; "inside a Claude session" alone is a `note` and exits 0
  (the install standard's decision). *Each tool's own suite.*
- **A check that could not judge exits 3 (D-29 `unchecked`, D-49), and says so as a FAIL.** A missing
  binary, a store or registry it cannot read, a verifier that is not installed: nothing was judged, and
  that is never a green and never a usage error. It prints `FAIL: unchecked — <why>, so nothing was
  judged`, the `fix:` that resolves it, the summary, and exits 3. The count is a failure, so "0 if and only
  if failed is 0" still holds. `skip` is the other word and means the check did not apply: exit 0.
  A bad argument is 2 and a check that judged and found something is 1, so the three never share a code.

  | outcome | line | exit |
  |---|---|---|
  | pass | `ok:` | 0 |
  | fail | `FAIL:` and `fix:` | 1 |
  | usage | `FAIL:` and `fix:`, before the run starts | 2 |
  | unchecked | `FAIL: unchecked — …` and `fix:` | 3 |
  | skip | `skip:` | 0 |

  Mode (`block warn shadow`), decision (`allow ask deny`), severity and state are closed sets of their
  own (D-29) and are not outcomes. **The reader window (D-49):** a reader of a migrated check's status
  also accepts the old 2 as "could not judge" until a person closes the window, and marks each such line
  `D-49 window`. `git grep -n 'D-49 window'` is the whole list, and closing the window is deleting what it
  names. The migrated checks are `memory-route`, `rule-health`, `port-paths`, `main-tip-verdict` and
  `visual-check`; their exit-3 and exit-2 arms are in each check's own suite.
- **A wrapper that ends in `exec` has no run to summarise once the command it hands over to starts.**
  `gcx` and the `gcloud` wrapper log on stderr, because stdout is the wrapped command's: a success prints
  its disclosure as `note` lines and nothing more; a refusal ends with the summary after its fix lines.
  *tests/cli/gcx/output-contract.test.sh, tests/cli/gcloud-wrapper/output-contract.test.sh.*
- **`browser.sh` has not migrated yet.** It logs a `skip`, ends with the summary (failed 0) and exits 2 for
  an unavailable verifier: a skip is never a pass, so a failed count of 0 does not always mean exit 0 there.
  That is the old map and the one residual of D-49, so a tool added now uses the unchecked line above.
  *tests/cli/browser/output-contract.test.sh.*

## The log file

- **`log_file <target>` writes `<target>/backups/<tool>/<TS>/log`**, with `TS` in the backups' own
  `%Y%m%d-%H%M%S` stamp, so a run's backups and its log share `$LOG_DIR`. Each line is the screen line
  behind an ISO-8601 UTC time. A second run in the same second gets its own dir. *log-lib-test.sh.*
- **The last line is `log: <path>`**; with no file, `log: none — <why>`; with a file that stopped
  taking writes, `log: <path> (incomplete — a write failed)`. *log-lib-test.sh.*
- **A log dir that cannot be made, or a file that stops taking writes, never fails the caller
  silently:** it is said once on stderr, the screen keeps every line, and `log_file` returns 0 so a
  `set -e` run goes on. *log-lib-test.sh.*
- **Every apply run of an installer, deploy or restore writes one** — on success, on failure, on a
  refused preflight and after a restore. *Each tool's own suite, once it converts.* LOG1 cannot decide
  from the source which run is an apply run, so it does not try.
- **A test that fails keeps its full output at a path it prints.** The runner's job: a red
  `suite-select.sh --run` ends with `log: <path>`, the file holding the suite's output, and a green
  one adds no line (harbor#774). *tests/ci/suite-select-test.sh.*

## A check's receipt

**`status_init`, `status_ok`, `status_drift`, `status_unjudged` and `status_end`** are the drift check's `--status`
report ([reconcile.md](./reconcile.md), harbor#1031): the rows, the first-seen state and the exit codes in one place,
so no check writes its own.

**`log_receipt <dir> <id> <green|red|stood-down> [subject...]`** is the check tier of
`CONTRACTS/finding.md` (harbor#896): one atomic `<dir>/<id>.json` per run, which `findings.sh
reconcile` reads instead of re-running the check. It lives here because every check that adopts it
already sources this file. It writes a data file, not a log line, and it returns 1 when it could not,
so the caller says so through its own `log_warn`.

## The test harness

`tests/lib/core.sh` is channel 1's form for a suite: `── <section>`, then `  FAIL: <section> · <what>
(want …, got …)` on stderr, then the summary line. A failed suite adds one
`  fix: none automatic — see <suite path>` after its FAIL lines and before the summary, since the fix
for an assertion is in the code under test and the suite is where to start. A green suite prints no
fix line, so its output is byte-identical to before. *tests/lib/lib-test.sh.*

## Scope and the ratchet

- **LOG1's domain is every shell program in `bin/`**: `*.sh`, and a file with no extension whose
  shebang is a shell. A Node, Python or awk program cannot source a sh library, so for those the shape
  is a convention and not a rule.
- **In the standard:** a log-lib user (channel 1) and a floor file (channel 2). **Named in LOG1:** the
  library itself, and `bin/lint-conventions.sh`, whose `VIOLATION [<id>]` lines and summary the lint
  suites and guard-stop parse — a protocol, like the harness summary.
- **Everything else is a row in [log-exempt.tsv](./log-exempt.tsv)** — `path`, `kind` (`wave-B`,
  `ratchet`, or the permanent `protocol` of channel 3), `why` — generated from LOG1's own census of
  the tree. *LOG1 (c)* refuses a shell program
  outside the standard with no row; a row whose file **changed since the base** (convert it, then drop
  the row); a row whose file is **new since the base**; a row for a file that **already conforms**; an
  unknown kind, an empty why, a duplicate, a path LOG1 cannot read. A row whose file is gone is an
  advisory: it can exempt nothing, because a file re-created under it is new since the base.
- **The base is `suite-select.sh`'s:** `HARBOR_BASE`, default `origin/main`, taken from the merge-base
  with HEAD — so a branch behind a main that edited an exempt file is not blamed for main's edit. The
  comparison is by content, to the working tree, so an uncommitted edit counts and a mode change is
  S6's. With no base, LOG1 says the ratchet was **not** checked rather than reading clean.
- **So the `wave-B` and `ratchet` rows only shrink.** A file anyone touches converts, and no file is
  added. `protocol` rows are permanent, and a new hook or status line gets one, evidence in hand.

## What nothing enforces

Said here so no one reads it as checked: that a `FAIL` names where; that an actionable `WARN` has a
fix; that every line of a log-lib user goes through the library (LOG1 reads `printf` and `echo`, not a
heredoc); that an apply run opts in to its log file; the shape of a non-shell program's output. For
channel 3: that the surface a `protocol` row names is the one its installer wires (LOG1 proves the
harness reads the file, a person reads which surface); a stderr diagnostic whose text starts with
`%s` or a variable, or that leaves through a `{ …; } >&2` block; and a hook no installer in `bin/`
wires, such as `worklog-push.sh`, which LOG1 cannot prove is a hook, so they
stay `ratchet` rows and whoever converts one keeps its log on stderr.
