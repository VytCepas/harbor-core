#!/usr/bin/env sh
# 65-browser-route-harbor-chrome — a Claude-in-Chrome navigation to a vendor UI
# that `harbor chrome` covers is refused, and the refusal names the command.
#
# WHY (2026-09-30). contracts/browser-routing.md made `harbor chrome` row 4's first
# choice the same day, and a session still reached for Claude in Chrome twice,
# told the operator ads.reddit.com was "blocked", and only found the route when the
# operator named it. `harbor chrome` is a CLI, not an MCP, so ToolSearch never
# surfaces it; a memory line is a document the model must remember to consult. The
# operator asked for it to be enforced, so this rides the call and DENIES it.
#
# ONE LIST, NOT TWO. The hosts are read from contracts/browser-agent-hosts.txt —
# the allowlist `harbor chrome` itself enforces — so a host added there for the
# CLI is refused here in the same commit. The harbor checkout is found through
# projects.tsv beside this file, the registry the box packs already share.
#
# SILENT ON EVERYTHING ELSE. A host not on the list (a client site) is Claude in
# Chrome's to open; a lookalike (`ads.reddit.com.evil.test`) does not match,
# because the rule is "equal to a listed host or a subdomain of one" — the same
# test access-browser-agent.sh applies.
#
# EDITORS stay on Claude in Chrome: harbor chrome has no eval, so it cannot assert
# grid focus and wrote Sheets keys into the wrong cells after harbor#903 took
# docs.google.com (2026-10-06). harbor chrome still admits them for reading.
EDITORS="docs.google.com"
#
# FAIL-OPEN, like every path in this engine: no jq, no payload, no registry row,
# no hosts file — print nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0

case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR=. ;; esac
REG="$SELF_DIR/projects.tsv"
[ -f "$REG" ] || exit 0
H="$(awk -F'\t' '$1 == "harbor" { print $2; exit }' "$REG")"
case "$H" in "~"*) H="$HOME${H#\~}" ;; esac
HOSTS="$H/contracts/browser-agent-hosts.txt"
[ -n "$H" ] && [ -f "$HOSTS" ] || exit 0
# The private layer's own hosts (browser-hosts.txt: internal UIs and client tools, which core names none of), read
# beside the core list; absent is the core list alone (contracts/private-layer.md).
PHOSTS=""
if [ -f "$H/bin/scope-roots.sh" ]; then
  _pd="$(sh "$H/bin/scope-roots.sh" --private 2>/dev/null || true)"
  [ -z "$_pd" ] || PHOSTS="$_pd/browser-hosts.txt"
fi
[ -f "$PHOSTS" ] || PHOSTS="/dev/null"

# navigate carries .url; browser_batch carries navigate items in .actions.
URLS="$(printf '%s' "$P" | jq -r '
  .tool_input as $i
  | ([$i.url] + [($i.actions // [])[] | select(.name == "navigate") | .input.url])
  | .[] | select(type == "string" and . != "" and . != "back" and . != "forward")' 2>/dev/null || true)"
[ -n "$URLS" ] || exit 0

printf '%s\n' "$URLS" | while IFS= read -r U; do
  h="${U#*://}"; h="${h%%[/?#:]*}"
  h="$(printf '%s' "$h" | tr 'A-Z' 'a-z')"
  [ -n "$h" ] || continue
  _ed=0
  for e in $EDITORS; do
    case "$h" in "$e"|*."$e") _ed=1 ;; esac
  done
  [ "$_ed" = 0 ] || continue
  if cat "$HOSTS" "$PHOSTS" | grep -v '^[[:space:]]*#' | awk -v h="$h" '
       NF { l = tolower($1); n = length(l)
            if (h == l || (length(h) > n && substr(h, length(h) - n) == "." l)) { f = 1; exit } }
       END { exit !f }'; then
    printf 'HARBOR-DECISION deny: %s is a vendor UI that `harbor chrome` covers, and logged-in browser work there goes through it, not Claude in Chrome (contracts/browser-routing.md row 4; the operator'"'"'s own Chrome profile). Use the harbor_chrome MCP tools when they are listed (a confined Bash command cannot reach Chrome): mcp__harbor_chrome__attach, then mcp__harbor_chrome__goto with args ["%s"], and read it with mcp__harbor_chrome__snapshot. Without them, in Bash: harbor chrome attach  (once per session; the operator clicks Allow, then Connect), then: harbor chrome goto '"'"'%s'"'"'  and read it with: harbor chrome snapshot\n' "$h" "$U" "$U"
    exit 0
  fi
done
