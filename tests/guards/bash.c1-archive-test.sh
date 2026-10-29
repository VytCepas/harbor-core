#!/usr/bin/env sh
# guard-bash.sh (harbor#1313, release decision 23, lane L5): an archive extracted into the root, the home
# dir or a dir above the config dir, whose members decide where files land, on an installed floor. Rows
# generated from the review corpus by line number, with the ordinary extraction beside them allowed.
set -u
. "$(dirname "$0")/../lib/core.sh"
. "$(dirname "$0")/../lib/table.sh"
t_init
. "$T_ROOT/tests/guards/floor-fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/guards/bash.c1-archive.jsonl"
t_done
