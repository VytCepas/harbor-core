#!/bin/sh
# A batch runner in the shape of the eval corpus's: two background sessions per rep, collected and waited through
# reap_wait. Synthetic, so tests/skills/eval-runners-test.sh has a runner to signal where the corpus is not shipped.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/../reap.sh"  # a signal to this runner kills every session it started (harbor#768)
for rep in 1 2 3; do
  _wp=""; for arm in A B; do
    ( claude -p "task" --output-format json >/dev/null 2>&1 ) || true &
    _wp="$_wp $!"
  done
  reap_wait $_wp || :
  printf 'rep %s done\n' "$rep"
done
