#!/usr/bin/env sh
# member-connectors.sh (harbor#1278, lane I; control member.connectors) — the person's side of a connector: enter its key, see what is stored.
#   sh member-connectors.sh key <ref>     ask the person for the key of a connector the policy declares, hidden, and put it in the company store
#   sh member-connectors.sh list          each connector of this laptop's policy, and whether its key is stored (names only, never a value)
# The agent never runs this. `key` refuses inside a Claude Code session (its environment names it), without a terminal of the person's own, and for any ref
# the root-owned <root>/connectors.json does not list: the ref and the words the person sees come from the signed policy, never from an argument or from the
# agent. The value is read from /dev/tty (not argv, not stdin of a caller, not the chat) and goes to bin/secret by a pipe. Every field is checked again on
# every put, so re-storing a ref that exists runs the same checks as the first store.
# Test seam, honoured only when no harbor-member-mode sits beside this file: HARBOR_MEMBER_CONNECTOR_VALUE_FILE (its first line is the value the terminal would give).
set -eu
CTL=member.connectors
case "${1:-}" in -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
_h0="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"; . "$_h0/library-log.sh"; log_init member-connectors; LOG_FD=2
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
case "$HERE" in */bin) ROOT="${HERE%/bin}" ;; *) printf '%s: this file is not in a managed root bin\n' "$CTL" >&2; exit 1 ;; esac
MARKER=0; [ -f "$HERE/harbor-member-mode" ] && [ ! -L "$HERE/harbor-member-mode" ] && MARKER=1
CONF="$ROOT/connectors.json"
no() { log_fail "$CTL: $1"; log_nofix "docs/how-to/member-install.md, A colleague's API key"; exit "${2:-1}"; }
command -v jq >/dev/null 2>&1 || no "jq is missing"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || no "this laptop's policy declares no connector ($CONF is missing)"

VERB="${1:-}"; [ $# -eq 0 ] || shift
case "$VERB" in
  list)
    [ $# -eq 0 ] || no "usage: member-connectors.sh list" 2
    _have="$(sh "$HERE/secret" list 2>/dev/null || :)"
    jq -r '.[] | [.name, .ref, .service] | @tsv' "$CONF" | while IFS="$(printf '\t')" read -r _n _r _s; do
      case "
$_have
" in *"
secret.$_r"[[:space:]]*|*"
secret.$_r
"*) _st=stored ;; *) _st='not stored' ;; esac
      printf '%s\t%s\t%s\t%s\n' "$_n" "$_r" "$_st" "$_s"
    done ;;
  key)
    [ $# -eq 1 ] || no "usage: member-connectors.sh key <ref>" 2
    REF="$1"
    # Not from a session: Claude Code's own variables, or the managed settings' env, mean an agent is the caller.
    if [ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}${HARBOR_MEMBER_ROLE:-}" ]; then no "this is for the person, in a terminal of their own, never inside a Claude Code session"; fi
    case "$REF" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789._-]*|[!abcdefghijklmnopqrstuvwxyz0123456789]*) no "'$REF' is not a name of a key" ;; esac
    case "$REF" in hub-*) no "'$REF' is a name the company keeps for itself" ;; esac
    _row="$(jq -c --arg r "$REF" '[.[] | select(.ref == $r)][0] // empty' "$CONF")" || _row=''
    [ -n "$_row" ] || no "no connector of this laptop's policy names '$REF'. Known: $(jq -r '[.[].ref] | join(" ")' "$CONF")"
    SVC="$(printf '%s' "$_row" | jq -r '.service')"; NAME="$(printf '%s' "$_row" | jq -r '.name')"
    [ -n "$SVC" ] && [ "${#SVC}" -le 120 ] && [ -z "$(printf '%s' "$SVC" | LC_ALL=C tr -d '[:print:]')" ] || no "the policy's words for '$REF' are not one printable line, so nothing is asked"
    if [ "$MARKER" = 0 ] && [ -n "${HARBOR_MEMBER_CONNECTOR_VALUE_FILE:-}" ]; then
      IFS= read -r _v < "$HARBOR_MEMBER_CONNECTOR_VALUE_FILE" || :
    else
      [ -t 0 ] && [ -t 2 ] || no "no terminal of your own to ask in. Open a terminal outside Claude Code and run this there"
      printf 'API key for %s (connector %s; typed here, hidden, never shown to your assistant): ' "$SVC" "$NAME" >&2
      stty -echo 2>/dev/null || :
      IFS= read -r _v || :
      stty echo 2>/dev/null || :; printf '\n' >&2
    fi
    _v="$(printf '%s' "$_v" | tr -d '\r\n')"
    [ "${#_v}" -ge 8 ] || no "nothing was stored: the value is empty or shorter than 8 characters, so it is not a key"
    [ "${#_v}" -le 4096 ] || no "nothing was stored: the value is longer than 4096 characters"
    [ -z "$(printf '%s' "$_v" | LC_ALL=C tr -d '[:print:]')" ] || no "nothing was stored: the value holds a control character"
    _hs=0; sh "$HERE/access.sh" has "$REF" >/dev/null 2>&1 || _hs=$?
    case "$_hs" in
      0|3) printf '%s' "$_v" | sh "$HERE/secret" put "$REF" >/dev/null 2>&1 || no "the store refused the new value for '$REF'; the old one is untouched" ;;
      4) no "'$REF' was revoked in the access register, so it is not stored again" ;;
      *) _e="$(printf '%s' "$_v" | sh "$HERE/access.sh" add "$REF" --kind token --what "API key for $SVC" \
           --use-when "the connector $NAME is used" --reaches "$SVC, through the MCP server $NAME only" \
           --cannot 'be shown to an assistant, or reach any program but that MCP server' --grant 'the person, typed in a terminal' \
           --revoke "retire the key at $SVC, then harbor access revoke $REF" --secret "$REF" --value-stdin 2>&1)" || no "nothing was stored: $(printf '%s' "$_e" | tr '\n' ' ' | cut -c1-240)" ;;
    esac
    _v=''
    log_ok "$CTL: the key for $REF is in the company store. Restart Claude Code, and its tools are there."; log_end || : ;;
  *) no "usage: member-connectors.sh key <ref> | list" 2 ;;
esac
