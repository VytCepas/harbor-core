#!/usr/bin/env sh
# admission-bash.sh (harbor#1313 round 2, lane L8): startup files and dirs, scheduler dirs and the ssh files that
# the RCFILE and SCHED lists left out, dd and in-place writers into them, and a relative crontab write after a
# cd into /etc. Rows generated from the review corpus by line number; allow rows pin reads and project files.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/c1-r2-paths.jsonl"
t_done
