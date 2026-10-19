#!/usr/bin/env sh
# store-check (CX1, harbor#150 Phase 5 · harbor#183/#184) — bound the memory
# store. SIZE and AGE, which is the half nothing measured.
#
# WHY THIS EXISTS, AND WHY IT IS NOT bin/memory-lint.sh. memory-lint is the
# anti-ROT gate: dangling wikilinks, dead relative paths, slug collisions. It has
# no size dimension at all, and size is the thing that costs something every
# session. Measured on this box 2026-08-20, with the cwd at $HOME:
#
#   the store               85 file(s), 457,140 B
#   MEMORY.md, the index    22,234 B, 84 pointer line(s)
#   ~/.claude/CLAUDE.md     14,576 B
#   context-budget total    44,078 B against a 24,000 B ceiling — 183%
#
# The INDEX alone is larger than the constitution, it is charged in FULL in every
# session, and it grows by one line per memory written, forever. Nothing bounded
# it. That is CX1's "nothing bounds the store behind it", and harbor#183's
# always-on overage is now mostly this one file.
#
# THE ALLOWANCE IS THE INDEX'S OWN SHAPE (harbor#316, from 2026-09-20):
#
#   allowance = always-on pointers x 150 B + 600 B of section structure
#
# so the bound depends on the file being measured and on nothing else. The number
# is CONSTITUTION.md's own arithmetic — "Allowing 150 B a pointer ... plus ~600 B
# of section structure" — applied to the file that sentence was about.
#
# IT USED TO BE `ceiling - (spent - index)`, DERIVED FROM context-budget.sh, and
# the reasoning for that is worth keeping because it was good and still lost. The
# argument was: a second constant that must agree with HARBOR_CONTEXT_CEILING is a
# copy, and copies drift while reading perfectly (T1/T2). True of a second
# CEILING. Not true of 150 B, which is not a copy of anything — it is the cost of
# one routing-table line, a fact about this file's shape and about no other
# surface in the system.
#
# WHAT KILLED THE OLD FORMULA WAS THE OTHER TOOL GETTING BETTER. #316 taught
# context-budget.sh to count plugin agent descriptions, slash-command
# descriptions and the SessionStart injection — 19,494 B that every session was
# always paying and nothing had ever counted. Nothing about the memory store
# changed. The allowance fell from 9,477 B to 799 B and this tool began demanding
# a five-pointer index: §2.11's false positive, arrived at by measuring something
# else more honestly. A bound that moves for that reason is pointed at the wrong
# thing.
#
# WHEN THE ALLOWANCE CANNOT BE DERIVED, THERE IS STILL NO VERDICT, and the
# trigger has simply moved: an index with bytes and no parsed pointer means either
# "not a routing table" or "the extractor stopped matching", and nothing here can
# tell which. It never falls back to an invented number, because a bound nobody
# chose is the arguable threshold that gets a check switched off (§2.11), and
# because substituting weaker evidence under a stronger name is §2.7.
#
# THE SUBJECT IS THE cwd-KEYED AUTO-MEMORY STORE, not $CFG/MEMORY. That is the
# store the harness actually loads into every session, and it is keyed by the
# working directory with `/` -> `-` and NO WALK-UP — a fact context-budget.sh
# establishes behaviourally rather than from docs, and gets its own comment
# there. This file resolves it the same way ON PURPOSE and the duplication is
# noted rather than hidden: two tools must agree about which file loads, and the
# alternative — this one asking context-budget where to look — makes the size
# report depend on a tool whose failure mode is printing no rows at all.
#
# INDEX PARITY IS A DIFFERENT SURFACE FROM memory-lint's DANGLING CHECK. That one
# reads [[wikilinks]] BETWEEN notes. This one reads the index's `](file.md)`
# pointers, in both directions:
#
#   dangling  the index points at a note that is not there — a recall that will
#             never resolve, paid for in every session's prefix.
#   orphan    a note no index line names. It cost bytes to write and it is
#             invisible at recall time, which is the worse of the two failures
#             because nothing about it looks wrong.
#
# AGE IS REPORT-ONLY, ALWAYS — memory-lint's doctrine, and the argument is
# unchanged: a note written once and correct forever is the GOAL. A gate that
# failed on age would teach the operator to touch files to silence a linter.
# Age here comes from mtime, not git, because this store is not a git repo
# (memory-lint reports 0 stale on it for exactly that reason). mtime is weaker
# evidence — a copy or a restore resets it — and that is disclosed in the output
# rather than papered over.
set -eu

# NOGLOB, memory-lint's reason: lists below are split by setting IFS and
# expanding unquoted, which governs field splitting only. A note filename holding
# *, ? or [ ] would still be pathname-expanded against the working directory.
set -f

# harbor#813: its own dir by ${0%/*}, never a dirname fork. stdout is the report or its JSON, so a
# log goes to stderr; usage errors stay plain exits 2 (CONTRACTS/logging.md).
case "$0" in */*) _sc_dir="${0%/*}" ;; *) _sc_dir=. ;; esac
LOG_FD=2; . "$_sc_dir/log-lib.sh"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STORE=""
INDEX=""
FULL_INDEX=""
STRICT=0
JSON=0
TOP=10
STALE_DAYS=180

usage() {
  cat <<'USAGE'
store-check (CX1) — size and age over the always-on memory store

  store-check.sh [--root DIR] [--index FILE] [--full-index FILE]
                 [--strict] [--json]
                 [--top N] [--stale-days N]

  --root DIR      the store to check (default: the cwd-keyed auto-memory store)
  --index FILE    the always-on index (default: MEMORY.md inside the store)
  --full-index F  the OVERFLOW index: pointers that are searched, never loaded.
                  Default INDEX-FULL.md beside the index, used only if present.
                  Parity is the UNION of both; bytes are the always-on one only.
  --strict        exit 1 when the index is over its derived allowance, or when
                  index parity is broken. Age and per-note size never fail.
  --json          machine-readable report
  --top N         how many largest notes to list (default 10)
  --stale-days N  age threshold in days (default 180, report-only)

  Link rot is bin/memory-lint.sh's subject, not this tool's. Run both.

  Exit: 0 clean (or nothing to check), 1 a --strict finding, 2 usage error.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)       [ "$#" -ge 2 ] || { printf 'store-check: --root needs a directory\n' >&2; exit 2; }
                  STORE="$2"; shift 2 ;;
    --root=*)     STORE="${1#--root=}"; shift ;;
    --index)      [ "$#" -ge 2 ] || { printf 'store-check: --index needs a file\n' >&2; exit 2; }
                  INDEX="$2"; shift 2 ;;
    --index=*)    INDEX="${1#--index=}"; shift ;;
    --full-index) [ "$#" -ge 2 ] || { printf 'store-check: --full-index needs a file\n' >&2; exit 2; }
                  FULL_INDEX="$2"; shift 2 ;;
    --full-index=*) FULL_INDEX="${1#--full-index=}"; shift ;;
    # VALIDATED, NOT LEFT TO THE ARITHMETIC. memory-lint carries the same guard
    # and the same reason: under dash a non-numeric operand makes $((…)) abort
    # the interpreter, so a typo kills the gate instead of printing a usage
    # error.
    --top)        [ "$#" -ge 2 ] || { printf 'store-check: --top needs a number\n' >&2; exit 2; }
                  case "$2" in ''|*[!0-9]*) printf 'store-check: --top expects a non-negative integer, got %s\n' "$2" >&2; exit 2 ;; esac
                  TOP="$2"; shift 2 ;;
    --stale-days) [ "$#" -ge 2 ] || { printf 'store-check: --stale-days needs a number\n' >&2; exit 2; }
                  case "$2" in ''|*[!0-9]*) printf 'store-check: --stale-days expects a non-negative integer, got %s\n' "$2" >&2; exit 2 ;; esac
                  STALE_DAYS="$2"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    --json)       JSON=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            printf 'store-check: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# THE SAME RESOLUTION context-budget.sh USES, deliberately. Direct slug match on
# the working directory, no walk-up to an ancestor store.
STORE_DEFAULT="$CFG/projects/$(printf '%s' "$PWD" | tr '/' '-')/memory"
[ -n "$STORE" ] || STORE="$STORE_DEFAULT"
[ -n "$INDEX" ] || INDEX="$STORE/MEMORY.md"

# ── THE ALLOWANCE BASIS IS THE CWD'S, SO A --root ELSEWHERE HAS NO VERDICT ──
# harbor#317. The allowance is `CEIL - (SPENT - IDX_BYTES)`, and `SPENT` is the
# `SPENT EVERY SESSION` line parsed out of context-budget.sh — which is computed
# for THIS cwd. The subtraction is only sound when the index being measured is
# the one already inside that number. Point `--root` at another store and the
# tool subtracts an index that was never in `SPENT`, inflating the allowance by
# exactly that index's size.
#
# Measured 2026-09-16 from ~/harbor, and it is the whole bug:
#
#   store-check --root <the -Users-someone store>
#       index 10479, allowance 20369 = 40000 - 19631   -> "9890 B of headroom"
#   context-budget.sh, same box, same minute
#       WORST CASE 40589 = 30110 + 10479               -> "OVER by 589 bytes"
#
#   19631 = 30110 - 10479. One tool subtracts the index from the basis, the
#   other adds it to the basis. Same file, same minute, opposite verdicts.
#
# So the verdict is refused rather than repaired: re-deriving `SPENT` for an
# arbitrary store means re-implementing context-budget's surface accounting, and
# §2.7 forbids substituting a weaker computation under the stronger one's name.
# The size facts are still printed; only the VERDICT is withheld.
#
# THAT REFUSAL IS LIFTED AS OF harbor#316, AND ONLY BECAUSE ITS CAUSE IS GONE.
# Every line above is an argument about ONE formula: `CEIL - (SPENT - IDX_BYTES)`
# mixes a number computed for this cwd with an index belonging to another store,
# so the subtraction was unsound off-cwd and the verdict was correctly withheld.
# The allowance is now `always-on pointers x 150 + 600`, computed entirely from
# the index being measured — it reads nothing about this cwd, this box's
# constitution or any other surface. There is no longer a mismatch to protect
# against, so `--root` gets a real verdict, and the ability to judge the OTHER
# nine stores on this box is the point rather than a by-product. The text above
# is kept whole because it is the record of why the refusal existed; deleting it
# would leave the next reader to rediscover the unsound subtraction. The variable
# it used to set is gone rather than pinned to 1: a flag that cannot be false is a
# branch no test can reach, which is CONSTITUTION §2.10 in a different costume.
# Default beside the always-on index, not inside $STORE: --index may point
# anywhere, and the overflow belongs next to the index it overflows from.
[ -n "$FULL_INDEX" ] || FULL_INDEX="$(dirname "$INDEX")/INDEX-FULL.md"

# NO STORE IS NOT AN ERROR. Most working directories have none, and this tool
# runs from lint and from `harbor`. Exiting 2 here would make the common case
# noisy, which is how a check gets dropped from the caller.
if [ ! -d "$STORE" ]; then
  if [ "$JSON" -eq 1 ]; then
    printf '{"schema_version":1,"root":"%s","present":false}\n' "$STORE"
  else
    printf 'store-check: no store at %s — nothing always-on to bound for this cwd.\n' "${STORE#"$HOME"/}"
  fi
  exit 0
fi

TMP="${TMPDIR:-/tmp}/harbor-store-check.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

# ── the corpus ──────────────────────────────────────────────────────────────
# memory-lint's walk, for the same reasons: dot-directories are history or
# another scope, indexes/ is the derived tier, and -print0 is not portable.
# -L, AND IT IS NOT COSMETIC (harbor#608). CHECKS.md's `memory-route` row
# routes a governed repo's silo to the one $HOME store BY SYMLINK, so $STORE is
# a LINK and not a directory for 25 of this box's 200 silos — harbor's own and
# all three trio repos among them. `find` does not follow a symlinked START
# path without -L, while the index is read straight THROUGH it by path
# traversal. So this walk returned nothing while the index was real, and every
# pointer in it was reported as dangling. Measured 2026-09-21 with cwd ~/harbor:
# `notes 0`, `store bytes 0`, 299 phantom dangles, against a store holding 301
# that `ls` and `stat` both see. `find -L` returns the 301.
find -L "$STORE" -type d \( -name '.*' -o -name node_modules -o -name indexes \) -prune -o \
     -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort > "$TMP/files"

INDEX_REL="${INDEX#"$STORE"/}"
# THE OVERFLOW INDEX IS AN INDEX, NOT A NOTE. It lives inside the store, so the
# walk finds it, and nothing points at an index — it would be reported as an
# orphan on every tiered store. Caught by store-check-test 12a before this
# shipped; without the exclusion, tiering makes the parity check cry wolf on the
# very file that implements it.
FULL_INDEX_REL="${FULL_INDEX#"$STORE"/}"
: > "$TMP/notes"
OLDIFS="$IFS"
IFS='
'
for f in $(cat "$TMP/files"); do
  rel="${f#"$STORE"/}"
  [ "$rel" = "$INDEX_REL" ] && continue
  [ -n "${FULL_INDEX_REL:-}" ] && [ "$rel" = "$FULL_INDEX_REL" ] && continue
  printf '%s\t%s\n' "$(bytes "$f")" "$rel" >> "$TMP/notes"
done
IFS="$OLDIFS"

N_NOTES="$(wc -l < "$TMP/notes" | tr -d ' ')"
STORE_BYTES=0
while IFS='	' read -r b _; do STORE_BYTES=$(( STORE_BYTES + b )); done < "$TMP/notes"
IDX_BYTES="$(bytes "$INDEX")"

# ── AN ABSENT INDEX IS NOT AN INDEX WITHIN ITS ALLOWANCE ────────────────────
# harbor#317. `bytes()` answers 0 for a file that is not there, and 0 is under
# every allowance, so a store directory with no MEMORY.md printed the same
# confident "Index within allowance — N B of headroom" as a healthy one. The
# `! -d "$STORE"` guard above catches a missing DIRECTORY and was doing the work
# this case needed; a directory that exists and holds no index walked straight
# past it. Measured 2026-09-16 on an empty `mkdir`: "9890 B of headroom", exit 0,
# and the same under --strict.
#
# The distinction is not pedantry. "Within allowance" is a claim that something
# was measured and found small; 0 bytes of nothing is the absence of a
# measurement, and reporting it as a pass is the §2 failure this tool exists to
# prevent in the memory store.
INDEX_PRESENT=true
[ -f "$INDEX" ] || INDEX_PRESENT=false

# ── index parity, both directions ───────────────────────────────────────────
# `](target)` is the pointer shape CONSTITUTION.md's memory section specifies:
# `- [Title](file.md) — hook`. Targets carrying a scheme or an anchor are not
# store pointers and are skipped rather than reported — an index may legitimately
# link out, and reporting those as dangling is the false positive that gets the
# parity check ignored.
# A TIERED INDEX IS TWO FILES AND ONE PARITY SET. The always-on index may be
# PARTIAL — it is the file charged to every session, so it is the one bounded by
# bytes — while the overflow index carries the rest and is never loaded, only
# searched. Parity must therefore be computed over the UNION: a note pointed at
# by the overflow index is not an orphan, and reporting it as one is the false
# positive that would make an operator delete a live note (Helm No.2.11).
# Bytes stay measured on $INDEX alone; that asymmetry IS the design.
harvest_pointers() {
  [ -f "$1" ] || return 0
  sed -n 's/.*](\([^)]*\)).*/\1/p' "$1" | LC_ALL=C sort -u > "$TMP/ptr_raw"
  while IFS= read -r t; do
    case "$t" in
      ''|*://*|'#'*) continue ;;
    esac
    # AN INDEX IS NOT A NOTE, in either direction. The two tiers cross-link so a
    # reader can walk between them, and those links target index files that the
    # corpus walk deliberately excludes — so without this they are reported as
    # dangling on every tiered store, which is the same cry-wolf as counting the
    # overflow index as an orphan. Basenames, because a pointer is relative.
    case "${t%%#*}" in
      "$(basename "$INDEX")"|"$(basename "${FULL_INDEX:-/nonexistent}")") continue ;;
    esac
    printf '%s\n' "${t%%#*}" >> "$2"
  done < "$TMP/ptr_raw"
}

: > "$TMP/ptr"
: > "$TMP/ptr_always"
harvest_pointers "$INDEX" "$TMP/ptr"
cp "$TMP/ptr" "$TMP/ptr_always"
FULL_INDEX_PRESENT=false
if [ -n "${FULL_INDEX:-}" ] && [ -f "$FULL_INDEX" ]; then
  FULL_INDEX_PRESENT=true
  harvest_pointers "$FULL_INDEX" "$TMP/ptr"
fi
LC_ALL=C sort -u "$TMP/ptr" > "$TMP/ptrset" 2>/dev/null || : > "$TMP/ptrset"
N_PTR="$(wc -l < "$TMP/ptrset" | tr -d ' ')"
LC_ALL=C sort -u "$TMP/ptr_always" > "$TMP/ptrset_always" 2>/dev/null || : > "$TMP/ptrset_always"
N_PTR_ALWAYS="$(wc -l < "$TMP/ptrset_always" | tr -d ' ')"

cut -f2 "$TMP/notes" | LC_ALL=C sort -u > "$TMP/noteset"
LC_ALL=C comm -23 "$TMP/ptrset"  "$TMP/noteset" > "$TMP/dangling"
LC_ALL=C comm -13 "$TMP/ptrset"  "$TMP/noteset" > "$TMP/orphan"
N_DANGLING="$(wc -l < "$TMP/dangling" | tr -d ' ')"
N_ORPHAN="$(wc -l < "$TMP/orphan" | tr -d ' ')"

# ── the allowance, derived from the index's OWN SHAPE (harbor#316) ──────────
# THIS USED TO BE `ceiling - (spent - index)`, AND THAT FORMULA HAD A FAULT THAT
# ONLY SHOWED WHEN THE OTHER TOOL GOT BETTER. It bound the index to surfaces that
# have nothing to do with the index: the constitution, the ambient skill
# descriptions, and — once #316 taught context-budget.sh to see them — plugin
# agent descriptions, slash-command descriptions and the SessionStart injection.
# Measured 2026-09-20, the hour that landed: the allowance fell from 9,477 B to
# 799 B and this tool began demanding a five-pointer index. Nothing about the
# store had changed. A gate whose verdict moves because a DIFFERENT surface was
# measured more honestly is a gate pointed at the wrong thing, and a permanently
# red one is CONSTITUTION §2.11's false positive, which gets switched off.
#
# THE OLD HEADER'S OBJECTION, ANSWERED RATHER THAN IGNORED. It said a second
# constant "must agree with HARBOR_CONTEXT_CEILING, and copies drift". True of a
# second CEILING; not true of this. 150 B is not a copy of anything — it is the
# cost of ONE ROUTING-TABLE LINE, `- [Title](file.md) — hook`, which is a fact
# about the index's shape and about nothing else in the system. The number is not
# invented here either: CONSTITUTION.md's own arithmetic for the 40,000 B figure
# reads "Allowing 150 B a pointer ... plus ~600 B of section structure". This
# takes that sentence at its word and applies it to the file it was about.
#
# WHAT IT BOUNDS IS PROSE CREEP, WHICH IS THE FAILURE THAT ACTUALLY HAPPENS. An
# index does not get big by gaining pointers — it is tiered, and the overflow
# file is free. It gets big when a pointer grows into a paragraph. Bytes per
# always-on pointer is exactly that quantity, it is indifferent to how many notes
# the box holds, and so it does not rot in either direction.
#
# AND IT SEVERS THE CIRCULARITY. store-check no longer runs context-budget at
# all, so improving one instrument can never again move the other's verdict —
# which is the structural bug this whole comment is about, not a side effect.
# THE 600 IS NOT TUNED TO THIS BOX, DELIBERATELY. Measured 2026-09-20 on the
# $HOME silo: the non-pointer lines come to 840 B, not 600, so the default
# undercounts the structure term by 240 B and 240 B of that store's 3,724 B
# overage is this constant rather than the index. Raising it to 840 would make
# today's measurement pass its own test, which is fitting the bound to the data
# and leaves nothing that could have come out red. The number stays where
# CONSTITUTION.md's arithmetic put it, the discrepancy is recorded here, and the
# knob exists for a box whose index legitimately carries more structure. What the
# overage is actually made of, same measurement: 34 of 52 pointer lines exceed
# 150 B, median 200, longest 576 — so ~94% of it is pointers, not preamble.
BYTES_PER_PTR="${HARBOR_INDEX_BYTES_PER_POINTER:-150}"
IDX_STRUCTURE="${HARBOR_INDEX_STRUCTURE_BYTES:-600}"
ALLOW=$(( N_PTR_ALWAYS * BYTES_PER_PTR + IDX_STRUCTURE ))

# ZERO POINTERS IS NOT A ZERO ALLOWANCE — IT IS A PARSE THAT RETURNED NOTHING.
# An index with bytes and no `](file.md)` line is either genuinely not a routing
# table or a `harvest_pointers` that stopped matching, and this tool cannot tell
# which from here. Reporting a confident OVER built on a possibly-broken extractor
# is the same error as reporting green on an empty store (harbor#317) with the
# sign flipped, and REF-10 already settled the general case for this repo: an
# extractor that returned nothing from a document that plainly cites is a finding,
# never a pass. So the verdict is withheld and the facts are still printed.
BUDGET_OK=1
[ "$INDEX_PRESENT" = true ] && [ "$IDX_BYTES" -gt 0 ] && [ "$N_PTR_ALWAYS" -eq 0 ] && BUDGET_OK=0

# ── age, from mtime ─────────────────────────────────────────────────────────
# BSD and GNU stat take different flags and this box is BSD. `find -mtime` is
# POSIX, takes neither, and answers the only question asked here.
: > "$TMP/stale"
# -L for the same reason as the corpus walk above (harbor#608). Without it a
# symlinked store reports 0 stale notes forever, and zero stale reads as a clean
# bill of health rather than as nothing having been looked at.
find -L "$STORE" -type f -name '*.md' -mtime "+$STALE_DAYS" -print 2>/dev/null \
  | LC_ALL=C sort > "$TMP/stale"
N_STALE="$(wc -l < "$TMP/stale" | tr -d ' ')"

# ── verdict ─────────────────────────────────────────────────────────────────
# A SIZE VERDICT NEEDS ALL THREE, NOT JUST THE NUMBERS (harbor#317). The
# allowance must have been derived, the basis must belong to the store being
# measured, and there must BE an index to measure. Any one missing and the facts
# are still printed while the verdict is withheld — never substituted.
VERDICT_OK=0
[ "$BUDGET_OK" -eq 1 ] && [ "$INDEX_PRESENT" = true ] && VERDICT_OK=1

OVER=0
[ "$VERDICT_OK" -eq 1 ] && [ "$IDX_BYTES" -gt "$ALLOW" ] && OVER=1
FAIL=0
[ "$STRICT" -eq 1 ] && { [ "$OVER" -eq 1 ] || [ "$N_DANGLING" -gt 0 ] || [ "$N_ORPHAN" -gt 0 ]; } && FAIL=1

if [ "$JSON" -eq 1 ]; then
  # SCHEMA 2 (harbor#316): `ceiling` and `spent` are gone because the allowance no
  # longer comes from them, and `basis_applies` is gone because it can no longer
  # be false — a key that is always true is a field a reader learns to skip.
  # `bytes_per_pointer` and `structure_bytes` replace them, so a consumer can
  # re-derive the allowance from the same row rather than trusting it.
  printf '{"schema_version":2,"root":"%s","present":true,"notes":%s,"store_bytes":%s,' \
    "$STORE" "$N_NOTES" "$STORE_BYTES"
  # `present` and `basis_applies` are additive (harbor#317). A consumer that
  # reads only `over` must not be able to mistake "nothing measured" for "fine",
  # which is why `allowance` and `over` are emitted ONLY with a real verdict --
  # an absent key is a question a reader has to notice, a `false` is not.
  printf '"index":{"path":"%s","present":%s,"bytes":%s,"pointers":%s,"pointers_always_on":%s,"allowance_derived":%s,"verdict":%s' \
    "$INDEX" "$INDEX_PRESENT" "$IDX_BYTES" "$N_PTR" "$N_PTR_ALWAYS" \
    "$( [ "$BUDGET_OK" -eq 1 ] && echo true || echo false )" \
    "$( [ "$VERDICT_OK" -eq 1 ] && echo true || echo false )"
  [ "$VERDICT_OK" -eq 1 ] && printf ',"allowance":%s,"bytes_per_pointer":%s,"structure_bytes":%s,"over":%s' \
    "$ALLOW" "$BYTES_PER_PTR" "$IDX_STRUCTURE" "$( [ "$OVER" -eq 1 ] && echo true || echo false )"
  printf '},"full_index":{"path":"%s","present":%s,"tiered":%s}' \
    "$FULL_INDEX" "$FULL_INDEX_PRESENT" \
    "$( [ "$N_PTR" -gt "$N_PTR_ALWAYS" ] && echo true || echo false )"
  printf ',"dangling":['
  _f=1; while IFS= read -r p; do [ "$_f" -eq 1 ] || printf ','; _f=0; printf '"%s"' "$p"; done < "$TMP/dangling"
  printf '],"orphans":['
  _f=1; while IFS= read -r p; do [ "$_f" -eq 1 ] || printf ','; _f=0; printf '"%s"' "$p"; done < "$TMP/orphan"
  printf '],"stale_days":%s,"stale":%s}\n' "$STALE_DAYS" "$N_STALE"
  exit "$FAIL"
fi

printf 'store-check — %s\n\n' "${STORE#"$HOME"/}"
printf '  %-34s %10s\n' "notes" "$N_NOTES"
printf '  %-34s %10s\n' "store bytes (recall corpus)" "$STORE_BYTES"
printf '  %-34s %10s  %s\n' "index bytes (ALWAYS ON)" "$IDX_BYTES" "$N_PTR pointer(s)"

if [ "$VERDICT_OK" -eq 1 ]; then
  printf '  %-34s %10s  = %s always-on pointer(s) x %s + %s structure\n' \
    "index allowance (derived)" "$ALLOW" "$N_PTR_ALWAYS" "$BYTES_PER_PTR" "$IDX_STRUCTURE"
  # GUARDED, BECAUSE AN INDEX FILE CAN EXIST AND BE EMPTY. 0 bytes and 0 pointers
  # passes BUDGET_OK (there is no parse to doubt) and would divide by zero here.
  [ "$N_PTR_ALWAYS" -gt 0 ] && printf '  %-34s %10s  against the %s B shape one pointer is allowed\n' \
    "bytes per always-on pointer" "$(( (IDX_BYTES - IDX_STRUCTURE) / N_PTR_ALWAYS ))" "$BYTES_PER_PTR"
elif [ "$BUDGET_OK" -eq 0 ]; then
  printf '  %-34s %10s  %s B of index, and no pointer parsed out of it\n' \
    "index allowance" "NOT DERIVED" "$IDX_BYTES"
else
  printf '  %-34s %10s  there is no index here to bound\n' \
    "index allowance" "NO INDEX"
fi
printf '\n'

if [ "$N_DANGLING" -gt 0 ]; then
  printf 'DANGLING — the index points at %s note(s) that are not there:\n' "$N_DANGLING"
  sed 's/^/    /' "$TMP/dangling"
  printf '\n'
fi
if [ "$N_ORPHAN" -gt 0 ]; then
  printf 'ORPHAN — %s note(s) no index line names, so nothing will recall them:\n' "$N_ORPHAN"
  sed 's/^/    /' "$TMP/orphan"
  printf '\n'
fi

if [ "$TOP" -gt 0 ] && [ "$N_NOTES" -gt 0 ]; then
  printf 'largest %s note(s) — the cost of a recall, not of a session:\n' "$TOP"
  LC_ALL=C sort -rn "$TMP/notes" | head -n "$TOP" | while IFS='	' read -r b p; do
    printf '  %8s  %s\n' "$b" "$p"
  done
  printf '\n'
fi

if [ "$N_STALE" -gt 0 ]; then
  printf '%s note(s) untouched in %s+ days — REPORT ONLY, age is not a defect.\n' "$N_STALE" "$STALE_DAYS"
  printf '  (mtime, not git: this store is not a repo, and a copy or restore resets it.)\n\n'
fi

printf 'Link rot is not measured here — run: sh bin/memory-lint.sh --root %s\n\n' "${STORE#"$HOME"/}"

if [ "$BUDGET_OK" -eq 1 ] && [ "$OVER" -eq 1 ]; then
  printf 'OVER — the index is %s B against an allowance of %s B.\n' "$IDX_BYTES" "$ALLOW"
  printf 'Every byte of it is spent before your first word, in every session.\n'
  if [ "$FULL_INDEX_PRESENT" = true ]; then
    printf 'The index is TIERED (%s of %s pointers always-on); move more of them to\n' \
      "$N_PTR_ALWAYS" "$N_PTR"
    printf '%s, which is searched and never loaded.\n' "${FULL_INDEX#"$HOME"/}"
  else
    printf 'Trim the pointers, not the notes — a pointer here averages %s B against\n' \
      "$(( (IDX_BYTES - IDX_STRUCTURE) / N_PTR_ALWAYS ))"
    printf 'the %s B a routing-table line is allowed. A TIERED index is the other\n' "$BYTES_PER_PTR"
    printf 'option: keep the always-on pointers here, move the rest to %s.\n' "${FULL_INDEX#"$HOME"/}"
    printf 'MOVING A POINTER IS ONLY SAFE IF SEARCH IS STATED — see CONSTITUTION.md.\n'
  fi
elif [ "$VERDICT_OK" -eq 1 ]; then
  printf 'Index within allowance — %s B of headroom.\n' "$(( ALLOW - IDX_BYTES ))"
elif [ "$BUDGET_OK" -eq 0 ]; then
  printf 'NO VERDICT on size: the index holds %s B and no `](file.md)` pointer was\n' "$IDX_BYTES"
  printf 'parsed out of it. That is either an index that is not a routing table or an\n'
  printf 'extractor that stopped matching, and this tool cannot tell which — so it\n'
  printf 'reports neither. The counts above are still real.\n'
else
  printf 'NO VERDICT on size: there is no index at %s.\n' "${INDEX#"$HOME"/}"
  printf 'An absent index is not an index within its allowance — 0 bytes is under\n'
  printf 'every ceiling, and reporting that as a pass is a measurement nobody took.\n'
fi

exit "$FAIL"
