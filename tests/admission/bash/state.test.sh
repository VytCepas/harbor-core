#!/usr/bin/env sh
# guard-bash.sh (harbor#779): the .helm-* state files of contracts/control-plane-state.md, one row per file and verb.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init
. "$T_ROOT/tests/admission/bash/fixture.sh"
cd "$T_ROOT"  # rows with no CLAUDE_PROJECT_DIR run inside this repo, as tests/floor/'s parts do

t_table "$CLAUDE_CONFIG_DIR/bin/guard-bash.sh" "$T_ROOT/tests/admission/bash/state.jsonl"

# The rows are only as complete as the table they cover. A row of contracts/control-plane-state.md with no
# guard rows here or in selfedit.jsonl would read as tested, so each class is held to its rows.
t_section "every table row has its guard rows"
_hs_rows="$(awk '/^## The table/ { s = 1; next } s && /^## / { s = 0 }
  s && /^\| `\.helm-/ { n = split($0, c, "|"); for (i = 2; i <= 4; i++) { gsub(/^[ \t]+|[ \t]+$|`/, "", c[i]) }
                         print c[2] "\t" c[3] "\t" c[4] }' "$T_ROOT/contracts/control-plane-state.md")"
t_eq "the table has integrity rows" yes "$(printf '%s\n' "$_hs_rows" | awk -F'\t' '$3 == "integrity"' | grep -q . && echo yes || echo no)"
_hs_has() { # <rows.jsonl> <want> <path> <jq-filter on ., with $p> -> yes|no
  # $1 may name several tables, space-separated: the gate's .helm-approvals and .helm-ship rows live in bash.gate.jsonl
  jq -e -s --arg w "$2" --arg p "$3" "[.[] | select(.want == \$w) | select($4)] | length > 0" $1 >/dev/null 2>&1 \
    && echo yes || echo no
}
while IFS='	' read -r _n _w _c; do
  case "$_w" in "<cfg>/bin/"*|'') continue ;; "<cfg>/"*) ;; *) continue ;; esac
  case "$_c" in integrity) _want=block ;; cache) _want=allow ;; *) continue ;; esac
  _p="{cfg}/$_n"
  t_eq "$_n ($_c): a guard-bash $_want row" yes \
    "$(_hs_has "$T_ROOT/tests/admission/bash/state.jsonl $T_ROOT/tests/admission/bash/gate.jsonl" "$_want" "$_p" \
       '(.cmd // "") | (endswith($p) or contains($p + " ") or contains($p + "/") or contains($p + "'"'"'"))')"
  for _tool in Write Edit; do
    [ "$_n" = .helm-sweep.lock ] && [ "$_tool" = Edit ] && continue  # a lock directory has no file to edit
    t_eq "$_n ($_c): a guard-selfedit $_tool $_want row" yes \
      "$(_hs_has "$T_ROOT/tests/guards/selfedit.jsonl" "$_want" "$_p" \
         ".tool == \"$_tool\" and ((.path // \"\") | (. == \$p or startswith(\$p + \"/\")))")"
  done
done <<ROWS
$_hs_rows
ROWS
t_done
