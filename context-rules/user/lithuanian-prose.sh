#!/usr/bin/env sh
# 68-lithuanian-prose (harbor#1572) — a call that writes Lithuanian text is told to run it through bin/doc-lithuanian-rewrite.sh first.
# Silent below six Lithuanian-only letters and on the call that runs the rewrite. The first note of a session carries the
# rules; the rest, and every call with no session id, are one line (ledger per session, pruned after 7 days).
# FAIL-OPEN like every path in this engine: no jq, no payload, print nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
# Bash's own description field is the agent's English label, not the text being written.
TXT="$(printf '%s' "$P" | jq -r '[(.tool_input // {}) | del(.description) | .. | strings] | join(" ")' 2>/dev/null || true)"
case "$TXT" in *doc-lithuanian-rewrite*) exit 0 ;; esac
N="$(printf '%s' "$P" | jq -r '[(.tool_input // {}) | del(.description) | .. | strings] | join(" ") | [scan("[ąčęėįšųūžĄČĘĖĮŠŲŪŽ]")] | length' 2>/dev/null || echo 0)"
case "$N" in ''|*[!0-9]*) exit 0 ;; esac
[ "$N" -ge 6 ] || exit 0

RUN='sh ~/port/harbor/bin/doc-lithuanian-rewrite.sh FILE (Haiku; --model sonnet for a long or client-facing text)'
SID="$(printf '%s' "$P" | jq -r '.session_id // ""' 2>/dev/null | tr -cd 'A-Za-z0-9_-' || true)"
L="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/lithuanian-prose"
# No session id means no ledger, so the one-line note: the rules on every call would repeat a kilobyte each time.
if [ -z "$SID" ] || [ -f "$L/$SID.seen" ]; then
  printf '%s\n' "Lithuanian text: before it goes out, rewrite it with $RUN and use what it prints."
  exit 0
fi
{ mkdir -p "$L" 2>/dev/null && : > "$L/$SID.seen" 2>/dev/null; } || true
# A ledger outlives its session by a week at most, as skill-first-use's does.
find "$L" -name '*.seen' -mtime +7 -exec rm -f {} + 2>/dev/null || true
printf '%s\n' "Lithuanian text: before it goes out to a person (mail, DM, comment, document), write it to a file and rewrite it with $RUN; use what it prints. The rewrite keeps every number, URL, identifier, „quoted“ and \`code\` span and every apostrophe term (event'as, tag'ą), and hands back the original if any of them changed. Write the draft to these rules in the first place: first sentence is the verdict; every action gets a person and a finite verb (Duomenis perkeliu, not vykdomas perkėlimas); plain words (dabar, kadangi, jei reikės — never šiuo metu, atsižvelgiant į tai, esant poreikiui); one-word hedges (turbūt, vargu ar); English jargon keeps its apostrophe ending and is never translated; literal identifiers are never declined; first person singular for the operator's own work; no irony or rhetorical questions to clients. Full rules: ~/.claude/skills/doc-lithuanian-prose/SKILL.md."
