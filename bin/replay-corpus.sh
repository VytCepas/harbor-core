#!/usr/bin/env sh
# M2 · DoctrineReplay (harbor#44) — build the real-traffic replay corpus.
#
# WHY THIS EXISTS. Harbor's floor has been rewritten across twelve adversarial
# passes against 573 SYNTHETIC assertions and zero real traffic. That is the
# mechanism behind "every pass fixed things and the next pass found ~24
# regressions": a rule change was argued, never measured. FLOOR.md's install
# criterion has been adjudicated three times by estimate.
#
# WHERE THE CORPUS COMES FROM, AND WHY NOT L1. harbor#44 says "once L1 records
# real commands, replay against the corpus". L1 (harbor#41) DELIBERATELY NEVER
# RECORDS COMMAND TEXT — it stores a salted truncated digest, because a guard
# that writes down what it blocked is an exfil channel aimed at your own disk.
# You cannot replay a digest. The only real-traffic source is the Claude Code
# transcripts under ~/.claude/projects/, where every command already sits in the
# clear, on disk, today. READING them creates no exposure that does not already
# exist. WRITING a distilled copy does, which is what the rest of this is about.
#
# MEASURED, NOT ASSUMED: on this machine 65 of 6,578 unique Bash payloads and 13
# of 754 Write/Edit payloads match the floor's OWN live-secret shape, and
# gitleaks finds 71 issues including 8 private-key and 2 aws-access-token. Many
# are certainly synthetic fixtures written while building the floor — but they
# cannot be separated from real ones without reading them at scale, which is the
# exact thing this design refuses to do. So the corpus is treated as
# credential-bearing and handled accordingly.
#
# THREE CONTROLS, IN ORDER:
#   1. SCRUB, shape-preserving. A matched secret is replaced by the SAME NUMBER
#      of bytes, keeping its prefix, so `ghp_<40 real>` becomes `ghp_AAAA…`.
#      The guard's regex still fires identically — which is the whole point:
#      DROPPING these records would blind the egress rules on precisely the
#      traffic they exist for, at a cost of only ~1% of the corpus.
#   2. VERIFY with an independent tool. gitleaks runs over the SCRUBBED output;
#      any record that still trips it is DROPPED, not shipped. Scrubbing that
#      trusts only its own regex is scrubbing that trusts the thing being tested.
#   3. NEVER PERSIST. The corpus is written to a caller-supplied path — in
#      practice a temp dir that bin/replay.sh deletes on exit — and this script
#      has no durable output mode at all. That is an OWNER DECISION (2026-07-28),
#      and the reason is sharper than "be careful with secrets": materialising
#      the corpus turns 481 mixed transcript files into ONE greppable store of
#      every command the operator has typed, and it OUTLIVES the 30-day GC that
#      deletes the transcripts. The transcripts stay the only copy.
#      What DOES persist is bin/replay.sh's baseline: payload hashes and
#      verdicts, no command text — the same redact-by-construction stance L1
#      takes, arrived at for the same reason.
set -eu

# The report is the run's log (CONTRACTS/logging.md, harbor#771); the corpus itself goes to --to, never stdout.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
log_init replay-corpus
# die <what failed> <fix> — a refusal: FAIL, its fix, the summary, exit 1.
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) die "config dir must be absolute: $CFG" "CLAUDE_CONFIG_DIR=\$HOME/.claude sh $0 --help" ;; esac

SRC_DIR="${HARBOR_TRANSCRIPTS:-$HOME/.claude/projects}"
OUT=""            # required: where to write. There is no default on purpose.
LIMIT=0
EXCL_FILE=""      # --exclude-file: a caller-supplied file, one glob per line
EXCL_LIST=""      # --exclude: collected IN MEMORY, materialised inside $TMP only

while [ $# -gt 0 ]; do
  case "$1" in
    --to)      shift; OUT="${1:-}" ;;
    --limit)   shift; LIMIT="${1:-0}" ;;
    # IN MEMORY, never a file at a predictable path (pass-3 review). The first
    # cut appended to `${TMPDIR:-/tmp}/helm-excl.$$` during ARGUMENT PARSING —
    # above `umask 077`, above the cleanup trap, and above the two ordinary
    # error exits (`no transcripts`, `jq is required`). So it was created 0644
    # at a PID-predictable name, `>>` wrote THROUGH a symlink planted there, and
    # it blocked forever in open(2) on a FIFO — with no `timeout` on macOS to
    # bound it. That is harbor#47 finding 8's shape, reopened one filename over
    # by the hunk that was fixing finding 7.
    --exclude)      shift; EXCL_LIST="$EXCL_LIST${1:-}
" ;;
    --exclude-file) shift; EXCL_FILE="${1:-}" ;;
    -h|--help)
      echo "usage: replay-corpus.sh --to <path> [--limit N] [--exclude <glob>]... [--exclude-file <f>]"
      echo "  Builds an EPHEMERAL corpus from $SRC_DIR at <path>."
      echo "  There is no durable output mode: the caller owns the path and its deletion."
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

[ -d "$SRC_DIR" ] || die "no transcripts at $SRC_DIR" "HARBOR_TRANSCRIPTS=<projects dir> sh $0 --help"
command -v jq >/dev/null 2>&1 || die "jq is required" "$(pkg_hint jq)"

# umask BEFORE mkdir (#47 finding 8): $TMP was created 0755 at a PID-predictable
# path that `mkdir -p` accepts pre-existing, so the pre-scrub RAW extract sat in a
# world-traversable directory for the length of the build.
umask 077
TMP="${TMPDIR:-/tmp}/helm-replay-build.$$"
mkdir -p "$TMP"
chmod 0700 "$TMP" 2>/dev/null || :
# u+w before rm: nothing here is mode-locked today, but the L1 host dir taught
# that a 0500 anywhere under a temp tree makes 'rm -rf' fail silently at exit.
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM HUP

# The exclusion patterns are materialised HERE — inside the 0700 temp dir, after
# the trap that deletes it — and never before. `--exclude` and `--exclude-file`
# are ADDITIVE (pass-3 review): they shared one variable, so whichever flag came
# last won and the other's patterns were discarded with no message at exit 0.
#
# `awk 1`, NOT `cat` — and yes, that is DE-20's entire subject, reintroduced by
# me three lines from the comment describing it (pass-4 review). `cat` does not
# terminate a final line that has none, so an `--exclude-file` written by
# `printf 'pat' > f` glued its last pattern onto the FIRST `--exclude` pattern
# and both silently matched nothing, at exit 0, with `0 excluded` printed as if
# nothing had been asked for. Unreachable from bin/replay.sh (it passes only
# --exclude-file, over a file it writes itself with a trailing newline on every
# line) — which is exactly why nothing caught it. R5d pins it now.
EXCL_PATS="$TMP/excl"; : > "$EXCL_PATS"
if [ -n "$EXCL_FILE" ] && [ -f "$EXCL_FILE" ]; then awk 1 "$EXCL_FILE" >> "$EXCL_PATS" 2>/dev/null || :; fi
printf '%s' "$EXCL_LIST" >> "$EXCL_PATS"

# ── 1 · extract ─────────────────────────────────────────────────────────────
# @json keeps ONE RECORD PER LINE. Commands contain newlines, and a naive
# `sort -u` over raw text splits one command into many fake entries — measured:
# 6,578 real commands read as 40,287 "lines".
#
# -R + `fromjson? // empty` (#47 finding 3): every transcript streamed into ONE
# jq, so a single malformed line anywhere aborted it and SILENTLY TRUNCATED the
# corpus at that point. A short corpus reports fewer blocks, which reads as a
# cleaner floor. Unparseable lines are now skipped, not fatal.
#
# `awk 1`, NOT `cat` — and this is a REGRESSION THE FIX ITSELF INTRODUCED
# (pass-2 review). jq's streaming parser needs no newlines, but `-R` reads LINES:
# a transcript file with no trailing newline glues its last record onto the first
# record of the next file, and BOTH are then unparseable and silently dropped.
# Two records lost per unterminated file — exactly 2*(N-1) for N files, one pair
# per boundary — invisible because the loss reads as a smaller corpus. `awk 1`
# terminates every line, so file boundaries survive concatenation.
#
# `-n1` IS LOAD-BEARING (pass-3 review), and this is the second regression the
# same one-word fix introduced. `awk` FATALs (rc 2) on the first operand it
# cannot open and never opens the REST OF THE BATCH; `cat` printed to the
# suppressed stderr and moved to the next file. ~481 paths fit one xargs batch,
# so a single .jsonl that find(2) lists and open(2) then fails on — an ordinary
# race against a store being appended to by live sessions and swept by the
# 30-day GC during a 30-60s build — silently discarded most of the corpus.
# Measured: 400 files under ordinary create/delete churn gave 136 records at
# HEAD against 400 with `cat`, both exiting 0 with empty stderr. `-n1` restores
# per-file tolerance (xargs resumes at the next batch) and keeps the line
# termination this fix was written for. R5b pins the termination half; R5c the
# tolerance half.
# THE PROJECT CENSUS (#47 finding 17). The 7.6%/15-18% figures in this repo's
# history were NOT reproducible by any code in it: the corpus was built over the
# whole transcript tree, and the "46% of it is harbor's own floor development"
# correction was applied by hand in a scratch script and recorded only in a
# commit message. A measurement whose denominator is chosen outside the tool is
# not a measurement. Transcripts are already partitioned by project directory, so
# the census is structural — no keyword heuristic — and it is printed on EVERY
# run whether or not anything is excluded.
find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort > "$TMP/alldirs"
: > "$TMP/dirs"; : > "$TMP/skipped"
while IFS= read -r _d; do
  _b="$(basename "$_d")"; _drop=0
  # GLOB, not substring: every project dir here shares the `-Users-someone`
  # prefix, so a substring test could not name one without matching all of them.
  # `--exclude -Users-someone` is exact; `--exclude '*example*'` is a wildcard.
  #
  # Read from a FILE, one pattern per line (pass-2 review). `for _x in $EXCLUDE`
  # split the list on IFS *and* pathname-expanded each word against the caller's
  # cwd — so `--exclude '*example*'` silently became a no-op when run from a directory
  # containing no matching file, and a pattern with a space split into two.
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
  { while IFS= read -r _d; do find "$_d" -name '*.jsonl' -type f -print0 2>/dev/null; done < "$TMP/dirs"; } \
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
# The SECRET corpus is lifted verbatim from guard-egress.sh rather than copied,
# so the scrubber and the guard can never disagree about what a secret looks
# like. A second copy of that regex is a second thing to keep in step, and
# PROVENANCE.md's whole enumerated-list-drift problem is exactly this shape.
GUARD_EGRESS="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/guard-egress.sh"
SECRET="$(sed -n "s/^SECRET='\(.*\)'$/\1/p" "$GUARD_EGRESS" 2>/dev/null || true)"
[ -n "$SECRET" ] || die "could not lift SECRET from $GUARD_EGRESS" "sh bin/floor-verify.sh --live"
# mawk 1.3.4 (ubuntu's awk) matches an open interval `{n,}` as exactly n, so RLENGTH stops short and the
# secret's tail survives unmasked (harbor#1149). `[c]{n}[c]*` means the same in every awk; any `{n,}` left refuses.
SCRUB_SHAPES="$(printf '%s' "$SECRET" | sed -E 's/(\[[^]]*\])\{([0-9]+),\}/\1{\2}\1*/g')"
case "$SCRUB_SHAPES" in *[0-9],\}*) die "SECRET has an open interval scrub() cannot rewrite for mawk" "make it a bracket expression, [..]{n,}, in $GUARD_EGRESS" ;; esac

# Same LENGTH and same PREFIX, body replaced with 'A'. Length matters: several
# floor rules key on {20,}/{32,} quantifiers, so a shorter replacement would
# stop matching and the corpus would silently under-report egress blocks.
scrub() { # stdin -> stdout
  SCRUB_RE="$SCRUB_SHAPES" awk '
    # ENVIRON, not -v: -v rewrites `\.` to `.` under gawk and mawk, loosening the regex (harbor#771).
    BEGIN { re = ENVIRON["SCRUB_RE"] }
    # Per-CHARACTER-CLASS substitution, not prefix+pad (#47 finding 6). The old
    # form kept the first 4 bytes and filled the rest with "A", which destroyed
    # the shape for 13 of the 25 SECRET families: `sk-ant-…` became `sk-aAAAA…`,
    # which no longer matches `sk-(ant|proj|live)-`, so the egress rules measured
    # as NOT FIRING on traffic they would really block. Mapping each byte to a
    # placeholder of its own class preserves length, punctuation, case pattern and
    # digit/letter structure — so every family still matches — while retaining
    # none of the value.
    # A JSON ESCAPE IS SYNTAX, NOT SECRET MATERIAL, and class-masking it produced a
    # corpus line that was not JSON. This scrubber runs over ALREADY-ENCODED text,
    # so a matched region can contain `\n`, `\t`, `\"` or `\uXXXX`. The class rule
    # below maps a lowercase letter to `a`, which turned `\n` into `\a` — an invalid
    # escape. Measured 2026-08-05: exactly one of 163 scrubbed payloads broke this
    # way, jq rejected that line, and the replay worker then dropped it SILENTLY,
    # leaving 31243 verdicts for 31244 records. The self-check caught the count and
    # refused to report, which is the only reason it was visible at all.
    #
    # So a backslash and the character it escapes are copied verbatim (six bytes for
    # `\uXXXX`). Nothing is lost: the escape is structure, and the value around it is
    # still masked.
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
    # The LITERAL PREFIX must survive the mask, or the family stops matching —
    # class-masking `ghp_` gave `aaa_`, and the suite caught it. Keep everything
    # up to and including the LAST separator inside the first 12 bytes
    # (ghp_ / sk-ant- / xoxb- / github_pat_ / glpat-), else the first 4
    # (AKIA / AIza / eyJh). PEM headers are left whole: the header is not the
    # secret, the body is, and scrub_pem owns that.
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
# PEM bodies are not caught by SECRET (which matches only the BEGIN marker) and
# gitleaks found 8 of them. Any long base64 run is replaced wholesale.
scrub_pem() { sed -E 's#[A-Za-z0-9+/]{60,}={0,2}#PEMBODYSCRUBBEDPEMBODYSCRUBBEDPEMBODYSCRUBBEDPEMBODYSCRUBBEDXX#g'; }

SCRUBBED=0
for t in Bash Write Edit Path; do
  # NOT `|| echo 0`: grep -c PRINTS its count and THEN exits 1 when the count is
  # zero, so the fallback appended a second zero and every arithmetic expansion
  # downstream died on "0\n0". The count is already there; only sanitise it.
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
    # One file per record, so a finding identifies WHICH record to drop rather
    # than condemning the whole corpus.
    _i=0
    while IFS= read -r l; do
      _i=$((_i + 1)); printf '%s\n' "$l" > "$TMP/gl/$t/$_i.txt"
    done < "$TMP/$t.scrub"
    gitleaks detect --no-git --source "$TMP/gl/$t" \
      --report-format json --report-path "$TMP/gl-$t.json" >/dev/null 2>&1 || true
    jq -r '.[]?.File' "$TMP/gl-$t.json" 2>/dev/null | sed 's#.*/##; s#\.txt$##' | sort -un > "$TMP/drop.$t"
    # `-s` on the drop LIST, not on the report: gitleaks writes a literal `[]`
    # for a clean scan, which is a non-empty FILE, and the filter below has a
    # trap that turns an empty drop list into an empty CORPUS —
    # `NR==FNR` is true for every line of the second file when the first file has
    # no lines, so the whole corpus is consumed as the drop list and nothing is
    # printed. It only misfires when gitleaks finds NOTHING, i.e. the normal case
    # for most operators, which is why every real run here looked fine.
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
  # NOT fail-open by accident: without the independent check the corpus rests on
  # one regex checking its own work, so the build refuses rather than shipping a
  # file it cannot vouch for. The work-log gate takes the same stance.
  die "gitleaks is not installed — refusing to build a corpus that only its own scrubber has vetted" "$(pkg_hint gitleaks)"
fi

# ── 4 · assemble ────────────────────────────────────────────────────────────
# `id` is the STABLE LABEL KEY: an adjudication ("this block is correct") must
# survive rule renames and corpus rebuilds, so it keys on the payload, not on a
# line number or a rule id. Editing the command by one byte makes a new record,
# which is correct — it is a different command and deserves re-adjudication.
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
# Defence in depth over the escape fix above, and the reason is the failure it
# already caused: a line that is not JSON cannot be replayed, and the consumer's
# only reaction was to drop it without a word.
#
# THE FIRST CUT OF THIS CHECK EXCLUDED THE BAD LINES AND EXITED 0, WHICH WAS
# WORSE THAN NOT CHECKING AT ALL (Codex, harbor#133). replay.sh derives IN from
# `wc -l` of this very file (replay.sh:113), so dropping a line here makes IN
# smaller by exactly the number of records that went missing — the verdict-count
# self-check downstream then BALANCES, and the one detector that surfaced the
# original scrubber defect goes blind. Filtering would have hidden the bug this
# check exists to catch, in the tool built to measure real traffic.
#
# So it refuses the build instead. A line that is not JSON is a defect in THIS
# SCRIPT'S scrubber, never a property of the traffic: the payload was already
# valid JSON when it was read, and nothing but the masking above sits between
# there and here. Measured 0 malformed lines in 31,488 records after the escape
# fix, so this fails on a real defect rather than on ordinary traffic.
MALFORMED=0
if command -v jq >/dev/null 2>&1; then
  : > "$TMP/malformed.lines"
  _ln=0
  while IFS= read -r _cl; do
    _ln=$((_ln + 1))
    [ -n "$_cl" ] || continue
    printf '%s' "$_cl" | jq -e . >/dev/null 2>&1 && continue
    MALFORMED=$((MALFORMED + 1))
    # The LINE NUMBER and byte length, never the text. This is command text, and
    # stderr is not a place to reprint the payload the whole tool exists to avoid
    # materialising. A rebuild reaches the same line number.
    printf '  corpus line %s (%s bytes)\n' "$_ln" "${#_cl}" >> "$TMP/malformed.lines"
  done < "$TMP/corpus.jsonl"
  if [ "$MALFORMED" -gt 0 ]; then
    # Excluding them would shrink the corpus, which balances replay.sh's verdict-count self-check and hides
    # exactly the class of bug that check exists to find.
    while IFS= read -r _ml; do log_note "$_ml"; done < "$TMP/malformed.lines"
    die "REFUSING TO BUILD — $MALFORMED assembled line(s) are not valid JSON; a defect in this script's scrubber, not in the traffic" "sh bin/floor-verify.sh --live; then file it on harbor#44"
  fi
fi

if [ "$LIMIT" -gt 0 ]; then
  # Sample by the record's OWN id, never by line position (#47 finding 7). The
  # old form seeded srand and assigned weights in FILE ORDER, so adding one
  # command reshuffled the whole sample and the baseline silently compared a
  # DIFFERENT set of records — a delta computed against a different population
  # is not a delta. Sorting on the payload hash is stable under insertion.
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
# Per-project Bash counts, so a corpus dominated by ONE project is visible in the
# output instead of being discovered later by hand.
log_note "census (Bash tool calls per project, unique payloads):"
while IFS= read -r _d; do
  _c="$(find "$_d" -name '*.jsonl' -type f -print0 2>/dev/null | xargs -0 -n1 awk 1 2>/dev/null \
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
  # Refuse a path under the config dir or the repo. Both are places a corpus
  # would quietly become durable: $CFG is swept by sandbox-make and baseline-pin,
  # and the repo has a GitHub remote and no .gitignore.
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
