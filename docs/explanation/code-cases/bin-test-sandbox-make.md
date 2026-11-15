---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/test-sandbox-make.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/test-sandbox-make.sh, lines 11-21 (before this edit)

```text
--with-floor exists because the sandbox went stale (QA-PLAN R8): it was built
once, the floor moved on for nine hardening passes, and "try it in the
sandbox" then validated a build nobody was shipping. Copying live and
installing the floor have to be ONE command, or the second step gets skipped.
Freshness is asserted by lint-conventions.sh rule X1.

Copied: settings.json, skills/, bin/, plugins/, MEMORY (WITHOUT .git — the
work-log sync hooks then stand down safely in-sandbox), .sec0-baseline.sha256.
Deliberately NOT copied: transcripts/history/caches/telemetry (irrelevant and
private), .helm-log-token and any credential (a sandbox must not be able to
push anywhere), backups/ (that is live-restore material).
```

## bin/test-sandbox-make.sh, lines 24-30 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/test-sandbox-make.sh, lines 36-37 (before this edit)

```text
The SOURCE dir follows CLAUDE_CONFIG_DIR like every other script, so a
sandbox can be built from a non-default config dir (convention audit).
```

## bin/test-sandbox-make.sh, lines 52-72 (before this edit)

```text
THE REFUSAL COMES BEFORE THE DELETION, AND IT COMPARES RESOLVED PATHS.
Measured 2026-08-06 against a fake HOME, this script deleted its own live config
dir and exited 0:

  $ sh test-sandbox-make.sh "$LIVE/" --fresh
  sandbox ready: …/.claude/
    destroy: rm -rf …/.claude/
  $ ls "$LIVE"        # CLAUDE.md, bin/, skills/ — gone
  settings.json

TWO independent defects stacked, and either alone is enough. (1) 'rm -rf "$DIR"'
ran THREE LINES ABOVE the live-dir refusal, so for `--fresh` the gate could not
matter whatever it compared. (2) The gate was a STRING compare in a `case`, the
exact P11-01 defect fixed in floor-deny/floor-install/floor-uninstall and left
here: `~/.claude/`, `~/.claude/.`, `~/.claude//` and `~/.claude/../.claude` are
all the same directory and none is the same string.

Blast radius is why this is ordered first rather than merely fixed: P11-01
stripped hooks from a live config, this deletes the directory — and unlike the
five gated mutators, nothing here has a `--live` escape, so the refusal is
unconditional by design.
```

## bin/test-sandbox-make.sh, lines 87-89 (before this edit)

```text
Rewrite absolute live paths in settings.json (hook + statusline commands) to
the sandbox's own copies — otherwise an in-sandbox session executes LIVE
scripts and the floor's blast radius is no longer contained.
```

## bin/test-sandbox-make.sh, lines 99-99 (before this edit)

```text
Marker: lets any tool assert it is acting on a sandbox, never live.
```

## bin/test-sandbox-make.sh, lines 105-124 (before this edit)

```text
--with-b6 too: the sandbox is exactly where a session-blocking gate should
be exercised before it is trusted live.
A FAILURE HERE MUST SAY WHAT IT LEFT BEHIND (harbor#313). `set -eu` used to
abort on this line with nothing said about the directory already created — and
a --fresh sandbox is SEEDED FROM THE LIVE CONFIG, so what it leaves is not an
empty shell: MEASURED 2026-08-25 by running the INSTALLED copy, which is the
copy a session reaches — rc=127 on the missing file, and the sandbox left behind
carried 7 guards, 5 PreToolUse hooks and 96 deny entries, every guard
byte-identical to $LIVE/bin and NONE of them this checkout's (verified with cmp
against both trees, not by counting). An earlier note in this work said 8 and 8;
that was a different run and the smaller figures are the re-measured ones.

That is the R8 shape this flag exists to prevent, wearing the appearance of
success: an operator who boots that sandbox is testing the build that is
ALREADY INSTALLED, which is the one case "try it in the sandbox" must never
quietly mean. Nothing about the directory shows it — the guards are present,
wired and blocking, just the previous versions, which is harbor#115's sentence
about the live floor arriving here one layer over.
The install standard's interface (harbor#765): --dir, with CLAUDE_CONFIG_DIR agreeing with it,
since here it names the SOURCE config dir and floor-install would refuse the disagreement.
```

## bin/test-sandbox-make.sh, lines 10-14 (before this edit)

```text

--with-floor exists because the sandbox went stale (QA-PLAN R8): "try it in the sandbox" validated a build nobody shipped,
so copying live and installing the floor are ONE command. Freshness is asserted by lint-conventions.rule X1.
Copied: settings.json, skills/, bin/, plugins/, MEMORY without .git (sync hooks stand down). Not copied: transcripts, history, credentials, backups/.
Removed notes: docs/explanation/code-cases/bin-test-sandbox-make.md
```

## bin/test-sandbox-make.sh, lines 22-22 (before this edit)

```text
The SOURCE dir follows CLAUDE_CONFIG_DIR like every other script.
```

## bin/test-sandbox-make.sh, lines 37-39 (before this edit)

```text
The refusal comes before the deletion and compares RESOLVED paths. Measured 2026-08-06, `"$LIVE/" --fresh` deleted the live config
dir and exited 0: `rm -rf "$DIR"` ran above the refusal, and the gate was a string compare (P11-01) that `~/.claude/.`,
`~/.claude//` and `~/.claude/../.claude` all defeat. Nothing here has a `--live` escape, so the refusal is unconditional.
```

## bin/test-sandbox-make.sh, lines 69-72 (before this edit)

```text
--with-b6 too: the sandbox is where a session-blocking gate is exercised before it is trusted live.
A failure here must say what it left behind (harbor#313): a --fresh sandbox is seeded from the LIVE config, so an aborted
install left guards byte-identical to $LIVE/bin and none of this checkout's (measured 2026-08-25), the R8 shape this flag prevents.
The install standard's interface (harbor#765): --dir, with CLAUDE_CONFIG_DIR agreeing, since here it names the SOURCE config dir.
```
