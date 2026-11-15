#!/usr/bin/env sh
# B8 (harbor#38) — pin the PERSISTENT INSTRUCTION surfaces of a config dir (the install standard, harbor#765).
#   sh pin-instructions.sh (--live | --dir PATH)           DRY RUN: what --apply would pin, against the pin now
#   sh pin-instructions.sh --apply (--live | --dir PATH)   (re-)pin; the operator's "yes, I did that"
#   sh pin-instructions.sh --check (--live | --dir PATH)   the drift against the pin; exit 1 on drift or no pin
#   sh pin-instructions.sh --print (--live | --dir PATH)   the manifest on stdout, and nothing else
#
# WHY: CLAUDE.md, agents/, skills/, commands/ and output-styles/ load into every FUTURE session, so anything written there is an instruction the model follows tomorrow
# (capability injection on a one-session delay). guard-selfedit protects only the floor's own teeth.
# THE DIVISION: B6 owns settings.json (it projects the whole `.permissions` object plus the top-level key NAMES since harbor#221, when a slash command rewrote
# settings.json through the harness config writer, outside permissions.deny and guard-selfedit); B8 owns the instruction surfaces around it and does not list it.
# The surfaces stay WRITABLE (the owner's stance); this removes the SILENCE: the manifest is compared at every SessionStart and drift is reported by path.
# Re-pinning is DELIBERATE and manual: auto-pinning would report each injection once and then bless it. The live dir needs an explicit --live (il_target, lint D7).
# ORDER (harbor#457): pin AFTER the install, or deploy's own files read as drift. It stays a path, not a `harbor` verb (contracts/cli.md: settings.json mutators
# are never hidden behind a friendly verb); before deploy it is reachable as `sh <checkout>/bin/pin-instructions.sh --apply --live`, which is how deploy spells it.
# NO .harbor-manifest ROWS (install standard §3): the pin is B8's own state, never an installed file.
# Removed notes: docs/explanation/code-cases/bin-pin-instructions.md
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
. "$HERE/library-admission.sh"
log_init pin-instructions

MODE=''
il_opt() {
  # shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
  case "$1" in
    --print|--check) [ -z "$MODE" ] || il_usage_error "$MODE and $1 are two modes; give one"
                     MODE="$1"; IL_TAKE=-1 ;;
    *) IL_TAKE=0 ;;
  esac
}
il_parse "$@"
[ -z "$MODE" ] || [ "$IL_APPLY" -eq 0 ] || il_usage_error "--apply and $MODE are two modes; give one"
il_target
CFG="$IL_TARGET"
if [ ! -d "$CFG" ]; then
  if [ "$IL_LIVE" -eq 1 ]; then
    log_fail "no config dir at $CFG, so there is nothing to pin: the first-run step has not been taken"
    log_fix "$(il_first_run_cmd)"
  else
    log_fail "no such config dir: $CFG"
    log_nofix "the path given to --dir"
  fi
  log_end; exit 1
fi

PIN="$CFG/.helm-instructions.sha256"
MAN="$(floor_instr_manifest "$CFG")"
N="$(printf '%s\n' "$MAN" | wc -l | tr -d ' ')"
[ "$MODE" != --print ] || { printf '%s\n' "$MAN"; exit 0; }

# The drift, one note per changed manifest line (< pinned, > now), capped so a flood stays readable.
_drift_notes() { # no temp file: a dry run and --check write nothing
  _dn="$(printf '%s\n' "$MAN" | floor_instr_diff "$PIN" | head -40 || :)"
  while IFS= read -r _l; do [ -z "$_l" ] || log_note "changed: $_l"; done <<EOF
$_dn
EOF
}

if [ "$IL_APPLY" -eq 0 ]; then
  if [ "$MODE" = --check ]; then log_head "check · $CFG"; else log_head "plan for $CFG (dry run: nothing is written)"; fi
  if [ ! -f "$PIN" ]; then
    if [ "$MODE" = --check ]; then
      log_fail "no pin at $PIN: the instruction surfaces of $CFG are unwatched"
      log_fix "$(il_cmd --apply)"
    else
      log_note "no pin yet: --apply would pin $N instruction-surface entries into $PIN"
      il_next --deploy-does "$(il_cmd --apply)"
    fi
  elif [ -z "$(printf '%s\n' "$MAN" | floor_instr_diff "$PIN")" ]; then
    log_ok "instruction surfaces unchanged since pinning ($N entries)"
  elif [ "$MODE" = --check ]; then
    log_fail "instruction surfaces CHANGED since they were pinned in $PIN"
    log_fix "$(il_cmd --apply)"
    _drift_notes
  else
    log_note "--apply would bless these changes to the instruction surfaces as intended:"
    _drift_notes
    il_next --deploy-does "$(il_cmd --apply)"
  fi
  log_end; exit $?
fi

log_head "apply to $CFG"
il_backup "$PIN" || { log_end; exit 1; }
if printf '%s\n' "$MAN" > "$PIN.tmp.$$" && mv -f "$PIN.tmp.$$" "$PIN"; then
  log_ok "pinned $N instruction-surface entries → $PIN"
else
  rm -f "$PIN.tmp.$$"
  log_fail "could not write $PIN — the previous pin is unchanged"
  log_nofix "the error above"
fi
log_end; exit $?
