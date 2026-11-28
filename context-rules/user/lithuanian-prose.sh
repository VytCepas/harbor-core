#!/usr/bin/env sh
# 68-lithuanian-prose (harbor#1572) — a call that writes Lithuanian text is told to run it through bin/doc-lithuanian-rewrite.sh first.
# Silent below six Lithuanian-only letters and on the call that runs the rewrite. The first note of a session carries the
# rules and the engine sends it once per context (`once: context`: a compaction re-arms it); a call with no session id gets one line.
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
# No session id means the engine keeps no ledger: the one-line note, since the rules on every call would repeat a kilobyte each time.
if [ -z "$SID" ]; then
  printf '%s\n' "Lithuanian text: write it to a file, then rewrite it with $RUN; use its output only on exit 0 (exit 3 prints nothing: rewrite by hand from the rules in ~/.claude/skills/doc-lithuanian-prose/SKILL.md, never into it)."
  exit 0
fi
printf '%s\n' "Lithuanian text: before it goes out to a person (mail, DM, comment, document), write it to a file and rewrite it with $RUN; use its output only on exit 0. The rewrite keeps every number, URL, identifier, „quoted“ and \`code\` span and every apostrophe term (event'as, tag'ą); if any of them changed it exits 3 and prints nothing, and the text is rewritten by hand from the skill. Write the draft to these rules in the first place: first sentence is the verdict; every action gets a person and a finite verb (Duomenis perkeliu, not vykdomas perkėlimas); plain words (dabar, kadangi, jei reikės — never šiuo metu, atsižvelgiant į tai, esant poreikiui); one-word hedges (turbūt, vargu ar); English jargon keeps its apostrophe ending and is never translated; literal identifiers are never declined; first person singular for the operator's own work; no irony or rhetorical questions to clients. Full rules: ~/.claude/skills/doc-lithuanian-prose/SKILL.md."
