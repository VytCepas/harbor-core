#!/usr/bin/env sh
# failure-observe.sh: the MCP server segment survives into the ledger (never the tool, never arguments),
# and FC-10 names that server instead of rendering `mcp -> -`.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/audit/triage/fixture.sh"
OBSF="$(mkfixture obs)"
cp "$T_ROOT/hooks/failure-observe/failure-observe.sh" "$OBSF/bin/failure-observe.sh"
printf '%s\n' "$HOST" > "$OBSF/.helm-obs-host"
jq --arg c "/bin/sh $OBSF/bin/failure-observe.sh" \
  '.hooks.PostToolUseFailure=[{matcher:".*",hooks:[{type:"command",command:$c}]}]' \
  "$OBSF/settings.json" > "$OBSF/s.tmp" && mv "$OBSF/s.tmp" "$OBSF/settings.json"
SINK="$OBSF/MEMORY/OBSERVABILITY/$HOST/tool-failures.jsonl"; : > "$SINK"
chmod 0500 "$OBSF/MEMORY/OBSERVABILITY/$HOST"
fail_as() { # <tool_name> <session> [error] — one PostToolUseFailure through the recorder
  jq -cn --arg t "$1" --arg s "$2" --arg e "${3:-Timeout 5000ms exceeded}" \
    '{tool_name:$t, session_id:$s, error:$e, tool_input:{url:"https://secret.example/?q=1"}}' \
    | sh "$OBSF/bin/failure-observe.sh"
}
last_t() { tail -n1 "$SINK" | jq -r '.t'; }

t_section "the recorder keeps the MCP server and nothing else"
fail_as mcp__harbor_chrome__goto s1
t_eq "mcp__<server>__<tool> keeps the server" mcp__harbor_chrome "$(last_t)"
t_eq "no argument or value reaches the ledger" 0 "$(grep -c 'secret.example' "$SINK")"
fail_as 'mcp__bad server__x' s1; t_eq "a server failing the charset gate stays bare mcp" mcp "$(last_t)"
fail_as "mcp__$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41)__x" s1
t_eq "an over-long server stays bare mcp" mcp "$(last_t)"
fail_as Read s1 'no such file'; t_eq "a non-MCP tool is untouched" Read "$(last_t)"

t_section "FC-10 names the server, with a remedy that fits a tool"
FM="$(mkfixture fc10mcp)"
mkdir -p "$FM/MEMORY/OBSERVABILITY/$HOST"
cp "$OBSF/bin/failure-observe.sh" "$FM/bin/"; printf '%s\n' "$HOST" > "$FM/.helm-obs-host"
jq --arg c "/bin/sh $FM/bin/failure-observe.sh" \
  '.hooks.PostToolUseFailure=[{matcher:".*",hooks:[{type:"command",command:$c}]}]' \
  "$FM/settings.json" > "$FM/s.tmp" && mv "$FM/s.tmp" "$FM/settings.json"
OBSF="$FM"; SINK="$FM/MEMORY/OBSERVABILITY/$HOST/tool-failures.jsonl"; : > "$SINK"
chmod 0500 "$FM/MEMORY/OBSERVABILITY/$HOST"
for s in a b c; do fail_as mcp__harbor_chrome__goto "$s"; done
t_eq "FC-10 fires on the repeated MCP failure" yes "$(has_rule "$FM" FC-10)"
t_has "the subject names the server" "$(subj_of "$FM" FC-10)" "harbor_chrome"
t_hasnt "and is not the bare 'mcp -> -'" "$(subj_of "$FM" FC-10)" "mcp → -"
t_hasnt "the remedy is not path-oriented" "$(repair_of "$FM" FC-10)" "pointer"
t_has "the remedy tells you to look at the server" "$(repair_of "$FM" FC-10)" "MCP server"
t_done
