---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-deny-hash.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-deny-hash.sh, lines 10-13 (before this edit)

```text
THE GAP IT CLOSES. `admission-egress.sh` knows generic secret SHAPES — `sk-`, `ghp_`,
PEM headers. It cannot know *your* secrets, so it cannot catch an API key with an
unusual prefix, or a client's name. This closes that without the filter becoming
the leak: only salted, truncated digests are stored.
```

## bin/admission-deny-hash.sh, lines 15-27 (before this edit)

```text
── THE TERMS ARE DECLARED, NOT INFERRED, AND THAT IS THE DESIGN ─────────────

The obvious build reads the private corpus and decides for itself which tokens
are secret. That is a policy guess with a cost in both directions: guess narrow
and the filter misses the thing it exists to catch, giving false confidence;
guess wide and it blocks ordinary work, which is how a control gets switched off
(policy/constitution.md §2.11).

So the source of truth is `<cfg>/.helm-deny-terms`, authored by the operator: one
term per line, `#` comments ignored. `--propose` reads the corpus and PRINTS
candidates for review, writing nothing. That is the constitution's rule made
concrete — the system may observe continuously and propose in batch, and may not
promote its own observations into a control without a person approving them.
```

## bin/admission-deny-hash.sh, lines 29-44 (before this edit)

```text
── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────

NOT WIRED INTO A GUARD. `admission-egress.sh` is a B6 hash-pinned control surface, so
making it consult this filter needs a re-pin and is the operator's act (owner
decision 2026-08-05). This ships the filter and an offline scanner, so the
detection exists and is measurable before anything blocks a tool call on it.

SINGLE-TOKEN TERMS ONLY. Scanning digests each whitespace-delimited token of the
input and tests membership, so a multi-word phrase cannot match. Said out loud
because a filter that silently ignores half its terms is worse than one that
refuses them: `--derive` REJECTS a term containing whitespace rather than storing
a digest nothing will ever match.

DELIBERATELY ONE FILE (docs/explanation/modularity.md): three modes over one digest
primitive and one filter format. Splitting them would put two spellings of the
filter format in two files, and the format is the whole contract.
```

## bin/admission-deny-hash.sh, lines 62-66 (before this edit)

```text
OPERANDS STAY IN "$@", NEVER IN A SPACE-JOINED STRING (PR #127 review). The first
cut accumulated `FILES="$FILES $1"` and later expanded it unquoted, so a filename
containing a space was split into two nonexistent paths — and because the reader
swallowed errors, the scan then reported CLEAN. Re-queueing each operand onto the
positional list preserves it byte-for-byte, whatever is in it.
```

## bin/admission-deny-hash.sh, lines 87-95 (before this edit)

```text
THE HASHER IS DERIVED, NEVER RE-IMPLEMENTED. floor_obs_digest owns the algorithm
— salt, separator, truncation length — and a second spelling here would drift
silently and stop matching, which for a leak filter fails toward MISSING a hit.

SOURCED FROM THE SIBLING, NEVER FROM THE INSPECTED DIRECTORY. Sourcing
`<cfg>/bin/library-admission.sh` executes a file out of the tree under inspection; a
hostile copy could redefine the digest to a constant and every scan would come
back clean. `$SELF/library-admission.sh` is the same trust domain as this script. The
SALT still comes from the inspected dir, which is data, not code.
```

## bin/admission-deny-hash.sh, lines 107-117 (before this edit)

```text
── ONE TOKEN ALPHABET, USED BY BOTH SIDES (PR #127 review) ──────────────────
`--derive` hashes whole terms; `--scan` hashes the tokens it finds in the input.
If those two disagree about what a token IS, a term can be stored and never
matched — `--derive` reports coverage for something no scan can ever hit, which
is the same silently-inert failure the multi-word refusal exists to prevent.
Measured examples that the first cut accepted and could never match:
`client:api/key` (`:` and `/` are separators to the scanner) and a base64 token
ending in `=`.

So the alphabet is defined ONCE, here, and both the round-trip check and the scan
tokenizer read it. A second spelling is the drift the T rules exist for.
```

## bin/admission-deny-hash.sh, lines 130-134 (before this edit)

```text
WRITES, SO IT IS GATED (lint D2). The default target is the active config dir,
which on the operator's machine IS the live one — so a bare --derive would
write a filter into ~/.claude because nobody named anywhere else. Resolved-path
compare, because a trailing slash or a symlinked route spells the same
directory differently.
```

## bin/admission-deny-hash.sh, lines 143-152 (before this edit)

```text
── THE TERMS FILE IS THE SECRET, AND IT IS PLAINTEXT ──────────────────────
The FILTER contains no secret in the clear, which is the ticket's promise. The
TERMS file necessarily does: the operator wrote the strings into it. So this
design does not remove a plaintext secret from the box, it adds one — and
saying so is the difference between a control and a comforting story.

Warned, never silently fixed: chmod-ing a file the operator authored is
modifying their content. Neither this file nor the filter is in
`permissions.deny` or the file-tool guard's protected set today; by M10's tier
table both are tier 0, so closing that is an operator act.
```

## bin/admission-deny-hash.sh, lines 169-171 (before this edit)

```text
A TERM WITH WHITESPACE IS REFUSED, NOT SILENTLY STORED. Scanning is
token-wise, so a phrase's digest could never match anything and the operator
would believe it was covered.
```

## bin/admission-deny-hash.sh, lines 177-179 (before this edit)

```text
…and the general case the whitespace check only covers a slice of: any
separator outside the scan alphabet splits the term, so its stored digest
could never be produced from real content.
```

## bin/admission-deny-hash.sh, lines 192-193 (before this edit)

```text
0600: the filter is not a secret, but it is a fingerprint OF one, and an
offline dictionary attack over a guessable term space is cheap.
```

## bin/admission-deny-hash.sh, lines 203-208 (before this edit)

```text
READ-ONLY BY CONSTRUCTION: this mode has no write path at all. It prints
high-signal shapes out of the private corpus for the operator to curate into
the terms file. It does NOT decide what is secret — see the header.
Corpus paths are collected onto the positional list rather than a space-joined
string, for the reason recorded at the argument loop: a path containing a space
becomes two nonexistent paths, and the reader then finds nothing.
```

## bin/admission-deny-hash.sh, lines 239-244 (before this edit)

```text
AN UNREADABLE INPUT IS REFUSED, NEVER SCANNED AS EMPTY (PR #127 review). The
first cut ran `cat $FILES … 2>/dev/null || :`, so a missing path, a permission
error, or a filename split on a space left the buffer empty or partial — and the
scanner then printed `clean` and exited 0 over content it had never read. For a
leak filter that is the worst available outcome: a confident all-clear on an
unexamined file. Checked BEFORE reading, so the refusal names the path.
```

## bin/admission-deny-hash.sh, lines 256-259 (before this edit)

```text
Tokens deduped BEFORE hashing: one sha256 fork per distinct token, not per
occurrence. No length floor is applied: --derive is the only writer of the filter
and it stores whatever the operator declared, so skipping short tokens here could
hide a hit.
```

## bin/admission-deny-hash.sh, lines 269-273 (before this edit)

```text
$FLOOR_GREP, NEVER a bare grep (lint F3), and here it is load-bearing rather
than stylistic: this box's grep is a ugrep wrapper carrying -I --ignore-files,
which silently skips inputs it judges binary or ignored. A skipped filter file
makes every membership test MISS, and for a leak filter that is the dangerous
direction — a scan that reports clean over content full of declared terms.
```

## bin/admission-deny-hash.sh, lines 276-277 (before this edit)

```text
THE MATCH IS REPORTED BY DIGEST, NEVER BY VALUE. Printing the token would
make this tool the leak it exists to prevent — including into a CI log.
```
