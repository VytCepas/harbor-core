#!/usr/bin/env sh
# M2 · DoctrineReplay (harbor#44) — build the real-traffic replay corpus.
# WHY: floor rewrites were argued against synthetic assertions, never measured on real traffic (harbor#44).
# SOURCE: the Claude Code transcripts, not L1 (harbor#41), which stores only a salted digest and cannot be replayed. Reading the
# transcripts adds no exposure; WRITING a distilled copy does, and some payloads carry live-secret shapes, so the corpus is credential-bearing.
# THREE CONTROLS, in order:
#   1. SCRUB, shape-preserving: same length and literal prefix, so the guard's regex fires identically (dropping them would blind egress rules).
#   2. VERIFY with gitleaks over the SCRUBBED output; a record that still trips it is DROPPED.
#   3. NEVER PERSIST: written only to a caller-supplied path (eval-replay.sh deletes it); no durable mode (owner decision 2026-07-28), as a
#      materialised corpus outlives the 30-day transcript GC. Only eval-replay.sh's payload hashes and verdicts persist.
# Removed notes: docs/explanation/code-cases/bin-eval-replay-corpus.md
set -eu

# The report is the run's log (contracts/logging.md, harbor#771); the corpus itself goes to --to, never stdout.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init replay-corpus
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) die "config dir must be absolute: $CFG" "CLAUDE_CONFIG_DIR=\$HOME/.claude sh $0 --help" ;; esac

SRC_DIR="${HARBOR_SESSION_TRANSCRIPTS:-$HOME/.claude/projects}"
OUT=""            # required: where to write. There is no default on purpose.
LIMIT=0
SINCE=0           # --since: only transcripts modified in the last N days (harbor#1420)
EXCL_FILE=""      # --exclude-file: a caller-supplied file, one glob per line
EXCL_LIST=""      # --exclude: collected IN MEMORY, materialised inside $TMP only

while [ $# -gt 0 ]; do
  case "$1" in
    --to)      shift; OUT="${1:-}" ;;
    --limit)   shift; LIMIT="${1:-0}" ;;
    --since)   shift; SINCE="${1:-0}" ;;
    # In memory, never a file at a predictable path: an append during argument parsing sat above umask and the trap, and followed a planted symlink (#47 finding 8).
    --exclude)      shift; EXCL_LIST="$EXCL_LIST${1:-}
" ;;
    --exclude-file) shift; EXCL_FILE="${1:-}" ;;
    -h|--help)
      echo "usage: eval-replay-corpus.sh --to <path> [--limit N] [--since DAYS] [--exclude <glob>]... [--exclude-file <f>]"
      echo "  Builds an EPHEMERAL corpus from $SRC_DIR at <path>."
      echo "  There is no durable output mode: the caller owns the path and its deletion."
      echo "  --since limits the corpus to transcripts modified in the last DAYS days."
      echo "  --exclude drops project dirs matching a GLOB (exact name, or '*example*')."
      echo "  Every run"
      echo "  prints the per-project census, so contamination is visible in the output"
      echo "  rather than corrected by hand afterwards."
      echo "  Without --to it reports what it WOULD build and writes nothing."
      exit 0 ;;
    *) die "unknown option $1: nothing was built" "sh $0 --help" ;;
  esac
  shift
done

case "$SINCE" in ''|*[!0-9]*) die "--since takes a whole number of days: $SINCE" "sh $0 --since 14 --help" ;; esac
# find(1) age filter: every transcript walk below goes through $AGE (unquoted on purpose).
AGE=""; [ "$SINCE" -gt 0 ] && AGE="-mtime -$SINCE"
[ -d "$SRC_DIR" ] || die "no transcripts at $SRC_DIR" "HARBOR_SESSION_TRANSCRIPTS=<projects dir> sh $0 --help"
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

# umask BEFORE mkdir (#47 finding 8): the raw pre-scrub extract must not sit in a world-traversable directory.
umask 077
TMP="${TMPDIR:-/tmp}/helm-replay-build.$$"
mkdir -p "$TMP"
chmod 0700 "$TMP" 2>/dev/null || :
# u+w before rm: a 0500 dir under a temp tree makes rm -rf fail silently.
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM HUP

# Exclusion patterns are materialised inside the 0700 temp dir, after the trap. --exclude and --exclude-file are ADDITIVE (they once shared a
# variable and the last flag won). `awk 1`, not `cat`: cat leaves a final line unterminated, gluing the file's last pattern onto the first
# --exclude pattern so both match nothing at exit 0 (R5d).
EXCL_PATS="$TMP/excl"; : > "$EXCL_PATS"
if [ -n "$EXCL_FILE" ] && [ -f "$EXCL_FILE" ]; then awk 1 "$EXCL_FILE" >> "$EXCL_PATS" 2>/dev/null || :; fi
printf '%s' "$EXCL_LIST" >> "$EXCL_PATS"

# ── 1 · extract ─────────────────────────────────────────────────────────────
# @json keeps ONE RECORD PER LINE (commands contain newlines, and raw `sort -u` splits them). -R + `fromjson? // empty`: one malformed line must not
# abort jq and silently truncate the corpus (#47 finding 3).
# `awk 1`, not `cat`: -R reads lines, so a file with no trailing newline glues its last record to the next file's first and both are lost (R5b).
# `-n1` is load-bearing: awk fatals on the first unopenable file and skips the rest of the xargs batch, where cat moved on; live sessions and
# the 30-day GC race the build (R5c).
# The project census prints on EVERY run: the denominator must be chosen inside the tool, structurally by project dir (#47 finding 17).
find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort > "$TMP/alldirs"
: > "$TMP/dirs"; : > "$TMP/skipped"
while IFS= read -r _d; do
  _b="$(basename "$_d")"; _drop=0
  # GLOB, not substring: every project dir shares the `-Users-someone` prefix. Patterns come from a FILE, one per line: `for _x in $EXCLUDE`
  # word-splits and pathname-expands against the caller's cwd (pass-2 review).
  if [ -s "$EXCL_PATS" ]; then
    while IFS= read -r _x; do
      [ -n "$_x" ] || continue
      # shellcheck disable=SC2254
      case "$_b" in $_x) _drop=1; break ;; esac
    done < "$EXCL_PATS"
  fi
  if [ "$_drop" = 1 ]; then printf '%s\n' "$_d" >> "$TMP/skipped"
  else printf '%s\n' "$_d" >> "$TMP/dirs"; fi
done < "$TMP/alldirs"

extract() { # <tool-filter> <payload-expr>
  { while IFS= read -r _d; do find "$_d" -name '*.jsonl' -type f $AGE -print0 2>/dev/null; done < "$TMP/dirs"; } \
    | xargs -0 -n1 awk 1 2>/dev/null \
    | jq -rcR "fromjson? // empty | select(.message.content?) | .message.content[]?
              | select(type==\"object\" and .type==\"tool_use\" and ($1))
              | ($2) | select(. != null and . != \"\") | @json" 2>/dev/null
}

extract '.name=="Bash"' '.input.command'                  | sort -u > "$TMP/Bash.raw"
extract '.name=="Write"' '.input.content'                 | sort -u > "$TMP/Write.raw"
extract '.name=="Edit"'  '.input.new_string'              | sort -u > "$TMP/Edit.raw"
extract '.name=="Write" or .name=="Edit" or .name=="MultiEdit"' '.input.file_path' \
                                                          | sort -u > "$TMP/Path.raw"

RAW_TOTAL=0
for t in Bash Write Edit Path; do
  RAW_TOTAL=$((RAW_TOTAL + $(wc -l < "$TMP/$t.raw" | tr -d ' ')))
done

# ── 2 · scrub, shape-preserving ─────────────────────────────────────────────
# The SECRET regex is lifted from admission-egress.sh, not copied, so the scrubber and the guard cannot disagree on what a secret looks like.
HARBOR_ADMISSION_EGRESS="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/admission-egress.sh"
SECRET="$(sed -n "s/^SECRET='\(.*\)'$/\1/p" "$HARBOR_ADMISSION_EGRESS" 2>/dev/null || true)"
[ -n "$SECRET" ] || die "could not lift SECRET from $HARBOR_ADMISSION_EGRESS" "sh bin/admission-verify.sh --live"
# mawk 1.3.4 (ubuntu's awk) matches an open interval `{n,}` as exactly n, so RLENGTH stops short and the
# secret's tail survives unmasked (harbor#1149). `[c]{n}[c]*` means the same in every awk; any `{n,}` left refuses.
SCRUB_SHAPES="$(printf '%s' "$SECRET" | sed -E 's/(\[[^]]*\])\{([0-9]+),\}/\1{\2}\1*/g')"
case "$SCRUB_SHAPES" in *[0-9],\}*) die "SECRET has an open interval scrub() cannot rewrite for mawk" "make it a bracket expression, [..]{n,}, in $HARBOR_ADMISSION_EGRESS" ;; esac

# Same LENGTH and PREFIX, body replaced: floor rules key on {20,}/{32,}, so a shorter replacement would stop matching.
scrub() { # stdin -> stdout
  SCRUB_RE="$SCRUB_SHAPES" awk '
    # ENVIRON, not -v: -v rewrites `\.` to `.` under gawk and mawk, loosening the regex (harbor#771).
    BEGIN { re = ENVIRON["SCRUB_RE"] }
    # Per-character-class mask, not prefix+pad (#47 finding 6): the old form turned `sk-ant-` into `sk-aAAAA`, which no longer matched, so egress rules
    # measured as not firing on traffic they would block. A JSON escape is syntax, not secret: the text is already encoded, and class-masking an
    # escaped newline into an invalid escape produced a non-JSON line the replay worker dropped silently. A backslash and the character it
    # escapes are copied verbatim (six bytes for the unicode form).
    function mask(t,   i, c, o, nx) {
      o = ""
      i = 1
      while (i <= length(t)) {
        c = substr(t, i, 1)
        if (c == "\\") {
          nx = substr(t, i + 1, 1)
          if (nx == "u") { o = o substr(t, i, 6); i += 6 }
          else           { o = o substr(t, i, 2); i += 2 }
          continue
        }
        if      (c ~ /[0-9]/)   o = o "0"
        else if (c ~ /[A-Z]/)   o = o "A"
        else if (c ~ /[a-z]/)   o = o "a"
        else                    o = o c      # -, _, ., /, : keep the structure
        i++
      }
      return o
    }
    # The LITERAL PREFIX must survive the mask (ghp_, sk-ant-, glpat-, else the first 4 bytes) or the family stops matching. PEM headers stay
    # whole; scrub_pem owns the body.
    function keep(t,   i, c, k) {
      if (t ~ /^-----BEGIN/) return length(t)
      k = 0
      for (i = 1; i <= (length(t) < 12 ? length(t) : 12); i++) {
        c = substr(t, i, 1)
        if (c == "_" || c == "-") k = i
      }
      return (k > 0) ? k : 4
    }
    {
      line = $0; out = ""
      while (match(line, re)) {
        m = substr(line, RSTART, RLENGTH)
        n = keep(m)
        out = out substr(line, 1, RSTART - 1) substr(m, 1, n) mask(substr(m, n + 1))
        line = substr(line, RSTART + RLENGTH)
      }
      print out line
    }'
}
# PEM bodies are not caught by SECRET (it matches only the BEGIN marker): any long base64 run is replaced wholesale.
scrub_pem() { sed -E 's#[A-Za-z0-9+/]{60,}={0,2}#PEMBODYSCRUBBEDPEMBODYSCRUBBEDPEMBODYSCRUBBEDPEMBODYSCRUBBEDXX#g'; }

SCRUBBED=0
for t in Bash Write Edit Path; do
  # NOT `|| echo 0`: grep -c prints 0 AND exits 1, so the fallback appended a second zero and broke the arithmetic.
  before="$(grep -icE "$SECRET" "$TMP/$t.raw" 2>/dev/null | head -1 | tr -d ' \n')"
  case "$before" in ''|*[!0-9]*) before=0 ;; esac
  scrub < "$TMP/$t.raw" | scrub_pem > "$TMP/$t.scrub"
  SCRUBBED=$((SCRUBBED + before))
done

# ── 3 · independent verification, fail-closed per record ────────────────────
DROPPED=0
if command -v gitleaks >/dev/null 2>&1; then
  for t in Bash Write Edit Path; do
    mkdir -p "$TMP/gl/$t"
    # One file per record, so a finding names which record to drop.
    _i=0
    while IFS= read -r l; do
      _i=$((_i + 1)); printf '%s\n' "$l" > "$TMP/gl/$t/$_i.txt"
    done < "$TMP/$t.scrub"
    gitleaks detect --no-git --source "$TMP/gl/$t" \
      --report-format json --report-path "$TMP/gl-$t.json" >/dev/null 2>&1 || true
    jq -r '.[]?.File' "$TMP/gl-$t.json" 2>/dev/null | sed 's#.*/##; s#\.txt$##' | sort -un > "$TMP/drop.$t"
    # `-s` on the drop LIST, not the report (gitleaks writes `[]` for a clean scan). An empty list must not reach the awk below: NR==FNR holds
    # for every line when the first file is empty, so the whole corpus is consumed as the drop list.
    if [ -s "$TMP/drop.$t" ]; then
      _d="$(wc -l < "$TMP/drop.$t" | tr -d ' ')"
      DROPPED=$((DROPPED + _d))
      awk 'NR==FNR{d[$1]=1;next} !(FNR in d)' "$TMP/drop.$t" "$TMP/$t.scrub" > "$TMP/$t.clean"
    else
      cp "$TMP/$t.scrub" "$TMP/$t.clean"
    fi
  done
  GATE="gitleaks"
else
  # Fail-closed: without the independent check the corpus rests on one regex checking its own work.
  die "gitleaks is not installed — refusing to build a corpus that only its own scrubber has vetted" "$(pkg_hint gitleaks)"
fi

# ── 4 · assemble ────────────────────────────────────────────────────────────
# `id` is the stable label key: it hashes the payload so an adjudication survives rule renames and rebuilds.
: > "$TMP/corpus.jsonl"
for t in Bash Write Edit Path; do
  case "$t" in Path) tool=Write; field=file_path ;; *) tool="$t"; field=payload ;; esac
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    id="$(printf '%s' "$l" | { command -v /sbin/sha256sum >/dev/null 2>&1 \
          && /sbin/sha256sum || shasum -a 256; } | cut -c1-16)"
    printf '{"id":"%s","tool":"%s","kind":"%s","payload":%s}\n' "$id" "$tool" "$field" "$l"
  done < "$TMP/$t.clean"
done >> "$TMP/corpus.jsonl"

# ── EVERY LINE MUST BE JSON, AND A BAD ONE FAILS THE BUILD ──────────────────
# A non-JSON line is a defect in THIS script's scrubber, never the traffic, so the build is refused rather than filtered: eval-replay.sh derives
# IN from `wc -l` of this file, and dropping a line would make its verdict-count self-check balance and blind it (harbor#133).
MALFORMED=0
if command -v jq >/dev/null 2>&1; then
  : > "$TMP/malformed.lines"
  _ln=0
  while IFS= read -r _cl; do
    _ln=$((_ln + 1))
    [ -n "$_cl" ] || continue
    printf '%s' "$_cl" | jq -e . >/dev/null 2>&1 && continue
    MALFORMED=$((MALFORMED + 1))
    # Line number and byte length only, never the command text.
    printf '  corpus line %s (%s bytes)\n' "$_ln" "${#_cl}" >> "$TMP/malformed.lines"
  done < "$TMP/corpus.jsonl"
  if [ "$MALFORMED" -gt 0 ]; then
    while IFS= read -r _ml; do log_note "$_ml"; done < "$TMP/malformed.lines"
    die "REFUSING TO BUILD — $MALFORMED assembled line(s) are not valid JSON; a defect in this script's scrubber, not in the traffic" "sh bin/admission-verify.sh --live; then file it on harbor#44"
  fi
fi

if [ "$LIMIT" -gt 0 ]; then
  # Sample by the record's own id, never file position (#47 finding 7): positional sampling reshuffles when one command is added, so the baseline
  # compared a different population.
  sort -t'"' -k4,4 "$TMP/corpus.jsonl" | head -"$LIMIT" > "$TMP/corpus.limited"
  mv "$TMP/corpus.limited" "$TMP/corpus.jsonl"
fi

N="$(wc -l < "$TMP/corpus.jsonl" | tr -d ' ')"

log_head "corpus"
log_note "source          $SRC_DIR"
log_note "projects        $(wc -l < "$TMP/dirs" | tr -d ' ') included, $(wc -l < "$TMP/skipped" | tr -d ' ') excluded"
if [ -s "$TMP/skipped" ]; then
  while IFS= read -r _d; do log_note "  - excluded   $(basename "$_d")"; done < "$TMP/skipped"
fi
log_note "census (Bash tool calls per project, unique payloads):"
while IFS= read -r _d; do
  _c="$(find "$_d" -name '*.jsonl' -type f $AGE -print0 2>/dev/null | xargs -0 -n1 awk 1 2>/dev/null \
        | jq -rcR "fromjson? // empty | select(.message.content?) | .message.content[]?
                   | select(type==\"object\" and .type==\"tool_use\" and .name==\"Bash\")
                   | .input.command | select(. != null) | @json" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  [ "${_c:-0}" -gt 0 ] && log_note "$(printf '  %8s  %s' "$_c" "$(basename "$_d")")"
done < "$TMP/dirs"
log_note "raw payloads    $RAW_TOTAL (deduped, per tool)"
log_note "scrubbed        $SCRUBBED payload(s) carried a live-secret shape (shape kept, value replaced)"
log_note "dropped         $DROPPED record(s) still tripped $GATE after scrubbing"
log_ok "corpus size     $N records"

if [ -n "$OUT" ]; then
  # Refuse a path under the config dir or the repo: both would quietly make the corpus durable.
  case "$OUT" in
    "$CFG"/*) die "refusing to write inside the config dir — the corpus is ephemeral: $OUT" "sh $0 --to \"\${TMPDIR:-/tmp}/corpus.jsonl\"" ;;
    */.git/*) die "refusing to write inside a git dir: $OUT" "sh $0 --to \"\${TMPDIR:-/tmp}/corpus.jsonl\"" ;;
  esac
  cp "$TMP/corpus.jsonl" "$OUT"
  chmod 0600 "$OUT"
  log_note "wrote           $OUT (0600, EPHEMERAL — the caller must delete it)"
else
  log_note "DRY RUN — nothing written. Pass --to <path> to emit."
fi
log_end; exit $?
