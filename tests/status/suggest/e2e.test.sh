#!/usr/bin/env sh
# e2e.test.sh (harbor#1485) — the suggestions, end to end: the real installers lay out a config dir, the real engine runs the session-start
# pack, the real stop tool writes the state and the real scan reads it. The one stand-in is the table, the neutral fixture rows, because core
# ships none. Every hook runs the installed copy, as a live session does.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/box"; ST="$T/suggest-state"; BOX="$CFG/context-rules/user"; TOOL="$CFG/bin/status-suggest.sh"
mkdir -p "$CFG"; printf '{}\n' > "$CFG/settings.json"
unset CLAUDE_CONFIG_DIR
t_section "the real installers lay out the box"
t_exit "the runtime installs" 0 sh "$T_ROOT/bin/deploy-runtime-install.sh" --dir "$CFG" --apply
t_exit "the packs install" 0 sh "$T_ROOT/bin/context-injection-install.sh" --dir "$CFG" --apply
t_exit "the stop tool is where hooks call it" 0 test -f "$CFG/bin/status-suggest.sh"
[ -f "$CFG/bin/injection-rule.sh" ] || t_done
cp "$T_ROOT/bin/admission-normalize.awk" "$CFG/bin/"   # the floor's installer lays this; the parser needs it
cp "$T_ROOT/fixtures/suggest/rows.tsv" "$BOX/suggest-rows.tsv"
# The ledger, as the floor leaves it: a sealed host dir, a salt, a host token.
LEDGER="$CFG/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; mkdir -p "${LEDGER%/*}"
printf 'probehost\n' > "$CFG/.helm-obs-host"; printf '0123456789abcdef0123456789abcdef\n' > "$CFG/.helm-obs-salt"
: > "$LEDGER"; chmod 0500 "${LEDGER%/*}"
REPO="$T/repo"; mkdir -p "$REPO"; ( cd "$REPO" && git init -q . )
printf '{}\n' > "$T/tr.jsonl"
awk -F'\t' -v OFS='\t' '$3 == "injection" && $12 == "suggest-start" { $2 = "warn" } { print }' "$CFG/bin/controls.tsv" > "$T/controls-warn.tsv"

CONTROLS=''; SURFACE=cli
# hook <payload>: the installed engine, as the harness calls it; CONTROLS empty reads the installed register, born shadow
hook() {
  printf '%s' "$1" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" HARBOR_STATUS_SUGGEST_DIR="$ST" \
    CLAUDE_CODE_ENTRYPOINT="$SURFACE" ${CONTROLS:+HARBOR_CONTEXT_CONTROLS="$CONTROLS"} /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null
}
start() { hook "$(jq -cn --arg s "$1" --arg src "${2:-startup}" '{hook_event_name:"SessionStart",source:$src,session_id:$s}')"; }
stoptool() { HARBOR_STATUS_SUGGEST_DIR="$ST" sh "$TOOL" "$@" 2>/dev/null; }
msg() { printf '%s' "$1" | jq -r '.systemMessage // empty'; }
note() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
statef() { [ -e "$ST/$1" ] && echo yes || echo no; }

t_section "the pack is born shadow, and the stop tool works through the installed copy"
t_eq "the installed register has the pack in shadow" 'shadow' "$(awk -F'\t' '$3 == "injection" && $12 == "suggest-start" { print $2 }' "$CFG/bin/controls.tsv")"
t_exit "stop, through the installed tool" 0 stoptool stop fixture-verb --origin agent
t_eq "status says so" true "$(stoptool status --json | jq '.rows[] | select(.id == "fixture-verb") | .stopped')"
stoptool start fixture-verb --origin panel
t_eq "start brings it back" false "$(stoptool status --json | jq '.rows[] | select(.id == "fixture-verb") | .stopped')"
stoptool off --origin panel
t_eq "off: status says so" false "$(stoptool status --json | jq '.enabled')"
stoptool on --origin panel
t_eq "on: status says so" true "$(stoptool status --json | jq '.enabled')"

t_section "SessionStart ticks once; 20 sessions make the intro due"
rm -f "$ST/sessions.tsv"
CONTROLS=''
start t0 >/dev/null
t_eq "shadow still counts the session" 1 "$(cut -f1 "$ST/sessions.tsv")"
start t0 >/dev/null
t_eq "the same session starts twice: one tick" 1 "$(cut -f1 "$ST/sessions.tsv")"
start t0r resume >/dev/null
t_eq "a resume is no new session" 1 "$(cut -f1 "$ST/sessions.tsv")"
CONTROLS="$T/controls-warn.tsv"
_o="$(start t1)"
t_has "at warn the agent gets the stop route" "$(note "$_o")" "$TOOL stop <id> --origin agent"
t_eq "and the count moves" 2 "$(cut -f1 "$ST/sessions.tsv")"
i=2; while [ "$i" -lt 19 ]; do i=$((i + 1)); start "t$i" >/dev/null; done
t_eq "19 sessions" 19 "$(cut -f1 "$ST/sessions.tsv")"
t_eq "at 19 the intro is not due" false "$(stoptool status --json | jq '.intro_due')"
start t20 >/dev/null
t_eq "at 20 the intro is due" true "$(stoptool status --json | jq '.intro_due')"
t_eq "and it stays due" true "$(stoptool status --json | jq '.intro_due')"

t_section "a candidate stopped through the tool drops from the next scan"
PJ="$HOME/.claude/projects/-fx"; mkdir -p "$PJ"; NOW="$(jq -n -r 'now | todate')"; n=0
tu() { n=$((n + 1)); printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"i%s","name":"%s","input":%s}]}}\n' "$NOW" "$n" "$2" "$3" >> "$PJ/$1.jsonl"; }
sb() { tu "$1" Bash "$(jq -cn --arg c "$2" '{command:$c}')"; }
for s in 1 2 3 4 5; do tu "a$s" mcp__fx__read '{}'; tu "a$s" Write '{"file_path":"/x/a.md"}'; done
for s in 1 2 3 4; do sb "b$s" 'python3 a.py'; sb "b$s" 'curl -s x.example'; done
for s in 1 2 3; do sb "c$s" 'docker ps'; tu "c$s" mcp__fx__read '{}'; sb "c$s" 'docker ps'; tu "c$s" mcp__fx__read '{}'; done
for s in 1 2 3; do sb "d$s" 'npm test'; sb "d$s" 'gh pr view'; done
# The pane's own argv: --live, the state folder by variable.
scan() { HARBOR_STATUS_SUGGEST_DIR="$ST" sh "$T_ROOT/bin/status-suggest-scan.sh" --json --live 2>/dev/null; }
_s="$(scan)"; TOP="$(printf '%s' "$_s" | jq -r '.candidates[0].id')"
t_eq "the cap holds three of the four" 3 "$(printf '%s' "$_s" | jq '.candidates | length')"
t_exit "stop the top one, the way Dismiss does" 0 stoptool stop "$TOP" --origin panel
_s2="$(scan)"
t_eq "it is gone from the next scan" 0 "$(printf '%s' "$_s2" | jq --arg i "$TOP" '[.candidates[] | select(.id == $i)] | length')"
t_eq "and the fourth takes its place" 3 "$(printf '%s' "$_s2" | jq '.candidates | length')"
t_eq "status lists it, with the panel origin" panel "$(stoptool status --json | jq -r --arg i "$TOP" '.stopped[] | select(.id == $i) | .origin')"
stoptool start "$TOP" --origin panel
t_eq "start puts it back" "$TOP" "$(scan | jq -r '.candidates[0].id')"

t_section "status --json reads the real table, and the pane's fixtures are the tools' own output"
t_eq "the rows are the table's, in order" "$(awk -F'\t' '$1 != "id" { print $1 }' "$BOX/suggest-rows.tsv")" "$(stoptool status --json | jq -r '.rows[].id')"
t_eq "the lines are the table's" "$(awk -F'\t' '$1 != "id" { print $7 }' "$BOX/suggest-rows.tsv")" "$(stoptool status --json | jq -r '.rows[].line')"
rm -f "$BOX/suggest-rows.tsv"
t_eq "no table (core ships none): no rows, still the contract's shape" '[]' "$(stoptool status --json | jq -c '.rows')"
_w="$T/fixture"; mkdir -p "$_w"
sh "$T_ROOT/tests/status/suggest/fixture.sh" "$_w" > "$T/real-tools.ts" 2>/dev/null
t_exit "mods/status-pane/tests/fixtures/real-tools.ts is what the tools print now; regenerate: sh tests/status/suggest/fixture.sh <empty dir> > that file" 0 \
  cmp "$T/real-tools.ts" "$T_ROOT/mods/status-pane/tests/fixtures/real-tools.ts"
t_done
