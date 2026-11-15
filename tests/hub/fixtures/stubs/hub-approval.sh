#!/usr/bin/env sh
# Stub of hub-approval.sh (harbor#1278): logs every call; stub-status and stub-file beside it hold the exit codes (default 1 and 0).
_d="${0%/*}"
printf '%s\n' "$*" >> "$_d/stub-approval.log"
case "${1:-}" in
  status) [ -f "$_d/stub-status" ] && exit "$(cat "$_d/stub-status")"; exit 1 ;;
  file) [ -f "$_d/stub-file" ] && exit "$(cat "$_d/stub-file")"; exit 0 ;;
esac
exit 0
