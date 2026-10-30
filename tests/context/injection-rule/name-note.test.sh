#!/usr/bin/env sh
# The name-note inform pack through the real engine (harbor#978 PR 4): a Write that creates a name the standard rejects
# draws a note naming the finding and the grammar, a compliant or existing path draws none, a repo without the standard
# is never judged, the pack never denies, and a fired note reaches the decision log.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"; BARE="$T/bare"
mkdir -p "$CFG/inject.d" "$CFG/bin" "$REPO/bin" "$REPO/standards" "$REPO/contracts" "$BARE/bin"
cp "$T_ROOT/context-rules/user/name-note.md" "$T_ROOT/context-rules/user/name-note.sh" "$CFG/inject.d/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"
# REPO carries the standard (its own lint and registry); BARE is a git repo that does not.
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/library-log.sh" "$REPO/bin/"; cp -R "$T_ROOT/standards/naming" "$REPO/standards/"
printf 'x\n' > "$REPO/README.md"
for _r in "$REPO" "$BARE"; do git -C "$_r" init -q . 2>/dev/null; done
OBS="$CFG/MEMORY/OBSERVABILITY/testhost"; mkdir -p "$OBS"; printf 'testhost\n' > "$CFG/.helm-obs-host"
: > "$OBS/guard-decisions.jsonl"; chmod 500 "$OBS"
trap 'chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT

call() { # <file_path> [project dir] [tool] → engine stdout in $OUT, rc in $RC
  jq -nc --arg f "$1" --arg t "${3:-Write}" '{hook_event_name:"PreToolUse",tool_name:$t,session_id:"s",tool_input:{file_path:$f,content:"x"}}' > "$T/in.json"
  OUT="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="${2:-$REPO}" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>"$T/err")"; RC=$?
}
note() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

t_section "a new name the standard rejects draws a note that names the finding and the grammar"
call "$REPO/bin/Foo_bar.sh"
t_has "bin/Foo_bar.sh draws the note" "$(note)" 'Name check (harbor#978'
t_has "it names the new path" "$(note)" '`bin/Foo_bar.sh` is a new name'
t_has "it names the family rule" "$(note)" '[name.family]'
t_has "it shows the bin grammar, <family>-<object>" "$(note)" '<family>[-<object>][-<verb>].<ext>'
call "$REPO/tests/foo/Bar.sh"
t_has "a new folder is judged too: tests/foo" "$(note)" '[name.test-path] tests/foo'
call "bin/Foo_bar.sh"
t_has "a relative path is read from the project dir" "$(note)" '`bin/Foo_bar.sh` is a new name'

t_section "what the write does not create is not judged"
call "$REPO/bin/drift-undeployed.sh"
t_eq "a compliant new name: silent" "" "$(note)"
call "$REPO/README.md"
t_eq "an existing file (an edit): silent" "" "$(note)"
call "$REPO/contracts/new-thing.md"
t_eq "a finding about a folder that already exists (CONTRACTS): silent" "" "$(note)"
call "$BARE/bin/Foo_bar.sh" "$BARE"
t_eq "a repo without the standard is never judged" "" "$(note)"
call "$T/outside/Foo_bar.sh" "$T"
t_eq "a path in no repo: silent" "" "$(note)"
call "$REPO/bin/Foo_bar.sh" "$REPO" Edit
t_eq "an Edit is not a create: the pack is not selected" "" "$(note)"

t_section "it informs and never denies"
call "$REPO/bin/Foo_bar.sh"
t_eq "a fired note carries no permissionDecision" "" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""')"
t_eq "exit 0" 0 "$RC"
t_eq "the script never prints a deny sentinel" 0 "$(grep 'printf' "$T_ROOT/context-rules/user/name-note.sh" | grep -c 'HARBOR-DECISION')"
t_eq "garbage payload: silent exit 0" 0 "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" >/dev/null 2>&1; echo $?)"
rm -f "$REPO/bin/lint-name.sh"; call "$REPO/bin/Foo_bar.sh"
t_eq "a repo whose lint is gone: silent exit 0" "0:" "$RC:$(note)"
cp "$T_ROOT/bin/lint-name.sh" "$REPO/bin/"

t_section "the decision log"
chmod u+w "$OBS"; : > "$OBS/guard-decisions.jsonl"; chmod 500 "$OBS"
call "$REPO/bin/drift-undeployed.sh"
t_eq "a silent call writes no record" 0 "$(wc -l < "$OBS/guard-decisions.jsonl" | tr -d ' ')"
call "$REPO/bin/Foo_bar.sh"
t_eq "once: match, the same bad path again in the session is not repeated" 0 "$(wc -l < "$OBS/guard-decisions.jsonl" | tr -d ' ')"
call "$REPO/bin/Other_tool.sh"
t_has "...a different bad path is" "$(note)" '`bin/Other_tool.sh` is a new name'
_rec="$(tail -n 1 "$OBS/guard-decisions.jsonl")"
t_eq "a fired note writes one record" 1 "$(wc -l < "$OBS/guard-decisions.jsonl" | tr -d ' ')"
t_eq "the record names the rule" name-note "$(printf '%s' "$_rec" | jq -r '.r')"
t_eq "the record is the inject guard's advise" "inject advise" "$(printf '%s' "$_rec" | jq -r '[.g,.d]|join(" ")')"
t_done
