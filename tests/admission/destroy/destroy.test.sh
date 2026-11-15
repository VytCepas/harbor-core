#!/usr/bin/env sh
# admission-destroy.sh (harbor#201): its rule table, its messages, and the shared shapes.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init

G="$T_ROOT/bin/admission-destroy.sh"
t_table  "$G" "$T_ROOT/tests/guards/destroy.jsonl"
t_msgs   "$G" "$T_ROOT/tests/admission/destroy/message.jsonl"
t_shared "$G" destroy
t_done
