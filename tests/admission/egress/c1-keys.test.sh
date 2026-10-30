#!/usr/bin/env sh
# admission-egress.sh (harbor#1313, release decision 23, lane L6): a Grep filtered to private key files, which
# the Read deny list cannot stop because it binds only the searched directory, on an installed floor.
# Rows generated from the review corpus by line number. The lane's Read cases are pinned in sec0-harden-test.sh.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-egress.sh" "$T_ROOT/tests/admission/egress/c1-keys.jsonl"
t_done
