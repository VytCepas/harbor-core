#!/usr/bin/env sh
# segment-table.sh <in-dir> <out-dir> — for each <in-dir>/N.cmd, write the segment table harbor's tokenizer
# (bin/admission-normalize.awk, the SEG* rows) builds to <out-dir>/N.segs. Reads, never executes.
# Not the guard's full path: floor_seg_load also neutralizes quotes inside heredoc bodies first, and this script
# does not source the guard library (lint scope.stand-down-declared reads such a source as a stand-down site).
# A heredoc body holding an unbalanced quote can therefore tokenize differently here than in the guard.
# Past 32768 bytes the guard builds no table (FLOOR_MAX_NORM), so neither does this.
# Used by parser_compare.py.
set -u
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
for f in "$1"/*.cmd; do
  [ -e "$f" ] || continue
  n="${f##*/}"; n="${n%.cmd}"
  if [ "$(wc -c < "$f")" -gt 32768 ]; then : > "$2/$n.segs"; continue; fi
  awk -f "$ROOT/bin/admission-normalize.awk" < "$f" 2>/dev/null | grep '^SEG' > "$2/$n.segs" || :
done
