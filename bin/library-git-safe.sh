#!/usr/bin/env sh
# library-git-safe.sh (harbor#1278) — git for a member hook, on a repo the agent can write. Sourced; never run.
# A managed hook runs OUTSIDE the sandbox. A repo's own `.git/config` (a filter, a textconv, diff.external, core.fsmonitor, core.hooksPath,
# core.pager, an include.path to more of the same) and its `.gitattributes` are files the agent can write, and git runs the programs they name.
# Env cannot switch repo config off, so this does not ask git to: the repo's config is never read.
#   gs_open <repo> <workdir>   builds <workdir>/gd, a git dir of our own: the repo's HEAD, index and refs, a config of one line, no hooks, no
#                              info/attributes, and sets GS_DIR. Objects are read from the repo's object store (data, never a program).
#                              Returns 1 on anything unexpected (no .git directory, a .git file or symlink, an unreadable index): the caller
#                              fails open. The repo's own index is copied, never written.
#   gs_git <args>              git against that dir and the repo's work tree, with every switch that stops a program the work tree can still
#                              name (.gitattributes names a filter, but no filter is defined, so none runs).
#   gs_env                     the same switches as a prefix for a caller that cannot use gs_open: LESS than gs_open, as the repo's config is
#                              still read, so it stops the global and system files and the flags only. Use gs_open for a repo the agent writes.
# The index copy keeps its mtime (cp -p): git treats an entry as racy when the file is not older than the index, and a fresh mtime would hide a
# same-size edit made in the same second.
# Fails open, unchecked, on: a linked worktree or any .git that is a file, a .git symlink, a split-index repo, a sha256 repo.
# --no-ext-diff --no-textconv (diff) and --no-filters (hash-object) are defence in depth: with the repo's config never read, no filter or textconv
# is defined, so removing them changes nothing today; they keep a caller that swaps the dir from running one.
GS_DIR=''; GS_TREE=''
gs_open() {
  _gr="$1"; _gw="$2"
  [ -d "$_gr/.git" ] && [ ! -L "$_gr/.git" ] && [ -r "$_gr/.git/HEAD" ] || return 1
  rm -rf "$_gw/gd"; mkdir -p "$_gw/gd" || return 1
  cp "$_gr/.git/HEAD" "$_gw/gd/HEAD" 2>/dev/null || return 1
  if [ -e "$_gr/.git/index" ]; then cp -p "$_gr/.git/index" "$_gw/gd/index" 2>/dev/null || return 1; fi
  ln -s "$_gr/.git/refs" "$_gw/gd/refs" 2>/dev/null || return 1
  [ ! -e "$_gr/.git/packed-refs" ] || ln -s "$_gr/.git/packed-refs" "$_gw/gd/packed-refs" 2>/dev/null || return 1
  printf '[core]\n\trepositoryformatversion = 0\n' > "$_gw/gd/config" || return 1
  GS_DIR="$_gw/gd"; GS_TREE="$_gr"
  return 0
}
GS_FLAGS='-c core.attributesFile=/dev/null -c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external= -c core.pager=cat -c core.untrackedCache=false -c core.sshCommand=false -c credential.helper= -c protocol.ext.allow=never -c core.fileMode=true'
gs_git() {
  # shellcheck disable=SC2086 # GS_FLAGS is a fixed list of words
  ( cd "$GS_TREE" 2>/dev/null || exit 1; exec env -u GIT_EXTERNAL_DIFF -u GIT_PAGER -u GIT_SSH -u GIT_SSH_COMMAND -u GIT_ASKPASS -u GIT_INDEX_FILE -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    GIT_DIR="$GS_DIR" GIT_WORK_TREE="$GS_TREE" GIT_OBJECT_DIRECTORY="$GS_TREE/.git/objects" GIT_PAGER=cat GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 git $GS_FLAGS "$@" )
}
gs_env() {
  # shellcheck disable=SC2086
  env -u GIT_EXTERNAL_DIFF GIT_PAGER=cat GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 git $GS_FLAGS "$@"
}
