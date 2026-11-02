#!/usr/bin/env sh
# policy-constitution-install.sh (harbor#173 · A2) — deploy policy/constitution.md to the box.
#   sh bin/policy-constitution-install.sh [--apply] (--live | --dir PATH) [--from-branch] [--accept-loss]
#     no --apply      what would change, the diff, and every refusal --apply would hit (exit 1 if any)
#     --apply --live  write the live CLAUDE.md
#     --from-branch   ...from a feature branch or with uncommitted policy/constitution.md edits
#     --accept-loss   ...discarding box-only text the back-port gate found
#
# There was no mechanism at all: editing policy/constitution.md changes no running session (the harness loads the box's
# own CLAUDE.md) and no lint or drift check compares the two. DE-30 rejected an AUTOMATED installer; this is a VERB: it
# does nothing without --apply, refuses the live file without --live, and refuses anything but a clean `main` without
# --from-branch. It never re-pins: B8 is the operator's act (admission-install.sh), since an installer that blesses its
# own instruction surfaces is a self-approval loop.
# Removed notes: docs/explanation/code-cases/bin-policy-constitution-install.md
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init constitution-install
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
SRC="$ROOT/policy/constitution.md"
FROM_BRANCH=0
# shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
il_opt() { case "$1" in --from-branch) FROM_BRANCH=1; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
il_parse "$@"
il_target
DEST="$IL_TARGET/CLAUDE.md"
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $DEST"; else log_head "plan for $DEST (dry run: nothing is written)"; fi
if [ ! -f "$SRC" ]; then
  log_fail "no policy/constitution.md at $ROOT"
  log_nofix "run this from a harbor checkout (bin/policy-constitution-install.sh beside policy/constitution.md)"
  log_end; exit 1
fi

_new="$(wc -c < "$SRC" | tr -d ' ')"
_old=0; [ -f "$DEST" ] && _old="$(wc -c < "$DEST" | tr -d ' ')"
_state=absent; [ ! -f "$DEST" ] || { cmp -s "$SRC" "$DEST" && _state=identical || _state=DIFFERS; }
log_note "repo policy/constitution.md: $_new B"
log_note "box CLAUDE.md: $_old B, $_state"
if [ "$_state" = DIFFERS ]; then
  log_note "delta: $(printf '%+d' "$(( _new - _old ))") B; the diff the live sessions would start seeing:"
  diff "$DEST" "$SRC" | head -60 > "${TMPDIR:-/tmp}/constitution-diff.$$" || :
  while IFS= read -r _dl; do log_note "diff $_dl"; done < "${TMPDIR:-/tmp}/constitution-diff.$$"
  rm -f "${TMPDIR:-/tmp}/constitution-diff.$$"
fi

# ── the branch gate ─────────────────────────────────────────────────────────
# --live says "yes, the live file"; this says "yes, THIS TEXT": a feature branch is text nobody has reviewed, and this file
# governs every future session. The dry run runs every gate --apply runs (the dry-run exit rule).
_branch="$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
_dirty="$(cd "$ROOT" && git status --porcelain -- policy/constitution.md 2>/dev/null || true)"
_base="${HARBOR_CI_BASE_BRANCH:-main}"
log_note "source: $_branch$([ -n "$_dirty" ] && printf ' (UNCOMMITTED changes to policy/constitution.md)')"
if [ "$_branch" != "$_base" ] && [ "$FROM_BRANCH" -eq 0 ]; then
  il_refuse "deploying from '$_branch', not $_base (DE-30): a feature branch is text nobody has reviewed, and this file governs every future session" \
    "$(il_cmd --apply) --from-branch"
fi
if [ -n "$_dirty" ] && [ "$FROM_BRANCH" -eq 0 ]; then
  il_refuse "policy/constitution.md has uncommitted changes: deploying would install text that is in no commit and no diff" \
    "$(il_cmd --apply) --from-branch"
fi

if [ "$_state" = identical ]; then
  log_ok "already identical, nothing to write"
  il_stop
  log_end; exit $?
fi

# ── THE BACK-PORT GATE (harbor#462) ─────────────────────────────────────────
# This deploys in ONE direction and the box can drift in the other (harbor#462): the live CLAUDE.md once held three doctrine
# blocks never committed anywhere, and a byte-perfect copy would have destroyed them silently. So the gate lives in the
# tool that would do the damage, not in a note asking people to check first.
# LINE-LEVEL AND ORDER-FREE: `comm` over sorted unique lines asks "is there text on the box that is in no commit" (diff
# would refuse a legitimate reorder); blank lines are dropped so reflowing is not a refusal (§2.11).
# "In no commit" means EVERY committed version, not just HEAD (harbor#683): the known set is the current file plus every
# version `git log --follow` reaches under each name it had. Outside a git checkout it is the current file alone, and the
# refusal says so (stricter, never looser).
# Cannot tell apart: a line removed from the repo as WRONG and hand-written back still passes as known; if that proves real,
# narrow the set to what the repo held at the last deploy (install-stamp records it).
# A history read that fails is counted and said, never passed off as complete (#685): the known set shrinks, which is only
# stricter, and the message names what was read and what was not.
if [ -f "$DEST" ]; then
  if ! _bp_tmp="$(mktemp -d "${TMPDIR:-/tmp}/constitution-install.XXXXXX")"; then
    log_fail "cannot make a workspace under ${TMPDIR:-/tmp}"
    log_nofix "the mktemp error above"
    log_end; exit 1
  fi
  trap 'rm -rf "$_bp_tmp"' EXIT INT TERM
  _known_from="the current policy/constitution.md does not — $ROOT is not a git checkout, so its history could not be read"
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Across renames (harbor#949): --follow pairs each version with the path it had then.
    if git -C "$ROOT" log --follow --diff-filter=d --format=@%H --name-only HEAD -- policy/constitution.md 2>/dev/null \
         | awk '/^@/ { r = substr($0, 2); next } NF && r != "" { print r " " $0; r = "" }' > "$_bp_tmp/revs" \
       && [ -s "$_bp_tmp/revs" ]; then
      _n_rev="$(awk 'NF { n++ } END { print n + 0 }' "$_bp_tmp/revs")"
      _n_bad=0
      cp "$SRC" "$_bp_tmp/known"
      while read -r _rev _rp; do
        git -C "$ROOT" show "$_rev:$_rp" >> "$_bp_tmp/known" 2>/dev/null || _n_bad=$((_n_bad + 1))
      done < "$_bp_tmp/revs"
      if [ "$_n_bad" -eq 0 ]; then
        _known_from="found in none of the $_n_rev committed version(s) of policy/constitution.md, nor in the current file"
      else
        _known_from="found in none of the $((_n_rev - _n_bad)) of $_n_rev committed version(s) that could be read, nor in the current file — $_n_bad version(s) could NOT be read, so a line held only there is reported here too"
      fi
      sed '/^[[:space:]]*$/d' "$_bp_tmp/known" | sort -u > "$_bp_tmp/src"
    else
      _known_from="the current policy/constitution.md does not — git log --follow failed in $ROOT, so its history could not be read (a partial or damaged clone?)"
      sed '/^[[:space:]]*$/d' "$SRC" | sort -u > "$_bp_tmp/src"
    fi
  else
    sed '/^[[:space:]]*$/d' "$SRC" | sort -u > "$_bp_tmp/src"
  fi
  sed '/^[[:space:]]*$/d' "$DEST" | sort -u > "$_bp_tmp/dst"
  comm -13 "$_bp_tmp/src" "$_bp_tmp/dst" > "$_bp_tmp/lost"
  _lost="$(wc -l < "$_bp_tmp/lost" | tr -d ' ')"
  if [ "${_lost:-0}" -gt 0 ] 2>/dev/null; then
    head -20 "$_bp_tmp/lost" > "$_bp_tmp/lost20"
    while IFS= read -r _ll; do log_note "box-only | $_ll"; done < "$_bp_tmp/lost20"
    [ "$_lost" -le 20 ] || log_note "box-only | … and $((_lost - 20)) more"
    log_note "the lossless way is a back-port: diff \"$ROOT/policy/constitution.md\" \"$DEST\", fold what belongs into policy/constitution.md, commit it, then re-run"
    il_loss "the box's CLAUDE.md carries $_lost line(s) $_known_from; deploying would delete text that exists in exactly one place on this box" \
      "$(il_cmd --apply --accept-loss)"
    [ "$IL_ACCEPT_LOSS" -eq 0 ] || log_note "--accept-loss: the backup this run takes is the only copy of those lines"
  fi
fi

il_stop
if [ "$IL_APPLY" -eq 0 ]; then
  [ "$IL_REFUSED" -eq 1 ] || il_apply_next constitution
  log_end; exit $?
fi

# Written through a temp file and moved, never a truncate in place; a symlinked CLAUDE.md is written through.
il_backup "$DEST" || { log_end; exit 1; }
_real="$DEST"
if [ -L "$DEST" ]; then
  _lt="$(readlink "$DEST" 2>/dev/null || true)"
  case "$_lt" in /*) _real="$_lt" ;; ?*) _real="$IL_TARGET/$_lt" ;; esac
fi
if ! { cp "$SRC" "$_real.tmp.$$" && mv -f "$_real.tmp.$$" "$_real"; }; then
  rm -f "$_real.tmp.$$"
  log_fail "could not write $DEST"
  log_nofix "the cp/mv error above; the box's CLAUDE.md is unchanged or in $IL_BK"
  log_end; exit 1
fi
# Post-write verify: a copy that reported success and landed different bytes is what every installer here guards against.
if ! cmp -s "$SRC" "$DEST"; then
  log_fail "$DEST differs from $SRC after the copy"
  log_fix "cp '$IL_BK/CLAUDE.md' '$DEST'"
  log_end; exit 1
fi
log_ok "installed $DEST, verified byte-identical ($_new B)"
[ ! -f "$IL_BK/CLAUDE.md" ] || log_note "backup: $IL_BK/CLAUDE.md"
il_source "$ROOT"; il_manifest CLAUDE.md
il_manifest_write || { log_end; exit 1; }
# This changed an instruction surface; the B8 re-pin is the operator's, and deploy asks for it itself.
[ "$IL_LIVE" -eq 0 ] || il_next --deploy-does "sh $IL_TARGET/bin/pin-instructions.sh --apply --live"
log_end; exit $?
