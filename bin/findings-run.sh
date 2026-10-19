#!/usr/bin/env sh
# findings-run.sh (harbor#856) — the scheduled entry of CONTRACTS/finding.md: reconcile, then heal.
#   sh findings-run.sh          fetch main from the pinned URL, run its findings.sh, stamp a receipt
#   sh findings-run.sh --help   this text
#   sh findings-run.sh --overrides   honour HARBOR_FINDINGS_URL, HARBOR_FINDINGS_REPO and
#                               CLAUDE_CONFIG_DIR from the environment — for its suite, never for launchd
#   exit 0 = reconcile and heal ran clean · exit 1 = a step failed or was refused
#   receipt: $CLAUDE_CONFIG_DIR/cache/findings-state.json — `ran_at` is liveness
#
# WHICH CODE RUNS. launchd runs THIS installed copy, never the checkout: a session can write the
# checkout, and a job aimed at it would let any session schedule code that runs with the operator's
# `gh` login (CONTRACTS/cli.md, judge-run.sh's row). What this copy runs is main as GitHub has it: a
# FRESH clone of a URL written here, into a new temp dir, with system and global git config switched
# off. Borrowing the session-writable ~/port/harbor clone would honour its config and hooks, so a
# session could redirect the fetch with `url.<x>.insteadOf` or plant a hook (review #895), and
# ~/.gitconfig is session-writable too. What git needs is passed in explicitly: gh as the credential
# helper, no hooks, and the operator's name and email read as plain values.
#
# HEAL RUNS ONLY AFTER A CLEAN RECONCILE. A repair is written into its finding's issue, so with a
# store that could not be reconciled the repair would land on a stale record or none.
#
# THE RECEIPT IS THE EVIDENCE, NOT THE LOG, for cu-doctor-run.sh's reason: a clean run and a run that
# never happened both leave an empty log. checks.log gets one line only when a run changed something
# (new, changed, fixed, re-filed, repaired, failed), so it carries the delta and never the census.
set -eu

OVERRIDES=0
case "${1:-}" in
  --overrides) OVERRIDES=1 ;;
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
log_init findings-run

# THE ENVIRONMENT IS NOT AN INPUT (review #895). A session can set variables that every later launchd
# job inherits, so the scheduled run takes nothing from it: the URL is the one pinned beside this copy
# (log-lib's repo_slug: bin/repo-slug.txt, which only a deploy writes; harbor#1149), never the registered
# checkout's origin or the private layer, which a session can write. The config dir is the one this
# installed copy sits in (<config>/bin/findings-run.sh), and every inherited HARBOR_* is cleared before
# main's findings.sh runs. Only --overrides, which launchd's arguments do not carry, reads them.
URL=""; STORE=""; _slug="$(repo_slug)"; [ -z "$_slug" ] || URL="https://github.com/$_slug.git"
CFG_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
if [ "$OVERRIDES" = 1 ]; then
  URL="${HARBOR_FINDINGS_URL:-$URL}"; STORE="${HARBOR_FINDINGS_REPO:-}"
  CFG_DIR="${CLAUDE_CONFIG_DIR:?--overrides needs CLAUDE_CONFIG_DIR}"
fi
for _v in $(env | sed -n 's/^\(HARBOR_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
[ -n "$STORE" ] || STORE="$(printf '%s' "$URL" | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')"
STATE="$CFG_DIR/cache/findings-state.json"
CHECKS_LOG="$CFG_DIR/cache/checks.log"
T="$(mktemp -d "${TMPDIR:-/tmp}/findings-run.XXXXXX")"
WT="$T/main"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT TERM HUP

stamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
# The cache is session-writable, so nothing here writes through a name a session could have planted
# (review #895): the receipt goes through an mktemp file renamed over it, and fails the run when it
# cannot be installed; checks.log is appended to only when it is a plain file with one link, since a
# symlink or a hard link would carry the append into whatever it points at.
receipt() { # <status> <sha> <reconcile rc> <heal rc> <note> — returns 1 when no receipt was installed
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 1
  [ ! -d "$STATE" ] || return 1
  _tmp="$(mktemp "$(dirname "$STATE")/.findings-state.XXXXXX")" || return 1
  jq -n --arg t "$(stamp)" --arg s "$1" --arg h "$2" --arg r "$3" --arg e "$4" --arg n "$5" \
    '{ran_at: $t, status: $s, sha: $h, reconcile_rc: $r, heal_rc: $e, note: $n}' > "$_tmp" \
    && mv -f "$_tmp" "$STATE" && [ -f "$STATE" ] && [ ! -L "$STATE" ] || { rm -f "$_tmp"; return 1; }
}
log_line() {
  if [ -e "$CHECKS_LOG" ] || [ -L "$CHECKS_LOG" ]; then
    { [ -f "$CHECKS_LOG" ] && [ ! -L "$CHECKS_LOG" ] && [ "$(ls -ln "$CHECKS_LOG" | awk '{ print $2 }')" = 1 ]; } \
      || { log_warn "checks.log is not a plain, singly-linked file — not appended to"; return 0; }
  fi
  printf '%s\n' "$1" >> "$CHECKS_LOG" 2>/dev/null || :
}
refuse() { # <note> <fix>
  receipt refused - - - "$1" || log_warn "and no receipt could be installed at $STATE"
  log_fail "$1 — nothing reconciled (receipt: $STATE)"; log_fix "$2"
  log_end || :; exit 1
}

[ -n "$URL" ] || refuse "this copy names no repository (no origin in its checkout, no repo-slug.txt beside it)" "deploy harbor again: the install carries bin/repo-slug.txt"
case "$STORE" in */*) ;; *) refuse "no finding store derivable from $URL" "HARBOR_FINDINGS_REPO=<owner/name> sh $0" ;; esac

# 1 · main as GitHub has it, in a clone nothing else has touched
# The repository variables are test-contract.md's list (harbor#824); the rest steer config and transport.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_PREFIX GIT_NAMESPACE GIT_CEILING_DIRECTORIES \
  GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_TEMPLATE_DIR GIT_EXEC_PATH \
  GIT_SSH GIT_SSH_COMMAND GIT_ASKPASS GIT_PROXY_COMMAND \
  GIT_SSL_NO_VERIFY GIT_SSL_CAINFO GIT_SSL_CAPATH GIT_SSL_CERT GIT_SSL_KEY GIT_CURL_VERBOSE \
  GIT_TRACE GIT_TRACE_PACKET GIT_TRACE_PERFORMANCE GIT_TRACE_SETUP GIT_TRACE_CURL GIT_TRACE2 \
  GIT_TRACE2_EVENT GIT_TRACE2_PERF GIT_REDACT_COOKIES \
  http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY \
  SSL_CERT_FILE SSL_CERT_DIR CURL_CA_BUNDLE GH_TOKEN GITHUB_TOKEN GH_HOST GH_CONFIG_DIR 2>/dev/null || :
# the operator's name and email, read only now that nothing above can point git at another config
_name="$(git config --global user.name 2>/dev/null || :)"; _mail="$(git config --global user.email 2>/dev/null || :)"
GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_COUNT=2; GIT_CONFIG_KEY_0=credential.helper; GIT_CONFIG_VALUE_0='!gh auth git-credential'
GIT_CONFIG_KEY_1=core.hooksPath; GIT_CONFIG_VALUE_1=/dev/null
GIT_AUTHOR_NAME="${_name:-harbor findings}"; GIT_AUTHOR_EMAIL="${_mail:-findings@localhost}"
GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"; GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
  GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git clone --quiet --single-branch --branch main "$URL" "$WT" 2>"$T/fetch.err" \
  || refuse "could not fetch main from $URL: $(head -1 "$T/fetch.err")" "git clone $URL"
SHA="$(git -C "$WT" rev-parse HEAD)"
[ "$(git -C "$WT" rev-parse refs/remotes/origin/main)" = "$SHA" ] \
  || refuse "the clone of $URL is not at its own origin/main" "git clone $URL"
SHA7="$(printf '%.7s' "$SHA")"

# 2 · reconcile, then heal — each run by main's own findings.sh
_rr=0; HARBOR_ROOT="$WT" HARBOR_FINDINGS_REPO="$STORE" sh "$WT/bin/findings.sh" reconcile --apply > "$T/reconcile.out" 2>&1 || _rr=$?
_hr=-
if [ "$_rr" -eq 0 ]; then
  _hr=0; HARBOR_ROOT="$WT" HARBOR_FINDINGS_REPO="$STORE" sh "$WT/bin/findings.sh" heal --apply > "$T/heal.out" 2>&1 || _hr=$?
else
  : > "$T/heal.out"
fi
cat "$T/reconcile.out" "$T/heal.out"

# 3 · the receipt, and the delta to checks.log
if [ "$_rr" -eq 0 ] && [ "$_hr" = 0 ]; then _st=ok; else _st=failed; fi
_why=""; [ "$_rr" -eq 0 ] || _why="reconcile exited $_rr; heal not run"
[ "$_hr" = - ] || [ "$_hr" -eq 0 ] || _why="heal exited $_hr"
if ! receipt "$_st" "$SHA7" "$_rr" "$_hr" "${_why:-clean}"; then
  _st=failed; _why="no receipt could be installed at $STATE${_why:+; $_why}"
fi
if [ "$_st" != ok ] || grep -qE '^  (new |subjects changed|fixed:|re-filed|repaired:|proposed:|FAILED)' "$T/reconcile.out" "$T/heal.out"; then
  _sum="$(head -1 "$T/reconcile.out" | cut -c1-200)"
  log_line "[check:findings] $(stamp) $_st at $SHA7 — ${_why:-$_sum}"
fi
if [ "$_st" = ok ]; then log_ok "reconciled and healed main at $SHA7 (receipt: $STATE)"
else log_fail "$_why at $SHA7 (receipt: $STATE)"; log_fix "sh $0   # the output above names the step"; fi
log_end
