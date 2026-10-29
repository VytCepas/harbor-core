#!/usr/bin/env sh
# guard-bash.sh (harbor#1313, lane L3): a pipe into a stdin-reading builtin, an interpreter or fish, on an installed floor.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/admission/bash/c1-pipe-interp.jsonl"
t_done
