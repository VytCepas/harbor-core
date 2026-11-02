#!/usr/bin/env sh
# 70-confinement-refused (harbor#1298) — a Bash call the confinement refused, and the decided treatment.
#
# Two refusal shapes, measured in #1297: a denied host arrives as a `<sandbox_violations>` block appended to
# the result; a denied write or read arrives as the tool's own "Operation not permitted", with no block. The
# block is the sandbox's alone, so it fires on its own; the bare phrase also comes from macOS privacy refusals,
# so it fires only while the confinement is installed (the marker deploy-confinement.sh leaves). A call that ran
# outside the sandbox (dangerouslyDisableSandbox) was not refused by it. Fail-open: print nothing, exit 0.
set -u
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
[ "$(printf '%s' "$P" | jq -r '.tool_input.dangerouslyDisableSandbox // false' 2>/dev/null || echo true)" = false ] || exit 0
R="$(printf '%s' "$P" | jq -r '(.tool_response // empty) | tostring' 2>/dev/null)" || exit 0
case "$R" in
  *'<sandbox_violations>'*) : ;;
  *'Operation not permitted'*)
    if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then MK="$(dirname "$HARBOR_MANAGED_SETTINGS")/harbor-confinement"
    else case "$(uname -s)" in
      Darwin) MK='/Library/Application Support/ClaudeCode/harbor-confinement' ;;
      *) MK=/etc/claude-code/harbor-confinement ;;
    esac; fi
    [ -f "$MK" ] || exit 0 ;;
  *) exit 0 ;;
esac
cat <<'NOTE'
The confinement refused part of that call — the OS sandbox, not a guard, and not
a transient. The treatment for each kind is already decided:
- A host off the list: name it to the operator. A host the box needs goes in the
  private layer's confinement-hosts.txt and the operator re-runs the install.
- A write outside the zone: confined writes land in $PORT_ROOT, ~/Deliverables and
  $TMPDIR. Name temp files under it (mktemp "${TMPDIR:-/tmp}/x.XXXXXX"); a bare
  mktemp is refused. Writes into ~/.claude (session title, memory) go through the
  Write tool, never a shell redirect.
- A credential file: denied by design. gh, git and gcx read the token the
  access-confinement hook mints before each call, so call them, not the file.
Retrying outside the sandbox is the escape the #555 stop rule counts; when one is
needed, say why in the response.
NOTE
