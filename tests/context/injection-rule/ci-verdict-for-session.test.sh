#!/usr/bin/env sh
# ci-verdict-for-session.test.sh (harbor#1044) — the CI watch's note reaches the session that opened the PR, through the
# real engine, on its next tool call: printed once, then gone; another session's note is never printed; no note, no text.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE
T="$T_TMP"; CFG="$CLAUDE_CONFIG_DIR"; U="$T_ROOT/context-rules/user"; BOX="$CFG/context-rules/user"
mkdir -p "$BOX" "$CFG/bin"
cp "$U/ci-verdict-for-session.md" "$U/ci-verdict-for-session.sh" "$BOX/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"
HARBOR_SCOPE_REPO="$T_ROOT"; export HARBOR_SCOPE_REPO
export HARBOR_STATUS_DIR="$T/state"; ND="$HARBOR_STATUS_DIR/session-notes"; mkdir -p "$ND"
call() { # <session id> [tool] → the engine's note for one PostToolUse, in $NOTE
  NOTE="$(printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"command":"ls"},"session_id":"%s"}' "${2:-Bash}" "$1" \
    | CLAUDE_PROJECT_DIR="$T" /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
}

t_section "a note for this session is printed on its next tool call, once"
printf '2026-11-16T14:55:35Z [check:event.session-ci-watch] PR acme/widgets#9: checks stuck: still running after 120m, watch stopped — failed: public mirror cancel\n' > "$ND/sessA"
call sessA
t_has "the note is the pack's" "$NOTE" "[context:ci-verdict-for-session]"
t_has "...and carries the verdict, naming the stuck job" "$NOTE" "PR acme/widgets#9: checks stuck"
t_has "...and the cancelled job" "$NOTE" "failed: public mirror cancel"
t_eq "the note file is gone once printed" no "$([ -e "$ND/sessA" ] && echo yes || echo no)"
call sessA
t_eq "the next call says nothing more" "" "$NOTE"
printf '2026-11-16T15:30:00Z [check:event.session-ci-watch] PR acme/widgets#9: checks green\n' > "$ND/sessA"
call sessA Read
t_has "a later verdict is a new note, printed on a Read too" "$NOTE" "PR acme/widgets#9: checks green"

t_section "another session's note, an unsafe id, or no note: silence"
printf 'x [check:event.session-ci-watch] PR acme/widgets#10: checks red\n' > "$ND/sessB"
call sessA
t_eq "session A never sees session B's note" "" "$NOTE"
t_eq "...which stays for B" yes "$([ -s "$ND/sessB" ] && echo yes || echo no)"
call '../sessB'
t_eq "a session id with a path in it names no file" "" "$NOTE"
call sessC
t_eq "no note file: no text at all" "" "$NOTE"
t_done
