#!/usr/bin/env sh
# guard-egress.sh (harbor#3, B4): its rule table, on an installed floor, and the shared shapes.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

G="$CLAUDE_CONFIG_DIR/bin/guard-egress.sh"
# harbor#783: gh body files the rows name as {tmp}/gh-body-*. The live token is
# assembled here so this file carries no token shape of its own.
printf 'notes\nkey ghp_%s\n' 'AbCdEfGhIjKlMnOpQrStUv' > "$T_TMP/gh-body-live.md"
cp "$T_TMP/gh-body-live.md" "$HOME/gh-body-home.md"
printf 'example ghp_ABCDEFGHIJKLMNOPQRSTUV and AKIAIOSFODNN7EXAMPLE\n' > "$T_TMP/gh-body-placeholder.md"
printf 'summary\n' > "$T_TMP/gh-body-clean.md"
mkfifo "$T_TMP/gh-body-fifo"
# harbor#795: four clean 1 MiB files fill the 4 MiB scan budget.
for _i in 1 2 3 4; do yes 'the quick brown fox jumps over the lazy dog' | head -c 1048576 > "$T_TMP/gh-body-mib$_i.md"; done
t_table  "$G" "$T_ROOT/tests/guards/egress.jsonl"
t_shared "$G" egress
t_done
