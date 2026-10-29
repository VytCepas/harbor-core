#!/usr/bin/env sh
# guard-bash.sh (harbor#3, B3): the shared shapes; its rule table runs as four part suites.
set -u
. "$(dirname "$0")/../lib/core.sh"
. "$(dirname "$0")/../lib/table.sh"
t_init
. "$T_ROOT/tests/guards/floor-fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_shared "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" bash
t_done
