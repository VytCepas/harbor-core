#!/usr/bin/env sh
# library-git-safe.sh (harbor#1278) — git for a member hook, on a repo the agent can write. Sourced; never run.
# A managed hook runs OUTSIDE the sandbox. A repo's own `.git/config` (a filter, a textconv, diff.external, core.fsmonitor, core.hooksPath,
# core.pager, an include.path to more of the same) and its `.gitattributes` are files the agent can write, and git runs the programs they name.
# Env cannot switch repo config off, so this does not ask git to: the repo's config is never read.
#   gs_open <repo> <workdir>   builds <workdir>/gd, a git dir of our own: the repo's HEAD, index and refs, a config of one line, no hooks, no
#                              info/attributes, and sets GS_DIR. Objects are read from the repo's object store (data, never a program).
#                              Returns 1 on anything unexpected (no .git directory, a .git file or symlink, an unreadable index): the caller
#                              fails open. The repo's own index is copied, never written.
#   gs_open_at <tree> <gitdir> <commondir> <workdir>   the same for a linked worktree.
#   gs_git <args>              git against that dir and the repo's work tree, with every switch that stops a program the work tree can still
#                              name (.gitattributes names a filter, but no filter is defined, so none runs).
#   gs_env                     the same switches as a prefix for a caller that cannot use gs_open: LESS than gs_open, as the repo's config is
#                              still read, so it stops the global and system files and the flags only. Use gs_open for a repo the agent writes.
# Pass --no-ext-diff --no-textconv to diff and --no-filters to hash-object as well: each stops a program on its own if a caller ever swaps the dir.
GS_DIR=''; GS_TREE=''; GS_OBJ=''
gs_open() {
  _gr="$1"; _gw="$2"
  [ -d "$_gr/.git" ] && [ ! -L "$_gr/.git" ] && [ -r "$_gr/.git/HEAD" ] || return 1
  gs_open_at "$_gr" "$_gr/.git" "$_gr/.git" "$_gw"
}
# gs_open_at <work tree> <git dir> <common git dir> <workdir> — the same private dir for a tree whose git dir is not <tree>/.git (a linked
# worktree: its HEAD and index sit in <git dir>, its refs and objects in <common git dir>). The caller got the three paths from
# `gs_env rev-parse`, which only reads. Index is copied with -p: git's racy-entry check compares the index mtime, and a fresh one hid an edit.
gs_open_at() {
  _gr="$1"; _gg="$2"; _gc="$3"; _gw="$4"
  [ -d "$_gg" ] && [ -r "$_gg/HEAD" ] && [ -d "$_gc/objects" ] && [ -d "$_gc/refs" ] || return 1
  rm -rf "$_gw/gd"; mkdir -p "$_gw/gd" || return 1
  cp "$_gg/HEAD" "$_gw/gd/HEAD" 2>/dev/null || return 1
  if [ -e "$_gg/index" ]; then cp -p "$_gg/index" "$_gw/gd/index" 2>/dev/null || return 1; fi
  ln -s "$_gc/refs" "$_gw/gd/refs" 2>/dev/null || return 1
  [ ! -e "$_gc/packed-refs" ] || ln -s "$_gc/packed-refs" "$_gw/gd/packed-refs" 2>/dev/null || return 1
  printf '[core]\n\trepositoryformatversion = 0\n' > "$_gw/gd/config" || return 1
  # Case folding is a property of the filesystem, not a program: without it a case-only rename reads as a delete plus an untracked file.
  for _gk in ignorecase precomposeunicode; do
    _gv="$(gs_env config --file "$_gc/config" --get "core.$_gk" 2>/dev/null)" || continue
    case "$_gv" in true|false) printf '\t%s = %s\n' "$_gk" "$_gv" >> "$_gw/gd/config" ;; esac
  done
  # info/exclude is a list of patterns (data): what the repo ignores stays ignored. info/attributes is NOT copied: it can name a filter's path.
  if [ -f "$_gc/info/exclude" ]; then mkdir -p "$_gw/gd/info" && cp "$_gc/info/exclude" "$_gw/gd/info/exclude" 2>/dev/null || return 1; fi
  GS_DIR="$_gw/gd"; GS_TREE="$_gr"; GS_OBJ="$_gc/objects"
  return 0
}
# gs_open_in <dir> <workdir> — gs_open_at for whatever checkout holds <dir> (a subdirectory, a linked worktree): the three paths come from
# `gs_env rev-parse`, which only reads. Sets GS_PREFIX, <dir>'s path under the tree ('' at the top, else 'sub/'), for a pathspec.
GS_PREFIX=''
gs_open_in() {
  _gi="$(gs_env -C "$1" rev-parse --show-toplevel --absolute-git-dir --git-common-dir --show-prefix 2>/dev/null)" || return 1
  { read -r _gi_t; read -r _gi_g; read -r _gi_c; read -r _gi_p; } <<GS_EOF
$_gi
GS_EOF
  [ -n "$_gi_t" ] || return 1
  case "$_gi_c" in /*) ;; *) _gi_c="$1/$_gi_c" ;; esac
  gs_open_at "$_gi_t" "$_gi_g" "$_gi_c" "$2" || return 1
  GS_PREFIX="$_gi_p"
}
# gs_track <dir> — after gs_open_in <dir>: copy the current branch's upstream (branch.<b>.remote, .merge and the remote's fetch refspecs) into the
# private config, so `status -b` can say ahead/behind. Values are written by `config --file` (data), never read back as a program.
gs_track() {
  _gt_b="$(gs_env -C "$1" symbolic-ref -q --short HEAD 2>/dev/null)" || return 0
  _gt_r="$(gs_env -C "$1" config --get "branch.$_gt_b.remote" 2>/dev/null)" || return 0
  _gt_m="$(gs_env -C "$1" config --get "branch.$_gt_b.merge" 2>/dev/null)" || return 0
  [ -n "$_gt_r" ] && [ -n "$_gt_m" ] || return 0
  gs_env config --file "$GS_DIR/config" "branch.$_gt_b.remote" "$_gt_r" || return 0
  gs_env config --file "$GS_DIR/config" "branch.$_gt_b.merge" "$_gt_m" || return 0
  gs_env -C "$1" config --get-all "remote.$_gt_r.fetch" 2>/dev/null | while IFS= read -r _gt_f; do
    [ -z "$_gt_f" ] || gs_env config --file "$GS_DIR/config" --add "remote.$_gt_r.fetch" "$_gt_f"
  done
  return 0
}
GS_FLAGS='-c core.attributesFile=/dev/null -c core.fsmonitor=false -c core.hooksPath=/dev/null -c diff.external= -c core.pager=cat -c core.untrackedCache=false -c core.sshCommand=false -c credential.helper= -c protocol.ext.allow=never -c core.fileMode=true'
gs_git() {
  # shellcheck disable=SC2086 # GS_FLAGS is a fixed list of words
  ( cd "$GS_TREE" 2>/dev/null || exit 1; exec env -u GIT_EXTERNAL_DIFF -u GIT_PAGER -u GIT_SSH -u GIT_SSH_COMMAND -u GIT_ASKPASS -u GIT_INDEX_FILE -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
    GIT_DIR="$GS_DIR" GIT_WORK_TREE="$GS_TREE" GIT_OBJECT_DIRECTORY="$GS_OBJ" GIT_PAGER=cat GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 git $GS_FLAGS "$@" )
}
gs_env() {
  # shellcheck disable=SC2086
  env -u GIT_EXTERNAL_DIFF GIT_PAGER=cat GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 git $GS_FLAGS "$@"
}
