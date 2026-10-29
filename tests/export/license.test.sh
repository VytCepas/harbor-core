#!/usr/bin/env sh
# The public export carries its licence and notices (harbor#1149): the Apache-2.0 text verbatim, a NOTICE naming
# every vendored tree, a licence file beside each, and a SECURITY.md that routes reports through GitHub with no email.
. "$(dirname "$0")/../lib/core.sh"; t_init
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'; }
R="$T_ROOT"

t_section "LICENSE is the verbatim Apache License 2.0"
t_eq "sha256 of apache.org/licenses/LICENSE-2.0.txt" "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" "$(sha "$R/LICENSE")"
t_has "README names the licence" "$(cat "$R/README.md")" "Apache License 2.0"

t_section "NOTICE names every vendored tree"
t_has "NOTICE carries the holder line" "$(cat "$R/NOTICE")" "Copyright 2026 Vytautas Cepas"
# a vendored tree is any directory under vendor/ but the dev-layer skills; derived from disk, never a fixed list
missing() { # <notice file> → the vendor/ dirs it does not name
  for d in "$R"/vendor/*/; do n="vendor/$(basename "$d")/"; case "$n" in vendor/skills/|vendor/skills-archive/) continue ;; esac; grep -qF "$n" "$1" || printf '%s ' "$n"; done
}
t_eq "no vendor/ directory is missing from NOTICE" "" "$(missing "$R/NOTICE")"
grep -v 'vendor/archify/' "$R/NOTICE" > "$T_TMP/notice.mut"
t_has "control: a NOTICE without archify goes red" "$(missing "$T_TMP/notice.mut")" "vendor/archify/"

t_section "each vendored licence sits beside its tree"
# vendor/skills is dev-layer: its licences are checked where it exists and absent from the export
set -- vendor/archify/LICENSE
[ -d "$R/vendor/skills" ] && set -- vendor/skills/LICENSE vendor/skills-archive/fabric/LICENSE-fabric "$@"
for f in "$@"; do
  [ -s "$R/$f" ] && t_pass || t_fail "$f is missing or empty"
  t_has "...$f is an MIT text" "$(cat "$R/$f")" "Permission is hereby granted, free of charge"
done

t_section "SECURITY.md routes reports through GitHub"
S="$(cat "$R/SECURITY.md")"
t_has "private vulnerability reporting" "$S" "Report a vulnerability"
t_eq "no email address" "0" "$(printf '%s\n' "$S" | grep -cE '[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.[a-z]{2,}')"
t_done
