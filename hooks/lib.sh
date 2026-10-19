#!/usr/bin/env sh
# hooks/lib.sh (harbor#824, cf. project-init#1065) — shared by hooks/pre-commit and hooks/pre-push.
# Never run: every function is safe under the caller's `set -eu`.
#
# THE HAZARD. git exports GIT_DIR (and, in a linked worktree, GIT_WORK_TREE and GIT_INDEX_FILE)
# into every hook's process. Probed 2026-09-29: GIT_DIR wins over an unrelated `-C <dir>` for
# every ref-touching operation — `git -C fakeroot commit --allow-empty` under a poisoned GIT_DIR
# landed the commit on the OTHER repo's refs, not fakeroot's, and `-C`'s own `--show-toplevel`
# printed fakeroot while `log` read the other repo's history. A suite that builds its own scratch
# git repo in a tmpdir and drives it with `git -C "$tmp" …`, expecting isolation, instead acts on
# whatever repo GIT_DIR names — the real one the hook fired in. That is project-init#1065: synthetic
# commits landed on the pushed branch, local main moved, and stray config keys were written.
# Harbor's own lint-conventions.sh showed the milder half of the same bug: 10 spurious VIOLATIONs
# and an altered read (IJ6, C2) purely from GIT_DIR pointing elsewhere — its `git -C "$ROOT"` calls
# stopped seeing $ROOT.
#
# THE SCRUB IS SCOPED TO THE SUITE/LINT BOUNDARY, NEVER THE WHOLE HOOK. Both hooks call git
# themselves before this point — `git rev-parse --show-toplevel`, `git diff --cached`,
# `git checkout-index` — and those calls need the REAL GIT_DIR to see the repo the hook fired in.
# Unsetting these vars for the whole hook would break that. hook_scrub_run wraps only the
# subprocess that runs a suite, the linter, or the floor smoke.
hook_scrub_run() { # <cmd> [args…] — run with the git-hook env vars gone, whatever else is passed
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
      -u GIT_QUARANTINE_PATH -u GIT_PREFIX "$@"
}

# hook_event <kind> <subject> <src> (harbor#1043, E1 PR 2) — one event on the local bus. Needs
# $_hk_here, the directory this file is in (the caller sets it before sourcing). It can neither
# fail nor print: a bus that is missing, unwritable or broken costs the commit nothing, and the
# hook's own `exit 0` is the second guard. The bus is bin/event-bus.sh beside hooks/, never
# assumed under the repo root — a foreign repo that points core.hooksPath here has no bus, and
# then nothing is emitted.
hook_event() {
  [ -n "${2-}" ] && [ -f "$_hk_here/../bin/event-bus.sh" ] || return 0
  # Bounded (harbor#1051, §3a.9): a bus that hangs is killed after HARBOR_EVENT_BUS_TIMEOUT s
  # (default 2, 1..60), with its children, and the commit goes on. Same shape as bin/event-hook.sh.
  _hb="${HARBOR_EVENT_BUS_TIMEOUT:-2}"; case "$_hb" in ''|*[!0-9]*) _hb=2 ;; esac
  [ "$_hb" -ge 1 ] && [ "$_hb" -le 60 ] || _hb=2
  # With perl the bus is its own process-group leader and the kill takes the group, so a double-forked
  # child dies too; without perl only direct children do (docs/design/events.md, "Bounded").
  _hq=""
  if command -v perl >/dev/null 2>&1; then
    _hq=1; perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' -- sh "$_hk_here/../bin/event-bus.sh" emit "$1" "$2" --src "$3" >/dev/null 2>&1 </dev/null & _hp=$!
  else
    sh "$_hk_here/../bin/event-bus.sh" emit "$1" "$2" --src "$3" >/dev/null 2>&1 </dev/null & _hp=$!
  fi
  ( trap 'kill "$_hs"; exit 0' TERM; sleep "$_hb" & _hs=$!
    wait "$_hs" && { if [ -n "$_hq" ]; then kill -s TERM -- "-$_hp"; else pkill -P "$_hp"; fi; kill "$_hp"; } ) >/dev/null 2>&1 </dev/null & _hg=$!
  wait "$_hp" 2>/dev/null || :
  kill "$_hg" 2>/dev/null || :; wait "$_hg" 2>/dev/null || :
}

# hook_replaying (harbor#1114) — true while a rebase or a multi-commit cherry-pick/revert (git's
# sequencer) is in progress: git replays commits through post-commit then, and each is a rewrite of one
# that already has its event, not a new commit (a 20-commit rebase wrote 20 events and paid the bus
# bound per commit). Asked of git as --git-path, so a linked worktree's own state dir is the one read.
# CHERRY_PICK_HEAD is deliberately not a marker: git leaves it set while a plain single cherry-pick
# runs post-commit (measured), and that pick is a genuine new commit that must emit.
hook_replaying() {
  for _hr in rebase-merge rebase-apply sequencer; do
    _hrp="$(git rev-parse --git-path "$_hr" 2>/dev/null)" || continue
    [ -z "$_hrp" ] || [ ! -e "$_hrp" ] || return 0
  done
  return 1
}
