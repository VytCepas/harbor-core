#!/usr/bin/env sh
# e2e.test.sh (harbor#1485) — the suggestions, end to end: the real installers lay out a config dir, the real engine runs the real packs,
# the real stop tool writes the state and the real scan reads it. The one stand-in is the table, the neutral fixture rows, because core
# ships none until the operator names the jobs. Every hook runs the installed copy, as a live session does.
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
cp "$T_ROOT/fixtures/injection-rule/suggest-tool.tsv" "$BOX/suggest-tool.tsv"
# The ledger, as the floor leaves it: a sealed host dir, a salt, a host token.
LEDGER="$CFG/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; mkdir -p "${LEDGER%/*}"
printf 'probehost\n' > "$CFG/.helm-obs-host"; printf '0123456789abcdef0123456789abcdef\n' > "$CFG/.helm-obs-salt"
: > "$LEDGER"; chmod 0500 "${LEDGER%/*}"
REPO="$T/repo"; mkdir -p "$REPO"; ( cd "$REPO" && git init -q . )
printf '{}\n' > "$T/tr.jsonl"
awk -F'\t' -v OFS='\t' '$3 == "injection" && $12 ~ /^suggest-(tool|start)$/ { $2 = "warn" } { print }' "$CFG/bin/controls.tsv" > "$T/controls-warn.tsv"
VERB='The agent can use a ready-made report for this job. Say stop suggesting this if you would rather not see it.'
INTRO='Harbor can look over recent sessions for repeated work. Open /status-pane and press Scan to try it.'

CONTROLS=''; SURFACE=cli
# hook <payload>: the installed engine, as the harness calls it; CONTROLS empty reads the installed register, born shadow
hook() {
  printf '%s' "$1" | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" HARBOR_STATUS_SUGGEST_DIR="$ST" \
    CLAUDE_CODE_ENTRYPOINT="$SURFACE" ${CONTROLS:+HARBOR_CONTEXT_CONTROLS="$CONTROLS"} /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null
}
call() { # <session> <command>
  hook "$(jq -cn --arg s "$1" --arg c "$2" --arg t "$T/tr.jsonl" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:$s,transcript_path:$t,tool_input:{command:$c}}')"
}
start() { hook "$(jq -cn --arg s "$1" --arg src "${2:-startup}" '{hook_event_name:"SessionStart",source:$src,session_id:$s}')"; }
stoptool() { HARBOR_STATUS_SUGGEST_DIR="$ST" sh "$TOOL" "$@" 2>/dev/null; }
msg() { printf '%s' "$1" | jq -r '.systemMessage // empty'; }
note() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
noted() { case "$(note "$1")" in *'[context:suggest-tool]'*) echo yes ;; *) echo no ;; esac; }
statef() { [ -e "$ST/$1" ] && echo yes || echo no; }
recs() { jq -c --arg r "$1" --arg d "$2" 'select(.r == $r and .d == $d)' "$LEDGER" | wc -l | tr -d ' '; }

t_section "a row fires: shadow shows nothing and writes no state"
_o="$(call sh1 'fixturectl report')"
t_eq "the installed register has both packs in shadow" 'shadow shadow' "$(awk -F'\t' '$3 == "injection" && $12 ~ /^suggest-(tool|start)$/ { printf "%s%s", s, $2; s = " " }' "$CFG/bin/controls.tsv")"
t_eq "shadow: no line" '' "$(msg "$_o")"
t_eq "shadow: no note" no "$(noted "$_o")"
t_eq "shadow: no shown record" no "$(statef shown.tsv)"
t_eq "shadow: no line claimed" no "$([ -d "$CFG/state/inject/sh1.seen.line" ] && echo yes || echo no)"
t_eq "shadow: the ledger's one record is what the shadow days are read from" 1 "$(recs suggest-tool-fixture-verb shadow)"
t_eq "shadow: and that record is no would-block" '{"suggest-tool-fixture-verb":1}' "$(CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/admission-observe-report.sh" --json 2>/dev/null | jq -c .inject_shadow)"

t_section "a row fires at warn: the line, the note, shown, and silence for the rest of the session"
CONTROLS="$T/controls-warn.tsv"
_o="$(call w1 'fixturectl report')"
t_eq "the person's line, from the table" "harbor: $VERB" "$(msg "$_o")"
t_has "the agent's note names the row" "$(note "$_o")" '[context:suggest-tool] Suggestion fixture-verb.'
t_has "a safe row's note switches" "$(note "$_o")" 'Switch to fixture-report'
t_has "the note carries the route for a no" "$(note "$_o")" "$TOOL stop fixture-verb --origin agent"
t_eq "shown is written, by the installed tool through spoke:" fixture-verb "$(cut -f1 "$ST/shown.tsv" 2>/dev/null)"
t_eq "shown holds the table's line" "$VERB" "$(cut -f3 "$ST/shown.tsv" 2>/dev/null)"
t_eq "status reads the same last line" fixture-verb "$(stoptool status --json | jq -r '.last.id')"
t_eq "the ledger has the row token" 1 "$(recs suggest-tool-fixture-verb advise)"
_o="$(call w1 'fixturectl report')"
t_eq "a second matching call: no line" '' "$(msg "$_o")"
t_eq "a second matching call: no note" no "$(noted "$_o")"
t_eq "...and no second record" 1 "$(recs suggest-tool-fixture-verb advise)"
_o="$(call w2 'fixturectl report --dry-run')"
t_eq "a row's quiet pattern: no line" '' "$(msg "$_o")"
_o="$(call w2 'fixturectl report')"
t_eq "the next session may hear it again" "harbor: $VERB" "$(msg "$_o")"

t_section "stopped and off stay silent, and a stop reaches the next session"
t_exit "stop, through the installed tool" 0 stoptool stop fixture-verb --origin agent
_o="$(call s1 'fixturectl report')"
t_eq "the next session: no line" '' "$(msg "$_o")"
t_eq "the next session: no note" no "$(noted "$_o")"
t_eq "and status says so" true "$(stoptool status --json | jq '.rows[] | select(.id == "fixture-verb") | .stopped')"
stoptool start fixture-verb --origin panel
t_eq "start brings it back in another session" "harbor: $VERB" "$(msg "$(call s2 'fixturectl report')")"
stoptool off --origin panel
_o="$(call s3 'fixturectl report')"
t_eq "off: no line" '' "$(msg "$_o")"
t_eq "off: no note" no "$(noted "$_o")"
t_eq "and status says so" false "$(stoptool status --json | jq '.enabled')"
stoptool on --origin panel
t_eq "on brings it back" "harbor: $VERB" "$(msg "$(call s4 'fixturectl report')")"
# One name for the folder: with the variable unset, the rule, the tool and the scan all read the default.
_d="$HOME/.local/state/harbor/suggest"
sh "$TOOL" stop fixture-verb --origin agent 2>/dev/null
_o="$(printf '%s' "$(jq -cn --arg t "$T/tr.jsonl" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"s5",transcript_path:$t,tool_input:{command:"fixturectl report"}}')" \
  | env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" HARBOR_CONTEXT_CONTROLS="$CONTROLS" /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null)"
t_eq "the default folder: a stop there silences the rule" '' "$(msg "$_o")"
t_eq "...and it landed there" fixture-verb "$(cut -f1 "$_d/stopped.tsv")"

t_section "a spoke: a killed writer's lock is broken inside the 3 s bound; a live one costs the hook 3 s, not its 10"
mkdir "$ST/.lock"; rm -f "$ST/shown.tsv"
_t0="$(date +%s)"; _o="$(call lk1 'fixturectl report')"; _t1="$(date +%s)"
t_eq "the line still leaves" "harbor: $VERB" "$(msg "$_o")"
t_eq "the record lands: a stale lock loses nothing" yes "$(statef shown.tsv)"
t_exit "...and the lock is gone" 1 test -e "$ST/.lock"
t_eq "the hook is back inside 10 s" yes "$([ $((_t1 - _t0)) -lt 10 ] && echo yes || echo no)"
mkdir "$ST/.lock"; rm -f "$ST/shown.tsv"
( n=0; while [ "$n" -lt 30 ] && [ -d "$ST/.lock" ]; do touch "$ST/.lock" 2>/dev/null; n=$((n + 1)); sleep 0.2; done ) & _h=$!
_t0="$(date +%s)"; _o="$(call lk2 'fixturectl report')"; _t1="$(date +%s)"
rmdir "$ST/.lock" 2>/dev/null || :
wait "$_h"
t_eq "a live lock: the line still leaves" "harbor: $VERB" "$(msg "$_o")"
t_eq "the hook is back inside 10 s" yes "$([ $((_t1 - _t0)) -lt 10 ] && echo yes || echo no)"
t_eq "shown was cut off, silently" no "$(statef shown.tsv)"

t_section "SessionStart ticks once; 20 sessions make the intro due, on a known surface only"
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
SURFACE=claude-desktop
t_eq "at 19 a known surface hears nothing" '' "$(msg "$(call i19 'ls')")"
start t20 >/dev/null
t_eq "at 20 the intro is due" true "$(stoptool status --json | jq '.intro_due')"
SURFACE=cli
t_eq "due, on an unknown surface: silent" '' "$(msg "$(call i20 'ls')")"
SURFACE=''
t_eq "due, with no surface at all: silent" '' "$(msg "$(call i21 'ls')")"
t_eq "and it stays due" true "$(stoptool status --json | jq '.intro_due')"
SURFACE=claude-desktop
t_eq "a real row outranks it" "harbor: $VERB" "$(msg "$(call i22 'fixturectl report')")"
t_eq "...and it stays due" true "$(stoptool status --json | jq '.intro_due')"
t_eq "due, on the known surface: the intro speaks" "harbor: $INTRO" "$(msg "$(call i23 'ls')")"
t_eq "...spoke: records it" fixture-intro "$(cut -f1 "$ST/shown.tsv")"
t_eq "...and it is not due again for 20 sessions" false "$(stoptool status --json | jq '.intro_due')"
t_eq "the next session hears no intro" '' "$(msg "$(call i24 'ls')")"
SURFACE=cli

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
t_eq "the rows are the table's, in order" "$(awk -F'\t' '$1 != "id" { print $1 }' "$BOX/suggest-tool.tsv")" "$(stoptool status --json | jq -r '.rows[].id')"
t_eq "the lines are the table's" "$(awk -F'\t' '$1 != "id" { print $7 }' "$BOX/suggest-tool.tsv")" "$(stoptool status --json | jq -r '.rows[].line')"
cp "$T_ROOT/context-rules/user/suggest-tool.tsv" "$BOX/suggest-tool.tsv"
t_eq "core's shipped table: no rows, still the contract's shape" '[]' "$(stoptool status --json | jq -c '.rows')"
_w="$T/fixture"; mkdir -p "$_w"
sh "$T_ROOT/tests/status/suggest/fixture.sh" "$_w" > "$T/real-tools.ts" 2>/dev/null
t_exit "mods/status-pane/tests/fixtures/real-tools.ts is what the tools print now; regenerate: sh tests/status/suggest/fixture.sh <empty dir> > that file" 0 \
  cmp "$T/real-tools.ts" "$T_ROOT/mods/status-pane/tests/fixtures/real-tools.ts"
t_done
