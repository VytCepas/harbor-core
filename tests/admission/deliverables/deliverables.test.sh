#!/usr/bin/env sh
# guard-deliverables.sh (harbor#402): its rule table, its messages, and the shared shapes.
# The rule is "which directory is this", so the sandbox HOME is the fixture.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init

G="$T_ROOT/bin/guard-deliverables.sh"
mkdir -p "$HOME/Desktop" "$HOME/Documents/repo" "$HOME/Downloads" \
         "$HOME/Deliverables/2026-09-02-thing" "$HOME/proj"
: > "$HOME/Documents/repo/.git"          # a repo parked in a dropzone
: > "$HOME/Documents/kept-by-hand.html"  # already there, so the operator filed it
: > "$HOME/existing.md"

t_table  "$G" "$T_ROOT/tests/guards/deliverables.jsonl"
t_msgs   "$G" "$T_ROOT/tests/admission/deliverables/message.jsonl"
t_shared "$G" deliverables
t_done
