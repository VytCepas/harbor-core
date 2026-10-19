#!/usr/bin/env sh
# browser-hosts-add.sh (harbor#900) — propose a host for `harbor chrome` goto/tab-new, and on --apply
# write it to CONTRACTS/browser-agent-hosts.txt in the file's own shape.
#
#   sh bin/browser-hosts-add.sh --why "<vendor — what it is>" <host>...           dry run: checks + diff
#   sh bin/browser-hosts-add.sh --why "<vendor — what it is>" <host>... --apply   write the block
#   --no-probe   skip the anonymous `curl -L` redirect measurement
#
# The dry run writes nothing, so an agent can propose a host and show the diff. --apply is the
# operator's step; it edits this checkout only. The live box reads the DEPLOYED copy, so the gate
# that counts is the PR review, the merge and deploy.sh (the file's rule: "a reviewed change").
# Stdout is the diff; the log goes to stderr.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HERE%/bin}"
LOG_FD=2
. "$HERE/log-lib.sh"
log_init browser-hosts-add

HOSTS_FILE="${HARBOR_HOSTS_FILE:-$ROOT/CONTRACTS/browser-agent-hosts.txt}"   # test seam
CURL="${HARBOR_CURL:-curl}"                                                    # test seam

_usage() { sed -n '/^#   sh bin\/browser-hosts-add.sh --why/,/^#   --no-probe/p' "$0" | sed 's/^# \{0,2\}//'; }
_refuse() { log_fail "$1"; log_fix "${2:-sh bin/browser-hosts-add.sh --help}"; log_end || :; exit 1; }

WHY='' APPLY=0 PROBE=1 HOSTS=''
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) _usage; exit 0 ;;
    --apply) APPLY=1 ;;
    --no-probe) PROBE=0 ;;
    --why) [ $# -ge 2 ] || _refuse '--why needs a value'; WHY="$2"; shift ;;
    -*) _refuse "unknown flag: $1" ;;
    *) HOSTS="${HOSTS:+$HOSTS }$1" ;;
  esac
  shift
done

[ -f "$HOSTS_FILE" ] || _refuse "missing host allowlist: $HOSTS_FILE" 'git checkout -- CONTRACTS/browser-agent-hosts.txt'
[ -n "$HOSTS" ] || _refuse 'no host given'

# --why becomes the comment the suite requires above every host line: one line, said in words.
case "$WHY" in
  '') _refuse 'no --why: every host sits under a comment naming its vendor and why it is here' \
        "sh bin/browser-hosts-add.sh --why 'Vendor — the UI it is' <host>" ;;
esac
case "$WHY" in *'
'*) _refuse '--why must be one line' ;; esac
[ "${#WHY}" -le 200 ] || _refuse "--why is ${#WHY} chars; keep it under 200"
WHY="${WHY#\#}"; WHY="${WHY# }"

# A host already admitted by a listed line (equal, or a subdomain of one) — the same rule as
# _host_ok in bin/browser-agent.sh. Prints the admitting line.
_admitted_by() {
  while IFS= read -r _l; do
    case "$_l" in ''|'#'*) continue ;; esac
    [ "$1" = "$_l" ] && { printf '%s' "$_l"; return 0; }
    case "$1" in *".$_l") printf '%s' "$_l"; return 0 ;; esac
  done < "$HOSTS_FILE"
  return 1
}

NOTES=''
for h in $HOSTS; do
  case "$h" in *://*|*/*) _refuse "'$h' is not a bare host: give the host only, no scheme or path" ;; esac
  case "$h" in *[ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) _refuse "'$h' has upper case: hosts are listed lower case" ;; esac
  case "$h" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*|.*|*.|*..*|-*) _refuse "'$h' is not a plain host name [a-z0-9.-]" ;; esac
  # A line admits every subdomain, so two labels admit a whole registrable domain (example.com, google.com).
  _dots="$(printf '%s' "$h" | tr -cd '.')"
  [ "${#_dots}" -ge 2 ] || _refuse "'$h' has only two labels: a line admits every subdomain, so it would admit all of *.$h" \
    "list the one app host instead, e.g. app.$h"
  if _by="$(_admitted_by "$h")"; then _refuse "'$h' is already admitted by the line '$_by'"; fi
  log_ok "$h: plain, at least three labels, not yet admitted"
  if [ "$PROBE" = 1 ]; then
    _r="$("$CURL" -sSL -o /dev/null --max-time 20 -A 'Mozilla/5.0' -w '%{http_code} %{url_effective}' "https://$h/" 2>/dev/null)" || _r=''
    _code="${_r%% *}"; _end="${_r#* }"; _end="${_end#https://}"; _end="${_end#http://}"; _end="${_end%%/*}"; _end="${_end%%\?*}"
    if [ -z "$_r" ] || [ "$_code" = 000 ]; then
      log_warn "$h: no answer over https anonymously; listed unmeasured"
    elif [ "$_end" = "$h" ]; then
      log_ok "$h: anonymous curl -L stays on $h (HTTP $_code)"
      NOTES="${NOTES:+$NOTES; }$h stays on itself"
    else
      if _by="$(_admitted_by "$_end")"; then
        log_ok "$h: anonymous curl -L lands on $_end, admitted by '$_by'"
      else
        log_warn "$h: anonymous curl -L lands on $_end, which is NOT listed — signed out, goto will be refused there"
      fi
      NOTES="${NOTES:+$NOTES; }$h lands on $_end signed out"
    fi
  fi
  log_note "review: is $h a client live site? Those go through TagScope, never here"
done

# The block, in the file's shape: blank line, comment(s), host lines.
TODAY="$(date -u +%Y-%m-%d)"
BLOCK="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; NEW="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
trap 'rm -f "$BLOCK" "$NEW"' EXIT
{
  printf '\n'
  printf '%s\n' "$WHY" | fold -s -w 86 | sed 's/ *$//; s/^/# /'
  [ -n "$NOTES" ] && printf '%s\n' "anonymous curl -L, $TODAY: $NOTES" | fold -s -w 86 | sed 's/ *$//; s/^/# /'
  for h in $HOSTS; do printf '%s\n' "$h"; done
} > "$BLOCK"
cat "$HOSTS_FILE" "$BLOCK" > "$NEW"

# The suite's own rule, applied to the result: every host line sits under a comment.
_bare="$(awk '/^#/ { why = 1; next } /^[[:space:]]*$/ { why = 0; next } !why { print }' "$NEW")"
[ -z "$_bare" ] || _refuse "the result would hold a host with no comment above it: $_bare"

diff -u "$HOSTS_FILE" "$NEW" | sed "1s#.*#--- $HOSTS_FILE#; 2s#.*#+++ $HOSTS_FILE (proposed)#" || :

if [ "$APPLY" = 0 ]; then
  log_note "dry run: nothing written. The operator applies with --apply"
  log_end
  exit $?
fi

cat "$NEW" > "$HOSTS_FILE"
for h in $HOSTS; do
  _admitted_by "$h" >/dev/null || _refuse "$h is not admitted after the write"
done
log_ok "written to $HOSTS_FILE"
log_note "next: just test browser-test, commit, PR; live only after the merge and deploy.sh --apply"
log_end
