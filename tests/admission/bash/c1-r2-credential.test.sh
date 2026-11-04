#!/usr/bin/env sh
# admission-bash.sh (harbor#1313, round 2, lane L9): a delete or move that reaches the gcloud credential store through
# a glob in any component or through its parent dir, a glob in every component under HOME, and a two-level dot-glob
# after a cd into HOME, on an installed floor. Rows generated from the review corpora by line number.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/c1-r2-credential.jsonl"
t_done
