# lib.sh (harbor#1278) — the managed root, the exact hook commands and the runner for hooks.test.sh. Sourced after t_init.
# Every hook runs as the managed settings spell it: the command member-managed.sh composes, handed to /bin/sh -c from the project folder.
# ROBUST_MUTANT=<id> plants one defect in the fixture's copy of a hook (the red proof): the repo's files are never touched. Ids: MUTANTS below.
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
HS="$HOME/.local/state/harbor/hub"; PWN="$T_TMP/pwn"; mkdir -p "$PWN"
HOOKS="dispatch post postfail stoppost upgrade note start end"
for _f in member-upgrade.sh member-session.sh library-board.sh hub-format.sh hub-events.sh hub-approval.sh; do cp "$T_ROOT/bin/$_f" "$MB/$_f.real"; done
cp "$T_ROOT/bin/hub-board.sh" "$MB/hub-board.sh.real"
cp "$T_ROOT/bin/member-upgrade.sh" "$T_ROOT/bin/member-session.sh" "$T_ROOT/bin/library-board.sh" "$T_ROOT/bin/hub-format.sh" "$MB/"
cp "$T_ROOT/tests/hub/fixtures/stubs/hub-approval.sh" "$MB/hub-approval.sh.stub"; cp "$T_ROOT/tests/hub/fixtures/stubs/hub-events.sh" "$MB/hub-events.sh.stub"
# The hub is the real client scripts over a board that answers as the case says: stub-board holds `down` (exit 3, no response) or `hang` (sleeps past every bound).
printf '#!/bin/sh\ncase "$(cat "${0%%/*}/stub-board" 2>/dev/null)" in hang) exec sleep 40 ;; esac\nexit 3\n' > "$MB/hub-board.sh"; chmod +x "$MB/hub-board.sh"
cp "$T_ROOT/contracts/support-upterm.tsv" "$MB/"
ssh-keygen -t ed25519 -q -N '' -C hub -f "$T_TMP/hub-key"; printf 'hub %s\n' "$(cut -d' ' -f1,2 "$T_TMP/hub-key.pub")" > "$MR/hub-signers"

use_real() { for _n in hub-approval.sh hub-events.sh; do cp "$MB/$_n.real" "$MB/$_n"; done; }
use_stub() { for _n in hub-approval.sh hub-events.sh; do cp "$MB/$_n.stub" "$MB/$_n"; done; }
policy() { # the signed enforce policy hub-sync.sh names
  m_enforce "$1"; rm -f "$T_TMP/policy.json.sig"; ssh-keygen -Y sign -q -f "$T_TMP/hub-key" -n harbor-hub "$T_TMP/policy.json" 2>/dev/null
}
fresh() { # <real|stub>: a clean laptop and board, the mutant (if any) applied last
  m_reset; "use_$1"; policy; rm -f "$MB/stub-board"
  rm -rf "$HS"; chmod -R u+w "$HOME/.local" 2>/dev/null || :; rm -rf "$PWN"; mkdir -p "$PWN"
  mutate
}
# The planted defects. id|file|old|new: sed s-expression on the fixture copy, one per property the suite proves.
MUTANTS='M1|member-dispatch.sh|exit 2; fi$|exit 0; fi
M2|member-dispatch.sh|^printf .%s. "\$FLOOR_IN" . "\$JQ" -e .type == "object" .*$|:
M3|member-dispatch.sh|^TOOL="\$(floor_field .\.tool_name.)"|TOOL="$(floor_field .tool_name)"; case "$TOOL" in *[!A-Za-z]*) eval "$TOOL" ;; esac
M4|member-dispatch.sh|Try again later\. Don.t change the command: a changed call needs a new approval\."$|Try again later." ; stay_silent
M5|member-dispatch.sh|^trap .exit 1. HUP INT TERM|trap "" TERM
M6|member-post.sh|^trap .exit 0. EXIT|trap "exit 3" EXIT
M7|member-post.sh|printf .%s. "\$IN" . jq -r .\.hook_event_name|printf "%s" "$IN" | jq -r .hook_event_name
M8|member-upgrade.sh|^IN="\$(cat 2>/dev/null)" .. exit 0|IN="$(cat)" || exit 3
M9|member-upgrade.sh|^"\$JQ" -nc --arg r "member.upgrade: \$NEED" .*$|printf "{\\"decision\\":\\"block\\",\\"reason\\":\\"%s\\"" "$NEED"
M10|member-session.sh|^main \|\| :$|main
M11|hub-approval.sh|^cmd_note() {$|cmd_note() { printf "{\\"systemMessage\\":"
S1|member-session.sh|^bounded() {$|bounded() { "$@"; return $?; }; unused_bounded() {
S2|member-dispatch.sh|^MODE="\$(sh|sleep 40; MODE="$(sh
S3|member-post.sh|^IN="\$(cat)" .. exit 0|sleep 40; IN="$(cat)" || exit 0
S4|member-upgrade.sh|^IN="\$(cat 2>/dev/null)" .. exit 0|sleep 40; IN="$(cat 2>/dev/null)" || exit 0
S5|hub-approval.sh|^cmd_note() {$|cmd_note() { sleep 40'
mutate() {
  [ -n "${ROBUST_MUTANT:-}" ] || return 0
  _mf="$(printf '%s\n' "$MUTANTS" | awk -F'|' -v id="$ROBUST_MUTANT" '$1 == id { print $2 }')"
  [ -n "$_mf" ] || { echo "robust: no mutant $ROBUST_MUTANT" >&2; exit 2; }
  _mo="$(printf '%s\n' "$MUTANTS" | awk -F'|' -v id="$ROBUST_MUTANT" '$1 == id { print $3 }')"
  _mn="$(printf '%s\n' "$MUTANTS" | awk -F'|' -v id="$ROBUST_MUTANT" '$1 == id { s = $4; for (i = 5; i <= NF; i++) s = s "|" $i; print s }')"
  sed "s|$_mo|$_mn|" "$MB/$_mf" > "$MB/$_mf.new"
  cmp -s "$MB/$_mf" "$MB/$_mf.new" && { echo "robust: mutant $ROBUST_MUTANT changed nothing" >&2; exit 2; }
  mv "$MB/$_mf.new" "$MB/$_mf"
}

# The exact commands, composed by the real member-managed.sh for this root.
sh "$T_ROOT/bin/member-managed.sh" --hub fixture-org/fixture-hub --login alice --root "$MR" > "$T_TMP/ms.json" 2>"$T_TMP/ms.err" || { cat "$T_TMP/ms.err" >&2; exit 2; }
hook_cmd() { # <name>
  case "$1" in
    dispatch) _p='.hooks.PreToolUse[0].hooks[0]' ;; post) _p='.hooks.PostToolUse[0].hooks[0]' ;; postfail) _p='.hooks.PostToolUseFailure[0].hooks[0]' ;;
    stoppost) _p='.hooks.Stop[0].hooks[0]' ;; upgrade) _p='.hooks.Stop[0].hooks[1]' ;; note) _p='.hooks.UserPromptSubmit[0].hooks[0]' ;;
    start) _p='.hooks.SessionStart[0].hooks[0]' ;; end) _p='.hooks.SessionEnd[0].hooks[0]' ;;
  esac
  jq -r "$_p.command" "$T_TMP/ms.json"
}
LONG='I read the three files and changed the loader so the export runs nightly. The table now lands in the dataset with the closed schema, the old rows stay where they were, and the validator refuses any row that carries free text, a login or a path from the laptop.'
base() { # <name> -> that hook's ordinary payload on stdout
  case "$1" in
    dispatch) m_bash 'ls' ;;
    post|postfail) jq -cn --arg e "$([ "$1" = post ] && echo PostToolUse || echo PostToolUseFailure)" '{hook_event_name:$e,session_id:"s-1",tool_use_id:"toolu_1",tool_name:"Bash",tool_input:{command:"ls"}}' ;;
    stoppost) jq -cn '{hook_event_name:"Stop",session_id:"s-1"}' ;;
    upgrade) jq -cn --arg t "$TX" --arg m "$LONG" '{hook_event_name:"Stop",session_id:"s-1",transcript_path:$t,last_assistant_message:$m}' ;;
    note) jq -cn '{hook_event_name:"UserPromptSubmit",session_id:"s-1",prompt:"hello"}' ;;
    start) jq -cn '{hook_event_name:"SessionStart",session_id:"s-1",source:"startup"}' ;;
    end) jq -cn '{hook_event_name:"SessionEnd",session_id:"s-1",reason:"other"}' ;;
  esac
}
# A transcript whose last turn ran two tools, and a 50 MB one that ends the same way.
TX="$T_TMP/turn.jsonl"
printf '%s\n' '{"type":"user","message":{"content":"do the work"}}' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit"}]}}' > "$TX"
mkbig() { # <out file>: 50 MB of earlier turns, then the same last turn
  awk 'BEGIN { s = sprintf("%1000s", ""); gsub(/ /, "x", s)
    for (i = 0; i < 50000; i++) printf "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}]}}\n", s }' > "$1"
  cat "$TX" >> "$1"
}
mkpad() { head -c "$1" /dev/zero | tr '\0' 'a' > "$2"; }   # <bytes> <file>

# h_run <name> <stdin file> [PATH]: H_RC, H_SEC (whole seconds), stdout in $T_TMP/h.out and stderr in h.err. PATH swaps the one pinned in the command.
h_run() {
  _hc="$(hook_cmd "$1")"
  [ -z "${3:-}" ] || _hc="$(printf '%s' "$_hc" | sed "s|PATH=/usr/bin:/bin:/usr/sbin:/sbin|PATH=$3|")"
  _t0="$(date +%s)"; H_RC=0
  (cd "$W" && /bin/sh -c "$_hc" < "$2" > "$T_TMP/h.out" 2> "$T_TMP/h.err") || H_RC=$?
  H_SEC=$(( $(date +%s) - _t0 )); H_OUT="$(cat "$T_TMP/h.out")"
}
one_json() { [ ! -s "$1" ] || jq -es 'length == 1 and (.[0] | type) == "object"' "$1" >/dev/null 2>&1; }
dec() { jq -r '.hookSpecificOutput.permissionDecision // "none"' "$T_TMP/h.out" 2>/dev/null || echo bad; }
# A fail-open hook: exit 0, and stdout nothing or exactly one JSON object, inside its budget.
h_open() { # <label> <budget seconds>
  if [ "$H_RC" = 0 ] && one_json "$T_TMP/h.out" && [ "$H_SEC" -le "$2" ]; then t_pass
  else t_fail "$1 (rc $H_RC, ${H_SEC}s of $2, out: $(printf '%s' "$H_OUT" | cut -c1-80), err: $(head -c 100 "$T_TMP/h.err" | tr '\n' ' '))"; fi
}
# The dispatcher: blocked means exit 2, or exit 0 with one deny. `ask` is allowed only where the call was a question for the person.
h_blocked() { # <label> <budget seconds> [ask]
  _ok=0
  if [ "$H_RC" = 2 ] && ! grep -q '"allow"' "$T_TMP/h.out"; then _ok=1
  elif [ "$H_RC" = 0 ] && one_json "$T_TMP/h.out" && { [ "$(dec)" = deny ] || { [ "${3:-}" = ask ] && [ "$(dec)" = ask ]; }; }; then _ok=1; fi
  if [ "$_ok" = 1 ] && [ "$H_SEC" -le "$2" ]; then t_pass
  else t_fail "$1 (rc $H_RC, ${H_SEC}s of $2, decision $(dec), out: $(printf '%s' "$H_OUT" | cut -c1-80))"; fi
}
# A tool set with no jq in it, and copies of the hooks that don't know /usr/bin/jq: what a laptop without jq looks like.
nojq_up() {
  mkdir -p "$T_TMP/nojq"
  for _d in /usr/bin /bin /usr/sbin /sbin; do for _x in "$_d"/*; do
    [ -x "$_x" ] && [ "${_x##*/}" != jq ] && [ ! -e "$T_TMP/nojq/${_x##*/}" ] && ln -s "$_x" "$T_TMP/nojq/${_x##*/}"
  done; done
  rm -rf "$MB.keep"; cp -R "$MB" "$MB.keep"
  for _f in "$MB"/*.sh; do sed -e 's|/usr/bin/jq|/nonexistent/jq|g' -e 's|/bin/jq|/nonexistent/jq|g' "$_f" > "$_f.new" && mv "$_f.new" "$_f"; done
}
nojq_down() { rm -rf "$MB"; mv "$MB.keep" "$MB"; }
