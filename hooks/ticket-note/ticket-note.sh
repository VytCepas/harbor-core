#!/usr/bin/env sh
# ticket-note (harbor#354) — Stop hook. When a session touched a ticket, remind the operator
# to move it, and name the mechanism that actually closes it.
# Stop fires at the end of EVERY TURN (verified against the binary, 2.1.245), so an unconditional reminder would print every turn and be switched off (No.2 clause 11): it speaks only when a ticket IDENTIFIER is present, once per distinct id set per session.
# Never blocks (systemMessage to the operator, exit 0 on every path). Persists no transcript content: dedup state is a DIGEST of the id set (DEAD-ENDS DE-16).
# Falsifier: a session naming a GitHub issue produces no note, or one naming none produces one. Non-GitHub trackers are not core's (harbor#1273).
# Removed notes: docs/explanation/code-cases/hooks-ticket-note-ticket-note.md
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CFG/cache/ticket-note"

# -- the off switch (harbor#362) -- a switch in a file the installer owns is not a switch (an edited-in `exit 0` was overwritten and a second copy wired). Two spellings:
#   TICKET_NOTE=off        for one run, or exported from a settings `env` block.
#   $CFG/ticket-note.off   sentinel file; NO INSTALLER WRITES OR REMOVES IT, so it survives a reinstall, and the installer declines to wire the hook while it exists.
# Silent and zero: a hook announcing it is disabled is the noise the operator asked to stop.
case "${TICKET_NOTE:-on}" in
  off|OFF|0|no|false) exit 0 ;;
esac
[ -e "$CFG/ticket-note.off" ] && exit 0

# Absolute paths and BSD grep: `grep` here is ugrep, which skips binary/gitignored files, and a hook inherits no profile PATH.
JQ=/usr/bin/jq
GREP=/usr/bin/grep
[ -x "$JQ" ]   || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -x "$GREP" ] || GREP="$(command -v grep 2>/dev/null || printf '')"
[ -n "$JQ" ] && [ -n "$GREP" ] || exit 0

# The scan window is 10 MB: the expression costs ~0.1 s per MB, covering the p95 transcript in under a second against a 10 s hook timeout, and a hook over its timeout is SKIPPED (docs/explanation/admission-baseline.md).
# Above the window it degrades to a tail AND SAYS SO in the note, so a partial scan never reads as a full one.
SCAN_MAX="${TICKET_NOTE_SCAN_MAX:-10000000}"
MAX_SHOW="${TICKET_NOTE_MAX_SHOW:-6}"

# Owners: a GitHub URL alone is not the operator's ticket (research drags in other people's issues, e.g. apache/superset#13003). Falsifier: work on a repo under a fourth owner produces no GitHub line.
# The operator's own account is core's; any other owner is the private layer's (github_owners in harbor.toml,
# contracts/private-layer.md), read through the resolver beside this script. No resolver or no key: the account alone.
GH_OWNERS="${TICKET_NOTE_GH_OWNERS:-}"
if [ -z "$GH_OWNERS" ]; then
  GH_OWNERS="VytCepas"
  case "$0" in */*) _hd="${0%/*}" ;; *) _hd=. ;; esac
  [ ! -f "$_hd/manifest.tsv" ] || _hd="$_hd/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
  if [ -f "$_hd/scope-roots.sh" ]; then
    _more="$(sh "$_hd/scope-roots.sh" --conf github_owners 2>/dev/null | paste -sd'|' - 2>/dev/null || true)"
    [ -z "$_more" ] || GH_OWNERS="$GH_OWNERS|$_more"
  fi
fi

PAYLOAD="$(cat 2>/dev/null)" || exit 0
[ -n "$PAYLOAD" ] || exit 0

pfield() { printf '%s' "$PAYLOAD" | "$JQ" -r "$1" 2>/dev/null || printf ''; }

SID="$(pfield '.session_id // ""')"
TRANSCRIPT="$(pfield '.transcript_path // ""')"
ACTIVE="$(pfield '.stop_hook_active // false')"

# Loop guard, though this hook never blocks: the harness sets stop_hook_active during a Stop continuation.
[ "$ACTIVE" = "true" ] && exit 0

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# ONE pass: shapes are alternated into one expression, then the classifying greps run over the tiny MATCH LIST. -a because a NUL byte would make a binary-mode skip answer "no tickets" silently.
SHAPES="github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+"
SHAPES="$SHAPES|gh (issue|pr) (close|reopen|edit|comment|develop|merge|ready) +#?[0-9]+"

TRUNC=0
SIZE="$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
if [ "$SIZE" -gt "$SCAN_MAX" ]; then
  TRUNC=1
  MATCHES="$(tail -c "$SCAN_MAX" "$TRANSCRIPT" 2>/dev/null | LC_ALL=C "$GREP" -Eao "$SHAPES" 2>/dev/null)"
else
  MATCHES="$(LC_ALL=C "$GREP" -Eao "$SHAPES" "$TRANSCRIPT" 2>/dev/null)"
fi
[ -n "$MATCHES" ] || exit 0

# The regex is the whitelist: ids are matched out of [A-Za-z0-9._-], '/' and '#', so no transcript text reaches the message with a quote, backslash or newline.
# A full URL names its repo; a bare `gh issue close 152` does not, so it renders as gh#N. The owner filter is a separate -i pass: -i on the whole expression would loosen the verb words.
GH_URLS="$(printf '%s' "$MATCHES" \
  | LC_ALL=C "$GREP" -Eo 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+' 2>/dev/null \
  | LC_ALL=C "$GREP" -iE "^github\.com/($GH_OWNERS)/" 2>/dev/null \
  | LC_ALL=C sed -E -e 's@^github\.com/@@' -e 's@/(issues|pull)/@#@' \
  | LC_ALL=C sort -u)"
# Only verbs that ACT on an issue: `view`/`list` is how research reads someone else's tracker.
GH_CMDS="$(printf '%s' "$MATCHES" \
  | LC_ALL=C "$GREP" -Eo 'gh (issue|pr) (close|reopen|edit|comment|develop|merge|ready) +#?[0-9]+' 2>/dev/null \
  | LC_ALL=C "$GREP" -Eo '[0-9]+$' 2>/dev/null \
  | LC_ALL=C sed -e 's|^|gh#|' \
  | LC_ALL=C sort -u)"
GH_IDS="$(printf '%s\n%s\n' "$GH_URLS" "$GH_CMDS" | LC_ALL=C sed '/^$/d' | LC_ALL=C sort -u)"

[ -n "$GH_IDS" ] || exit 0

ALL="$GH_IDS"
COUNT="$(printf '%s\n' "$ALL" | LC_ALL=C wc -l | tr -d ' ')"

# Once per distinct id SET per session: a new ticket re-arms the note.
KEY="$(printf '%s' "$ALL" | /usr/bin/shasum -a 256 2>/dev/null | cut -d' ' -f1)"
[ -n "$KEY" ] || KEY="$(printf '%s' "$ALL" | cksum | tr -d ' ')"
SAFE_SID="$(printf '%s' "$SID" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
[ -n "$SAFE_SID" ] || SAFE_SID=unknown
STATE="$STATE_DIR/$SAFE_SID"
# A state dir this cannot write must not silently disable the hook: dedup degrades to off and the note says so.
DEDUP=1
mkdir -p "$STATE_DIR" 2>/dev/null || DEDUP=0
[ "$DEDUP" = 1 ] && [ ! -w "$STATE_DIR" ] && DEDUP=0
if [ "$DEDUP" = 1 ] && [ -f "$STATE" ]; then
  [ "$(cat "$STATE" 2>/dev/null)" = "$KEY" ] && exit 0
fi

SHOWN="$(printf '%s\n' "$ALL" | head -n "$MAX_SHOW" | tr '\n' ' ' | sed -e 's/ $//' -e 's/ /, /g')"
MORE=""
[ "$COUNT" -gt "$MAX_SHOW" ] && MORE=" (+$((COUNT - MAX_SHOW)) more)"

# -- the message (harbor#362) -- only what the reader cannot derive then: the ids touched and the command that closes them; reference text lives in the dev-tracking skill.
MSG="Tickets: ${SHOWN}${MORE}
  GitHub   gh issue close <n>"
if [ "$TRUNC" = 1 ]; then
  MSG="$MSG
  (ticket-note: transcript over ${SCAN_MAX}B — only the last ${SCAN_MAX}B was scanned,
  so an earlier ticket may be missing from the list above.)"
fi
if [ "$DEDUP" = 0 ]; then
  MSG="$MSG
  (ticket-note: $STATE_DIR is not writable, so this repeats every turn until fixed.)"
fi

printf '%s' "$MSG" | "$JQ" -Rs '{systemMessage: .}' 2>/dev/null || exit 0
# Temp-then-rename: a half-written digest read by a concurrent Stop would re-arm the note.
if [ "$DEDUP" = 1 ]; then
  printf '%s\n' "$KEY" > "$STATE.$$" 2>/dev/null && mv -f "$STATE.$$" "$STATE" 2>/dev/null || true
fi
exit 0
