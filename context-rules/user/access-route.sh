#!/usr/bin/env sh
# 45-access-route-pointer — an access failure names its route card, and the account
# that card says to use, at the moment the failure happens.
#
# WHY (2026-09-24). The access register already answers the three questions a session
# gets wrong — which account to use, which role it holds, and whether it already
# holds enough — but nothing pointed at it when a call failed, so a session found
# it only if a memory note happened to be loaded. A 403 read as "we have no
# access" when the answer was "that is the wrong account" is the failure this
# exists for; the operator asked for it by name. A rule the model has to go and
# fetch does not bind (docs/reports/evals.md E6: 0/4 as prose in a runbook, 4/4 injected at
# the tool call), which is why this rides the call rather than a document.
#
# PostToolUse, NOT PostToolUseFailure. A Bash command that exits non-zero is a
# SUCCESSFUL tool call — measured, see tool-failure.sh — so the 401 or 403 lives
# in tool_response, on this event.
#
# SILENT UNLESS BOTH HOLD: the output carries an access-failure signature AND the
# command maps to a route card that exists. Reading ABOUT access — a grep over
# the private layer, the memory store, check-routes.sh printing cards — prints the very
# words this matches, and a note fired at the page that documents 403s is the
# false positive that gets a pack switched off (CONSTITUTION §2.11). `once:
# match` keys on the output, so the same failure retried is told once.
#
# FAIL-OPEN, like every path in this engine: no jq, no payload, no card, no routes
# table, and no access register at all (core ships no cards and no table, harbor#1149) —
# print nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
CMD="$(printf '%s' "$P" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0
# The response may be a string or an object of streams. Stringifying an object
# would escape the quotes this matches (`"code": 403`), so read the streams.
OUT="$(printf '%s' "$P" | jq -r '
  (.tool_response // "")
  | if type == "string" then .
    elif type == "object" then ([.stdout, .stderr, .output] | map(select(type == "string")) | join("\n"))
    else tostring end' 2>/dev/null || true)"
[ -n "$OUT" ] || exit 0

case "$CMD" in
  *check-routes*|*harbor-private/*|*/memory/*|*inject.d*|*context-rules*) exit 0 ;;
esac
# The first word AFTER any leading `cd <dir> &&`, because that prefix is how most
# commands on this box begin (bare `cd ~/…` is forbidden, so an absolute cd leads
# the compound). Without the strip, `cd /repo && sed -n 1,99p bin/<tool>` read as a
# `cd` and fired on the PERMISSION_DENIED in the source it printed (2026-09-24).
FIRST="$(printf '%s' "$CMD" | sed -E -e ':a' -e 's/^[[:space:]]*cd[[:space:]]+[^;&|]*(&&|;)[[:space:]]*//' -e 'ta' | awk '{ print $1 }')"
case "$FIRST" in
  grep|rg|ugrep|cat|sed|awk|head|tail|less|more|find|ls|echo|printf|git|diff|wc|jq|cut|sort|column|tr) exit 0 ;;
esac

SIG='Reauthentication failed|PERMISSION_DENIED|UNAUTHENTICATED|ACCESS_TOKEN_SCOPE_INSUFFICIENT|insufficient authentication scopes|invalid authentication credentials|invalid_grant|Access Denied: |does not have [A-Za-z0-9._]+ ?permission|HTTP/[0-9.]+ 40[13]|http=40[13]|"code": ?40[13]|Needs authentication|OAuthException|Error validating access token|401 Unauthorized|403 Forbidden'
HIT="$(printf '%s\n' "$OUT" | /usr/bin/grep -oE "$SIG" 2>/dev/null | head -1 || true)"
[ -n "$HIT" ] || exit 0

# The register comes from the one resolver (bin/scope-roots.sh --access, $ACCESS_DIR wins). Run from a
# checkout it is beside this file; installed, it is in the harbor checkout.
case "$0" in */*) _H="${0%/*}" ;; *) _H=. ;; esac
_R="$_H/../../bin/scope-roots.sh"
[ -f "$_R" ] && [ -f "$_H/../../contracts/roots.tsv" ] || _R="${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}/bin/scope-roots.sh"
DIR="$(sh "$_R" --access 2>/dev/null)" || exit 0
[ -n "$DIR" ] || exit 0

# Command -> card. The table is the register's own: <register>/routes.tsv, `pattern<TAB>card` per line (contracts/access-card.md),
# because which command belongs to which card names the systems this box reaches, and core names none (harbor#1149). No table
# is silence, like no card. First match wins, so the specific rows sit above the general ones: a `gcx me <tool>` against a
# project's own dataset is that project before it is the warehouse CLI, and that before it is gcloud. @B@ in a pattern is a word
# boundary for a CLI name, so `gh ` does not fire inside "high " and `cu ` not inside "focus ". Expanded by hand, not by sed:
# the class holds `&`, which a sed replacement reads as the matched text.
ROUTES="$DIR/routes.tsv"
[ -f "$ROUTES" ] || exit 0
B='(^|[[:space:];&|(/])'
SYS=''
while IFS='	' read -r _pat _card; do
  case "$_pat" in ''|'#'*) continue ;; esac
  # A card name is a file name inside the register and nothing else: a row cannot walk out of it.
  case "$_card" in ''|*[!A-Za-z0-9._-]*|.*) continue ;; esac
  while :; do
    case "$_pat" in *@B@*) _pat="${_pat%%@B@*}$B${_pat#*@B@}" ;; *) break ;; esac
  done
  if printf '%s' "$CMD" | /usr/bin/grep -qE -- "$_pat"; then SYS=$_card; break; fi
done < "$ROUTES"
[ -n "$SYS" ] || exit 0

CARD="$DIR/$SYS.md"
[ -f "$CARD" ] || exit 0
SHOWN="$(printf '%s' "$DIR" | sed "s#^$HOME#~#")"

# The card's own allocation, read live, so this note can never disagree with it.
USE="$(/usr/bin/grep -iE '^[[:blank:]]*account:' "$CARD" 2>/dev/null | sed 's/^[^:]*:[[:blank:]]*//' | awk -F'|' '
  function t(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { a = t($1); u = tolower(t($2)); c = t($4)
    if (u == "primary")  { p = p sep1 "`" a "` (" c ")"; sep1 = "; " }
    if (u == "fallback") { f = f sep2 "`" a "`"; sep2 = ", " }
    if (u == "never")    { n = n sep3 "`" a "`"; sep3 = ", " } }
  END { if (p != "") printf "use %s", p
        if (f != "") printf "; fall back to %s only if that fails", f
        if (n != "") printf "; never %s", n }')"

printf 'Access failure on **%s** (`%s`). Before retrying, switching tools or concluding there is no access, check the account' "$SYS" "$HIT"
if [ -n "$USE" ]; then printf ': the route card says %s.' "$USE"; else printf '.'; fi
printf ' What each account holds and provably cannot reach is in `%s/%s.md`, and every account against every system is `%s/ACCOUNTS.md`.' "$SHOWN" "$SYS" "$SHOWN"
case "$HIT" in
  'Reauthentication failed')
    printf ' `Reauthentication failed` is an expired login, not lost access: ask the operator to run `! gcx <role> gcloud auth login <account>` for the account above, then carry on.\n' ;;
  *)
    printf ' Tell the causes apart before concluding: a 401 is the credential, 403 SERVICE_DISABLED is the API, ACCESS_TOKEN_SCOPE_INSUFFICIENT is the token scope, and a plain 403 or PERMISSION_DENIED is often just the wrong account.\n' ;;
esac
