#!/usr/bin/env sh
# doc-freshness.sh — per-document staleness over Harbor's governing files.
# harbor#5 (workstream C1a), method taken from upstream `Interview` @ a4e8e74.
#
# Method from upstream Interview @ a4e8e74: score each governing file's age and ask "still right?". Staleness is a
# PRIORITY signal, never a failure flag: this script never exits non-zero for age alone.
# Two corpora, two age sources (C1a, harbor#43): repo documents age from git; the operator's MEMORY/TELOS/*.md and
# MEMORY/IDENTITY.md are untracked (they must never reach the Log), so they age from mtime, and GOALS.md carries a
# per-entry reviewed date because mtime is a whole-file signal. The report never prints that corpus's content, ids and
# ages only (CONSTITUTION №3); a test asserts it.
# Removed notes: docs/explanation/code-cases/bin-doc-freshness.md
set -eu

# --help before any work (S4, harbor#140); the text is the header read at runtime, so it cannot drift.
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

# D1: the config dir is a variable. HARBOR_DOC_TELOS_DIR overrides the corpus root so the suite scores a fixture,
# not the operator's real goals.
TELOS_ROOT="${HARBOR_DOC_TELOS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/MEMORY}"

# Thresholds in days by what the document is FOR; PROVENANCE tracks a continuously shipping upstream, so it goes stale fastest.
threshold() {
  case "$1" in
    docs/reference/provenance.md)            echo 60  ;;   # upstream releases; docs/explanation/admission-baseline.md names this the only drift mitigation
    docs/how-to/handover.md|docs/generated/status.md)     echo 30  ;;   # "resume here" — wrong fast
    policy/constitution.md)          echo 180 ;;   # should move slowly or it is not constitutional
    contracts/*)              echo 120 ;;   # frozen seams
    docs/reports/rejected-approaches.md)             echo 365 ;;   # append-only; silence is legitimate
    docs/reports/handover-archive.md)       echo 365 ;;   # superseded records — OLD BY DESIGN.
                                            # (№2.11: the default 90 would nag forever about a file whose job is to stop changing.)
    *)                        echo 90  ;;
  esac
}

# Commit times come from ONE `git log` pass (harbor#667): `git log -1 -- <file>` per document cost 7 s here. Newest commit
# first, so the first sighting of a path is its last change; a document with no history is simply absent (age unknown).
commit_times() { # <out file>: "<unix time><TAB><path>" per path
  git -C "$ROOT" log -c --format=%ct --name-only --no-renames -- '*.md' 2>/dev/null | awk '
    /^[0-9]+$/ { ct = $0; next }
    $0 != "" && !($0 in seen) { seen[$0] = 1; print ct "\t" $0 }' > "$1"
}

# mtime in seconds, portably; failure is -1 = unknown, never 0 = brand new. Validate the OUTPUT, never the exit code:
# on GNU, `stat -f` prints filesystem fields and then fails, so an `||` chain appends to that garbage and the
# arithmetic aborts under `set -eu`. The BSD path wins the first case unchanged.
mtime_days() { # <absolute path>
  [ -f "$1" ] || { echo -1; return 0; }
  _m="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_m" in ''|*[!0-9]*) _m="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_m" in ''|*[!0-9]*) echo -1; return 0 ;; esac
  echo $(( (NOW - _m) / 86400 ))
}

# Pure calendar arithmetic: no `date -d` / `date -j`, the GNU/BSD split.
jdn() { # <YYYY-MM-DD> — prints a day number, or nothing if the format is wrong
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) return 0 ;;
  esac
  _y=${1%%-*}; _rest=${1#*-}; _mo=${_rest%%-*}; _d=${_rest#*-}
  # ${x#0} not $((x)): a leading zero reads as OCTAL, so 08 and 09 would abort under set -eu.
  _y="${_y#0}"; _mo="${_mo#0}"; _d="${_d#0}"
  _y=$((_y)); _mo=$((_mo)); _d=$((_d))
  if [ "$_mo" -le 2 ]; then _y=$((_y - 1)); _mo=$((_mo + 12)); fi
  _era=$(( _y / 100 ))
  echo $(( 365*_y + _y/4 - _era + _era/4 + (153*(_mo - 3) + 2)/5 + _d ))
}

# Age in days, LOCAL to LOCAL; ERR when unreadable, to tell "cannot be scored" from "dated in the future". Both sides
# local: a local date against UTC epoch days scored today's entries -1 in the offset window after midnight.
date_days() { # <YYYY-MM-DD>
  _a="$(jdn "$1")"
  [ -n "$_a" ] || { echo ERR; return 0; }
  _b="$(jdn "$(date +%Y-%m-%d)")"
  echo $(( _b - _a ))
}

MODE="${1:-}"
# Unknown flag or extra argument exits 2 (contracts/cli.md:70, uniform across verbs). The guard lives here, not in
# the dispatcher, which would need a second copy of each verb's flag list. Checked beyond $1 (harbor#226), and the
# offending token is named.
case "$MODE" in
  ''|--open) ;;
  *) log_fail "unknown flag $MODE (accepts: --open)"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
[ $# -le 1 ] || { log_fail "unexpected argument $2 (accepts: --open)"; log_fix "sh $0 --help"; log_end || :; exit 2; }

# ── ContextAudit — the open-question markers Interview surfaces separately ──
if [ "$MODE" = "--open" ]; then
  log_head "open markers (TBD / TODO / OPEN / undecided / awaiting)"
  # -w, not \b: \b is a GNU extension that git grep does not honour here, so it matched nothing (lint F2's fail-open shape).
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

# A ROWS file, not a pipeline: `for ... done | sort` runs the loop in a subshell and discards the stale_n count (№2.10).
ROWS="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
TIMES="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
AGES="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$ROWS" "$TIMES" "$AGES"' EXIT INT TERM HUP

emit() { # <priority> <stale:0|1> <formatted line>
  printf '%08d\t%s\t%s\n' "$1" "$2" "$3" >> "$ROWS"
}

# Join the document list to the commit times, in document order; a document with no commit time drops out. A path with
# whitespace dropped out of the old word-split loop too, so it still does (the report stays byte-identical).
commit_times "$TIMES"
printf '%s\n' "$docs" | awk -F'\t' 'NR == FNR { t[$2] = $1; next } ($0 in t) && $0 !~ /[ \t]/ { print t[$0] "\t" $0 }' "$TIMES" - > "$AGES"

TAB="$(printf '\t')"
while IFS="$TAB" read -r ct f; do
  a=$(( (NOW - ct) / 86400 ))
  [ "$a" -ge 0 ] || continue
  case "$f" in contracts/*) t="$(threshold 'contracts/x')" ;; *) t="$(threshold "$f")" ;; esac
  if [ "$a" -gt "$t" ]; then p=$(( a + 200 )); s="STALE — still right?"; k=1
  else p="$a"; s="fresh"; k=0; fi
  emit "$p" "$k" "$(printf '%-30s %5dd %5dd  %s' "$f" "$a" "$t" "$s")"
done < "$AGES"
sort -rn "$ROWS" | cut -f3-
stale_n="$(cut -f2 "$ROWS" | grep -c '^1$' || true)"
: > "$ROWS"

# ── C1a corpus (harbor#43): the operator's working context ──────────────────
# The `telos` skill reads these paths; when absent the honest output is the FINDING, not a silent empty table.
printf '\n%-30s %6s %6s  %s\n' 'WORKING CONTEXT' AGE LIMIT STATUS
printf '%s\n' "$_RULE"
telos_n=0
for rel in TELOS/TELOS.md TELOS/GOALS.md TELOS/BELIEFS.md IDENTITY.md; do
  [ -f "$TELOS_ROOT/$rel" ] || continue
  telos_n=$(( telos_n + 1 ))
  case "$rel" in
    TELOS/GOALS.md)
      # PER ENTRY, since a goal list is not one document: `- \`G1\` · 2026-07-30 · active · <goal>`; the date is when it was
      # last REVIEWED. Ids are stable, so edits do not reset the file. The goal TEXT is cut here and never printed.
      _seen=0
      while IFS= read -r line; do
        # COLUMN 0 only: the indented format example in the file's own header must not parse as an undated goal.
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
          # A future review date is a typo or clock problem, not staleness.
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
      # mtime is a WEAK signal (`touch` looks like a review), but the only one for an untracked file.
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
