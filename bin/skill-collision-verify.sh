#!/usr/bin/env sh
# skill-collision-verify.sh (harbor#117 · I3, #476, #641) — the pre-install collision scan, by content.
#
#   sh bin/skill-collision-verify.sh <name> [<name>...]   exit 1 if installing would
#                                                 destroy work only the box has
#   sh bin/skill-collision-verify.sh --all                every tracked skill
#
# WHAT I3 ASKED FOR, AND WHAT WAS ACTUALLY MISSING. The ticket wanted a scan
# across three writers — the operator's own skills, `sync-desktop-app-skills.sh`,
# and this repo — so that no install silently overwrites another writer's work.
#
# THE THIRD WRITER DOES NOT EXIST ON THIS BOX. Measured 2026-08-22: no
# `sync-desktop-app-skills.sh` anywhere under the config dir. The epic named it
# in 2026-07-22 and nothing has checked since — the same shape as I2, where five
# of eight "duplicate pairs" named a twin that was never there. A scan built
# against a phantom writer reads as coverage and is not, so this one is built
# against the writers that exist: this repo's installer, and whoever edited the
# live directory by hand.
#
# THE HOLE IT CLOSES. `skill-install.sh` verifies byte-identity AFTER writing —
# it proves the copy landed, not that the copy was safe to make. Its predecessor
# question, *does the destination hold something the repo has never seen*, was
# never asked, and the answer is destroyed by the `cp -R` before anyone can look.
#
# THE DISCRIMINATOR IS CONTENT, NEVER MTIME (harbor#476, #641). This read SKILL.md's mtime, and was
# wrong two ways: it guarded a DIRECTORY by one file, and `cp -R` stamps the destination with install
# time, so the second install of any change that did not touch SKILL.md was refused forever — and the
# verdict flipped with `git checkout`, which rewrites mtimes. Its override became the routine path.
#
# The question is "does the live copy hold work that exists nowhere else", so every live file that
# differs from the source (or exists only live) is asked it, through install-lib's il_known: bytes the
# install manifest records for that path (what an install put there), or bytes committed at
# skills/<n>/… or vendor/skills/<n>/… (an older version) are known. One unknown file refuses.
# With no git checkout and no manifest row for a file there is no verdict, and no verdict does not
# block (§2.11): the backup skills-install takes still holds it.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
  '')        printf 'skills-collide: name a skill, or --all\n' >&2; exit 2 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/library-log.sh"
. "$ROOT/bin/deploy-install-lib.sh"
log_init skills-collide
# A helper, called by skills-install with CLAUDE_CONFIG_DIR set to its own resolved target.
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST_ROOT="$CFG_DIR/skills"
GIT=0; git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && GIT=1

src_for() { # <name> -> tracked source dir
  for _b in "$ROOT/skills" "$ROOT/vendor/skills"; do
    [ -d "$_b/$1" ] && { printf '%s' "$_b/$1"; return 0; }
  done
  return 1
}
# Caches are not payload, exactly as skills-install's byte check excludes them.
_files() { ( cd "$1" && find . -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name .DS_Store -print ) | sed 's|^\./||' | LC_ALL=C sort; }

names=''
if [ "$1" = --all ]; then
  for _d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
    [ -d "$_d" ] || continue
    names="$names $(basename "$_d")"
  done
else
  names="$*"
fi

log_head "collision scan · $DEST_ROOT"
for n in $names; do
  if ! src="$(src_for "$n")"; then
    log_fail "$n is not tracked here: no skills/$n or vendor/skills/$n in $ROOT"
    log_nofix "the skill's name, as ls $ROOT/skills $ROOT/vendor/skills spells it"
    continue
  fi
  dst="$DEST_ROOT/$n"
  [ -d "$dst" ] || continue                                   # nothing to collide with
  diff -r -x __pycache__ -x '*.pyc' -x .DS_Store "$src" "$dst" >/dev/null 2>&1 && continue   # identical: no write happens
  _unknown=''; _nv=''
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    if [ -f "$src/$_f" ] && cmp -s "$src/$_f" "$dst/$_f"; then continue; fi
    il_known "$CFG_DIR" "skills/$n/$_f" "$dst/$_f" "$ROOT" "skills/$n/$_f" "vendor/skills/$n/$_f" && continue
    if [ "$GIT" -eq 0 ] && [ -z "$(il_mf_blob "$CFG_DIR" "skills/$n/$_f")" ]; then _nv="$_nv $_f"; continue; fi
    _unknown="$_unknown $_f"
  done <<EOF
$(_files "$dst")
EOF
  [ -z "$_nv" ] || log_note "$n: no verdict for$_nv — no git checkout at $ROOT and no install record, so not refused"
  if [ -n "$_unknown" ]; then
    log_fail "$n: the installed copy holds bytes in no commit and no install record:$_unknown — installing would overwrite work only this box has. Capture them first: diff -r '$src' '$dst'"
    log_nofix "harbor#476 — copy them into ${src#"$ROOT"/} through a PR, or install with --accept-loss once you have looked"
  else
    log_ok "$n: every installed file the source lacks is an older commit or an install record: nothing only this box has"
  fi
done

log_end; exit $?
