#!/usr/bin/env sh
# gate-queue.sh (harbor#1018) — the approvals that wait for the operator: the ONLY queue writer (ship contract §5b.9).
#
#   <cfg>/bin/gate-queue.sh add <merge|deploy> <owner/repo> <sha> [<pr>] --reason <text>   queue it; prints the id
#   <cfg>/bin/gate-queue.sh list [--json]          the open rows, each with its exact approve command
#   <cfg>/bin/gate-queue.sh close <id> <answer>    e.g. after the operator refused the prompt
#
# A merge takes its <pr>, a deploy none. The id is <kind>-<owner>_<name>[-<pr>]-<sha12>. Unattended code queues here
# and never runs gate-approve.sh: a pending prompt stops a session until someone answers it. The queue is
# ~/.local/state/harbor/approvals/queue.jsonl; each add is an approval.open, each close an approval.close, and
# gate-approve.sh closes a row it completes. Exit 0 done, 1 nothing to close, 2 usage. Runs only as the installed copy.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -P -- "$HERE" && pwd -P)"
LOG_FD=2   # stdout is the list, or the queued id
. "$HERE/library-log.sh"
. "$HERE/library-gate.sh"
log_init gate-queue
usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }
_hex40() { case "$1" in *[!0-9abcdef]*) return 1 ;; esac; [ "${#1}" -eq 40 ]; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
ACT="${1:-}"; [ $# -eq 0 ] || shift
case "$ACT" in
  list) [ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = --json ]; } || { usage >&2; exit 2; } ;;
  close) [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] || { usage >&2; exit 2; } ;;
  add)
    K="${1:-}"; RP="${2:-}"; SH="${3:-}"; PR='-'; WHY=''
    [ $# -ge 3 ] && shift 3 || { usage >&2; exit 2; }
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) [ $# -ge 2 ] && [ -n "$2" ] || { usage >&2; exit 2; }; WHY="$2"; shift ;;
        *[!0-9]*|'') usage >&2; exit 2 ;;
        *) [ "$PR" = - ] || { usage >&2; exit 2; }; PR="$1" ;;
      esac; shift
    done
    { [ "$K" = merge ] && [ "$PR" != - ]; } || { [ "$K" = deploy ] && [ "$PR" = - ]; } || { usage >&2; exit 2; }
    gate_repo_ok "$RP" && _hex40 "$SH" && [ -n "$WHY" ] || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac
gate_init gate-queue.sh
case "$ACT" in
  list)
    [ -f "$GATE_QDIR/queue.jsonl" ] || { if [ "${1:-}" = --json ]; then echo '[]'; else echo 'no approvals queued'; fi; exit 0; }
    _open="$(jq -c -n '[inputs] | group_by(.id) | map(select(last.closed | not) | first) | sort_by(.ts)' "$GATE_QDIR/queue.jsonl")"
    if [ "${1:-}" = --json ]; then printf '%s\n' "$_open"
    else printf '%s' "$_open" | jq -r 'if length == 0 then "no approvals queued" else .[] | "\(.ts)  \(.id)\n  why: \(.reason)\n  run: \(.command)" end'; fi ;;
  add)
    gate_queue_add "$K" "$RP" "$PR" "$SH" "$WHY"
    printf '%s\n' "$GATE_QID" ;;
  close)
    [ "$(gate_queue_state "$1")" = open ] || { log_fail "no open queue row $1"; log_fix "$GATE_BIN/gate-queue.sh list"; log_end || :; exit 1; }
    gate_queue_close "$1" "$2" ;;
esac
