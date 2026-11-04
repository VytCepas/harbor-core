#!/usr/bin/env sh
# L0-11 (harbor#75) — read the session registry Claude Code already maintains,
# and answer the question no session can answer about itself: who else is here?
#
#   sh context-peers.sh            # table of live sessions
#   sh context-peers.sh --json     # same data, machine-readable
#   sh context-peers.sh --repo DIR # only sessions sharing DIR's working tree
#
# WHY. Claude Code writes $CFG/sessions/<pid>.json per process — pid, sessionId,
# cwd, procStart, startedAt, status, name. Collection was already solved; nothing
# in bin/ read it. status-fleet-glyph.sh tells you WHICH session this is; no session had
# any idea the others existed. Two claudes in one working tree fight over the
# index and the branch, and the first anyone learns of it is a checkout yanking
# the tree from under the other.
# Removed notes: docs/explanation/code-cases/bin-context-peers.md
# PRIVACY (CONSTITUTION §3). These records live under ~/.claude and carry
# absolute paths and session identity. This prints to a terminal. Never pipe
# --json anywhere cacheable, and never paste it into a web tool.
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SESS="${HARBOR_SESSION_REGISTRY_DIR:-$CFG/sessions}"
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
# stdout is the table or JSON a caller parses, so the log goes to stderr (contracts/logging.md).
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$DIR/library-log.sh"
FORMAT=table
ONLY_REPO=""

# HARBOR_CONTEXT_PEER_EXCLUDE lets the SessionStart caller drop ITSELF ("3 sessions are here" when one is you is an off-by-one that makes a warning ignored).
EXCLUDE_SID="${HARBOR_CONTEXT_PEER_EXCLUDE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json ;;
    --peers) FORMAT=peers ;;
    --repo) shift; ONLY_REPO="${1:-}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    # Usage exit 2, per contracts/cli.md — 0 success, 1 ran-and-reported, 2 usage.
    *) printf 'fleet-sessions: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { log_fail "jq is required, and is not on PATH"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1; }

# ── liveness ──
# A PID IS NOT AN IDENTITY: the registry is keyed by pid and does not self-reap, so a recycled pid makes an unrelated process read ALIVE and inflates the peer count with ghosts. Liveness is TWO facts: the pid exists AND the process under it started when the record says.
# The comparison is not a string match: the record's procStart is UTC and `ps -o lstart` is local (measured: the same instant, three hours apart).
_epoch_local() { # <ps lstart string> -> epoch seconds
  date -j -f '%a %b %d %T %Y' "$1" +%s 2>/dev/null && return 0
  date -d "$1" +%s 2>/dev/null && return 0
  printf ''
}
_epoch_utc() { # <procStart string, UTC> -> epoch seconds
  date -j -u -f '%a %b %d %T %Y' "$1" +%s 2>/dev/null && return 0
  TZ=UTC date -d "$1" +%s 2>/dev/null && return 0
  printf ''
}

# TOLERANCE, not equality: ps reports whole seconds and the record is written a beat after exec; 90s is far narrower than any realistic pid recycle.
_SKEW=90

is_live() { # <pid> <procStart>
  _p="$1"; _ps="$2"
  kill -0 "$_p" 2>/dev/null || return 1
  _l="$(ps -o lstart= -p "$_p" 2>/dev/null | sed 's/^ *//;s/ *$//')"
  # No ps output means UNKNOWN, and unknown is not alive (else this silently degrades back to `kill -0`).
  [ -n "$_l" ] || return 1
  [ -n "$_ps" ] || return 1
  _a="$(_epoch_local "$_l")"; _b="$(_epoch_utc "$_ps")"
  [ -n "$_a" ] && [ -n "$_b" ] || return 1
  _d=$(( _a > _b ? _a - _b : _b - _a ))
  [ "$_d" -le "$_SKEW" ]
}

# ── where a session actually is ──
# Grouped by git WORKING TREE, not cwd: sessions in different subdirectories of one repo still contend for the index and the branch. GOVERNED is delegated to floor_in_repo (rule M1: the marker walk lives there only).
# The registry cwd is the LAUNCH directory (harbor#75; `lsof -d cwd` returns the identical value), so Harbor records the tree a session WRITES to in $CFG/.helm-peers/<sid> (context-resolve.sh, PostToolUse). That record wins when `src=write`; the launch tree is the fallback and is reported AS the fallback.
PEER_DIR="${HARBOR_CONTEXT_PEERS_DIR:-$CFG/.helm-peers}"
# Validated on read as well as on write (P13-peer-04): a plain Bash redirect into $CFG/.helm-peers/ succeeds and this value reaches another session's SessionStart `additionalContext`, so an unconstrained record is a cross-session instruction channel (CONSTITUTION 4); jq quoting is transport safety, not content safety.
# A tree must be absolute, free of control characters (a newline forges a second `key=` line, P13-peer-05) and a real directory; anything else reads as absent and degrades to the launch dir.
# peer_display <value>: bound a REGISTRY-sourced field before it reaches another session's model context (PR #93 review, P1). `name` and `status` come from Claude Code's registry, unvalidated, and `--peers` renders them into additionalContext.
# A charset filter does NOT close this (`SYSTEM: disregard the operator` is letters, spaces and a colon), so the free-text name is OMITTED from the prompt-bound report (the session id identifies a peer) and kept in the human table. What remains bounds the validated fields (tree, branch): control characters out, a plain display set, a length cap against context floods.
peer_display() { # <value>
  printf '%s' "$1" | tr -d '\000-\037' | tr -c 'A-Za-z0-9 ._@#()+/:-' '?' | cut -c1-200
}

peer_get() { # <sessionId> <key>
  [ -n "$1" ] || return 0
  case "$1" in *[!A-Za-z0-9_-]*) return 0 ;; esac
  [ -f "$PEER_DIR/$1" ] || return 0
  _pv="$(sed -n "s/^$2=//p" "$PEER_DIR/$1" 2>/dev/null | head -n 1)"
  [ -n "$_pv" ] || return 0
  _pc="$(printf '%s' "$_pv" | tr -d '\000-\037')"
  [ "$_pc" = "$_pv" ] || return 0
  case "$2" in
    tree)   case "$_pv" in /*) ;; *) return 0 ;; esac; [ -d "$_pv" ] || return 0 ;;
    src)    case "$_pv" in launch|write) ;; *) return 0 ;; esac ;;
    pid)    case "$_pv" in ''|*[!0-9]*) return 0 ;; esac ;;
    branch) case "$_pv" in *[!A-Za-z0-9_./+-]*) return 0 ;; esac ;;
  esac
  printf '%s' "$_pv"
}
tree_of() { # <cwd> -> working-tree root, or the cwd itself
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1"
}
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''; }
governed_of() { # <cwd> -> repo | ambient
  # shellcheck disable=SC2034 # CLAUDE_PROJECT_DIR: read by library-admission.sh
  ( CLAUDE_PROJECT_DIR="$1"; . "$DIR/library-admission.sh" 2>/dev/null || exit 1
    if floor_in_repo; then printf 'repo'; else printf 'ambient'; fi ) 2>/dev/null || printf '?'
}

# ── collect ─────────────────────────────────────────────────────────────────
# UNIT SEPARATOR, NOT TAB: a tab is IFS whitespace, so `IFS=<tab> read` folds runs and drops empty fields (an ambient session has no branch, which shifted every later column left). 0x1f is non-whitespace and cannot occur in a path.
SEP="$(printf '\037')"
ROWS=""
if [ -d "$SESS" ]; then
  for f in "$SESS"/*.json; do
    [ -f "$f" ] || continue
    _j="$(jq -r '[.pid, .sessionId, .cwd, .procStart, .status, .name, .kind]
                 | @tsv' "$f" 2>/dev/null)" || continue
    [ -n "$_j" ] || continue
    _pid=$(printf '%s' "$_j"  | cut -f1)
    _sid=$(printf '%s' "$_j"  | cut -f2)
    _cwd=$(printf '%s' "$_j"  | cut -f3)
    _pst=$(printf '%s' "$_j"  | cut -f4)
    _sta=$(printf '%s' "$_j"  | cut -f5)
    _nam=$(printf '%s' "$_j"  | cut -f6)
    _knd=$(printf '%s' "$_j"  | cut -f7)
    [ -n "$_pid" ] && [ "$_pid" != "null" ] || continue
    is_live "$_pid" "$_pst" || continue
    [ -z "$EXCLUDE_SID" ] || [ "$_sid" != "$EXCLUDE_SID" ] || continue
    _rtree="$(peer_get "$_sid" tree)"
    _rsrc="$(peer_get "$_sid" src)"
    if [ -n "$_rtree" ] && [ "$_rsrc" = "write" ]; then
      _tree="$_rtree"; _src=write
      _brch="$(peer_get "$_sid" branch)"
      [ -n "$_brch" ] || _brch="$(branch_of "$_rtree")"
    else
      _tree="$(tree_of "$_cwd")"; _src=launch
      _brch="$(branch_of "$_cwd")"
    fi
    [ -z "$ONLY_REPO" ] || [ "$_tree" = "$(tree_of "$ONLY_REPO")" ] || continue
    ROWS="$ROWS$_pid$SEP$_sid$SEP$_tree$SEP$_brch$SEP$_sta$SEP$_nam$SEP$_knd$SEP$(governed_of "$_cwd")$SEP$_src
"
  done
fi

# ── emit ────────────────────────────────────────────────────────────────────
if [ "$FORMAT" = json ]; then
  printf '%s' "$ROWS" | jq -R -s --arg sep "$SEP" 'split("\n") | map(select(length>0) | split($sep)
    | {pid: (.[0]|tonumber?), sessionId: .[1], tree: .[2], branch: .[3],
       status: .[4], name: .[5], kind: .[6], context: .[7], treeSource: .[8]})'
  exit 0
fi

# ── --peers · the SessionStart line ─────────────────────────────────────────
# ONE short paragraph or nothing: it is injected into every session's context, so a table would be skipped, and silence with no peers is the correct output. It says which tree each session works in and WHETHER THAT WAS OBSERVED (`launched there; nothing written yet` marks a launch directory).
if [ "$FORMAT" = peers ]; then
  [ -n "$ROWS" ] || exit 0
  _line=""
  _n=0
  printf '%s' "$ROWS" | while IFS="$SEP" read -r p _s t b st n _k g src; do
    [ -n "$p" ] || continue
    _w="$(peer_display "$t")"
    [ "$src" = "write" ] || _w="$_w (launched there; nothing written yet)"
    # The session id, not the name (see peer_display). Status renders only when it is one short lowercase word; anything else is a value nobody defined.
    _st="?"; case "$st" in [abcdefghijklmnopqrstuvwxyz][abcdefghijklmnopqrstuvwxyz]*) [ "${#st}" -le 12 ] && _st="$st" ;; esac
    printf '  · %s [%s] %s%s\n' "$(peer_display "$p")" "$_st" "$_w" \
      "$( [ -n "$b" ] && printf ' on %s' "$(peer_display "$b")" )"
  done > "${TMPDIR:-/tmp}/.helm-peers-line.$$"
  _n="$(grep -c . "${TMPDIR:-/tmp}/.helm-peers-line.$$" 2>/dev/null || echo 0)"
  if [ "${_n:-0}" -gt 0 ]; then
    printf 'Other live Claude Code sessions on this machine (%s). Two sessions writing one working tree contend for the index and the branch:\n' "$_n"
    cat "${TMPDIR:-/tmp}/.helm-peers-line.$$"
  fi
  rm -f "${TMPDIR:-/tmp}/.helm-peers-line.$$"
  exit 0
fi

_n="$(printf '%s' "$ROWS" | grep -c . || true)"
if [ "${_n:-0}" -eq 0 ]; then
  echo "no live claude sessions."
  exit 0
fi
printf '%-7s %-10s %-9s %-8s %-22s %-6s %s\n' PID NAME STATUS CONTEXT BRANCH TREE-SRC TREE
printf '%s' "$ROWS" | while IFS="$SEP" read -r p _s t b st n _k g src; do
  [ -n "$p" ] || continue
  printf '%-7s %-10s %-9s %-8s %-22s %-6s %s\n' \
    "$p" "${n:-–}" "${st:-–}" "$g" "${b:-–}" "$src" "$t"
done

# The count is the point: a session wants to know whether anyone else is in ITS tree.
_here="$(printf '%s' "$ROWS" | awk -F"$SEP" -v t="$(tree_of "$PWD")" '$3==t' | grep -c . || true)"
if [ "${_here:-0}" -gt 1 ]; then
  printf '\n⚠ %s sessions share this working tree — they contend for the index and the branch.\n' "$_here"
fi
exit 0
