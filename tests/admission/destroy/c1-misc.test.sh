#!/usr/bin/env sh
# admission-destroy.sh (harbor#1313, release decision 23, lane L7): git's abbreviations of the hard-reset flag
# keep the ask, and they and the merge flag's still take the harbor#1290 snapshot. Rows generated from the
# review corpora by line number.
set -u
. "$(dirname "$0")/../../lib/core.sh"
. "$(dirname "$0")/../../lib/table.sh"
t_init

G="$T_ROOT/bin/admission-destroy.sh"
TB="$T_ROOT/tests/admission/destroy/c1-misc.jsonl"
t_table "$G" "$TB"

# The snapshot, for each abbreviated reset row: the command is read from the table, never restated here.
GI="-c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main"
t_section "an abbreviated reset still snapshots the worktree first (harbor#1290)"
for _id in C1-L7-gf-431 C1-L7-var-17 C1-L7-ok-25; do
  R="$T_TMP/r-$_id"; mkdir -p "$R" && git $GI -C "$R" init -q
  printf 'one\n' > "$R/a.txt"; git $GI -C "$R" add -A && git $GI -C "$R" commit -qm init
  printf 'two\n' > "$R/a.txt"
  jq -c --arg d "$R" --arg id "$_id" 'select(.id == $id) | {tool_name:"Bash",tool_input:{command:.cmd},cwd:$d}' "$TB" > "$T_TMP/payload"
  sh "$G" < "$T_TMP/payload" > /dev/null 2> "$T_TMP/err"
  t_eq "$_id: one snapshot" 1 "$(git -C "$R" for-each-ref refs/snapshots/ | wc -l | tr -d ' ')"
  _s="$(git -C "$R" for-each-ref --count=1 --format='%(refname)' refs/snapshots/)"
  t_eq "$_id: it holds the edit" two "$(git -C "$R" show "$_s:a.txt" 2>&1)"
done
t_done
