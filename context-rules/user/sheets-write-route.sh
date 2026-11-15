#!/usr/bin/env sh
# 67-sheets-write-route — opening a Google Sheet in harbor chrome names the write route (harbor#1507).
# Silent for every other URL. FAIL-OPEN like every path in this engine: no jq, no payload, print nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
U="$(printf '%s' "$P" | jq -r '((.tool_input.args // []) + ([(.tool_input.steps // [])[] | (.args // [])[]]))[] | select(type == "string")' 2>/dev/null | tr 'A-Z' 'a-z' || true)"
case "$U" in
  *https://docs.google.com/spreadsheets/*) ;;
  *) exit 0 ;;
esac
printf '%s\n' 'Google Sheets: read it here if you need to, but WRITE cells through the Google Sheets connector (mcp__claude_ai_Google_Sheets__* tools; the operator authorises it once with /mcp), never by typing into the grid: harbor chrome cannot see which cell has focus, and keys have landed in the wrong cells (harbor#1117, #1507). If the connector tools are not listed, say so and ask the operator to authorise it before any write.'
