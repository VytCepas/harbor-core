#!/usr/bin/env sh
# 97-agent-model-required (harbor#843): deny an Agent call that leaves its model tier to inheritance.
#
# DENIES ONLY WHEN ALL THREE HOLD. Measured over the 14 days to 2026-09-30, 73 of
# 417 Agent calls were forks. A rule of "no model means deny" would have blocked
# every one of them wrongly (§2.11):
#   1. tool_input.model is absent or empty;
#   2. subagent_type is not `fork`, which always runs on the parent's model;
#   3. no definition of subagent_type declares a `model:` other than `inherit`.
#      It looks in <config>/agents and the project's .claude/agents, matching the
#      filename or the `name:` field. For `plugin:name` it looks in any installed
#      copy under <config>/plugins. If ANY copy pins a model, the call passes,
#      because the cache holds several versions and which one is live is not
#      visible from here. `pr-review-toolkit:code-reviewer` is `model: opus`.
# Built-in types (general-purpose, Explore, Plan) have no file to read, so they
# stay in scope. Explore and Plan are `inherit` in CLI 2.1.285.
#
# FAIL-OPEN, like every run: script in this engine. No jq, an empty or malformed
# payload, or a tool_input that is not an object prints nothing and exits 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
US="$(printf '\037')"
# One jq call for all three fields. They are joined on the unit separator, not a
# tab: tab is IFS whitespace, so `read` would collapse the empty field that
# condition 1 depends on.
F="$(printf '%s' "$P" | jq -r --arg us "$US" \
  '(.tool_input | if type == "object" then . else error("not an object") end) as $i
   | [($i.model // "" | tostring), ($i.subagent_type // "" | tostring), (.cwd // "" | tostring)] | join($us)' \
  2>/dev/null)" || exit 0
IFS="$US" read -r MODEL TYPE CWD <<EOF
$F
EOF
[ -z "$MODEL" ] || exit 0
[ "$TYPE" != fork ] || exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# The declared model of one definition, from its frontmatter only: quotes and a
# trailing comment are stripped, so `model: "opus"  # why` reads as opus.
pinned() { # <definition.md> → 0 iff it declares a model other than inherit
  _m="$(awk 'NR == 1 && !/^---/ { exit } NR > 1 && /^---/ { exit }
    NR > 1 && /^model:/ { sub(/^model:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); gsub(/["'\'']/, ""); gsub(/[[:space:]]/, ""); print; exit }' "$1" 2>/dev/null)" || return 1
  [ -n "$_m" ] && [ "$_m" != inherit ]
}
named() { # <definition.md> <name> → 0 iff the file is that agent, by filename or name: field
  _b="${1##*/}"; [ "${_b%.md}" = "$2" ] && return 0
  awk -v n="$2" 'NR == 1 && !/^---/ { exit 1 } NR > 1 && /^---/ { exit 1 }
    NR > 1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/["'\''[:space:]]/, ""); exit ($0 == n ? 0 : 1) }' "$1" 2>/dev/null
}
# A name that is not a plain identifier cannot select a definition. Without this,
# `demo-kit:*` would become a find pattern that matches every agent in the plugin.
case "$TYPE" in *[!A-Za-z0-9._:-]*) TYPE='' ;; esac
exempt=1
if [ -n "$TYPE" ]; then
  case "$TYPE" in
    *:*)
      _plug="${TYPE%%:*}"; _name="${TYPE#*:}"
      _defs="$(find "$CFG/plugins" -path "*/$_plug/*" -path '*/agents/*' -name '*.md' 2>/dev/null || true)" ;;
    *)
      _name="$TYPE"; _top=''
      [ -z "$CWD" ] || _top="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
      # `if`, never `[ -f ] && printf`: with no definitions anywhere, the last test
      # returned 1, the substitution failed, and `set -e` exited silently, which
      # allowed the call. That is the ordinary case on this box.
      _defs="$(for _d in "$CFG/agents" "${CLAUDE_PROJECT_DIR:-}/.claude/agents" "$CWD/.claude/agents" "$_top/.claude/agents"; do
        for _f in "$_d"/*.md; do if [ -f "$_f" ]; then printf '%s\n' "$_f"; fi; done
      done)" ;;
  esac
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    if named "$_f" "$_name" && pinned "$_f"; then exempt=0; break; fi
  done <<EOF
$_defs
EOF
fi
[ "$exempt" -eq 1 ] || exit 0

printf '%s\n' 'HARBOR-DECISION deny: Set `model` on this Agent call, and `effort` where named. Without a model the agent silently inherits this session'"'"'s model (harbor#818, enforced by harbor#843). haiku + effort medium: search, inventory, CI and log triage, polling, scans, one review lens. haiku + effort high: a scoped code change a test or script checks: fixes with tests, debugging, small features, refactors, doc updates. sonnet: after haiku fails a gate or refuses once, work nothing can check mechanically, multi-file or cross-repo changes, merge conflicts. opus: coordination, design, guard work, security review, final verification, or anything sonnet failed. Full rules: ~/.claude/skills/agent-routing/SKILL.md. Exempt: subagent_type fork, and an agent whose definition pins model:.'
