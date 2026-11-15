#!/usr/bin/env sh
# memory (harbor#6 — workstream D, D1/D7) — the L0 memory front door.
# `memory <query>` runs the Bun engine when present; without Bun the same command still answers
# over the same markdown with grep only (D7). POSIX sh by design: the bottom rung must not need
# the missing runtime. Writes nothing; engine indexes are rebuilt per invocation.
# Removed notes: docs/explanation/code-cases/bin-memory.md
set -u

# NOGLOB is load-bearing: IFS splitting does not stop pathname expansion on unquoted words, so a
# query like '*.md' would expand against the caller's cwd and the answer would depend on where
# you stood. Nothing here needs globbing.
set -f

# Resolve self through the symlink (~/.local/bin/memory): otherwise the engine is unreachable and
# the tool silently drops to the grep rung.
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

# Status lines are log-lib's, on stderr: stdout is the answer (contracts/logging.md).
[ -f "$DIR/library-log.sh" ] || { printf 'memory: library-log.sh is missing beside %s\n' "$_self" >&2; exit 2; }
. "$DIR/library-log.sh"
. "$DIR/library-fs.sh"   # fs_session_key: the harness's key, as memory-route.sh (harbor#966)
log_init memory
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
# die <exit> <what failed> <fix command>: FAIL, its fix, the summary, exit.
die() { _x="$1"; log_fail "$2"; log_fix "$3"; log_end || :; exit "$_x"; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Default is the notes store (harbor#1010 PR 4, D-68): projects/<home-key>/memory, key = the harness's key of the
# physical $HOME (library-fs.sh, as memory-route.sh); $CFG/MEMORY only when that silo is absent.
STORE="${HARBOR_MEMORY_ROOT:-}"
if [ -z "$STORE" ]; then
  _hk="$(CDPATH= cd -- "$HOME" 2>/dev/null && pwd -P | fs_session_keys)"
  if [ -n "$_hk" ] && [ -d "$CFG/projects/$_hk/memory" ]; then STORE="$CFG/projects/$_hk/memory"; else STORE="$CFG/MEMORY"; fi
fi

# Pin grep: a ugrep wrapper first in PATH skips binary and gitignored files and returns a shorter
# list with exit 0, which reads like a correct answer.
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

# Rotate the arguments (`set -- "$@" "$1"; shift`) so every byte of every term survives, with no IFS
# splitting. Flags are validated here and reach the engine BEFORE `--`, terms after it, so a
# flag-shaped term stays a term; $FLAGS only holds literals this loop wrote.
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
      # End of options: everything after `--` is a query term, even if it starts with a dash.
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

# rung 1: the engine
BUN="${HARBOR_MEMORY_BUN:-}"
[ -n "$BUN" ] || BUN="$(command -v bun 2>/dev/null || true)"

# Runtime present but engine absent is NOT the no-runtime case, yet both say "tier grep". The
# reachable cause is a COPY of this script (it resolves the engine relative to itself); `memory`
# installs as a symlink for that reason.
if [ -n "$BUN" ] && [ -x "$BUN" ] && [ ! -f "$ENGINE" ]; then
  log_warn "a runtime is installed but the engine is not at $ENGINE — answering at the grep tier"
  log_fix "ln -sfn <repo>/bin/memory.sh ~/.local/bin/memory   # a SYMLINK to the repo, not a copy"
  _warned=1
fi

if [ -n "$BUN" ] && [ -x "$BUN" ] && [ -f "$ENGINE" ]; then
  # `--` before the query terms: the engine uses strict parseArgs, so a dash-leading term was
  # read as an unknown option and exited 2 while the grep rung handled it fine.
  # shellcheck disable=SC2086 — $FLAGS holds only literals written above.
  exec "$BUN" "$ENGINE" "$VERB" --root "$STORE" $FLAGS -- "$@"
fi

# rung 2: grep. Not a ranker reimplementation: it answers "which notes mention every word" and says
# which rung produced it. Exit 2 when the verb needs bun (the operation did not run); a search
# that finds nothing exits 0.
if [ "$VERB" != "search" ]; then
  die 2 "\`$VERB\` needs bun, which is not installed" "memory <terms>   # the grep tier answers a search"
fi

JSON=0
case " $FLAGS " in *" --json "*) JSON=1 ;; esac

if [ ! -d "$STORE" ]; then  # exit 0 is the contract: no store is an empty answer, not a failed run
  log_warn "no store at $STORE"; log_fix "memory --root <a memory store directory> <terms>"; log_end || :; exit 0
fi

# Narrow progressively, one term at a time; -F because a query is words, not a regex ("c++").
# operator searching for "c++" must not get a quantifier error.
HITS="$(find "$STORE" -type d \( -name '.*' -o -name node_modules -o -name indexes \) -prune -o \
        -type f -name '*.md' -print 2>/dev/null | sort)"
# Terms come straight from "$@"; only the file list is newline-delimited.
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

# Both rungs emit the same shape, so the grep tier carries `query` too. awk, not sed: portable
# newline escaping across BSD and GNU sed.
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
