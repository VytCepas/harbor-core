#!/usr/bin/env sh
# memory-lint (harbor#6 — workstream D, D2) — the deterministic anti-rot gate
# over a memory store. No LLM, no Bun, no network: every finding is a fact about
# the files, reproducible by anyone with awk and git.
#
# Four checks, not the same kind of thing:
#   dangling    a note links to a slug no note carries. HARD under --strict.
#   dead-path   a note cites ](./relative) that does not resolve. HARD.
#   collision   two notes share a slug, so every link to it is ambiguous. HARD.
#   stale       not touched in a long time. REPORT-ONLY always: age is not a defect, and failing on it teaches
#               touching files to silence a linter (constitution §2.11, a false positive is a defect).
# Why sh and not the engine: it must run where bun does not (CI preflight), so the dangling definition exists in two
# languages. fixtures/memory/expected.json pins the answer and tests/memory/memory/memory.test.sh asserts this script
# and tools/memory/graph.ts each reproduce it.
# Removed notes: docs/explanation/code-cases/bin-memory-lint.md
set -u

# NOGLOB: lists are split by IFS and expanded unquoted, which does not stop pathname expansion; a filename or
# [[link]] containing * ? [ ] would be expanded against the cwd and findings would depend on where the lint ran.
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
log_init memory-lint
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2

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
  segment that is a raw machine name (hostname -s, or HARBOR_MEMORY_HOST_NAMES, space separated) and not the lowercase alias.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)       [ "$#" -ge 2 ] || die "--root needs a directory" "sh bin/memory-lint.sh --help"
                  STORE="$2"; shift 2 ;;
    --root=*)     STORE="${1#--root=}"; shift ;;
    --stale-days) [ "$#" -ge 2 ] || die "--stale-days needs a number" "sh bin/memory-lint.sh --help"
                  # Validated here: under dash a non-numeric operand makes $((…)) abort with "Illegal number" instead of a usage error.
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

# Same scope as the engine (tools/memory/store.ts): dot-dirs are history or another scope, indexes/ is derived. The file
# list is newline-delimited (-print0 is not portable); the fixture corpus holds a name with a space to keep that honest.
# -L is not cosmetic (harbor#608): a governed repo's silo is a SYMLINK to the $HOME store, and `find` without -L does
# not follow a symlinked start path, so the walk returned nothing while the index was real and every pointer read as dangling.
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

# link extraction: one awk pass per file emitting `line<TAB>dialect<TAB>target`; only awk can track frontmatter state,
# and `related:` means a list, a scalar or a block of objects depending on what follows it.
extract_links() { # <file>
  # An unclosed frontmatter block is not frontmatter: tools/memory/store.ts treats it as all body, while this awk
  # once parsed the whole file as frontmatter and fabricated dangling references. The closing fence is found first, in its own pass.
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
    # Code is not prose, in agreement with tools/memory/store.ts: `[[ $? == 1 ]]` is a shell test, not a wikilink.
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
HOSTS="${HARBOR_MEMORY_HOST_NAMES:-$(hostname -s 2>/dev/null || true)}"
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
# git log, not mtime: a fresh clone rewrites every mtime. A store that is not a git repo has no age, reported as such.
: > "$TMP/stale"
if git -C "$STORE" rev-parse --git-dir >/dev/null 2>&1; then
  NOW="$(date +%s)"
  CUTOFF=$((NOW - STALE_DAYS * 86400))
  # One `git log` per note, slow on purpose (24 s on the live store). harbor#216's single `--name-only` pass (113 ms)
  # was wrong four ways, all silent; each is now an assertion in tests/memory/memory/memory.test.sh. A fast path needs:
  #   1 a nested store: `--name-only` paths are repo-root-relative (`--relative -- .`);
  #   2 core.quotePath: C-quoted non-ASCII names never equal `find`'s (`-c core.quotePath=false`);
  #   3 a filename that looks like the commit-header marker (`C<digits>`) re-dates every later path;
  #   4 merge commits: `--name-only` prints nothing for a merge, `git log -1 -- <path>` matches history simplification.
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
