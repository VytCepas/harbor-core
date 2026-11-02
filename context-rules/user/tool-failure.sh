#!/usr/bin/env sh
# 85-tool-failure-is-not-a-result — the note, and the one case it must not fire on.
#
# A `run:` SCRIPT RATHER THAN A BODY, FOR ONE REASON: `is_interrupt`. The operator
# pressing Ctrl+C produces a PostToolUseFailure like any other, and a note reading
# "that call did not run, decide what it costs" delivered to a session the OPERATOR
# just stopped is a false positive on the loudest possible trigger — CONSTITUTION
# §2.11, and the shape that gets a pack switched off in its first week. No
# predicate in the engine's fixed vocabulary can read that field, so the condition
# lives here.
#
# MEASURED, NOT ASSUMED (2026-09-02, claude 2.1.258, a nested `claude -p` with the
# event wired to a logging probe): the payload is `session_id`, `transcript_path`,
# `cwd`, `prompt_id`, `permission_mode`, `effort`, `hook_event_name`, `tool_name`,
# `tool_input`, `tool_use_id`, `error`, `is_interrupt`, `duration_ms`. There is NO
# `tool_response` on this event.
#
# AND A NON-ZERO BASH EXIT IS NOT A TOOL FAILURE. The 2026-09-02 probe saw it
# fire PostToolUse; by 2026-10-28 the harness sent it here as `Exit code N`, and
# the note fired a paragraph on `jq` exiting 2 over an absent optional file
# (harbor#1390). So the script now says it: a plain `Exit code N` is silent, a
# guard or permission refusal and a timeout still fire, and so does a tool that
# refused outright — a missing file, an Edit whose anchor did not match.
#
# FAIL-OPEN, like every other path in this engine: no jq, unreadable stdin, an
# unexpected shape — print nothing, exit 0. A hook whose failure mode is noise is
# a hook the operator removes.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
[ "$(printf '%s' "$P" | jq -r '.is_interrupt // false' 2>/dev/null || echo true)" = false ] || exit 0
# harbor#1390: a Bash call that ran and exited non-zero now lands here as `Exit code N`. The command DID run and
# its output is the result, so that is silent. A guard or permission refusal and a timeout are decisions: they fire.
E="$(printf '%s' "$P" | jq -r '.error // "" | tostring' 2>/dev/null)" || exit 0
case "$E" in
  *"HELM FLOOR"*|*"hook error"*|*BLOCKED*|*"Permission to use"*|*"requested permissions"*|*"timed out"*) ;;
  "Exit code "[0-9]*) exit 0 ;;
esac
cat <<'NOTE'
That tool call did not run, so it produced no evidence — and the cheapest moment
to decide what that costs is now, before the next call papers over it. If the
call was a VERIFICATION, you do not have the result you were about to claim: say
"not verified" and name the check that failed, rather than reaching for a weaker
one that did succeed — an unavailable verifier means defer, never substitute. If
it failed on a permission or a guard, that is a decision and not a transient, so
re-issuing the same call unchanged only spends another turn to be told the same
thing: change the approach, or ask. And if you route around this, the detour is
part of the answer — a step that was skipped is reported as skipped, in the
response, not left for the reader to infer from silence.
NOTE
