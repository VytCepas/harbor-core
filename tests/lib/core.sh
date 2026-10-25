# tests/lib/core.sh — the harness every suite under tests/ sources (harbor#667).
#
#   . "$(dirname "$0")/../lib/core.sh"; t_init
#   t_section "name"; t_eq/t_has/t_hasnt/t_exit …; t_done
#
# t_init sandboxes the run: HOME, CLAUDE_CONFIG_DIR and TMPDIR point into a fresh
# temp dir, the caller's HELM_* and HARBOR_* knobs are cleared, and $T_BIN leads PATH for stubs.
# A section that runs no assertion fails, and so does a suite that runs none.

# The caller variables t_init keeps (lint C10 reads this line): status-gen's re-entry marker must
# reach a suite it runs and that suite's children, or the suite runs status-gen back (harbor#288).
T_PASS_ENV='HARBOR_IN_SUITE'

t_init() { # [name] — defaults to the file name without .sh
  T_NAME="${1:-$(basename "$0" .sh)}"
  T_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  while [ "$T_ROOT" != / ] && [ ! -f "$T_ROOT/CONTRACTS/suites.txt" ]; do
    T_ROOT="$(dirname "$T_ROOT")"
  done
  if [ ! -f "$T_ROOT/CONTRACTS/suites.txt" ]; then
    # A suite the box carries sets T_STANDALONE=1 (harbor#727): with no checkout, its root is the dir above its own.
    [ "${T_STANDALONE:-0}" = 1 ] || { echo "$T_NAME: repo root not found" >&2; exit 2; }
    T_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
  fi
  T_SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/${0##*/}"; T_SELF="${T_SELF#"$T_ROOT"/}"
  _td="${TMPDIR:-/tmp}"
  T_TMP="$(mktemp -d "${_td%/}/$T_NAME.XXXXXX")" || exit 2
  trap 'chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT  # u+w: an installed floor leaves 0500 dirs
  trap 'exit 130' INT TERM HUP
  mkdir -p "$T_TMP/home" "$T_TMP/cfg" "$T_TMP/tmp" "$T_TMP/bin"
  T_BIN="$T_TMP/bin"
  HOME="$T_TMP/home"; CLAUDE_CONFIG_DIR="$T_TMP/cfg"; TMPDIR="$T_TMP/tmp"
  PATH="$T_BIN:$PATH"
  export HOME CLAUDE_CONFIG_DIR TMPDIR PATH
  # Knobs from the caller's shell must not decide a verdict here: every HELM_*, HARBOR_* (CI's
  # HARBOR_SUITE_COUNTS cost floor.status-test 4 passes, harbor#773) and GIT_* (a suite's own
  # `git -C "$T_TMP/…"` inherits GIT_DIR, harbor#824) and XDG_* (a runner's outranks HOME, harbor#865).
  for _v in $(env | sed -n -e 's/^\(HELM_[A-Za-z0-9_]*\)=.*/\1/p' -e 's/^\(HARBOR_[A-Za-z0-9_]*\)=.*/\1/p') \
            CLOUD_POSTURE CLOUDSDK_CONFIG FAST XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME \
            GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
            GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_PREFIX; do
    case " $T_PASS_ENV " in *" $_v "*) ;; *) unset "$_v" ;; esac
  done
  # No suite drives the real Chrome: `harbor chrome attach` opens a window through AppleScript.
  HARBOR_OSASCRIPT=false; export HARBOR_OSASCRIPT
  # No suite reads the real credential store: a store-reading tool's case brings its own stub (harbor#1205).
  HARBOR_SECRET_BIN="$T_TMP/no-secret-store"; export HARBOR_SECRET_BIN
  T_PASS=0; T_FAIL=0; T_SEC=""; T_SEC_N=0
  _t_cfg > "$T_TMP/.cfg.before"  # the repo's shared config, before the suite touches anything (harbor#1152)
}

# The repo's shared .git/config (worktrees share it): t_done fails a suite that adds a key there. No repo
# at T_ROOT: empty, both sides. branch.* is left out: any worktree's `git push -u` writes it mid-suite,
# which failed unrelated suites four times on 2026-10-09, and a suite never needs one.
_t_cfg() { git -C "$T_ROOT" config --local --list 2>/dev/null | grep -v '^branch\.' | sort; }
_t_cfg_leak() { # prints keys present now and absent before
  _t_cfg > "$T_TMP/.cfg.after"
  grep -vxF -f "$T_TMP/.cfg.before" "$T_TMP/.cfg.after" 2>/dev/null
}

t_pass() { T_PASS=$((T_PASS + 1)); T_SEC_N=$((T_SEC_N + 1)); }
t_fail() { # <what went wrong>
  T_FAIL=$((T_FAIL + 1)); T_SEC_N=$((T_SEC_N + 1))
  printf '  FAIL: %s%s\n' "${T_SEC:+$T_SEC · }" "$1" >&2
}

t_section() { # <title>
  _t_close
  T_SEC="$1"; T_SEC_N=0
  printf '── %s\n' "$1"
}
_t_close() { [ -z "$T_SEC" ] || [ "$T_SEC_N" -gt 0 ] || t_fail "section ran no assertions"; }

t_eq()    { [ "$3" = "$2" ] && t_pass || t_fail "$1 (want '$2', got '$3')"; }        # <label> <want> <got>
t_has()   { case "$2" in *"$3"*) t_pass ;; *) t_fail "$1 (missing: $3)" ;; esac; }  # <label> <text> <needle>
t_hasnt() { # a negative on empty output proves nothing, so empty fails (lint F9's point)
  case "$2" in '') t_fail "$1 (no text to check)" ;; *"$3"*) t_fail "$1 (must not contain: $3)" ;; *) t_pass ;; esac
}
t_exit() { # <label> <want-exit> <cmd> [args…] — the exact code, never "non-zero"
  _tl="$1"; _tw="$2"; shift 2
  "$@" >/dev/null 2>&1; _tr=$?
  t_eq "$_tl" "exit $_tw" "exit $_tr"
}

t_done() {
  _t_close
  _tk="$(_t_cfg_leak | sed 's/=.*//' | tr '\n' ' ')"
  [ -z "$_tk" ] || t_fail "wrote the shared git config of $T_ROOT (added: ${_tk% }) — a suite must touch only its temp repo (harbor#1152)"
  [ $((T_PASS + T_FAIL)) -gt 0 ] || t_fail "the suite ran no assertions"
  # A failed suite's FAIL lines end in one fix line naming its file (CONTRACTS/logging.md, harbor#771).
  [ "$T_FAIL" -eq 0 ] || printf '  fix: none automatic — see %s\n' "$T_SELF" >&2
  if [ "${T_SMOKE:-0}" = 1 ]; then printf '%s smoke: %d passed, %d failed (NOT a full run)\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  else printf '%s: %d passed, %d failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"; fi
  [ "$T_FAIL" -eq 0 ] && exit 0
  exit 1
}
