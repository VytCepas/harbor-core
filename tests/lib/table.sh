# tests/lib/table.sh — run a guard's JSONL case tables (harbor#667). Source after core.sh.
#   t_table  <guard-path> <rows.jsonl>   asserts each row's verdict (`want`)
#   t_msgs   <guard-path> <rows.jsonl>   asserts each row's reason text (`has` / `hasnt`)
#   t_shared <guard-path> <name>         the shared shapes + benign corpus for one guard
# Rows run on $T_JOBS workers (default 3); assertions then run in row order. T_SMOKE=1 runs the
# first row per rule and verdict only, for pre-commit; its summary says it is not a full run.
T_JOBS="${T_JOBS:-3}"
T_TODO=0

_t_run_rows() { # <guard-path> <rows.jsonl> — fills $_tw/in and $_tw/out
  _tw="$T_TMP/rows.$(basename "$2" .jsonl).$$"; rm -rf "$_tw"; mkdir -p "$_tw/in" "$_tw/out"
  _gd="$(dirname "$1")"
  for _fx in nonorm copy; do
    mkdir -p "$T_TMP/fx-$_fx"; cp "$1" "$_gd/guard-lib.sh" "$T_TMP/fx-$_fx/" 2>/dev/null
  done
  cp "$_gd/floor-normalize.awk" "$T_TMP/fx-copy/" 2>/dev/null
  jq -c -s 'if env.T_SMOKE == "1" then reduce .[] as $r ({seen: {}, out: []};  # smoke: first row per rule and verdict
      ([$r.rule, $r.want] | tojson) as $k | if $r.rule != null and .seen[$k] then . else .seen[$k] = true | .out += [$r] end) | .out
    else . end | .[]' "$2" | awk -v d="$_tw/in" '{ f = sprintf("%s/%04d", d, NR); print > f; close(f) }'
  ls "$_tw/in" | xargs -P "$T_JOBS" -I{} sh "$T_ROOT/tests/lib/row.sh" "$1" "$_tw/in/{}" "$_tw/out/{}" "$T_TMP"
}

t_table() { # <guard-path> <rows.jsonl> [section title]
  t_section "${3:-$(basename "$2")}"
  _t_run_rows "$1" "$2"
  jq -r '@sh "_tf=\(input_filename) _id=\(.id) _want=\(.want) _todo=\(.todo // "")"' "$_tw"/in/* > "$_tw/rows.sh"  # one jq, not one per row
  while IFS= read -r _tl; do
    eval "$_tl"; _tg=""; _to="${_tf%/in/*}/out/${_tf##*/}"
    [ ! -f "$_to" ] || IFS= read -r _tg < "$_to"
    t_eq "$_id" "$_want" "$_tg"
    [ -z "$_todo" ] || { T_TODO=$((T_TODO + 1)); printf '  todo: %s — today %s, should be %s\n' "$_id" "$_want" "$_todo"; }
  done < "$_tw/rows.sh"
}

t_msgs() { # <guard-path> <rows.jsonl> [section title]
  t_section "${3:-$(basename "$2")}"
  _t_run_rows "$1" "$2"
  for _ti in "$_tw"/in/*; do
    _tn="$(basename "$_ti")"
    eval "$(jq -r '@sh "_id=\(.id) _has=\(.has // "") _hasnt=\(.hasnt // "")"' "$_ti")"
    _txt="$(sed 1d "$_tw/out/$_tn" 2>/dev/null)"
    [ -z "$_has" ] || t_has "$_id" "$_txt" "$_has"
    [ -z "$_hasnt" ] || t_hasnt "$_id" "$_txt" "$_hasnt"
  done
}

t_shared() { # <guard-path> <name> — rows built from guards.jsonl, shapes.jsonl, benign.jsonl, exemptions.jsonl
  _sd="$T_ROOT/tests/guards"
  jq -c -n --arg g "$2" -f "$T_ROOT/tests/lib/shared.jq" \
    --slurpfile reg "$_sd/guards.jsonl" --slurpfile shapes "$_sd/shapes.jsonl" \
    --slurpfile benign "$_sd/benign.jsonl" --slurpfile ex "$_sd/exemptions.jsonl" \
    > "$T_TMP/shared.jsonl" || { t_fail "shared rows for $2 could not be built"; return; }
  t_table "$1" "$T_TMP/shared.jsonl" "shared shapes + benign corpus ($2)"
}
