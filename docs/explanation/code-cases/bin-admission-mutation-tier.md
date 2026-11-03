---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/admission-mutation-tier.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/admission-mutation-tier.sh, lines 10-13 (before this edit)

```text
protected, which is the right shape for a veto and the wrong shape for a
question like "may a rule be strict about settings.json and relaxed about a
cache". Tiers are that second question, and they are what a later rule would
read. Nothing reads them yet, deliberately — see below.
```

## bin/admission-mutation-tier.sh, lines 15-26 (before this edit)

```text
IT CHANGES NO GUARD BEHAVIOUR, AND IT IS NOT INERT EITHER. A tier table nothing
reads is a wish (policy/constitution.md). What makes this one load-bearing without
moving a B6 hash-pinned surface is `tests/admission/mutation-tier/mutation-tier.test.sh`: it fires the REAL
admission-self-edit.sh at every fixture path and re-reads the whole permissions.deny
array, so the table and the surface cannot drift apart. A divergence fails CI.

DELIBERATELY ONE FILE (docs/explanation/modularity.md): one predicate plus two
renderers over one fixture. Splitting the classifier from the reporter would put
two spellings of the tier globs in two files, and the globs are the whole rule.

READ-ONLY. It writes nothing anywhere, in any mode. The classifier prints data; the report's own
lines are log-lib's (contracts/logging.md, harbor#771), and its table stays data between them.
```

## bin/admission-mutation-tier.sh, lines 54-60 (before this edit)

```text
TRAILING SLASHES ARE STRIPPED (PR #126 review). `rel_of()` matches the prefix
`"$CFG"/*`, so a config dir spelled `~/.claude/` made the boundary a DOUBLE
slash: `$CFG/settings.json` no longer matched, and the classifier reported
`outside` — silently stopping judging every path — for one of the commonest
spellings, and for `CLAUDE_CONFIG_DIR` values that legitimately carry one. The
rest of the floor normalises trailing slashes, so a reader that does not is the
odd one out. `/` itself is left alone rather than reduced to the empty string.
```

## bin/admission-mutation-tier.sh, lines 64-72 (before this edit)

```text
Matched against the path RELATIVE to the config dir, lowercased, because APFS is
case-insensitive by default: `Settings.json` reaches the same inode, and a
case-sensitive POSIX glob would call it tier 3. That exact one-character bypass
was found against admission-self-edit.sh in red-team pass 2, so this reader must not
reintroduce it.

ORDER IS THE RULE. `bin/*` is tier 1 while `bin/` under a pins directory is not a
thing — but `.helm-pins/*` must be tested before any broader glob, or a pin file
with a `.sh` name would classify as code. Most specific first, always.
```

## bin/admission-mutation-tier.sh, lines 95-115 (before this edit)

```text
rel_of <path> — the path relative to $CFG, or the path itself when outside it.
Physical resolution is NOT attempted here: this is a classifier over a NAME, and
a name is all a caller may have (a path that does not exist yet still has a
tier). admission-self-edit.sh resolves physically before deciding, which is correct
for a veto and is a different job.
A PATH OUTSIDE THE CONFIG DIR IS NOT TIER 3, IT IS UNJUDGED — and conflating the
two was a real defect in the first draft. Everything unmatched fell through to
tier 3 ("ordinary, session-writable by design"), so asking about
/etc/passwd or a path under a DIFFERENT config dir returned a reassuring
"tier 3" about a file this classifier knows nothing about. A caller acting on
that would relax a rule over an unexamined path. It now says `outside`.
BOTH SIDES ARE NORMALISED, and trimming only `CFG` was a regression (PR #128
review). With a config dir spelled `/tmp/cfg/`, callers build the target the usual
way as `$CFG/settings.json`, i.e. `/tmp/cfg//settings.json`. Trimming CFG to
`/tmp/cfg` then strips the prefix `/tmp/cfg/` and leaves `/settings.json` — with a
leading slash — which matches no tier glob and fell through to tier 3. The version
BEFORE the trailing-slash fix classified that exact shell-built path correctly, so
fixing one spelling had broken another.

Leading separators are therefore dropped after prefix removal. Interior doubles
need no handling: `bin//admission-bash.sh` still matches the `bin/*` glob.
```

## bin/admission-mutation-tier.sh, lines 127-128 (before this edit)

```text
guard_blocks fires the REAL guard, in a sandbox config dir, because asking a
case glob whether the guard would block is asking a copy of the guard.
```

## bin/admission-mutation-tier.sh, lines 130-133 (before this edit)

```text
`-r`, NOT `-x`: the guard is invoked as `sh <file>`, so readability is what
matters and the repo copies are 0644. Testing for the exec bit reported
`unknown` for every path — a whole column of "could not tell" that read as if
the probe had run.
```

## bin/admission-mutation-tier.sh, lines 135-141 (before this edit)

```text
THE PARENT DIRECTORY MUST EXIST, and leaving it out was a false-positive
factory. guard-selfedit resolves the target PHYSICALLY (floor_norm_path) before
matching, and an unresolvable path keeps a spelling the protected globs miss —
so `.helm-pins/x` and `hooks/h.sh` both reported "not protected" against a
sandbox that had no such directories, and the report printed "UNPROTECTED at
tier 1" for a path the guard demonstrably blocks. A probe that does not
reproduce the real tree measures the probe (§2.6).
```

## bin/admission-mutation-tier.sh, lines 149-151 (before this edit)

```text
deny_covers reads the WHOLE array and matches the entry's glob against the path,
rather than grepping settings.json for a substring — a deny entry naming a
neighbouring path would otherwise read as coverage.
```

## bin/admission-mutation-tier.sh, lines 155-169 (before this edit)

```text
`**` crosses directory separators, a single `*` does not. Translated through a
DOT ESCAPING IS ONE BACKSLASH, NOT TWO. `"\\\\."` is the jq string `\\.`, which as a
regex means "a literal backslash then any character" — so `settings.json` compiled
to `settings\\.json` and matched NOTHING, and every path reported deny=no. The
discriminating check is that `settings.json` matches while `settingsXjson` does
not, i.e. the dot stayed literal instead of becoming a wildcard.
PRINTABLE placeholder, and the reason is worth keeping: the first version used a
literal NUL, which worked correctly and made the whole script read as "binary
data" to this box's ugrep-backed grep. Lint D1 then reported a hardcoded live
config dir that does not appear in the file at all, because its pipeline saw
"Binary file matches" as a hit. A working trick that breaks the tools reading
the file is not a working trick.
placeholder rather than a lookbehind: `**` -> DBLSTAR -> `.*`, and any
remaining `*` -> `[^/]*`. A lookbehind works in jq's Oniguruma but is the kind
of cleverness that fails silently on a jq built without it.
```

## bin/admission-mutation-tier.sh, lines 178-181 (before this edit)

```text
BIND THE ENTRY FIRST. `$p | test("^" + (. | glob2re) + "$")` rebinds `.` to
$p for the whole pipeline INCLUDING the argument, so every entry compiled
the PATH as its own pattern and matched itself — the report claimed every
path was deny-covered, `cache/x` included. Measured, not theorised.
```

## bin/admission-mutation-tier.sh, lines 213-214 (before this edit)

```text
The product of this ticket: where the two enforcement layers DISAGREE about one
path. Neither layer can see the other, and nothing until now compared them.
```

## bin/admission-mutation-tier.sh, lines 243-246 (before this edit)

```text
A tier 0 or 1 path with only ONE layer behind it is the finding. Deny is
un-swallowable and evaluated before hooks; guard-selfedit is documented
FAIL-OPEN on a parse error. So each missing layer costs something different,
and the note says which.
```
