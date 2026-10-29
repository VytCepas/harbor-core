#!/usr/bin/env sh
# guard-selfedit.sh (harbor#3, B2): its rule table, on an installed floor, and the shared benign corpus.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

G="$CLAUDE_CONFIG_DIR/bin/guard-selfedit.sh"
t_table  "$G" "$T_ROOT/tests/guards/selfedit.jsonl"
t_shared "$G" selfedit

# harbor#787: a config dir reached through a symlink, and a target whose parent does not exist yet (a
# new snapshot dir). floor_norm_path keeps the raw prefix there, so the raw root has to match too.
t_section "a config dir spelled through a symlink, parent not yet created"
ln -s "$CLAUDE_CONFIG_DIR" "$T_TMP/cfg-link"
for _p in backups/deploy-9/config.tgz .helm-context/s9 .helm-pins/new/x settings.json; do
  _rc=0; printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$T_TMP/cfg-link/$_p" \
    | CLAUDE_CONFIG_DIR="$T_TMP/cfg-link" sh "$G" >/dev/null 2>&1 || _rc=$?
  t_eq "a Write to <link>/$_p is refused" 2 "$_rc"
done
_rc=0; printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$T_TMP/cfg-link/MEMORY/new/x.md" \
  | CLAUDE_CONFIG_DIR="$T_TMP/cfg-link" sh "$G" >/dev/null 2>&1 || _rc=$?
t_eq "a Write to <link>/MEMORY/new/x.md stays allowed" 0 "$_rc"
t_done
