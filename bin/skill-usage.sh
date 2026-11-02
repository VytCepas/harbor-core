#!/usr/bin/env sh
# skill-usage.sh (harbor#173 · A7, harbor#518) — how often is a skill invoked, and when last?
#
#   sh bin/skill-usage.sh              every invocation, with last-seen and cost per use
#   sh bin/skill-usage.sh --days 30    only sessions touched in the last N days
#   sh bin/skill-usage.sh --unused     installed skills with no invocation in the
#                                      window the transcript store still holds
#
# Frequency half of context cost (size x frequency; bin/context-budget.sh measures only size). Read from the
# transcripts and never written to a ledger: a distilled second copy drifts. Prints counts and names, never
# content (CONSTITUTION §3).
# Two clocks (harbor#518): the record's `.timestamp` is last-seen; file mtime only bounds the store's window (the
# ceiling statement). The tax is charged-bytes DIVIDED BY uses, not bytes x uses, which would rank the
# most-used skill as the most expensive.
# Removed notes: docs/explanation/code-cases/bin-skill-usage.md
set -eu
# harbor#521: touched, so converted (LOG1 ratchet). Stdout is the report; the log goes to stderr.
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || HERE=""
[ -n "$HERE" ] && [ -f "$HERE/library-log.sh" ] || { echo "skill-usage: library-log.sh is missing beside $0" >&2; exit 1; }
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
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

# File list by find, not a glob or grep: this estate's grep is ugrep with --ignore-files and silently skips the
# gitignored session store.
LIST="${TMPDIR:-/tmp}/skill-usage.$$"
trap 'rm -f "$LIST" "$LIST.hits" "$LIST.names" "$LIST.last"' EXIT INT TERM
if [ -n "$DAYS" ]; then
  find "$PROJ" -name '*.jsonl' -type f -mtime "-$DAYS" > "$LIST"
else
  find "$PROJ" -name '*.jsonl' -type f > "$LIST"
fi
_sessions="$(wc -l < "$LIST" | tr -d ' ')"

# The window this tool can see (harbor#248): the transcript store is garbage-collected, so "never" is a claim about
# a rolling window. The span is derived from the files, never a constant.
# Verbatim from lint-conventions.sh:_x8_mtime: `-f` is "filesystem" to GNU stat, so an `||` chain would append to
# its garbage. Digits or nothing.
_su_mtime() { # <file> -> epoch seconds, or empty
  _v="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_v" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "$_v"
}
# Explicit `if`, not `[ ... ] && ...`: under `set -e` a failing AND-list as the last command aborts the loop.
_oldest=''; _newest=''
while IFS= read -r _f; do
  _m="$(_su_mtime "$_f")"
  if [ -n "$_m" ]; then
    if [ -z "$_oldest" ]; then _oldest="$_m"; _newest="$_m"; fi
    if [ "$_m" -lt "$_oldest" ]; then _oldest="$_m"; fi
    if [ "$_m" -gt "$_newest" ]; then _newest="$_m"; fi
  fi
done < "$LIST"

# Phrased "no invocation in", not "never": the reader is looking at days, not history.
_window='an unknown span — no readable mtime in the store'
if [ -n "$_oldest" ]; then
  _span_d=$(( ( _newest - _oldest ) / 86400 ))
  _window="$_span_d day(s) of transcripts"
fi

# Both invocation shapes: the Skill tool's `input.skill`, and an operator-typed slash command arriving as a
# `<command-name>` marker (counting only the first reports most skills as unused). One jq pass also carries the
# record timestamp; rows are `epoch<TAB>date<TAB>name`. `fromdateiso8601` refuses fractional seconds, so the
# timestamp is sliced to [0:19] + Z, which keeps `date` out of this file (BSD and GNU differ). The `try` is
# load-bearing: a raise aborts the document and `|| true` would turn every hit in it into a quiet zero.
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

# Name-only projection: `grep -Fxq` and `uniq -c` below match whole lines and break on three-column rows.
cut -f3 "$LIST.hits" > "$LIST.names"

_total="$(wc -l < "$LIST.hits" | tr -d ' ')"

# Last seen per skill: the largest epoch each name appears with, and its date.
awk -F'\t' '{ if ($1 + 0 > m[$3] + 0) { m[$3] = $1; d[$3] = $2 } }
            END { for (k in m) printf "%s\t%s\t%s\n", k, m[k], d[k] }' \
    "$LIST.hits" > "$LIST.last"

# Recency cutoff derived from the store (half the span, floored at a day). "Now" is the newest event on record,
# so a rerun over an unchanged store gives the same answer.
_clamped=''
_newest_evt="$(awk -F'\t' '$1 + 0 > m + 0 { m = $1 } END { print m + 0 }' "$LIST.hits")"

# Clamp the anchor to the newest file mtime: one record dated 2099 flipped every other skill to STALE (§2.11).
# No honest event postdates the newest mtime. The offending row still prints its own date, as the only evidence
# that something is wrong.
if [ -n "${_newest:-}" ] && [ "$_newest_evt" -gt "$_newest" ]; then
  _clamped="$_newest_evt"
  _newest_evt="$_newest"
fi
_stale_s=$(( ( ${_newest:-0} - ${_oldest:-0} ) / 2 ))
[ "$_stale_s" -ge 86400 ] || _stale_s=86400
_stale_d=$(( _stale_s / 86400 ))

# Tier and description size: length($0) of the description line matches context-budget.sh:126, so the tools join.
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
    # Two zero-invocation states (harbor#518): an AMBIENT skill pays its description every session (SILENT); an
    # invoked-only one costs nothing (DORMANT).
    case "$(_tier_of "$d")" in
      invoked-only) _t='DORMANT — invoked-only (costs nothing)' ;;
      *)            _t='SILENT — AMBIENT, pays its description every session' ;;
    esac
    # Bytes, not just the tier (harbor#178): the join with context-budget.sh, measured as the description LINE.
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
  # The only actionable line: the number a ceiling decision is made against.
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
# Say so when the data is impossible; a silent clamp would hide a clock problem in the store.
if [ -n "$_clamped" ]; then
  printf '\n  NOTE: a record is dated later than any file in the store was written.\n'
  printf '  The recency cutoff was clamped to the newest file mtime so one bad\n'
  printf '  stamp cannot age every other skill. The offending row still shows its\n'
  printf '  own date, which is the only evidence you have that it is wrong.\n'
fi
printf '\n'
printf '  %6s  %-26s %-12s %-10s %-6s %s\n' 'uses' 'skill' 'tier' 'last seen' 'state' 'context tax'
sort "$LIST.names" | uniq -c | sort -rn | while read -r c n; do
  # Not every name is an installed skill (`compact`, `clear`, `resume` have no SKILL.md): tier is absent and the
  # tax a dash, since a zero would claim a cost never measured. ASCII in the columns: printf pads by bytes and an
  # em-dash is three.
  if [ -f "$SKILLS/$n/SKILL.md" ]; then _tier="$(_tier_of "$SKILLS/$n")"; else _tier='absent'; fi

  _seen="$(_last_of "$n")"
  _epoch="${_seen%%	*}"; _date="${_seen##*	}"
  case "$_epoch" in ''|*[!0-9]*) _epoch=0 ;; esac
  [ -n "$_date" ] || _date='-'

  # Epoch 0 means no parseable timestamp: still counted, but not placed on the recency axis (a dash, not a guessed state).
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
