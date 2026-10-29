#!/usr/bin/env sh
# standard-fleet-names-run.sh (harbor#967) — the scheduled entry of docs/reference/checks.md `standard.fleet-names`: the weekly naming check.
#   sh standard-fleet-names-run.sh          fetch main from the pinned URL, run its standard-fleet-names.sh
#   sh standard-fleet-names-run.sh --help   this text
#   exit: standard-fleet-names.sh's own (0 nothing new, 1 new findings, 3 not run); 1 when main could not be fetched
#
# WHICH CODE RUNS. launchd runs THIS installed copy, never the checkout: a session can write the checkout, and a
# weekly job aimed at it would run whatever a session left there, unfenced, as the operator. What this copy runs is
# main as GitHub has it, a FRESH clone into a new temp dir with system and global git config off. The clone block is
# lint-findings-run.sh's (harbor#856, review #895); this is its third user (after eval-redteam-corpus-run.sh), so
# its extraction is a recorded follow-up on harbor#1313, not done here. The repos it reads are the local
# checkouts, read only. The environment is not an input: every HARBOR_* and PORT_ROOT is
# cleared, the URL is repo-slug.txt beside this copy, and the cache is the config dir this copy sits in.
set -eu
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
. "$(dirname -- "$0")/library-log.sh"
log_init standard-fleet-names-run
URL=""; _slug="$(repo_slug)"; [ -z "$_slug" ] || URL="https://github.com/$_slug.git"
CFG_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
for _v in $(env | sed -n 's/^\(HARBOR_[A-Za-z0-9_]*\)=.*/\1/p') PORT_ROOT; do unset "$_v"; done
CHECKS_LOG="$CFG_DIR/cache/checks.log"
stamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
refuse() { # <note> <fix>
  printf '[check:standard.fleet-names] %s not run: %s\n' "$(stamp)" "$1" >> "$CHECKS_LOG" 2>/dev/null || :
  log_fail "$1"; log_fix "$2"; log_end || :; exit 1
}
[ -n "$URL" ] || refuse "this copy names no repository (no repo-slug.txt beside it)" "deploy harbor again: the install carries bin/repo-slug.txt"
T="$(mktemp -d "${TMPDIR:-/tmp}/standard-fleet-names-run.XXXXXX")"
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; trap - EXIT; exit 130' INT TERM HUP

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
_rc=0; sh "$T/main/bin/standard-fleet-names.sh" --config-dir "$CFG_DIR" || _rc=$?
log_end || :
exit "$_rc"
