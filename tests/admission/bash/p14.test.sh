#!/usr/bin/env sh
# guard-bash.sh (harbor#1149, docs/explanation/admission-baseline.md pass 14): the pass-14 fixes, on an installed floor.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/admission/bash/p14.jsonl"
t_done
