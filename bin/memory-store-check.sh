#!/usr/bin/env sh
# store-check (CX1, harbor#150 Phase 5 · harbor#183/#184) — bound the memory
# store. SIZE and AGE, which is the half nothing measured.
#
# Why (CX1): bin/memory-lint.sh is the anti-rot gate (dangling wikilinks, dead paths, slug collisions) and has no size dimension, while the always-on index is charged in full to every session and grows by one line per memory. This bounds it.
# The allowance is the index's own shape (harbor#316): always-on pointers x 150 B + 600 B of section structure, the arithmetic of policy/constitution.md applied to the file it was about. It used to be `ceiling - (spent - index)` from context-budget.sh; when #316 taught that tool to count more surfaces the allowance fell from 9,477 B to 799 B with nothing changed in the store (§2.11), so this tool no longer reads the other. 150 B is the cost of one routing-table line, not a copy of any ceiling.
# When the allowance cannot be derived there is no verdict: an index with bytes and no parsed pointer is either not a routing table or an extractor that stopped matching, and a bound nobody chose gets a check switched off (§2.11, §2.7).
# The subject is the cwd-keyed auto-memory store (the one the harness loads: the cwd with `/` -> `-`, no walk-up), resolved here as context-budget.sh does on purpose, since asking it would make this report depend on a tool whose failure mode is printing no rows.
# Index parity reads the `](file.md)` pointers both ways (memory-lint reads [[wikilinks]] between notes): dangling = the index names a missing note; orphan = a note no index line names, invisible at recall.
# Age is report-only, always (a gate on age teaches touching files). It comes from mtime because the store is not a git repo, which is weaker evidence (a copy or restore resets it) and is disclosed in the output.
# Removed notes: docs/explanation/code-cases/bin-memory-store-check.md
set -eu

# Noglob, as memory-lint: a note filename holding * ? or [ ] would be pathname-expanded in the unquoted lists below.
set -f

# harbor#813: its own dir by ${0%/*}, never a dirname fork. stdout is the report or its JSON, so a
# log goes to stderr; usage errors stay plain exits 2 (contracts/logging.md).
case "$0" in */*) _sc_dir="${0%/*}" ;; *) _sc_dir=. ;; esac
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$_sc_dir/library-log.sh"
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

  memory-store-check.sh [--root DIR] [--index FILE] [--full-index FILE]
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
    # Validated, not left to the arithmetic: under dash a non-numeric operand aborts the interpreter, so a typo would kill the gate instead of giving a usage error (as memory-lint).
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

# The allowance basis (harbor#317, lifted by harbor#316). The old formula `CEIL - (SPENT - IDX_BYTES)` mixed a number computed for this cwd with an index from another store, so `--root` elsewhere gave the opposite verdict to context-budget.sh ("9890 B of headroom" against "OVER by 589") and the verdict was withheld. The allowance now reads only the index being measured, so `--root` gets a real verdict and the refusal flag is gone (a flag that cannot be false is a branch no test reaches, §2.10).
# Default beside the always-on index, not inside $STORE: --index may point
# anywhere, and the overflow belongs next to the index it overflows from.
[ -n "$FULL_INDEX" ] || FULL_INDEX="$(dirname "$INDEX")/INDEX-FULL.md"

# No store is not an error: most working directories have none, and exiting 2 would make the common case noisy.
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
# memory-lint's walk (dot-directories are history, indexes/ is the derived tier). `find -L` is not cosmetic (harbor#608): memory.route links a governed repo's silo to the one $HOME store by symlink, and find does not follow a symlinked START path without -L, so the index was real while the walk returned nothing and every pointer read as dangling.
find -L "$STORE" -type d \( -name '.*' -o -name node_modules -o -name indexes \) -prune -o \
     -type f -name '*.md' -print 2>/dev/null | LC_ALL=C sort > "$TMP/files"

INDEX_REL="${INDEX#"$STORE"/}"
# The overflow index is an index, not a note: it lives in the store and nothing points at it, so it would be an orphan on every tiered store (store-check-test 12a).
FULL_INDEX_REL="${FULL_INDEX#"$STORE"/}"
: > "$TMP/notes"
OLDIFS="$IFS"
IFS='
'
# Every size from ONE wc, not two forks per note (harbor#559: ~1,000 at session start). A file wc cannot read
# is 0, as bytes() answers. If wc itself cannot run (an argument list too long), each note is sized alone.
set -- $(cat "$TMP/files")   # noglob is on for the whole script (above)
if [ $# -gt 0 ] && wc -c -- "$@" > "$TMP/sizes" 2>/dev/null || [ -s "$TMP/sizes" ]; then
  awk -v store="$STORE/" -v idx="$INDEX_REL" -v full="${FULL_INDEX_REL:-}" '
    NR == FNR { n = $1; sub(/^ *[0-9]+ /, ""); sz[$0] = n; next }
    { rel = $0; if (index(rel, store) == 1) rel = substr(rel, length(store) + 1)
      if (rel == idx || (full != "" && rel == full)) next
      printf "%s\t%s\n", (($0 in sz) ? sz[$0] : 0), rel }' "$TMP/sizes" "$TMP/files" > "$TMP/notes"
else
  for f in "$@"; do
    rel="${f#"$STORE"/}"
    [ "$rel" = "$INDEX_REL" ] && continue
    [ -n "${FULL_INDEX_REL:-}" ] && [ "$rel" = "$FULL_INDEX_REL" ] && continue
    printf '%s\t%s\n' "$(bytes "$f")" "$rel" >> "$TMP/notes"
  done
fi
IFS="$OLDIFS"

N_NOTES="$(wc -l < "$TMP/notes" | tr -d ' ')"
STORE_BYTES=0
while IFS='	' read -r b _; do STORE_BYTES=$(( STORE_BYTES + b )); done < "$TMP/notes"
IDX_BYTES="$(bytes "$INDEX")"

# ── AN ABSENT INDEX IS NOT AN INDEX WITHIN ITS ALLOWANCE ────────────────────
# harbor#317: `bytes()` answers 0 for a missing file and 0 is under every allowance, so a store with no MEMORY.md printed "Index within allowance". 0 bytes of nothing is the absence of a measurement, not a pass.
INDEX_PRESENT=true
[ -f "$INDEX" ] || INDEX_PRESENT=false

# ── index parity, both directions ───────────────────────────────────────────
# `](target)` is the pointer shape of policy/constitution.md's memory section. Targets with a scheme or anchor are skipped (an index may link out; reporting those dangling gets the check ignored).
# A tiered index is two files and one parity set: the always-on index may be partial and is the one bounded by bytes; the overflow index is never loaded, only searched. Parity is over the UNION, or a note named only by the overflow index reads as an orphan and an operator deletes a live note (§2.11). Bytes stay on $INDEX alone.
harvest_pointers() {
  [ -f "$1" ] || return 0
  # Once, not two forks per pointer (harbor#559: ~1,000 basename forks at session start).
  _hp_idx="$(basename "$INDEX")"; _hp_full="$(basename "${FULL_INDEX:-/nonexistent}")"
  sed -n 's/.*](\([^)]*\)).*/\1/p' "$1" | LC_ALL=C sort -u > "$TMP/ptr_raw"
  while IFS= read -r t; do
    case "$t" in
      ''|*://*|'#'*) continue ;;
    esac
    # An index is not a note, in either direction: the tiers cross-link and the corpus walk excludes index files, so without this those links read as dangling. Basenames, because a pointer is relative.
    case "${t%%#*}" in
      "$_hp_idx"|"$_hp_full") continue ;;
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
# Why this shape (harbor#316): the old `ceiling - (spent - index)` bound the index to surfaces unrelated to it, and a gate whose verdict moves because a DIFFERENT surface was measured more honestly is pointed at the wrong thing (§2.11). 150 B per pointer is one routing-table line; the 600 is policy/constitution.md's own "~600 B of section structure". It bounds prose creep, the failure that actually happens (a pointer growing into a paragraph; the overflow file is free), and it severs the circularity with context-budget.sh.
# The 600 is not tuned to this box, on purpose: the $HOME silo's non-pointer lines measured 840 B (2026-09-20), and raising the default to 840 would fit the bound to the data and leave nothing that could come out red. The knob (HARBOR_MEMORY_INDEX_STRUCTURE_BYTES) is for a box whose index legitimately carries more structure.
BYTES_PER_PTR="${HARBOR_MEMORY_INDEX_BYTES_PER_POINTER:-150}"
IDX_STRUCTURE="${HARBOR_MEMORY_INDEX_STRUCTURE_BYTES:-600}"
ALLOW=$(( N_PTR_ALWAYS * BYTES_PER_PTR + IDX_STRUCTURE ))

# Zero pointers is not a zero allowance, it is a parse that returned nothing: a confident OVER built on a possibly-broken extractor is harbor#317's green-on-empty with the sign flipped (REF-10 settled the general case). The verdict is withheld and the facts still print.
BUDGET_OK=1
[ "$INDEX_PRESENT" = true ] && [ "$IDX_BYTES" -gt 0 ] && [ "$N_PTR_ALWAYS" -eq 0 ] && BUDGET_OK=0

# ── age, from mtime ─────────────────────────────────────────────────────────
# BSD and GNU stat take different flags; `find -mtime` is POSIX and answers the only question asked.
: > "$TMP/stale"
# -L as in the corpus walk (harbor#608): otherwise a symlinked store reports 0 stale forever.
find -L "$STORE" -type f -name '*.md' -mtime "+$STALE_DAYS" -print 2>/dev/null \
  | LC_ALL=C sort > "$TMP/stale"
N_STALE="$(wc -l < "$TMP/stale" | tr -d ' ')"

# ── verdict ─────────────────────────────────────────────────────────────────
# A size verdict needs a derived allowance and an index to measure; otherwise the facts print and the verdict is withheld, never substituted (harbor#317).
VERDICT_OK=0
[ "$BUDGET_OK" -eq 1 ] && [ "$INDEX_PRESENT" = true ] && VERDICT_OK=1

OVER=0
[ "$VERDICT_OK" -eq 1 ] && [ "$IDX_BYTES" -gt "$ALLOW" ] && OVER=1
FAIL=0
[ "$STRICT" -eq 1 ] && { [ "$OVER" -eq 1 ] || [ "$N_DANGLING" -gt 0 ] || [ "$N_ORPHAN" -gt 0 ]; } && FAIL=1

if [ "$JSON" -eq 1 ]; then
  # SCHEMA 2 (harbor#316): `ceiling`, `spent` and `basis_applies` are gone; `bytes_per_pointer` and `structure_bytes` let a consumer re-derive the allowance from the same row.
  printf '{"schema_version":2,"root":"%s","present":true,"notes":%s,"store_bytes":%s,' \
    "$STORE" "$N_NOTES" "$STORE_BYTES"
  # `allowance` and `over` are emitted ONLY with a real verdict (harbor#317): an absent key is a question a reader has to notice, a `false` is not.
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
  # Guarded: an existing empty index passes BUDGET_OK and would divide by zero.
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
    printf 'MOVING A POINTER IS ONLY SAFE IF SEARCH IS STATED — see policy/constitution.md.\n'
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
