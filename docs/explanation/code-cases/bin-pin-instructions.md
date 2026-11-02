---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/pin-instructions.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/pin-instructions.sh, lines 8-40 (before this edit)

```text
WHY THIS EXISTS: ~/.claude/CLAUDE.md, agents/, skills/, commands/ and
output-styles/ are loaded into every FUTURE session. Anything written there is
an instruction the model will follow tomorrow — capability injection on a
one-session delay. guard-selfedit protects only the floor's own teeth, and B6
hashed settings.json, so all five were unwatched.

"B6 HASHED settings.json" WAS A CLAIM ABOUT FOUR FIELDS, NOT ABOUT THE FILE,
and reading it as the latter is what left a seam nobody owned (harbor#221): a
slash command rewrote settings.json through the harness config writer — not
Edit, not Write, so neither permissions.deny nor guard-selfedit saw it — and
the new top-level key sat outside B6's projection while B8's surface list does
not contain settings.json at all. B6 now projects the whole `.permissions`
object plus the top-level key NAMES, so the sentence above is true of the file
and not only of a corner of it. THE DIVISION, stated once so neither gate has
to guess: B6 owns settings.json; B8 owns the instruction surfaces around it,
and deliberately does not list it.

The owner's stance is that these stay WRITABLE (upstream's "you may edit
~/.claude freely"). This does not change that. It removes the SILENCE: the
manifest is compared at every SessionStart and drift is reported by path.

Re-pinning is DELIBERATE and manual by design. If drift auto-pinned itself the
gate would report every injection exactly once and then bless it. The live dir
needs an explicit --live (install-lib's il_target, lint D7): this script KNOWS
its resolved target, so the check is exact, where guard-bash's text scanner was
broken six ways in pass 10.

ORDER (harbor#457): pin AFTER the install. The pin records what is on the instruction surfaces now, so one taken
before deploy would read everything deploy then installs as drift. It stays a path and not a `harbor` verb
(contracts/cli.md: the settings.json mutators are never hidden behind a friendly verb). Before deploy it is still
reachable from the checkout, `sh <checkout>/bin/pin-instructions.sh --apply --live`, which is how deploy spells it;
the copy under <config dir>/bin, which the floor installer spells, exists only once a deploy has put it there.
NO .harbor-manifest ROWS (install standard §3): the pin is B8's own state, never an installed file.
```
