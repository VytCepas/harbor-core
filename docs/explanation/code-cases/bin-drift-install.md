---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/drift-install.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/drift-install.sh, lines 9-77 (before this edit)

```text
WHY THIS IS NOT ALREADY COVERED. Three things on this box compare an install
against something, and none of them asks this question:

  admission-integrity.sh (B6)  pins the box to ITSELF — settings, plugins and
                           marketplaces against `.sec0-baseline.sha256`, plus
                           "every guard is present, non-empty, has the
                           kill-switch". A guard that is present, non-empty
                           and SIX WEEKS STALE passes all three.
  deploy-install-stamp.sh (#115)  gates the WRITE: "would this deploy remove commits
                           that are already live". It fires at deploy time and
                           says nothing between deploys.
  pin-instructions.sh (B8) pins INSTRUCTION surfaces (CLAUDE.md, skills,
                           hooks, plugins). `bin/` is not among them.
  drift-renew-check.sh (#44)     asks "is anything BUILT here not DEPLOYED", by
                           counting commits since the install stamp over each
                           installer's OWN declared payload.
  lint X2 / X2b            the closest siblings, and the ones to read first.
                           X2 walks `$ROOT/bin/*.sh` and compares each against
                           its twin in the live bin; X2b does the same for
                           `~/.local/bin`. Both already handle the hard part —
                           which SIDE is newer — and X2's header carries the
                           incident that taught it.

ALL OF THEM ENUMERATE FROM THE REPOSITORY. That is the gap, and it is the whole
reason this exists. X2 loops over repo files and asks "is this deployed";
renew-check loops over the installer's payload and asks "did this get out".
Neither ever lists the live directory, so a file that exists ONLY on the box —
in no repo tree and no installer payload — is not something they report; it is
something they cannot reach. X2 skips it at `[ -f "$LIVEBIN/$b" ] || continue`
before any comparison happens, because the loop never had it to begin with.

This enumerates `$DIR/bin` and asks what is unaccounted for. Verified
2026-09-05: in the same lint run that reported X2's one advisory, and with
`renew-check --live` printing `renew 0` — both correct — memory-log-token-save.sh sat
in the live floor holding a GitHub PAT, and neither could name it.

So the box was pinned to itself from three directions and to the repository
from none. Measured 2026-09-05: `memory-log-token-save.sh` was live in the floor's
`bin/`, handling a GitHub PAT, and existed in no branch, no commit and no
working tree of this repository. Nothing had ever reported it, because
nothing was asking.

WHY CONTENT AND NOT A COMMIT COUNT. The obvious check is "how many commits
has main moved since the install stamp". It was built that way first and the
measurement killed it: on 2026-09-05 the stamp read 14 commits behind while
all 48 installed files were byte-identical to `origin/main`. floor-install and
runtime-install write overlapping sets, so each stamp undercounts what the
other deployed, and a lag counter reports drift that is not there. A check
that cries wolf gets switched off, and a disabled check protects nothing
(CLAUDE.md No.2.11).

THE FOUR VERDICTS. Content alone cannot tell a stale copy from a hand-edit, so
git is asked instead of guessed. The live bytes are hashed with
`git hash-object`, which yields the same blob id git itself would store, and
that id is looked up in the path's history:

  current    blob == the blob at <ref>.
  stale      blob == the blob at some ANCESTOR commit for that path. The file
             is a real past version, so this is an undeployed change, and the
             number of commits since is reported.
  modified   blob matches <ref> and no ancestor. Nobody's deploy produced
             these bytes -- either a hand-edit or a file the repo has not seen.
  unsourced  the path does not exist at <ref> at all. Loudest of the four: a
             live floor file with no source of truth, which no deploy can
             reproduce and no review has read.

`stale` and `modified` are deliberately separate. Merging them would report a
missed deploy and an unreviewed edit to a security guard as the same event,
and only one of those is fixed by re-running the installer.
```

## bin/drift-install.sh, lines 93-96 (before this edit)

```text
EXIT 2 NEVER COMES WITHOUT A FAIL LINE AND ITS FIX (harbor#457). It used to leave one printf on stderr, so a caller
that relays the first FAIL (live-verify) could only say "exited 2: no FAIL line". The libs load before the arguments
are read for that reason (a --dir or --ref with no value included: dash dies on the second shift with no FAIL line);
the one exit 2 left outside is the line above, where the libs themselves cannot be found.
```

## bin/drift-install.sh, lines 127-129 (before this edit)

```text
NO INSTALL TO COMPARE IS NAMED BY ITS CAUSE (harbor#457): a box with no config dir, or no settings.json, has had no
first-run step, and one with a config dir but no bin/ has had no deploy (unless .harbor-manifest says one ran). The
first has a command only on the live box.
```

## bin/drift-install.sh, lines 142-144 (before this edit)

```text
A ref that does not resolve must ABORT, never silently classify every file as
`unsourced` -- that failure mode reports a clean box as catastrophically
broken, which is the same false-positive trap in the other direction.
```

## bin/drift-install.sh, lines 154-159 (before this edit)

```text
WHERE AN INSTALLED FILE COMES FROM (harbor#763). bin/<name> is bin/<name> in the repo, except for
what runtime-install's SUITE ships from elsewhere: bin/recover-test.sh is tests/deploy/restore/recover.test.sh,
lib/core.sh is tests/lib/core.sh. The mapping is read from the installer AT THE REF, so the question
is always "what would that commit's installer have put here". Without it the suite read `unsourced`
on every run, forever, and a stale or hand-edited copy of it could never be told apart.
DATA ships the same way (docs/reference/checks.md, contracts/*.tsv into bin/), so it is read too.
```

## bin/drift-install.sh, lines 173-175 (before this edit)

```text
THE SET: every file in bin/ (a file only the box has is the finding this exists for), plus what the
install manifest (install standard §3) and SUITE record elsewhere — lib/core.sh — for the two installers
whose payload this check owns. The verdict never comes from the manifest: it is git's, below.
```

## bin/drift-install.sh, lines 180-181 (before this edit)

```text
A file a pack installed (its manifest in .harbor-packs, written by pack.sh) is that pack's, not this commit's, and
pack.sh refuses to write over a core file: so it is never `unsourced` here.
```

## bin/drift-install.sh, lines 189-192 (before this edit)

```text
THE REGISTER IS INSTALLED COMPOSED (harbor#1149): bin/docs/reference/checks.md is core docs/reference/checks.md plus the private layer's rows and the
rows of the packs installed in $DIR/checks.d, so
the blob it is held to is the composition of the register AT THAT COMMIT, never the bare core blob. With no private
layer the composition is core byte for byte, and the blob is the commit's own.
```

## bin/drift-install.sh, lines 195-196 (before this edit)

```text
The required-checks list is installed composed the same way (harbor#1149): bin/required-checks.tsv is core's rows plus the private
layer's required-checks.tsv, so it is held to the composition of the list AT THAT COMMIT; with no layer that is the commit's own blob.
```

## bin/drift-install.sh, lines 208-210 (before this edit)

```text
An install made before the list was composed is a bare older core blob, and one made when the private layer held other rows is an
older core with an older revision of the layer's file (the layer is a repo of its own and records them). Both are BEHIND, not edited
in place; only bytes no commit of either explains read modified (a layer row deployed uncommitted and since dropped, or an edit).
```

## bin/drift-install.sh, lines 237-239 (before this edit)

```text
Absent at the ref. It may still be a file the repo DELETED, which is a
different story from one it never had, so history is asked before the
louder verdict is used.
```

## bin/drift-install.sh, lines 254-255 (before this edit)

```text
Differs from the ref. Walk that path's history for these exact bytes; an engine moved into
hooks/<engine>/ (D-88) also walks its old bin/ path, or every copy from before the move reads modified.
```
