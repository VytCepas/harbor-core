#!/usr/bin/env sh
# SANDBOX (harbor#33) — build a disposable copy of ~/.claude's CONFIG surfaces
# for floor development. Everything in workstream B and K1/K2 runs against this
# via CLAUDE_CONFIG_DIR — never against the live dir.
#
#   sh test-sandbox-make.sh [dir]              # default: ~/.claude-sandbox ; refuses if it exists
#   sh test-sandbox-make.sh [dir] --fresh      # delete + recreate
#   sh test-sandbox-make.sh [dir] --fresh --with-floor   # …and install THIS repo's floor
#   CLAUDE_CONFIG_DIR=<dir> claude        # boot a session against it
# --with-floor exists because the sandbox went stale (QA-PLAN R8): copying live and installing the floor are ONE command; freshness is lint rule X1.
# Copied: settings.json, skills/, bin/, plugins/, MEMORY without .git. Not copied: transcripts, history, credentials, backups/.
# Removed notes: docs/explanation/code-cases/bin-test-sandbox-make.md
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
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
# The refusal comes before the deletion and compares RESOLVED paths: `"$LIVE/" --fresh` once deleted the live config dir (2026-08-06) because the delete ran above a string-compare gate that trailing-dot and `..` spellings defeat.
# There is no `--live` escape here, so the refusal is unconditional.
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
# Rewrite absolute live paths in settings.json to the sandbox's copies, or a session executes LIVE scripts.
sed "s|$LIVE|$DIR|g" "$LIVE/settings.json" > "$DIR/settings.json"
[ -f "$LIVE/.sec0-baseline.sha256" ] && cp "$LIVE/.sec0-baseline.sha256" "$DIR/"
for d in skills bin plugins; do
  [ -d "$LIVE/$d" ] && cp -R "$LIVE/$d" "$DIR/$d"
done
if [ -d "$LIVE/MEMORY" ]; then
  cp -R "$LIVE/MEMORY" "$DIR/MEMORY"
  rm -rf "$DIR/MEMORY/.git"
fi
printf 'created-from: %s\ncreated-at: %s\n' "$LIVE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$DIR/.helm-sandbox"

if [ "$WITH_FLOOR" -eq 1 ]; then
  log_head "installing this repo's floor into the sandbox"
  # --with-b6 too: the sandbox is where a session-blocking gate is exercised before it is trusted live.
  # A failure here must say what it left behind (harbor#313): a --fresh sandbox is seeded from the LIVE config, so an aborted install left guards byte-identical to $LIVE/bin and none of this checkout's (R8 shape).
  # The install standard's interface (harbor#765): --dir, with CLAUDE_CONFIG_DIR agreeing, since here it names the SOURCE config dir.
  if ! _fi="$(CLAUDE_CONFIG_DIR="$DIR" sh "$SRC/admission-install.sh" --apply --dir "$DIR" --with-b6 2>&1)"; then
    printf '%s\n' "$_fi" | grep -E '^  (FAIL|fix):' || :
    log_fail "floor-install FAILED, so this sandbox does NOT carry this checkout's floor: $DIR holds whatever $LIVE had when it was seeded, so it may look armed and still be the installed build (QA-PLAN R8); do not trust a guard result from it"
    log_fix "rm -rf '$DIR'; sh $SRC/test-sandbox-make.sh '$DIR' --fresh --with-floor"
    log_end; exit 1
  fi
  log_ok "floor installed from $SRC (B6 included)"
  # floor-verify takes --dir (harbor#800), and the environment must name the same dir or nothing.
  if CLAUDE_CONFIG_DIR="$DIR" sh "$SRC/admission-verify.sh" --dir "$DIR"; then log_ok "the floor verifies in the new sandbox"
  else
    log_fail "the floor did not verify in the new sandbox $DIR (floor-verify's lines above)"
    log_fix "sh $SRC/admission-verify.sh --dir '$DIR'"
    log_end; exit 1
  fi
fi

log_ok "sandbox ready: $DIR"
log_note "boot:    CLAUDE_CONFIG_DIR=$DIR claude"
log_note "destroy: rm -rf $DIR"
[ "$WITH_FLOOR" -eq 1 ] || log_warn "no floor installed, so this sandbox tests an unguarded config"
[ "$WITH_FLOOR" -eq 1 ] || log_fix "sh $SRC/test-sandbox-make.sh '$DIR' --fresh --with-floor"
log_end; exit $?
