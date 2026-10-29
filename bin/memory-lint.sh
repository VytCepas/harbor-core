#!/usr/bin/env sh
# memory-lint (harbor#6 — workstream D, D2) — the deterministic anti-rot gate
# over a memory store. No LLM, no Bun, no network: every finding is a fact about
# the files, reproducible by anyone with awk and git.
#
# FOUR CHECKS, and they are not the same kind of thing:
#
#   dangling    a note links to a slug no note carries. HARD under --strict:
#               the link is wrong now, and it will not fix itself.
#   dead-path   a note cites ](./relative) that does not resolve. HARD too.
#   collision   two notes share a slug, so every link to it is ambiguous and
#               whichever one a reader gets is filesystem order. HARD.
#   stale       a note has not been touched in a long time. REPORT-ONLY, always
#               — age is not a defect. A note written once and correct forever
#               is the GOAL, and a gate that fails on it would teach the
#               operator to touch files to silence a linter, which is how a
#               store fills with meaningless commits. policy/constitution.md §2.11: a
#               false positive is a defect, not safety.
#
# WHY THIS IS SH AND NOT PART OF THE ENGINE. It has to run where the engine
# cannot: CI preflights a fixed binary list that does not include bun, and D2 is
# a gate. That means the dangling-reference definition now exists in two
# languages, which is a drift risk and is handled the way policy/constitution.md's
# cross-repo-seam row says to handle it — a shared fixture both sides run.
# fixtures/memory/expected.json pins the answer; tests/memory/memory/memory.test.sh asserts THIS
# script and tools/memory/graph.ts each reproduce it, so the two cannot drift
# apart without a test going red.
set -u

# NOGLOB. Every list here is split by setting IFS and expanding unquoted, which
# governs FIELD splitting only — pathname expansion still applies to the same
# word. A note filename or a [[link target]] containing *, ? or [ ] would be
# expanded against the working directory before it was ever compared to a slug,
# so a store could report dangling references that depend on where the lint was
# run from. Nothing here needs globbing.
set -f

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# The default is the notes store, as bin/memory.sh resolves it (harbor#1010): projects/<home-key>/memory, else the old MEMORY tree.
STORE="${HARBOR_MEMORY_ROOT:-}"
if [ -z "$STORE" ]; then
  _hk="$(CDPATH='' cd -- "$HOME" 2>/dev/null && pwd -P | sed 's|/|-|g')"
  if [ -n "$_hk" ] && [ -d "$CFG/projects/$_hk/memory" ]; then STORE="$CFG/projects/$_hk/memory"; else STORE="$CFG/MEMORY"; fi
fi
STRICT=0
STRICT_NAMES=0
NAMES=0
JSON=0
STALE_DAYS=365

# Status lines are log-lib's, on stderr: stdout is the findings (or the JSON) and only that (contracts/logging.md).
_here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$_here/library-log.sh"
log_init memory-lint; LOG_FD=2

# die <what failed> <fix command>: FAIL, its fix, the summary, exit 2 (a usage error is not a run).
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 2; }

usage() {
  cat <<'USAGE'
memory-lint (harbor#6) — deterministic anti-rot over a memory store

  memory-lint.sh [--root DIR] [--strict] [--json] [--stale-days N]

  --strict       exit 1 when a dangling reference, dead path or slug collision
                 is found. Staleness never fails, in any mode.
  --json         machine-readable report
  --stale-days N staleness threshold in days (default 365, report-only)
  --names        also judge note and folder names (below), report-only
  --strict-names implies --names, and also exit 1 on a name finding. Names are report-only without it, because the live store predates
                 D-24 and a gate that is red on day one gets switched off (CONSTITUTION No.2.11)

  NAME checks (harbor#1010, D-24, D-34): NAME-CLAIM a note whose file name is not lowercase kebab `<subject>-<claim>`
  (two words at least; MEMORY.md, INDEX-FULL.md and README.md are the store's own); NAME-STEM a note whose front
  matter `name:` differs from its file stem; NAME-DIR a subfolder that is not lowercase kebab; NAME-HOST a path
  segment that is a raw machine name (hostname -s, or HARBOR_HOST_NAMES, space separated) and not the lowercase alias.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)       [ "$#" -ge 2 ] || die "--root needs a directory" "sh bin/memory-lint.sh --help"
                  STORE="$2"; shift 2 ;;
    --root=*)     STORE="${1#--root=}"; shift ;;
    --stale-days) [ "$#" -ge 2 ] || die "--stale-days needs a number" "sh bin/memory-lint.sh --help"
                  # VALIDATED HERE, not left to the arithmetic below. Under dash
                  # — the canonical /bin/sh this file is written for — a non-
                  # numeric operand makes $((…)) abort the interpreter with
                  # "Illegal number", so a typo killed the gate instead of
                  # printing a usage error.
                  case "$2" in ''|*[!0-9]*) die "--stale-days expects a non-negative integer, got $2" "sh bin/memory-lint.sh --stale-days 365" ;; esac
                  STALE_DAYS="$2"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    --names)      NAMES=1; shift ;;
    --strict-names) STRICT_NAMES=1; NAMES=1; shift ;;
    --json)       JSON=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage >&2; die "unknown argument $1" "sh bin/memory-lint.sh --help" ;;
  esac
done

[ -d "$STORE" ] || die "no store at $STORE" "sh bin/memory-lint.sh --root <the memory store directory>"

TMP="${TMPDIR:-/tmp}/harbor-memory-lint.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# The same scope the engine walks (tools/memory/store.ts): dot-directories are
# either history (.git) or another scope (.agents — an L3 repo store), and
# indexes/ is the derived tier. -print0 is not portable, so the file list is
# newline-delimited and every consumer sets IFS accordingly; a note filename
# containing a space is in the fixture corpus precisely to keep that honest.
# -L, AND IT IS NOT COSMETIC (harbor#608). docs/reference/checks.md's `memory-route` row
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

# slug<TAB>relpath for every note, in a stable order.
: > "$TMP/slugs"
OLDIFS="$IFS"
IFS='
'
for f in $(cat "$TMP/files"); do
  b="${f##*/}"
  printf '%s\t%s\n' "${b%.md}" "${f#"$STORE"/}" >> "$TMP/slugs"
done
IFS="$OLDIFS"
cut -f1 "$TMP/slugs" | LC_ALL=C sort -u > "$TMP/slugset"

# ── link extraction ─────────────────────────────────────────────────────────
# One awk pass per file emitting `line<TAB>dialect<TAB>target`. awk is on CI's
# preflight list; a sed/grep pipeline could not track frontmatter state, and the
# `related:` block is exactly where state is needed — the same key name means a
# list, a scalar or a block of objects depending on what follows it.
extract_links() { # <file>
  # AN UNCLOSED FRONTMATTER BLOCK IS NOT FRONTMATTER. A note that opens with
  # `---` and never closes it is a typo, and the two readers disagreed about it:
  # tools/memory/store.ts falls back to "no frontmatter, all body" (it searches
  # for the closing fence and gives up if there is none), while this awk had no
  # such lookahead — `infm` never reset, so the ENTIRE file was parsed as
  # frontmatter and ordinary body prose under a `related:` line became fabricated
  # dangling references, failing --strict on a missing dash.
  #
  # Two implementations of one definition may not disagree; that is the whole
  # reason expected.json is the arbiter. So the closing fence is established
  # first, in its own pass, and passed in.
  _fm_closed="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {print 1; exit}' "$1")"
  awk -v fmclosed="${_fm_closed:-0}" '
    function emit(line, dialect, target) {
      gsub(/^[ \t]+|[ \t]+$/, "", target)
      if (target != "") printf "%d\t%s\t%s\n", line, dialect, target
    }
    NR == 1 && $0 == "---" && fmclosed == 1 { infm = 1; next }
    infm && $0 == "---"    { infm = 0; inrel = 0; next }
    infm {
      if ($0 ~ /^related:[ \t]*\[/) {
        s = $0; sub(/^related:[ \t]*\[/, "", s); sub(/\].*$/, "", s)
        n = split(s, parts, ",")
        for (i = 1; i <= n; i++) { gsub(/["'"'"']/, "", parts[i]); emit(NR, "frontmatter", parts[i]) }
        inrel = 0; next
      }
      if ($0 ~ /^related:[ \t]*$/) { inrel = 1; next }
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) { inrel = 0 }
      if (inrel) {
        # `- slug: x`, `  slug: x`, or a bare `- x`. Any other key inside an
        # object item (type:, note:) is deliberately ignored, not guessed at.
        if ($0 ~ /^[ \t]*-?[ \t]*slug:/) { s = $0; sub(/^[ \t]*-?[ \t]*slug:[ \t]*/, "", s); gsub(/["'"'"']/, "", s); emit(NR, "frontmatter", s) }
        else if ($0 ~ /^[ \t]*-[ \t]*[^ \t]/) {
          s = $0; sub(/^[ \t]*-[ \t]*/, "", s)
          if (s !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) { gsub(/["'"'"']/, "", s); emit(NR, "frontmatter", s) }
        }
      }
    }
    # CODE IS NOT PROSE, and this must agree with tools/memory/store.ts line for
    # line — the two readers are held to one pinned answer. `[[ $? == 1 ]]` is a
    # shell test; without this a note documenting a bash fix reports two dangling
    # wikilinks, which is what the real store did.
    /^[ \t]*(```|~~~)/ { infence = !infence; next }
    infence { next }
    {
      s = $0
      gsub(/`[^`]*`/, "", s)      # inline spans: the real case was in backticks
      while (match(s, /\[\[[^]]+\]\]/)) {
        t = substr(s, RSTART + 2, RLENGTH - 4)
        sub(/\|.*$/, "", t)
        emit(NR, "wikilink", t)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# Normalised exactly as tools/memory/graph.ts normalizeTarget() does: strip an
# anchor, a .md suffix and any directory prefix, then lowercase. Two readers
# that disagree about what a link POINTS AT disagree about everything after.
normalize() { # <target>
  printf '%s' "$1" \
    | sed -e 's/#.*$//' -e 's/\.md$//' -e 's#.*/##' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

: > "$TMP/dangling"
: > "$TMP/deadpath"

OLDIFS="$IFS"
IFS='
'
for f in $(cat "$TMP/files"); do
  rel="${f#"$STORE"/}"
  for row in $(extract_links "$f"); do
    ln="${row%%	*}"
    rest="${row#*	}"
    dialect="${rest%%	*}"
    target="${rest#*	}"
    norm="$(normalize "$target")"
    [ -n "$norm" ] || continue
    if ! LC_ALL=C grep -qxF -- "$norm" "$TMP/slugset"; then
      printf '%s\t%s\t%s\t%s\n' "$rel" "$ln" "$dialect" "$target" >> "$TMP/dangling"
    fi
  done
  # Relative path citations: ](./x) and ](../x), resolved against the CITING
  # file's directory, never the store root — the mistake lint rule T3 made on
  # its first run, which fired on six correct links.
  d="$(dirname "$f")"
  for row in $(grep -noE '\]\(\.\.?/[^)#[:space:]]*' "$f" 2>/dev/null || true); do
    ln="${row%%:*}"
    p="${row#*:}"
    p="${p#](}"
    [ -n "$p" ] || continue
    [ -e "$d/$p" ] || printf '%s\t%s\t%s\n' "$rel" "$ln" "$p" >> "$TMP/deadpath"
  done
done
IFS="$OLDIFS"

# ── collisions ──────────────────────────────────────────────────────────────
cut -f1 "$TMP/slugs" | LC_ALL=C sort | uniq -d > "$TMP/dupslugs"

count() { [ -s "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

# ── names (harbor#1010 PR 4; D-24 claim-style, D-34 host alias) ─────────────
# Pure functions of the path and the front matter: nothing here reads a clock or git. A finding is
# `kind<TAB>path<TAB>why`. Report-only unless --strict-names (see usage).
: > "$TMP/names"
HOSTS="${HARBOR_HOST_NAMES:-$(hostname -s 2>/dev/null || true)}"
is_kebab() { case "$1" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*|-*|*-|*--*) return 1 ;; *) return 0 ;; esac; }
OLDIFS="$IFS"
IFS='
'
for f in $( [ "$NAMES" -eq 1 ] && cat "$TMP/files" ); do
  rel="${f#"$STORE"/}"; stem="${rel##*/}"; stem="${stem%.md}"
  # NAME-DIR and NAME-HOST read every directory segment of the path.
  _d="${rel%/*}"; [ "$_d" = "$rel" ] && _d=""
  IFS=/
  for seg in $_d; do
    is_kebab "$seg" || printf 'NAME-DIR\t%s\tsubfolder "%s" is not lowercase kebab\n' "$rel" "$seg" >> "$TMP/names"
  done
  IFS='
'
  for seg in $_d "$stem"; do
    for h in $HOSTS; do
      [ "$(printf '%s' "$seg" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')" ] || continue
      [ "$seg" != "$h" ] || printf 'NAME-HOST\t%s\t"%s" is a raw machine name; use the lowercase host alias\n' "$rel" "$seg" >> "$TMP/names"
    done
  done
  case "$stem" in MEMORY|INDEX-FULL|README) continue ;; esac
  if ! is_kebab "$stem"; then
    printf 'NAME-CLAIM\t%s\tfile name is not lowercase kebab <subject>-<claim>\n' "$rel" >> "$TMP/names"
  else
    case "$stem" in *-*) ;; *) printf 'NAME-CLAIM\t%s\tone word is a subject with no claim\n' "$rel" >> "$TMP/names" ;; esac
  fi
  _nm="$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f && /^name:/ {sub(/^name:[ \t]*/, ""); gsub(/["'"'"']/, ""); print; exit}' "$f")"
  [ -z "$_nm" ] || [ "$_nm" = "$stem" ] || printf 'NAME-STEM\t%s\tfront matter name "%s" differs from the file stem\n' "$rel" "$_nm" >> "$TMP/names"
done
IFS="$OLDIFS"
N_NAMES="$(count "$TMP/names")"

# ── staleness (report-only, git-derived) ────────────────────────────────────
# git log, not mtime: a fresh clone rewrites every mtime, so an mtime-based age
# would call an entire store stale the day it is checked out. A store that is
# not a git repo simply has no age, which is reported as such rather than
# guessed at.
: > "$TMP/stale"
if git -C "$STORE" rev-parse --git-dir >/dev/null 2>&1; then
  NOW="$(date +%s)"
  CUTOFF=$((NOW - STALE_DAYS * 86400))
  # ONE `git log` PER NOTE, AND IT IS SLOW ON PURPOSE — 24 s on the live L0 store
  # (308 notes, 1567 commits). harbor#216 replaced this with a single
  # `--name-only` pass at 113 ms and the replacement was WRONG IN FOUR WAYS, all
  # reproduced, all silent, all reporting success. Reverted; the speed is not
  # worth a gate that lies. Every one of the four is now an assertion in
  # tests/memory/memory/memory.test.sh, so a future fast path has to earn its way past them:
  #
  #  1 NESTED STORE. `git log --name-only` emits paths relative to the REPO ROOT,
  #    not to the store. On this repo`s own fixtures/memory/corpus the join
  #    matched nothing and 17 stale notes reported as 0. `git log -1 -- "$rel"`
  #    resolves the pathspec against `-C "$STORE"`, so this loop is correct for a
  #    store at any depth. A fast path needs `--relative -- .`.
  #  2 core.quotePath. git C-quotes a non-ASCII name in --name-only output
  #    ("caf\303\251.md"), which can never equal the raw path from `find`, so
  #    every such note vanished from the report. A bare space does NOT trigger it,
  #    which is why the fixture corpus`s `spaced name.md` was no control at all.
  #    A fast path needs `-c core.quotePath=false`.
  #  3 A FILENAME THAT LOOKS LIKE THE HEADER. The one-pass parser marked a
  #    commit by a `C<digits>` prefix; a tracked file literally named
  #    `C1700000000` is indistinguishable from it and re-dates every path after
  #    it. Any interleaved format has this hazard, because a git path can be
  #    almost any byte string.
  #  4 MERGE COMMITS DIVERGE IN BOTH DIRECTIONS. The replacement`s own comment
  #    claimed it "can only UNDER-report" and that was false: --name-only prints
  #    nothing for a merge, so a note whose newest touch is a conflict resolution
  #    reads OLDER than it is (over-report), while a merge pruned by history
  #    simplification makes it read NEWER (under-report). `git log -1 -- <path>`
  #    applies the same simplification the operator sees.
  #
  # STILL git log AND NOT mtime: a fresh clone rewrites every mtime, so an
  # mtime age would call an entire store stale the day it is checked out.
  OLDIFS="$IFS"
  IFS='
'
  for f in $(cat "$TMP/files"); do
    rel="${f#"$STORE"/}"
    ts="$(git -C "$STORE" log -1 --format=%ct -- "$rel" 2>/dev/null || true)"
    [ -n "$ts" ] || continue
    [ "$ts" -lt "$CUTOFF" ] 2>/dev/null && printf '%s\t%s\n' "$rel" "$(( (NOW - ts) / 86400 ))" >> "$TMP/stale"
  done
  IFS="$OLDIFS"
  GIT_BACKED=true
else
  GIT_BACKED=false
fi

count() { [ -s "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
N_DANGLING="$(count "$TMP/dangling")"
N_DEADPATH="$(count "$TMP/deadpath")"
N_DUP="$(count "$TMP/dupslugs")"
N_STALE="$(count "$TMP/stale")"
N_NOTES="$(count "$TMP/files")"

if [ "$JSON" -eq 1 ]; then
  printf '{"schema_version":1,"root":"%s","notes":%s,"git_backed":%s,"stale_days":%s,' \
    "$STORE" "$N_NOTES" "$GIT_BACKED" "$STALE_DAYS"
  printf '"dangling":['
  _f=1
  while IFS='	' read -r rel ln dialect target; do
    [ "$_f" -eq 1 ] || printf ','
    _f=0
    printf '{"path":"%s","line":%s,"dialect":"%s","target":"%s"}' "$rel" "$ln" "$dialect" "$target"
  done < "$TMP/dangling"
  printf '],"dead_paths":['
  _f=1
  while IFS='	' read -r rel ln p; do
    [ "$_f" -eq 1 ] || printf ','
    _f=0
    printf '{"path":"%s","line":%s,"cites":"%s"}' "$rel" "$ln" "$p"
  done < "$TMP/deadpath"
  printf '],"collisions":['
  _f=1
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ "$_f" -eq 1 ] || printf ','
    _f=0
    printf '"%s"' "$s"
  done < "$TMP/dupslugs"
  printf '],"stale":%s,"name_findings":[' "$N_STALE"
  _f=1
  while IFS='	' read -r k rel why; do
    [ "$_f" -eq 1 ] || printf ','
    _f=0
    printf '{"kind":"%s","path":"%s","why":"%s"}' "$k" "$rel" "$(printf '%s' "$why" | sed 's/"/\\"/g')"
  done < "$TMP/names"
  printf ']}\n'
else
  while IFS='	' read -r rel ln dialect target; do
    printf 'DANGLING  %s:%s (%s) -> %s\n' "$rel" "$ln" "$dialect" "$target"
  done < "$TMP/dangling"
  while IFS='	' read -r rel ln p; do
    printf 'DEAD-PATH %s:%s cites %s\n' "$rel" "$ln" "$p"
  done < "$TMP/deadpath"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    printf 'COLLISION slug "%s" is carried by:\n' "$s"
    LC_ALL=C grep -E "^$s	" "$TMP/slugs" | cut -f2 | sed 's/^/            /'
  done < "$TMP/dupslugs"
  while IFS='	' read -r k rel why; do
    printf '%-10s %s: %s\n' "$k" "$rel" "$why"
  done < "$TMP/names"
  while IFS='	' read -r rel days; do
    printf 'STALE     %s (%s days since its last commit, report-only)\n' "$rel" "$days"
  done < "$TMP/stale"
fi

# The verdict, on stderr. A finding that --strict gates is a FAIL; without it, a WARN that cannot change the exit.
_gate() { # <count> <what> <fix>
  [ "$1" -gt 0 ] || return 0
  if [ "$STRICT" -eq 1 ]; then log_fail "$1 $2"; log_fix "$3"; else log_warn "$1 $2"; log_fix "$3"; fi
}
log_head "$N_NOTES note(s) in $STORE"
_gate "$N_DANGLING" "dangling reference(s)" "write the note each DANGLING line names, or drop the link"
_gate "$N_DEADPATH" "dead path citation(s)" "correct the path each DEAD-PATH line cites"
_gate "$N_DUP" "slug collision(s)" "rename or merge the notes each COLLISION line lists"
if [ "$N_NAMES" -gt 0 ]; then
  _nfix="rename the note or folder each NAME-* line names (D-24 <subject>-<claim>, lowercase kebab); links follow the slug"
  if [ "$STRICT_NAMES" -eq 1 ]; then log_fail "$N_NAMES name finding(s)"; log_fix "$_nfix"; else log_warn "$N_NAMES name finding(s), report-only without --strict-names"; log_fix "$_nfix"; fi
fi
[ $((N_DANGLING + N_DEADPATH + N_DUP)) -gt 0 ] || log_ok "no dangling reference, dead path or slug collision"
[ "$N_STALE" -eq 0 ] || log_note "$N_STALE stale note(s), report-only: age is not a defect"
[ "$GIT_BACKED" = true ] || log_note "store is not a git repo — staleness not measured"
log_end; exit $?
