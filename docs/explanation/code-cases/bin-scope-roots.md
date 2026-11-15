---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/scope-roots.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/scope-roots.sh, lines 30-47 (before this edit)

```text

WHY. Measured 2026-09-23: 91 non-comment, non-markdown lines here name a repo
root and 13 go through an override variable. Those 13 were written one at a
time, and two of them (PROJECT_INIT_SRC, HARBOR_SCOPE_SCAFFOLDER) are different
names for one repo. A default written at its use site reads correctly forever
while drifting from every sibling, because nothing ever compares them.

THE MOVE IS WHY THE BASE IS SYMBOLIC. harbor#619 moves every governed repo
under PORT_ROOT. With the base named rather than spelled, that is ONE edit in
repos_prefix() below; without it, it is an edit at each site plus a hunt for
the ones that never used a variable at all.

DELIBERATELY NOT READ BY THE FLOOR. bin/library-admission.sh keeps its own literal
default for PORT_ROOT, and ROOT1 checks the two agree. The floor is POSIX,
hash-pinned per file (B6) and must answer with no I/O it does not control; a
guard that resolves its stop by reading a TSV gains a file that can be absent,
truncated or edited between the pin and the call. One source of TRUTH does not
require one source of BYTES — it requires a check, and that is ROOT1.
```

## bin/scope-roots.sh, lines 50-52 (before this edit)

```text
${0%/*}, not $(dirname -- "$0"): a failed fork or dirname off PATH makes the
dirname call empty, `cd -- ""` silently stays put, and SRC becomes whatever
the SESSION's cwd happened to be (harbor#810, #813).
```

## bin/scope-roots.sh, lines 66-68 (before this edit)

```text
harbor#961 W5: the roots that took registered names (standards/naming/renames.tsv), old TAB new. Until 2026-11-15 an
old name is still asked for (a sibling repo, a pack's shims.tsv, a private plist's @NAME@) and still read as an
override when the new one is unset: the dual-read window. Past it, delete the line and the old name is refused.
```

## bin/scope-roots.sh, lines 79-89 (before this edit)

```text
The one line the ~/port move edits. Returns the LITERAL TEXT a default is
expected to spell, not a resolved path — ROOT1 compares source text, and
`$HOME` in a script is four characters, not a directory.

harbor#619 moved every governed repo to $HOME/port on 2026-09-23, so this is
that edit. It is the DEFAULT's spelling, and a site may spell it two ways, both
read by --check: flat (the home-relative text, which IGNORES an exported PORT_ROOT and
is refused for a REPOS row, harbor#630) or nested
(PORT_ROOT with that text as its own default, which honours it). --check reads a default with a
pattern that steps over ONE nested ${...}, and normalises the nested spelling
back to this text before comparing, so the table still holds one spelling.
```

## bin/scope-roots.sh, lines 101-103 (before this edit)

```text
The same base as a PATH on this box. REPOS is the workspace root, so it honours an exported
PORT_ROOT; the text above is for comparing source, this is for resolving it (harbor#630: a
fresh machine with another root used to get the home-relative default from --get, --list and --repos).
```

## bin/scope-roots.sh, lines 165-168 (before this edit)

```text
The access register: account, role and route cards (contracts/access-card.md). They name accounts,
so they are private data and core ships none. $ACCESS_DIR, when set, wins as every override here
does. A register that is not there is exit 1 with nothing on stdout and the reason on stderr, so a
reader says "no register" and never cd's, reads or passes against an empty path (harbor#1149).
```

## bin/scope-roots.sh, lines 182-186 (before this edit)

```text
The private rules (contracts/private-layer.md, harbor#1149): <private>/context-rules, the shape of core's context-rules/ -
user/ for the rules every session on the box carries (and the project registry), one folder per repo for the rules
`context-injection-install.sh --projects` seeds. They name clients and repos, so core ships none. Nothing in it is code: the
installer takes .md packs and projects.tsv only. Absent is exit 1 with nothing on stdout and the reason on stderr,
so a reader says "no private packs" and never reads or seeds an empty path.
```

## bin/scope-roots.sh, lines 211-217 (before this edit)

```text
Rows validated and printed as id TAB path TAB kind TAB remote TAB topology TAB interaction TAB note TAB domain TAB governed
TAB owner TAB covers (a shorter row prints '-' for what it lacks, harbor#966). A row that would resolve outside
PORT_ROOT, repeat an id or a path (case-insensitively) or has other than four, six, seven or eleven fields refuses the
whole read (exit 2): a lookup that skips a bad row answers "unknown" for a repo that is only
mistyped. One trailing / on a path is dropped. This pass is lexical; confine() follows symlinks.
Kinds, topologies and interaction modes are judged only when a kinds file is given (--registry-check), so a
lookup never fails over a vocabulary edit. The two Team Topologies vocabularies are contracts/private-layer.md's.
```

## bin/scope-roots.sh, lines 304-307 (before this edit)

```text
A ROLE REPO FOLLOWS THE REGISTRY BY KIND (harbor#966). The table names the scaffolder and the fleet controller
by their checkout's id, and a rename changes a registry row's id and path but never its kind, so looking the
table's id up would answer the old name. Exactly one row of the kind is the answer; none or two (a rename
window that briefly lists both) fall back to the id, today's lookup.
```

## bin/scope-roots.sh, lines 323-326 (before this edit)

```text
harbor.toml, the flat subset: key = "value" or key = ["a", "b"] on one line, # comments, no tables.
Unknown keys, tables, duplicate keys, a backslash or an empty string inside a value and any other
shape are refused (exit 2): a typo read as "unset" would silently install the default. Values print
raw; an array prints one per line.
```

## bin/scope-roots.sh, lines 365-367 (before this edit)

```text
The harbor.toml keys: core's own, then every key an installed pack declares in its conf-keys.txt
(installed at <config dir>/conf-keys.d/<repo-id>.txt by bin/pack.sh), so core names no pack's key
(#949, contracts/pack.md). Three former core keys left after one release, once their pack declared them (#1273).
```

## bin/scope-roots.sh, lines 406-407 (before this edit)

```text
harbor#961 W5: two repo roots took registered names. Until 2026-11-15 the old name is still asked for (a
sibling repo's call) and still read as an override when the new one is unset (renames.tsv dual-read window).
```

## bin/scope-roots.sh, lines 411-414 (before this edit)

```text
The caller's own override still wins — the table supplies the DEFAULT,
never the answer. A resolver that ignored an exported value would make
every override in the tree a lie. The name is a table row (matched
exactly above), so the indirection below cannot be handed a command.
```

## bin/scope-roots.sh, lines 529-532 (before this edit)

```text
1 · every site's default equals the table.
    Reading the INDEX via git grep, not the working tree: grep here is
    ugrep and skips gitignored files, which would report a clean tree by
    not looking at it.
```

## bin/scope-roots.sh, lines 541-543 (before this edit)

```text
Every occurrence of ${VAR:-...}, whatever surrounds it.
One nested ${...} is stepped over (the PORT_ROOT spelling); [^}$] and \$[^{}] keep the
alternation unambiguous, so a flat default and a nested one both read to their own end.
```

## bin/scope-roots.sh, lines 557-560 (before this edit)

```text
THREE SHAPES ARE NOT A DISAGREEMENT, and each was measured on this
tree before the list existed. A rule that flagged them would fire on
correct code, and a rule that fires on correct code gets switched
off (CONSTITUTION No.2.11) — taking the real disagreements with it.
```

## bin/scope-roots.sh, lines 564-567 (before this edit)

```text
deriving the repo from $0. Strictly better
than a literal: it survives the move with no
edit at all, which is the outcome this table
is trying to buy.
```

## bin/scope-roots.sh, lines 589-593 (before this edit)

```text
2 · a ${VAR:-...} naming a governed repo whose VAR is NOT in the table.
    This is the arm that catches the NEXT one, and the reason the table is
    a gate rather than a list: a list only records what someone remembered.
    The repo ids are the registry's (repos_list), never a list here (harbor#1273): no registry is the
    roots table's repos alone, so this arm sees fewer repos and says so. Ids are [A-Za-z0-9._-]; dots escaped.
```

## bin/scope-roots.sh, lines 599-611 (before this edit)

```text
    Anchored on a default that STARTS with the home prefix: `${BIN:-$_self_dir,
    $HOME/port/harbor/bin}` in bin/harbor is a help STRING listing where it
    looked, not a root, and flagging it would be the false positive above
    wearing a different hat.
    `(port/)?` BECAUSE THE BASE MOVED (harbor#619). Anchored on `$HOME/<repo>`
    alone, this arm went blind the day every default became
    `$HOME/port/<repo>`: an unregistered root spelled the NEW way matched
    nothing and the check stayed green. Optional rather than required, so a
    new variable still spelling the pre-move address is caught too.
    And the nested spelling, for the same reason: a root written
    `${PORT_ROOT:-$HOME/port}/<repo>` must not hide from the arm that finds new ones.
    The repo name ends at / or the closing brace: `.../harbor-private` is the private
    layer (scope-roots.sh --private), a different root, not a spelling of harbor.
```

## bin/scope-roots.sh, lines 623-625 (before this edit)

```text
3 · a table row nothing uses. A dead row is not harmless: it is a rule
    that can never fire, and a suite of rules that can never fire is how a
    green run stops meaning anything.
```

## bin/scope-roots.sh, lines 633-638 (before this edit)

```text
4 · two variables for one path need a stated reason. The table showed
    PROJECT_INIT_SRC and HARBOR_SCOPE_SCAFFOLDER as one repo under two names, and
    nothing recorded whether that was a decision (harbor#630). Merging them
    changes an env contract suites and operators set by hand, so the pair
    stays; what is refused is a pair nobody explained. The reason is the fifth
    column of EVERY row sharing the path (no # in it: a # starts a comment).
```

## bin/scope-roots.sh, lines 649-651 (before this edit)

```text
The per-hit FAILs above are printed live, from inside a piped subshell (harbor#630's own
fix for the same problem this file's loops have): their counts do not survive back to this
shell. This FAIL, called here in the parent, is what log_end actually tallies and exits on.
```
