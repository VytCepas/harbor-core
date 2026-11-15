#!/usr/bin/env sh
# check-run.sh (harbor#1437) — the scheduled entry of the read-only checks that run from main: one runner, one table.
#   sh check-run.sh <check-id>              fetch main from the pinned URL, run the row contracts/scheduled-checks.tsv names
#   sh check-run.sh <check-id> --from DIR   run that tree instead of a fresh clone (the suite's door; launchd passes only the id)
#   sh check-run.sh --list                  the ids this copy's tree would run (needs --from DIR, or fetches main)
#   exit: the check's own (0 clean, 1 findings), 1 when main could not be fetched or the id is not in the table, 2 usage
#
# WHICH CODE RUNS. launchd runs THIS installed copy, never the checkout: a session can write the checkout, and a weekly job
# aimed at it would run whatever a session left there, as the operator. What this copy runs is main as GitHub has it, a
# FRESH clone with system and global git config off (the block of standard-fleet-names-run.sh, which this generalises:
# one table instead of one runner a check). The environment is not an input: every HARBOR_* and PORT_ROOT is cleared, the
# URL is repo-slug.txt beside this copy, and the cache is the config dir this copy sits in.
#
# THE TABLE contracts/scheduled-checks.tsv: id <TAB> receipt <TAB> command. `receipt` is `tool` when the command writes its
# own receipt for the findings reconcile (contracts/finding.md), `wrap` when this runner writes it from the exit code: 0 green,
# 1 red naming the command's last line, anything else stood-down (nothing judged is not a clean run). {cfg} in a command is
# the config dir. A check is on a schedule only through a launchd plist that names its id here and a register row.
set -eu
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(the table and the flags are in the header above.)\n'; exit 0 ;;
  '') echo "check-run: usage: check-run.sh <check-id> [--from DIR] | --list [--from DIR]" >&2; exit 2 ;;
esac
. "$(dirname -- "$0")/library-log.sh"
log_init check-run
ID="$1"; shift
FROM=""
while [ $# -gt 0 ]; do
  case "$1" in --from) [ $# -ge 2 ] || { echo "check-run: --from needs a directory" >&2; exit 2; }; FROM="$2"; shift 2 ;; *) echo "check-run: unknown argument $1" >&2; exit 2 ;; esac
done
case "$ID" in --list|[abcdefghijklmnopqrstuvwxyz]*) ;; *) echo "check-run: $ID is not a check id" >&2; exit 2 ;; esac
CFG_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
for _v in $(env | sed -n 's/^\(HARBOR_[A-Za-z0-9_]*\)=.*/\1/p') PORT_ROOT; do unset "$_v"; done
CHECKS_LOG="$CFG_DIR/cache/checks.log"
stamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
refuse() { # <note> <fix>
  printf '[check:%s] %s not run: %s\n' "$ID" "$(stamp)" "$1" >> "$CHECKS_LOG" 2>/dev/null || :
  log_fail "$1"; log_fix "$2"; log_end || :; exit 1
}
T="$(mktemp -d "${TMPDIR:-/tmp}/check-run.XXXXXX")"
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; trap - EXIT; exit 130' INT TERM HUP

if [ -n "$FROM" ]; then
  [ -d "$FROM" ] || refuse "--from $FROM is not a directory" "pass a checkout"
  TREE="$FROM"
else
  URL=""; _slug="$(repo_slug)"; [ -z "$_slug" ] || URL="https://github.com/$_slug.git"
  [ -n "$URL" ] || refuse "this copy names no repository (no repo-slug.txt beside it)" "deploy harbor again: the install carries bin/repo-slug.txt"
  # main as GitHub has it, in a clone nothing else has touched (lint-findings-run.sh's block)
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_PREFIX GIT_NAMESPACE GIT_CEILING_DIRECTORIES \
    GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_TEMPLATE_DIR GIT_EXEC_PATH \
    GIT_SSH GIT_SSH_COMMAND GIT_ASKPASS GIT_PROXY_COMMAND \
    GIT_SSL_NO_VERIFY GIT_SSL_CAINFO GIT_SSL_CAPATH GIT_SSL_CERT GIT_SSL_KEY GIT_CURL_VERBOSE \
    GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP GIT_TRACE_CURL GIT_TRACE2 \
    GIT_TRACE2_EVENT GIT_TRACE2_PERF GIT_REDACT_COOKIES \
    http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY \
    SSL_CERT_FILE SSL_CERT_DIR CURL_CA_BUNDLE GH_TOKEN GITHUB_TOKEN GH_HOST GH_CONFIG_DIR 2>/dev/null || :
  GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_COUNT=2; GIT_CONFIG_KEY_0=credential.helper; GIT_CONFIG_VALUE_0='!gh auth git-credential'
  GIT_CONFIG_KEY_1=core.hooksPath; GIT_CONFIG_VALUE_1=/dev/null
  export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
  git clone --quiet --single-branch --branch main "$URL" "$T/main" 2>"$T/fetch.err" \
    || refuse "could not fetch main from $URL: $(head -1 "$T/fetch.err")" "git clone $URL"
  [ "$(git -C "$T/main" rev-parse refs/remotes/origin/main)" = "$(git -C "$T/main" rev-parse HEAD)" ] \
    || refuse "the clone of $URL is not at its own origin/main" "git clone $URL"
  log_note "main at $(git -C "$T/main" rev-parse --short HEAD)"
  TREE="$T/main"
fi
TABLE="$TREE/contracts/scheduled-checks.tsv"
[ -f "$TABLE" ] || refuse "$TABLE does not exist" "the tree has no contracts/scheduled-checks.tsv"
if [ "$ID" = --list ]; then awk -F'	' '!/^#/ && NF >= 3 { print $1 }' "$TABLE"; exit 0; fi
ROW="$(awk -F'	' -v id="$ID" '!/^#/ && $1 == id { print; exit }' "$TABLE")"
[ -n "$ROW" ] || refuse "$ID is not a row of contracts/scheduled-checks.tsv" "add the row there (docs/reference/checks.md, \"Adding a check\")"
MODE="$(printf '%s' "$ROW" | cut -f2)"; CMD="$(printf '%s' "$ROW" | cut -f3-)"
case "$MODE" in tool|wrap) ;; *) refuse "$ID's receipt column is '$MODE', not tool or wrap" "fix its row" ;; esac
# {cfg} is the config dir; the command's first word is a path inside the tree
CMD="$(printf '%s' "$CMD" | sed "s|{cfg}|$CFG_DIR|g")"
_prog="${CMD%% *}"; _rest=""; [ "$CMD" = "$_prog" ] || _rest="${CMD#* }"
[ -f "$TREE/$_prog" ] || refuse "$ID's command $_prog is not in the tree" "fix its row"
_rc=0
# shellcheck disable=SC2086 # the row's arguments are words by design
( cd "$TREE" && CLAUDE_CONFIG_DIR="$CFG_DIR" sh "$_prog" $_rest ) > "$T/out" 2>&1 || _rc=$?
cat "$T/out"
if [ "$MODE" = wrap ]; then
  RD="$(receipt_dir "$CFG_DIR")"
  case "$_rc" in
    0) log_receipt "$RD" "$ID" green || log_warn "no receipt written to $RD" ;;
    1) _last="$(grep -v '^[[:space:]]*$' "$T/out" | tail -1 | tr -c 'A-Za-z0-9._:/@ -' ' ' | cut -c1-200)"
       log_receipt "$RD" "$ID" red "${_last:-exit 1}" || log_warn "no receipt written to $RD" ;;
    *) log_receipt "$RD" "$ID" stood-down || log_warn "no receipt written to $RD" ;;
  esac
fi
printf '[check:%s] %s exit %s\n' "$ID" "$(stamp)" "$_rc" >> "$CHECKS_LOG" 2>/dev/null || :
log_end || :
exit "$_rc"
