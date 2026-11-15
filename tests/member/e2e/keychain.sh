#!/bin/sh
# keychain.sh (harbor#1278) — installed as `security` for the copy of bin/secret in the e2e root: the OS keychain is the one thing below
# harbor that a suite must not touch (tests/lib/core.sh). The two verbs bin/secret uses, over files named by service in E2E_KEYCHAIN's place.
KC="${0%/*}/keychain"; mkdir -p "$KC"
verb="$1"; shift
s=''; w=''; want=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) s="$2"; shift ;;
    -a|-l) shift ;;
    -w) if [ "$verb" = add-generic-password ]; then w="$2"; shift; else want=1; fi ;;
  esac
  shift
done
case "$verb" in
  add-generic-password) printf '%s' "$w" > "$KC/$s" ;;
  find-generic-password) [ -f "$KC/$s" ] && [ "$want" = 1 ] && cat "$KC/$s" ;;
  *) exit 1 ;;
esac
