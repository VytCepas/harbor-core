#!/usr/bin/env sh
# worktree.sh keeps the repo's name out of the worktree it is run from, lists the old sibling layout and the
# new one side by side, and takes the emptied <repo>/ directory with the last tree (harbor#1149).
. "$(dirname "$0")/../../lib/core.sh"; t_init
WT="$T_ROOT/bin/worktree.sh"
P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
mkdir -p "$P/sessions" "$P/peers" "$P/cfg" "$P/port"
g() { _d="$1"; shift; git -C "$_d" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
yn() { if "$@"; then echo yes; else echo no; fi; }
REPO="$P/port/repo"; mkdir -p "$REPO"; git init -q "$REPO"; git -C "$REPO" symbolic-ref HEAD refs/heads/main
: > "$REPO/seed"; g "$REPO" add seed; g "$REPO" commit -qm seed
SEED="$(git -C "$REPO" rev-parse HEAD)"; git -C "$REPO" update-ref refs/remotes/origin/main "$SEED"
# $1 is the checkout worktree.sh runs from: the main one, or a linked tree of it.
wtf() { _r="$1"; shift
  HOME="$P" PORT_ROOT="$P/port" HARBOR_ROOT="$_r" HARBOR_BASE=origin/main CLAUDE_CONFIG_DIR="$P/cfg" \
    HARBOR_SESSIONS_DIR="$P/sessions" HARBOR_PEERS_DIR="$P/peers" sh "$WT" "$@" 2>&1; }
verdict() { wtf "$REPO" list | awk -v p="$1" '$2 == p { print $1; exit }'; }  # <path> → verdict

t_section "new, run from inside a linked worktree, names the repo and not the worktree"
g "$REPO" worktree add -q -b b-host "$P/port/repo-wt-host" "$SEED" >/dev/null 2>&1
wtf "$P/port/repo-wt-host" new feat/inner >/dev/null
t_eq "the tree is under .worktrees/repo/" yes "$(yn [ -d "$P/port/.worktrees/repo/feat-inner" ])"
t_eq "…and nothing is nested under the host worktree's own name" no "$(yn [ -e "$P/port/.worktrees/repo-wt-host" ])"

t_section "both layouts in one listing, the old one untouched"
t_eq "the new tree is listed" COLLECT "$(verdict "$P/port/.worktrees/repo/feat-inner")"
t_eq "the legacy sibling is listed" COLLECT "$(verdict "$P/port/repo-wt-host")"
wtf "$REPO" gc >/dev/null
t_eq "a dry-run gc moved neither" yesyes "$(yn [ -d "$P/port/repo-wt-host" ])$(yn [ -d "$P/port/.worktrees/repo/feat-inner" ])"

t_section "the last tree takes its emptied <repo>/ directory with it, and only then"
wtf "$REPO" new feat/second >/dev/null
wtf "$REPO" retire feat-inner >/dev/null
t_eq "a sibling tree keeps the directory" yes "$(yn [ -d "$P/port/.worktrees/repo" ])"
wtf "$REPO" retire feat-second >/dev/null
t_eq "the emptied directory goes" no "$(yn [ -d "$P/port/.worktrees/repo" ])"
t_eq ".worktrees itself stays" yes "$(yn [ -d "$P/port/.worktrees" ])"
wtf "$REPO" new feat/third >/dev/null; : > "$P/port/.worktrees/repo/stray-file"
wtf "$REPO" retire feat-third >/dev/null
t_eq "a directory holding anything else is not removed" yes "$(yn [ -e "$P/port/.worktrees/repo/stray-file" ])"
wtf "$REPO" gc --apply >/dev/null
t_eq "gc --apply collected the legacy sibling" no "$(yn [ -d "$P/port/repo-wt-host" ])"
t_done
