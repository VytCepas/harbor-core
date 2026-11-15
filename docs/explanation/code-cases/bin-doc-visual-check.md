---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/doc-visual-check.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/doc-visual-check.sh, lines 5-15 (before this edit)

```text
THREE MECHANISMS, NONE OF THEM REDUNDANT. Lint H1 reads CSS SOURCE and catches
a colour token with no dark value. This reads PIXELS and catches what source
arithmetic cannot — a token used on a surface it was not chosen for, an
inherited colour, a hand-written literal. archify's own visual-check reads
GEOMETRY — containment and projected text size at desktop widths — and greps
zero times for contrast. Measured on 2026-08-31/09-01: H1 found 1 defect, this
found 12 more that H1 passes cleanly, and archify found 12 more that BOTH pass.

Which verifiers a page gets is decided per page, by a marker the RENDERER
declares — see the routing block at the foot of this file.

```

## bin/doc-visual-check.sh, lines 20-30 (before this edit)

```text

WHY `--generated` EXISTS, and it is not a quieter default. The bare form checks
everything under docs/ and build/, which is right for a person: a page that
ships is a page that must be legible, whoever made it. But build/ is gitignored
scratch, so it accumulates artifacts no generator owns — on 2026-09-01 an audit
page written by hand on 08-13, failing AA at 4.09:1, with no source to fix. A
SUITE that goes red on that is a suite the operator switches off (No.2.11), and
one that skips build/ entirely stops checking real pages. `--generated` is the
third answer: check exactly what the repo can rebuild from source, which is
what CI can hold anyone to.

```

## bin/doc-visual-check.sh, lines 31-47 (before this edit)

```text
EXIT CODES ARE A CONTRACT (D-29): 0 pass, 1 fail, 2 usage, 3 UNCHECKED. Unchecked
means the verifier was unavailable (no node, no Playwright, no Chrome): nothing was
judged, and it is never reported as a pass — an unavailable verifier defers, it does
not get substituted with weaker evidence (CONSTITUTION No.2.7). Before D-49 that was
exit 2, "SKIPPED"; a reader that must still meet an old copy accepts 2 as well and
marks the line `D-49 window`.

NOT IN contracts/suites.txt, deliberately, and this is the open decision:
the check needs a Chrome channel, which the self-hosted runner is not known to
have. A suite entry that silently skips on the runner is the vacuous-gate
shape C3 exists to prevent, so wiring it in is gated on either proving Chrome
on the runner or accepting exit 3 as a distinct CI state.

THE NODE HALF IS bin/doc-visual-check.mjs. Two runtimes for one gate is a
deviation from the layer rule, recorded rather than hidden: Playwright is
Node-only and the shell owns the gate contract, so the seam is at the browser
boundary and nowhere else.
```

## bin/doc-visual-check.sh, lines 63-64 (before this edit)

```text
A flag this script does not know is a usage error (2, D-29), judged before anything that can be unavailable, so a
typo is never read as a missing verifier. A page whose name starts with `-` is written `./-name.html`.
```

## bin/doc-visual-check.sh, lines 76-78 (before this edit)

```text
THE NODE HALF PRINTS TAG LINES (ok, FAIL, fix, skip, note) and this says each one through the library, so a
FAIL is counted, followed by its fix, and written to the log. Its exit code (0 pass, 1 fail, 2 usage,
3 unchecked) is left in $_PRC. A FAIL is held until its fix arrives, so log_fail and log_fix stay adjacent.
```

## bin/doc-visual-check.sh, lines 100-106 (before this edit)

```text
THE SECOND VERIFIER LEAVES EXHAUST, and naming two of its files by hand left
the rest on disk: `archify visual-check` writes a receipt, a contact sheet AND
one PNG capture per viewport per theme — measured 2026-09-02, sixteen files and
2.0 MB per sweep, growing with every run. A checker that litters the directory
it is judging is a checker whose next run reads its own droppings, and build/
being gitignored only hides it. One prefix, one glob, and `_sweep_exhaust` is a
function rather than a line so the self-test can exercise the SAME code.
```

## bin/doc-visual-check.sh, lines 112-116 (before this edit)

```text
A CHECKER THAT CANNOT FAIL IS WORSE THAN NO CHECKER (No.2.10). Two fixtures,
one each way: a page that is legible must pass, and the same page with one
colour walked toward its background must fail. The control is the half that
matters — without it a checker that returns "fail" unconditionally scores
perfectly on the red arm.
```

## bin/doc-visual-check.sh, lines 126-128 (before this edit)

```text
`|| _rc=$?` AND NOT A BARE CALL: under `set -e` a probe that exits 1 aborts
this script before the case can read it, so the red arm never runs and the
self-test reports one pass and a silent exit 1 — which is what it did.
```

## bin/doc-visual-check.sh, lines 143-148 (before this edit)

```text
THE THIRD ARM IS A CONTROL ON AN EXEMPTION, not on this checker. The gate
below drops archify's `viewer/viewport-overflow` because at v2.16.0 it fires
on archify's OWN bundled example — so the exemption is only defensible while
that stays true. This renders that example and asserts it still fails. When a
re-pin makes it pass, this arm goes red and the exemption must be deleted:
the mechanism that stops a measured workaround becoming folklore.
```

## bin/doc-visual-check.sh, lines 167-173 (before this edit)

```text
A FOURTH ARM, ON THE CLEANUP ITSELF, because the leak it closes was invisible
from every green result: the gate passed, the report was correct, and 2.0 MB
of capture PNGs accumulated beside the pages under test on every run. The
fixture carries one of EACH shape archify actually writes — receipt, contact
sheet, and a capture per viewport per theme — and the arm asserts the page
survives and nothing else does. Naming two of them by hand is exactly what
shipped, so the fixture is what stops that returning.
```

## bin/doc-visual-check.sh, lines 203-217 (before this edit)

```text
RENDER FRESH, BUT NEVER INTO THE REPO. This gate ran `status-dashboard-generate.sh` only
when build/dashboard.html was ABSENT, so on 2026-09-01 it scored a palette fix
against output written before the fix and reported twelve failures that no
longer existed. Regenerating in place fixed that and broke something worse:
lint D2 immediately flagged this file as a mutator, and it was right — a
checker that rewrites two generated pages turns a clean tree dirty and would
leave CI with a non-empty `git status`. So the pages are rendered to a temp
directory through each generator's STDOUT mode and checked there. Nothing under
the repo is written.

BOTH HALVES ARE DERIVED FROM THE GENERATOR'S OWN SOURCE, never listed here: it
declares its destination as `OUT="$ROOT/..."`, and it declares whether stdout
needs a flag — `status-dashboard-generate.sh` writes by default and prints with `--stdout`,
`doc-index-generate.sh` prints by default and writes with `--apply`. Adding a generator
that follows either convention enrols it with no edit to this file.
```

## bin/doc-visual-check.sh, lines 237-241 (before this edit)

```text
DISCOVERY IS RECURSIVE, because build/<client>/*.html is a surface too and a
top-level glob never saw it. Three exclusions: a page just rendered fresh above
(checking the stale twin as well would report a defect already fixed), and
archify's own `<name>.visual-check.html` contact sheets — a checker that grades
its own exhaust is a loop.
```

## bin/doc-visual-check.sh, lines 250-251 (before this edit)

```text
GREEN OVER ZERO PAGES IS A FAILURE, not a skip. A gate that renders nothing
and prints a pass teaches the reader that it was checked.
```

## bin/doc-visual-check.sh, lines 262-277 (before this edit)

```text
THE SECOND VERIFIER, AND IT IS NOT A DUPLICATE. archify ships its own
visual-check; measured at v2.16.0 it runs four DESKTOP viewports up to
2048x1320 and asserts layout containment and projected text legibility, and it
greps zero times for contrast, luminance or WCAG. Ours asserts AA contrast at a
720px narrow viewport and nothing about geometry. Neither subsumes the other,
so an archify-rendered page gets both. TWO DECLARED MARKERS, because a diagram
reaches a reader two ways: archify's own page stamps `data-preset` on <html>,
and a report that embeds the figure carries `<figure class="af">`. Both are
written by a renderer, never inferred from content. A bare search for
`data-preset=` was the first attempt and it was wrong for a reason worth
recording: the embedded stylesheet defines each preset AS A SELECTOR, so every
page carrying the fragment matched — right answer, wrong question, and the next
page to mention the string in prose would have been routed too.
AN ABSENT SECOND VERIFIER IS ANNOUNCED, NEVER SILENT (No.2.7). Without this the
gate would print a clean pass over pages whose geometry nobody checked, which is
substituting weaker evidence and calling it the same result.
```

## bin/doc-visual-check.sh, lines 288-293 (before this edit)

```text
ONE DIAGNOSTIC CLASS IS EXEMPT AND THE SELF-TEST IS WHAT KEEPS IT HONEST.
`viewer/viewport-overflow` fires 6/6 on archify's OWN bundled example at this
pin, so gating on it would import a guard that upstream cannot pass — the
false positive of No.2.11, which ends with the guard switched off. Everything
else archify reports is taken: `viewer/projected-text-readability` caught a
real defect here that our probe cannot see, and `archify validate` passes.
```
