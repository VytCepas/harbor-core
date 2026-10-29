#!/usr/bin/env sh
# guard-bash.sh (harbor#3, B3): the exec part of its rule table, on an installed floor.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/admission/bash/exec.jsonl"
t_done
