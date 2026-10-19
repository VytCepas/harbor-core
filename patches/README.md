# Operator patches — edits an agent is not allowed to make

`permissions.deny` covers `.github/workflows/**`, deliberately: that deny exists
so an agent cannot rewrite the gate that judges it. It is not only `Edit` —
copying a workflow file to a scratch path to generate a unified diff is refused
too. So a change to CI arrives here, as prose plus exact replacement blocks, for
a human to apply by hand.

## Why this directory exists rather than `build/`

The first two of these lived in `build/`, which is **gitignored**. That was
discovered on 2026-08-06 when lint rule C5 shipped an advisory naming
`build/governance-change-class.patch.md`: the file was present on the machine
that wrote it and existed nowhere else — not in CI, not in review, not in any
other clone. `build/`'s own ignore rule states the reason it cannot hold these:
*"build/ is generated output, never a source."* A patch someone writes, reviews
and applies is a source.

`build/governance-suite-manifest.patch.md` had the same defect and had carried it
since it was written; it is tracked here now.

## The rule these follow

A patch is not a `patch(1)` hunk. Hunks carry line numbers, which a hand cannot
get right and which an agent here is not permitted to generate mechanically —
the one time that was tried, the hand-written hunk header was wrong on both the
start line and the counts. Each file states what to replace and what to replace
it with, in full, plus what to check afterwards and **what failure to watch
for**.

## Applying one

Read it, apply the edit, then run whatever the file's "After applying" section
names. Several of these are observable: lint C5's advisory disappears when the
change-class patch lands, which is the proof it landed rather than a claim that
it did.
