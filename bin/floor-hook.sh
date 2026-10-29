#!/usr/bin/env sh
[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0
# B9 (harbor#39) — fail-CLOSED wrapper for the PreToolUse floor guards.
#
# THE PROBLEM IT SOLVES: every dependency failure in the guard chain was silent,
# and the floor still looked installed, pinned and wired:
#
#   jq missing            → guard exits 0   (every field reads empty → allow all)
#   guard file deleted    → sh exits 127    (not a deny)
#   guard not executable  → sh exits 126    (not a deny)
#   guard syntax error    → sh exits 1      (not a deny)
#
# None of those is exit 2, so none of them denies. B6 catches some of it, but
# only at the NEXT SessionStart, and B6 installs last. This wrapper converts the
# whole class from silent-allow into loud-deny.
#
#   sh floor-hook.sh <guard-path>            # fail-CLOSED (PreToolUse)
#   sh floor-hook.sh --advisory <guard-path> # never blocks (PostToolUse)
#
# WHY --advisory EXISTS: exit 2 is meaningless on PostToolUse and SessionStart —
# a PostToolUse hook that exits 2 just discards its annotation, and a SessionStart
# gate blocks via {"continue":false} instead. Fail-closed is only coherent where
# a non-zero exit actually denies, so annotate-web is wrapped in advisory mode
# and guard-integrity is not wrapped at all (it is already fail-closed itself).
#
# THE ESCAPE HATCH IS FIRST, DELIBERATELY: a broken floor must never lock the
# operator out of fixing it. `HELM_DISABLE_FLOOR=1 claude` always opens.
set -u

ADVISORY=0
if [ "${1:-}" = "--advisory" ]; then ADVISORY=1; shift; fi
GUARD="${1:-}"
# harbor#810: this wrapper's own crash (a fork or exec failure) is a deny, never a non-blocking error.
# Safe here only because this file runs without set -e: under -e, bash 3.2 hands an EXIT trap $?=0 for
# a fatal set -u or `.` error and the shell then exits 0 (measured), which is why the guards carry none.
trap '_fr=$?; case $_fr in 0|2) ;; *) [ "$ADVISORY" = 1 ] && exit 0; printf "HELM FLOOR [wrapper]: BLOCKED — floor-hook.sh failed internally (exit %s) before a verdict\n" "$_fr" >&2; exit 2 ;; esac' EXIT

# OBSERVE-1 (harbor#41): the wrapper's OWN denies. These are the class that says
# "the floor is broken", as distinct from "a rule fired" — without them a jq
# outage reads as a quiet drop in block counts and looks like the rules getting
# better. guard-lib is sourced LAZILY, on the deny path only: this wrapper runs
# on every tool call and its entire job is to still work when the guard chain
# does not, so it must not take a 780-line dependency to say yes.
obs() { # <rule>
  # Resolve from the WRAPPER's own directory, never from $GUARD (#47 finding 16).
  # `dirname -- ''` is `.`, so an empty or relative GUARD sourced
  # ./guard-lib.sh from the SESSION's cwd — an attacker-authored file in the repo
  # being worked on, executing inside the hook with stderr swallowed, able to
  # `exit 0` and turn this fail-CLOSED deny into an ALLOW.
  # harbor#810: no dirname fork. A failed or unresolvable $(dirname) resolved this to the cwd too.
  case "$0" in */*) _lib="${0%/*}" ;; *) _lib=. ;; esac
  _lib="$(CDPATH= cd -- "${_lib:-/}" 2>/dev/null && pwd)/guard-lib.sh"
  case "$_lib" in /*) ;; *) return 0 ;; esac
  [ -f "$_lib" ] && [ ! -L "$_lib" ] || return 0
  # shellcheck source=/dev/null
  { . "$_lib"; } 2>/dev/null || return 0
  # THE WRAPPER HAS NO SUBJECT, SO IT MUST NOT INHERIT ONE (harbor#350 follow-up).
  # floor_obs_digest hashes $FLOOR_OBS_SUBJECT, which every GUARD sets from the
  # payload it just extracted. This wrapper extracts nothing: its denials are
  # class-level — the guard file is missing, jq is unavailable, the guard exited
  # without a verdict — and none of them is about a particular command, so `h`
  # belongs at `-`.
  #
  # WHY THIS IS A CONTROL AND NOT TIDINESS. harbor#350 widened the digest from
  # `block` to `block|deny|ask` (guard-lib.sh:584). `wrapper deny` is inside that
  # set and sets no subject, so the value hashed became whatever the ENVIRONMENT
  # held — and a project's settings.json `env` block can set it. That is the
  # exact class already refused for FLOOR_GREP, FLOOR_AWK and FLOOR_INSTR_SURFACES
  # (guard-lib.sh:438): an attacker-chosen constant stamped into the one record
  # class that means "the floor is broken", on the channel FC-2 reads.
  #
  # LATENT WHEN WRITTEN, NOT WHEN EXPLOITED. Every reader of `h` still filters
  # `.d=="block"` (failure-capture.sh:489,582,605,750 and observe-report.sh:141),
  # so nothing consumes it today. Widening those readers is the obvious next step
  # after harbor#350, and the hole opens the moment it happens — so it is closed
  # here rather than left as a note on a ticket.
  #
  # CLEARED, NOT VALIDATED. A charset gate would still let a chosen value through
  # as long as it looked like a command; only refusing to carry one is sound, and
  # an empty subject already returns `-` (guard-lib.sh:626).
  FLOOR_OBS_SUBJECT=''
  floor_log_decision wrapper deny "$1" 2>/dev/null || :
  return 0
}

deny() { # <reason> [rule]
  printf 'HELM FLOOR [wrapper]: BLOCKED — %s\n' "$1" >&2
  printf 'The floor could not evaluate this call, so it denied it (fail-closed).\n' >&2
  printf 'Fix the guard, or open an unguarded session: HELM_DISABLE_FLOOR=1 claude\n' >&2
  obs "${2:-wrapper-unknown.meta}"
  exit 2
}
# The ADVISORY early-exit records too: annotate-web is wired --advisory and can
# never signal anything through an exit code, so a wrapper failure there is
# invisible by construction unless it is written down.
pass_or_deny() { # <reason> [rule]
  if [ "$ADVISORY" = "1" ]; then obs "${2:-wrapper-unknown.meta}"; exit 0; fi
  deny "$1" "${2:-wrapper-unknown.meta}"
}

# WHICH WIRING, not just which class (FC-2 follow-up). The stderr banner above
# already names the guard and the exit code, so the OPERATOR watching a denied
# call can see both — but `obs` writes only the rule token, so the ledger keeps
# the class and drops the identity. A judge reading that record days later gets
# "some guard was missing" and cannot say which of the five wirings it was, which
# is why the one live 2026-08-20 record could only ever be diagnosed by the
# timestamp next to it.
#
# THE ENRICHMENT IS DISCARDED ON ANY DOUBT. floor_log_decision gates the rule
# token to [a-z0-9-] and 40 characters and rewrites ANY violation to
# `unclassified` wholesale (guard-lib.sh:479-480) — so a basename with an
# underscore, or one long enough to overflow, would cost the class name this
# record already carried. Worse-than-today is not a trade a diagnostic aid gets
# to make, so every step below falls back rather than reaching.
#
# A VARIABLE, NOT A COMMAND SUBSTITUTION: `$(...)` is a subshell fork, and this
# wrapper runs on EVERY tool call. Parameter expansion needs no child, and each
# caller invokes this from inside its own failure branch — the allow path must
# not pay for a diagnostic it will never emit.
#
# NOT ON no-jq / no-grep, DELIBERATELY. Those are one systemic outage, not a
# per-guard fault: tagging them by wiring would split a single jq failure into
# five rows of x1 in the report's top-rules census and hide the shape that
# matters. The interpreter canaries stay class-only.
RULE=""
set_rule() { # <bare-rule> [numeric-suffix] -> sets RULE to <token>.meta
  RULE="$1.meta"
  _b="${GUARD##*/}"; _b="${_b%.sh}"
  case "$_b" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) return 0 ;; esac
  # Degrade in the order that keeps the more valuable half: guard+rc, then guard
  # alone, then the bare class. The rc distinguishes 127 (missing) from 126 (not
  # executable), but WHICH guard is what routes the repair.
  if [ -n "${2:-}" ]; then
    case "$2" in *[!0-9]*) ;; *) [ $((${#1} + ${#_b} + ${#2} + 2)) -le 40 ] && RULE="$1-$_b-$2.meta" && return 0 ;; esac
  fi
  [ $((${#1} + ${#_b} + 1)) -le 40 ] && RULE="$1-$_b.meta"
  return 0
}

[ -n "$GUARD" ] && [ -s "$GUARD" ] || { set_rule wrapper-guard-missing; pass_or_deny "guard missing or empty: ${GUARD:-<none>}" "$RULE"; }

# CANARY the interpreters the guards depend on. Without jq every floor_field
# returns empty, so a guard "sees" an empty command and allows everything — the
# most dangerous silent failure in the set.
# ABSOLUTE PATH FIRST, exactly as the grep canary below and as guard-lib's
# FLOOR_JQ now resolves it. A bare `command -v` made this canary fire on a merely
# STRIPPED PATH while /usr/bin/jq was executable and the guards could read it
# perfectly well — a deny with nothing wrong. The two checks must agree, or the
# canary passes while the guards starve, or denies while they are fine.
# THE CANARY HONOURS THE SAME OVERRIDE THE GUARDS WILL USE (review of harbor#341).
# Ignoring FLOOR_JQ meant that on a host with no /usr/bin/jq, a VALID allowlisted
# override the guards could have parsed with was denied here first — the canary
# contradicting the resolver it exists to predict. The allowlist is repeated
# rather than sourced because this wrapper must still answer when guard-lib
# cannot be read; it is duplicated deliberately, and both copies must move
# together.
_fjq="${FLOOR_JQ:-}"
case "$_fjq" in
  /usr/bin/jq|/bin/jq|/usr/local/bin/jq|/opt/homebrew/bin/jq) [ -x "$_fjq" ] || _fjq="" ;;
  *) _fjq="" ;;
esac
{ [ -n "$_fjq" ] || [ -x /usr/bin/jq ] || command -v jq >/dev/null 2>&1; } \
  || pass_or_deny "jq is unavailable — the guards cannot parse the hook payload" wrapper-no-jq.meta
{ [ -x /usr/bin/grep ] || command -v grep >/dev/null 2>&1; } || pass_or_deny "grep is unavailable" wrapper-no-grep.meta

# stdin is consumed once, so read it here and hand it to the guard. harbor#810: /bin/cat first,
# and an unread payload is a deny: read as empty, it let the guard allow anything.
_cat=/bin/cat; [ -x "$_cat" ] || _cat=cat
IN="$("$_cat" 2>/dev/null)" || pass_or_deny "the hook payload could not be read" wrapper-no-input.meta
# Pass 14 E-3: floor_field is empty on bad JSON, so a payload jq rejects (a lone \uD83D escape) made
# every guard allow. Nothing a guard could read is nothing it vetted.
_pj="$_fjq"; [ -n "$_pj" ] || { [ -x /usr/bin/jq ] && _pj=/usr/bin/jq; } || _pj=jq
printf '%s' "$IN" | "$_pj" -e 'type == "object"' >/dev/null 2>&1 \
  || { set_rule wrapper-bad-json; pass_or_deny "the hook payload is not JSON jq can parse, so no guard could read it" "$RULE"; }

# The guard's stderr goes to a mktemp file: a fixed /tmp name is refused inside the confinement (only $TMPDIR is
# writable there, harbor#555), and the guard then never ran. /tmp is the fallback, so a repo's TMPDIR cannot stop it.
# /usr/bin first, as /bin/cat: a stripped PATH must not deny (B9).
_ef="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/floor-hook.XXXXXX" 2>/dev/null || mktemp "${TMPDIR:-/tmp}/floor-hook.XXXXXX" 2>/dev/null \
  || /usr/bin/mktemp /tmp/floor-hook.XXXXXX 2>/dev/null || mktemp /tmp/floor-hook.XXXXXX 2>/dev/null)" \
  || pass_or_deny "no temp file for the guard's stderr could be made" wrapper-no-tmp.meta
OUT="$(printf '%s' "$IN" | sh "$GUARD" 2>"$_ef")"
RC=$?
ERR="$("$_cat" "$_ef" 2>/dev/null)" || ERR="fork: the guard's stderr could not be read"
# A builtin printf (bash 3.2 as sh) whose blocked write a signal interrupts exits 1 with this text
# and no verdict. The guard is pure, so re-running it is safe: at most twice, ONLY for that text on
# a code other than 0/2, and the retry's verdict is the verdict. Any other exit keeps the deny below.
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

# harbor#810: a fork or descriptor that failed inside a rule reads as "no match", so an allow that
# carries one on stderr judged nothing. It is refused like a guard that never reached a verdict.
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
