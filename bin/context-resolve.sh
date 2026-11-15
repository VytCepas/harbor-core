#!/usr/bin/env sh
# H2 (harbor#4) — SessionStart resolver: write this session's detect-and-defer
# context to a per-session FILE.
# Per-session FILE, not an env var: each hook is a fresh process, so an exported variable dies with it, and a file is the only channel a later PostToolUse/Stop hook can read. Keyed on `.session_id` so two sessions in one config dir cannot hand each other a verdict.
# NEVER BLOCKS: every path exits 0; this resolver only records and the readers stand down.
# Removed notes: docs/explanation/code-cases/bin-context-resolve.md
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
set -u
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
. "$DIR/library-admission.sh"
floor_read_stdin

CFG="$(floor_config_dir)"
CTX_DIR="$CFG/.helm-context"
PEER_DIR="$CFG/.helm-peers"
SID="$(floor_field '.session_id')"
EVENT="$(floor_field '.hook_event_name')"
# The event is decided from the payload, not an argument, so a wiring mistake cannot swap recorder and resolver; SessionStart carries no `.tool_name` and PostToolUse always does.
if [ -z "$EVENT" ]; then
  if [ -n "$(floor_field '.tool_name')" ]; then EVENT=PostToolUse; else EVENT=SessionStart; fi
fi
# No session id means nothing to key on: write nothing (a shared file is the cross-session bleed this design avoids); readers treat an absent file as stand down.
[ -n "$SID" ] || exit 0
case "$SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac   # a session id is a path component

# ── L0-11 (harbor#75) · THE PEER RECORD ──
# The registry cwd (read by context-peers.sh) is the LAUNCH directory and never updates, and `lsof -d cwd` gives the same stale answer (measured 2026-08-02: both read $HOME for a session editing ~/harbor).
# Two sessions contend when both WRITE a tree, so the signal is the tree a session writes to, recorded when it writes; that is why this script is also wired at PostToolUse (a separate recorder would be a new floor file with a B6 pin and wiring assertions in thirteen files).
# A peer report is advisory and must never cost a tool call: every path exits 0.
# peer_ok_tree <path>: 0 iff safe to record. The record feeds another session's SYSTEM CONTEXT (context-peers.sh --peers into SessionStart additionalContext), so an unconstrained value is a cross-session instruction channel (CONSTITUTION 4; P13-peer-04, P13-peer-05).
# Three constraints: absolute (a sentence is not a path), no control characters (a newline forges a second field, and both readers take the FIRST `key=` line), really a directory.
peer_ok_tree() {
  case "${1:-}" in /*) ;; *) return 1 ;; esac
  _pk="$(printf '%s' "$1" | tr -d '\000-\037')"
  [ "$_pk" = "$1" ] || return 1
  [ -d "$1" ] || return 1
  return 0
}
peer_write() { # <tree> <src> — atomic, best-effort, never fatal
  [ -n "$1" ] || return 0
  peer_ok_tree "$1" || return 0
  mkdir -p "$PEER_DIR" 2>/dev/null || return 0
  _pt="$PEER_DIR/.$SID.$$"
  {
    printf 'tree=%s\n' "$1"
    printf 'src=%s\n'  "$2"
    printf 'pid=%s\n'  "${PEER_PID:-}"
    printf 'branch=%s\n' "$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  } > "$_pt" 2>/dev/null || { rm -f "$_pt" 2>/dev/null; return 0; }
  mv -f "$_pt" "$PEER_DIR/$SID" 2>/dev/null || rm -f "$_pt" 2>/dev/null
  return 0
}
peer_field() { # <key> — read a key out of this session's record
  [ -f "$PEER_DIR/$SID" ] || return 0
  sed -n "s/^$1=//p" "$PEER_DIR/$SID" 2>/dev/null | head -n 1
}

# bash_write_target <command> <cwd>: print ONE absolute path the command writes into (harbor#610): a `>`/`>>` target, `tee [-a]` file, the last operand of cp/mv/install, or the dir of `git -C <dir> <mutating-subcommand>`.
# Prints nothing when unsure: quoted strings are blanked, heredoc bodies dropped, only plain literals count (no $vars, ~, globs or substitutions); writes inside scripts are out of scope by decision.
bash_write_target() {
  _bc="$1"; _bd="$2"
  case "$_bd" in /*) ;; *) return 0 ;; esac
  case "$_bc" in *'<<'*) _bc="$(printf '%s\n' "$_bc" | sed -n 1p)" ;; esac
  _bc="$(printf '%s' "$_bc" | tr '\n' ';' | sed -e "s/'[^']*'/#Q#/g" -e 's/"[^"]*"/#Q#/g')"
  _bw='[A-Za-z0-9_./+@%:,-]+'
  # A /dev/ target is a device, except /dev/shm/: a tmpfs a tree can live in (hosted CI's TMPDIR, harbor#1149).
  _bt="$(printf '%s\n' "$_bc" | "$FLOOR_GREP" -oE "(^|[^>&=<|-])>>?[ ]*$_bw" | sed -E 's/^.*>[ ]*//' | sed -e '\#^/dev/shm/#b' -e '\#^/dev/#d' | sed -n 1p)"
  if [ -z "$_bt" ]; then
    _bt="$(printf '%s\n' "$_bc" | "$FLOOR_GREP" -oE "(^|[;&|(] *)tee( +-[a-zA-Z]+)* +$_bw" | sed -E 's/^.* //' | sed -e '\#^/dev/shm/#b' -e '\#^/dev/#d' | sed -n 1p)"
  fi
  if [ -z "$_bt" ]; then
    _bs="$(printf '%s\n' "$_bc" | "$FLOOR_GREP" -oE "(^|[;&|(] *)(cp|mv|install)( +[^;&|<>()]+)+" | sed -n 1p)"
    case "$_bs" in *' -t'*|*'--target'*) _bs="" ;; esac
    _bt="$(printf '%s\n' "$_bs" | sed -E 's/.* //' | "$FLOOR_GREP" -xE "$_bw" | sed -n 1p)"
    # a single operand is not a copy
    [ "$(printf '%s\n' "$_bs" | tr ' ' '\n' | "$FLOOR_GREP" -c '^[^-;&|(]')" -ge 3 ] || _bt=""
  fi
  if [ -z "$_bt" ]; then
    _bt="$(printf '%s\n' "$_bc" | "$FLOOR_GREP" -oE "(^|[;&|(] *)git +-C +$_bw +(add|commit|checkout|switch|merge|rebase|reset|pull|stash|cherry-pick|restore|revert|am|apply|rm|mv)( |;|$)" | sed -E 's/^.*git +-C +//; s/ .*//' | sed -n 1p)"
  fi
  [ -n "$_bt" ] || return 0
  case "$_bt" in /*) printf '%s' "$_bt" ;; *) printf '%s/%s' "${_bd%/}" "$_bt" ;; esac
}

if [ "$EVENT" = "PostToolUse" ]; then
  # Only a write-shaped tool upgrades src=launch to src=write (a Read carries file_path too and forged a write, harbor#610); a Bash call counts only when bash_write_target names a target, and anything not parsed confidently is ignored.
  _tn="$(floor_field '.tool_name')"
  case "$_tn" in
    Write|Edit|MultiEdit|NotebookEdit)
      _fp="$(floor_field '.tool_input.file_path // .tool_input.notebook_path // empty')" ;;
    Bash)
      _fp="$(bash_write_target "$(floor_field '.tool_input.command')" "$(floor_field '.cwd')")" ;;
    *) exit 0 ;;
  esac
  [ -n "$_fp" ] || exit 0
  # THE PREFIX FAST-PATH IS GONE (pass 13, P13-peer-01/02): `case "$_fp" in "$_known"/*) exit 0` made the feature inert when the launch dir is an ANCESTOR of every repo (both sessions launch at $HOME), and with no record `_known` is empty so the pattern is `/*` and matches everything: the first record was never written. It also swallowed nested repos.
  # So the toplevel is resolved every time and the WRITE is what gets skipped: one `git rev-parse` per file-write PostToolUse, off the veto path.
  _d="$_fp"; [ -d "$_d" ] || _d="$(dirname "$_fp")"
  _tree="$(git -C "$_d" rev-parse --show-toplevel 2>/dev/null || printf '')"
  # Not in a repo: leave the record alone; a write to /tmp is not a claim about where this session works.
  [ -n "$_tree" ] || exit 0
  _known="$(peer_field tree)"
  # The branch is part of the record, so part of the skip condition (PR #93 review): peer_write is the only place `branch=` is recomputed, so skipping on tree and src alone left a stale branch in every peer table after a checkout in the same tree.
  _cur_branch="$(git -C "$_d" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  if [ "$_tree" = "$_known" ] && [ "$(peer_field src)" = "write" ] \
     && [ "$_cur_branch" = "$(peer_field branch)" ]; then exit 0; fi
  PEER_PID="$(peer_field pid)"
  peer_write "$_tree" write
  exit 0
fi

if floor_in_repo; then VERDICT=repo; else VERDICT=ambient; fi

# C2 (harbor#5): the constitution's deference, surfaced rather than assumed. policy/constitution.md yields to a governed repo's own CLAUDE.md on workflow, conventions and tooling, and its five rules never yield (harbor#581, decision (A) 2026-09-22); SessionStart `additionalContext` is the only channel that reaches the session before work.
# It emits a POINTER and a stand-down notice, never doctrine (docs/reports/platform-epic.md section 0: CORE is never appended to the system prompt unattended). Ambient sessions get nothing: the constitution is already in force.
DEFER_MSG=""
if [ "$VERDICT" = "repo" ]; then
  DEFER_MSG="Detect-and-defer: this session is inside a governed repo. The repo's own CLAUDE.md and .agents/ governance are AUTHORITATIVE on workflow, conventions and tooling. Harbor's five constitutional rules (No.1-No.5: response shape, verification, privacy, security protocol, analysis is read-only) still apply here; they never yield (contracts/marker.md, harbor#581). Global-log and other ambient-engine hooks do not act in this repo."
fi

# L0-11 · this session's OWN record: the launch tree is labelled `src=launch` (a guess) until the first write replaces it with `src=write` (the PostToolUse branch above).
PEER_PID=""
if [ -d "$CFG/sessions" ] && command -v jq >/dev/null 2>&1; then
  # Correlate to the registry ONCE, at SessionStart, by sessionId and never `name` (display text, not identity; harbor#75).
  for _sf in "$CFG"/sessions/*.json; do
    [ -f "$_sf" ] || continue
    if [ "$(jq -r '.sessionId // empty' "$_sf" 2>/dev/null)" = "$SID" ]; then
      PEER_PID="$(jq -r '.pid // empty' "$_sf" 2>/dev/null)"; break
    fi
  done
fi
_lcwd="${CLAUDE_PROJECT_DIR:-$(floor_field '.cwd')}"
[ -n "$_lcwd" ] || _lcwd="$PWD"
peer_write "$(git -C "$_lcwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$_lcwd")" launch

# THE REPORT names every OTHER live session and its tree; it does not claim which tree THIS one will end up in (nothing is written yet, and a warning that guesses is worse than silence, harbor#75).
# Failure is silence: context-peers.sh needs jq and a `ps` per session, so where it cannot answer this prints nothing rather than a count it did not measure.
PEERS=""
if [ -x "$DIR/context-peers.sh" ] || [ -f "$DIR/context-peers.sh" ]; then
  PEERS="$(HARBOR_CONTEXT_PEER_EXCLUDE="$SID" sh "$DIR/context-peers.sh" --peers 2>/dev/null || true)"
fi
if [ -n "$PEERS" ] || [ -n "$DEFER_MSG" ]; then
  _msg="$DEFER_MSG"
  if [ -n "$PEERS" ]; then
    [ -n "$_msg" ] && _msg="$_msg
"
    _msg="$_msg$PEERS"
  fi
  # jq builds the JSON: the message carries paths and branch names (operator data), and hand-quoting those into JSON is the injection shape CONSTITUTION 4 names.
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "$_msg" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' 2>/dev/null || true
  fi
fi

mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
# Atomic: truncating in place leaves a window where the file exists and is empty, which is read as unknown (stand down): an intermittent stand-down almost impossible to reproduce.
_tmp="$CTX_DIR/.$SID.$$"
printf '%s\n' "$VERDICT" > "$_tmp" 2>/dev/null || exit 0
mv -f "$_tmp" "$CTX_DIR/$SID" 2>/dev/null || rm -f "$_tmp"

# Reap stale entries (older than a day); failure is ignored, since housekeeping must never affect the verdict already written.
find "$CTX_DIR" -type f -mtime +1 -exec rm -f {} + 2>/dev/null || true
# Peer records need the same reaping: a dead session's record is a GHOST PEER, and a collision warning that cries wolf goes unread (context-peers.sh also cross-checks liveness).
# `! -type d`, NOT `-type f`: a FIFO is not a regular file, so `-type f` walked past a planted one forever (P13-peer-08).
find "$PEER_DIR" ! -type d -mtime +1 -exec rm -f {} + 2>/dev/null || true
exit 0
