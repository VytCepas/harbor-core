# fixture-repo.sh (harbor#996 D) — sourced by the catalog suites: builds the fixture repo as a git checkout.
# fixtures/standard-catalog/repo is the tree; fixtures/standard-catalog/expected holds the answers it must give.
# After t_init: CAT_FX (the fixture folder), CAT_TOOL (the tool), cat_repo <dir> (a fresh checkout with the tracked map).
CAT_FX="$T_ROOT/fixtures/standard-catalog"
CAT_TOOL="$T_ROOT/bin/standard-catalog.sh"
cat_repo() { # <dir> — the fixture tree, its expected map in place, everything staged
  rm -rf "$1"; cp -R "$CAT_FX/repo" "$1"
  cp "$CAT_FX/expected/context-map.txt" "$1/docs/context-map.md"
  git -C "$1" init -q; git -C "$1" add -A
}
# the level columns of catalog.tsv that are "-" with no finding naming the path and the column (stdout: one line each)
cat_blank_without_finding() { # <catalog.tsv> <findings.tsv>
  awk -F'\t' -v OFS='\t' '
    FNR == NR { cols[$1] = "," $2 ","; next }
    NF != 11 { print $2, "has " NF " columns, not 11"; next }
    { split("system domain subsystem family kind layer lifecycle owner", nm, " ")
      for (i = 1; i <= 8; i++) {
        v = $(i + 2)
        if (v == "") print $2, nm[i], "empty"
        else if (v == "-" && index(cols[$2], "," nm[i] ",") == 0) print $2, nm[i], "- with no finding"
      } }' "$2" "$1"
}
