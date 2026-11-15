#!/usr/bin/env sh
# skills/doc-atlas/build/build.py inside_views(): a diagram declaring `inside` links from one part of
# another diagram, its tab follows its parent's, and every bad declaration stops the build.
. "$(dirname "$0")/../../lib/core.sh"; t_init
run() { python3 - "$T_ROOT/skills/doc-atlas/build" "$1" <<'PY' 2>&1
import sys, json
sys.path.insert(0, sys.argv[1])
from build import inside_views
case = sys.argv[2]
ins = {"ok": {"kid": ("top", "a")}, "nodiag": {"kid": ("nope", "a")}, "nopart": {"kid": ("top", "zz")},
       "self": {"kid": ("kid", "a")}, "twice": {"kid": ("top", "a"), "other": ("top", "a")},
       "cycle": {"kid": ("other", "a"), "other": ("kid", "a")}}[case]
names = ["kid", "top", "other", "last"]   # child listed BEFORE its parent
cfg = {"diagrams": {n: ({"inside": {"diagram": ins[n][0], "node": ins[n][1]}} if n in ins else {}) for n in names}}
data = {"order": names[:], "diagrams": {n: {"tab": n.upper(), "nodes": {"a": {"label": n + "-a"}}} for n in names}}
try:
    inside_views(cfg, data)
except SystemExit as e:
    print("REFUSED", e); sys.exit(0)
d = data["diagrams"]
print("order=" + ",".join(data["order"]), "link=" + json.dumps(d["top"]["nodes"]["a"].get("inside")),
      "back=" + json.dumps(d["kid"].get("parent")))
PY
}
t_section "a valid inside view"
OK="$(run ok)"
t_has "the child tab follows its parent" "$OK" "order=top,kid,other,last"
t_has "the part links down to the child" "$OK" 'link=["kid", "KID"]'
t_has "the child links back up to the part" "$OK" 'back=["top", "a", "top-a", "TOP"]'
t_section "every bad declaration stops the build"
t_has "unknown diagram" "$(run nodiag)" "REFUSED kid.inside: 'nope' is not another diagram"
t_has "unknown part" "$(run nopart)" "REFUSED kid.inside: top has no part 'zz'"
t_has "itself" "$(run self)" "REFUSED kid.inside: 'kid' is not another diagram"
t_has "two views on one part" "$(run twice)" "one inside view per part"
t_has "a cycle" "$(run cycle)" "REFUSED inside views form a cycle"
t_done
