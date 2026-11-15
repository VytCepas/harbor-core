#!/usr/bin/env sh
# skill-install.sh (harbor#7 · I1) — install a tracked skill into ~/.claude/skills.
#   harbor skills [--apply] (--live | --dir PATH) [--accept-loss] [commands] [<name> | --all] [--from-old OLD]
#     no name, no --all   list the tracked skills and their install state
#     <name> | --all      install or update one, or every tracked skill (a dry run unless --apply)
#     commands            the slash commands in commands/ instead of skills
#     --from-old OLD      a rename: the old dir moves into the backup
#     --accept-loss       install over a newer live copy, or one holding files the repo does not
#   A dry run exits 1 exactly when --apply would refuse (nested, newer, box-only files).
#   skill-catalog is the one skill that is COMPOSED, not copied (harbor#1149): see COMPOSED below.
#
# Why: the hand-typed `cp -R skills/<name>/. ~/.claude/skills/<name>/` silently nests <name>/<name>/ and leaves
# the original files serving if the trailing `/.` is omitted. This verb verifies byte-identity after writing
# (diff -r, caches excluded), refuses a nested dir, and handles a rename (kebab `red-team` beside PascalCase
# `RedTeam` leaves two skills in the listing). Dry run is the default: this writes an instruction surface the B8 pin watches.
# Removed notes: docs/explanation/code-cases/bin-skill-install.md
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-fs.sh"
. "$HERE/deploy-install-lib.sh"
log_init skills-install

# Two payload kinds, one gate (harbor#7): commands are flat files, skills are directories. The nesting refusal and
# `--from-old` are directory-shaped; the gate (dry run, verify after writing, no live surface without --live) is shared.
KIND=skills; ALL=0; NAME=''; FROM_OLD=''
il_opt() {
  # shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
  case "$1" in
    commands|skills) KIND="$1"; IL_TAKE=1 ;;
    --all) ALL=1; IL_TAKE=1 ;;
    # A TRAILING `--from-old` USED TO ABORT WITH NO OUTPUT; il_value makes it a usage error.
    --from-old) il_value --from-old "$2"; FROM_OLD="$2"; IL_TAKE=2 ;;
    -*) IL_TAKE=0 ;;
    *) [ -z "$NAME" ] || il_usage_error "one name, or --all: got $NAME and $1"; NAME="$1"; IL_TAKE=1 ;;
  esac
}
il_parse "$@"
[ "$ALL" -eq 0 ] || [ -z "$NAME" ] || il_usage_error "a name and --all are two selections; give one"
il_target
DEST_ROOT="$IL_TARGET/$KIND"
WROTE=0; BAD=0
# Every file this installs is a row of the install manifest (install standard §3), whose commit is this checkout's.
il_source "$ROOT"

# Both tracked homes. vendor/ first is deliberate: a name present in both means
# a re-authored skill has landed in skills/ and should win.
src_for() {
  for d in "$ROOT/skills/$1" "$ROOT/vendor/skills/$1"; do
    [ -f "$d/SKILL.md" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

# The skill book is COMPOSED, not copied (harbor#1149): the installed book lists every installed skill and CLI, so
# copying the tracked one drops rows and a byte check would call it DRIFTED for ever. bin/skill-catalog.sh install is
# its one writer and judge, and --all installs it LAST. Without the generator beside this script it is an ordinary payload.
COMPOSED=skill-catalog
_composed() { [ "$KIND" = skills ] && [ "$1" = "$COMPOSED" ] && [ -f "$ROOT/bin/skill-catalog.sh" ]; }

# The one install command for ONE name, whatever this run selected: a fix names the skill it fixes.
_cmd_for() { # <name>
  printf 'sh %s --apply%s %s %s' "$IL_SELF" "$([ "$KIND" = commands ] && printf ' commands')" "$1" "$(il_spell)"
}

# The exec bit is payload and diff -r cannot see it: `cp -R` over an existing file keeps the destination's mode, so
# a 644 copy of a 755 checker passed the byte check and then exited 126. Only the skills path needs this; commands
# are never executed.
# Mode through fs-lib (harbor#618): octal digits, or '?' when unreadable. On GNU the old BSD-first
# chain put filesystem text into 'chmod "$(_mode_of …)"', so no skill could install once a mode drifted.
_mode_of() { _mo="$(fs_mode "$1")"; printf '%s' "${_mo:-?}"; } # <file> -> numeric mode
_mode_mismatches() { # <src-dir> <dest-dir> -> prints one line per differing file
  ( cd "$1" && find . -type f -print ) | while IFS= read -r _mm_rel; do
    [ -n "$_mm_rel" ] || continue
    [ -f "$2/$_mm_rel" ] || continue
    _mm_s="$(_mode_of "$1/$_mm_rel")"; _mm_d="$(_mode_of "$2/$_mm_rel")"
    [ "$_mm_s" = "$_mm_d" ] || printf '  %s: source %s, installed %s\n' "${_mm_rel#./}" "$_mm_s" "$_mm_d"
  done
}

# Generated caches are not payload: a box-only __pycache__ failed every re-install's byte check (#702).
_diff_r() { diff -r -x __pycache__ -x '*.pyc' -x .DS_Store "$@"; }

state_of() {
  _s="$1"; _d="$DEST_ROOT/$2"
  [ -d "$_d" ] || { printf 'absent'; return; }
  [ -d "$_d/$2" ] && { printf 'NESTED'; return; }
  if _composed "$2"; then
    # The generator answers: 0 current, 1 stale, anything else it could not say (a router row it cannot read).
    _sc=0; il_run sh "$ROOT/bin/skill-catalog.sh" install --check >/dev/null 2>&1 || _sc=$?
    case "$_sc" in 0) printf 'current' ;; 1) printf 'DRIFTED' ;; *) printf 'UNREADABLE' ;; esac
    return
  fi
  if _diff_r "$_s" "$_d" >/dev/null 2>&1 && [ -z "$(_mode_mismatches "$_s" "$_d")" ]
  then printf 'current'; else printf 'DRIFTED'; fi
}

list_all() {
  log_head "tracked skills and their install state in $DEST_ROOT"
  for d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    n=$(basename "$d"); _st="$(state_of "${d%/}" "$n")"
    case "$_st" in
      current) log_ok "$n: current (${d#"$ROOT"/})" ;;
      NESTED)  log_warn "$n: NESTED (${d#"$ROOT"/}) — an earlier hand-typed cp left $n/$n/ and the old copy is still serving"
               log_nofix "skills/README.md (the trailing /. trap): move $DEST_ROOT/$n/$n aside by hand" ;;
      UNREADABLE) log_warn "$n: the generator cannot say whether the installed book is current"
               log_nofix "sh $ROOT/bin/skill-catalog.sh install --check $(il_spell): its FAIL line names the cause" ;;
      *)       log_note "$n: $_st (${d#"$ROOT"/})" ;;
    esac
  done
}

# Files the INSTALLED copy has and the source does not: cp cannot remove them, so the byte check
# after writing would fail. Caches are excluded exactly as _diff_r excludes them.
_box_only() { # <src> <dest> → one path per file, relative to dest
  ( cd "$2" && find . -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name .DS_Store -print ) 2>/dev/null \
    | sed 's|^\./||' | while IFS= read -r _bo; do [ -e "$1/$_bo" ] || printf '%s\n' "$_bo"; done | LC_ALL=C sort
}
# The same content question skills-collide asks (harbor#641): a box-only file whose bytes are an older
# commit of the skill, or an install record, is one the repo moved or dropped; only the rest are lost.
_unknown_of() { # <name> <dest> <box-only paths> → the ones in no commit and no install record
  printf '%s\n' "$3" | while IFS= read -r _uo; do
    [ -n "$_uo" ] || continue
    il_known "$IL_TARGET" "skills/$1/$_uo" "$2/$_uo" "$ROOT" "skills/$1/$_uo" "vendor/skills/$1/$_uo" || printf '%s\n' "$_uo"
  done
}

# What the run takes out goes into its backup dir, never rm: a move IS the backup.
_aside() { # <path under the target>
  _ar="${1#"$IL_TARGET"/}"
  if [ -n "$IL_BK" ] && mkdir -p "$IL_BK/$(dirname -- "$_ar")" && mv "$1" "$IL_BK/$_ar"; then return 0; fi
  log_fail "could not move $1 into the backup ${IL_BK:-(no backup dir)}"
  log_nofix "the mv error above"
  return 1
}

# A loss is refused unless --accept-loss, per skill, so one refusal never stops the rest of --all.
_loss() { # <name> <what installing would lose>
  if [ "$IL_ACCEPT_LOSS" -eq 1 ]; then log_warn "$1: --accept-loss: $2"; return 0; fi
  log_fail "$1: $2"
  log_fix "$(_cmd_for "$1") --accept-loss"
  return 1
}

# ── RENAME (--from-old) ─────────────────────────────────────────────────────
# A case-only rename is the same directory on this case-insensitive volume: `Telos`/`telos` pass the string guard,
# install_one writes into the directory about to be deleted, and the skill is destroyed after "installed" (harbor#239).
# The test must assert the installed skill still exists, not only that the old name is gone.
remove_old() {
  [ -n "$FROM_OLD" ] || return 0
  [ "$FROM_OLD" != "$1" ] || return 0
  [ -d "$DEST_ROOT/$FROM_OLD" ] || return 0

  # A symlink is not the same directory under another name: the case-only branch would claim it and the two-step mv
  # would move the link INTO the installed skill (PR #241). There is no rename to perform; the link goes to the backup.
  if [ -L "$DEST_ROOT/$FROM_OLD" ]; then
    _aside "$DEST_ROOT/$FROM_OLD" || return 1
    il_manifest_drop "$KIND/$FROM_OLD"
    log_ok "$FROM_OLD: removed (a symlink; renamed to $1), kept in $IL_BK"
    return 0
  fi

  # Ask the filesystem, not strings and not `pwd -P` (which returns the spelling typed): drop a marker under one name and
  # look for it under the other. No `stat` flavour test needed (BSD and GNU differ).
  _same=0
  _probe=".harbor-same-dir-probe.$$"
  if : > "$DEST_ROOT/$FROM_OLD/$_probe" 2>/dev/null; then
    [ -e "$DEST_ROOT/$1/$_probe" ] && _same=1
    rm -f "$DEST_ROOT/$FROM_OLD/$_probe"
  fi

  if [ "$_same" -eq 1 ]; then
    # Same directory, wrong spelling: rename in two steps through a temp name, since a direct `mv Alpha alpha` is a no-op or an error here.
    _tmp="$DEST_ROOT/$1.rename-tmp.$$"
    if ! mv "$DEST_ROOT/$FROM_OLD" "$_tmp" 2>/dev/null; then
      log_fail "$1: could not stage the case-only rename of $DEST_ROOT/$FROM_OLD"
      log_nofix "the mv error above; $FROM_OLD is where it was"
      return 1
    fi
    if ! mv "$_tmp" "$DEST_ROOT/$1" 2>/dev/null; then
      # Put it back rather than leaving the skill under a temp name.
      mv "$_tmp" "$DEST_ROOT/$FROM_OLD" 2>/dev/null || true
      log_fail "$1: could not rename $DEST_ROOT/$FROM_OLD to $1"
      log_nofix "the mv error above; $FROM_OLD was put back"
      return 1
    fi
    log_ok "$FROM_OLD: renamed to $1 (case-only; one directory)"
    return 0
  fi

  _aside "$DEST_ROOT/$FROM_OLD" || return 1
  il_manifest_drop "$KIND/$FROM_OLD"
  log_ok "$FROM_OLD: removed (renamed to $1), kept in $IL_BK"
}

install_one() {
  n="$1"
  if ! src=$(src_for "$n"); then
    log_fail "no tracked skill named $n in skills/ or vendor/skills/"
    log_fix "sh $IL_SELF $(il_spell)"
    return 1
  fi
  dest="$DEST_ROOT/$n"
  st=$(state_of "$src" "$n")

  if [ "$st" = UNREADABLE ]; then
    log_fail "$n: the generator cannot say what the installed book should be, so it was not touched"
    log_fix "sh $ROOT/bin/skill-catalog.sh install --check $(il_spell)"
    return 1
  fi
  if [ "$st" = current ]; then
    log_ok "$n: current"
    # The rename cleanup must not sit behind this early return: when the kebab name was already current the old
    # PascalCase dir stayed and the listing held two skills (install test case 6).
    # A current copy is recorded too, so the first deploy on the standard leaves a complete manifest.
    if [ "$IL_APPLY" -eq 1 ]; then il_manifest_drop "$KIND/$n"; il_manifest "$KIND/$n"; remove_old "$n"
    elif [ -n "$FROM_OLD" ] && [ -d "$DEST_ROOT/$FROM_OLD" ]; then
      log_note "$n: would also move $DEST_ROOT/$FROM_OLD into the backup (renamed)"
    fi
    return 0
  fi
  if [ "$st" = NESTED ]; then
    log_fail "$n: $dest/$n/ is a nested copy an earlier hand-typed cp left, and the old copy is still serving"
    log_nofix "skills/README.md (the trailing /. trap): move $dest/$n aside by hand, then re-run"
    return 1
  fi

  # I3 · ask before writing (harbor#117): skill-collision-verify.sh refuses only when a live file's bytes are in no
  # commit and no install record (harbor#476, #641), so an ordinary update stays silent. The dry run asks too.
  _refused=0; _replace=0; _collided=0
  if [ "$st" = DRIFTED ] && [ -x "$ROOT/bin/skill-collision-verify.sh" ] && [ "$KIND" = skills ]; then
    if ! _co="$(CLAUDE_CONFIG_DIR="$IL_TARGET" sh "$ROOT/bin/skill-collision-verify.sh" "$n" 2>&1)"; then
      _collided=1
      _loss "$n" "$(printf '%s\n' "$_co" | sed -n "s/^  FAIL: $n: //p" | head -1 | sed 's/ Capture them first:.*//') (skills-collide); capture them first with diff -r '${src}' '${dest}'" || _refused=1
    fi
  fi
  if [ "$st" = DRIFTED ]; then
    _only="$(_box_only "$src" "$dest")"
    if [ -n "$_only" ]; then
      _replace=1
      _lost="$(_unknown_of "$n" "$dest" "$_only")"
      if [ -n "$_lost" ] && [ "$_collided" -eq 0 ]; then
        _loss "$n" "the installed copy holds $(printf '%s\n' "$_lost" | wc -l | tr -d ' ') file(s) the repo does not ($(printf '%s\n' "$_lost" | head -3 | sed 's|^|/|' | tr '\n' ' ' | sed 's/ $//')), and installing would fail after writing" || _refused=1
      elif [ -z "$_lost" ]; then
        log_note "$n: the installed copy's extra files are older commits or install records; the install moves them into the backup ($(printf '%s\n' "$_only" | head -3 | sed 's|^|/|' | tr '\n' ' ' | sed 's/ $//'))"
      fi
    fi
  fi
  [ "$_refused" -eq 0 ] || return 1

  if [ "$IL_APPLY" -eq 0 ]; then
    if [ "$st" = absent ]; then log_note "$n: would install (absent)"; else log_note "$n: would update (drifted)"; fi
    [ -z "$FROM_OLD" ] || log_note "$n: would also move $DEST_ROOT/$FROM_OLD into the backup (renamed)"
    return 0
  fi

  # The generator writes the book: its own backup, its own byte check, its own manifest row.
  if _composed "$n"; then
    if ! il_run sh "$ROOT/bin/skill-catalog.sh" install --apply; then
      log_fail "$n: the generator could not write the installed book"
      log_nofix "its FAIL lines above; the pre-run copy is in the backup it names"
      return 1
    fi
    WROTE=1
    log_ok "$n: composed from what is installed, verified"
    return 0
  fi

  # The pre-run copy goes into the backup. With box-only files accepted as lost, the installed dir
  # itself is moved there, so the new copy lands in an empty dir and the byte check can pass.
  if [ "$_replace" -eq 1 ]; then _aside "$dest" || return 1; else il_backup "$dest" || return 1; fi
  mkdir -p "$dest"
  # The trailing /. is the whole point of this script. Do not "simplify" it.
  if ! cp -R "$src/." "$dest/"; then
    log_fail "$n: could not copy $src into $dest"
    log_nofix "the cp error above; the pre-run copy is in $IL_BK"
    return 1
  fi
  WROTE=1

  if [ -d "$dest/$n" ]; then
    log_fail "$n: a nested $dest/$n exists after the copy; not removing it automatically"
    log_nofix "skills/README.md (the trailing /. trap)"
    return 1
  fi
  if ! _diff_r "$src" "$dest" >/dev/null 2>&1; then
    log_fail "$n: $dest differs from its source after the copy ($(_diff_r "$src" "$dest" 2>&1 | head -1))"
    log_nofix "diff -r '$src' '$dest'; the pre-run copy is in $IL_BK"
    return 1
  fi

  # Carry the source's modes over (`cp -R` did not for existing files), then CHECK that it took.
  ( cd "$src" && find . -type f -print ) | while IFS= read -r _im_rel; do
    [ -n "$_im_rel" ] || continue
    [ -f "$dest/$_im_rel" ] || continue
    chmod "$(_mode_of "$src/$_im_rel")" "$dest/$_im_rel" 2>/dev/null || true
  done
  _im_bad="$(_mode_mismatches "$src" "$dest")"
  if [ -n "$_im_bad" ]; then
    log_fail "$n: installed with modes its source does not have: $(printf '%s' "$_im_bad" | tr '\n' ';')"
    log_nofix "the chmod errors above; the pre-run copy is in $IL_BK"
    return 1
  fi

  log_ok "$n: installed, verified — bytes and modes"
  il_manifest_drop "$KIND/$n"; il_manifest "$KIND/$n"
  remove_old "$n"
}

# The dest root may be absent (commands/ was): creating it is part of installing, and a dry run must work without it
# and exit 1 only for what --apply would refuse. The creation sits below il_target's live gate.
if [ "$IL_APPLY" -eq 1 ]; then
  mkdir -p "$DEST_ROOT"
  log_head "apply to $DEST_ROOT"
elif [ "$KIND" = commands ] || [ -n "$NAME" ] || [ "$ALL" -eq 1 ]; then
  log_head "plan for $DEST_ROOT (dry run: nothing is written)"
fi

if [ "$KIND" = commands ]; then
  found=0
  for f in "$ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -n "$NAME" ] && [ "$NAME" != "${b%.md}" ] && [ "$NAME" != "$b" ] && continue
    found=1
    d="$DEST_ROOT/$b"
    if [ -f "$d" ] && cmp -s "$f" "$d"; then log_ok "${b%.md}: current"; il_manifest "$KIND/$b"; continue; fi
    if [ "$IL_APPLY" -eq 0 ]; then
      if [ -f "$d" ]; then log_note "${b%.md}: would update (drifted)"; else log_note "${b%.md}: would install (absent)"; fi
      continue
    fi
    il_backup "$d" || { BAD=1; continue; }
    if cp "$f" "$d.tmp.$$" && mv -f "$d.tmp.$$" "$d" && cmp -s "$f" "$d"; then
      WROTE=1; log_ok "${b%.md}: installed, verified byte-identical"; il_manifest "$KIND/$b"
    else
      rm -f "$d.tmp.$$"; BAD=1
      log_fail "${b%.md}: $d differs from commands/$b after the copy"
      log_nofix "the cp/mv error above; the pre-run copy is in $IL_BK"
    fi
  done
  if [ "$found" -eq 0 ]; then
    BAD=1
    log_fail "no tracked command named ${NAME:-<any>} in commands/"
    log_fix "sh $IL_SELF commands $(il_spell)"
  fi
elif [ "$ALL" -eq 1 ]; then
  for d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    ! _composed "$(basename "$d")" || continue
    install_one "$(basename "$d")" || BAD=1
  done
  # The composed book goes last: it lists what the loop above installed.
  if _composed "$COMPOSED" && src_for "$COMPOSED" >/dev/null; then install_one "$COMPOSED" || BAD=1; fi
  # A RETIRED skill's rows go too (472 rows stayed and reference-check printed "473 references do not resolve" every
  # session). A skill still tracked but missing on disk keeps its rows (REF-5's finding), as does a retired dir still on disk.
  if [ "$IL_APPLY" -eq 1 ] && [ -f "$IL_TARGET/.harbor-manifest" ]; then
    for _rn in $(awk -v k="$KIND/" '!/^#/ && NF >= 5 && $(NF-1) == "skills-install" {
        r = $0; sub(/^[^ ]+ [^ ]+ /, "", r); sub(/ [^ ]+ [^ ]+$/, "", r)
        if (index(r, k) == 1) { n = substr(r, length(k) + 1); sub(/\/.*/, "", n); if (n ~ /^[A-Za-z0-9._-]+$/) print n } }' \
        "$IL_TARGET/.harbor-manifest" | LC_ALL=C sort -u); do
      ! src_for "$_rn" >/dev/null || continue
      [ ! -e "$DEST_ROOT/$_rn" ] || continue
      il_manifest_drop "$KIND/$_rn"; log_note "$_rn: retired, and gone from $DEST_ROOT, so its manifest rows are dropped"
    done
  fi
elif [ -z "$NAME" ]; then
  list_all
else
  install_one "$NAME" || BAD=1
fi

# The rows this run recorded (install standard §3); il_manifest_write is a no-op on a dry run.
il_manifest_write || BAD=1
# An install changed what every future session loads; the B8 re-pin is the operator's, and deploy's own step.
if [ "$IL_APPLY" -eq 1 ] && [ "$WROTE" -eq 1 ] && [ "$IL_LIVE" -eq 1 ]; then
  il_next --deploy-does "sh $IL_TARGET/bin/pin-instructions.sh --apply --live"
fi
if [ "$IL_APPLY" -eq 0 ] && [ "$BAD" -eq 0 ] && { [ "$KIND" = commands ] || [ -n "$NAME" ] || [ "$ALL" -eq 1 ]; }; then
  # Every skill, on the live box, is deploy's --only skills (§4); one skill or the commands alone stay here.
  il_apply_next skills --all
fi
log_end; exit $?
