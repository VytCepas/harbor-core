#!/usr/bin/env sh
# SANDBOX (harbor#33) — build a disposable copy of ~/.claude's CONFIG surfaces
# for floor development. Everything in workstream B and K1/K2 runs against this
# via CLAUDE_CONFIG_DIR — never against the live dir.
#
#   sh test-sandbox-make.sh [dir]              # default: ~/.claude-sandbox ; refuses if it exists
#   sh test-sandbox-make.sh [dir] --fresh      # delete + recreate
#   sh test-sandbox-make.sh [dir] --fresh --with-floor   # …and install THIS repo's floor
#   CLAUDE_CONFIG_DIR=<dir> claude        # boot a session against it
#
# --with-floor exists because the sandbox went stale (QA-PLAN R8): it was built
# once, the floor moved on for nine hardening passes, and "try it in the
# sandbox" then validated a build nobody was shipping. Copying live and
# installing the floor have to be ONE command, or the second step gets skipped.
# Freshness is asserted by lint-conventions.sh rule X1.
#
# Copied: settings.json, skills/, bin/, plugins/, MEMORY (WITHOUT .git — the
# work-log sync hooks then stand down safely in-sandbox), .sec0-baseline.sha256.
# Deliberately NOT copied: transcripts/history/caches/telemetry (irrelevant and
# private), .helm-log-token and any credential (a sandbox must not be able to
# push anywhere), backups/ (that is live-restore material).
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# The SOURCE dir follows CLAUDE_CONFIG_DIR like every other script, so a
# sandbox can be built from a non-default config dir (convention audit).
SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/library-log.sh"
log_init sandbox-make
LIVE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DIR=""; FRESH=0; WITH_FLOOR=0
for a in "$@"; do
  case "$a" in
    --fresh)      FRESH=1 ;;
    --with-floor) WITH_FLOOR=1 ;;
    -*)           printf 'sandbox-make: unknown flag %s\n' "$a" >&2; exit 1 ;;
    *)            DIR="$a" ;;
  esac
done
DIR="${DIR:-$HOME/.claude-sandbox}"
# THE REFUSAL COMES BEFORE THE DELETION, AND IT COMPARES RESOLVED PATHS.
# Measured 2026-08-06 against a fake HOME, this script deleted its own live config
# dir and exited 0:
#
#   $ sh test-sandbox-make.sh "$LIVE/" --fresh
#   sandbox ready: …/.claude/
#     destroy: rm -rf …/.claude/
#   $ ls "$LIVE"        # CLAUDE.md, bin/, skills/ — gone
#   settings.json
#
# TWO independent defects stacked, and either alone is enough. (1) 'rm -rf "$DIR"'
# ran THREE LINES ABOVE the live-dir refusal, so for `--fresh` the gate could not
# matter whatever it compared. (2) The gate was a STRING compare in a `case`, the
# exact P11-01 defect fixed in floor-deny/floor-install/floor-uninstall and left
# here: `~/.claude/`, `~/.claude/.`, `~/.claude//` and `~/.claude/../.claude` are
# all the same directory and none is the same string.
#
# Blast radius is why this is ordered first rather than merely fixed: P11-01
# stripped hooks from a live config, this deletes the directory — and unlike the
# five gated mutators, nothing here has a `--live` escape, so the refusal is
# unconditional by design.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then
  log_fail "refusing to target the live config dir: $DIR is $LIVE"
  log_fix "sh $SRC/test-sandbox-make.sh $HOME/.claude-sandbox --fresh"
  log_end; exit 1
fi
[ "$FRESH" -eq 1 ] && rm -rf "$DIR"
if [ -e "$DIR" ]; then
  log_fail "$DIR already exists"
  log_fix "sh $SRC/test-sandbox-make.sh '$DIR' --fresh$([ "$WITH_FLOOR" -eq 1 ] && printf ' --with-floor')"
  log_end; exit 1
fi

mkdir -p "$DIR"
# Rewrite absolute live paths in settings.json (hook + statusline commands) to
# the sandbox's own copies — otherwise an in-sandbox session executes LIVE
# scripts and the floor's blast radius is no longer contained.
sed "s|$LIVE|$DIR|g" "$LIVE/settings.json" > "$DIR/settings.json"
[ -f "$LIVE/.sec0-baseline.sha256" ] && cp "$LIVE/.sec0-baseline.sha256" "$DIR/"
for d in skills bin plugins; do
  [ -d "$LIVE/$d" ] && cp -R "$LIVE/$d" "$DIR/$d"
done
if [ -d "$LIVE/MEMORY" ]; then
  cp -R "$LIVE/MEMORY" "$DIR/MEMORY"
  rm -rf "$DIR/MEMORY/.git"
fi
# Marker: lets any tool assert it is acting on a sandbox, never live.
printf 'created-from: %s\ncreated-at: %s\n' "$LIVE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$DIR/.helm-sandbox"

if [ "$WITH_FLOOR" -eq 1 ]; then
  log_head "installing this repo's floor into the sandbox"
  # --with-b6 too: the sandbox is exactly where a session-blocking gate should
  # be exercised before it is trusted live.
  # A FAILURE HERE MUST SAY WHAT IT LEFT BEHIND (harbor#313). `set -eu` used to
  # abort on this line with nothing said about the directory already created — and
  # a --fresh sandbox is SEEDED FROM THE LIVE CONFIG, so what it leaves is not an
  # empty shell: MEASURED 2026-08-25 by running the INSTALLED copy, which is the
  # copy a session reaches — rc=127 on the missing file, and the sandbox left behind
  # carried 7 guards, 5 PreToolUse hooks and 96 deny entries, every guard
  # byte-identical to $LIVE/bin and NONE of them this checkout's (verified with cmp
  # against both trees, not by counting). An earlier note in this work said 8 and 8;
  # that was a different run and the smaller figures are the re-measured ones.
  #
  # That is the R8 shape this flag exists to prevent, wearing the appearance of
  # success: an operator who boots that sandbox is testing the build that is
  # ALREADY INSTALLED, which is the one case "try it in the sandbox" must never
  # quietly mean. Nothing about the directory shows it — the guards are present,
  # wired and blocking, just the previous versions, which is harbor#115's sentence
  # about the live floor arriving here one layer over.
  # The install standard's interface (harbor#765): --dir, with CLAUDE_CONFIG_DIR agreeing with it,
  # since here it names the SOURCE config dir and floor-install would refuse the disagreement.
  if ! _fi="$(CLAUDE_CONFIG_DIR="$DIR" sh "$SRC/floor-install.sh" --apply --dir "$DIR" --with-b6 2>&1)"; then
    printf '%s\n' "$_fi" | grep -E '^  (FAIL|fix):' || :
    log_fail "floor-install FAILED, so this sandbox does NOT carry this checkout's floor: $DIR holds whatever $LIVE had when it was seeded, so it may look armed and still be the installed build (QA-PLAN R8); do not trust a guard result from it"
    log_fix "rm -rf '$DIR'; sh $SRC/test-sandbox-make.sh '$DIR' --fresh --with-floor"
    log_end; exit 1
  fi
  log_ok "floor installed from $SRC (B6 included)"
  # floor-verify takes --dir (harbor#800), and the environment must name the same dir or nothing.
  if CLAUDE_CONFIG_DIR="$DIR" sh "$SRC/floor-verify.sh" --dir "$DIR"; then log_ok "the floor verifies in the new sandbox"
  else
    log_fail "the floor did not verify in the new sandbox $DIR (floor-verify's lines above)"
    log_fix "sh $SRC/floor-verify.sh --dir '$DIR'"
    log_end; exit 1
  fi
fi

log_ok "sandbox ready: $DIR"
log_note "boot:    CLAUDE_CONFIG_DIR=$DIR claude"
log_note "destroy: rm -rf $DIR"
[ "$WITH_FLOOR" -eq 1 ] || log_warn "no floor installed, so this sandbox tests an unguarded config"
[ "$WITH_FLOOR" -eq 1 ] || log_fix "sh $SRC/test-sandbox-make.sh '$DIR' --fresh --with-floor"
log_end; exit $?
