#!/usr/bin/env sh
# guard-stop.sh (harbor#291, #676): red, green and false-positive cases for the one Stop-event gate.
# Classification only: every transcript is synthesised here with jq, so none carries anything from
# the box and a quote in a path cannot turn a fixture into invalid JSON that reads as allow.
. "$(dirname "$0")/../lib/core.sh"; t_init
GUARD="$T_ROOT/bin/guard-stop.sh"; WORK="$T_TMP/sg"
# Each session's recorded context lives here; floor_log_decision's sink does not, so it stays blind.
CFG="$WORK/cfg"; mkdir -p "$CFG/.helm-context"
# SG-1 counts a bin/guard-* edit only in a tree holding tests/floor/floor-test.sh, or in the config
# dir, and wants a verdict from each of that tree's floor parts (harbor#727). Two parts here.
for _t in repo scratch; do
  mkdir -p "$WORK/$_t/bin" "$WORK/$_t/tests/floor"
  : > "$WORK/$_t/tests/floor/floor-test.sh"; : > "$WORK/$_t/tests/floor/floor.a-test.sh"
done
R="$WORK/repo"; SCR="$WORK/scratch"; PROJ="$WORK/project"; mkdir -p "$PROJ/bin"
tu_edit() { # <path> [tool]
  jq -cn --arg p "$1" --arg n "${2:-Edit}" \
    '{type:"assistant",message:{content:[{type:"tool_use",id:"edit-x",name:$n,input:{file_path:$p}}]}}'
}
tu_bash() { # <id> <command>
  jq -cn --arg i "$1" --arg c "$2" \
    '{type:"assistant",message:{content:[{type:"tool_use",id:$i,name:"Bash",input:{command:$c}}]}}'
}
tr_res() { # <id> <result-text>
  jq -cn --arg i "$1" --arg t "$2" \
    '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$i,content:[{type:"text",text:$t}]}]}}'
}
# The gate refuses once per defect per session, so each case needs a fresh id. Counters are files:
# every call site is a $(...) subshell, where a shell variable would increment a copy.
bump() { _n="$(( $(cat "$1" 2>/dev/null || echo 0) + 1 ))"; printf '%s\n' "$_n" > "$1"; printf '%s' "$_n"; }
new_sid() { _s="sid-$(bump "$WORK/sid-counter")"; printf 'ambient\n' > "$CFG/.helm-context/$_s"; printf '%s' "$_s"; }
tx() { _f="$WORK/tx-$(bump "$WORK/tx-counter").jsonl"; : > "$_f"; printf '%s' "$_f"; }
# verdict_at <sid> <transcript> [stop_hook_active] → block | allow | PARSE_ERR; a non-zero exit is
# logged to $RCF, and D3 below asserts none happened (legacy counted in a subshell and saw none).
RCF="$WORK/rc-bad"; : > "$RCF"
verdict_at() {
  _p="$(jq -cn --arg tx "$2" --arg s "$1" --argjson a "${3:-false}" \
        '{session_id:$s,transcript_path:$tx,stop_hook_active:$a,hook_event_name:"Stop"}')"
  _out="$(printf '%s' "$_p" | CLAUDE_CONFIG_DIR="$CFG" sh "$GUARD" 2>/dev/null)" || echo "$1 $?" >> "$RCF"
  if [ -z "$_out" ]; then echo allow; return 0; fi
  printf '%s' "$_out" | jq -er '.decision' 2>/dev/null || echo PARSE_ERR
}
want() { t_eq "$2" "$1" "$(verdict_at "$(new_sid)" "$3" "${4:-false}")"; }  # <verdict> <label> <tx> [active]
want_cwd() { # <verdict> <label> <tx> <cwd> — the session ran from <cwd>
  _p="$(jq -cn --arg tx "$3" --arg s "$(new_sid)" --arg c "$4" '{session_id:$s,transcript_path:$tx,stop_hook_active:false,cwd:$c}')"
  t_eq "$2" "$1" "$(printf '%s' "$_p" | CLAUDE_CONFIG_DIR="$CFG" sh "$GUARD" 2>/dev/null | jq -r '.decision // "allow"' 2>/dev/null || echo allow)"
}
stop_run() { printf '%s' "$1" | CLAUDE_CONFIG_DIR="${2:-$CFG}" sh "$GUARD" 2>/dev/null; }  # <payload> [cfg]
payload() { jq -cn --arg tx "$1" --arg s "$2" '{session_id:$s,transcript_path:$tx,stop_hook_active:false}'; }
FT='sh tests/floor/floor-test.sh'; GB="$R/bin/guard-bash.sh"
FA='sh tests/floor/floor.a-test.sh'; FULL="$(printf 'floor-test: 10 passed, 0 failed\nfloor.a-test: 5 passed, 0 failed')"

t_section "the loop guard: stop_hook_active is checked before anything else"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "$FT"; tr_res c1 "floor-test: 10 passed, 3 failed"; } >> "$T"
want block "loop guard off: both rules fire on this fixture" "$T" false
want allow "stop_hook_active=true allows the same one" "$T" true

t_section "SG-1 a floor surface edited, and the suite after it"
T="$(tx)"; tu_edit "$GB" >> "$T"
want block "floor edit, nothing run" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "for f in tests/floor/floor*-test.sh; do sh \$f; done"; tr_res c1 "$FULL"; } >> "$T"
want allow "floor edit then every part of the suite" "$T"
# harbor#1176, same class as SG-2: a labelled floor-part line counts for its part as the plain one does.
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "$FT"; tr_res c1 "run 0 floor-test: 10 passed, 0 failed"; \
             tu_bash c2 "$FA"; tr_res c2 "floor.a-test: 5 passed, 0 failed"; } >> "$T"
want allow "a prefixed floor-test line counts for its part (#1176)" "$T"
# Control: the prefix must not lose the red. A prefixed RED part still blocks.
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "$FT"; tr_res c1 "run 1 floor-test: 10 passed, 3 failed"; \
             tu_bash c2 "$FA"; tr_res c2 "floor.a-test: 5 passed, 0 failed"; } >> "$T"
want block "a prefixed RED floor-test line still blocks (#1176 control)" "$T"
T="$(tx)"; { tu_bash c1 "for f in tests/floor/floor*-test.sh; do sh \$f; done"; tr_res c1 "$FULL"; tu_edit "$GB"; } >> "$T"
want block "the suite BEFORE the edit is not evidence" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "for f in tests/floor/floor*-test.sh; do sh \$f; done"; tr_res c1 "$FULL"; \
             tu_edit "$R/bin/guard-lib.sh"; } >> "$T"
want block "a later edit owes a later run" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "$FT"; tr_res c1 "floor-test: 10 passed, 0 failed"; } >> "$T"
want block "one part is not the suite, as one shard was not (harbor#679, #727)" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "$FT"; tr_res c1 "floor-test: 10 passed, 0 failed"; \
             tu_bash c2 "$FA"; tr_res c2 "floor.a-test: 5 passed, 0 failed"; } >> "$T"
want allow "the parts one command at a time count" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "T_SMOKE=1 $FT"; tr_res c1 "floor-test smoke: 92 passed, 0 failed (NOT a full run)"; \
             tu_bash c2 "$FA"; tr_res c2 "floor.a-test: 5 passed, 0 failed"; } >> "$T"
want block "the smoke does not count as the main part (№2.7)" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "cat /tmp/an-old-run.log"; tr_res c1 "$FULL"; } >> "$T"
want block "verdicts a command only READ are not a run" "$T"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "sh bin/suite-select.sh --run tests/floor/floor-test.sh"; \
             tr_res c1 "floor-test: 10 passed, 0 failed"; tu_bash c2 "sh bin/suite-select.sh --run tests/floor/floor.a-test.sh"; \
             tr_res c2 "floor.a-test: 5 passed, 0 failed"; } >> "$T"
want allow "the CI route counts (suite-select --run, per part)" "$T"
T="$(tx)"; { tu_edit "$CFG/bin/guard-x.sh"; tu_bash c1 "$FT"; tr_res c1 "floor-test: 10 passed, 0 failed"; } >> "$T"
want allow "a config-dir edit with no checkout in view owes the main part" "$T"
want_cwd block "a config-dir edit from a checkout owes that checkout's parts" "$T" "$R"

t_section "SG-1 which paths are floor surfaces, and which only look like one"
T="$(tx)"; tu_edit "$R/bin/guard-lib.sh" >> "$T";         want block "bin/guard-lib.sh" "$T"
T="$(tx)"; tu_edit "$R/bin/floor-normalize.awk" >> "$T";  want block "bin/floor-normalize.awk" "$T"
T="$(tx)"; tu_edit "$R/bin/floor-hook.sh" >> "$T";        want block "bin/floor-hook.sh" "$T"
T="$(tx)"; tu_edit "$R/bin/guard-stop.sh" Write >> "$T";  want block "Write counts, not only Edit" "$T"
T="$(tx)"; tu_edit "$R/bin/guard-stop.sh" NotebookEdit >> "$T"; want block "NotebookEdit counts too" "$T"
T="$(tx)"; tu_edit "$R/README.md" >> "$T";                want allow "a doc edit is not a floor edit" "$T"
T="$(tx)"; tu_edit "$R/docs/guard-notes.sh" >> "$T";      want allow "guard-notes.sh outside bin/ is not a surface" "$T"
T="$(tx)"; tu_edit "$R/bin/status-gen.sh" >> "$T";        want allow "an ordinary bin/ script is not a surface" "$T"
T="$(tx)"; tu_edit "$R/bin/guard-bash.sh.bak" >> "$T";    want allow "a .bak copy is not the surface" "$T"
T="$(tx)"; tu_edit "$SCR/bin/guard-x.sh" >> "$T";         want block "a Harbor checkout anywhere still counts" "$T"
T="$(tx)"; tu_edit "$CFG/bin/guard-x.sh" >> "$T";         want block "the installed floor in the config dir counts" "$T"
T="$(tx)"; tu_edit "$PROJ/bin/guard-auth.sh" >> "$T"      # review of #684: a project's own guard script
want allow "a governed project's own bin/guard-auth.sh is not a Harbor floor surface" "$T"
T="$(tx)"; tu_edit "$PROJ/bin/floor-plan.sh" >> "$T";     want allow "a project's bin/floor-plan.sh is not one either" "$T"

t_section "SG-1 the gap, pinned so it cannot change unnoticed"
T="$(tx)"; tu_bash c1 "sed -i '' s/a/b/ bin/guard-bash.sh" >> "$T"; want allow "KNOWN GAP: sed -i on a surface via Bash" "$T"
T="$(tx)"; tu_bash c1 "cp /tmp/x bin/guard-bash.sh" >> "$T";        want allow "KNOWN GAP: cp onto a surface via Bash" "$T"

t_section "SG-2 a suite this session ran, and whether it ended green"
T="$(tx)"; { tu_bash c1 "$FT"; tr_res c1 "floor-test: 1500 passed, 25 failed"; } >> "$T"
want block "red suite, no later run" "$T"
T="$(tx)"; { tu_bash c1 "$FT"; tr_res c1 "floor-test: 1500 passed, 25 failed"; \
             tu_bash c2 "$FT"; tr_res c2 "floor-test: 1525 passed, 0 failed"; } >> "$T"
want allow "red then green, the ordinary fix cycle" "$T"
T="$(tx)"; { tu_bash c1 "$FT"; tr_res c1 "floor-test: 1525 passed, 0 failed"; \
             tu_bash c2 "$FT"; tr_res c2 "floor-test: 1500 passed, 25 failed"; } >> "$T"
want block "green then red: the LAST verdict decides" "$T"
T="$(tx)"; { tu_bash c1 "sh bin/normalize-test.sh"; tr_res c1 "normalize-test: 164 passed, 3 failed"; \
             tu_bash c2 "$FT"; tr_res c2 "floor-test: 1525 passed, 0 failed"; } >> "$T"
want block "a green floor-test does not clear a red normalize-test" "$T"
T="$(tx)"; { tu_bash c1 "$FT"; tr_res c1 "floor-test: 1500 passed, 25 failed"; \
             tu_bash c2 "T_SMOKE=1 $FT"; tr_res c2 "floor-test smoke: 92 passed, 0 failed (NOT a full run)"; } >> "$T"
want block "a green smoke does not clear a red full run" "$T"
T="$(tx)"; { tu_bash c1 "sh bin/lint-conventions.sh"; tr_res c1 "lint-conventions: 62 rules, 4 violations"; } >> "$T"
want block "violations count like failures" "$T"
T="$(tx)"; { tu_bash c1 "sh bin/lint-conventions.sh"; tr_res c1 "lint-conventions: 62 rules, 0 violations"; } >> "$T"
want allow "zero violations is clean" "$T"
# marker-test prints three numbers: the last reads 0, and any-number would read 80.
T="$(tx)"; { tu_bash c1 "sh bin/marker-test.sh"; \
             tr_res c1 "marker-test: 80 passed, 0 failed, 0 awaiting an owner decision"; } >> "$T"
want allow "marker-test's three-number line, clean" "$T"
T="$(tx)"; { tu_bash c1 "sh bin/marker-test.sh"; \
             tr_res c1 "marker-test: 78 passed, 2 failed, 0 awaiting an owner decision"; } >> "$T"
want block "marker-test's three-number line, red" "$T"
# harbor#1176: a labelled summary `<label> <rc> <verdict>` must key on the suite name, not the label.
T="$(tx)"; { tu_bash c1 "sh tests/rules-test.sh"; tr_res c1 "check 1 check: 6 rules, 1 violations"; \
             tu_bash c2 "sh tests/rules-test.sh"; tr_res c2 "check: 6 rules, 0 violations"; } >> "$T"
want allow "a prefixed red line, then a plain clean one for the same suite clears it (#1176)" "$T"
T="$(tx)"; { tu_bash c1 "sh tests/rules-test.sh"; tr_res c1 "check 1 check: 6 rules, 1 violations"; \
             tu_bash c2 "sh tests/rules-test.sh"; tr_res c2 "check 0 check: 6 rules, 0 violations"; } >> "$T"
want allow "a prefixed red line, then a prefixed clean one, clears it (#1176)" "$T"
T="$(tx)"; { tu_bash c1 "sh tests/rules-test.sh"; tr_res c1 "check 0 check: 6 rules, 0 violations"; \
             tu_bash c2 "sh tests/rules-test.sh"; tr_res c2 "check: 6 rules, 1 violations"; } >> "$T"
want block "a prefixed clean line, then a plain RED one still blocks: the true positive survives (#1176)" "$T"

t_section "SG-2 the id pairing: a verdict read is not a verdict produced"
T="$(tx)"; { tu_bash c1 "cat /tmp/old-build.log"; tr_res c1 "floor-test: 1500 passed, 25 failed"; } >> "$T"
want allow "a red verdict inside a cat is not this session's" "$T"
T="$(tx)"; { tu_bash c1 "git log -1"; tr_res c1 "floor-test: 1500 passed, 25 failed"; } >> "$T"
want allow "nor one inside a commit message" "$T"
T="$(tx)"; tr_res orphan "floor-test: 1500 passed, 25 failed" >> "$T"
want allow "an orphan result with no command" "$T"

t_section "both rules at once: one block, not two"
T="$(tx)"; { tu_edit "$GB"; tu_bash c1 "sh bin/normalize-test.sh"; \
             tr_res c1 "normalize-test: 100 passed, 1 failed"; } >> "$T"
want block "SG-1 and SG-2 together" "$T"
_o="$(stop_run "$(payload "$T" "$(new_sid)")")"
t_eq "decision" block "$(printf '%s' "$_o" | jq -r '.decision')"
t_has "the reason names SG-1" "$(printf '%s' "$_o" | jq -r '.reason')" "SG-1"
t_has "the reason names SG-2" "$(printf '%s' "$_o" | jq -r '.reason')" "SG-2"
t_eq "a systemMessage for the operator" true "$(printf '%s' "$_o" | jq -r '.systemMessage | length > 0')"
t_eq "one verdict emitted, not two" 1 "$(printf '%s' "$_o" | grep -c 'decision')"

t_section "once per state, because Stop fires at the end of every turn"
_s1="$(new_sid)"
T="$(tx)"; tu_edit "$GB" >> "$T"
t_eq "the first turn is refused" block "$(verdict_at "$_s1" "$T")"
t_eq "the second turn is not held" allow "$(verdict_at "$_s1" "$T")"
t_eq "nor the third" allow "$(verdict_at "$_s1" "$T")"
T2="$(tx)"; tu_edit "$R/bin/guard-egress.sh" >> "$T2"
t_eq "a different surface is refused again" block "$(verdict_at "$_s1" "$T2")"
t_eq "a new session is refused again" block "$(verdict_at "$(new_sid)" "$T")"
_sf="$CFG/.helm-stop-gate/$_s1"  # digests only: the config dir is private (§3)
t_eq "a state file is written" yes "$([ -f "$_sf" ] && echo yes || echo no)"
t_has "the defect it records names a path" "$(cat "$T")" "repo/bin/guard-"
t_hasnt "the state file carries no repo path" "$(cat "$_sf" 2>/dev/null)" "repo"
t_hasnt "the state file carries no guard name" "$(cat "$_sf" 2>/dev/null)" "guard-"
t_eq "lines that are not a 64-hex digest" 0 "$(awk 'length($0)!=64 || $0 ~ /[^0-9a-f]/ {n++} END{print n+0}' "$_sf")"
# With no session_id there is nowhere to record the one-shot, so the gate fails open (#676).
t_eq "no session_id: the gate allows" "" "$(stop_run "$(jq -cn --arg tx "$T" '{transcript_path:$tx,stop_hook_active:false}')")"

t_section "fail open on every error path: a turn that cannot end is the worst case"
T="$(tx)"; want allow "an empty transcript" "$T"
want allow "a transcript that does not exist" "$WORK/nope.jsonl"
T="$(tx)"; printf 'this is not json\n' >> "$T"; want allow "a transcript of garbage lines" "$T"
T="$(tx)"; { tu_edit "$GB"; printf 'not json\n'; } >> "$T"
want allow "one garbage line poisons the whole parse (fails OPEN)" "$T"
for _in in '{}' 'not json' ''; do
  _e="$(stop_run "$_in")"; _erc=$?
  t_eq "payload '$_in': exit" 0 "$_erc"
  t_eq "payload '$_in': silent" "" "$_e"
done

t_section "the kill switch, and no stand-down inside a governed repo (harbor#676)"
T="$(tx)"; tu_edit "$GB" >> "$T"
_o="$(payload "$T" "$(new_sid)" | HELM_DISABLE_FLOOR=1 CLAUDE_CONFIG_DIR="$CFG" sh "$GUARD" 2>/dev/null)"
t_eq "HELM_DISABLE_FLOOR=1 opens an unguarded session" "" "$_o"
_sg="$(new_sid)"; printf 'repo\n' > "$CFG/.helm-context/$_sg"  # the five never yield (harbor#581)
t_eq "a governed session (context: repo) is still gated" block "$(stop_run "$(payload "$T" "$_sg")" | jq -r '.decision' 2>/dev/null)"
mkdir -p "$WORK/no-context"
t_eq "a session with no recorded context is still gated" block \
  "$(stop_run "$(payload "$T" sid-nocontext)" "$WORK/no-context" | jq -r '.decision' 2>/dev/null)"

t_section "SG-3 a handed-over command is checked against the shell it runs in (harbor#1284)"
# The red fixtures are the recorded failures: memory verify-handover-runs-where-it-lands,
# stdin-prompts-die-under-bang-bash, bang-gh-runs-as-the-app, and the 2026-10-17 deploy handover.
SG3TX="$(tx)"; tu_bash c0 "ls" >> "$SG3TX"
# P4 reads a PR's state live; this gh answers by number: 77 open, 78 merged, 79 never answers.
FGH="$WORK/fake-gh"; mkdir -p "$FGH"
printf '#!/bin/sh\ncase " $* " in *" 77 "*) echo OPEN ;; *" 78 "*) echo MERGED ;; *" 79 "*) sleep 9 ;; esac\n' > "$FGH/gh"
chmod +x "$FGH/gh"
sg3_out() { # <message> [transcript] [mode] [sid] → the hook's raw stdout
  jq -cn --arg tx "${2:-$SG3TX}" --arg s "${4:-$(new_sid)}" --arg m "$1" \
    '{session_id:$s,transcript_path:$tx,stop_hook_active:false,last_assistant_message:$m}' \
    | PATH="$FGH:$PATH" HARBOR_ADMISSION_SG3="${3:-warn}" CLAUDE_CONFIG_DIR="$CFG" sh "$GUARD" 2>/dev/null
}
sg3() { sg3_out "$@" | jq -r '.systemMessage // ""' 2>/dev/null; }  # → what the operator sees
M=merge; DEP='sh ~/port/harbor/bin/deploy.sh'; OGH=/opt/homebrew/bin/gh
t_has "P1 deploy --apply under ! (2026-10-17)" "$(sg3 "Run it:
! $DEP --apply --live")" "terminal answer"
t_has "P1 the harbor verb routes to the same script" "$(sg3 "! harbor deploy --apply --live")" "terminal answer"
t_has "P1 gh auth login prompts" "$(sg3 "! $OGH auth login")" "terminal answer"
t_eq "P1 gcloud auth login runs its browser plumb under ! (replay, 7419e469)" "" "$(sg3 "! gcloud auth login")"
t_eq "P1 gh auth login --with-token reads stdin, not a terminal" "" "$(sg3 "! $OGH auth login --with-token < t")"
t_eq "P1 the dry run does not prompt" "" "$(sg3 "! $DEP --live")"
t_eq "P1 the same command for a terminal is the right handover" "" "$(sg3 "In a terminal:
\`\`\`
$DEP --apply --live
\`\`\`")"
t_has "P2 a --watch (2026-10-16)" "$(sg3 "! $OGH pr checks 1280 -R o/r --watch && $OGH pr $M 1280 -R o/r --$M")" "out of sight"
t_has "P2 a long sleep" "$(sg3 "! sleep 600 && $OGH run list")" "out of sight"
t_has "P2 a wait loop (2026-08-24)" "$(sg3 "! until $OGH pr checks 9; do sleep 30; done")" "out of sight"
t_eq "P2 a short sleep fits the cap" "" "$(sg3 "! sleep 5 && ls")"
t_has "P3 bare gh" "$(sg3 "! gh pr $M 36 -R o/mailcal --squash")" "runs as the App"
t_has "P3 an emptied token is still the shim" "$(sg3 "   ! GH_TOKEN= gh pr $M 232 --repo o/r --$M")" "runs as the App"
t_has "P3 env -u is still the shim" "$(sg3 "! env -u GH_TOKEN gh pr review 1218 -R o/r --approve")" "runs as the App"
t_has "P3 inside a list item in backticks" "$(sg3 "- \`! gh pr review 7 --approve\` then wait")" "runs as the App"
t_has "P3 a fence opened by ! stays ! to its end" "$(sg3 "\`\`\`
! cd /Users/x/port/r && git pull
gh pr $M 5 --squash
\`\`\`")" "runs as the App"
t_eq "P3 the full path is the operator" "" "$(sg3 "! $OGH pr $M 36 -R o/r --squash")"
t_eq "P3 prose naming gh is not a handover" "" "$(sg3 "Never hand over bare gh pr $M from a ! line.")"
t_eq "P1 sudo inside a quoted remote --command runs on the VM (replay, a41f27d5)" "" \
  "$(sg3 "! gcloud compute ssh vm --command 'sudo cat /x; sudo rm -f /y'")"
t_eq "cd ~/ under ! ran clean in the transcripts, so it is no predicate" "" "$(sg3 "! cd ~/port/frobapp && sh bin/x.sh")"
T="$(tx)"; { tu_bash p1 "$OGH pr create --fill"; tr_res p1 "https://github.com/o/r/pull/77"; } >> "$T"
FD="$(printf 'Then, in a terminal:\n```\n%s --apply --live\n```' "$DEP")"
t_has "P4 deploy while the PR this session opened is unmerged (memory, 2026-08-24)" "$(sg3 "$FD" "$T")" "PR o/r#77"
t_has "P4 a -install.sh --apply too" "$(sg3 "! sh bin/runtime-install.sh --live --apply" "$T")" "PR o/r#77"
t_eq "P4 a message that names the PR before the install has sequenced it" "" "$(sg3 "Merge #77 in the browser, then:
$FD" "$T")"
T4="$(tx)"; { tu_bash p1 "$OGH pr create --fill"; tr_res p1 "https://github.com/o/r/pull/78"; } >> "$T4"
t_eq "P4 a PR merged where the transcript cannot see it (replay: merged a day before)" "" "$(sg3 "$FD" "$T4")"
T5="$(tx)"; { tu_bash p1 "$OGH pr create --fill"; tr_res p1 "https://github.com/o/r/pull/79"; } >> "$T5"
t_eq "P4 no answer from gh in 4s drops the finding (fail open)" "" "$(sg3 "$FD" "$T5")"
t_eq "P4 a merge earlier in the same handover clears it" "" "$(sg3 "! $OGH pr $M 77 -R o/r --squash
$FD" "$T")"
T2="$(tx)"; cat "$T" > "$T2"
jq -cn '{type:"user",message:{content:"<bash-stdout>✓ Merged pull request o/r#77 (x)</bash-stdout>"}}' >> "$T2"
t_eq "P4 a merge the operator ran with ! clears it" "" "$(sg3 "$FD" "$T2")"
T3="$(tx)"; { tu_bash p1 "cat notes.md"; tr_res p1 "https://github.com/o/r/pull/77"; } >> "$T3"
t_eq "P4 a PR URL the session only read is not one it opened" "" "$(sg3 "$FD" "$T3")"
t_section "SG-3 modes, id and cadence"
_o="$(sg3_out "! gh pr view 3")"
t_eq "warn holds nothing" "" "$(printf '%s' "$_o" | jq -r '.decision // ""')"
t_has "every refusal quotes the control id" "$(printf '%s' "$_o" | jq -r '.systemMessage')" "[stop:handover-shell]"
t_eq "block refuses" block "$(sg3_out "! gh pr view 3" "" block | jq -r '.decision // ""')"
t_eq "off is silent" "" "$(sg3_out "! gh pr view 3" "" off)"
t_eq "an unknown mode is warn, never off" "" "$(sg3_out "! gh pr view 3" "" bogus | jq -r '.decision // ""')"
_s3="$(new_sid)"
t_has "the first turn is told" "$(sg3 "! gh pr view 3" "" warn "$_s3")" "SG-3"
t_eq "the same handover is not repeated" "" "$(sg3 "! gh pr view 3" "" warn "$_s3")"
T="$(tx)"; tu_edit "$GB" >> "$T"
_o="$(sg3_out "! gh pr view 4" "$T")"
t_eq "beside SG-1 it rides the one block" 1 "$(printf '%s' "$_o" | grep -c 'decision')"
t_has "and the operator sees SG-3 there" "$(printf '%s' "$_o" | jq -r '.systemMessage')" "SG-3"
t_hasnt "warn keeps it out of the model's reason" "$(printf '%s' "$_o" | jq -r '.reason')" "SG-3"
T="$(tx)"; printf '%s\n' "$(jq -cn '{type:"assistant",message:{content:[{type:"text",text:"! gh pr view 5"}]}}')" >> "$T"
t_has "no message in the payload: the transcript's last text is read" \
  "$(payload "$T" "$(new_sid)" | CLAUDE_CONFIG_DIR="$CFG" sh "$GUARD" 2>/dev/null | jq -r '.systemMessage // ""')" "SG-3"
# The prompt list is derived from the scripts, never trusted: a bin/*.sh that prompts and is not
# in SG3_TTY is red here (comment lines are not prompts).
_tty="$(sed -n "s/^SG3_TTY='\(.*\)'\$/\1/p" "$GUARD")"
for _f in "$T_ROOT"/bin/*.sh; do
  awk '/^[ \t]*#/ { next } /\/dev\/tty|\[y\/N\]/ { f = 1; exit } END { exit !f }' "$_f" || continue
  t_has "$(basename "$_f") prompts, so SG3_TTY names it" "$_tty" "$(basename "$_f")"
done

t_section "D3: the hook never exits non-zero"
t_eq "invocations that exited non-zero" 0 "$(wc -l < "$RCF" | tr -d ' ')"
t_eq "guard-stop.sh ends with" "exit 0" "$(tail -1 "$GUARD")"
t_done
