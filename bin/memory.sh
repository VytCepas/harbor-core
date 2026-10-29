#!/usr/bin/env sh
# memory (harbor#6 — workstream D, D1/D7) — the L0 memory front door.
#
# One door, two rungs. `memory <query>` runs the Bun engine when Bun is present;
# when it is not, the SAME command still answers, over the same markdown, using
# nothing but grep. That is D7's third standalone degradation, and it is why
# this file is POSIX sh rather than part of the engine: a ladder whose bottom
# rung needs the runtime that is missing is not a ladder.
#
# WHY THE FRONT DOOR IS NOT THE ENGINE. bin/deploy-doctor.sh classifies bun as
# OPTIONAL — "the floor is deliberately zero-Bun" — and CI preflights a fixed
# list of binaries that does not include it. Anything Harbor must be able to run
# on any machine lives in bin/ and is sh; the retrieval algorithms live in
# tools/memory/ and are TypeScript, which is the language-by-layer rule from
# policy/constitution.md applied rather than restated.
#
# Writes nothing. Reads markdown. Every index is rebuilt per invocation by the
# engine and discarded (contracts/memory-format.md).
set -u

# NOGLOB, AND IT IS LOAD-BEARING. Splitting a list by setting IFS and expanding
# unquoted — `set -- $_new`, `for f in $HITS` — controls FIELD splitting but does
# nothing about PATHNAME expansion, which happens on the same unquoted word. So
# `memory '*.md'` had its query term expanded against the caller's working
# directory: measured before this line existed, the identical query returned 7
# results run from a directory holding .md files and 1 from a directory without.
# A search tool whose answer depends on where you were standing is worse than one
# that errors. Nothing here needs globbing; `case` patterns are unaffected by -f.
set -f

# ── resolve self through symlinks ───────────────────────────────────────────
# The installed entry point is a symlink (~/.local/bin/memory), so $0's dirname
# is the symlink's directory, not the repo's. Without this the engine is
# unreachable from exactly the place an operator actually types the command, and
# the tool silently drops to the grep rung while reporting nothing unusual.
_self="$0"
_hops=0
while [ -L "$_self" ]; do
  _hops=$((_hops + 1))
  [ "$_hops" -gt 32 ] && break   # a symlink cycle must not hang the front door
  _here="$(CDPATH= cd -- "$(dirname -- "$_self")" && pwd)"
  _link="$(readlink "$_self")"
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$_here/$_link" ;;
  esac
done
DIR="$(CDPATH= cd -- "$(dirname -- "$_self")" && pwd)"
REPO="$(CDPATH= cd -- "$DIR/.." && pwd)"
ENGINE="$REPO/tools/memory/memory-engine.ts"

# Status lines are log-lib's, on stderr: stdout is the answer (contracts/logging.md). A clean search logs
# nothing; a refusal ends with the summary after its fix line. Found beside the file the link resolves to.
[ -f "$DIR/library-log.sh" ] || { printf 'memory: library-log.sh is missing beside %s\n' "$_self" >&2; exit 2; }
. "$DIR/library-log.sh"
log_init memory; LOG_FD=2
# die <exit> <what failed> <fix command>: FAIL, its fix, the summary, exit.
die() { _x="$1"; log_fail "$2"; log_fix "$3"; log_end || :; exit "$_x"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# THE DEFAULT IS THE NOTES STORE (harbor#1010 PR 4, D-68): the $HOME silo, projects/<home-key>/memory, which is where
# the notes and their index live and where every governed repo's silo is routed (memory-route.sh). The old
# $CFG/MEMORY tree is the fallback only when that silo does not exist, so a box without notes still answers.
# Same key rule as memory-route.sh: the physical $HOME with every `/` turned into `-`.
STORE="${HARBOR_MEMORY_ROOT:-}"
if [ -z "$STORE" ]; then
  _hk="$(CDPATH= cd -- "$HOME" 2>/dev/null && pwd -P | sed 's|/|-|g')"
  if [ -n "$_hk" ] && [ -d "$CFG/projects/$_hk/memory" ]; then STORE="$CFG/projects/$_hk/memory"; else STORE="$CFG/MEMORY"; fi
fi

# PIN grep, for the same reason bin/guard-lib.sh pins $FLOOR_GREP. On this
# machine the `grep` first in PATH is a ugrep wrapper carrying `-I
# --ignore-files`, so it silently skips binary AND gitignored files. The grep
# rung's entire job is to find every note that mentions a word; a wrapper that
# quietly omits some of them returns a SHORTER list with a zero exit status,
# which reads exactly like a correct answer. Absolute path first, PATH second so
# this still runs on a box without /usr/bin/grep.
MEM_GREP="$( [ -x /usr/bin/grep ] && echo /usr/bin/grep || echo grep )"

usage() {
  cat <<'USAGE'
memory (harbor#6) — on-demand L0 memory retrieval

  memory <terms...>            search the store, BM25-ranked
  memory search <terms...>     the same, said explicitly
  memory graph <slug>          notes linked to <slug> (needs bun)
  memory stats                 corpus summary (needs bun)

  --root DIR   read this store instead of the notes store (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<home-key>/memory;
               the old .../MEMORY tree only when that does not exist)
  --json       machine-readable output
  --limit N    cap the result count
  --depth N    graph traversal depth

Reads markdown only. Writes nothing.
USAGE
}

[ "$#" -eq 0 ] && { usage; exit 2; }
case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac

# ── split off --root, keep everything else for the engine ───────────────────
# ROTATION, not a delimited string. The first cut joined the remaining arguments
# with newlines and re-split them with IFS, which loses any argument that
# CONTAINS the delimiter: a single term `foo<newline>bar` came back as two terms.
# `set -- "$@" "$1"; shift` walks the list exactly once and pushes each argument
# onto the end unchanged, so every byte of every argument survives — spaces,
# newlines, quotes and glob characters alike — with no IFS games and nothing for
# `set -f` to have to protect.
#
# FLAGS ARE SEPARATED FROM TERMS HERE, not passed through. The engine gets its
# options BEFORE a `--` and the query terms after it, so a term that looks like
# a flag stays a term. Passing "$@" wholesale after `--` was tried and broke the
# opposite way: `--json` became a search word and the JSON output vanished.
# Every flag value is validated here rather than in the engine, so the message
# names `memory`, and $FLAGS can be expanded unquoted safely — it only ever
# holds literals this loop wrote.
VERB=""
FLAGS=""
_argc=$#
_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
while [ "$_argc" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || die 2 "--root needs a directory" "memory --help"
      STORE="$2"; shift 2; _argc=$((_argc - 2)) ;;
    --root=*)
      STORE="${1#--root=}"; shift; _argc=$((_argc - 1)) ;;
    --json)
      FLAGS="$FLAGS --json"; shift; _argc=$((_argc - 1)) ;;
    --limit|--depth)
      [ "$#" -ge 2 ] || die 2 "$1 needs a number" "memory --help"
      _num "$2" || die 2 "$1 expects a non-negative integer, got $2" "memory $1 10 <terms>"
      FLAGS="$FLAGS $1=$2"; shift 2; _argc=$((_argc - 2)) ;;
    --limit=*|--depth=*)
      _num "${1#*=}" || die 2 "${1%%=*} expects a non-negative integer" "memory ${1%%=*}=10 <terms>"
      FLAGS="$FLAGS $1"; shift; _argc=$((_argc - 1)) ;;
    --)
      # End of options. Everything after it is a query term, including anything
      # that looks like a flag — the standard escape hatch, and the one an
      # operator reaches for when a search word starts with a dash.
      shift; _argc=$((_argc - 1))
      while [ "$_argc" -gt 0 ]; do
        set -- "$@" "$1"; shift; _argc=$((_argc - 1))
      done ;;
    *)
      set -- "$@" "$1"; shift; _argc=$((_argc - 1)) ;;
  esac
done

[ "$#" -eq 0 ] && { usage; exit 2; }

case "$1" in
  search|graph|stats) VERB="$1"; shift ;;
  *) VERB="search" ;;
esac

# ── rung 1: the engine ──────────────────────────────────────────────────────
BUN="${HARBOR_MEMORY_BUN:-}"
[ -n "$BUN" ] || BUN="$(command -v bun 2>/dev/null || true)"

# SAY SO WHEN THE RUNTIME IS PRESENT BUT THE ENGINE IS NOT. Dropping to the grep
# rung is the correct answer on a machine with no runtime; it is the WRONG answer
# on a machine that has one and simply cannot see tools/memory/, and the two are
# indistinguishable in the output — both say "tier grep".
#
# The reachable way to land here: this script COPIED out of the repo rather than
# symlinked to it. It resolves the engine relative to itself, so a copy at
# ~/.claude/bin/memory.sh looks for ~/.claude/tools/memory/ and finds nothing.
# That is why `memory` installs as a symlink while `harbor` installs as a copy —
# `harbor restore` must survive the checkout disappearing, and this must reach
# into it.
if [ -n "$BUN" ] && [ -x "$BUN" ] && [ ! -f "$ENGINE" ]; then
  log_warn "a runtime is installed but the engine is not at $ENGINE — answering at the grep tier"
  log_fix "ln -sfn <repo>/bin/memory.sh ~/.local/bin/memory   # a SYMLINK to the repo, not a copy"
  _warned=1
fi

if [ -n "$BUN" ] && [ -x "$BUN" ] && [ -f "$ENGINE" ]; then
  # `--` BEFORE the query terms, and --root BEFORE that. The engine parses argv
  # with node:util parseArgs in strict mode, so an unseparated term beginning
  # with a dash — a version string, a negative number, anything flag-shaped —
  # was read as an unknown option and killed the process with exit 2. The grep
  # rung handled the same query fine, so the PRIMARY tier failed on input its
  # own fallback survived.
  # shellcheck disable=SC2086 — $FLAGS holds only literals written above.
  exec "$BUN" "$ENGINE" "$VERB" --root "$STORE" $FLAGS -- "$@"
fi

# ── rung 2: grep ────────────────────────────────────────────────────────────
# Deliberately NOT a reimplementation of the ranker. It answers the question the
# markdown can answer without a runtime — "which notes mention every one of
# these words" — and says which rung produced it, so a degraded answer is never
# mistaken for a ranked one.
# EXIT 2, not 0. The requested operation did not run, and a caller that checks
# only the status must not be told it succeeded. Distinct from a search that
# finds nothing, which IS a successful answer and exits 0.
if [ "$VERB" != "search" ]; then
  die 2 "\`$VERB\` needs bun, which is not installed" "memory <terms>   # the grep tier answers a search"
fi

JSON=0
case " $FLAGS " in *" --json "*) JSON=1 ;; esac

if [ ! -d "$STORE" ]; then  # exit 0 is the contract: no store is an empty answer, not a failed run
  log_warn "no store at $STORE"; log_fix "memory --root <a memory store directory> <terms>"; log_end || :; exit 0
fi

# Progressive narrowing: start from every markdown file, then keep only the ones
# matching each term in turn. -F because a query is words, not a regex — an
# operator searching for "c++" must not get a quantifier error.
HITS="$(find "$STORE" -type d \( -name '.*' -o -name node_modules -o -name indexes \) -prune -o \
        -type f -name '*.md' -print 2>/dev/null | sort)"
# Terms are read straight from "$@" rather than re-collected into a string, for
# the same reason the argument loop rotates: a term is whatever the caller typed.
# Only the FILE list is newline-delimited, and `find -print` cannot emit a path
# containing a newline in a form this loop could misread anyway.
for t in "$@"; do
  [ -n "$HITS" ] || break
  NEXT=""
  OLDIFS="$IFS"
  IFS='
'
  for f in $HITS; do
    IFS="$OLDIFS"
    if "$MEM_GREP" -qiF -- "$t" "$f" 2>/dev/null; then
      NEXT="$NEXT$f
"
    fi
    IFS='
'
  done
  IFS="$OLDIFS"
  HITS="$(printf '%s' "$NEXT")"
done

COUNT=0
if [ -n "$HITS" ]; then
  COUNT="$(printf '%s\n' "$HITS" | "$MEM_GREP" -c . || true)"
fi

# THE TWO RUNGS EMIT THE SAME SHAPE. A consumer must not have to know which rung
# answered in order to read the reply, so the grep tier carries `query` too. It
# was missing, which meant a caller could read `.query` from a ranked answer and
# get null from a degraded one — a difference that only shows up on the machine
# without the runtime, which is the machine nobody tests on.
# awk, not sed: escaping a newline portably across BSD and GNU sed is a trap, and
# awk is on CI's preflight list.
json_escape() {
  printf '%s' "$1" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); if (NR>1) printf "\\n"; printf "%s", $0}'
}
QSTR=""
for t in "$@"; do
  if [ -z "$QSTR" ]; then QSTR="$t"; else QSTR="$QSTR $t"; fi
done

if [ "$JSON" -eq 1 ]; then
  printf '{"schema_version":1,"tier":"grep","root":"%s","query":"%s","count":%s,"results":[' \
    "$STORE" "$(json_escape "$QSTR")" "$COUNT"
  _first=1
  OLDIFS="$IFS"
  IFS='
'
  for f in $HITS; do
    [ -n "$f" ] || continue
    [ "$_first" -eq 1 ] || printf ','
    _first=0
    printf '{"path":"%s"}' "${f#"$STORE"/}"
  done
  IFS="$OLDIFS"
  printf ']}\n'
else
  OLDIFS="$IFS"
  IFS='
'
  for f in $HITS; do
    [ -n "$f" ] || continue
    printf '       %s\n' "${f#"$STORE"/}"
  done
  IFS="$OLDIFS"
  printf 'memory: %s result(s), tier grep\n' "$COUNT"
fi
[ "${_warned:-0}" -eq 0 ] || { log_end || :; }
