#!/usr/bin/env sh
# OBSERVE-1 (harbor#41) — the SessionStart half of the guard-decision ledger.
#
# THIS SCRIPT HAS NO KILL-SWITCH LINE, AND THAT IS THE ENTIRE POINT.
# Every guard and admission-hook.sh open with `[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ]
# && exit 0` on line 2, and floor-install.sh wires every PreToolUse guard THROUGH
# admission-hook.sh. So under an override the wrapper returns at line 2 and the guard
# is never spawned: zero processes, zero rule evaluations, nothing anywhere in
# the floor that could record that the operator walked past it. An override is
# the operator saying "this rule is wrong" with their hands instead of their
# mouth — the highest-quality feedback signal in the system — and it was
# structurally unobservable. A hook that runs REGARDLESS of the switch is the
# only place it can be seen.
#
# bin/decider-set.sh lists this file as exempt from the kill-switch line, with that reason, and lint F1
# reads the list. It is SessionStart-only and never reaches a verdict: it cannot block anything.
#
# It is also the ONLY component permitted to create anything. floor_log_decision
# on the hot path creates nothing — see library-admission.sh property 3 — so every
# directory, the sink, the host token and the salt are made here, once, at
# SessionStart, where a fork costs nothing and no verdict is pending.
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${CFG%/}" != "$CFG" ] && [ "$CFG" != "/" ]; do CFG="${CFG%/}"; done
case "$CFG" in /*) ;; *) exit 0 ;; esac

# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac

# Sourced HERE, not at the recording block below, because the host partition needs
# floor_host_token before it can name a directory. library-admission.sh creates nothing at
# source time (its property 3), so moving this up adds no side effect and no fork.
#
# Absent library means exit 0, not a degraded token. Nothing this script creates
# has any value without the library that records into it: the sink, the salt and
# the host token exist only to be written by floor_log_decision. B6 hash-pins
# library-admission.sh, so its absence is already a floor failure that guard-integrity
# reports under its own name — inventing a second, quieter spelling of that
# failure here would create a ledger directory for a floor that cannot record,
# which reads as "observed and clean" instead of "not observed".
[ -f "$DIR/library-admission.sh" ] || exit 0
. "$DIR/library-admission.sh" 2>/dev/null || exit 0

# A SessionStart hook must never be the thing that breaks a session. Everything
# below is best-effort; the script exits 0 on every path, including this one.
ROTATE_BYTES=5242880          # ~45k records at the measured ~110 bytes each

# obs_safe_write <path> <content> — the ONLY way this script creates a file.
#
# REVIEW 2026-07-28 (#47, findings 1 and 2), both REPRODUCED. The two token files
# were written with a bare `> "$F"`, and that is two separate holes:
#
#   FIFO   `mkfifo ~/.claude/.helm-obs-host` makes `>` block in open(2) forever.
#          `2>/dev/null` cannot catch a BLOCK. The write sat between 'chmod 0700'
#          and 'chmod 0500', so when the harness killed the hung hook the host dir
#          was left WRITABLE — and floor_log_decision's `[ ! -w ]` gate then
#          refused on every call, permanently blinding the ledger. floor-install
#          runs this synchronously, so the installer hung too.
#   SYMLINK `ln -s ~/anything ~/.claude/.helm-obs-host` made `>` truncate and
#          overwrite the TARGET at every SessionStart.
#
# library-admission.sh's hot-path READER type-checks these same two files for exactly
# this reason. The writer did not. Write via a temp file inside a directory we
# control, then `mv` — so the final name is never opened through a link or a FIFO.
obs_safe_write() { # <path> <content>
  _p="$1"; _c="$2"
  if [ -e "$_p" ] && { [ ! -f "$_p" ] || [ -L "$_p" ]; }; then return 0; fi
  _t="$_p.tmp.$$"
  # The temp path needs the SAME gate as the final one (pass-2 review): the first
  # cut only moved the unchecked `>` from "$_p" to "$_t", so a planted symlink or
  # FIFO at the temp name reopened both holes one name over. `[ -e ]` alone is not
  # the check — a symlink to a NON-EXISTENT target makes it false, and `>` then
  # creates through the link.
  if [ -e "$_t" ] || [ -L "$_t" ]; then rm -f "$_t" 2>/dev/null || return 0; fi
  [ -e "$_t" ] || [ -L "$_t" ] && return 0
  ( umask 077; printf '%s\n' "$_c" > "$_t" ) 2>/dev/null || { rm -f "$_t" 2>/dev/null; return 0; }
  # And re-check what we actually created before trusting it.
  { [ -f "$_t" ] && [ ! -L "$_t" ]; } || { rm -f "$_t" 2>/dev/null; return 0; }
  chmod 0600 "$_t" 2>/dev/null || :
  mv -f "$_t" "$_p" 2>/dev/null || rm -f "$_t" 2>/dev/null
  return 0
}

# ── the host partition ──────────────────────────────────────────────────────
# THE SAME FUNCTION as hooks/worklog-push/worklog-push.sh and hooks/memory-harvest/memory-harvest.sh call, so the
# ledgers partition identically and a cross-device merge lines up. This used to be
# three copies of one `hostname -s` expression, which stayed byte-identical right
# up until the value itself moved and forked all three ledgers at once — see
# floor_host_token in library-admission.sh for the measurement.
HOST="$(floor_host_token)"

OBS="$CFG/MEMORY/OBSERVABILITY"
ODIR="$OBS/$HOST"
SINK="$ODIR/guard-decisions.jsonl"

# The host dir is held at 0500 for the rest of the session, so every step that
# needs to CREATE something has to open the mode and close it again. Failing
# closed here means failing BLIND — records drop, no verdict is affected.
[ -d "$OBS" ] || mkdir -p "$OBS" 2>/dev/null || exit 0
[ -d "$ODIR" ] || mkdir -p "$ODIR" 2>/dev/null || exit 0
# The 0500 restore is a TRAP, not just a line at the end: a hook killed at its
# timeout (the FIFO case above) otherwise leaves the directory writable, and a
# writable host dir is precisely what reopens the plant this design closes.
# The signal handlers must EXIT (pass-2 review). A trap body without `exit`
# swallows the signal: the script resumes, the harness sees it still alive and
# escalates to SIGKILL — which bypasses traps entirely and leaves the host dir
# writable, i.e. exactly the state this trap exists to prevent.
trap 'chmod 0500 "$ODIR" 2>/dev/null || :' EXIT
trap 'chmod 0500 "$ODIR" 2>/dev/null || :; exit 143' INT TERM HUP
chmod 0700 "$ODIR" 2>/dev/null || exit 0

# ── rotation: one live generation, closed ones archived ─────────────────────
# Bounded by SIZE and not by date. A day-partitioned FILENAME would need the hot
# path to create tomorrow's file at midnight, and the hot path cannot create —
# so a session crossing midnight would go silently blind for its whole remainder.
# The clock lives in each record's `ts` instead, which loses nothing: file order
# is authoritative.
# obs_prepare_sink <path> — rotate, type-check, create, 0600. Returns 1 when the
# path is refused. ONE spelling for BOTH ledgers (harbor#465): this was inline
# and single-use until tool-failures.jsonl arrived, and a second copy of a
# rotation-plus-type-check is exactly the shape that drifts while both halves go
# on reading correctly.
# obs_archive_generation <path> — moves a closed generation to archive/<base>.<UTC stamp>.jsonl, 0400,
# never replacing an existing archive. Returns 1 (and moves nothing) when it cannot.
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
      # The old .1 is archived before it is replaced, never overwritten: one generation lost
      # 2026-08-06..10-04 of the guard ledger. Archive refused -> no rotation (an oversize sink
      # loses nothing). Archived names miss every reader's `<sink>*` glob, so reads stay bounded.
      if [ ! -e "$_sk.1" ] || obs_archive_generation "$_sk.1"; then
        mv -f "$_sk" "$_sk.1" 2>/dev/null || :
      fi
    fi
  fi
  # A pre-existing NON-FILE at the sink path (a FIFO, a directory, a symlink) is
  # refused rather than reused: the hot path type-checks too, but a sink it will
  # always refuse is a ledger that is silently empty forever.
  if [ -e "$_sk" ] && { [ ! -f "$_sk" ] || [ -L "$_sk" ]; }; then return 1; fi
  [ -f "$_sk" ] || : >> "$_sk" 2>/dev/null || :
  chmod 0600 "$_sk" 2>/dev/null || :
  return 0
}

if ! obs_prepare_sink "$SINK"; then
  chmod 0500 "$ODIR" 2>/dev/null || :
  exit 0
fi

# ── the SECOND ledger: tool outcomes, not guard decisions (harbor#465) ──────
# Written by failure-observe.sh at PostToolUseFailure, and created HERE for the
# same reason guard-decisions.jsonl is: the host dir goes back to 0500 below and
# stays there, so nothing on a hook path can create anything afterwards.
#
# A REFUSAL HERE DOES NOT EXIT, and the asymmetry is deliberate. Above, a refused
# guard sink means the thing this whole script exists to prepare cannot be
# prepared. Here, the guard ledger is already ready — exiting would skip the salt
# and the host token below and take out the FIRST recorder to punish a defect in
# the second. One blind ledger beats two.
obs_prepare_sink "$ODIR/tool-failures.jsonl" || :

# ── the stream root (harbor#1181) ───────────────────────────────────────────
# harbor_emit (audit-stream-lib.sh) writes <host>/streams/<stream>/<day>/, and the host dir is 0500 for the rest of the
# session, so the root is made here. A writable subdir cannot swap the guard sinks: those are entries of the host
# dir itself. A non-directory or a symlink at the path is left alone and every emit spills, which says so.
if [ ! -e "$ODIR/streams" ] && [ ! -L "$ODIR/streams" ]; then mkdir -m 0700 "$ODIR/streams" 2>/dev/null || :; fi

# ── the per-install salt ────────────────────────────────────────────────────
# 128 bits, created once and never rotated: rotating it would silently reset
# every recurrence count, which is the one question the digest exists to answer.
# 0600 and outside MEMORY/ — it is a secret, not a record, and MEMORY has a git
# remote. Without it floor_obs_digest yields "-" and blocks are still counted,
# just not correlated.
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

# ── the host token the hot path reads with a builtin ────────────────────────
# Deriving the token costs a fork (see floor_host_token); the hot path reads this
# file with `read` instead. Written every session so a rename of the machine is
# picked up at the next start rather than never.
#
# This comment used to say the value "changes once per boot". It does not — that
# claim is what let the 2026-08-04 fork go unnoticed, because a value believed
# constant is a value nobody checks. The cache is refreshed every SessionStart
# precisely because the token CAN move.
# Type-checked like every other read of this file: `read` from a FIFO blocks
# exactly as `>` does, and a symlink would have us compare against the wrong file.
_cur=""
if [ -f "$CFG/.helm-obs-host" ] && [ ! -L "$CFG/.helm-obs-host" ]; then
  { IFS= read -r _cur < "$CFG/.helm-obs-host"; } 2>/dev/null || :
fi
[ "$_cur" = "$HOST" ] || obs_safe_write "$CFG/.helm-obs-host" "$HOST"

# ── close the directory, THEN record ────────────────────────────────────────
# This ordering is load-bearing. floor_log_decision refuses to write unless the
# directory is non-writable, because that gate — not the file type check — is
# what makes a FIFO plant unwinnable (library-admission.sh property 2). Recording before
# the chmod would work here and teach the wrong invariant; recording after also
# proves the gate is satisfiable, which is the failure mode a mode-drift bug
# would otherwise hide until the ledger was needed.
chmod 0500 "$ODIR" 2>/dev/null || :

# ARMED vs OVERRIDE. `armed` is the DENOMINATOR: without a count of sessions
# where the floor was live, "override rate" is uncomputable and the raw override
# count says nothing. Per-RULE attribution of an override is deliberately NOT
# attempted here — see the reader, which reports "the last blocks preceding an
# override" from file order and labels it exactly that. Claiming to know which
# rule the operator walked past would be an inference dressed as a record.
# library-admission.sh is already sourced at the top — the host partition needed it — and
# its absence exited 0 there, so reaching this point means floor_log_decision is
# defined.
# harbor#309: the SessionStart payload names the session, so these records carry its key `sk`.
# Never from a terminal, where cat would wait for input nobody sends.
[ -t 0 ] || floor_read_stdin || :
# ── a settings `env` block that sets either switch (harbor#954 PR B, from #977) ──
# The write-time guards (killswitch-assign, switch-in-settings) catch the plain spellings of putting a switch in
# a settings file and miss five shapes (docs/explanation/admission-baseline.md residuals). This reads the files instead, so how the switch got
# there no longer matters. It lives HERE because this script runs when the switch is set, which is exactly when
# every guard has stood down. A report, never a refusal: a SessionStart hook cannot block, and the operator may
# have set it on purpose. Keys only, never values.
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

# A SHADOW session (harbor#482) is the third boundary: guards run and record, and
# almost nothing blocks. It is its own record, never `armed`, so a shadow session
# cannot inflate the denominator of a rate it does not enforce. The kill-switch
# wins when both are set, because then no guard runs at all.
if [ "${HARBOR_ADMISSION_DISABLE:-${HELM_DISABLE_FLOOR:-0}}" = "1" ]; then
  floor_log_decision session override floor-disabled.meta || :
elif [ "${HARBOR_ADMISSION_SHADOW:-${HELM_FLOOR_SHADOW:-0}}" = "1" ]; then
  floor_log_decision session shadow floor-shadow.meta || :
else
  floor_log_decision session armed floor-armed.meta || :
fi

exit 0
