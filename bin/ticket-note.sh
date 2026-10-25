#!/usr/bin/env sh
# ticket-note (harbor#354) — Stop hook. When a session touched a ticket, remind the operator
# to move it, and name the mechanism that actually closes it.
#
# WHY IT IS GATED, AND WHY THAT IS NOT OPTIONAL. Stop fires at the end of EVERY
# TURN, not at the end of the session. Verified against the binary here, 2.1.245,
# rather than taken from a doc: its own summaries are Stop = "Right before Claude
# concludes its response" and SessionEnd = "When a session is ending". An
# unconditional reminder would therefore print on every turn of every session,
# and a guard that fires on ordinary work gets switched off — CONSTITUTION No.2
# clause 11. So it speaks only when a ticket IDENTIFIER is present, and only
# once per distinct set of identifiers per session.
#
# IT NEVER BLOCKS. The audience is the operator, not the model, so the channel
# is systemMessage and the exit status is 0 on every path. A reminder is a
# finding, never an order.
#
# IT PERSISTS NO TRANSCRIPT CONTENT. The dedup state is a DIGEST of the id set,
# never the ids themselves: DEAD-ENDS DE-16 rejected building a durable corpus
# out of transcript content, and a hash is not a corpus. The ids in the message
# are recomputed from the transcript each run and stored nowhere.
#
# Falsifier: a session that names a GitHub issue produces no note, or a session
# that names none produces one. A ticket tracker other than GitHub is not core's
# (harbor#1273): its nudge, if any, belongs to the pack that carries its tool.
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CFG/cache/ticket-note"

# ── THE OFF SWITCH (harbor#362) ─────────────────────────────────────────────
# THIS EXISTS BECAUSE ITS ABSENCE WAS EXPLOITED BY ITS OWN INSTALLER. The operator
# turned this hook off on 2026-08-25 the only way available — an `exit 0` edited
# into the script body — and `runtime-install` overwrote the file the next day and
# wired a second, undisabled copy beside it. Two entries in `.hooks.Stop`, the
# reminder back, and no record that anyone had asked it to stop. A switch that
# lives in a file the installer owns is not a switch.
#
# TWO SPELLINGS, AND THE DIFFERENCE IS DURABILITY, NOT PREFERENCE:
#   TICKET_NOTE=off        for one run, or exported from a settings `env` block.
#   $CFG/ticket-note.off   a sentinel file. NO INSTALLER WRITES OR REMOVES IT, so
#                          it survives a reinstall — which the env var alone does
#                          not, and surviving the reinstall is the whole ticket.
# The installer also reads the sentinel and declines to wire the hook at all, so
# turning it off does not leave a wired hook exiting silently forever.
#
# SILENT AND ZERO. No message, no stderr, exit 0 — a hook announcing that it is
# disabled is the noise the operator just asked to stop.
case "${TICKET_NOTE:-on}" in
  off|OFF|0|no|false) exit 0 ;;
esac
[ -e "$CFG/ticket-note.off" ] && exit 0

# Absolute paths, and BSD grep specifically. `grep` on this box is ugrep, which
# skips binary and gitignored files — a negative from it is not evidence, and
# this hook's whole output rests on a match/no-match decision. A hook also
# inherits no shell profile, so PATH is not to be trusted for jq either.
JQ=/usr/bin/jq
GREP=/usr/bin/grep
[ -x "$JQ" ]   || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -x "$GREP" ] || GREP="$(command -v grep 2>/dev/null || printf '')"
[ -n "$JQ" ] && [ -n "$GREP" ] || exit 0

# THE WINDOW IS 10 MB, AND THE NUMBER IS MEASURED, NOT PICKED. On this box
# 2026-08-25: 122 transcripts, median 0.6 MB, p95 9.9 MB, max 87 MB. The
# expression below (five shapes when measured) costs ~0.1s per MB (1 MB 0.10s, 5 MB 0.49s,
# 10 MB 0.95s, 20 MB 2.01s), so 10 MB covers the 95th percentile ENTIRELY at
# under a second, against a 10s hook timeout.
#
# A full pass was tried first and rejected: 87 MB took 7.3s, and FLOOR.md's
# finding is that a hook exceeding its timeout is SKIPPED — latency here is not
# discomfort, it is the check silently switching itself off. A `grep -F`
# prefilter was tried too and bought nothing (7.1s): `86` appears on nearly
# every line of a uuid-laden JSONL, so it filters nothing.
#
# Above the window it degrades to a tail AND SAYS SO in the note: a window that
# silently covered part of a session reads exactly like one that covered all.
SCAN_MAX="${TICKET_NOTE_SCAN_MAX:-10000000}"
MAX_SHOW="${TICKET_NOTE_MAX_SHOW:-6}"

# OWNERS, BECAUSE A GITHUB URL ALONE IS NOT THE OPERATOR'S TICKET. Reading
# research during a session drags in other people's issues, and the first
# version happily reminded about them: a real 87 MB transcript yielded
# apache/superset#13003, facebook/react#10191 and ten
# more — every single URL match was third-party. Derived 2026-08-25 from the
# actual origin remotes of the checkouts on this box, not from recall.
# Falsifier: work on a repo under a fourth owner produces no GitHub line.
# The operator's own account is core's; any other owner is the private layer's (github_owners in harbor.toml,
# CONTRACTS/private-layer.md), read through the resolver beside this script. No resolver or no key: the account alone.
GH_OWNERS="${TICKET_NOTE_GH_OWNERS:-}"
if [ -z "$GH_OWNERS" ]; then
  GH_OWNERS="VytCepas"
  case "$0" in */*) _hd="${0%/*}" ;; *) _hd=. ;; esac
  if [ -f "$_hd/roots.sh" ]; then
    _more="$(sh "$_hd/roots.sh" --conf github_owners 2>/dev/null | paste -sd'|' - 2>/dev/null || true)"
    [ -z "$_more" ] || GH_OWNERS="$GH_OWNERS|$_more"
  fi
fi

PAYLOAD="$(cat 2>/dev/null)" || exit 0
[ -n "$PAYLOAD" ] || exit 0

pfield() { printf '%s' "$PAYLOAD" | "$JQ" -r "$1" 2>/dev/null || printf ''; }

SID="$(pfield '.session_id // ""')"
TRANSCRIPT="$(pfield '.transcript_path // ""')"
ACTIVE="$(pfield '.stop_hook_active // false')"

# The loop guard, even though this hook never blocks: the harness sets it while
# a Stop continuation is running, and a hook that ignores it is a hook whose
# bound belongs to somebody else's cap rather than to its author.
[ "$ACTIVE" = "true" ] && exit 0

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# ONE pass over the file. The shapes below are alternated into a
# single expression so a big transcript is read once; the classifying greps then
# run over the MATCH LIST, which is tens of bytes. -a because a transcript can
# carry NUL bytes and a binary-mode skip would answer "no tickets" silently
# (both /usr/bin/grep and the ugrep fallback accept -a; verified).
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

# THE REGEX IS THE WHITELIST. Every id that reaches the message is matched out
# of [A-Za-z0-9._-], '/' and '#' only, so no transcript text can carry a quote,
# a backslash or a newline into the message it is interpolated into.
#
# Two GitHub shapes: a full issue or PR URL, which names its repo, and a bare
# `gh issue close 152`, which does not. Both are ticket work; only the first can
# be attributed, so the second is rendered as gh#N rather than guessed at.
# The owner filter is a SEPARATE, case-insensitive pass over the tiny match
# list, deliberately not folded into the pattern above: -i on the whole
# expression would also loosen the verb words, and `GH ISSUE CLOSE` is not typed.
GH_URLS="$(printf '%s' "$MATCHES" \
  | LC_ALL=C "$GREP" -Eo 'github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+' 2>/dev/null \
  | LC_ALL=C "$GREP" -iE "^github\.com/($GH_OWNERS)/" 2>/dev/null \
  | LC_ALL=C sed -E -e 's@^github\.com/@@' -e 's@/(issues|pull)/@#@' \
  | LC_ALL=C sort -u)"
# Only verbs that ACT on an issue. `gh issue view` and `gh issue list` are how
# research reads someone else's tracker; close/reopen/edit/comment/develop are
# things you only do to a ticket you own.
GH_CMDS="$(printf '%s' "$MATCHES" \
  | LC_ALL=C "$GREP" -Eo 'gh (issue|pr) (close|reopen|edit|comment|develop|merge|ready) +#?[0-9]+' 2>/dev/null \
  | LC_ALL=C "$GREP" -Eo '[0-9]+$' 2>/dev/null \
  | LC_ALL=C sed -e 's|^|gh#|' \
  | LC_ALL=C sort -u)"
GH_IDS="$(printf '%s\n%s\n' "$GH_URLS" "$GH_CMDS" | LC_ALL=C sed '/^$/d' | LC_ALL=C sort -u)"

[ -n "$GH_IDS" ] || exit 0

ALL="$GH_IDS"
COUNT="$(printf '%s\n' "$ALL" | LC_ALL=C wc -l | tr -d ' ')"

# Once per distinct id SET per session. A new ticket entering the session
# re-arms the note; a further turn on the same tickets does not.
KEY="$(printf '%s' "$ALL" | /usr/bin/shasum -a 256 2>/dev/null | cut -d' ' -f1)"
[ -n "$KEY" ] || KEY="$(printf '%s' "$ALL" | cksum | tr -d ' ')"
SAFE_SID="$(printf '%s' "$SID" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
[ -n "$SAFE_SID" ] || SAFE_SID=unknown
STATE="$STATE_DIR/$SAFE_SID"
# A STATE DIR THIS CANNOT WRITE MUST NOT SILENTLY DISABLE THE HOOK. The first
# version exited 0 there, which is the shape the doctrine calls worst: a check
# that stops running without saying so. So dedup degrades to off and the note
# says it degraded — noisy and fixable beats quiet and gone.
DEDUP=1
mkdir -p "$STATE_DIR" 2>/dev/null || DEDUP=0
[ "$DEDUP" = 1 ] && [ ! -w "$STATE_DIR" ] && DEDUP=0
if [ "$DEDUP" = 1 ] && [ -f "$STATE" ]; then
  [ "$(cat "$STATE" 2>/dev/null)" = "$KEY" ] && exit 0
fi

SHOWN="$(printf '%s\n' "$ALL" | head -n "$MAX_SHOW" | tr '\n' ' ' | sed -e 's/ $//' -e 's/ /, /g')"
MORE=""
[ "$COUNT" -gt "$MAX_SHOW" ] && MORE=" (+$((COUNT - MAX_SHOW)) more)"

# ── THE MESSAGE (harbor#362, trimmed 2026-08-30) ────────────────────────────
# WAS 10 LINES AND 767 BYTES, AT THE END OF EVERY TURN THAT NAMED A TICKET, and
# only the first of those lines was session state. The rest was REFERENCE re-read
# aloud each time — the half-hourly format, what -b means, `cu doctor`, the
# EPICS-only mirroring rule, FIXED/IN PROGRESS/NOT FIXED, the alert-thread line —
# all of it already in the dev-tracking skill and the operator memory that loads
# every session. A reminder that restates a rule the reader already has is how a
# gate on ordinary work earns itself an off switch (No.2 clause 11), and this one
# had just been given one.
#
# WHAT SURVIVES IS WHAT THE READER CANNOT DERIVE AT THAT MOMENT: which ids this
# session touched, and the command that closes them.
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
# Temp-then-rename: five sessions run on this box at once, and a half-written
# digest read by a concurrent Stop would re-arm the note for no reason.
if [ "$DEDUP" = 1 ]; then
  printf '%s\n' "$KEY" > "$STATE.$$" 2>/dev/null && mv -f "$STATE.$$" "$STATE" 2>/dev/null || true
fi
exit 0
