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
# AND A NON-ZERO BASH EXIT IS NOT A TOOL FAILURE. The same probe ran a command
# that exited 1 and the harness fired PostToolUse, not this event: the tool did
# its job, and the shell's verdict is part of a successful result. What lands here
# is the tool itself refusing — a missing file, an Edit whose anchor did not
# match, a denied permission. That is a narrower and better-behaved trigger than
# "something went wrong", and it is why `once: session` is enough.
#
# FAIL-OPEN, like every other path in this engine: no jq, unreadable stdin, an
# unexpected shape — print nothing, exit 0. A hook whose failure mode is noise is
# a hook the operator removes.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
[ "$(printf '%s' "$P" | jq -r '.is_interrupt // false' 2>/dev/null || echo true)" = false ] || exit 0
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
