#!/usr/bin/env sh
# admission-bash.sh (harbor#1313, release decision 23, lane L4): an unfiltered find whose destructive verb hid
# behind a wrapper, a value-taking xargs flag, a group opener, -ok/-okdir or an rsync delete flag, and a GNU
# multi-word rsync delete flag, on an installed floor. Rows generated from the review corpora by line number.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/c1-find-spray.jsonl"
t_done
