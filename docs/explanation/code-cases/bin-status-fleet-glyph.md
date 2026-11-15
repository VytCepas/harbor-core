---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/status-fleet-glyph.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/status-fleet-glyph.sh, lines 6-110 (before this edit)

```text
FOUR ROWS, ONE QUESTION EACH (operator decision 2026-10-16, layout B of
~/Deliverables/2026-10-15-statusline-redesign; it replaces the three cadence rows of
2026-07-29 and 2026-10-05):
  row 1  SESSION — the moving numbers, all from the stdin JSON, zero extra reads
  row 2  PLACE   — which session (its title, up to 64 columns), which repo and branch,
                   which PR, how many sessions are live
  row 3  YOU     — what waits on the operator: handoffs and approvals from
                   the obligations ledger, then every alarm word, coloured by severity.
                   ABSENT when nothing waits, so colour on this row always means act
  row 4  BOX     — network, Remote Control, CPU, GPU, RAM, disk, CI and the fleet
EMOJI ONLY WHERE A GLYPH SAYS MORE THAN A WORD (operator, 2026-10-16: "just in some
places where it makes sense"): two-state facts (🏠🔒🔓 network,
📱📵 Remote Control) and the nautical nouns the line started with (operator, same day): ⛵ live
sessions and ⚓ fleet berths. No emoji on the YOU row, the cache or a level. Numbers keep their
word labels (ctx, 5h, CPU, RAM, SSD, swap). ONLY yellow and red carry colour: informational
tokens are plain, dim or grey, like the session title and the cache share. Every emoji is East-Asian-width W (§2); alarms stay WORDS (§3).

── THE 2026-08-23 REDESIGN, AND THE FOUR MEASUREMENTS BEHIND IT ─────────────

1 · ALARMS MOVED LEFT, AMBIENT MOVED RIGHT. The statusline docs state that
  system notifications (MCP errors, auto-updates) render on the RIGHT SIDE OF
  THE SAME ROW and "may truncate your status line output". The loudest token on
  this box — `renew`, four merged floor commits that gate nothing here — was in
  exactly that column. Truncation must destroy the LEAST important token, so
  ordering was: alarms · identity · pin · inventory · age.

  REVERSED 2026-08-24 to identity · inventory · age · alarms, at the operator's
  request and with this cost put to them in these words. The note at the print
  block carries the decision; this paragraph is left standing because it is the
  argument AGAINST it, and a reversal whose counter-argument has been deleted is
  one nobody can re-examine.

2 · ICONS ARE EMOJI-PRESENTATION ONLY, AND THERE ARE THREE — four until the
  pushpin was cut on 2026-08-24, and the width rule here is unchanged and binds
  any icon added later. The operator
  reported seeing "nothing apart from the anchor", and the reason is measurable:
  `unicodedata.east_asian_width` is **W** for the anchor and the sailboat, and
  **N** for the pencil, the up-down arrow and the bare warning sign. A narrow
  text-presentation dingbat is not drawn from the colour-emoji font, so it
  renders thin or not at all. Every icon here is verified W (two columns), and
  the width tiers below count them as two.

3 · ICONS NAME NOUNS, ALARMS ARE WORDS. Kept from the earlier decision and now
  load-bearing: the operator read "⚓2 ⚠1" as "two anchors and one hat". An icon
  carrying an alarm is an icon that gets misread. So ⚓⛵📡 count things and every
  alarm is a word in caps. THE FOURTH ICON, 📌, WAS REMOVED 2026-08-24 — the
  recolour left it grey in both states, i.e. an icon that no longer answered its
  own question, and this rule is why it went rather than gaining a colour back.

4 · THE JUDGE IS ON THE ROW NOW, AND THAT WAS THE REAL DEFECT. This box had
  FOUR verdict surfaces and rendered one: the pin hash (green), `renew` (two
  gaps, far right), `.helm-judge` (crit=1 warn=62, INVISIBLE) and
  pulse-state.json (ok, invisible). A reader saw `floor✓` and concluded safe
  while the daily judge held a crit. Two different questions, one of them
  unasked. `floor✓` became 📌 — it only ever meant "the deny list matches its
  pin" — and is now the WORD PIN DRIFT alone (2026-08-24); the judge has its own
  token WITH AN AGE, because the crit that
  prompted this rested on a single record from three days earlier whose remedy
  had already run. A verdict with no age cannot be falsified.

WHAT IS DELIBERATELY ABSENT, AND WHY (do not "fix" these):
• No STORED countdown. The harness CANCELS an in-flight script when a new
  trigger arrives, so no field may assume it ran recently. Time renders as an
  age, or a time LEFT, computed at print time from an absolute epoch — never
  as a stored countdown. This bullet read "No countdown or ETA" until
  2026-09-23; row 1's reset time (harbor#84) was already a time-left computed
  this way, and ⏳'s CI estimate (harbor#657, operator request) is the second.
  The reason stands and binds both: what is stored is WHEN, never HOW LONG.
• No BURN RATE — but the earlier reason for that ban was wrong and is recorded
  here so it is not re-argued from it. The ban said a rate cannot be trusted
  because the script may not have run recently; that does not reach `$ ÷
  total_duration_ms`, where BOTH operands arrive in the same payload and
  nothing is stored between ticks. It is out because the operator cut it as
  noise (2026-08-23), which is a taste call and a legitimate one.
• No absolute token count beside `ctx N%`. Operator decision 2026-08-23: the
  model tile already states the window size, so a percentage is sufficient and
  the absolute is a second encoding of the same fact.
• No `>200k` threshold token. Operator decision 2026-08-24, and the argument
  against cutting it is recorded here because it was a real one: the harness
  reports `exceeds_200k_tokens` independently of window size, so on a 1M model it
  was the only sign on the row that the cheap-cache regime had been left. The
  operator does not want the fact, which settles it — a taste call about their own
  status row, the same class as the burn-rate cut above. `exceeds_200k_tokens`
  stays in the payload and stays unread. The suite asserts the ABSENCE both ways
  round, so this line is a rule rather than a note.
• No `blocks N`. It was a monotonic LIFETIME counter (4,719 against 102,012
  records) that no action could move, i.e. wallpaper by the third session.
  `ovr N` survives it: an override is the operator saying a rule is wrong with
  their hands, and it renders nothing until one happens.
• No cached floor verdict. /sbin/sha256sum exists on this box and costs 4.0ms
  measured (shasum 16.8ms), so the integrity check runs LIVE.

ALL ARITHMETIC AND FORMATTING HAPPEN IN jq. Two reasons, both measured:
rate_limits.used_percentage is utilization*100 with NO rounding
(0.417 -> 41.699999999999996), and POSIX `[ 41.7 -ge 85 ]` is not false — it is
an ERROR that `2>/dev/null &&` swallows into silence, i.e. a colour ramp that
never fires. And reading a TSV with IFS=<tab> COLLAPSES consecutive tabs, so
one empty field shifts every later field a column left and still looks
plausible. jq emits the finished string; the shell never parses a number.

NEVER invokes the orchestrator (REVIEW F6): a tick re-runs sub-second and a
live snapshot is a full-fleet scan. Fleet state is read from the cache written
by status-fleet-snapshot-refresh.sh (launchd com.harbor.status.fleet-snapshot, 5 min).
Absent/stale/invalid cache degrades to "fleet: unknown".

```

## bin/status-fleet-glyph.sh, lines 139-145 (before this edit)

```text
DARK GREY, AND IT IS A DIFFERENT THING FROM DIM (operator decision 2026-08-24).
`$E[2m` is a faint ATTRIBUTE applied to whatever colour is current, and several
terminals render it as plain or ignore it outright; `$E[90m` is bright-black, an
actual colour, so it is the same grey everywhere and it OVERRIDES an inherited
red or yellow rather than tinting it. That distinction is the whole reason this
variable exists: the harbor-state tokens below were red and yellow, and dimming
them would have left them red and yellow on most terminals.
```

## bin/status-fleet-glyph.sh, lines 148-179 (before this edit)

```text
── the separator grammar (operator request 2026-08-24) ──────────────────────
THREE RELATIONSHIPS WERE BEING CARRIED BY TWO SPACES AND ONE MIDDOT, and the
reader had to already know which was which. The reported case was
`$1.57  5h 1% ·4h13m  7d 49% ·1d19h`: four durations and two percentages, where
the only thing distinguishing "a different fact" from "more about the fact to my
left" was one space against two. That distinction does not survive a glance, and
it does not survive a terminal that renders spacing tightly either.

SO THE ROW HAS A GRAMMAR NOW, AND IT IS EXACTLY TWO MARKS. What separates them
is the TRAILING space, not the character — say it that way, because the first
draft of this comment said the middot takes no space before it, which is simply
untrue of every middot on the row:
  ` │ `  a DIFFERENT fact       — space, bar, space
  ` ·`   MORE ABOUT the fact on its left — space, middot, then the value with no
         gap: `5h 1% ·in 4h13m`, `⛵2 ·2 busy`
A single space with no mark is the third relationship and the commonest: "same
fact, next part of it" (`harbor main wt ~3 #294`).

AND TWO CONSECUTIVE SPACES NOW MEAN NOTHING AT ALL — they are the state this
change removed, so the suite asserts the rendered rows contain none. That one
assertion is the whole grammar-guard: any future token appended with the old
double-gap idiom fails it, and nothing else would have noticed.

A THIRD MARK EXISTS AND IS DELIBERATELY NOT OURS. `runtime4·floor5` is
drift-renew-check.sh's vocabulary, borrowed verbatim — see the note at the STALE tile
for why re-spelling another tool's naming here is a defect rather than a tidy-up.

ONE COLUMN, NOT TWO, AND THAT IS THE PART A TEST CANNOT SEE. U+2502 is
single-width where every emoji on row 2 is double. The tiers pick by which
tokens they include and never by measuring the finished string — this file's own
header explains why — so a separator that quietly changed width would widen
every row with nothing to catch it.
```

## bin/status-fleet-glyph.sh, lines 184-188 (before this edit)

```text
THE RAW PAYLOAD, ON REQUEST. Claude Code hands this script the only copy of the
session JSON that exists; nothing else on the box can produce one. Without a
dump hook, "does this version really send effort.level" is answerable only from
documentation, and CONSTITUTION §2.5 is explicit that a source which exists is
not a source that supports the claim. One tick with this set settles it.
```

## bin/status-fleet-glyph.sh, lines 194-203 (before this edit)

```text
Claude Code CAPTURES this script's output rather than attaching it to the tty,
so `tput cols` cannot work here and the docs say so; COLUMNS/LINES are exported
instead (v2.1.153+). An UNREADABLE width is not a narrow one: 0 and unset both
mean "unknown" and take the full render, because silently dropping fields on a
wide terminal is the failure nobody would report.

EVERY ICON IS TWO COLUMNS. The tiers are chosen by which tokens they include,
never by measuring the finished string — an ANSI-laden string containing
double-width emoji has no correct `${#s}`, and a width computed from one is the
confident wrong number this file's own rules forbid.
```

## bin/status-fleet-glyph.sh, lines 213-219 (before this edit)

```text
The statusline is the one place that is told how full the context is, so it hands that to the Stop hook:
$STATE/ctx/<session_id> holds ctx_pct, one integer, re-scaled to CLAUDE_CODE_AUTO_COMPACT_WINDOW when that
is set (used_percentage is measured against the model window and stops predicting compaction once an
earlier window is configured). The row itself still shows the payload's own percentage, unchanged.
It also reads the state record hooks/session-state/session-state.sh wrote at the last Stop and shows one token for it,
only while the payload's prompt_id is the one the record was written for: a new prompt means the record
is a turn old, and a stale `? you` on a working session is a lie.
```

## bin/status-fleet-glyph.sh, lines 265-268 (before this edit)

```text
One jq pass, fully rendered. An absent field contributes ZERO columns: no
label, no gap, no placeholder. `// null` then an explicit empty-list branch,
never `// 0` — 0% is the most dangerous plausible wrong number here, because
it reads as "plenty of room" in precisely the state where there is none.
```

## bin/status-fleet-glyph.sh, lines 270-273 (before this edit)

```text
THE CLOCK IS INJECTED, NOT READ INSIDE jq. jq's `now` would make the reset
countdowns below unpinnable — a golden-output suite cannot assert on a value
that moves between the fixture and the assertion. HARBOR_TEST_NOW lets the suite
freeze it; nothing else sets it, so live rendering takes the real clock.
```

## bin/status-fleet-glyph.sh, lines 282-282 (before this edit)

```text
Context also says when it is roomy: green under half (operator ask 2026-10-16, more colour).
```

## bin/status-fleet-glyph.sh, lines 285-309 (before this edit)

```text
WHEN THE WINDOW REFILLS. A percentage answers "how much is left"; the
question you actually have at 91% is "how long until I can work again",
and that is a subtraction the reader should not have to do in their head.
`resets_at` is documented as present only for Claude.ai subscribers after
the first API response, with each window independently absent — so this
returns "" and contributes ZERO columns rather than a placeholder.

A RESET IN THE PAST IS DROPPED, not rendered as 0m. A stale payload is the
one case where a countdown would state something false with total
confidence, and "0m" reads as "about to refill" when it may mean the field
is simply old.

AND IT SAYS `in`. `5h 1% ·4h13m` puts two durations in one token that mean
opposite things — the LENGTH of the window and the time REMAINING in it — and
the middot says only "related", never which. Three characters buy that, and
the alternative considered and rejected was a refresh glyph: ambiguous-width
in several fonts, which the tier note in the header explains cannot be
measured here.

NO APOSTROPHE MAY APPEAR IN THIS BLOCK, and that is not a style rule. Every
comment from here down to the join sits inside a single-quoted jq program, so
a single apostrophe closes the quote and the shell parses the rest of the
program as code. It cost two rounds to find while writing this very comment:
the failure surfaces as "bad substitution: no closing )" pointing at a line
that reads like ordinary prose, and the prose is the bug.
```

## bin/status-fleet-glyph.sh, lines 325-329 (before this edit)

```text
THE WINDOW SIZE IS DERIVED FROM THE FIELD, NEVER READ OFF THE NAME.
`display_name` happens to read "Opus 5 (1M context)" today, so appending a
size would print it twice; a name without the parenthetical would print it
never. Strip any trailing parenthetical and state the size from
context_window_size, which is the field that actually knows.
```

## bin/status-fleet-glyph.sh, lines 336-341 (before this edit)

```text
EFFORT IS ON THE ROW BECAUSE IT MOVES AND IT IS EXPENSIVE. The field
reflects mid-session /effort changes, and a session silently running at
`max` costs a multiple of one running at `medium`. xhigh and max are
yellow: not an alarm, a price tag. Absent when the model has no effort
parameter, and then it costs zero columns. Model and effort are one fact
in two parts, so they share the brain tile and a plain space.
```

## bin/status-fleet-glyph.sh, lines 348-351 (before this edit)

```text
THE EXCEPTIONS ONLY. `fast` renders when fast mode is ON; `no-think` when
extended thinking is OFF. Rendering the ordinary state of either would be a
token that never changes, which is the wallpaper failure this file names
twice elsewhere.
```

## bin/status-fleet-glyph.sh, lines 355-360 (before this edit)

```text
CONTEXT AS A PERCENTAGE, AND NOTHING ELSE (operator decisions 2026-08-23 and
2026-08-24). The absolute count went first: the model tile above states the
window size, so it was the same fact spelled twice. The `>200k` threshold
followed, cut on 08-24 — see the absent-by-decision list in the header for
the argument that was made FOR keeping it, which was a good one and lost.
`exceeds_200k_tokens` is still in the payload; it is deliberately unread.
```

## bin/status-fleet-glyph.sh, lines 366-382 (before this edit)

```text
CACHE SHARE — cache_read / (input + cache_read + cache_creation): how much
of the live context came from cache instead of being re-sent.

THE TWO GUARDS BELOW OVERLAP, AND NEITHER IS INDIVIDUALLY KILLABLE BY A
TEST. Do not delete one on the strength of a green suite. Removing the null
check alone leaves $u null, so each `// 0` yields 0, so $tot is 0, so the
`<= 0` branch suppresses the column anyway — same observable. Removing the
`<= 0` check alone is covered by the null check for the same reason.
Removing BOTH is what bites: jq raises on division by zero, the whole row-1
pass dies, and 16 assertions go red (verified 2026-07-31). A null
current_usage and a present-but-all-zero one are observationally identical,
so no assertion can separate them — this comment is the only mechanism.

The null case is not hypothetical: the schema documents current_usage as
null before the first API call AND AGAIN AFTER EVERY /compact until the next
one. "cache 0%" there would be a confident wrong number in the exact moment
the context was just rebuilt.
```

## bin/status-fleet-glyph.sh, lines 394-395 (before this edit)

```text
The countdown sits INSIDE the colour span, so a red 5h reads as one unit
rather than a red number beside an uncoloured time.
```

## bin/status-fleet-glyph.sh, lines 408-415 (before this edit)

```text
── row 2 · the ground ───────────────────────────────────────────────────────
BUILT IN THREE ZONES, AND THE ZONE ORDER IS THE FIX:
  ALARM   things to act on, leftmost, words in caps, absent when clean
  GROUND  which session, which tree, which PR — and the pin
  AMBIENT inventory and cache age, rightmost, where truncation is harmless
The statusline docs put system notifications on the right of this same row and
say they "may truncate your status line output". Everything on the right must
therefore be something you can afford to lose mid-sentence.
```

## bin/status-fleet-glyph.sh, lines 417-433 (before this edit)

```text
THE ZONE OWNS THE COLOUR, NOT THE CALLER (operator decision 2026-08-24). Every
harbor-state token is dark grey now, and the enforcement is HERE rather than at
the fourteen call sites that used to spell ${RED} and ${YEL} themselves. One
place cannot drift; fourteen can, and the fifteenth caller would arrive red.

WHY NOT STRIP THE CALLER ANSI INSTEAD. Stripping needs a `sed` per token — this
file's header explains that a statusline paying forks per tick is a statusline
you switch off, and it would be 14 of them. So callers pass PLAIN TEXT and the
suite asserts row 2 contains no red, yellow or green at all. That assertion is
the mechanism: without it this is a convention, and a convention is a wish.

SEVERITY COLOUR RETURNS, ON THE YOU ROW ONLY (operator decision 2026-10-16). The
2026-08-24 grey was right for a row that mixed alarms with inventory: colour there
competed with the facts. YOU holds nothing but things to act on, so its colour has
one meaning, and severity is decided HERE, by the word, in one place: red when
something is broken or unsafe now, yellow when it is waiting. Callers still pass
plain text, and the suite asserts PLACE and BOX inventory stay uncoloured grey.
```

## bin/status-fleet-glyph.sh, lines 455-470 (before this edit)

```text
WHICH TERMINAL IS THIS, AND WHAT IS IT WORKING ON (owner request 2026-07-31).
With several terminals open on the same repo, dir+branch identifies the WORK but
not the SESSION — two windows on the same branch render identically, which is
exactly when you need to tell them apart.

`session_name` is the real answer, and it is ABSENT until a name exists (a
custom one from `/rename`/`--name`, or an AI-generated title); the default
display name like `harbor-3f` does NOT populate it. So a name-or-nothing field
would show nothing on a fresh terminal, i.e. it would fail the request in the
common case.

Hence a two-tier field, VISUALLY DISTINCT rather than merged: a chosen name
renders bright, a session-id stem renders dim. Reading a dim stem tells you the
session is unnamed and `/rename` will fix it; a merged rendering would teach
you to read an opaque 6-char token as if it were a name. `agent.name` sits
between them because an --agent session's identity IS the agent.
```

## bin/status-fleet-glyph.sh, lines 473-476 (before this edit)

```text
`kind SP name` — kind never contains a space, so ${x%% *} / ${x#* } is exact.
NOT a tab-separated pair: this file's own header records that reading TSV with
IFS=<tab> collapses consecutive tabs, so one empty field shifts the rest and
still looks plausible.
```

## bin/status-fleet-glyph.sh, lines 488-493 (before this edit)

```text
THE OPEN PR FOR THIS BRANCH, AND ITS REVIEW STATE. Harbor's whole workflow is
PR-gated and the review gate has been merged past once, over two real findings
including a crash — so "is there a PR and has anyone approved it" is a fact
with a history on this box, not a decoration. `pr.review_state` may be absent
independently of `pr`, and `pr.kind == "mr"` means a GitLab merge request, so
the number takes the `!` sigil that platform uses.
```

## bin/status-fleet-glyph.sh, lines 506-508 (before this edit)

```text
THE REPO, NOT THE DIRECTORY. A linked worktree is named for its task, so the
directory alone hides which repo it belongs to; the payload names the repo
(workspace.repo.name) and the directory is the fallback when it does not.
```

## bin/status-fleet-glyph.sh, lines 511-517 (before this edit)

```text
IN A WORKTREE OR IN THE MAIN TREE. `workspace.git_worktree` is documented as
ABSENT in the main working tree and populated for ANY linked worktree — which
makes the safe state the labelled one and the hazardous state the blank one.
That is backwards for this box: the measured incident was three files reverted
to HEAD mid-suite in the MAIN tree by another session, while the peers who did
it were each on their own worktree. So the marker is dim here and the alarm is
carried by the ships tile instead, which is the thing that knows about peers.
```

## bin/status-fleet-glyph.sh, lines 521-546 (before this edit)

```text
CAPPED, BECAUSE THE NAME IS THE ONE FIELD SOMETHING ELSE WRITES (operator
decision 2026-08-24). `session_name` carries a chosen name from /rename OR an
AI-generated title, and a title is prose — "investigating the statusline
separator grammar and the FC-2 repair wording" is a plausible one. Every other
token on this row has a bounded width by construction; this one does not, and an
unbounded leading token pushes the whole row into the truncation zone the note at
the print block just accepted for the alarms. So the row leads with the topic and
the topic cannot expand the row.

48 COLUMNS AND AN ELLIPSIS. Cut on a character count rather than a word boundary:
a word-boundary cut is a variable-width cut, which is the thing being prevented.
${#NAME} is byte length in POSIX sh, so a multibyte title caps shorter in columns
than 48 rather than longer — the safe direction, and stated because the opposite
would silently defeat the cap.

RAISED FROM 24 (operator decision 2026-08-24). 24 cut real names mid-word —
"Click up milestone regi…" — which loses the fact the token exists to carry, so
the cap was costing more than the row width it bought. 48 fits the names
actually in use here while still bounding the row: the cap is what stops one
prose title from pushing the alarms on the right into the terminal's own
truncation, so it is raised rather than removed. HARBOR_STATUS_GLYPH_NAME_CAP overrides
it per-session for anyone who wants a different trade.

RAISED TO 80 (operator decisions 2026-10-16: "at least 60", then 80). The title now leads
its own row, PLACE, and the alarms it used to push off the edge live on YOU, so
the cost that justified 48 is gone; the cap still bounds the one prose field.
```

## bin/status-fleet-glyph.sh, lines 559-562 (before this edit)

```text
WHICH SESSION is a different fact from WHICH TREE, so it takes the boundary
mark. This was the one place a SPACED middot was doing a separator's job
(`2df546 · someone`) while a TIGHT middot two tokens away meant sub-fact
(`·18h`) — the same character, two opposite meanings, on one row.
```

## bin/status-fleet-glyph.sh, lines 565-567 (before this edit)

```text
…and everything after it is ONE fact in several parts — tree, branch, worktree
mark, dirty count, PR — so those stay space-joined. That is now what a space
means, and it is the reason the cluster does not need a mark of its own.
```

## bin/status-fleet-glyph.sh, lines 582-584 (before this edit)

```text
Branch + dirty count. -uall, not -uno: untracked files are how a stray scratch
file reaches a commit, and -uno reports a clean tree on this very box while two
untracked files sit in bin/. A count is a count, never a guess.
```

## bin/status-fleet-glyph.sh, lines 588-589 (before this edit)

```text
0 renders NOTHING, not a tick. Absence of the marker IS the clean signal; a
tick would be a second symbol to learn carrying no new information.
```

## bin/status-fleet-glyph.sh, lines 595-628 (before this edit)

```text
(L0-11, harbor#75; rewritten 2026-08-23 onto the registry.)

THE OLD TOKEN COULD NOT FIRE WHERE IT MATTERED, TWICE OVER. It required
`src=write` on a peer record and counted only peers, so with five live sessions
— four launched in $HOME — it rendered nothing while the SessionStart hook in
the same terminal announced four peers. Dropping the filter fixed the silence
and exposed the second half: `.helm-peers` is written by context-resolve.sh, so
a session that has run no tool has NO RECORD, and the count read 3 of 5.

TWO SOURCES, EACH USED FOR WHAT IT ACTUALLY KNOWS:
  • the COUNT and the busy/idle split come from Claude Code's own session
    registry ($CFG/sessions/<pid>.json), which covers a session from the moment
    it starts, before it has done anything.
  • the TREE attribution comes from `.helm-peers`, because harbor#75 measured
    the registry's `cwd` to be the LAUNCH directory — as is `lsof -d cwd` — so
    a tree count keyed on it reads 2-in-this-tree for two sessions that share
    only the terminal they were started from.
Neither source can answer the other's question, and the previous code failed by
asking one source both.

NO FORKS FOR THE COUNT. The registry is keyed by pid IN THE FILENAME, so the
pid needs no parse, and liveness is `kill -0` — a shell builtin. The registry
does not self-reap, and context-peers.sh defeats a recycled pid by comparing
`procStart` against `ps -o lstart` within a 90s window; that costs a fork per
session and is deliberately NOT done here. This is a display count, and paying
five forks per tick to sharpen it in a rare case is how a statusline becomes
the slow thing you switch off. context-peers.sh remains the accurate answer.

STATUS IS COUNTED, NEVER RENDERED. context-peers.sh records that registry
`name` and `status` are PEER-SUPPLIED — writable by another session or a crafted
file — and bounds them before display for that reason. Counting is immune to it:
the comparison is against the literal string `busy` and what reaches the row is
a digit this script produced. Echoing a peer field would be a cross-session
instruction channel; a tally is not.
```

## bin/status-fleet-glyph.sh, lines 637-638 (before this edit)

```text
No jq: one substring test on the record, which cannot be turned into a
different question by its contents the way a rendered field could.
```

## bin/status-fleet-glyph.sh, lines 641-643 (before this edit)

```text
DEGRADE TO 1, NEVER TO 0. An unreadable or absent registry means this script
cannot see itself, and "0 sessions" printed by a session is a visibly false
number. One is the floor the row can always defend.
```

## bin/status-fleet-glyph.sh, lines 667-672 (before this edit)

```text
THE COUNT IS INVENTORY; THE SHARED TREE IS AN ALARM. `here > 1` is the exact
condition under which uncommitted work has actually been lost on this box —
three files reverted to HEAD mid-suite, git status clean, no stash — so it must
not live in the ambient zone, which the narrow tier drops entirely. Inventory
is what you can afford to lose off the right edge; this is not.
⛵ on PLACE now (2026-10-16): live sessions are part of where this one stands.
```

## bin/status-fleet-glyph.sh, lines 682-707 (before this edit)

```text
Rendering owes the cache AGE, because a glyph that cannot say how old it is
cannot be told apart from a glyph that is current.

DRIFT LEFT THIS TILE (2026-08-23) and became an alarm word. It was `⚠N` here,
and ⚠ is East-Asian-width N — a narrow text-presentation dingbat that this
terminal does not draw from the emoji font. An alarm rendered in a glyph the
operator cannot see is worse than no alarm, because the tile still looks
populated.

THE DRIFT PREDICATE COUNTS THE VERDICT, NOT THE MANIFEST. It was
`(.drift.total // 0) > 0`, and drift.total is the number of files the manifest
COVERS: fleet states it in the docstring (drift.py:36) and sets
it from `len(manifest)` (drift.py:113). So the alarm counted every repo that
carried a manifest AT ALL — the live box showed 8 with only 7 drifted, because
`zarija` reports status "clean", modified [] and missing [] against a 126-file
manifest. The alarm could not reach 0 while any repo was scaffolded.

NO APOSTROPHES IN THE jq BLOCK BELOW. It is a shell single-quoted string, so one
apostrophe ends it early: measured, a first draft of a comment there took
statusline-test from 79 passed / 0 failed to 54 passed / 25 failed and made the
glyph print nothing at all.

`no-manifest` deliberately does NOT count, and that is the weaker half: an
UNMEASURED repo reads exactly like a clean one. Widening it would put
yard permanently in the alarm; the tradeoff is asserted in
tests/status/statusline/fleet.test.sh so it stays a decision.
```

## bin/status-fleet-glyph.sh, lines 726-747 (before this edit)

```text
jq's EXIT CODE IS PART OF THE ANSWER. This was `|| true`, which threw the
status away — and jq STREAMS: on `[{…}] garbage` it prints the first
document's line and only then fails, so the tile rendered a real fleet
count from a file it could not finish reading. Measured 2026-08-14: ⚓1
from a cache with trailing junk.

ONE DOCUMENT, OR NOTHING. `jq -r PROGRAM file` runs the program ONCE PER
JSON DOCUMENT, and a cache holding two concatenated top-level arrays is
not a parse error — it is two answers. Measured 2026-08-14: `[{…}]`
followed by `[{…},{…},{…}]` rendered THREE statusline rows with TWO
different fleet counts (⚓1 then ⚓3), against this file's own two-row
contract. The `[ -n "$g" ]` guard accepted it because a multi-document
answer is non-empty. The same shape defeated the WRITER's gate, which
checked `jq -e 'type == "array"'` — also per document. Both are fixed.

A LINE COUNT IS THE TELL, not a re-parse: this program emits exactly one
line per document by construction, so more than one line means more than
one document. NOT `case "$g" in *"$(printf '\n')"*)`: command substitution
STRIPS trailing newlines, so that subshell yields the EMPTY STRING, the
pattern collapses to `**`, and every cache — including a valid one —
matched and blanked the tile. Caught by keeping a valid single array in
the probe set as a control (CONSTITUTION §2.11).
```

## bin/status-fleet-glyph.sh, lines 753-754 (before this edit)

```text
The cache age is a sub-fact of the fleet count, so it rides it (`·4m ago`)
instead of standing alone as a bare duration nobody could name.
```

## bin/status-fleet-glyph.sh, lines 764-787 (before this edit)

```text
The one ground fact that can change mid-session, because it changes the moment
settings.json is edited.

THE ICON IS GONE (operator decision 2026-08-24) and this is the third and last
step of one argument, so the whole arc is here rather than three comments apart.
The token was `floor✓`, which sat two columns from `renew … floor4` and made one
surface look like it contradicted the other — a reader saw `floor✓` and concluded
the floor was fine while four merged floor commits gated nothing. It became 📌 to
stop that. Then the 08-24 recolour made every state token grey, so the pushpin was
grey whether the pin held or not: an icon in two identical states, which is a
column spent to say the check ran. The operator asked for it removed and they are
right — that is the same reasoning that cut `blocks N` and keeps `worst=ok` silent.

SO THE BINARY NOW HAS EXACTLY ONE CHANNEL, and the comment this replaces called
the redundancy deliberate. It was, and losing it has a cost worth stating: with
the alarm zone moved to the right end of row 2, a system notification can truncate
the row and PIN DRIFT is then not merely quiet but ABSENT — the two decisions
compound, and neither one alone would have done it. `harbor verify` and
session-verdicts.sh both still report the pin, so the fact has surfaces; what it
no longer has is a surface you cannot miss.

NOTHING RENDERS WHEN THE PIN HOLDS. That is this file's rule everywhere else and
the pin is no longer the exception: a token whose steady state is "fine" is
wallpaper by the third session, and wallpaper is how a real alarm gets missed.
```

## bin/status-fleet-glyph.sh, lines 794-796 (before this edit)

```text
The hash is still computed on the holding path even though nothing renders:
it is what decides that nothing should render, and skipping it would turn a
verified all-clear into an assumed one.
```

## bin/status-fleet-glyph.sh, lines 808-818 (before this edit)

```text
THE NUMBERS ABOVE ARE ONLY AS TRUE AS THE JOBS THAT WRITE THEM. `renew`, the
judge verdict, the guard-decision counts and the whole fleet snapshot are files
on disk refreshed by launchd. If com.harbor.status.fleet-snapshot stops, every one of
them freezes at its last value and keeps rendering as current — a green board
over a dead reporter, which is the exact failure this box has already measured
in its data pipelines.

CACHED, NOT PROBED. `launchctl list` per tick is a fork this row may not spend,
so status-fleet-snapshot-refresh.sh writes `.helm-watch` and this reads it. RENDERS
NOTHING WHEN THE FILE IS ABSENT: that means the check has never run, which is a
verdict for renew-check, not a number to invent here.
```

## bin/status-fleet-glyph.sh, lines 833-846 (before this edit)

```text
Written twice a day by housekeeping-clean.sh --record, which rides fleet-snapshot's
run (09:00 and 16:00, operator decision 2026-09-22): `items` is the DECIDE and
RISK rows — a branch whose PR merged, a finished worktree, work that exists in
one place only. CACHED, NOT PROBED: the count needs a GitHub read per repo.

ZERO RENDERS NOTHING, like every other token here. The `?` is the honest
middle: some repo could not be read (`unread`), or the record is older than
the longest gap between two slots plus margin (26h) — either way the number is
a lower bound, and a bare 🧹3 would claim to be the whole of it.

SWEEP IS THE ALARM, WITH AN AGE. `due=1` is the writer's call (any RISK row,
or enough rows), not re-derived here — one policy, one place. The zone owns
the colour, so it is grey like every other alarm (operator decision
2026-08-24); being in the alarm zone at all is the escalation.
```

## bin/status-fleet-glyph.sh, lines 878-882 (before this edit)

```text
status-obligations.sh writes the cache inside fleet-snapshot's run and stores epochs, so the age of the oldest overdue
row is counted here at print time. `⧗N` is the rows still open (grey); OVERDUE is the alarm, with its age.
ABSENT RENDERS NOTHING, like every token here. `⧗?` is the honest middle: the cache is over 900s old (the writer did
not run, so no count and no alarm is claimed from it) or a source did not answer on the last reconcile (the count is a
lower bound, so it is not printed as a number). An overdue row is in the ledger whatever a source said, so OVERDUE still shows.
```

## bin/status-fleet-glyph.sh, lines 884-890 (before this edit)

```text
THE YOU QUEUE (2026-10-16) is the cache's `you` list: the operator-owned
handoffs (`intent`, opened by `event-bus.sh emit obligation.open <slug> --data
'{"title":"…"}'` with no session id) and approvals. Titles are written by sessions,
so control characters are stripped and the text capped here as well as at the fold:
an escape sequence in a title must not be able to repaint this row. 40 columns each (was 90): two
90-column titles pushed every alarm past the terminal's edge; the full title is in `harbor status obligations`. Overdue items
are red. A stale cache claims no queue at all, the rule OVERDUE already follows.
```

## bin/status-fleet-glyph.sh, lines 915-925 (before this edit)

```text
Operator request 2026-09-23 (harbor#657). ci-queue.sh writes the cache inside
fleet-snapshot's run, every 300s; it stores each repo's expected finish as an
EPOCH, and the minutes are subtracted here, at print time — so the time left
keeps counting down between refreshes, and only a run that starts or ends
shows up to one refresh late. `~` because the estimate ignores `needs:`.

IDLE RENDERS NOTHING, like every token on this row. `due` is a job running past
its usual length, never a negative number. `?` is the honest middle, as on 🧹:
a repo GitHub did not answer for, or a cache older than three refreshes (900s)
— then the count is shown with no time at all, because a time computed from a
stale finish would be a confident guess about a queue nobody has looked at.
```

## bin/status-fleet-glyph.sh, lines 941-947 (before this edit)

```text
A WEDGED RUNNER IS AN ALARM, NOT INVENTORY (harbor#152). ci-queue.sh calls a
stall only when a self-hosted job has queued past ten minutes while a runner
of that repo sat idle on two refreshes in a row — the state that froze every
merge for 25 minutes on 2026-08-06 while every surface read "queued, online".
A stale cache says nothing: a stall read from a cache nobody refreshed is a
confident claim about a queue nobody looked at. The remedy is in
`sh bin/ci-queue.sh --print`, not here — this row has no room for it.
```

## bin/status-fleet-glyph.sh, lines 956-962 (before this edit)

```text
ci-main-tip-verdict.sh writes {at, unread, repos:[{repo, tip, ...}]} inside fleet-snapshot's run; the older
single-repo cache has no .repos and reads as one nameless repo. An ALARM, because a merged commit nobody
has a green run for is how 41 of 99 pushes went unnoticed; the age is computed here from when the first failing
run completed (tip.red_at; the commit's time in an older cache), so it keeps counting between refreshes. One failed push
run alone reads `·1 run`: red at once, but a reader can tell a flake from a pattern. A scheduled workflow failing beside
a green push tip is `SCHED <repo>`, ambient, not an alarm (tip.sched; a main-health workflow fails the tip instead). A cache over 900s old, or one whose last read failed, is not
claimed either way: `main?` says "could not look". Compact: `MAIN RED estate 3h`, two are listed, more count.
```

## bin/status-fleet-glyph.sh, lines 988-990 (before this edit)

```text
ci-runner-switch.sh writes the cache inside fleet-snapshot's run and sets HARBOR_CI_RUNNER; this only shows it. The runners
are this Mac and a Linux container, hence `local`, not `mac` (2026-10-05). The FALLBACK is the news, so github-hosted (the normal state) renders nothing, like every idle token on this row.
A cache over 900s old, or one whose last read failed, says `CI?`: the runner may be one this token does not know.
```

## bin/status-fleet-glyph.sh, lines 1051-1064 (before this edit)

```text
WHAT IS BUILT HERE AND NOT RUNNING THERE (harbor#44). Cache written by
status-fleet-snapshot-refresh.sh — the answer needs a `git rev-list` and a walk of
LaunchAgents, and a tick must not scale with either.

RED, AND LOUDER THAN ANY COUNT. A renewal not done is a merged, tested,
contract-documented guard that gates nothing on this machine — measured
2026-08-13 as 11 bin/hooks commits behind, which is why admission-cloud.sh and
admission-destroy.sh were not live.

THE COUNT IS DROPPED AND THE TOKENS ARE KEPT VERBATIM. drift-renew-check.sh owns this
vocabulary; `renew 2 runtime3·floor4` states the same quantity twice, and
re-spelling `runtime3` as `runtime+3` here would be a second implementation of
another tool's naming that can disagree with it. The label says the condition,
the tokens stay renew-check's.
```

## bin/status-fleet-glyph.sh, lines 1074-1089 (before this edit)

```text
THE DAILY JUDGE'S VERDICT — new on the row 2026-08-23, and the reason for the
whole redesign. This box carried `crit=1 warn=62` in .helm-judge while the row
rendered a green pin, because nothing read the verdict; `renew` only notices the
judge when the FILE is absent or two days stale, never what it says.

THE AGE IS NOT OPTIONAL. The crit that prompted this rested on ONE
wrapper-guard-missing record from 2026-08-20, and the remedy it prints
(re-run admission-install.sh) had already run on 2026-08-23 — so the verdict was
almost certainly true-but-spent, and nothing on the row could say so. An
undated verdict cannot be falsified, and CONSTITUTION §2.4 says a claim with no
falsifier is not a claim. Age comes from the file mtime, the same idiom the
fleet cache uses, and not from parsing the ISO stamp inside: `date -j -f` is
BSD-only and this file must survive a userland change.

`worst=ok` RENDERS NOTHING. A judge reporting clean every tick is wallpaper by
the third session, and wallpaper is how a real alarm gets missed.
```

## bin/status-fleet-glyph.sh, lines 1117-1122 (before this edit)

```text
OVERRIDES ONLY — `blocks N` was removed 2026-08-23. It was a monotonic lifetime
counter (4,719 blocks against 102,012 ledger records) that no action could move,
so it was read past by the third session; the operator asked for it gone and the
reasoning agrees. An OVERRIDE is different in kind: it is the operator saying a
rule is wrong with their hands, which CONSTITUTION §2.11 calls a defect in the
rule. It renders nothing until one happens, which is most of the time.
```

## bin/status-fleet-glyph.sh, lines 1128-1131 (before this edit)

```text
Proposal packets waiting for a human (harbor#44). Same silence rule: nothing at
zero, nothing when the file is absent. YELLOW, not red — a queued packet is the
system working as designed, where a renewal not done is a gap between what was
built and what is running.
```

## bin/status-fleet-glyph.sh, lines 1154-1157 (before this edit)

```text
CPU BUSY IS READ FROM A CACHE, NEVER SAMPLED INLINE. A real busy figure needs two
counter reads a second apart (iostat -c 2 -w 1); `ps %cpu` is a decayed average and
`top -l 1` costs 250 ms. A detached sampler refreshes `epoch busy` and a render
shows the last value, so the 1 s wait never lands on a tick.
```

## bin/status-fleet-glyph.sh, lines 1298-1318 (before this edit)

```text
── ZONE ORDER: GROUND, AMBIENT, ALARM (operator decision 2026-08-24) ─────────
THIS REVERSES DECISION 1 IN THE HEADER, AND THE COST IS REAL AND ACCEPTED. That
decision put alarms leftmost because the statusline docs say Claude Code renders
its own system notifications on the RIGHT of this row and that they "may truncate
your status line output" — so the rightmost token is the one you can afford to
lose. Alarms are now the rightmost token, which means a long MCP error can eat
them, and the failure mode is that you would not know an alarm was there to lose.

The operator was shown that cost, in those words, and chose the right end anyway.
It is their status row and the trade is theirs to make: what they get back is a
row that leads with what they are working on instead of with harbor's complaints,
every session, including the overwhelming majority where nothing is wrong.

RECORDED RATHER THAN ARGUED AGAIN. The next reader will find decision 1 above
still explaining why alarms belong on the left; both are operator decisions and
this one is later. Do not "restore" the old order from that paragraph alone.

SUPERSEDED 2026-10-16 BY THE YOU ROW, and the cost above is gone rather than
re-accepted: alarms now lead a row of their own, so no notification can clip them
and they no longer crowd what PLACE is for. Both paragraphs stay as the record.

```

## bin/status-fleet-glyph.sh, lines 16-16 (before this edit)

```text
Removed notes: docs/explanation/code-cases/bin-status-fleet-glyph.md
```

## bin/status-fleet-glyph.sh, lines 19-22 (before this edit)

```text
  HARBOR_STATUS_GLYPH_DUMP=<f>  append the raw stdin payload to <f> and continue. The
                         honest way to answer "is that field actually in the
                         payload on THIS version" — the docs are a claim, one
                         captured tick is the fact. Off unless set.
```

## bin/status-fleet-glyph.sh, lines 649-649 (before this edit)

```text
The sweep's alarm, computed with its tile above (the 🧹 section).
```

## bin/status-fleet-glyph.sh, lines 651-651 (before this edit)

```text
The obligations alarm, computed with its tile above (the ⧗ section).
```

## bin/status-fleet-glyph.sh, lines 763-766 (before this edit)

```text
DISK, used/total like RAM (operator, 2026-10-16), on the volume that holds $HOME: on macOS the
Data volume, since `/` is the sealed system snapshot. Used is total minus available, because APFS
volumes share a container and the Used column undercounts. One `df` fork; yellow under 15% free,
red under 7%. HARBOR_STATUS_GLYPH_DF stands in for df in the suite.
```

## bin/status-fleet-glyph.sh, lines 775-776 (before this edit)

```text
SWAP, used/total, always shown once sysctl answers (operator, 2026-10-16): macOS grows the
swap files on demand, so a total of 0 is real and reads `0/0G`.
```
