#!/usr/bin/env sh
# memory-route.sh routes every tree under <PORT_ROOT>/.worktrees/<repo>/<slug>, including a tree of a repo
# that has no projects.tsv row (harbor#1149). Everything is a fixture, $HOME included.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/box"; CFG="$T/cfg"; REPOROOT="$T/repo"; REG="$T/priv/context-rules/user/projects.tsv"
PORT="$T/port"; TAB="$(printf '\t')"
mkdir -p "$CFG/projects" "$REPOROOT" "$T/priv/context-rules/user" "$PORT"   # the registry is the private layer's (harbor#1149)
# The harness's key (claude's bundle: every character outside [A-Za-z0-9] a dash), never the tool's own (harbor#966).
key_for() { printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }
route_of() { printf '%s' "$CFG/projects/$(key_for "$1")/memory"; }
is_link() { [ -L "$1" ] && echo link || echo "not a link"; }
mkdir -p "$(route_of "$T")"; printf -- '---\nname: a\n---\nx\n' > "$(route_of "$T")/a.md"
printf '# c\nregd\t~/port/regd\tw\n' > "$REG"
mr() { HOME="$T" PORT_ROOT="$PORT" HARBOR_SCOPE_PRIVATE="$T/priv" HARBOR_SCOPE_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" "$@" 2>&1; }
repo() { mkdir -p "$PORT/$1"; git -C "$PORT/$1" init -q; git -C "$PORT/$1" config user.email t@t; git -C "$PORT/$1" config user.name t
  : > "$PORT/$1/f"; git -C "$PORT/$1" add -A >/dev/null 2>&1; git -C "$PORT/$1" commit -qm base >/dev/null 2>&1; }
repo regd; repo unregd                      # unregd is in repos.tsv, not in projects.tsv
mkdir -p "$PORT/.worktrees/regd" "$PORT/.worktrees/unregd"
git -C "$PORT/regd" worktree add -q -b s1 "$PORT/.worktrees/regd/s1" >/dev/null 2>&1
git -C "$PORT/unregd" worktree add -q -b s2 "$PORT/.worktrees/unregd/s2" >/dev/null 2>&1
mkdir -p "$PORT/.worktrees/unregd/notatree"  # a directory that is not a worktree

t_section "a tree of a registered repo and a tree of an unregistered one"
t_has "before --apply the unregistered repo's tree is named BLIND" "$(mr)" 'BLIND  worktrees/unregd/s2'
mr --apply >/dev/null
t_eq "the registered repo's tree is routed" link "$(is_link "$(route_of "$PORT/.worktrees/regd/s1")")"
t_eq "the unregistered repo's tree is routed" link "$(is_link "$(route_of "$PORT/.worktrees/unregd/s2")")"
t_eq "…to the one store, not a store of its own" "$(route_of "$T")" "$(readlink "$(route_of "$PORT/.worktrees/unregd/s2")")"
t_eq "a plain directory under .worktrees/<repo>/ is not routed" "not a link" "$(is_link "$(route_of "$PORT/.worktrees/unregd/notatree")")"
t_eq "the check is green afterwards" 0 "$(mr >/dev/null; echo $?)"

t_section "a tree found twice is counted once"
_n="$(mr | grep -c 'regd/s1\|worktrees/regd')"
t_eq "the registered repo's tree appears on one line" 1 "$_n"
t_section "harbor#966: a tree under .worktrees is routed under the key the harness reads"
# Measured 2026-11-03: 890 route keys kept a `.`, and none of the 57 keys the harness wrote has one. Hand-typed vector from the bundle.
t_eq "the key of a dotted, underscored path is the harness's" "-a--worktrees-b-c-d" "$(sh "$T_ROOT/bin/memory-route.sh" --key /a/.worktrees/b_c/d 2>&1)"
t_eq "…and the .worktrees tree's route sits under that key" link "$(is_link "$CFG/projects/-$(printf '%s' "${PORT#/}/.worktrees/regd/s1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')/memory")"
t_eq "…not under the key that keeps the dot" "not a link" "$(is_link "$CFG/projects/$(printf '%s' "$PORT/.worktrees/regd/s1" | sed 's|/|-|g')/memory")"

t_done
