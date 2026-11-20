#!/usr/bin/env sh
# 68-browser-last-tier — opening a vendor UI in harbor chrome names the tier the route card ranks above the browser (harbor#1507).
#
# WHY. access/ROUTING.md ranks the tiers cli > api > mcp > browser, and nothing applied that at the moment a session opens a
# vendor UI: measured 2026-10-18..11-14, the most-opened hosts were vendor UIs whose card has a cli or api route. A policy in a
# document does not bind (docs/reports/evals.md E6: 0/4 as prose, 4/4 injected at the call), so the note rides the call that
# opens the page. As a note it informs; the refusal is the chrome servers', which call --check below (operator-approved
# 2026-11-20), and a call whose task is the UI (Preview, an invite, a screen with no API) carries --ui=<why> past it.
#
# ONE SOURCE. Which host belongs to which system is the card's own `ui-hosts:` field (contracts/access-card.md), read from the
# register (bin/scope-roots.sh --access), so core names no vendor and no client host and a card edit moves the mapping.
# The tier and the first move are read live from the same card (`via:`, `use:`), so this note cannot disagree with it.
#
# ONCE PER SYSTEM, NOT ONCE PER PACK: the engine's `once:` keys on the pack, so this pack is `once: never` and keeps its own
# ledger, one line per system per session (skill-first-use.sh does the same).
#
# SILENT UNLESS ALL HOLD: a goto/tab_new URL (or a goto inside steps) whose host is equal to, or a subdomain of, a card's
# listed ui-host, and that card's leftmost `via:` tier is not browser or none. A lookalike host does not match.
# FAIL-OPEN like every path in this engine: no jq, no payload, no register, no session id for the ledger's file name
# (the note then fires each time, never silently drops) — print nothing, exit 0. ONE EXCEPTION, THE ALARM: a register that
# holds cards but not one `ui-hosts:` line is a mapping that broke, not "no route", and the note says so once a session.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
# --check <url>... is the chrome servers' api-first guard (operator 2026-11-20: "api access as priority", enforced): one line per
# match, card<TAB>tier<TAB>first move, with no ledger and no note, so the guard refuses every time where the note speaks once.
CHECK=0
if [ "${1:-}" = --check ]; then shift; CHECK=1; P="$(jq -cn '{tool_input:{args:$ARGS.positional}}' --args "$@")"; else P="$(cat)"; fi
[ -n "$P" ] || exit 0

# goto and tab_new carry the url in .args; steps carries {verb, args} items, and only a goto step opens a page.
URLS="$(printf '%s' "$P" | jq -r '
  .tool_input as $i
  | ([($i.args // [])[]] + [($i.steps // [])[] | select(.verb == "goto") | (.args // [])[0]])
  | .[] | select(type == "string" and . != "")' 2>/dev/null || true)"
[ -n "$URLS" ] || exit 0
SID="$(printf '%s' "$P" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "$SID" in *[!A-Za-z0-9._-]*) SID='' ;; esac

# The register: next to this file in a checkout, else the registered harbor checkout (as access-route.sh).
case "$0" in */*) _H="${0%/*}" ;; *) _H=. ;; esac
_R="$_H/../../bin/scope-roots.sh"
[ -f "$_R" ] && [ -f "$_H/../../contracts/roots.tsv" ] || _R="${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}/bin/scope-roots.sh"
DIR="$(sh "$_R" --access 2>/dev/null)" || exit 0
[ -d "$DIR" ] || exit 0
SHOWN="$(printf '%s' "$DIR" | sed "s#^$HOME#~#")"
_G=/usr/bin/grep; [ -x "$_G" ] || _G=grep

# host<TAB>card for every `ui-hosts:` line of a card (a file carrying `identity:`, which no README or generated file does),
# commas or blanks between hosts. A card name is a file name inside the register, so nothing walks out of it.
CARDS=0; MAP=''
for _f in "$DIR"/*.md; do
  [ -f "$_f" ] || continue
  "$_G" -qiE '^[[:blank:]]*identity:' "$_f" 2>/dev/null || continue
  CARDS=$((CARDS + 1))
  _c="${_f##*/}"; _c="${_c%.md}"
  case "$_c" in ''|*[!A-Za-z0-9._-]*|.*) continue ;; esac
  _m="$("$_G" -m1 -iE '^[[:blank:]]*ui-hosts:' "$_f" 2>/dev/null | sed 's/^[^:]*://' | tr ',A-Z' ' a-z' \
        | awk -v c="$_c" '{ for (i = 1; i <= NF; i++) printf "%s\t%s\n", $i, c }' || true)"
  [ -z "$_m" ] || MAP="$MAP$_m
"
done
[ "$CARDS" -gt 0 ] || exit 0

# The ledger. No session id, no ledger: the note fires every time rather than not at all.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SEEN=''
if [ -n "$SID" ]; then
  SEEN="$CFG/state/browser-last-tier/$SID.seen"
  mkdir -p "${SEEN%/*}" 2>/dev/null || SEEN=''
  [ -z "$SEEN" ] || find "${SEEN%/*}" -name '*.seen' -mtime +7 -exec rm -f {} + 2>/dev/null || true
fi
told() { [ -n "$SEEN" ] && [ -f "$SEEN" ] && "$_G" -qxF -- "$1" "$SEEN"; }
tell() { [ -z "$SEEN" ] || printf '%s\n' "$1" >> "$SEEN" 2>/dev/null || true; }

if [ -z "$MAP" ]; then
  [ "$CHECK" = 0 ] || exit 0   # the guard: no mapping is no match; the note below is the alarm
  told '#empty-map' && exit 0
  tell '#empty-map'
  printf 'The access register at %s holds %s route card(s) and not one `ui-hosts:` line, so no vendor UI host maps to a route and the cli-over-browser note is silent for every host. That is a broken mapping, not "no route": check the system'"'"'s card `via:` yourself before opening its UI in the browser, and have the `ui-hosts:` fields restored (contracts/access-card.md).\n' "$SHOWN" "$CARDS"
  exit 0
fi

printf '%s\n' "$URLS" | while IFS= read -r U; do
  # Userinfo before the port: in user:pw@host the first colon is not a port (review of harbor#1536).
  h="${U#*://}"; h="${h%%[/?#]*}"; h="${h##*@}"; h="${h%%:*}"
  h="$(printf '%s' "$h" | tr 'A-Z' 'a-z')"
  [ -n "$h" ] || continue
  # The longest listed host the URL's host equals or is a subdomain of.
  card="$(printf '%s' "$MAP" | awk -F'\t' -v h="$h" '
    NF >= 2 { l = $1; n = length(l)
      if ((h == l || (length(h) > n && substr(h, length(h) - n) == "." l)) && n > best) { best = n; c = $2 } }
    END { if (c != "") print c }')"
  [ -n "$card" ] || continue
  told "$card" && continue
  CARD="$DIR/$card.md"
  [ -f "$CARD" ] || continue
  tier="$("$_G" -m1 -iE '^[[:blank:]]*via:' "$CARD" 2>/dev/null | sed 's/^[^:]*://' | awk '{ gsub(/[>,]/, " "); print $1 }' || true)"
  case "$tier" in cli|api|mcp) ;; *) continue ;; esac
  use="$("$_G" -m1 -iE '^[[:blank:]]*use:' "$CARD" 2>/dev/null | sed 's/^[^:]*:[[:blank:]]*//' \
         | awk '{ i = index($0, ". "); if (i > 0) $0 = substr($0, 1, i); if (length($0) > 240) $0 = substr($0, 1, 237) "..."; if ($0 !~ /[.]$/) $0 = $0 "."; print }' || true)"
  [ -n "$use" ] || use="see the card"
  if [ "$CHECK" = 1 ]; then printf '%s\t%s\t%s\n' "$card" "$tier" "$use"; continue; fi
  tell "$card"
  printf '%s is reached at tier `%s`, ahead of the browser (the ladder is cli > api > mcp > browser, and the browser is the LAST tier). The card'"'"'s first move: %s Take that first; open %s here only when the task needs the UI (or that tier has failed, and say so), and then go ahead. Card: %s/%s.md.\n' \
    "$card" "$tier" "$use" "$h" "$SHOWN" "$card"
done
