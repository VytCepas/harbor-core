#!/usr/bin/env sh
# skills/doc-atlas/build/build.py unzoned(): an architecture drawing of 8+ parts with no archify
# `boundaries` is named; zoned, waived, smaller or non-architecture drawings are not.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_TMP/specs"; mkdir -p "$S"
spec() { # <file> <parts> <type> <with-boundaries>
  python3 - "$S/$1" "$2" "$3" "$4" <<'PY'
import json, sys
f, n, typ, zoned = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4] == "y"
d = {"diagram_type": typ, "components": [{"id": f"p{i}"} for i in range(n)]}
if zoned:
    d["boundaries"] = [{"kind": "region", "label": "All", "wraps": [f"p{i}" for i in range(n)]}]
json.dump(d, open(f, "w"))
PY
}
spec flat8.json 8 architecture n; spec zoned8.json 8 architecture y; spec small7.json 7 architecture n
spec waived8.json 8 architecture n; spec flow8.json 8 dataflow n
run() { python3 - "$T_ROOT/skills/doc-atlas/build" "$S" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from build import unzoned
D = lambda f, **k: {"spec": f, "parts": "components", "edges": "connections", **k}
cfg = {"specs": sys.argv[2], "diagrams": {"flat8": D("flat8.json"), "zoned8": D("zoned8.json"),
       "small7": D("small7.json"), "waived8": D("waived8.json", zones_waived="a matrix"),
       "flow8": D("flow8.json")}}
print("|".join(unzoned(cfg)))
PY
}
OUT="$(run 2>&1)"
t_section "which drawings are named"
t_eq "only the flat 8-part architecture drawing is named" "flat8: 8 parts, no zones" "$OUT"
t_hasnt "a zoned drawing is not named" "$OUT" "zoned8"
t_hasnt "7 parts is under the threshold" "$OUT" "small7"
t_hasnt "zones_waived silences it" "$OUT" "waived8"
t_hasnt "a non-architecture drawing is not named" "$OUT" "flow8"
t_done
