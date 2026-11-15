#!/usr/bin/env sh
# hooks/lib.sh (harbor#824, cf. project-init#1065) — shared by hooks/pre-commit and hooks/pre-push.
# Never run: every function is safe under the caller's `set -eu`.
# The hazard: git exports GIT_DIR (and GIT_WORK_TREE/GIT_INDEX_FILE in a linked worktree) into every hook, and GIT_DIR beats an unrelated `-C <dir>`, so a suite driving its own scratch repo acted on the real one (project-init#1065).
# The scrub is scoped to the suite/lint boundary, never the whole hook: the hooks' own git calls need the REAL GIT_DIR.
# Removed notes: docs/explanation/code-cases/hooks-lib.md
hook_scrub_run() { # <cmd> [args…] — run with the git-hook env vars gone, whatever else is passed
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
      -u GIT_QUARANTINE_PATH -u GIT_PREFIX "$@"
}

# hook_event <kind> <subject> <src> (harbor#1043): one event on the local bus (bin/event-bus.sh beside hooks/); needs $_hk_here from the caller. Can neither fail nor print; a missing bus emits nothing.
hook_event() {
  [ -n "${2-}" ] && [ -f "$_hk_here/../bin/event-bus.sh" ] || return 0
  # Bounded (harbor#1051): a bus that hangs is killed after HARBOR_EVENT_BUS_TIMEOUT s (default 2, 1..60), with its children.
  _hb="${HARBOR_EVENT_BUS_TIMEOUT:-2}"; case "$_hb" in ''|*[!0-9]*) _hb=2 ;; esac
  [ "$_hb" -ge 1 ] && [ "$_hb" -le 60 ] || _hb=2
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

# hook_replaying (harbor#1114): true during a rebase or multi-commit pick, whose post-commit replays rewrite commits that already have an event. CHERRY_PICK_HEAD is deliberately not a marker: it is set during a plain single pick, which must emit.
hook_replaying() {
  for _hr in rebase-merge rebase-apply sequencer; do
    _hrp="$(git rev-parse --git-path "$_hr" 2>/dev/null)" || continue
    [ -z "$_hrp" ] || [ ! -e "$_hrp" ] || return 0
  done
  return 1
}
