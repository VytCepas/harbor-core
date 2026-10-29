#!/usr/bin/env sh
# guard-bash.sh (harbor#1313, release decision 23, lane L1): recursive deletes reaching HOME, the root or the
# config dir by a spelling the rm rules compared literally (a dot-glob after a cd, a home-star glob, an IFS
# separator, a brace word), on an installed floor. Rows generated from the review corpora by line number.
set -u
. "$(dirname "$0")/../lib/core.sh"
. "$(dirname "$0")/../lib/table.sh"
t_init
. "$T_ROOT/tests/guards/floor-fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/guards/bash.c1-rm-home-root.jsonl"
t_done
