#!/usr/bin/env sh
# admission-bash.sh (harbor#1149, docs/explanation/admission-baseline.md pass 13): the residual pass-13 spellings, on an installed floor.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/p13-residual.jsonl"
t_done
