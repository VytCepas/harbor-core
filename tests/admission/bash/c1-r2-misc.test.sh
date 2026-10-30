#!/usr/bin/env sh
# admission-bash.sh (harbor#1313, round 2, lane L10): zsh glob qualifiers and modifiers, an IFS brace, an ANSI-C NUL
# word, a parallel-wrapped delete, a decoded command word, cp onto a disk node, a glob redirect onto a system file,
# a path-qualified env before an interpreter, and a push option value that starts with a plus. Rows by line number.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/admission-bash.sh" "$T_ROOT/tests/admission/bash/c1-r2-misc.jsonl"
t_done
