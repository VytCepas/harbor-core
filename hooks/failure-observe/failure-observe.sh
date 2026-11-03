#!/usr/bin/env sh
# FO-1 (harbor#465) — the PostToolUseFailure sink: one durable record per failed
# tool call, in the shape admission-observe.sh established.
# Register and analyse, never repair (CONSTITUTION: encoding a fix is human-gated). admission-observe.sh records guard decisions; this records what a call then DID (harbor#462's dead pointers left no trace).
# Properties inherited from the guard ledger:
# 1. Creates nothing: admission-observe.sh creates the sink at SessionStart and holds the host dir at 0500, so append works and create does not.
# 2. The sink follows $0, not the caller's environment (suite copies once filled the real ledger via $CLAUDE_CONFIG_DIR); a checkout has no MEMORY tree, so a copy is BLIND, not misfiled.
# 3. The recurrence key is tool + input, never the whole payload (session_id and cwd would give every session a different digest).
# 4. Salted digest, never truncated; the salt is never rotated (rotation would reset recurrence counts).
# 5. Every path exits 0.
# `k` is the one readable subject (the guard ledger keeps none): a path with $HOME as `~`, or the bare command name of a Bash call, 120 chars, charset-gated; never content, arguments or URL queries.
# Removed notes: docs/explanation/code-cases/hooks-failure-observe-failure-observe.md
set -u

PAYLOAD="$(cat 2>/dev/null | head -c 262144)" || exit 0
[ -n "${PAYLOAD:-}" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

CFG="${0%/*}"; CFG="${CFG%/*}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) exit 0 ;; esac

# Sourced for floor_obs_digest: one digest implementation on this box. Absent library: exit 0.
[ -f "$CFG/bin/library-admission.sh" ] || exit 0
. "$CFG/bin/library-admission.sh" 2>/dev/null || exit 0

HOST=unknown-host
_ht="$CFG/.helm-obs-host"
if [ -f "$_ht" ] && [ ! -L "$_ht" ]; then
  _hr=""
  { IFS= read -r _hr < "$_ht"; } 2>/dev/null || :
  case "$_hr" in ''|*[!A-Za-z0-9_-]*) ;; *) HOST="$_hr" ;; esac
fi

# Directory gate first: a writable host dir would let another writer swap the sink between the check and the append.
ODIR="$CFG/MEMORY/OBSERVABILITY/$HOST"
[ ! -w "$ODIR" ] || exit 0
SINK="$ODIR/tool-failures.jsonl"
{ [ -f "$SINK" ] && [ ! -L "$SINK" ]; } || exit 0

_TAB="$(printf '\t')"
FIELDS="$(printf '%s' "$PAYLOAD" | jq -r '
  [ (.tool_name // "none"),
    (if (.is_interrupt // false) then "1" else "0" end),
    ((.duration_ms // 0) | tostring),
    ( .tool_input.file_path // .tool_input.notebook_path // .tool_input.path
      // (.tool_input.command | strings | split(" ")[0])
      // "-" ),
    ((.error // "") | ascii_downcase),
    (.session_id // "-"),
    ((.tool_name // "none") + "" + ((.tool_input // {}) | tojson))
  ] | @tsv' 2>/dev/null)" || exit 0
[ -n "${FIELDS:-}" ] || exit 0

# Split by parameter expansion, never `IFS=<tab> read`: tab is IFS whitespace, so an empty field (error "") would shift every later field left.
# Not wrapped in a helper: `F="$(_cut)"` runs in a subshell and loses the remainder update.
_r="$FIELDS"
F_TOOL="${_r%%"$_TAB"*}"; _r="${_r#*"$_TAB"}"
F_INT="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_MS="${_r%%"$_TAB"*}";   _r="${_r#*"$_TAB"}"
F_KEY="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_ERR="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_SID="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_SUBJ="$_r"
case "$F_SUBJ" in *"$_TAB"*) exit 0 ;; esac

# An interrupt (Ctrl+C) is not a failure; counting it would make the loudest signal noise (No.2.11).
[ "${F_INT:-0}" = "1" ] && exit 0

# tool_name is attacker-shaped only for mcp__ (middle from a repo .mcp.json), so only its charset-gated server segment survives.
# Not matched against FLOOR_OBS_TOOLS: that enum lacks Read, and a dead Read is the whole of harbor#462.
_t="${F_TOOL:-none}"
case "$_t" in
  '')          _t=none ;;
  mcp__*)      _srv="${_t#mcp__}"; _srv="${_srv%%__*}"
               case "$_srv" in ''|*[!A-Za-z0-9_-]*) _t=mcp ;; *) _t="mcp__$_srv" ;; esac
               [ "${#_t}" -le 40 ] || _t=mcp ;;
  *[!A-Za-z0-9_]*) _t=other ;;
esac
[ "${#_t}" -le 40 ] || _t=other

# The error CLASS, never the text (unbounded, carries the failing path). Most specific first.
# `blocked` keeps a floor block, already a record in guard-decisions.jsonl, from being double-counted.
case "$F_ERR" in
  *"helm floor"*|*"blocked"*|*"permission to use"*|*"requested permissions"*) _e=blocked ;;
  *"no such file"*|*"does not exist"*|*"not found"*|*"enoent"*)               _e=not-found ;;
  *"permission denied"*|*"eacces"*|*"operation not permitted"*)               _e=permission ;;
  *"timed out"*|*"timeout"*|*"etimedout"*)                                    _e=timeout ;;
  *"exit code"*|*"exited with"*|*"non-zero"*)                                 _e=exit-nonzero ;;
  '')                                                                          _e=empty ;;
  *)                                                                           _e=other ;;
esac
# browser-agent hand-offs (signed out, hidden window, destructive click, off-list host) are its rules working, not the tool failing.
[ "$_t" != mcp__harbor_chrome ] || case "$F_ERR" in *"fail: hand-off:"*) _e=handoff ;; esac

_k="${F_KEY:--}"
case "$_k" in "$HOME"/*) _k="~/${_k#"$HOME"/}" ;; "$HOME") _k='~' ;; esac
[ "${#_k}" -le 120 ] || _k="$(printf '%.120s' "$_k")"
# The charset gate is the injection boundary (defence in depth: jq also escapes on emission).
case "$_k" in ''|*[!A-Za-z0-9_./~@:+-]*) _k=- ;; esac

_h=-
FLOOR_OBS_SUBJECT="$F_SUBJ"; export FLOOR_OBS_SUBJECT
{ _h="$(floor_obs_digest "$CFG")"; } 2>/dev/null || _h=-
case "$_h" in *[!0-9abcdef]*|'') _h=- ;; esac

_s=-
FLOOR_OBS_SUBJECT="session:$F_SID"; export FLOOR_OBS_SUBJECT
{ _s="$(floor_obs_digest "$CFG")"; } 2>/dev/null || _s=-
case "$_s" in *[!0-9abcdef]*|'') _s=- ;; esac
unset FLOOR_OBS_SUBJECT

# No recurrence key, no row: a row of dashes inflates counts and carries nothing.
[ "$_h" = "-" ] && exit 0

_ms="${F_MS:-0}"
case "$_ms" in ''|*[!0-9]*) _ms=0 ;; esac

_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || _ts=""
case "$_ts" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *) exit 0 ;;
esac

# Built by jq, not printf: `k` carries text derived from a tool input and a `"` would forge a record.
_LINE="$(jq -cn --arg ts "$_ts" --arg t "$_t" --arg e "$_e" --arg k "$_k" \
                --arg h "$_h" --arg s "$_s" --argjson ms "$_ms" \
  '{v:1, ts:$ts, t:$t, e:$e, k:$k, h:$h, s:$s, ms:$ms}' 2>/dev/null)" || exit 0
case "$_LINE" in '{'*'}') ;; *) exit 0 ;; esac

{ printf '%s\n' "$_LINE" >> "$SINK"; } 2>/dev/null || :
exit 0
