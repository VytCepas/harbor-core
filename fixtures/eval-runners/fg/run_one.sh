#!/bin/sh
# run_one.sh <run-dir> — a foreground runner in the shape of the eval corpus's: one session as a background child of
# this shell, waited through reap_wait. Synthetic (see batch/run.sh).
set -u
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/../reap.sh"  # a TERM or HUP kills the session this runner started (harbor#806)
D="$1"; ID=$(basename "$D")
cd "$D/work" || exit 1
claude -p "task" --output-format json > "$D/out.tmp" 2>/dev/null &
RC=0; reap_wait $! || RC=$?
rm -f "$D/out.tmp"
echo "done $ID rc=$RC"
