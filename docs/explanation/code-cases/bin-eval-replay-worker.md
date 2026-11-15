---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/eval-replay-worker.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/eval-replay-worker.sh, lines 3-4 (before this edit)

```text
harbor#133 — lifted out of eval-replay.sh's heredoc so the suite can reach it.

```

## bin/eval-replay-worker.sh, lines 7-7 (before this edit)

```text

```

## bin/eval-replay-worker.sh, lines 8-12 (before this edit)

```text
`set -u` and DELIBERATELY NOT `set -e`. Every jq below is expected to fail on a
record that is not valid JSON — that is the whole path this file exists to keep
honest — and under `-e` the assignment `id="$(jq …)"` would abort the worker
before it could print the ERROR verdict, reproducing the silent drop as an even
quieter one. The `rc=$?` after the guard call fails the same way under `-e`.
```

## bin/eval-replay-worker.sh, lines 14-26 (before this edit)

```text

WHY THIS IS A FILE AND NOT A HEREDOC INSIDE eval-replay.sh. It used to be written to
`$TMP/one.sh` under eval-replay.sh's own private temp dir and deleted by its EXIT
trap. That made it UNREACHABLE from the suite: replay-test's assertion on the
never-drop-a-record property guarded it with `[ -f "$TMP/rp/one.sh" ]`, a path
that never existed, so the test took its `else ok` branch on every run and
reverting the fix would still have passed (Codex, harbor#133). A test that
cannot fail is worse than no test, and the untestability was the heredoc — so
the heredoc is gone rather than worked around.

Invoked per record with the record as a single line on stdin: every attempt to
stream records through xargs failed on the quoting, and a replay that loses
records reports "no regressions" from an empty run.
```

## bin/eval-replay-worker.sh, lines 27-29 (before this edit)

```text
Stdout is the verdict, which eval-replay.sh reads as data (id<TAB>verdict<TAB>rule), so the log is on stderr (LOG_FD=2,
contracts/logging.md, harbor#771); eval-replay.sh discards it. A record with no verdict is a WARN, not a failure of
the worker: the ERROR verdict is the worker succeeding at saying so, and the exit code stays 0 as it always was.
```

## bin/eval-replay-worker.sh, lines 40-46 (before this edit)

```text
NEVER EXIT WITHOUT A LINE. This used to `exit 0` on an unextractable id, which
for a record that is not valid JSON meant the worker produced NOTHING — and the
run came back one verdict short of the corpus with no indication why. The
self-check in eval-replay.sh caught the arithmetic and refused to report, which is the
only reason the defect surfaced at all; the count is not a substitute for saying
which record failed. A synthetic key keeps the tally honest without inventing a
join key that could collide with a real payload hash.
```

## bin/eval-replay-worker.sh, lines 61-66 (before this edit)

```text
rc is THREE-valued, not two (#47 finding 5). Anything outside {0,2} is a guard
that did not reach a verdict — a syntax error, a missing interpreter, a kill —
and the first cut fell through to ALLOW. A broken guard then reported "0
blocked", which reads exactly like a clean floor. admission-hook.sh maps the same
class to a DENY for precisely this reason; the replay must not be more
forgiving than production.
```
