#!/usr/bin/env sh
# policy-constitution-install.sh (harbor#173 · A2) — deploy policy/constitution.md to the box.
#   sh bin/policy-constitution-install.sh [--apply] (--live | --dir PATH) [--from-branch] [--accept-loss]
#     no --apply      what would change, the diff, and every refusal --apply would hit (exit 1 if any)
#     --apply --live  write the live CLAUDE.md
#     --from-branch   ...from a feature branch or with uncommitted policy/constitution.md edits
#     --accept-loss   ...discarding box-only text the back-port gate found
#
# THE GAP THIS CLOSES IS THAT THERE WAS NO MECHANISM AT ALL. Editing
# policy/constitution.md changes no running session: the copy the harness loads is the
# box's own CLAUDE.md, a separate file, and nothing deployed to it. Lint X2
# compares only bin/*.sh; guard-selfedit protects the floor's own surfaces;
# drift-reference-check.sh says in its own header that it does not compare live against
# repo. So a session could edit the constitution, report the rule as in force, and
# be wrong — with every instrument green.
#
# DE-30 REJECTED AN AUTOMATED INSTALLER AND THIS IS NOT ONE. What it rejected was
# a deployment that runs unattended with a byte-equality oracle deciding when to
# fire. This is a VERB: it does nothing without --apply, refuses the live file
# without --live, and refuses to deploy from anything but a clean `main` unless
# the operator says --from-branch out loud. The failure DE-30 names — unreviewed
# text arriving over the live constitution from a work-in-progress checkout — is
# the specific thing those two gates exist to make impossible by accident.
#
# IT NEVER RE-PINS. B8 is the operator's act from their own terminal, for the
# reason admission-install.sh records at length: an installer run from a session that
# blesses its own instruction surfaces is a self-approval loop.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init constitution-install
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
SRC="$ROOT/policy/constitution.md"
FROM_BRANCH=0
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

# ── what would change ───────────────────────────────────────────────────────
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
# THE ONE THAT IS NOT ABOUT PERMISSIONS. --live says "yes, the live file"; this
# one says "yes, THIS TEXT" — and they are different questions. A feature branch
# is by definition text nobody has reviewed, and the live constitution is the one
# file where unreviewed text governs every future session on the box.
# The dry run runs every gate --apply runs (the dry-run exit rule), so deploy's plan sees a refusal.
_branch="$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || printf unknown)"
_dirty="$(cd "$ROOT" && git status --porcelain -- policy/constitution.md 2>/dev/null || true)"
_base="${HARBOR_CI_BASE_BRANCH:-${HARBOR_BASE_BRANCH:-main}}"
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
# THIS DEPLOYS IN ONE DIRECTION AND THE BOX HAS DRIFTED IN THE OTHER. Measured
# 2026-09-06: the live CLAUDE.md was 1,933 bytes LARGER than policy/constitution.md and
# every diff hunk was an append — three blocks of doctrine written straight into
# the live file and never committed anywhere. `git log -S` over each of their
# distinctive phrases returned ZERO commits, so version control had never held
# them. One of the three was the entire "Every check and every notifier is
# registered" rule, which docs/reference/checks.md opens by citing as its reason to exist.
#
# Running this command in that state would have destroyed all three, silently and
# with a post-write `cmp` reporting success — the copy is byte-perfect, which is
# exactly what makes it unrecoverable. The backup below is real but it is a file
# in `backups/` that nobody has a reason to open, because nothing said anything
# was lost.
#
# NOTHING DETECTED THIS. Lint X2 compares bin/*.sh and not this document.
# drift-reference-check.sh states in its own header that it does not compare live
# against repo. admission-self-edit.sh stops a SESSION writing there, which is a
# different question from whether the operator's own edits ever come back. The
# one-way installer was the whole mechanism, and a one-way installer facing a
# two-way surface loses the direction it does not carry.
#
# SO THE GATE IS HERE, IN THE TOOL THAT WOULD DO THE DAMAGE, rather than in a
# note asking people to check first. A rule with no mechanism is a wish, and the
# operator reading a warning is not a mechanism — they are running this command
# precisely because they believe the repo is ahead.
#
# LINE-LEVEL AND ORDER-FREE, deliberately. `diff` would call a moved paragraph a
# deletion and refuse a legitimate reorder; `comm` over sorted unique lines asks
# only "is there text on the box that is in no commit", which is the actual
# question. Blank lines and pure-whitespace lines are dropped so reflowing does
# not manufacture a refusal (§2.11 — a gate with false positives gets switched
# off, and a switched-off gate protects nothing).
#
# "IN NO COMMIT" MEANS EVERY COMMITTED VERSION, NOT JUST HEAD (harbor#683). The
# sentence above stated the right question and the code asked a narrower one: it
# compared the live file with the current policy/constitution.md only. So every
# intentional edit that replaced a line refused. Deploying #581 (2026-09-24)
# named the three lines of the old defer paragraph as text "that exists in
# exactly one place on this box", although it had been committed for weeks and
# was replaced on purpose. An operator trained to answer every refusal with
# --accept-loss answers the real one the same way. The known set is therefore
# the current file plus every version `git log --follow -- policy/constitution.md`
# reaches, under each name it had: 22 revisions on 2026-09-24, about half a second at load 10.
#
# OUTSIDE A GIT CHECKOUT the history cannot be read, so the known set falls back
# to the current file alone, and the refusal says so. Stricter, never looser.
#
# WHAT THIS CANNOT TELL APART, stated rather than discovered: a line removed from
# the repo as WRONG and then hand-written back into the live file still passes as
# "known", because some commit once held it. If that case turns out to be real,
# narrow the known set to what the repo held at the last deploy (install-stamp
# records it).
#
# A HISTORY READ THAT FAILS IS SAID, NEVER PASSED OFF AS COMPLETE (review of
# #685). If `git log` fails (a corrupt or partial object store), or some
# `git show` does, the known set shrinks. That only makes the gate stricter, so
# nothing live is ever let through. But the first cut then claimed "none of the 0
# committed versions", a search that never happened, so the refusal reported a
# false fact on exactly the run where the operator most needs a true one.
# Failures are counted, and the message names what was read and what was not.
if [ -f "$DEST" ]; then
  if ! _bp_tmp="$(mktemp -d "${TMPDIR:-/tmp}/constitution-install.XXXXXX")"; then
    log_fail "cannot make a workspace under ${TMPDIR:-/tmp}"
    log_nofix "the mktemp error above"
    log_end; exit 1
  fi
  trap 'rm -rf "$_bp_tmp"' EXIT INT TERM
  _known_from="the current policy/constitution.md does not — $ROOT is not a git checkout, so its history could not be read"
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # ACROSS RENAMES (harbor#949): the W2 move left `rev-list -- policy/constitution.md` one version, and 17
    # lines committed under CONSTITUTION.md refused. --follow pairs each version with the path it had then.
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
# POST-WRITE VERIFY. A copy that reported success and landed different bytes is
# the failure every installer in this repo was written for.
if ! cmp -s "$SRC" "$DEST"; then
  log_fail "$DEST differs from $SRC after the copy"
  log_fix "cp '$IL_BK/CLAUDE.md' '$DEST'"
  log_end; exit 1
fi
log_ok "installed $DEST, verified byte-identical ($_new B)"
[ ! -f "$IL_BK/CLAUDE.md" ] || log_note "backup: $IL_BK/CLAUDE.md"
# Its row in the install manifest (install standard §3); a symlinked CLAUDE.md is recorded as the link.
il_source "$ROOT"; il_manifest CLAUDE.md
il_manifest_write || { log_end; exit 1; }
# This changed an instruction surface; the B8 re-pin is the operator's, and deploy asks for it itself.
[ "$IL_LIVE" -eq 0 ] || il_next --deploy-does "sh $IL_TARGET/bin/pin-instructions.sh --apply --live"
log_end; exit $?
