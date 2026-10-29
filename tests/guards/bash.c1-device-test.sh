#!/usr/bin/env sh
# guard-bash.sh (harbor#1313, lane L2 device): the raw-device wipe, discard, partition and format fixes, and the
# dd-family writes onto critical system files, on an installed floor. Modelled on bash.p14-test.sh. Rows are the
# fixed tree's own verdicts (gen-rows-l2.sh, kept out of the repo). The device-node-replace asks are guard-destroy's:
# destroy.c1-device-test.sh.
set -u
. "$(dirname "$0")/../lib/core.sh"
. "$(dirname "$0")/../lib/table.sh"
t_init
. "$T_ROOT/tests/guards/floor-fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/guards/bash.c1-device.jsonl" "device destruction (guard-bash)"
t_done
