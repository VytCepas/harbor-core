#!/usr/bin/env sh
# admission-egress.sh (harbor#1278): the member-box rules, on an installed floor beside the root's member-mode marker. With no
# records file the guard refuses itself, as floor_member_stop does when member-dispatch.sh did not run it, so a fired rule is a block.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"
: > "$CLAUDE_CONFIG_DIR/bin/harbor-member-mode"
t_table "$CLAUDE_CONFIG_DIR/bin/admission-egress.sh" "$T_ROOT/tests/admission/egress/member.jsonl"
t_done
