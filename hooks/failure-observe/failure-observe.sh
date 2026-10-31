#!/usr/bin/env sh
# FO-1 (harbor#465) — the PostToolUseFailure sink: one durable record per failed
# tool call, in the shape floor-observe.sh established.
#
# WHAT WAS MISSING, AND IT IS NOT WHAT IT LOOKS LIKE. Harbor already registers,
# analyses and notifies end to end: floor-observe.sh writes guard-decisions.jsonl,
# audit-triage.sh judges it, audit-triage-run.sh runs that daily, session-verdicts.sh
# speaks the verdict. All of it works. It watches GUARD DECISIONS — what the floor
# decided ABOUT a call — and records nothing about what the call then DID. So a
# Read on a path that resolves to nothing, a Bash command exiting non-zero, a
# skill invoked by a name that no longer exists: none of them leave a trace
# anywhere. That is precisely harbor#462's class. Ten dead constitution pointers
# were followed by sessions for 34 days; every follow was a tool call that found
# nothing, and not one of them was written down.
#
# `PostToolUseFailure` was already wired, under matcher `.*`, to inject-hook.sh
# ALONE — which emits a note into the session and a dedup marker, both of which
# die with the session. The event carries what a ledger needs and nobody was
# keeping it.
#
# REGISTER AND ANALYSE. NEVER REPAIR. CONSTITUTION "Encoding a fix is a
# human-gated act", and this repo carries the receipt: pass 9's fixes were
# applied confidently and pass 10 found ~24 defects caused by them, with a green
# suite throughout. A ledger that quietly repaired the harbor#462 citations would
# have rewritten the constitution on its own authority AND GOTTEN IT WRONG — the
# correct repair was to declare a root, not to delete ten pointers.
#
# ── FIVE PROPERTIES INHERITED FROM THE GUARD LEDGER, NOT REINVENTED ─────────
#
# 1. THIS SCRIPT CREATES NOTHING. floor-observe.sh is the only component allowed
#    to create, at SessionStart, where a fork costs nothing and no verdict is
#    pending. It holds the host directory at 0500 for the rest of the session, so
#    an append into an existing 0600 file works and a create does not. A recorder
#    that could create could be made to create somewhere else.
#
# 2. THE SINK FOLLOWS THE WRITER ($0), NOT THE CALLER'S ENVIRONMENT. Measured
#    2026-08-25 on the guard ledger: 1,723 records in one day written by suite
#    copies into the operator's real ledger, because the sink was resolved from
#    $CLAUDE_CONFIG_DIR. Per-suite isolation cannot fix that — a caller running
#    `env -i` strips the variable by construction — so the sink is derived from
#    this script's own path. A checkout has no MEMORY/OBSERVABILITY tree, so a
#    copy run from one is BLIND rather than misfiled.
#
# 3. THE RECURRENCE KEY IS THE TOOL AND ITS INPUT, NEVER THE WHOLE PAYLOAD. The
#    payload carries session_id and cwd, so hashing it would give the same failing
#    call a different digest in every session — and recurrence counting, the one
#    thing the digest exists for, would be dead on arrival. library-admission.sh already
#    learned this; the comment above floor_obs_digest says so in those words.
#
# 4. SALTED, NOT TRUNCATED. Same argument as the guard ledger's: an unsalted
#    truncated hash of a low-entropy input is a confirmation oracle, not a
#    redaction. The salt is the same per-install 128 bits, deliberately never
#    rotated — rotating it would silently reset every recurrence count.
#
# 5. EVERY PATH EXITS 0. A hook that fails a session is worse than a ledger with
#    a hole in it, and this one fires on the failure path, where something has
#    already gone wrong for the operator.
#
# ── WHAT THIS RECORDS THAT THE GUARD LEDGER DELIBERATELY DOES NOT ───────────
#
# A READABLE SUBJECT (`k`), and it is the one place this design is wider than the
# ledger it copies. The guard ledger stores a digest and no plaintext at all,
# correctly: floor_block's own stderr tells the operator which commands were
# blocked, so known plaintext is guaranteed and a command is far more sensitive
# than a filename. Here the question the ticket asks is "which tool fails, ON WHAT
# INPUT", and a finding that cannot name the input cannot be acted on — a digest
# would answer "this recurred" and never "this path is dead", which is the whole
# of harbor#462.
#
# So `k` is bounded on purpose and is NOT the input: a file path with $HOME
# replaced by `~`, or the BARE COMMAND NAME of a Bash call with every argument
# discarded, capped at 120 characters and charset-gated. Never content, never
# arguments, never a URL's query. The full input is still only ever present as
# the salted digest.
set -u

# ── the payload, bounded ────────────────────────────────────────────────────
PAYLOAD="$(cat 2>/dev/null | head -c 262144)" || exit 0
[ -n "${PAYLOAD:-}" ] || exit 0

# jq absent means BLIND, never wrong (B9's lesson, one layer in): a recorder that
# cannot parse must write nothing rather than write something unparseable.
command -v jq >/dev/null 2>&1 || exit 0

# ── the config root, derived from THIS FILE (property 2) ────────────────────
CFG="${0%/*}"; CFG="${CFG%/*}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) exit 0 ;; esac

# library-admission.sh is sourced for floor_obs_digest and the tool enum — ONE digest
# implementation and ONE tool vocabulary on this box, not a second spelling that
# drifts. Absent library means exit 0: nothing here has value without it.
[ -f "$CFG/bin/library-admission.sh" ] || exit 0
. "$CFG/bin/library-admission.sh" 2>/dev/null || exit 0

# ── the host partition, read exactly as the hot path reads it ───────────────
# Type-checked before `read`, because a FIFO at this path blocks the builtin the
# same way `>>` blocks, and 2>/dev/null cannot catch a block.
HOST=unknown-host
_ht="$CFG/.helm-obs-host"
if [ -f "$_ht" ] && [ ! -L "$_ht" ]; then
  _hr=""
  { IFS= read -r _hr < "$_ht"; } 2>/dev/null || :
  case "$_hr" in ''|*[!A-Za-z0-9_-]*) ;; *) HOST="$_hr" ;; esac
fi

# THE TWO GATES, IN THIS ORDER. The directory gate is what keeps the file gate's
# answer true one instruction later: a writable host dir means somebody other
# than floor-observe.sh can swap the sink between the check and the append.
ODIR="$CFG/MEMORY/OBSERVABILITY/$HOST"
[ ! -w "$ODIR" ] || exit 0
SINK="$ODIR/tool-failures.jsonl"
{ [ -f "$SINK" ] && [ ! -L "$SINK" ]; } || exit 0

# ── the fields ──────────────────────────────────────────────────────────────
# One jq, tab-separated. @tsv escapes an embedded tab or newline rather than
# forging a field boundary, which a hostile tool_input would otherwise do.
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

# SPLIT BY PARAMETER EXPANSION, NEVER BY `IFS=<tab> read`. Tab is IFS WHITESPACE
# in POSIX sh, so a run of tabs collapses to one delimiter and an EMPTY field
# shifts every field after it one place left. Measured by this file's own suite:
# a failure whose `error` is the empty string moved the subject into the session
# slot and left the digest subject empty, floor_obs_digest returned "-", and the
# record was dropped — so every tool that fails without an error MESSAGE would
# have been silently absent from the ledger. `read -r a b c d` on `A\tB\t\tD`
# assigns c=D, verified directly. This split preserves empties.
# Written out rather than wrapped in a helper, because a helper called as
# `F="$(_cut)"` runs in a SUBSHELL and its update to the remainder never reaches
# this scope — so every field came back as the first one. That was the first fix
# for the bug above and it was worse than the bug.
_r="$FIELDS"
F_TOOL="${_r%%"$_TAB"*}"; _r="${_r#*"$_TAB"}"
F_INT="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_MS="${_r%%"$_TAB"*}";   _r="${_r#*"$_TAB"}"
F_KEY="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_ERR="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_SID="${_r%%"$_TAB"*}";  _r="${_r#*"$_TAB"}"
F_SUBJ="$_r"
# @tsv escapes a literal tab inside a field as `\t`, so a tab surviving in the
# LAST field means the row had more columns than this split expects — a shape
# nothing here understands. Dropped, rather than filed under fields that have
# quietly shifted.
case "$F_SUBJ" in *"$_TAB"*) exit 0 ;; esac

# ── an INTERRUPT IS NOT A FAILURE, and this is the first thing checked ──────
# `is_interrupt` is the operator pressing Ctrl+C. Counting it would make the
# busiest signal in the ledger a record of the operator changing their mind, and
# a ledger whose loudest finding is noise is one that gets muted (No.2.11).
[ "${F_INT:-0}" = "1" ] && exit 0

# ── the tool: gated and capped, NOT matched against an enum ────────────────
# tool_name is attacker-shaped for exactly one family. `mcp__server__tool` takes
# its middle from a repo-supplied .mcp.json, so only its charset-gated, capped server
# segment survives (below); the tool part never does.
#
# EVERY OTHER TOOL NAME COMES FROM THE HARNESS, and that is why this does NOT
# reuse FLOOR_OBS_TOOLS. That enum bounds cardinality against names an attacker
# could choose, and once mcp__* is mapped there is no such name left here. What a
# hand-listed enum WOULD do is relabel every tool the list has not caught up with
# as `other` — and the first casualty is measured, not hypothetical: `Read` is
# absent from FLOOR_OBS_TOOLS, correctly, because no guard gates a read. A read
# that finds nothing is the whole of harbor#462, so a ledger built on that enum
# would file the single most important failure class on this box under `other`.
# A stale enum is blindness aimed precisely at the newest tool, which is the one
# most likely to be failing.
_t="${F_TOOL:-none}"
# The MCP SERVER segment alone is kept (`mcp__<server>`): enough to say WHICH server fails, never the tool or any argument.
# Charset-gated and capped like every other tool name; a server that fails either gate stays the bare constant `mcp`.
case "$_t" in
  '')          _t=none ;;
  mcp__*)      _srv="${_t#mcp__}"; _srv="${_srv%%__*}"
               case "$_srv" in ''|*[!A-Za-z0-9_-]*) _t=mcp ;; *) _t="mcp__$_srv" ;; esac
               [ "${#_t}" -le 40 ] || _t=mcp ;;
  *[!A-Za-z0-9_]*) _t=other ;;
esac
[ "${#_t}" -le 40 ] || _t=other

# ── the error CLASS, never the error text ──────────────────────────────────
# An enum, for the same reason the guard ledger's verdicts are one: free text
# from a failing tool is unbounded, frequently carries the very path or payload
# that failed, and cannot be grouped. Six classes, ordered most-specific first.
#
# `blocked` exists so the two ledgers do not double-count. A floor block reaches
# this event as a failure AND is already one record in guard-decisions.jsonl;
# without a class of its own it would inflate every count here with decisions
# that are, by design, working exactly as intended.
case "$F_ERR" in
  *"helm floor"*|*"blocked"*|*"permission to use"*|*"requested permissions"*) _e=blocked ;;
  *"no such file"*|*"does not exist"*|*"not found"*|*"enoent"*)               _e=not-found ;;
  *"permission denied"*|*"eacces"*|*"operation not permitted"*)               _e=permission ;;
  *"timed out"*|*"timeout"*|*"etimedout"*)                                    _e=timeout ;;
  *"exit code"*|*"exited with"*|*"non-zero"*)                                 _e=exit-nonzero ;;
  '')                                                                          _e=empty ;;
  *)                                                                           _e=other ;;
esac
# browser-agent's own refusals that hand the next step to the operator (signed out, a hidden window,
# a destructive click, an off-list host): its rules working, not the tool failing. Its server only.
[ "$_t" != mcp__harbor_chrome ] || case "$F_ERR" in *"fail: hand-off:"*) _e=handoff ;; esac

# ── the readable subject, bounded and redacted (see the header) ────────────
_k="${F_KEY:--}"
case "$_k" in "$HOME"/*) _k="~/${_k#"$HOME"/}" ;; "$HOME") _k='~' ;; esac
# A cap by parameter expansion rather than `cut`: no second PATH-resolved binary,
# and 120 characters is past every real path in this estate.
[ "${#_k}" -le 120 ] || _k="$(printf '%.120s' "$_k")"
# The charset gate is the injection boundary. jq escapes correctly on emission
# below, so this is defence in depth rather than the only line — but a subject
# that reaches the ledger carrying a control character is one that breaks the
# reader, and a broken reader reports clean.
case "$_k" in ''|*[!A-Za-z0-9_./~@:+-]*) _k=- ;; esac

# ── the digests ─────────────────────────────────────────────────────────────
# Recurrence key: tool + NUL + the input's canonical JSON (property 3). The
# session digest answers "across how many sessions" without the ledger holding a
# session id, and is salted by the same secret for the same reason.
_h=-
FLOOR_OBS_SUBJECT="$F_SUBJ"; export FLOOR_OBS_SUBJECT
{ _h="$(floor_obs_digest "$CFG")"; } 2>/dev/null || _h=-
case "$_h" in *[!0-9abcdef]*|'') _h=- ;; esac

_s=-
FLOOR_OBS_SUBJECT="session:$F_SID"; export FLOOR_OBS_SUBJECT
{ _s="$(floor_obs_digest "$CFG")"; } 2>/dev/null || _s=-
case "$_s" in *[!0-9abcdef]*|'') _s=- ;; esac
unset FLOOR_OBS_SUBJECT

# A record with no recurrence key cannot answer the only question this ledger
# exists for, and a row of dashes is worse than no row: it inflates every count
# while carrying nothing. Dropped, deliberately.
[ "$_h" = "-" ] && exit 0

_ms="${F_MS:-0}"
case "$_ms" in ''|*[!0-9]*) _ms=0 ;; esac

# ── the clock ───────────────────────────────────────────────────────────────
# A malformed clock ABORTS the record rather than writing an unparseable field:
# one dropped record beats a ledger jq refuses to read.
_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || _ts=""
case "$_ts" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *) exit 0 ;;
esac

# ── the record ──────────────────────────────────────────────────────────────
# Built by jq and not printf. Every other field above is enum- or charset-gated,
# but `k` is the one that carries text derived from a tool input, and a `"` in a
# printf template is a forged record — after which the whole file stops parsing
# and every rule downstream reports clean.
_LINE="$(jq -cn --arg ts "$_ts" --arg t "$_t" --arg e "$_e" --arg k "$_k" \
                --arg h "$_h" --arg s "$_s" --argjson ms "$_ms" \
  '{v:1, ts:$ts, t:$t, e:$e, k:$k, h:$h, s:$s, ms:$ms}' 2>/dev/null)" || exit 0
case "$_LINE" in '{'*'}') ;; *) exit 0 ;; esac

{ printf '%s\n' "$_LINE" >> "$SINK"; } 2>/dev/null || :
exit 0
