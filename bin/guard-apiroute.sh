#!/usr/bin/env sh
[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0
# guard-apiroute (harbor#545) — PostToolUse(Bash|Write|Edit|MultiEdit) and
# SessionStart. Claude Code's own API route is not a setting anything a session
# runs may change.
#
# WHAT HAPPENED. 2026-09-17 20:58Z: a subagent probing `--help` across a
# scaffolded project ran its `setup_models.sh`, which ignores its arguments and
# installed claude-code-router 3.1.0. The router's first run backed up
# ~/.claude/settings.json and wrote `apiKeyHelper` and
# `env.ANTHROPIC_BASE_URL=http://127.0.0.1:3456` (plus two sibling URLs) into it.
# Claude Code reloads settings live, so from 20:59:00Z every request from the
# session, its four subagents and the permission classifier went to a port
# nothing listened on — "Connection refused" — until a person restored the file
# by hand the next morning.
#
# WHY A COMMAND GUARD IS NOT ENOUGH. The command the floor saw was
# `python3 help_probe.py <dir>`. Nothing in its text names the write, so
# guard-bash (which refuses the router and its installer BY NAME) cannot be the
# whole answer. This hook reads the RESULT instead of the command.
#
# WHAT IT DOES. After every shell or file tool call, and at session start, it
# reads the settings files Claude Code loads — the config dir's settings.json and
# settings.local.json, and the project's .claude/ pair — for the keys that decide
# WHERE requests go and HOW they authenticate, and holds each file against the
# copy of it this guard last ACCEPTED:
#   - FIRST SIGHT. Whatever the file already says becomes its accepted copy,
#     route keys included, and is never rewritten: it predates anything this
#     guard watched, and deleting an operator's existing credential or proxy on
#     the first run would itself lock Claude Code out (Codex, harbor PR #547). A
#     route key found then is reported once, so a stale reroute is not kept in
#     silence.
#   - ACCEPTED BEFORE. A route key ADDED since, or pointed at a new value, is put
#     back by restoring the accepted copy byte for byte. A key the file dropped
#     is not a reroute, and any other change is accepted.
#   - SEEN ABSENT, NOW PRESENT. The file arrived under watch, so every route key
#     in it is new: those keys are deleted with jq and the rest is kept.
# The rerouted copy is kept beside the file as evidence, and the tool call is
# answered with a block reason naming the keys, so the agent that ran the
# command learns what it did before its next request leaves the machine.
#
# THE ACCEPTED COPIES ARE A TRUST ANCHOR: a session that could write one could
# bless its own reroute, and one that could DELETE them could make its reroute a
# first sight. So they live in $CLAUDE_CONFIG_DIR/.helm-apiroute/, not in cache/
# (which is anyone's to wipe: 'rm -rf ~/.claude/cache' in the same call as a
# reroute had it baselined, measured), and guard-selfedit and guard-bash protect
# that directory like the allow list below.
#
# NOT A BAN ON GATEWAYS. An operator who wants one lists the key names, one per
# line, in $CLAUDE_CONFIG_DIR/.helm-apiroute-allow. guard-selfedit and
# guard-bash protect that file, so a session cannot allow itself.
#
# KEYS, NEVER VALUES, in every message: an ANTHROPIC_AUTH_TOKEN value is a
# credential. Values are compared inside jq and never printed. Registered in
# CHECKS.md as `api-route`; every repair is stamped `[check:api-route]` in
# $CLAUDE_CONFIG_DIR/cache/checks.log.
#
# FAILS OPEN. An error in this hook must never stop a session doing ordinary
# work, so every path exits 0; only the message on stdout carries a verdict.
# `-u` without `-e`, for that reason: a failing command inside a repair must
# fall through to the next step and the report, never abort the hook.
set -u
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/guard-lib.sh"

floor_read_stdin
# ONE jq for both payload fields. This runs after every shell and file call and
# a spawn costs ~4 ms on this box (measured), so the common path is held to a
# handful of them: the first draft spawned ~30 and cost 120 ms a call.
_meta="$(printf '%s' "${FLOOR_IN:-}" | "$FLOOR_JQ" -r '[(.hook_event_name // ""), (.cwd // "")] | @tsv' 2>/dev/null)"
EVENT="${_meta%%	*}"
CWD="${_meta#*	}"
[ "$CWD" = "$_meta" ] && CWD=""
# The project whose .claude/ settings Claude Code loaded is the one it was
# launched in, which the harness names in CLAUDE_PROJECT_DIR. The payload cwd
# follows a `cd` inside the Bash tool, so it is only the fallback — the order
# floor_in_repo uses.
PROJ="${CLAUDE_PROJECT_DIR:-$CWD}"
CFG="$(floor_config_dir)"
SNAPDIR="$CFG/.helm-apiroute"
ALLOW="$CFG/.helm-apiroute-allow"

# The keys that pick Claude Code's endpoint, provider, proxy or credential. Env
# keys are read under `.env`; `apiKeyHelper` is top-level.
ROUTE_KEYS='ANTHROPIC_BASE_URL|ANTHROPIC_API_BASE_URL|CLAUDE_AGENT_API_BASE_URL|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_VERTEX_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|HTTPS_PROXY|HTTP_PROXY|ALL_PROXY|https_proxy|http_proxy|all_proxy|apiKeyHelper'

have_jq() { command -v "$FLOOR_JQ" >/dev/null 2>&1; }

# routes_only — key names on stdin, kept only if they are route keys and not on
# the operator's allow list; printed space-separated.
routes_only() {
  "$FLOOR_GREP" -x -E "$ROUTE_KEYS" \
    | if [ -f "$ALLOW" ]; then "$FLOOR_GREP" -v -x -F -f "$ALLOW"; else cat; fi \
    | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

# key_names <file> — the route-key names the TEXT of <file> sets. It stands in
# for jq when jq is missing or cannot parse a file caught half-written, so a
# write is never missed for want of a parser.
key_names() {
  "$FLOOR_GREP" -o -E "\"($ROUTE_KEYS)\"[[:space:]]*:" "$1" 2>/dev/null | sed -E 's/^"([^"]*)".*/\1/'
}

# route_keys <file> — every route key <file> sets.
route_keys() {
  if have_jq && _rk="$("$FLOOR_JQ" -r '((.env // {}) | keys[]?), (if has("apiKeyHelper") then "apiKeyHelper" else empty end)' "$1" 2>/dev/null)"; then
    :
  else
    _rk="$(key_names "$1")"
  fi
  printf '%s\n' "$_rk" | routes_only
}

# added_keys <file> <accepted> — the route keys <file> sets that <accepted> does
# not set to the same value: added, or pointed somewhere new. Without a parse of
# both it compares names, so a new key is still caught and a changed value is not.
added_keys() {
  if have_jq && _rk="$("$FLOOR_JQ" -r --slurpfile acc "$2" '
      def routes: [((.env // {}) | if type == "object" then to_entries[] | {k: .key, v: .value} else empty end),
                   (if type == "object" and has("apiKeyHelper") then {k: "apiKeyHelper", v: .apiKeyHelper} else empty end)];
      ($acc[0] | routes) as $a | routes[] | select(. as $e | any($a[]; . == $e) | not) | .k' "$1" 2>/dev/null)"; then
    :
  else
    _an=" $(key_names "$2" | tr '\n' ' ') "
    _rk=""
    for _k in $(key_names "$1"); do
      case "$_an" in *" $_k "*) ;; *) _rk="$_rk
$_k" ;; esac
    done
  fi
  printf '%s\n' "$_rk" | routes_only
}

# in_step <file> <copy> — the two mtimes are equal. find, not test's -nt/-ot,
# which POSIX lacked before 2024 (harbor#811): an operand prints only when it is
# no newer than either, so both print only when equal. -L follows a symlink.
in_step() {
  _st="$(find -L "$1" "$2" ! -newer "$1" ! -newer "$2" 2>/dev/null)"
  [ "$_st" = "$1
$2" ]
}

# accept <file> <copy> — make <file>'s bytes the accepted state. `cp -p` carries
# the mtime across, so "in step" is an mtime test (one find), and a copy is made
# only when the file really changed. Once a copy exists, a file jq cannot parse
# never replaces it: a half-written copy restored later would break the very
# settings it was kept to repair.
accept() {
  if [ ! -f "$2" ] || ! in_step "$1" "$2"; then
    if [ -f "$2" ] && have_jq && ! "$FLOOR_JQ" empty "$1" >/dev/null 2>&1; then return 0; fi
    [ -d "${2%/*}" ] || mkdir -p "${2%/*}" 2>/dev/null || return 0
    cp -p "$1" "$2.$$" 2>/dev/null && mv "$2.$$" "$2" 2>/dev/null
    rm -f "$2.$$" 2>/dev/null
  fi
  return 0
}

# mark <path> — record that a settings file was ABSENT when this guard looked,
# so one that appears there later is known to have arrived under watch. `: >` is
# a shell builtin: once its directory exists, a marker costs no spawn.
mark() {
  [ -d "${1%/*}" ] || mkdir -p "${1%/*}" 2>/dev/null
  : >"$1" 2>/dev/null
  return 0
}

# stamp <file> <keys> <action> — the registry line every verdict carries.
stamp() {
  mkdir -p "$CFG/cache" 2>/dev/null \
    && printf '[check:api-route] %s %s keys=%s action=%s\n' "$ts" "$1" "$2" "$3" >>"$CFG/cache/checks.log" 2>/dev/null
  return 0
}

json_str() {
  if have_jq; then "$FLOOR_JQ" -Rs . 2>/dev/null
  else printf '"%s"' "$(sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')"
  fi
}

# The project directory is often $HOME, where `$PROJ/.claude` IS the config dir:
# one file, one check.
set -- "$CFG/settings.json" "$CFG/settings.local.json"
if [ -n "$PROJ" ] && [ "$PROJ/.claude" != "$CFG" ]; then
  set -- "$@" "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"
fi
_have=""
for f in "$@"; do
  s="$SNAPDIR/${f#/}"
  if [ -f "$f" ]; then
    _have="$_have$f
"
  elif [ -f "$s.accepted" ]; then
    # Gone since it was accepted: absence is the accepted state now.
    rm -f "$s.accepted" 2>/dev/null
    mark "$s.absent"
  elif [ ! -f "$s.absent" ]; then
    mark "$s.absent"
  fi
done
[ -n "$_have" ] || exit 0
set --
while IFS= read -r f; do [ -n "$f" ] && set -- "$@" "$f"; done <<EOF
$_have
EOF
# FAST PATH: the route keys are JSON keys, so a file whose text never names one
# cannot set one. One grep across every file decides which need the full read.
MENTION="
$("$FLOOR_GREP" -l -E "\"($ROUTE_KEYS)\"" "$@" 2>/dev/null)
"

MSGS=""
NOTES=""
for f in "$@"; do
  s="$SNAPDIR/${f#/}"
  case "$MENTION" in
    *"
$f
"*) named=1 ;;
    *) named="" ;;
  esac
  if [ -f "$s.accepted" ]; then
    # A file that names no route key cannot have added one, and one
    # byte-identical to its accepted copy has changed nothing.
    if [ -z "$named" ] || cmp -s "$f" "$s.accepted"; then accept "$f" "$s.accepted"; continue; fi
    bad="$(added_keys "$f" "$s.accepted")"
    [ -n "$bad" ] || { accept "$f" "$s.accepted"; continue; }
  elif [ -f "$s.absent" ]; then
    bad=""
    [ -n "$named" ] && bad="$(route_keys "$f")"
    [ -n "$bad" ] || { accept "$f" "$s.accepted"; rm -f "$s.absent" 2>/dev/null; continue; }
  else
    # FIRST SIGHT: the baseline, never a repair (see the header).
    accept "$f" "$s.accepted"
    pre=""
    [ -n "$named" ] && pre="$(route_keys "$f")"
    if [ -n "$pre" ]; then
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      NOTES="$NOTES $f already set $pre when this guard first read it, so they are its baseline and only a later change to them is put back."
      stamp "$f" "$pre" "kept as the baseline at first sight"
    fi
    continue
  fi
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  ev="$f.apiroute-$ts"
  cp -p "$f" "$ev" 2>/dev/null || ev="(not saved)"
  how="NOT REPAIRED: the repair failed"
  if [ -f "$s.accepted" ]; then
    if cp "$s.accepted" "$f.apiroute.$$" 2>/dev/null && mv "$f.apiroute.$$" "$f" 2>/dev/null; then
      how="restored the last accepted copy"
    fi
    left="$(added_keys "$f" "$s.accepted")"
  else
    re="^($(printf '%s' "$bad" | tr ' ' '|'))\$"
    if ! have_jq; then
      how="NOT REPAIRED: the file arrived with no accepted copy to restore and there is no jq to delete the keys"
    elif "$FLOOR_JQ" --arg re "$re" 'with_entries(select(.key | test($re) | not))
           | if (.env | type) == "object" then .env |= with_entries(select(.key | test($re) | not)) else . end' \
           "$f" >"$f.apiroute.$$" 2>/dev/null \
      && [ -s "$f.apiroute.$$" ] && mv "$f.apiroute.$$" "$f" 2>/dev/null; then
      how="deleted those keys and kept everything else"
    fi
    left="$(route_keys "$f")"
    if [ -z "$left" ]; then accept "$f" "$s.accepted"; rm -f "$s.absent" 2>/dev/null; fi
  fi
  rm -f "$f.apiroute.$$" 2>/dev/null
  [ -n "$left" ] && how="NOT REPAIRED: it still sets $left"
  MSGS="$MSGS $f set $bad; $how. The rerouted copy is $ev."
  stamp "$f" "$bad" "$how"
done

[ -n "$MSGS$NOTES" ] || exit 0
TEXT=""
[ -n "$MSGS" ] && TEXT="HELM FLOOR [api-route]: Claude Code's API route was changed —$MSGS Those keys send every request from every session on this box somewhere else; the last time, it was a port nothing listened on and every session failed with 'Connection refused'. Do not run that command again. A gateway the operator really wants is allowed by listing its keys in $ALLOW."
[ -n "$NOTES" ] && TEXT="${TEXT:+$TEXT }HELM FLOOR [api-route]: first read of a settings file that already routes Claude Code —$NOTES If the operator did not set them, they should be removed by hand; a gateway that is wanted can be made explicit in $ALLOW."
printf '%s\n' "$TEXT" >&2
# The decision log (harbor#957 item 4): it repairs rather than refuses, so a record is advise, never deny.
[ -z "$MSGS" ] || floor_log_decision apiroute advise route-repaired.meta
[ -z "$NOTES" ] || floor_log_decision apiroute advise route-baseline.meta
if [ "$EVENT" = "SessionStart" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(printf '%s' "$TEXT" | json_str)"
elif [ -n "$MSGS" ]; then
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$TEXT" | json_str)"
fi
exit 0
