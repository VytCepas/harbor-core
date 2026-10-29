#!/usr/bin/env sh
# hooks/post-checkout (harbor#1116): a linked worktree is born routed to the memory store, and nothing else is touched.
# Everything is a fixture, $HOME included; the hook under test is the repo's real one, via core.hooksPath.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/box"; CFG="$T/cfg"; REPOROOT="$T/repo"; TAB="$(printf '\t')"
PRIV="$T/priv"   # the registry is the private layer's (harbor#1149)
mkdir -p "$CFG/projects" "$REPOROOT" "$PRIV/inject.d/box" "$T/main" "$T/other"
key_for() { printf '%s' "$1" | sed 's|/|-|g'; }
route_of() { printf '%s' "$CFG/projects/$(key_for "$1")/memory"; }
is_link() { [ -L "$1" ] && echo link || echo "not a link"; }
mkdir -p "$(route_of "$T")"; printf -- '---\nname: a\n---\nx\n' > "$(route_of "$T")/a.md"
printf 'main\t~/main\tw\nother\t~/other\tw\n' > "$PRIV/inject.d/box/projects.tsv"
# `other` is a registry row that is not a worktree: it is routed only if the hook ran the router.
G() { HOME="$T" PORT_ROOT="$T/port" HARBOR_SCOPE_PRIVATE="$PRIV" HARBOR_SCOPE_REPO="$REPOROOT" CLAUDE_CONFIG_DIR="$CFG" git -C "$T/main" -c core.hooksPath="$T_ROOT/hooks" "$@"; }
git -C "$T/main" init -q; git -C "$T/main" config user.email t@t; git -C "$T/main" config user.name t
: > "$T/main/f"; git -C "$T/main" add -A >/dev/null 2>&1; git -C "$T/main" commit -qm base >/dev/null 2>&1

t_section "an ordinary checkout does not run the router"
G checkout -q -b plain >/dev/null 2>&1
t_eq "a branch switch routes nothing" "not a link" "$(is_link "$(route_of "$T/other")")"

t_section "a fresh clone is not a linked worktree"
G clone -q "$T/main" "$T/cloned" >/dev/null 2>&1
t_eq "a clone routes nothing" "not a link" "$(is_link "$(route_of "$T/other")")"

t_section "a new linked worktree is routed, with the whole tree"
G worktree add -q -b side "$T/main-wt-side" >/dev/null 2>&1
t_eq "the worktree exists" yes "$([ -f "$T/main-wt-side/.git" ] && echo yes || echo no)"
t_eq "the new worktree is routed to the store" link "$(is_link "$(route_of "$T/main-wt-side")")"
t_eq "…by the one router, so the registry's other rows are too" link "$(is_link "$(route_of "$T/other")")"

t_section "a later checkout INSIDE a linked worktree is ordinary again"
rm -f "$(route_of "$T/other")"
HOME="$T" PORT_ROOT="$T/port" HARBOR_SCOPE_PRIVATE="$PRIV" HARBOR_SCOPE_REPO="$REPOROOT" CLAUDE_CONFIG_DIR="$CFG" git -C "$T/main-wt-side" -c core.hooksPath="$T_ROOT/hooks" checkout -q -b again >/dev/null 2>&1
t_eq "a branch switch in a worktree routes nothing" "not a link" "$(is_link "$(route_of "$T/other")")"

t_section "harbor#966: another repo's raw worktree is blind until the hook is wired box-wide"
# The 2026-10-04 reading (RED 1 of 56, GREEN later that day): harbor's hooksPath reaches harbor's trees only.
printf 'wl\t~/wl\tw\n' >> "$PRIV/inject.d/box/projects.tsv"
git init -q "$T/wl"; git -C "$T/wl" config user.email t@t; git -C "$T/wl" config user.name t
: > "$T/wl/f"; git -C "$T/wl" add -A >/dev/null 2>&1; git -C "$T/wl" commit -qm base >/dev/null 2>&1
: > "$T/gc-none"
printf '[hook "harbor-memory-route"]\n\tevent = post-checkout\n\tcommand = %s\n' "$T_ROOT/hooks/post-checkout" > "$T/gc-hook"
W() { _gc="$1"; shift; HOME="$T" PORT_ROOT="$T/port" HARBOR_SCOPE_PRIVATE="$PRIV" HARBOR_SCOPE_REPO="$REPOROOT" CLAUDE_CONFIG_DIR="$CFG" \
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$_gc" "$@"; }
route() { W "$T/gc-none" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" 2>/dev/null; }
W "$T/gc-none" git -C "$T/wl" worktree add -q -b a "$T/wl-wt-a" >/dev/null 2>&1
t_eq "a raw worktree of a repo with no harbor hook is not routed" "not a link" "$(is_link "$(route_of "$T/wl-wt-a")")"
_out="$(route)"; _c=$?
t_eq "…and memory-route reads RED" 1 "$_c"
t_has "…naming that worktree" "$_out" 'BLIND  wl/wl-wt-a'
t_has "…and naming the unwired box-wide hook as the cause" "$_out" 'not wired box-wide'
_out="$(W "$T/gc-hook" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" 2>/dev/null)"
t_hasnt "…which it does not say once the hook is wired" "$_out" 'not wired box-wide'
W "$T/gc-hook" git -C "$T/wl" worktree add -q -b b "$T/wl-wt-b" >/dev/null 2>&1
t_eq "with the box-wide config hook, the new worktree is routed" link "$(is_link "$(route_of "$T/wl-wt-b")")"
t_eq "…and so is the one made before it, by the one router" link "$(is_link "$(route_of "$T/wl-wt-a")")"
route >/dev/null; t_eq "…and memory-route reads GREEN" 0 "$?"

t_section "box-wide, a worktree outside \$HOME never runs the router"
rm -f "$(route_of "$T/other")"
_o="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/outside"
git init -q "$_o"; git -C "$_o" config user.email t@t; git -C "$_o" config user.name t
: > "$_o/f"; git -C "$_o" add -A >/dev/null 2>&1; git -C "$_o" commit -qm base >/dev/null 2>&1
W "$T/gc-hook" git -C "$_o" worktree add -q -b c "$_o-wt-c" >/dev/null 2>&1
t_eq "the worktree exists" yes "$([ -f "$_o-wt-c/.git" ] && echo yes || echo no)"
t_eq "…and no route was made anywhere (the router did not run)" "not a link" "$(is_link "$(route_of "$T/other")")"

t_section "the hook never fails the checkout"
rm -f "$PRIV/inject.d/box/projects.tsv"
_out="$(G worktree add -b side2 "$T/main-wt-side2" 2>&1)"; _c=$?
t_eq "a router that stands down does not fail git worktree add" 0 "$_c"
t_has "…and the operator is told the route is incomplete" "$_out" 'memory route incomplete'
t_eq "…and the worktree still exists" yes "$([ -f "$T/main-wt-side2/.git" ] && echo yes || echo no)"
t_done
