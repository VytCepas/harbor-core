#!/usr/bin/env sh
# doc-freshness.sh — per-document staleness over Harbor's governing files.
# harbor#5 (workstream C1a), method taken from upstream `Interview` @ a4e8e74.
#
# Upstream's Interview reads the constitutional files, scores each one's age
# against a threshold, surfaces the stalest, and asks "still right?" instead of
# "what's your mission?". Harbor took the *method*; the plumbing did not port —
# TelosFreshness.ts/InterviewScan.ts are Bun, the seven files are upstream's, and
# the cache is Pulse's. Here the age source is git, which already knows.
#
# STALENESS IS A PRIORITY SIGNAL, NOT A FAILURE FLAG. A 200-day-old contract may
# be exactly right; the question this produces is "still right?", and that is
# why this script never exits non-zero for age alone.
#
# TWO CORPORA, TWO AGE SOURCES (C1a, harbor#43). The repo's documents are aged
# from git, which already knows. The operator's working context —
# `MEMORY/TELOS/*.md` and `MEMORY/IDENTITY.md` — CANNOT be, because those files
# must never reach the Log (harbor#43's privacy decision) and an untracked file
# has no commit date. So that corpus is aged from mtime, and `GOALS.md` carries a
# per-entry reviewed date because mtime is a whole-file signal and a goal list is
# not one thing: editing G4 must not make G1 look reviewed.
#
# THE REPORT NEVER PRINTS THE CONTENT OF THAT CORPUS. Ids and ages only. A
# freshness table gets pasted into a chat, screenshotted, and read over someone's
# shoulder; goals and identity are exactly the material CONSTITUTION №3 keeps
# inside this machine. A test asserts the text cannot appear here.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
NOW="$(date +%s)"
# stdout is the report (status-dashboard-generate.sh reads its table), so the run log goes to stderr (contracts/logging.md).
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init freshness

# D1: the config dir is a variable, never a bare ~/.claude. HARBOR_DOC_TELOS_DIR
# overrides the whole corpus root so the suite can score a fixture instead of
# reading the operator's real goals — a test that needs live personal files to
# pass is a test nobody can run.
TELOS_ROOT="${HARBOR_DOC_TELOS_DIR:-${HARBOR_TELOS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/MEMORY}}"

# Thresholds in days, by what the document is FOR. A contract that froze a seam
# should outlive a handoff brief by a wide margin; PROVENANCE tracks an upstream
# that ships continuously, so it goes stale fastest.
threshold() {
  case "$1" in
    docs/reference/provenance.md)            echo 60  ;;   # upstream releases; docs/explanation/admission-baseline.md names this the only drift mitigation
    docs/how-to/handover.md|docs/generated/status.md)     echo 30  ;;   # "resume here" — wrong fast
    policy/constitution.md)          echo 180 ;;   # should move slowly or it is not constitutional
    contracts/*)              echo 120 ;;   # frozen seams
    docs/reports/rejected-approaches.md)             echo 365 ;;   # append-only; silence is legitimate
    docs/reports/handover-archive.md)       echo 365 ;;   # superseded records — OLD BY DESIGN.
                                            # The default 90 would nag forever
                                            # about a file whose whole job is to
                                            # stop changing, and a check that
                                            # fires on the ordinary case is one
                                            # that gets muted (№2.11).
    *)                        echo 90  ;;
  esac
}

age_days() { # <path relative to ROOT>
  _t="$(git -C "$ROOT" log -1 --format=%ct -- "$1" 2>/dev/null || true)"
  [ -n "$_t" ] || { echo -1; return 0; }
  echo $(( (NOW - _t) / 86400 ))
}

# mtime, in seconds, portably. BSD stat and GNU stat disagree on the flag, and
# `ls -l` parsing loses the year. Both spellings are tried and the failure is
# -1 = unknown, never 0 = brand new: a corpus whose age cannot be read must not
# render as freshly reviewed.
#
# VALIDATE THE OUTPUT, NEVER THE EXIT CODE — the rule already written at
# bin/alert-probe.sh:93 and applied here late. `stat -f` means "format" to BSD stat and
# "file system status" to GNU stat, so on Linux the first call PRINTS a block of
# filesystem fields to stdout and THEN fails; an `||` chain appends the second
# call's answer to that garbage, `$_m` is non-empty, `[ -n "$_m" ]` waves it
# through, and the arithmetic below dies:
#
#   bin/doc-freshness.sh: 84: Illegal number:   File: ".../TELOS.md"
#
# Under this file's `set -eu` that ABORTS `harbor fresh` part-way through its own
# report — measured 2026-09-06 on GNU coreutils 9.4, which is also why the eight
# C1a assertions in floor-test could not pass on a Linux runner. The BSD path is
# unchanged: `stat -f %m` returns digits there and wins the first case.
mtime_days() { # <absolute path>
  [ -f "$1" ] || { echo -1; return 0; }
  _m="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_m" in ''|*[!0-9]*) _m="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_m" in ''|*[!0-9]*) echo -1; return 0 ;; esac
  echo $(( (NOW - _m) / 86400 ))
}

# A `YYYY-MM-DD` → day number. Pure arithmetic on the calendar fields (no
# `date -d` / `date -j`, which are the GNU/BSD split this repo keeps tripping over).
jdn() { # <YYYY-MM-DD> — prints a day number, or nothing if the format is wrong
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) return 0 ;;
  esac
  _y=${1%%-*}; _rest=${1#*-}; _mo=${_rest%%-*}; _d=${_rest#*-}
  # ${x#0} not $((x)): POSIX arithmetic reads a leading zero as OCTAL, so `08` and
  # `09` are errors under set -eu and August and September would abort the script.
  _y="${_y#0}"; _mo="${_mo#0}"; _d="${_d#0}"
  _y=$((_y)); _mo=$((_mo)); _d=$((_d))
  if [ "$_mo" -le 2 ]; then _y=$((_y - 1)); _mo=$((_mo + 12)); fi
  _era=$(( _y / 100 ))
  echo $(( 365*_y + _y/4 - _era + _era/4 + (153*(_mo - 3) + 2)/5 + _d ))
}

# Age in days, LOCAL to LOCAL. Prints ERR when the date is unreadable, so the
# caller can tell "cannot be scored" from "dated in the future" — different facts
# with different fixes.
#
# BOTH SIDES ARE LOCAL, and that is the bug this shape exists to prevent. The first
# cut compared a local calendar date against UTC epoch days (`NOW / 86400`), so in
# a UTC+3 timezone every entry dated TODAY scored -1 between 00:00 and 03:00 local
# and was reported as an unparseable date. Found on 2026-07-31 at 00:30 local, by
# the first real GOALS.md rather than by the suite — the fixture used today's date
# and passed all afternoon, because the skew only appears inside the offset window.
date_days() { # <YYYY-MM-DD>
  _a="$(jdn "$1")"
  [ -n "$_a" ] || { echo ERR; return 0; }
  _b="$(jdn "$(date +%Y-%m-%d)")"
  echo $(( _b - _a ))
}

MODE="${1:-}"
# UNKNOWN FLAG → 2, WHICH IS THE CLI CONTRACT AND WAS NOT HONOURED HERE.
# contracts/cli.md:70 makes exit 2 "usage error — unknown verb, unknown flag,
# missing argument", uniform across verbs "because a caller that has to remember
# per-verb codes will not". Measured 2026-08-14: `harbor fresh --bogus` ran the full
# report and exited 0 — the flag was neither honoured nor refused, so a typo in a
# wired invocation or a CI step reads as success. `harbor cite` and `harbor dash`
# had the same hole; unknown VERBS were already handled at bin/harbor.
#
# The guard is HERE and not in the dispatcher because the dispatcher cannot know
# which flags a verb takes without a second copy of that list — and a copy is what
# rots. Each verb owns its own flag set; bin/harbor forwards and exits verbatim.
#
# AND THE GUARD VALIDATED ONLY $1 (harbor#226). `doc-freshness.sh --open --bogus` and
# `doc-freshness.sh --open extra` ran the full report and exited 0 — the same hole one
# position over, with the same consequence the paragraph above describes. The
# offending token is named rather than counted, because "too many arguments" sends
# the reader back to work out which one.
case "$MODE" in
  ''|--open) ;;
  *) log_fail "unknown flag $MODE (accepts: --open)"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
[ $# -le 1 ] || { log_fail "unexpected argument $2 (accepts: --open)"; log_fix "sh $0 --help"; log_end || :; exit 2; }

# ── ContextAudit — the open-question markers Interview surfaces separately ──
if [ "$MODE" = "--open" ]; then
  log_head "open markers (TBD / TODO / OPEN / undecided / awaiting)"
  # -w, NOT \b. `\b` is a GNU extension that git grep's default engine silently
  # does not honour here — it matched NOTHING and reported "none", which is the
  # exact fail-open shape lint rule F2 exists to catch in the guards.
  _open="$(git -C "$ROOT" grep -nwEi '(TBD|TODO|FIXME|still open|awaiting an owner|undecided|not adjudicated)' \
      -- '*.md' 2>/dev/null \
    | grep -vE '^(vendor/|docs/reports/rejected-approaches\.md|bin/)' \
    | cut -c1-160 | sed 's/^/  /' || true)"
  if [ -n "$_open" ]; then printf '%s\n' "$_open"; log_note "$(printf '%s\n' "$_open" | wc -l | tr -d ' ') open marker(s) listed above"
  else log_ok "no open markers"; fi
  log_end; exit $?
fi

log_head "documents, stalest first"
# The rule under each column header is part of the table (data; status-dashboard-generate.sh keys on it), not a log header.
_RULE='───────────────────────────────────────────────────────────'
printf '%-30s %6s %6s  %s\n' DOCUMENT AGE LIMIT STATUS
printf '%s\n' "$_RULE"

# Priority sort: over-threshold first (Interview's +200 bump), then by age.
docs="$(cd "$ROOT" && git ls-files '*.md' 'contracts/*.md' 2>/dev/null \
        | grep -vE '^(vendor/|\.github/)' | sort -u)"

# ROWS, not a pipeline. `for … done | sort` puts the loop body in a SUBSHELL, so
# every `stale_n=$((stale_n + 1))` inside it was discarded and the summary below
# reported "Nothing past its threshold" unconditionally — a report that cannot
# report (CONSTITUTION №2.10). Invisible in this repo only because every document
# is younger than its threshold today, so the true and the broken answer agree.
ROWS="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$ROWS"' EXIT INT TERM HUP

emit() { # <priority> <stale:0|1> <formatted line>
  printf '%08d\t%s\t%s\n' "$1" "$2" "$3" >> "$ROWS"
}

for f in $docs; do
  a="$(age_days "$f")"
  [ "$a" -ge 0 ] || continue
  case "$f" in contracts/*) t="$(threshold 'contracts/x')" ;; *) t="$(threshold "$f")" ;; esac
  if [ "$a" -gt "$t" ]; then p=$(( a + 200 )); s="STALE — still right?"; k=1
  else p="$a"; s="fresh"; k=0; fi
  emit "$p" "$k" "$(printf '%-30s %5dd %5dd  %s' "$f" "$a" "$t" "$s")"
done
sort -rn "$ROWS" | cut -f3-
stale_n="$(cut -f2 "$ROWS" | grep -c '^1$' || true)"
: > "$ROWS"

# ── C1a corpus (harbor#43): the operator's working context ──────────────────
# The `telos` skill is installed and ambient and reads these three paths. When
# they do not exist the honest output is the FINDING, not a silent empty table —
# a live skill pointed at an empty address is the defect the ticket names.
printf '\n%-30s %6s %6s  %s\n' 'WORKING CONTEXT' AGE LIMIT STATUS
printf '%s\n' "$_RULE"
telos_n=0
for rel in TELOS/TELOS.md TELOS/GOALS.md TELOS/BELIEFS.md IDENTITY.md; do
  [ -f "$TELOS_ROOT/$rel" ] || continue
  telos_n=$(( telos_n + 1 ))
  case "$rel" in
    TELOS/GOALS.md)
      # PER ENTRY, because a goal list is not one document. Format, mirroring
      # IDEAS.md so the operator learns one shape and not two:
      #   - `G1` · 2026-07-30 · active · <the goal>
      # The date is when the entry was last REVIEWED. Ids are stable: an edited
      # or retired goal keeps its id, which is what makes staleness trackable
      # per entry rather than resetting the whole file on every edit.
      #
      # The goal TEXT is cut here and never printed. Ids and ages only.
      _seen=0
      while IFS= read -r line; do
        # COLUMN 0, not `^[[:space:]]*-`. The relaxed form scored the FORMAT EXAMPLE
        # in the file's own header — an indented `- \`G1\` · YYYY-MM-DD · …` inside a
        # code block — as a real, undated goal. A document that documents its own
        # shape must not be parsed as an instance of it.
        _id="$(printf '%s' "$line" | sed -n 's/^-[[:space:]]*`\([A-Za-z][A-Za-z0-9_-]*\)`.*/\1/p')"
        [ -n "$_id" ] || continue
        _rv="$(printf '%s' "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
        _seen=$(( _seen + 1 ))
        if [ -z "$_rv" ]; then
          emit 999999 1 "$(printf '  %-28s %5s  %4dd  %s' "$_id" 'no date' 90 'UNDATED — cannot be scored')"
          continue
        fi
        a="$(date_days "$_rv")"
        if [ "$a" = "ERR" ]; then
          emit 999998 1 "$(printf '  %-28s %5s  %4dd  %s' "$_id" 'bad' 90 'UNPARSEABLE reviewed date')"
        elif [ "$a" -lt 0 ]; then
          # A future review date is a typo or a clock problem, not staleness — and
          # calling it stale would send the operator to re-review a fresh entry.
          emit 999997 1 "$(printf '  %-28s %4dd  %4dd  %s' "$_id" "$a" 90 'DATED IN THE FUTURE — typo?')"
        elif [ "$a" -gt 90 ]; then
          emit $(( a + 200 )) 1 "$(printf '  %-28s %4dd  %4dd  %s' "$_id" "$a" 90 'STALE — still right?')"
        else
          emit "$a" 0 "$(printf '  %-28s %4dd  %4dd  %s' "$_id" "$a" 90 'fresh')"
        fi
      done < "$TELOS_ROOT/$rel"
      emit 1000000 0 "$(printf '%-30s %5s %5s  %s' "$rel" '—' '—' 'per entry, below')"
      [ "$_seen" -gt 0 ] || emit 999997 1 "$(printf '%-30s %5s %5s  %s' "$rel" '—' '—' 'NO typed entries — nothing to score')"
      ;;
    *)
      # mtime is a WEAK signal and this says so rather than pretending: `touch`
      # looks identical to a review. It is the only signal available for an
      # untracked file, which is why GOALS.md carries dates in the content.
      a="$(mtime_days "$TELOS_ROOT/$rel")"
      t=180
      if [ "$a" -lt 0 ]; then
        emit 999996 1 "$(printf '%-30s %5s %5dd  %s' "$rel" '?' "$t" 'age UNKNOWN — treated as stale')"
      elif [ "$a" -gt "$t" ]; then
        emit $(( a + 200 )) 1 "$(printf '%-30s %4dd  %4dd  %s' "$rel" "$a" "$t" 'STALE — still right? (mtime)')"
      else
        emit "$a" 0 "$(printf '%-30s %4dd  %4dd  %s' "$rel" "$a" "$t" 'fresh (mtime)')"
      fi
      ;;
  esac
done
if [ "$telos_n" -eq 0 ]; then
  log_note "working context ABSENT — vendor/skills/telos is installed and ambient and reads MEMORY/TELOS/{TELOS,GOALS,BELIEFS}.md + MEMORY/IDENTITY.md; none exists. That is harbor#43, open by decision (the content is the operator's to write). Nothing here is scored."
else
  sort -rn "$ROWS" | cut -f3-
  stale_n=$(( stale_n + $(cut -f2 "$ROWS" | grep -c '^1$' || true) ))
fi

printf '\n'
if [ "$stale_n" -eq 0 ]; then
  log_ok "nothing past its threshold (age is a priority signal, not a failure; a fresh document is not evidence that it is correct)"
else
  log_warn "$stale_n document(s) past threshold"
  log_fix "sh $0 (stalest first; ask \"still right?\" of each, and rewrite nothing that still is)"
fi
log_note "open questions: sh bin/doc-freshness.sh --open"
log_end; exit $?
