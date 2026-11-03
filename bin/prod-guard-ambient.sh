#!/usr/bin/env sh
set -eu
# B10 (harbor#56) — the ambient shim for yard's `prod_guard.py`.
# Shim, not a fork: prod_guard.py is yard's file and owns the cloud/data destruction corpus (bin/admission-bash.sh deliberately omits that class). The installed copy stays byte-identical (asserted by prod-guard-test.sh); the deferral lives here (contracts/marker.md).
# Why it defers (harbor#56): two PreToolUse hooks returning `ask` give ONE prompt whose reason is from whichever hook COMPLETED LAST, so two guards on one command is a nondeterministic message. Exactly one guard owns the message per command. Not `permissionDecision: defer`: measured, it produced no tool_result next to a project `ask`. Standing down at exit 0 with no output is the floor's own idiom (floor_engine_stand_down).
# The predicate is wiring, not marker presence (every governed repo has a marker and none wires prod_guard), asked of the RENDERED settings file the harness reads, never of the template.
# Removed notes: docs/explanation/code-cases/bin-prod-guard-ambient.md

usage() { printf '  FAIL: usage: prod-guard-ambient.sh <installed-prod_guard.py>\n  fix: none automatic — see bin/prod-guard-install.sh, which wires it\n' >&2; exit 2; }
[ $# -eq 1 ] || usage
GUARD="$1"

PAYLOAD="$(cat)"

# the ledger (harbor#320): this guard's decisions were invisible to the statusline, block counter and false-positive detector, and "absent" reads as "never fired". Logging is lazy (library-admission.sh is large and this runs on every Bash call, so it loads after the verdict exists), subshelled with `set +eu` (an aborting hook is a hard block, not a stand-down) and redirected (hook stdout IS the verdict). Lint C7 holds the `prod` token in FLOOR_OBS_GUARDS. harbor#813: no dirname fork.
case "$0" in */*) _LIB="${0%/*}/library-admission.sh" ;; *) _LIB=./library-admission.sh ;; esac
_log() { # <verdict> <rule.shape>; FLOOR_IN gives the record its session key (harbor#309)
  [ -f "$_LIB" ] || return 0
  # shellcheck disable=SC2034 # FLOOR_IN, FLOOR_TOOL: read by library-admission.sh
  ( set +eu; FLOOR_TOOL=Bash; FLOOR_IN="$PAYLOAD"; . "$_LIB"; floor_log_decision prod "$1" "$2" ) \
    >/dev/null 2>&1 || :
}

# The session cwd the harness sends, not this process's $PWD.
d=""
if command -v jq >/dev/null 2>&1; then
  d="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$d" ] || d="${CLAUDE_PROJECT_DIR:-$PWD}"

# Up-walk for a rendered settings file that wires a prod_guard; a symlinked settings file is ignored (marker forgery, library-admission.sh). Mode `other` excludes this shim's own command by BASENAME, not the whole directory (Codex review on #77): prod-guard-install.sh merges additively, so a prod_guard wired in the ambient settings before the install survives it and does own the message.
wires_prod_guard() { # <settings-file> [other]
  _s="$1"; _mode="${2:-any}"
  [ -f "$_s" ] && [ ! -L "$_s" ] || return 1
  # Cheap gate first: this runs on every Bash call; jq only on a hit.
  grep -q 'prod_guard' "$_s" 2>/dev/null || return 1
  # No jq: for a PROJECT that is still a defer; for the AMBIENT dir stay armed (a duplicated prompt on a command that stays gated beats a silent stand-down).
  command -v jq >/dev/null 2>&1 || { [ "$_mode" = any ]; return; }
  if [ "$_mode" = other ]; then
    # Token basename, not a substring of the command (Codex review on #77): a PATH component named prod-guard-ambient-user must not hide a foreign guard. Both quote characters are stripped (\047 is the portable single quote, since the awk program is itself single-quoted); an unstripped trailing quote classified our own command as foreign. One command must be one awk record, so `gsub` inside jq collapses whitespace per command (a `tr` after jq would merge separate commands).
    jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty | gsub("[[:space:]]+";" ")' \
      "$_s" 2>/dev/null \
      | awk '
          /prod_guard/ {
            self = 0
            for (i = 1; i <= NF; i++) {
              t = $i; gsub(/["\047]/, "", t); sub(/^.*\//, "", t)
              if (t == "prod-guard-ambient.sh") self = 1
            }
            if (!self) other = 1
          }
          END { exit(other ? 0 : 1) }'
  else
    printf '%s' "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | join(" ")' "$_s" 2>/dev/null || true)" \
      | grep -q 'prod_guard'
  fi
}

# The up-walk must not find itself: ~/.claude/settings.json wires this shim and is an ancestor .claude of every path under $HOME, so the unguarded walk stood down for all real work (measured: `terraform destroy` returned nothing from ~/Documents, a correct ask from /tmp). The ambient dir is derived from the guard path argument (two dirnames up): correct under CLAUDE_CONFIG_DIR and hermetic in fixtures. A project's own copy is still deferred to.
# `/bin/pwd -P`, not the builtin: bash 3.2 (macOS /bin/sh) returns the lexically canonicalised argument even with -P, so on a case-insensitive volume two spellings of one directory compare unequal. `stat -f` is BSD-only, so rejected.
# `CDPATH=''`, not bare `CDPATH=`: the linter reads the bare form as a typo (SC1007). A comment line may not START with the linter's own name, or it is parsed as a directive.
_canon() {
  ( CDPATH='' cd -P -- "$1" 2>/dev/null && { /bin/pwd -P 2>/dev/null || pwd; } ) ||
    printf '%s\n' "$1"
}

# Two identities for the ambient dir, and the union is the skip set: two dirnames up from the guard argument (the installer's shape), and the config dir resolved directly (lint D1's idiom), since a guard passed from outside the config dir would resurrect the self-defer.
ambient_cfg="$(_canon "$(dirname "$(dirname "$GUARD")")")"

# `${HOME:-}`, not `$HOME`: under set -u an unset HOME aborts the shim (a non-zero PreToolUse hook is a hard block), and an empty one collapses to /.claude. An unusable candidate falls back to the argv-derived identity.
_cfg_candidate="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
case "$_cfg_candidate" in
  /.claude | /.claude/ | .claude | '') live_cfg="$ambient_cfg" ;;
  *) live_cfg="$(_canon "$_cfg_candidate")" ;;
esac

while [ -n "$d" ] && [ "$d" != "/" ]; do
  if [ -d "$d/.claude" ] && [ ! -L "$d/.claude" ]; then
    c="$(_canon "$d/.claude")"
    if [ "$c" != "$ambient_cfg" ] && [ "$c" != "$live_cfg" ]; then
      # A project: ANY prod_guard wired there owns the message. `armed`, not `allow`, is the honest ledger verdict for a stand-down: this shim did not decide the command was safe.
      if wires_prod_guard "$d/.claude/settings.json"; then
        _log armed prod-project-owns.meta
        exit 0   # this repo owns the message for these commands
      fi
      if wires_prod_guard "$d/.claude/settings.local.json"; then
        _log armed prod-project-owns.meta
        exit 0
      fi
    else
      # The ambient config dir: only a prod_guard that is NOT this shim owns it.
      if wires_prod_guard "$d/.claude/settings.json" other; then
        _log armed prod-ambient-owns.meta
        exit 0
      fi
      if wires_prod_guard "$d/.claude/settings.local.json" other; then
        _log armed prod-ambient-owns.meta
        exit 0
      fi
    fi
  fi
  d="$(dirname "$d")"
done

# No project copy owns it, so this one does. A dependency failure is not exit 2 here (unlike admission-hook.sh, whose guards are vetoes): this guard asks on ~0.4% of Bash calls (harbor#56), so exit 2 on a missing python3 would deny all of it (§2.11), and silent exit 0 is the silent-allow class. So announce it as an `ask` ONCE per session, then stand down.
_broken() { # <reason>
  _sid="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null || true)"
  _stamp="${TMPDIR:-/tmp}/prod-guard-broken.${_sid:-nosession}"
  if [ -e "$_stamp" ]; then
    # Both broken paths log: after the stamp this guard is silent by design, indistinguishable from one finding nothing, so the rule token lets a reader count how long the box ran unguarded. `advise`, not `ask`: this branch emits no permissionDecision.
    _log advise prod-broken-silenced.meta
    printf '  WARN: prod-guard-ambient: %s (already reported this session)\n  fix: none automatic — see the first report this session\n' "$1" >&2
    exit 0
  fi
  : > "$_stamp" 2>/dev/null || true
  _log ask prod-broken.meta
  # The corpus as prod_guard.py's DENY_RULES hold it, bq and gsutil included (harbor#954 item 8).
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"prod-guard-ambient is INSTALLED BUT NOT FUNCTIONING: %s. Nothing is evaluating terraform/tofu destroy, kubectl/helm delete, aws/gcloud/az delete, warehouse table and dataset removal, recursive bucket removal, SQL DROP/TRUNCATE or rm -rf. Reported once per session; it will stand down silently for the rest of this session."}}\n' "$1"
  exit 0
}
[ -f "$GUARD" ] || _broken "no guard file at $GUARD"
command -v python3 >/dev/null 2>&1 || _broken "python3 not on PATH"

# The delegated verdict: the only place the shim touches the data path, so it is byte-transparent (asserted). prod_guard.py writes one json.dumps object with no trailing newline on a verdict, nothing on an allow, and returns 0 on every path; diagnostics go to stderr, unchanged.
# The `X` sentinel: `$(...)` strips trailing newlines, so appending a byte and removing it keeps the stream intact whatever the guard writes. `exit "$_r"` inside the substitution keeps a crashing python3's code (a non-zero hook is a hard block, see _broken), and `set +e` inside stops this file's `set -e` aborting before the sentinel.
_pout=""; _prc=0
_pout="$( set +e; printf '%s' "$PAYLOAD" | python3 "$GUARD"; _r=$?; printf X; exit "$_r" )" || _prc=$?
_pout="${_pout%X}"

# Classified by tier, not by rule: the rule lives in prod_guard.py's reason prose, and parsing it would fork this shim's view of a corpus it does not own. Both json.dumps spacings are matched (_broken emits the compact one).
case "$_pout" in
  '')                                                                _pv=allow; _pr=prod-clean.meta ;;
  *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*)   _pv=deny;  _pr=prod-gated.argv ;;
  *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*)     _pv=ask;   _pr=prod-gated.argv ;;
  # `other` is deliberate: output this shim cannot classify. `prod-unparsed` in the ledger means prod_guard.py changed its output shape.
  *)                                                                 _pv=other; _pr=prod-unparsed.meta ;;
esac
_log "$_pv" "$_pr"

printf '%s' "$_pout"
exit "$_prc"
