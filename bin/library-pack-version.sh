#!/usr/bin/env sh
# library-pack-version.sh (harbor#1278, harbor#1149) — the harbor_version grammar of contracts/pack.md, sourced by pack.sh
# (a pack's constraint against core) and hub.sh (an extension's constraint against a pin). Never run.

[ -n "${_LOG_LIB:-}" ] || . "$(dirname -- "$0")/library-log.sh"

# pack_ver_ok <constraint> <core>: exit 0 satisfied, 1 not, 2 malformed. Constraint: [op]N[.M], comma = AND. Core: N or N.M.
pack_ver_ok() {
  awk -v c="$1" -v core="$2" '
    function num(v,   a) { split(v, a, "."); return a[1] * 1000000 + (a[2] == "" ? 0 : a[2]) }
    BEGIN { n = split(c, p, /[ ]*,[ ]*/); k = num(core)
      for (i = 1; i <= n; i++) { s = p[i]; gsub(/^[ ]+|[ ]+$/, "", s)
        if (s !~ /^(>=|<=|>|<|=)?[0-9]+(\.[0-9]+)?$/) exit 2
        op = s; sub(/[0-9.]+$/, "", op); v = num(substr(s, length(op) + 1))
        if (op == ">=") ok = (k >= v); else if (op == "<=") ok = (k <= v); else if (op == ">") ok = (k > v)
        else if (op == "<") ok = (k < v); else ok = (k == v)
        if (!ok) exit 1 }
      exit 0 }'
}
