#!/usr/bin/env sh
# eval-git-verbs-probe (harbor#1291) — does every row of contracts/verbs/git.md behave as listed in a fresh session,
# decided offline from the two things that decide it: the permission rules and the PreToolUse hooks.
#
#   sh bin/eval-git-verbs-probe.sh [--register FILE] [--derived] [--live] [--settings FILE]...
#
# Rules come from --settings files, --live (the box's user and managed settings), and --derived (what
# bin/admission-deny.sh would write from the register: the default when no source is named). Each row
# becomes one concrete command, run through the Bash hooks admission-install.sh wires, exactly as the harness runs
# them (/bin/sh <hook>, JSON on stdin), then matched against deny, ask and allow (deny outranks ask outranks allow).
# A row with perm `allow` must come out free, `ask` an ask, `deny` a deny, `builtin` or `classifier` no rule; a
# floor `block:<rule>` must be refused by that rule, an `ask:` by a destroy ask. Exit 1: some row disagrees.
#
# NOT DECIDABLE HERE: `builtin` rows are free because Claude Code itself recognises the read-only form, which no
# settings file records. They pass as free-builtin when no rule or hook objects; only a `claude -p` session can
# confirm the rest (steps: the lane's operator-steps file). Default permission mode only: auto mode adds a classifier.
set -u
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH= cd -- "$DIR/.." && pwd)"
TAB="$(printf '\t')"
. "$DIR/library-log.sh"
. "$DIR/deploy-install-lib.sh"
log_init eval-git-verbs-probe

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }
die() { # <message> [fix]
  log_fail "$1"; log_fix "${2:-sh bin/eval-git-verbs-probe.sh --help}"; log_end >/dev/null; exit 2
}

REG="$ROOT/contracts/verbs/git.md"; DERIVED=0; LIVE=0; SETTINGS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --register) REG="${2:-}"; shift 2 ;;
    --derived) DERIVED=1; shift ;;
    --live) LIVE=1; shift ;;
    --settings) [ -f "${2:-}" ] || die "--settings wants a file: ${2:-}"; SETTINGS="$SETTINGS
$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -f "$REG" ] || die "no register at $REG"
command -v jq >/dev/null 2>&1 || die "jq is needed"
[ -n "$SETTINGS" ] || [ "$LIVE" = 1 ] || DERIVED=1

W="$(mktemp -d "${TMPDIR:-/tmp}/eval-git-verbs-probe.XXXXXX")" || die "no temp dir"
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
trap 'exit 130' INT TERM HUP
# The hooks log under HOME and the config dir: keep the real ones out of the probe.
mkdir -p "$W/home" "$W/cfg" "$W/cwd"
_realhome="$HOME"
export HOME="$W/home" CLAUDE_CONFIG_DIR="$W/cfg"
unset HARBOR_ADMISSION_DISABLE HELM_DISABLE_FLOOR

# --- the rules --------------------------------------------------------------------------------------------------
# shellcheck disable=SC2034 # IL_ENV, IL_DIR and IL_DIR_SET are inputs il_target reads
if [ "$DERIVED" = 1 ]; then
  mkdir -p "$W/derived"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$W/derived/settings.json"
  # il_target refuses a --dir that is physically the live config dir; il_run is the install standard's executed spelling.
  IL_ENV=""; IL_DIR="$W/derived"; IL_DIR_SET=1; il_target
  ( CLAUDE_CONFIG_DIR="$W/derived"; export CLAUDE_CONFIG_DIR; il_run sh "$DIR/admission-deny.sh" --apply ) > "$W/derived/log" 2>&1 \
    || die "deriving the rules failed: $(head -c 300 "$W/derived/log")"
  SETTINGS="$SETTINGS
$W/derived/settings.json"
fi
if [ "$LIVE" = 1 ]; then
  for _f in "${CLAUDE_CONFIG_DIR_LIVE:-$_realhome/.claude}/settings.json" "/Library/Application Support/ClaudeCode/managed-settings.json"; do
    [ -f "$_f" ] && SETTINGS="$SETTINGS
$_f"
  done
fi
: > "$W/rules"
printf '%s\n' "$SETTINGS" | while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  jq -e . "$_f" >/dev/null 2>&1 || die "not JSON: $_f"
  jq -r '(.permissions // {}) as $p | ["deny","ask","allow"][] as $k | ($p[$k] // [])[]
         | select(type == "string" and (. == "Bash" or (startswith("Bash(") and endswith(")"))))
         | "\($k)\t" + (if . == "Bash" then "*" else .[5:-1] end)' "$_f" >> "$W/rules"
done
[ "$(wc -l < "$W/rules" | tr -d ' ')" -gt 0 ] || die "no Bash permission rules in: $(printf '%s' "$SETTINGS" | tr '\n' ' ')"

# _glob <rule> <command>: 0 iff a permission rule matches it. `*` is any text; a trailing ` *` also matches the
# bare command; the legacy `cmd:*` is a prefix.
_glob() {
  case "$1" in *:'*') set -- "${1%:\*} *" "$2" ;; esac
  # shellcheck disable=SC2254
  case "$2" in $1) return 0 ;; esac
  case "$1" in *' *') case "$2" in ${1%' *'}) return 0 ;; esac ;; esac
  return 1
}
# _rules <command> -> deny | ask | allow | none
_rules() {
  for _k in deny ask allow; do
    while IFS="$TAB" read -r _rk _rp; do
      [ "$_rk" = "$_k" ] || continue
      _glob "$_rp" "$1" && { printf '%s' "$_k"; return 0; }
    done < "$W/rules"
  done
  printf none
}

# --- one concrete command per row ---------------------------------------------------------------------------------
_inst() { # <spelling> -> a command that matches it; nothing (rc 1) when the spelling needs a hand-made one
  case "$1" in
    'git push --force*main*') echo 'git push --force origin main' ;;
    'git push -f*main*') echo 'git push -f origin main' ;;
    'git push --force*master*') echo 'git push --force origin master' ;;
    'git push -f*master*') echo 'git push -f origin master' ;;
    'git clean -f*') echo 'git clean -fd' ;;
    'git fetch --u*') echo 'git fetch --upload-pack=sh' ;;
    'git fetch * --u*') echo 'git fetch origin --upload-pack=sh' ;;
    'git fetch * +*') echo 'git fetch origin +main:main' ;;
    'git switch * --di*') echo 'git switch x --discard-changes' ;;
    'git switch * --force*') echo 'git switch x --force' ;;
    'git switch * -f*') echo 'git switch x -f' ;;
    'git worktree add -B *') echo 'git worktree add -B main ../x' ;;
    'git worktree add * -B *') echo 'git worktree add ../x -B main' ;;
    *)
      _c="$(printf '%s' "$1" | sed -e 's|<dir>|/tmp/x|g' -e 's|<branch>|feat/x|g' -e 's|<key>|user.name|g' -e 's|<value>|x|g' \
        -e 's|<cmd>|sh|g' -e 's|<file>|out.txt|g' -e 's|<read>|log|g' -e 's|<harbor>|/opt/harbor|g' -e 's|<path>|../x|g' \
        -e "s|<floor-surface>|$W/cfg/settings.json|g" -e 's|<x>|x|g' | awk '{ for (i = 1; i <= NF; i++) if ($i == "*") $i = "README.md"; print }')"
      case "$_c" in *'*'*|*'<'*|*'>'*) return 1 ;; esac
      printf '%s\n' "$_c" ;;
  esac
}

# --- the hooks the harness runs on a Bash call, read from the wiring table, not copied --------------------------------
awk '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit }
     f && /^PreToolUse;/ { n = split($0, a, ";"); m = split(a[2], t, "|"); for (i = 1; i <= m; i++) if (t[i] == "Bash") print a[3] }' \
  "$DIR/admission-install.sh" > "$W/hooks.all"
# govern-hook --box asks GitHub about merges: no git shape reaches it, and a probe must not need the network.
grep -v '^govern-hook' "$W/hooks.all" > "$W/hooks" || :
[ -s "$W/hooks" ] || die "no Bash PreToolUse hooks found in the hook wiring table"

# _hooks <command> -> pass | ask | deny | block:<rule>   (the first hook that objects)
_hooks() {
  jq -n --arg c "$1" --arg d "$W/cwd" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' > "$W/payload"
  _n=0
  while IFS= read -r _h; do
    _n=$((_n + 1))
    # shellcheck disable=SC2086 # the wiring row is an argv: a bare name is a file in bin/
    ( set -- $_h; _a=""; for _t in "$@"; do case "$_t" in -*) _a="$_a $_t" ;; *) _a="$_a $DIR/$_t" ;; esac; done
      # shellcheck disable=SC2086
      /bin/sh $_a < "$W/payload" > "$W/h$_n.out" 2> "$W/h$_n.err"; echo $? > "$W/h$_n.rc" ) &
  done < "$W/hooks"
  wait
  _i=1
  while [ "$_i" -le "$_n" ]; do
    if [ "$(cat "$W/h$_i.rc")" = 2 ]; then
      _id="$(sed -n 's/.*HELM FLOOR \[[^]:]*:\{0,1\}\([^]]*\)\].*/\1/p' "$W/h$_i.err" | head -n 1)"
      printf 'block:%s' "$_id"; return 0
    fi
    _d="$(jq -r '.hookSpecificOutput.permissionDecision // empty' "$W/h$_i.out" 2>/dev/null)"
    case "$_d" in ask|deny) printf '%s' "$_d"; return 0 ;; esac
    _i=$((_i + 1))
  done
  printf pass
}

# --- the register -----------------------------------------------------------------------------------------------------
awk -F'|' '/^\| `/ { for (i = 2; i <= 5; i++) { v = $i; gsub(/^[ \t`]+|[ \t`]+$/, "", v); printf "%s%s", v, (i < 5 ? "\t" : "\n") } }' "$REG" > "$W/rows"
[ -s "$W/rows" ] || die "the register has no rows: $REG"

_fb=0
log_head "rows"
while IFS="$TAB" read -r _sp _class _perm _floor; do
  if ! _cmd="$(_inst "$_sp")"; then
    log_fail "$_sp: no concrete command for this spelling"
    log_fix "add the spelling to _inst in bin/eval-git-verbs-probe.sh"; continue
  fi
  _r="$(_rules "$_cmd")"; _h="$(_hooks "$_cmd")"
  case "$_perm" in
    allow) _wr=allow ;; ask) _wr=ask ;; deny) _wr=deny ;; builtin|classifier) _wr=none ;;
    *) log_fail "$_sp: perm is $_perm"; log_fix "use builtin, allow, ask, deny or classifier in $REG"; continue ;;
  esac
  case "$_floor" in
    block:*) _wh="block:${_floor#block:}" ;;
    ask:*) _wh="ask" ;;
    *) _wh=pass ;;
  esac
  _ok=1; _why=""
  [ "$_r" = "$_wr" ] || { _ok=0; _why="rules say $_r, register says $_perm"; }
  case "$_wh" in
    ask) case "$_h" in ask|deny) ;; *) _ok=0; _why="$_why; hooks say $_h, register says $_floor" ;; esac ;;
    *) [ "$_h" = "$_wh" ] || { _ok=0; _why="$_why; hooks say $_h, register says ${_floor}"; } ;;
  esac
  case "$_h:$_r:$_perm" in
    pass:allow:*) _out=free ;; pass:none:builtin) _out=free-builtin ;; pass:none:*) _out=prompt ;;
    pass:*) _out="rule-$_r" ;; *) _out="refused-$_h" ;;
  esac
  if [ "$_ok" = 1 ]; then
    [ "$_out" = free-builtin ] && _fb=$((_fb + 1))
    log_ok "$(printf '%-48s %-13s %s' "$_sp" "$_out" "$_cmd")"
  else
    log_fail "$_sp: ${_why#; }  [$_cmd]"
    log_fix "make the row and the rules agree: edit $REG, then sh bin/admission-deny.sh --apply --live"
  fi
done < "$W/rows"
log_note "$_fb free row(s) rest on Claude Code's built-in read-only set, which no offline probe can confirm"
log_end
