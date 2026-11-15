---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of hooks/worklog-push/worklog-push.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## hooks/worklog-push/worklog-push.sh, lines 15-24 (before this edit)

```text
ONE marker implementation, not three (H2, contracts/marker.md). This hook used
to walk the tree itself with `[ -e "$d/.agents" ]` — the exact predicate
floor_in_repo was hardened away from after the 2026-07-24 marker-forgery
finding, because it accepts a zero-byte FILE or a symlink to anywhere. Verified
still forgeable here before the change: a planted `.agents` file made this hook
stand down, i.e. silently stopped work-log sync, while the guards refused the
same forgery. It also walked from the hook process's own $PWD instead of the
session cwd the payload carries.

Stdin is read FIRST now, because the shared resolver reads .cwd from it.
```

## hooks/worklog-push/worklog-push.sh, lines 34-34 (before this edit)

```text
Stands down only where the repo's .agents/config.yaml says `worklog: off` (harbor#954).
```

## hooks/worklog-push/worklog-push.sh, lines 39-39 (before this edit)

```text
Session record — append-only, write-once path per host (memory-format contract).
```

## hooks/worklog-push/worklog-push.sh, lines 45-49 (before this edit)

```text
The format lives in floor_worklog_record (library-admission.sh), not here. It used to
be open-coded, and harbor#6 added a SECOND writer — memory-harvest.sh, which
backfills a record for a session that never reached this hook. Two open-coded
writers of one format drift silently: both keep producing files, they just stop
being the same shape.
```

## hooks/worklog-push/worklog-push.sh, lines 62-63 (before this edit)

```text
Tracked-glob allowlist (deny-by-default; never git add -A). One add per
glob: git aborts a multi-pathspec add wholesale if ANY pathspec is empty.
```

## hooks/worklog-push/worklog-push.sh, lines 71-71 (before this edit)

```text
Fail-CLOSED secret gate on the staged snapshot.
```

## hooks/worklog-push/worklog-push.sh, lines 78-82 (before this edit)

```text
floor_gitleaks_staged, not a literal subcommand: 8.18.4 has no `gitleaks git`
and exits 1 on it, which `--exit-code 1` makes indistinguishable from a finding
— so this gate refused every commit on a box carrying the version CI itself
pins, while reporting a secret. See library-admission.sh for the probe and the measured
equivalence. The fail-closed posture below is unchanged: non-zero still blocks.
```

## hooks/worklog-push/worklog-push.sh, lines 112-115 (before this edit)

```text
Push — network failures are the ONLY fail-open leg (commit stays local).
The token is the store's `worklog-token` and nothing else (harbor#1205, decided 2026-10-23). A plaintext file
left from before is never read: it is named, with the command that moves it. Each state warns once (a stamp per
state), so a token that is gone is said, never silently unpushed.
```

## hooks/worklog-push/worklog-push.sh, lines 135-143 (before this edit)

```text
THE TOKEN GOES THROUGH THE ENVIRONMENT, NEVER THE URL. CONSTITUTION §4 states
this as a bare imperative — "Never put auth tokens in URLs. Authorization:
header only — URLs leak into logs, shell history, and referrers" — and this
hook, which runs on every Stop, was the thing breaking it. A URL-embedded
credential reaches the reflog, `ps`, and any proxy in front of the remote.
The credential helper receives it from the environment instead: the helper
STRING is visible in `ps`, the token is not. It also means a failure message
from git can no longer contain the credential, which is why the error is now
safe to print.
```

## hooks/worklog-push/worklog-push.sh, lines 145-150 (before this edit)

```text
PUSH TO `origin`, NOT TO A URL. Pushing to an explicit URL never advances
origin/main, so `git status` in the work-log reported a monotonically growing
[ahead N] while every push was succeeding — measured at 11 with local HEAD and
the remote ref at the IDENTICAL sha. A status signal that is always wrong is
one nobody reads, and this one hid the only question worth asking of a
sync hook: is the log actually leaving this machine?
```

## hooks/worklog-push/worklog-push.sh, lines 155-160 (before this edit)

```text
FAIL OPEN ON NETWORK ONLY, which is what the header has always claimed. The
old `>/dev/null 2>&1 || true` made a rejected credential, a non-fast-forward,
a deleted remote and a clean success indistinguishable — so the stated
contract and the implemented one were different documents. The commit is
local either way and the next Stop retries; what changes is whether the
operator ever learns the log stopped leaving the machine.
```

## hooks/worklog-push/worklog-push.sh, lines 9-10 (before this edit)

```text
CLAUDE_CONFIG_DIR-aware: in a sandbox session this resolves to the sandbox,
whose MEMORY has no .git — the hook stands down instead of touching live.
```

## hooks/worklog-push/worklog-push.sh, lines 113-113 (before this edit)

```text

```
