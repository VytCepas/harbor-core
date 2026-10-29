#!/usr/bin/env sh
# guard-bash.sh (harbor#3, B3): the destroy part of its rule table, on an installed floor.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

# harbor#954: marked repos that do and do not wire github_command_guard, for the force-push rows.
_gw() { # <dir> <settings-file> <json>
  mkdir -p "$T_TMP/$1/.agents" "$T_TMP/$1/.claude" "$T_TMP/$1/sub"
  printf 'context: repo\n' > "$T_TMP/$1/.agents/config.yaml"
  printf '%s\n' "$3" > "$T_TMP/$1/.claude/$2"
}
_gcg='"\"$CLAUDE_PROJECT_DIR\"/.agents/hooks/github_command_guard.sh"'
_gw guarded-hook settings.json "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":$_gcg}]}]}}"
_gw guarded-local settings.local.json "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":$_gcg}]}]}}"
_gw guarded-plugin settings.json '{"enabledPlugins":{"project-init-lifecycle@project-init":true}}'
_gw guard-post-only settings.json "{\"hooks\":{\"PostToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":$_gcg}]}]}}"
_gw guard-named-only settings.json '{"permissions":{"allow":["Bash(.agents/hooks/github_command_guard.sh)"]}}'
_gw plugin-disabled settings.json '{"enabledPlugins":{"project-init-lifecycle@project-init":false}}'
_gw plugin-local-off settings.json '{"enabledPlugins":{"project-init-lifecycle@project-init":true}}'
printf '%s\n' '{"enabledPlugins":{"project-init-lifecycle@project-init":false}}' > "$T_TMP/plugin-local-off/.claude/settings.local.json"
_gw plugin-not-installed settings.json '{"enabledPlugins":{"project-init-lifecycle@elsewhere":true}}'
_gw guard-symlinked settings.local.json '{}'
ln -s "$T_TMP/guarded-hook/.claude/settings.json" "$T_TMP/guard-symlinked/.claude/settings.json"
# The plugin is installed on this box under one marketplace only.
mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
printf '%s\n' '{"version":2,"plugins":{"project-init-lifecycle@project-init":[{"scope":"user","installPath":"/nowhere","version":"1"}]}}' \
  > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/admission/bash/destroy.jsonl"
t_done
