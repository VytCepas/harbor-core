#!/usr/bin/env sh
# OBSERVE-1 (harbor#41) — the SessionStart half of the guard-decision ledger.
# This script has no kill-switch line, deliberately: guards are spawned through admission-hook.sh, which returns at line 2 under an override, so only a hook that runs regardless of the switch can record it. bin/decider-set.sh lists it as exempt (lint F1).
# SessionStart-only, never blocks. It is the ONLY component permitted to create anything (library-admission.sh property 3): the directories, sink, host token and salt are made here.
# Removed notes: docs/explanation/code-cases/bin-admission-observe.md
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) exit 0 ;; esac

# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac

# Sourced here because the host partition needs floor_host_token. Absent library means exit 0: B6 already reports it, and a ledger dir for a floor that cannot record would read as "observed and clean".
[ -f "$DIR/library-admission.sh" ] || exit 0
. "$DIR/library-admission.sh" 2>/dev/null || exit 0

# A SessionStart hook must never break a session: everything below is best-effort and every path exits 0.
ROTATE_BYTES=5242880          # ~45k records at the measured ~110 bytes each

# obs_safe_write <path> <content> - the ONLY way this script creates a file (#47 findings 1, 2). A bare `>` blocks forever on a FIFO (the host dir stays writable) and overwrites a symlink's target;
# write a temp file in a directory we control, then mv.
obs_safe_write() { # <path> <content>
  _p="$1"; _c="$2"
  if [ -e "$_p" ] && { [ ! -f "$_p" ] || [ -L "$_p" ]; }; then return 0; fi
  _t="$_p.tmp.$$"
  # The temp path needs the same gate: `[ -e ]` is false for a symlink to a missing target, and `>` would create through it.
  if [ -e "$_t" ] || [ -L "$_t" ]; then rm -f "$_t" 2>/dev/null || return 0; fi
  [ -e "$_t" ] || [ -L "$_t" ] && return 0
  ( umask 077; printf '%s\n' "$_c" > "$_t" ) 2>/dev/null || { rm -f "$_t" 2>/dev/null; return 0; }
  { [ -f "$_t" ] && [ ! -L "$_t" ]; } || { rm -f "$_t" 2>/dev/null; return 0; }
  chmod 0600 "$_t" 2>/dev/null || :
  mv -f "$_t" "$_p" 2>/dev/null || rm -f "$_t" 2>/dev/null
  return 0
}

# ── the host partition ── the same floor_host_token as worklog-push and memory-harvest, so the ledgers partition identically.
HOST="$(floor_host_token)"

OBS="$CFG/MEMORY/OBSERVABILITY"
ODIR="$OBS/$HOST"
SINK="$ODIR/guard-decisions.jsonl"

# The host dir is held at 0500, so each step that creates something opens the mode and closes it again. Failing here means blind, never a changed verdict.
[ -d "$OBS" ] || mkdir -p "$OBS" 2>/dev/null || exit 0
[ -d "$ODIR" ] || mkdir -p "$ODIR" 2>/dev/null || exit 0
# The 0500 restore is a TRAP, and the signal trap must exit: otherwise the harness escalates to SIGKILL and the dir stays writable.
trap 'chmod 0500 "$ODIR" 2>/dev/null || :' EXIT
trap 'chmod 0500 "$ODIR" 2>/dev/null || :; exit 143' INT TERM HUP
chmod 0700 "$ODIR" 2>/dev/null || exit 0

# ── rotation: one live generation, closed ones archived ── by size, not date: the hot path cannot create tomorrow's file, and the clock lives in each record's ts.
# obs_prepare_sink is the one rotate/type-check/create spelling for both ledgers (harbor#465).
# obs_archive_generation <path> - moves a closed generation to archive/<base>.<UTC stamp>.jsonl, 0400, never replacing one; returns 1 and moves nothing on failure.
obs_archive_generation() { # <path>
  _ag="$1"
  { [ -f "$_ag" ] && [ ! -L "$_ag" ]; } || return 1
  _ad="${_ag%/*}/archive"
  if [ -e "$_ad" ] && { [ ! -d "$_ad" ] || [ -L "$_ad" ]; }; then return 1; fi
  [ -d "$_ad" ] || mkdir -m 0700 "$_ad" 2>/dev/null || return 1
  _ab="${_ag##*/}"; _ab="${_ab%.1}"; _ab="${_ab%.jsonl}"
  _as="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)" || return 1
  case "$_as" in ''|*[!0-9TZ]*) return 1 ;; esac
  _at="$_ad/$_ab.$_as.jsonl"; _an=0
  while [ -e "$_at" ] || [ -L "$_at" ]; do
    _an=$((_an + 1)); [ "$_an" -le 9 ] || return 1
    _at="$_ad/$_ab.$_as.$_an.jsonl"
  done
  mv -n "$_ag" "$_at" 2>/dev/null || return 1
  [ ! -e "$_ag" ] || return 1
  chmod 0400 "$_at" 2>/dev/null || :
  return 0
}

obs_prepare_sink() { # <path>
  _sk="$1"
  if [ -f "$_sk" ] && [ ! -L "$_sk" ]; then
    _sz="$(wc -c < "$_sk" 2>/dev/null || echo 0)"
    case "$_sz" in ''|*[!0-9\ ]*) _sz=0 ;; esac
    if [ "$(( _sz + 0 ))" -gt "$ROTATE_BYTES" ]; then
      # The old .1 is archived before it is replaced, never overwritten. Archive refused means no rotation; archived names miss every reader's `<sink>*` glob.
      if [ ! -e "$_sk.1" ] || obs_archive_generation "$_sk.1"; then
        mv -f "$_sk" "$_sk.1" 2>/dev/null || :
      fi
    fi
  fi
  # A pre-existing non-file at the sink path is refused, not reused: the hot path would refuse it too and the ledger would stay silently empty.
  if [ -e "$_sk" ] && { [ ! -f "$_sk" ] || [ -L "$_sk" ]; }; then return 1; fi
  [ -f "$_sk" ] || : >> "$_sk" 2>/dev/null || :
  chmod 0600 "$_sk" 2>/dev/null || :
  return 0
}

if ! obs_prepare_sink "$SINK"; then
  chmod 0500 "$ODIR" 2>/dev/null || :
  exit 0
fi

# ── the SECOND ledger: tool outcomes (harbor#465) ── written by failure-observe.sh, created here because the host dir goes back to 0500.
# A refusal here does not exit: the guard ledger is already ready, and exiting would skip the salt and host token below.
obs_prepare_sink "$ODIR/tool-failures.jsonl" || :

# ── the stream root (harbor#1181) ── harbor_emit (audit-stream-lib.sh) writes <host>/streams/<stream>/<day>/ and the host dir is 0500, so the root is made here; a non-directory or symlink there is left alone and every emit spills.
if [ ! -e "$ODIR/streams" ] && [ ! -L "$ODIR/streams" ]; then mkdir -m 0700 "$ODIR/streams" 2>/dev/null || :; fi

# ── the per-install salt ── created once, never rotated (rotation would reset every recurrence count); 0600 and outside MEMORY/, which has a git remote. Without it floor_obs_digest yields "-".
SALT="$CFG/.helm-obs-salt"
_need_salt=1
if [ -f "$SALT" ] && [ ! -L "$SALT" ]; then
  _s=""; { IFS= read -r _s < "$SALT"; } 2>/dev/null || :
  case "$_s" in
    *[!0-9abcdef]*|'') ;;
    *) [ "${#_s}" -eq 32 ] && _need_salt=0 ;;
  esac
fi
if [ "$_need_salt" = 1 ]; then
  _new="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
  case "$_new" in
    *[!0-9abcdef]*|'') ;;
    *) [ "${#_new}" -eq 32 ] && obs_safe_write "$SALT" "$_new" ;;
  esac
fi

# ── the host token the hot path reads with a builtin ── floor_host_token costs a fork, so the hot path `read`s this file; rewritten every session because the token CAN move.
# Type-checked like every read of this file: `read` blocks on a FIFO exactly as `>` does.
_cur=""
if [ -f "$CFG/.helm-obs-host" ] && [ ! -L "$CFG/.helm-obs-host" ]; then
  { IFS= read -r _cur < "$CFG/.helm-obs-host"; } 2>/dev/null || :
fi
[ "$_cur" = "$HOST" ] || obs_safe_write "$CFG/.helm-obs-host" "$HOST"

# ── close the directory, THEN record ── load-bearing: floor_log_decision refuses to write unless the dir is non-writable (library-admission.sh property 2), so recording after the chmod also proves the gate is satisfiable.
chmod 0500 "$ODIR" 2>/dev/null || :

# `armed` is the denominator of the override rate; per-rule attribution of an override is deliberately not attempted (the reader labels it file order).
# library-admission.sh was sourced at the top, so floor_log_decision is defined. harbor#309: the payload names the session (key `sk`); never read from a terminal.
[ -t 0 ] || floor_read_stdin || :
# ── a settings `env` block that sets either switch (harbor#954 PR B, from #977) ──
# The write-time guards miss five shapes (docs/explanation/admission-baseline.md residuals), so this reads the settings files. It lives here because this script runs when the switch is set. A report, never a refusal; keys only, never values.
_sw_proj="${CLAUDE_PROJECT_DIR:-}"
[ -n "$_sw_proj" ] || _sw_proj="$(floor_field '.cwd')"
_sw_hits=""
_sw_files="$(floor_switch_settings_files "$_sw_proj")"
while IFS= read -r _sw_f; do
  [ -n "$_sw_f" ] || continue
  _sw_k="$(floor_switch_in_settings "$_sw_f" | tr '\n' ' ' | sed 's/ *$//')"
  [ -n "$_sw_k" ] && _sw_hits="${_sw_hits:+$_sw_hits; }$_sw_f sets $_sw_k"
done <<SWEOF
$_sw_files
SWEOF
if [ -n "$_sw_hits" ]; then
  _sw_msg="HELM FLOOR [switch-in-settings]: a settings env block sets a floor switch, so every hook in a session started here reads it: $_sw_hits. If you did not put it there, remove it; the floor is not enforcing in the sessions it reaches."
  printf '%s\n' "$_sw_msg" >&2
  printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "$_sw_msg" | "$FLOOR_JQ" -Rs . 2>/dev/null)" "$(printf '%s' "$_sw_msg" | "$FLOOR_JQ" -Rs . 2>/dev/null)"
fi

# A shadow session (harbor#482) is its own record, never `armed`, so it cannot inflate the denominator of a rate it does not enforce; the kill-switch wins when both are set.
if [ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ]; then
  floor_log_decision session override floor-disabled.meta || :
elif [ "${HARBOR_ADMISSION_SHADOW:-0}" = "1" ]; then
  floor_log_decision session shadow floor-shadow.meta || :
else
  floor_log_decision session armed floor-armed.meta || :
fi

exit 0
