#!/usr/bin/env sh
# The Bash create-command name note (harbor#978 item 9) through the real engine: a create command from a
# name-create.d row whose new name breaks the standard draws a note with the compliant form, a compliant
# name, an unmatched command, a $VAR name or a heredoc body draws none, and nothing ever denies.
# The command rows are a neutral fixture (`fixturectl create`); real rows come from workload packs.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$T_TMP"; CFG="$T/cfg"; REPO="$T/repo"; BARE="$T/bare"
mkdir -p "$CFG/inject.d" "$CFG/bin" "$CFG/name-create.d" "$REPO/bin" "$REPO/standards" "$BARE"
cp "$T_ROOT/context-rules/user/name-note-create.md" "$T_ROOT/context-rules/user/name-note-create.sh" "$CFG/inject.d/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"
cp "$T_ROOT/bin/lint-name.sh" "$T_ROOT/bin/library-log.sh" "$REPO/bin/"; cp -R "$T_ROOT/standards/naming" "$REPO/standards/"
printf 'x\n' > "$REPO/README.md"
for _r in "$REPO" "$BARE"; do git -C "$_r" init -q . 2>/dev/null; done
printf 'fixturectl[[:space:]]+create[[:space:]]+\tskill\tUse the form the grammar names.\n' > "$CFG/name-create.d/fixture.tsv"
OBS="$CFG/MEMORY/OBSERVABILITY/testhost"; mkdir -p "$OBS"; printf 'testhost\n' > "$CFG/.helm-obs-host"
trap 'chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT

call() { # <command> [project dir] → engine stdout in $OUT, rc in $RC
  jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"s",tool_input:{command:$c}}' > "$T/in.json"
  OUT="$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="${2:-$REPO}" /bin/sh "$CFG/bin/injection-rule.sh" < "$T/in.json" 2>"$T/err")"; RC=$?
}
note() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

t_section "a create command with a bad name draws a note with the compliant form"
call "fixturectl create MyService"
t_has "it fires" "$(note)" 'Name check (harbor#978'
t_has "it names the new name" "$(note)" '`MyService` is a new skill name'
t_has "it carries the grammar" "$(note)" '<family-or-domain>[-<object>]'
t_has "it carries the row's own note" "$(note)" 'Use the form the grammar names.'
call "fixturectl create --force 'MyService' --quiet"
t_has "flags and quotes are stepped over" "$(note)" '`MyService` is a new skill name'
call "echo hi && fixturectl create MyService"
t_has "a command mid-chain is found" "$(note)" '`MyService`'

t_section "what is compliant or not judgeable draws none"
call "fixturectl create access-ledger"
t_eq "a compliant name: silent" "" "$(note)"
call "ls -la"
t_eq "an unmatched command: silent" "" "$(note)"
call "fixturectl create \$NAME"
t_eq "a name from a variable: silent" "" "$(note)"
call "fixturectl create \"\$(pick)\""
t_eq "a name from a substitution: silent" "" "$(note)"
call "cat <<EOF
fixturectl create MyService
EOF"
t_eq "a heredoc body is documentation: silent" "" "$(note)"
call "fixturectl create MyService" "$BARE"
t_eq "no lint in the repo or the config: silent" "" "$(note)"
rm -f "$CFG/name-create.d/fixture.tsv"; call "fixturectl create MyService"
t_eq "no rows (core names no command): silent" "" "$(note)"
printf 'fixturectl[[:space:]]+create[[:space:]]+\tskill\tUse the form the grammar names.\n' > "$CFG/name-create.d/fixture.tsv"

t_section "it informs and never denies"
call "fixturectl create MyService"
t_eq "no permissionDecision" "" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""')"
t_eq "exit 0" 0 "$RC"
t_eq "the script never prints a deny sentinel" 0 "$(grep 'printf' "$T_ROOT/context-rules/user/name-note-create.sh" | grep -c 'HARBOR-DECISION')"
t_eq "garbage payload: silent exit 0" 0 "$(printf 'not json' | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$CFG/bin/injection-rule.sh" >/dev/null 2>&1; echo $?)"
t_done
