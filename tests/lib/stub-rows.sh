# tests/lib/stub-rows.sh — _t_run_rows for a guard that answers every row alike (check-test's stubs).
# Source after table.sh. row.sh runs once per fixture kind and its verdict is shared by those rows.
_t_run_rows() { # <guard-path> <rows.jsonl> — fills $_tw/in and $_tw/out
  _tw="$T_TMP/rows.$(basename "$2" .jsonl).$$"; rm -rf "$_tw"; mkdir -p "$_tw/in" "$_tw/out"
  for _fx in nonorm copy; do mkdir -p "$T_TMP/fx-$_fx"; cp "$1" "$T_TMP/fx-$_fx/"; done
  jq -c . "$2" | awk -v d="$_tw/in" -v kf="$_tw/kinds" -v rf="$_tw/kinds.rows" '
    { f = sprintf("%s/%04d", d, NR); print > f; close(f)
      k = match($0, /"fixture":"[a-z]+"/) ? substr($0, RSTART + 11, RLENGTH - 12) : "-"
      kind[NR] = k; if (!(k in first)) { first[k] = f; print k, f > kf } }
    END { for (i = 1; i <= NR; i++) print kind[i] > rf }'
  while read -r _k _f; do
    sh "$T_ROOT/tests/lib/row.sh" "$1" "$_f" "$_tw/ref.$_k" "$T_TMP"
  done < "$_tw/kinds"
  awk -v d="$_tw" 'BEGIN { while ((getline k < (d "/kinds.rows")) > 0) { n++
      r = d "/ref." k; getline v < r; close(r); out = sprintf("%s/out/%04d", d, n); print v > out; close(out) } }'
}
