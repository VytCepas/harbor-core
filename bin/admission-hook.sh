#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# B9 (harbor#39) - fail-CLOSED wrapper for the PreToolUse floor guards: a missing jq/guard or a guard crash never exits 2, so it turns into a deny.
#   sh admission-hook.sh <guard-path>            # fail-CLOSED (PreToolUse)
#   sh admission-hook.sh --advisory <guard-path> # never blocks (PostToolUse; exit 2 means nothing there)
# The escape hatch on line 2 is first on purpose: a broken floor must never lock the operator out of fixing it.
# Removed notes: docs/explanation/code-cases/bin-admission-hook.md
set -u

ADVISORY=0
if [ "${1:-}" = "--advisory" ]; then ADVISORY=1; shift; fi
GUARD="${1:-}"
# harbor#810: this wrapper's own crash is a deny. Safe only because this file has no set -e (under -e bash 3.2 hands an EXIT trap $?=0).
trap '_fr=$?; case $_fr in 0|2) ;; *) [ "$ADVISORY" = 1 ] && exit 0; printf "HELM FLOOR [wrapper]: BLOCKED — admission-hook.sh failed internally (exit %s) before a verdict\n" "$_fr" >&2; exit 2 ;; esac' EXIT

# OBSERVE-1 (harbor#41): the wrapper's OWN denies; guard-lib is sourced lazily, on the deny path only.
obs() { # <rule>
  # Resolve from the wrapper's own directory, never $GUARD: an empty or relative GUARD would source an attacker-authored
  # ./library-admission.sh from the session cwd (#47 finding 16, harbor#810).
  case "$0" in */*) _lib="${0%/*}" ;; *) _lib=. ;; esac
  _lib="$(CDPATH= cd -- "${_lib:-/}" 2>/dev/null && pwd)/library-admission.sh"
  case "$_lib" in /*) ;; *) return 0 ;; esac
  [ -f "$_lib" ] && [ ! -L "$_lib" ] || return 0
  # shellcheck source=/dev/null
  { . "$_lib"; } 2>/dev/null || return 0
  # No subject (harbor#350): cleared so an env-supplied FLOOR_OBS_SUBJECT cannot reach the digest. Cleared, not validated.
  # shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
  FLOOR_OBS_SUBJECT=''
  floor_log_decision wrapper deny "$1" 2>/dev/null || :
  return 0
}

deny() { # <reason> [rule]
  printf 'HELM FLOOR [wrapper]: BLOCKED — %s\n' "$1" >&2
  printf 'The floor could not evaluate this call, so it denied it (fail-closed).\n' >&2
  printf 'Fix the guard, or open an unguarded session: HARBOR_ADMISSION_DISABLE=1 claude\n' >&2
  obs "${2:-wrapper-unknown.meta}"
  exit 2
}
pass_or_deny() { # <reason> [rule]
  if [ "$ADVISORY" = "1" ]; then obs "${2:-wrapper-unknown.meta}"; exit 0; fi
  deny "$1" "${2:-wrapper-unknown.meta}"
}

# Token carries the guard name (+rc) only when it fits floor_log_decision's [a-z0-9-]/40 gate, else the bare class.
# No $(...): a fork on every call.
RULE=""
set_rule() { # <bare-rule> [numeric-suffix] -> sets RULE to <token>.meta
  RULE="$1.meta"
  _b="${GUARD##*/}"; _b="${_b%.sh}"
  case "$_b" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) return 0 ;; esac
  if [ -n "${2:-}" ]; then
    case "$2" in *[!0-9]*) ;; *) [ $((${#1} + ${#_b} + ${#2} + 2)) -le 40 ] && RULE="$1-$_b-$2.meta" && return 0 ;; esac
  fi
  [ $((${#1} + ${#_b} + 1)) -le 40 ] && RULE="$1-$_b.meta"
  return 0
}

[ -n "$GUARD" ] && [ -s "$GUARD" ] || { set_rule wrapper-guard-missing; pass_or_deny "guard missing or empty: ${GUARD:-<none>}" "$RULE"; }

# Canary: without jq every floor_field is empty and a guard allows everything. Mirrors guard-lib's FLOOR_JQ allowlist,
# duplicated on purpose (this must answer when guard-lib is unreadable); keep both copies in step (harbor#341).
_fjq="${FLOOR_JQ:-}"
case "$_fjq" in
  /usr/bin/jq|/bin/jq|/usr/local/bin/jq|/opt/homebrew/bin/jq) [ -x "$_fjq" ] || _fjq="" ;;
  *) _fjq="" ;;
esac
{ [ -n "$_fjq" ] || [ -x /usr/bin/jq ] || command -v jq >/dev/null 2>&1; } \
  || pass_or_deny "jq is unavailable — the guards cannot parse the hook payload" wrapper-no-jq.meta
{ [ -x /usr/bin/grep ] || command -v grep >/dev/null 2>&1; } || pass_or_deny "grep is unavailable" wrapper-no-grep.meta

# stdin is consumed once: read it here and hand it to the guard (harbor#810: an unread payload is a deny).
_cat=/bin/cat; [ -x "$_cat" ] || _cat=cat
IN="$("$_cat" 2>/dev/null)" || pass_or_deny "the hook payload could not be read" wrapper-no-input.meta
# Pass 14 E-3: a payload jq rejects made every guard read empty and allow; nothing readable is nothing vetted.
_pj="$_fjq"; [ -n "$_pj" ] || { [ -x /usr/bin/jq ] && _pj=/usr/bin/jq; } || _pj=jq
printf '%s' "$IN" | "$_pj" -e 'type == "object"' >/dev/null 2>&1 \
  || { set_rule wrapper-bad-json; pass_or_deny "the hook payload is not JSON jq can parse, so no guard could read it" "$RULE"; }

# The guard's stderr goes to a mktemp file (harbor#555: only $TMPDIR is writable in the confinement; /tmp is the fallback).
# /usr/bin first: a stripped PATH must not deny (B9).
_ef="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/floor-hook.XXXXXX" 2>/dev/null || mktemp "${TMPDIR:-/tmp}/floor-hook.XXXXXX" 2>/dev/null \
  || /usr/bin/mktemp /tmp/floor-hook.XXXXXX 2>/dev/null || mktemp /tmp/floor-hook.XXXXXX 2>/dev/null)" \
  || pass_or_deny "no temp file for the guard's stderr could be made" wrapper-no-tmp.meta
OUT="$(printf '%s' "$IN" | sh "$GUARD" 2>"$_ef")"
RC=$?
ERR="$("$_cat" "$_ef" 2>/dev/null)" || ERR="fork: the guard's stderr could not be read"
# A builtin printf (bash 3.2 as sh) interrupted by a signal exits 1 with this text and no verdict. The guard is pure, so
# retry at most twice, only for that text on a code other than 0/2; the retry's verdict is the verdict.
_try=0
while [ "$_try" -lt 2 ]; do
  case "$RC" in 0|2) break ;; esac
  case "$ERR" in *"Interrupted system call"*) ;; *) break ;; esac
  _try=$((_try + 1))
  OUT="$(printf '%s' "$IN" | sh "$GUARD" 2>"$_ef")"
  RC=$?
  ERR="$("$_cat" "$_ef" 2>/dev/null)" || ERR="fork: the guard's stderr could not be read"
done
rm -f "$_ef"

# harbor#810: an allow carrying a fork or descriptor failure on stderr judged nothing, so it is refused like no verdict.
case "$RC:$ERR" in
  0:*"fork: "*|0:*"Cannot fork"*|0:*"Resource temporarily unavailable"*|0:*"Too many open files"*|0:*"Cannot allocate memory"*)
    printf '%s\n' "$ERR" >&2
    set_rule wrapper-resource-fail
    pass_or_deny "$(basename "$GUARD") allowed after a fork or file-descriptor failure, so the allow is unproven" "$RULE" ;;
esac
case "$RC" in
  0) [ -n "$OUT" ] && printf '%s\n' "$OUT"          # allow (pass any stdout through)
     [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
     exit 0 ;;
  2) [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2      # the guard's own deny + reason
     exit 2 ;;
  *) # ANY other code — 1 (syntax error), 126 (not executable), 127 (missing),
     # 137 (killed) — is a guard that did not reach a verdict. Deny.
     [ -n "$ERR" ] && printf '%s\n' "$ERR" >&2
     set_rule wrapper-no-verdict "$RC"
     pass_or_deny "$(basename "$GUARD") exited $RC without a verdict" "$RULE" ;;
esac
