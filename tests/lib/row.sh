#!/usr/bin/env sh
# tests/lib/row.sh <guard> <row.json> <out> <fixture-root> — one table row, for t_table's workers.
# Writes the verdict on line 1 and the reason text after it (a block's reason is its stderr); a guard
# still running at $T_ROW_SECS (default 60) is killed with every child it forked, under bash or dash,
# and reads `timeout`, so a loop cannot hang the suite (harbor#768). A pad is words, not one token:
# a single 33 KB token costs guard-egress ~5 s of CPU (quadratic -o scan), >60 s under CI load (harbor#1092).
# {j} expands to nothing: it splits a token-shaped literal in a row so no scanner sees it in the tracked file (harbor#1149).
. "$(dirname "$0")/../admission/helper/lib.sh"
_g="$1"; _o="$3"
_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
_row="$(jq -c --arg home "$HOME" --arg cfg "${CLAUDE_CONFIG_DIR:-}" --arg tmp "$4" --arg root "$_root" '
  walk(if type == "string" then gsub("\\{home\\}"; $home) | gsub("\\{cfg\\}"; $cfg) | gsub("\\{tmp\\}"; $tmp)
       | gsub("\\{root\\}"; $root) | gsub("\\{j\\}"; "") else . end)' "$2")"
_fx="$(printf '%s' "$_row" | jq -r '.fixture // ""')"
[ -z "$_fx" ] || _g="$4/fx-$_fx/$(basename "$_g")"
printf '%s' "$_row" | jq -c '
  (if .pad then " # " + (("xxxxxxx " * (.pad / 8 | ceil))[:.pad]) else "" end) as $pad
  | (if .input then {tool_name: .tool, tool_input: .input}
     elif .tool then {tool_name: .tool, tool_input: {file_path: .path}}
     else {tool_name: "Bash", tool_input: {command: (.cmd + $pad)}} end) as $base
  | (.ctx // {}) + $base' > "$_o.in"
set --
while IFS= read -r _kv; do [ -z "$_kv" ] || set -- "$@" "$_kv"; done <<EOF
$(printf '%s' "$_row" | jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"')
EOF
# harbor#768: dash has no tty here, refuses `set -m` and makes no group, so the timeout falls back to
# the tree: each generation is stopped before its children are listed, then all of it is killed.
_kill_tree() { # <root pid>
  _kt_all=" $1 "; _kt_new="$1"
  while [ -n "$_kt_new" ]; do
    kill -STOP $_kt_new 2>/dev/null
    _kt_new=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v all="$_kt_all" \
      'index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }')
    _kt_all="$_kt_all$_kt_new"
  done
  kill -9 $_kt_all 2>/dev/null
}
set -m 2>/dev/null  # own process group, so a timeout also kills the guard's children
{ env "$@" sh "$_g" < "$_o.in" > "$_o.raw" 2> "$_o.err" & } 2>/dev/null; _gp=$!  # before the fork: bash 3.2 can warn from the child
set +m
( trap 'kill $_s 2>/dev/null; exit' TERM; sleep "${T_ROW_SECS:-60}" & _s=$!; wait $_s
  : > "$_o.late"; kill -9 -"$_gp" 2>/dev/null || _kill_tree "$_gp" ) > /dev/null 2>&1 & _wd=$!
{ wait "$_gp"; } 2>/dev/null; _rc=$?; kill "$_wd" 2>/dev/null
_out="$(cat "$_o.raw")"
{ if [ -e "$_o.late" ]; then echo timeout; else t_fold "$_rc" "$_out"; fi
  if [ "$_rc" = 2 ]; then cat "$_o.err"
  else printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; fi
} > "$_o"
rm -f "$_o.in" "$_o.raw" "$_o.err"
