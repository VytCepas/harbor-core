#!/usr/bin/env sh
# lint-port-paths.sh with worktrees under <PORT_ROOT>/.worktrees/<repo>/<slug> (harbor#1149): the directory is
# does not disturb the scan, and a tree in it whose .git pointer still names a pre-move address is still caught.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/lint-port-paths.sh"
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE XDG_CONFIG_HOME PORT_ROOT PORT_PATHS_EXEMPT
export GIT_CONFIG_NOSYSTEM=1
H="$T/home"; C="$T/cfg"; P="$H/port"; mkdir -p "$H/.claude" "$C" "$P"
hit() { awk -F'\t' -v s="$2" -v c="$3" -v f="$4" '$1 == s && $2 == c && $3 == f { h = 1 } END { print h ? "yes" : "no" }' "$1"; }
none() { awk -F'\t' "NR > 1 && ($2) { h = 1 } END { print h ? \"found\" : \"none\" }" "$1"; }
scan() { HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" PORT_PATHS_EXEMPT=/dev/null sh "$TOOL" > "$T/inv.tsv" 2>/dev/null; }

mkdir -p "$P/az" "$P/.worktrees/az"; git -C "$P/az" init -q
printf 'cd ~/az/x\n' > "$P/az/a.sh"; git -C "$P/az" add -A
git -C "$P/az" -c user.name=f -c user.email=f@example.invalid commit -qm f
git -C "$P/az" worktree add -q -b feat "$P/.worktrees/az/feat" 2>/dev/null
printf 'cd ~/az/y\n' > "$P/.worktrees/az/feat/b.sh"; git -C "$P/.worktrees/az/feat" add -A
t_eq "the fixture is a real worktree under .worktrees" yes "$([ -f "$P/.worktrees/az/feat/.git" ] && echo yes)"

t_section "the owner is scanned with a tree under .worktrees/"
scan
t_eq "the owner repo is scanned" yes "$(hit "$T/inv.tsv" repo:az CODE "$P/az/a.sh")"

t_section "its .git pointer is checked like any other worktree's"
t_eq "a pointer into the live owner is quiet" none "$(none "$T/inv.tsv" "\$1 ~ /git-worktree/")"
printf 'gitdir: %s/az/.git/worktrees/feat\n' "$H" > "$P/.worktrees/az/feat/.git"   # the pre-move address
scan
t_eq "a pointer naming the pre-move address is CODE" yes "$(hit "$T/inv.tsv" git-worktree CODE "$P/.worktrees/az/feat/.git")"
t_done
