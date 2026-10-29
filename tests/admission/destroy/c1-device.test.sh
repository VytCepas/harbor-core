#!/usr/bin/env sh
# guard-destroy.sh (harbor#1313, lane L2): moving or installing a file over a /dev node is asked (operator,
# 2026-10-18), run from the tree exactly as destroy-test.sh runs it. Rows are the fixed tree's own verdicts.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
cd "$T_ROOT"

t_table "$T_ROOT/bin/guard-destroy.sh" "$T_ROOT/tests/admission/destroy/c1-device.jsonl" "device-node replace (guard-destroy)"
t_done
