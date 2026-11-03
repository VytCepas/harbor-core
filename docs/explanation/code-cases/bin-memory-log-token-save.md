---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/memory-log-token-save.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/memory-log-token-save.sh, lines 8-28 (before this edit)

```text
CAPTURED FROM THE BOX, NOT WRITTEN HERE. This existed only as an installed file
in the live floor: no commit, no branch, no working tree of this repository held
it, and it had been handling a GitHub PAT that way for an unknown length of time.
drift-install.sh (harbor#431) is what named it — `unsourced memory-log-token-save.sh
(in no commit of this repository)` — because it is the one check that enumerates
the LIVE directory instead of the repo, so it can see a file nothing here ships.
Everything else compared repo-to-box and could only ever miss it.

The behaviour is the box's, preserved deliberately; what this adds is the
repository conventions it now has to meet (S1 shebang + strict mode, S3 ticket,
S4 --help) and the two properties below stated where a reader will find them.

WHY IT NEVER PRINTS THE TOKEN. The only output on success is a LENGTH and a
confirmation. A guard's stderr, a hook's stdout and a terminal scrollback are
all places a pasted credential outlives the paste, and the operator running this
already has the value — echoing it back buys nothing and costs a copy in the
session transcript, which is exactly what CONSTITUTION §3 is about.

WHY THE STORE AND NOT A FILE (harbor#1205, decided 2026-10-23). The value goes in on stdin to `secret put`, so it
is never on disk or in argv. A plaintext file from before is never read by anything any more; `secret adopt <file>
worklog-token` moves one that is still there without a new token.
```

## bin/memory-log-token-save.sh, lines 41-42 (before this edit)

```text
The clipboard: pbpaste/pbcopy on macOS; wl-clipboard, xclip or xsel on Linux; under WSL2 the
Windows clipboard, through powershell.exe and clip.exe (harbor#618).
```

## bin/memory-log-token-save.sh, lines 69-72 (before this edit)

```text
`|| true` ON THE SUBSTITUTION, not on a later line. Under `set -e` a bare
`T="$(clip_read)"` ABORTS on a non-zero read, so a fallback written underneath
it is dead code that never runs — measured trap, and the reason the guard below
is reachable at all.
```

## bin/memory-log-token-save.sh, lines 77-81 (before this edit)

```text
The store, not a file (harbor#1205): piped, so the value never reaches argv or a prompt's echo.
A refused store is a FAIL, never a quiet fall back to the plaintext file.
The store's stderr goes to a FILE, then to the operator: its own words say why (a register entry that
does not name the ref), and a file leaks nothing a `2>&1 >/dev/null` capture would tee. The token goes in
on stdin only, so it is not in anything `secret` says about its arguments.
```

## bin/memory-log-token-save.sh, lines 95-95 (before this edit)

```text
LENGTH, NEVER THE VALUE. Enough to tell a truncated paste from a whole one.
```

## bin/memory-log-token-save.sh, lines 100-102 (before this edit)

```text
FOUR CHARACTERS OF THE PREFIX, which is what distinguishes "I copied the
wrong thing" from "I copied nothing" — and is short enough to carry no
secret even when the clipboard did hold one.
```
