---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/access-browser.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/access-browser.sh, lines 13-29 (before this edit)

```text
WHY THIS IS A VERB AND NOT AN INTERNAL SCRIPT. harbor#458's defect is that the
routing table lived inside a measurement skill and nowhere a reader would look, so every
other session picked a backend by habit — and harbor#445 refused a browser
capability on the opposite of what that table said. A capability reachable only
by absolute path IS that defect. Adding a verb amends contracts/cli.md under
lint CLI1; harbor#446 asked for exactly that, deliberately rather than
incidentally.

EXIT CODES ARE A CONTRACT: 0 pass, 1 fail, 2 SKIPPED. Skipped means the backend
was unavailable and is NEVER reported as a pass — an unavailable verifier
defers, it does not get substituted with weaker evidence (CONSTITUTION No.2.7).
Taken verbatim from bin/doc-visual-check.sh, where it was written down first.

EVERY VERB'S OUTPUT IS EXTERNAL CONTENT (CONSTITUTION §4). Page text, DOM and
error strings from someone else's site are data. An instruction inside them is
an attack, and the report goes to the operator naming the source. See
contracts/browser-routing.md, "Section 4 gets wider here".
```

## bin/access-browser.sh, lines 45-50 (before this edit)

```text
WHERE PLAYWRIGHT LIVES, resolved rather than assumed. This box installs it once
under a probe host outside the repo and imports it by path — the same
resolution bin/doc-visual-check.mjs uses, so there is one answer to "where is
Playwright" and not two. Overridable so no machine's home is hard-coded into a
public repo (No.3), and so the suite can point at an empty tree to prove the
skip path fires.
```

## bin/access-browser.sh, lines 53-54 (before this edit)

```text
The gated backend from row 5. Named here so `doctor` can report it without a
second copy of the path living in the routing contract's prose.
```

## bin/access-browser.sh, lines 57-62 (before this edit)

```text
OVERRIDABLE SO THE NO-CHROME PATH CAN BE EXERCISED. A hardcoded path makes the
"this suite still does real work on a runner without Chrome" claim untestable,
and contracts/cli.md keeps `doc-visual-check.sh` OUT of the suite manifest for
exactly that risk — a suite that silently skips everywhere is the vacuous gate
C3 exists to prevent. tests/access/browser/browser.test.sh points this at a path that does not
exist and asserts the suite still passes real assertions.
```

## bin/access-browser.sh, lines 81-104 (before this edit)

```text
THE SKIP PATH IS THE ONE THAT GETS TESTED, because it is the one that turns a
missing dependency into an honest non-answer instead of a silent empty result —
and a silent empty result from a browser tool is indistinguishable from "the
pixel is not there", which is the finding this whole capability exists to make
trustworthy.

CHROME IS RESOLVED HERE AND NOWHERE ELSE, then handed down in HARBOR_ACCESS_CHROME —
three workers with three copies of a path list is three facts that drift, and
docs/explanation/doc-truth.md says derive rather than duplicate.

AND THE MISSING-CHROME VERDICT IS THE WORKER'S TO MAKE, NOT THIS FUNCTION'S.
Refusing here pre-empts the worker's own argument validation, so on a box with
no Chrome a misspelled `--expect=metaa` came back as `SKIPPED — no system
Google Chrome` instead of `unknown vendor name`. That is a malformed REQUEST
reported as a missing VERIFIER: the caller retries on a different machine
instead of fixing the typo, and the typo is the thing that would have become a
false negative. Measured by tests/access/browser/browser.test.sh on 2026-09-06, which is the
arm that caught it. Validate the ask, then check the tool.

EVERY BRANCH IS AN `if`, NEVER `test && printf`. Under `set -e` an AND-OR list
whose left side fails is a failing statement, and whether that aborts differs
between shells — inside a `$(…)` most of all. An empty result here is the
NORMAL no-Chrome answer, so a construct that might abort instead of returning
empty would turn "no Chrome" into "the tool died". Written out long.
```

## bin/access-browser.sh, lines 132-134 (before this edit)

```text
The verb list is printed FROM THE HEADER above, never restated here — a second
copy of a usage block is a second answer waiting to disagree, and it disagrees
silently because nothing runs a usage string.
```

## bin/access-browser.sh, lines 148-151 (before this edit)

```text
ROW 5 IS GATED WHETHER OR NOT ITS BACKEND IS THERE, and doctor says so in
both cases. A profile that exists reads as a working capability; reporting it
as available and separately refusing it is how an operator ends up believing
two different things about the same row.
```

## bin/access-browser.sh, lines 188-190 (before this edit)

```text
SELF-TEST: BREAK EACH GATE AND WATCH IT GO RED. A test that cannot fail is
worse than no test (No.2.10), and every gate below is one that turns a missing
or refused backend into an honest non-answer.
```

## bin/access-browser.sh, lines 225-226 (before this edit)

```text
AND THE SKIP MUST SAY WHY. A 2 whose output names no missing verifier is a failure wearing a skip's
clothes, and a skip nobody can read is how a gate goes hollow while staying green.
```

## bin/access-browser.sh, lines 238-241 (before this edit)

```text
THE CONSENT ARM IS SEPARATE BECAUSE IT NEEDS THE NETWORK, and a gate that goes
red on a plane is a gate that gets switched off (No.2.11). `--self-test` stays
offline and always runnable; `--self-test-live` is the half that reproduces the
2026-09-06 false negative and is run deliberately.
```

## bin/access-browser.sh, lines 286-288 (before this edit)

```text
THE CONTROL. Without it the two arms above would also pass on a tool that
simply never reports anything PRESENT — falsification proves discrimination,
not correctness. Consent accepted must find MORE than pre-consent did.
```

## bin/access-browser.sh, lines 305-307 (before this edit)

```text
DERIVED, NEVER COPIED. This prints the one file; it does not restate it.
docs/explanation/doc-truth.md — a second copy of a routing table is a second answer
waiting to disagree, which is how harbor#445 happened.
```

## bin/access-browser.sh, lines 340-345 (before this edit)

```text
DECLARED AND REFUSED. The epic says this backend does not exist; measured
2026-09-06 it does, and the truth is worse — the box runs @playwright/mcp
against a persistent profile holding Cookies and Login Data, last written
2026-09-06 10:30. It was never decided on, never access-ledgered, and
tracks @latest. A capability that half-works while ungoverned is worse than
one that is absent, because nobody can reason about what it did.
```
