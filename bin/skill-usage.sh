#!/usr/bin/env sh
# skill-usage.sh (harbor#173 · A7, harbor#518) — how often is a skill invoked, and when last?
#
#   sh bin/skill-usage.sh              every invocation, with last-seen and cost per use
#   sh bin/skill-usage.sh --days 30    only sessions touched in the last N days
#   sh bin/skill-usage.sh --unused     installed skills with no invocation in the
#                                      window the transcript store still holds
#
# THE NUMBER EVERY COST ARGUMENT IN THIS REPO NEEDED AND NOBODY HAD. Context cost
# is size x frequency. `bin/context-budget.sh` measures size exactly and frequency
# not at all, so every trim decision on this branch — which skills to keep
# ambient, whether the book earns its description, whether a hook's per-fire cost
# beats a prefix's one-time cost — was priced with one factor missing.
#
# READ FROM TRANSCRIPTS, NEVER WRITTEN TO A LEDGER, and that is a rule rather than
# a convenience. A PostToolUse counter was the obvious build and it is the wrong
# one: it would persist a distilled second copy of something the transcripts
# already record perfectly, and a distilled copy drifts while reading correctly.
# The transcripts are the source; this is a query over them.
#
# IT PRINTS COUNTS AND NAMES, NEVER CONTENT (CONSTITUTION §3). Session transcripts
# hold work-log material, absolute paths and identity. Nothing here emits a line
# of one — the output is a skill name, an integer and a date.
#
# TWO CLOCKS, AND CONFLATING THEM IS THE BUG THIS AVOIDS (harbor#518). File mtime
# answers "what window does the store still hold" — a property of the GC, used for
# the CEILING statement below and nothing else. The `.timestamp` ON THE RECORD
# answers "when did this skill last fire", which is a property of the work. #518
# proposed deriving last-seen from mtime and that would have been wrong in the
# lenient direction: a long session that invokes a skill in its first minute and
# is touched hours later would report the skill as far fresher than it was. The
# record carries the exact moment, so nothing here reads an mtime for last-seen.
#
# WHY NOT `bytes x invocations`, WHICH IS WHAT #518 ASKED FOR. That product rises
# with use, so it ranks the most-used skill as the most expensive and inverts the
# decision it exists to inform. An ambient description is charged in EVERY session
# whether or not anything invokes it; the invocations are the RETURN, not the cost.
# So the join is charged-bytes DIVIDED BY uses — bytes paid per invocation earned,
# which is the number a trim decision actually needs and the one #492 can cite.
set -eu
# harbor#521: touched, so converted (LOG1 ratchet). Stdout is the report; the log goes to stderr.
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || HERE=""
[ -n "$HERE" ] && [ -f "$HERE/library-log.sh" ] || { echo "skill-usage: library-log.sh is missing beside $0" >&2; exit 1; }
LOG_FD=2
. "$HERE/library-log.sh"
log_init skill-usage
stop() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; } # <what failed> <fix command>

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJ="$CFG/projects"
SKILLS="$CFG/skills"

DAYS=''; MODE=count
while [ $# -gt 0 ]; do
  case "$1" in
    --days)   [ "$#" -ge 2 ] || { echo "skill-usage: --days needs a number" >&2; exit 2; }
              shift; DAYS="$1" ;;
    --unused) MODE=unused ;;
    -h|--help) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)        echo "skill-usage: unknown flag $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$PROJ" ] || stop "no session store at ${PROJ#"$HOME"/}" "ls -d ${PROJ#"$HOME"/}   # or set CLAUDE_CONFIG_DIR to the config dir that holds the transcripts"
command -v jq >/dev/null 2>&1 || stop "jq is required" "$(pkg_hint jq)"

# THE FILE LIST IS BUILT BY find, NOT BY A GLOB. This estate's `grep` is a ugrep
# wrapper carrying `-I --ignore-files`, which silently skips gitignored files —
# and the whole session store is gitignored. A negative rested on that grep would
# read as "this skill was never used" when it means "grep declined to look".
LIST="${TMPDIR:-/tmp}/skill-usage.$$"
trap 'rm -f "$LIST" "$LIST.hits" "$LIST.names" "$LIST.last"' EXIT INT TERM
if [ -n "$DAYS" ]; then
  find "$PROJ" -name '*.jsonl' -type f -mtime "-$DAYS" > "$LIST"
else
  find "$PROJ" -name '*.jsonl' -type f > "$LIST"
fi
_sessions="$(wc -l < "$LIST" | tr -d ' ')"

# ── THE WINDOW THIS TOOL CAN SEE, WHICH IS NOT FOREVER (harbor#248) ─────────
# This file's footer told the reader that "only a count over a LARGE window"
# separates "nothing wanted it" from "the description never triggered" — while
# having no idea how large its own window was, and printing `have NEVER been
# invoked` about it. Measured 2026-08-21: the store held 498 session files whose
# oldest mtime was 8 days old, and `bin/status-usage-aggregate.sh`'s header already
# records why — *"the transcript store is garbage-collected"*. So "never" was a
# claim about a rolling window, stated as a claim about all time, by the one tool
# whose whole purpose is to price a permanent decision.
#
# It matters beyond wording: harbor#178's "2,251 sessions" cannot be reproduced
# from this store today, and A6 was refused on a frequency count this tool now
# reads as zero. Neither can be re-argued without knowing the window each number
# came from.
#
# DERIVED FROM THE FILES, NEVER A CONSTANT. A documented GC horizon would be a
# copy of a harness behaviour nobody here controls, and copies drift while
# reading perfectly (T2). The span is whatever the store actually holds.
#
# Verbatim from lint-conventions.sh:_x8_mtime, and verbatim ON PURPOSE — `-f`
# means "file system" to GNU stat and "format" to BSD, so on Linux the first call
# prints filesystem fields and then fails, and an `||` chain appends the second
# call's answer to that garbage. Digits or nothing.
_su_mtime() { # <file> -> epoch seconds, or empty
  _v="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_v" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "$_v"
}
#
# EXPLICIT `if`, NOT `[ … ] && …`. This file runs under `set -e`, and an AND-list
# whose test fails is the last command of this loop body — the shape that aborts
# a strict shell on the perfectly ordinary case of "this file is not the oldest".
_oldest=''; _newest=''
while IFS= read -r _f; do
  _m="$(_su_mtime "$_f")"
  if [ -n "$_m" ]; then
    if [ -z "$_oldest" ]; then _oldest="$_m"; _newest="$_m"; fi
    if [ "$_m" -lt "$_oldest" ]; then _oldest="$_m"; fi
    if [ "$_m" -gt "$_newest" ]; then _newest="$_m"; fi
  fi
done < "$LIST"

# The span is printed in DAYS and the phrasing is deliberately "no invocation in"
# rather than "never": a reader deciding whether to make a skill permanently
# unreachable needs to know they are looking at days, not history.
_window='an unknown span — no readable mtime in the store'
if [ -n "$_oldest" ]; then
  _span_d=$(( ( _newest - _oldest ) / 86400 ))
  _window="$_span_d day(s) of transcripts"
fi

# BOTH SHAPES OF AN INVOCATION. The Skill tool records the name in
# `input.skill`, and a slash command the operator typed arrives as a
# `<command-name>` marker in a user turn. Counting only the first would report
# every operator-invoked skill — which on this box is most of them — as unused,
# and "unused" is exactly the verdict this tool exists to make safe to act on.
# ONE PASS, AND IT CARRIES THE CLOCK. This was two jq invocations per file, one
# per shape, both emitting a bare name. Folding them into a single filter that
# also picks up the record's own timestamp is faster than the pair it replaces
# (measured 2026-09-16 over 51 files: 13s against 16s) and is the entire source
# of the last-seen column. Each row is `epoch<TAB>date<TAB>name`.
#
# `fromdateiso8601` REFUSES FRACTIONAL SECONDS, which these timestamps carry
# (`2026-09-14T08:13:09.399Z`). Slicing to [0:19] and re-appending `Z` is the
# whole fix, and doing the parse inside jq means this file calls `date` NOWHERE —
# BSD `date -r` and GNU `date -d @` disagree exactly like the `stat` split that
# F11 exists to catch, and the disagreement is silent.
#
# THE `try` IS LOAD-BEARING, NOT DEFENSIVE NOISE. jq aborts the whole document on
# a raise, and this call is wrapped in `2>/dev/null || true` — so one malformed
# timestamp anywhere in a transcript would discard EVERY hit in that file and
# report it as a quiet zero. A skill would read as unused because one line was
# unparseable, which is precisely the verdict this tool exists to make safe.
# Same reason nothing is dropped for a MISSING timestamp: the hit still counts,
# it simply has no date, because losing a count to protect a column would trade
# the answer for the decoration.
: > "$LIST.hits"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  # harbor#521: only a typed user string or a system/local_command record STARTING with the marker is an invocation;
  # tool-result echoes, assistant prose, attachments and mid-string quotes are not (shapes counted in the ticket).
  jq -r '
    (if type == "object" then (.timestamp // "") else "" end) as $ts
    | (try (($ts[0:19] + "Z") | fromdateiso8601) catch 0) as $e
    | (if $ts == "" then "-" else $ts[0:10] end) as $d
    | [ (.. | objects
             | select(has("name") and .name == "Skill")
             | (.input.skill // .input.name // empty)),
        (( if type == "object" and .type == "user" and (.message.content | type) == "string" then .message.content
           elif type == "object" and .type == "system" and .subtype == "local_command" and (.content | type) == "string" then .content
           else empty end )
         | select(test("^\\s*<command-(name|message)>"))
         | capture("<command-name>/?(?<n>[a-z0-9][a-z0-9._-]*)</command-name>")
         | .n) ]
    | .[] | "\($e)\t\($d)\t\(.)"
  ' "$f" 2>/dev/null >> "$LIST.hits" || true
done < "$LIST"

# THE NAME-ONLY PROJECTION EXISTS BECAUSE TWO CONSUMERS MATCH WHOLE LINES.
# `grep -Fxq` below and the `uniq -c` table at the foot both assumed one bare
# name per line; against a three-column row the first silently never matches and
# the second counts date+name pairs as distinct skills. Deriving the old shape
# here keeps both correct without either having to know about the new columns.
cut -f3 "$LIST.hits" > "$LIST.names"

_total="$(wc -l < "$LIST.hits" | tr -d ' ')"

# LAST SEEN, PER SKILL: the largest epoch each name ever appears with, and the
# date that goes with it. One pass, no sort, no second read of the store.
awk -F'\t' '{ if ($1 + 0 > m[$3] + 0) { m[$3] = $1; d[$3] = $2 } }
            END { for (k in m) printf "%s\t%s\t%s\n", k, m[k], d[k] }' \
    "$LIST.hits" > "$LIST.last"

# THE RECENCY LINE IS DERIVED FROM THE STORE, NEVER A CONSTANT — same argument as
# the window above. Half the measured span, floored at a day so a store holding a
# single day cannot classify everything in it as stale. "Now" is the newest event
# on record rather than the wall clock, so the verdict is reproducible: re-running
# this tomorrow over an unchanged store returns the same answer it did today.
_clamped=''
_newest_evt="$(awk -F'\t' '$1 + 0 > m + 0 { m = $1 } END { print m + 0 }' "$LIST.hits")"

# THE ANCHOR IS CLAMPED TO THE STORE'S OWN UPPER BOUND, AND THIS IS NOT THEORY —
# an adversarial run on 2026-09-16 put ONE record dated 2099 in a two-file store
# and every other skill in it flipped to STALE. The recency axis is measured from
# the newest event on record, so a single impossible stamp moves the cutoff years
# forward and takes the whole report with it, silently and in the direction that
# invents work. §2.11: a false positive is a defect, and one that fires on every
# row is the kind that gets the instrument switched off.
#
# The bound is free and already computed. A record is written to a file BEFORE
# that file's mtime settles, so no honest event can postdate the newest mtime in
# the store. Clamping to `_newest` costs nothing when the data is sane and
# contains the blast radius when it is not — clock skew, a restored backup, a
# half-written line. The offending ROW still prints its own date rather than a
# laundered one, because hiding the bad datum would remove the only evidence that
# anything is wrong; it simply stops setting the threshold for everyone else.
if [ -n "${_newest:-}" ] && [ "$_newest_evt" -gt "$_newest" ]; then
  _clamped="$_newest_evt"
  _newest_evt="$_newest"
fi
_stale_s=$(( ( ${_newest:-0} - ${_oldest:-0} ) / 2 ))
[ "$_stale_s" -ge 86400 ] || _stale_s=86400
_stale_d=$(( _stale_s / 86400 ))

# Tier and description size, needed by BOTH modes now. The size is `length($0)`
# of the description LINE and that is deliberate — `context-budget.sh:126` uses
# the identical expression, so the two tools stay join-compatible by construction
# rather than by anyone remembering to keep them in step.
_tier_of() { # <skill-dir> -> ambient | invoked-only
  if awk 'NR==1 && $0 !~ /^---/ {exit} NR>1 && $0 ~ /^---/ {exit} NR>1' "$1/SKILL.md" 2>/dev/null \
     | grep -q '^disable-model-invocation:[[:space:]]*true'
  then printf 'invoked-only'
  else printf 'ambient'
  fi
}
_desc_bytes() { # <skill-dir> -> byte length of the description line, or 0
  _v="$(awk '/^description:/{print length($0); exit}' "$1/SKILL.md" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9]*) _v=0 ;; esac
  printf '%s' "$_v"
}
_last_of() { # <skill-name> -> "epoch<TAB>date", or empty
  awk -F'\t' -v k="$1" '$1 == k { printf "%s\t%s", $2, $3; exit }' "$LIST.last"
}

if [ "$MODE" = unused ]; then
  printf 'installed skills with ZERO invocations in %s session file(s) spanning %s%s\n\n' \
    "$_sessions" "$_window" "$([ -n "$DAYS" ] && printf ' (--days %s)' "$DAYS")"
  _n=0
  _amb_b=0; _amb_n=0
  for d in "$SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    n="$(basename "$d")"
    grep -Fxq "$n" "$LIST.names" 2>/dev/null && continue
    # THE TWO ZERO-INVOCATION STATES ARE NOT THE SAME FINDING (harbor#518). This
    # list reported them as one undifferentiated "unused" set, and only one half
    # is actionable: an AMBIENT skill that never fires pays for its description in
    # every session and returns nothing, while an invoked-only one that never
    # fires costs zero and is merely dormant. SILENT is a bill; DORMANT is an
    # option nobody exercised, and acting on the second buys exactly nothing.
    case "$(_tier_of "$d")" in
      invoked-only) _t='DORMANT — invoked-only (costs nothing)' ;;
      *)            _t='SILENT — AMBIENT, pays its description every session' ;;
    esac
    # THE BYTES, NOT JUST THE TIER (harbor#178). "AMBIENT and never invoked" is
    # the finding; what a trim decision needs on top of it is HOW MUCH, and
    # without that this report sent the reader to context-budget.sh, which knows
    # the ambient total and not which rows earned it. Neither tool could answer
    # the question on its own, and the answer is a join of the two — so the
    # frequency report carries the size, measured the same way context-budget
    # measures it (the description LINE, which is what the harness lists).
    _b=0
    case "$_t" in
      SILENT*) _b="$(_desc_bytes "$d")"
               _amb_b=$(( _amb_b + _b ))
               _amb_n=$(( _amb_n + 1 ))
               printf '  %-26s %6s B  %s\n' "$n" "$_b" "$_t" ;;
      *)       printf '  %-26s %8s  %s\n' "$n" '' "$_t" ;;
    esac
    _n=$(( _n + 1 ))
  done
  printf '\n  %d of %d installed skill(s) had NO invocation in the window above.\n' "$_n" \
    "$(_c=0; for d in "$SKILLS"/*/; do [ -f "$d/SKILL.md" ] && _c=$(( _c + 1 )); done; printf '%s' "$_c")"
  # THE ONLY LINE THAT IS ACTIONABLE. Everything above it is inventory; this is
  # the number a ceiling decision is made against, and it did not exist before.
  if [ "$_amb_n" -gt 0 ]; then
    printf '  %d of them are AMBIENT, costing %d B in EVERY session and returning nothing.\n' \
      "$_amb_n" "$_amb_b"
    printf '  Priced against the ceiling by: sh bin/context-budget.sh\n'
    printf '  Zero here has two readings — nothing wanted it, or the description never\n'
    printf '  triggered — and only a count over a LARGE window separates them. The window\n'
    printf '  is %s, which is a CEILING on what this source can\n' "$_window"
    printf '  ever say: the transcript store is garbage-collected, so a longer count is\n'
    printf '  not obtainable by asking again later. Flipping one to disable-model-invocation:\n'
    printf '  true on the second reading makes it permanently unreachable rather than\n'
    printf '  merely unused (harbor#178).\n'
  fi
  exit 0
fi

printf 'skill invocations across %s session file(s) spanning %s%s\n\n' \
  "$_sessions" "$_window" "$([ -n "$DAYS" ] && printf ' (--days %s)' "$DAYS")"
if [ "$_total" -eq 0 ]; then
  printf '  none recorded.\n'
  exit 0
fi
printf '  STALE = no invocation in the last %s day(s), which is half the span above —\n' "$_stale_d"
printf '  DERIVED from the store, not a threshold anyone chose, and it moves with it.\n'
printf '  The tax is the description charged across every session in the window,\n'
printf '  divided by the invocations it returned. Blank where nothing is charged.\n'
# SAY SO WHEN THE DATA IS IMPOSSIBLE. A clamp that repaired the report silently
# would leave the reader trusting a store that has a clock problem in it.
if [ -n "$_clamped" ]; then
  printf '\n  NOTE: a record is dated later than any file in the store was written.\n'
  printf '  The recency cutoff was clamped to the newest file mtime so one bad\n'
  printf '  stamp cannot age every other skill. The offending row still shows its\n'
  printf '  own date, which is the only evidence you have that it is wrong.\n'
fi
printf '\n'
printf '  %6s  %-26s %-12s %-10s %-6s %s\n' 'uses' 'skill' 'tier' 'last seen' 'state' 'context tax'
sort "$LIST.names" | uniq -c | sort -rn | while read -r c n; do
  # NOT EVERY NAME HERE IS AN INSTALLED SKILL. `compact`, `clear` and `resume`
  # are harness commands that arrive through the same `<command-name>` marker,
  # and they have no SKILL.md and therefore no description to charge. A dash is
  # the honest answer for them; a zero would read as "free", which is a claim
  # about a cost this tool never measured.
  # ASCII IN THE COLUMNS, AND THAT IS AN ALIGNMENT RULE RATHER THAN A STYLE ONE.
  # `printf %-12s` pads to a BYTE count, and an em-dash is three bytes in UTF-8,
  # so a `—` placeholder silently shortens its own column by two and skews every
  # row that uses it. Measured here on the first run. The prose above may keep
  # its dashes; the table may not.
  if [ -f "$SKILLS/$n/SKILL.md" ]; then _tier="$(_tier_of "$SKILLS/$n")"; else _tier='absent'; fi

  _seen="$(_last_of "$n")"
  _epoch="${_seen%%	*}"; _date="${_seen##*	}"
  case "$_epoch" in ''|*[!0-9]*) _epoch=0 ;; esac
  [ -n "$_date" ] || _date='-'

  # An epoch of 0 means the hit carried no parseable timestamp. It still counts —
  # see the extraction above — but it cannot be placed on the recency axis, and
  # guessing a state for it would be the fabrication the whole column exists to
  # avoid. It gets a dash, and the uses column still tells the truth.
  if [ "$_epoch" -eq 0 ]; then _state='-'
  elif [ "$_epoch" -ge $(( _newest_evt - _stale_s )) ]; then _state='ACTIVE'
  else _state='STALE'
  fi

  _tax=''
  if [ "$_tier" = ambient ]; then
    _b="$(_desc_bytes "$SKILLS/$n")"
    if [ "$_b" -gt 0 ] && [ "$c" -gt 0 ]; then
      _tax="$(( ( _b * _sessions ) / c )) B/use"
    fi
  fi
  printf '  %6d  %-26s %-12s %-10s %-6s %s\n' "$c" "$n" "$_tier" "$_date" "$_state" "$_tax"
done
printf '\n  %s invocation(s) total.\n' "$_total"
exit 0
