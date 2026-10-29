# tests/admission/bash/fixture.sh — the installed floor that bash, egress and selfedit rows run against.
# Source after t_init; tests/admission/baseline/fixture.sh builds on it. SEC-0 base, full floor install into
# $CLAUDE_CONFIG_DIR, and project dirs under {tmp}: governed, bare, empty-agents, and two forged markers.
# Only governed lacks a wired github_command_guard (harbor#954).
_fs="$T_ROOT/bin"; _fc="$CLAUDE_CONFIG_DIR"
mkdir -p "$_fc/bin" "$T_TMP/governed/.agents" "$T_TMP/bare" "$T_TMP/empty-agents/.agents" \
         "$T_TMP/forged-file" "$T_TMP/forged-link"
printf 'context: repo\nproject:\n  name: "governed"\n' > "$T_TMP/governed/.agents/config.yaml"
: > "$T_TMP/forged-file/.agents"
ln -s "$T_TMP/governed/.agents" "$T_TMP/forged-link/.agents"  # a real marker, so only the ! -L check blocks it
# harbor#954: the force-push rules stand down only where the repo wires github_command_guard. The
# refused markers wire it, so their rows still fail on the marker, not on a missing guard; governed does not.
for _d in empty-agents forged-file forged-link; do
  mkdir -p "$T_TMP/$_d/.claude"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\\"$CLAUDE_PROJECT_DIR\\"/.agents/hooks/github_command_guard.sh"}]}]}}\n' \
    > "$T_TMP/$_d/.claude/settings.json"
done
for _f in floor-hook.sh guard-lib.sh guard-selfedit.sh guard-bash.sh guard-egress.sh annotate-web.sh \
          floor-deny.sh floor-normalize.awk floor-observe.sh floor-install.sh guard-integrity.sh library-log.sh; do
  cp "$_fs/$_f" "$_fc/bin/$_f"
done
chmod +x "$_fc"/bin/*.sh
printf '{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}\n' > "$_fc/settings.json"
sh "$_fs/deploy-harden.sh" --apply --dir "$_fc" > /dev/null 2>&1
sh "$_fs/floor-install.sh" --apply --dir "$_fc" > /dev/null 2>&1
