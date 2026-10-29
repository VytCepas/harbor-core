#!/usr/bin/env sh
# skills-install.sh (harbor#7 · I1) — install a tracked skill into ~/.claude/skills.
#   harbor skills [--apply] (--live | --dir PATH) [--accept-loss] [commands] [<name> | --all] [--from-old OLD]
#     no name, no --all   list the tracked skills and their install state
#     <name> | --all      install or update one, or every tracked skill (a dry run unless --apply)
#     commands            the slash commands in commands/ instead of skills
#     --from-old OLD      a rename: the old dir moves into the backup
#     --accept-loss       install over a newer live copy, or one holding files the repo does not
#   A dry run exits 1 exactly when --apply would refuse (nested, newer, box-only files).
#   skill-catalog is the one skill that is COMPOSED, not copied (harbor#1149): see COMPOSED below.
#
# WHY THIS EXISTS. Until now the documented mechanism was a hand-typed
# `cp -R skills/<name>/. ~/.claude/skills/<name>/`, and skills/README.md records
# the measured failure: omit the trailing `/.` and cp -R into an existing
# destination silently produces ~/.claude/skills/<name>/<name>/ and leaves the
# ORIGINAL files serving. Nothing errors. That trap sat in front of 25 pending
# directory renames, which is why a verb had to exist before the surgery.
#
# THREE THINGS IT DOES THAT THE cp DOES NOT:
#   1. Verifies byte-identity AFTER writing, with diff -r (generated caches
#      excluded), and fails if not.
#   2. Refuses to leave a nested <name>/<name>/ behind, and detects a pre-existing
#      one from an earlier hand-typed install.
#   3. Handles the rename case, which a copy cannot: installing kebab `red-team`
#      while PascalCase `RedTeam` is still present leaves BOTH in the listing,
#      and the model sees two skills where the repo has one.
#
# DRY RUN IS THE DEFAULT, deliberately. This writes into ~/.claude/skills, an
# instruction surface the B8 pin watches; every write here makes the operator
# re-pin. A verb that mutates that surface on a typo is worse than the cp it
# replaces.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$HERE/.." && pwd)"
. "$HERE/log-lib.sh"
. "$HERE/fs-lib.sh"
. "$HERE/install-lib.sh"
log_init skills-install

# ── TWO PAYLOAD KINDS, ONE GATE (harbor#7) ──────────────────────────────────
# Slash commands are flat .md FILES; skills are DIRECTORIES. The nesting refusal
# and `--from-old` are directory-shaped and do not transfer — but the part that
# actually protects the operator does: dry-run by default, verify after writing,
# and refuse the live instruction surface without an explicit --live. That gate
# is the reason this file exists, and a second installer would be a second copy
# of it, drifting in the direction nobody notices until it matters.
KIND=skills; ALL=0; NAME=''; FROM_OLD=''
il_opt() {
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

# THE SKILL BOOK IS COMPOSED, NOT COPIED (harbor#1149). The installed book lists every skill installed in the config dir and
# the CLIs on the box, so it differs from the tracked copy by design. Copying the tracked one over it drops every row the repo
# does not ship (the box's skills, the packs', the CLI table) until the next deploy, and a byte comparison calls the composed
# one DRIFTED for ever. bin/skill-catalog.sh install is its one writer and its one judge (`install --check`), so this installer
# asks it, and --all installs the book LAST because it lists what the run installed. Without the generator beside this script
# (a copy of the tree that lacks it) the book is an ordinary payload.
COMPOSED=skill-catalog
_composed() { [ "$KIND" = skills ] && [ "$1" = "$COMPOSED" ] && [ -f "$ROOT/bin/skill-catalog.sh" ]; }

# The one install command for ONE name, whatever this run selected: a fix names the skill it fixes.
_cmd_for() { # <name>
  printf 'sh %s --apply%s %s %s' "$IL_SELF" "$([ "$KIND" = commands ] && printf ' commands')" "$1" "$(il_spell)"
}

# ── THE EXEC BIT IS PART OF THE PAYLOAD, AND diff -r CANNOT SEE IT ──────────
# Measured 2026-09-05 installing `measurement-audit`: the tracked
# check-event-volumes.sh is 755, the live copy had been 644 since it was
# hand-created, and `cp -R` into an EXISTING file keeps the DESTINATION's mode —
# so the copy landed 644 while install_one printed "verified byte-identical" and
# state_of went on reporting `current`. `./check-event-volumes.sh` then exits
# 126. A checker that cannot be run, behind a green install and a green listing:
# the same shape as every other defect this workstream is about, one layer down.
#
# Only the skills path needs this. Slash commands are flat .md files that nothing
# executes, so the commands path below is deliberately left comparing bytes.
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

# Generated caches are not payload: a box-only __pycache__ made every re-install
# of its skill fail the byte check below, after writing (found by the #702 deploy).
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
# A CASE-ONLY RENAME IS THE SAME DIRECTORY, and this box's volume is
# case-INSENSITIVE (macOS default). `Telos` and `telos` are two strings and one
# directory, so the string guard below passes, `install_one` writes into the
# directory it is about to delete, and the skill is destroyed — after printing
# that it installed successfully (harbor#239).
#
# The suite did not catch it because case 6 asserted only that the OLD name was
# gone. On a case-insensitive volume that assertion is satisfied BY the
# destruction: the test passed because the skill had been deleted. The missing
# half — does the installed skill still exist — is now asserted too.
#
# Every rename this verb actually performs is PascalCase -> kebab-case, so the
# untested shape was also the only shape that occurs in practice.
remove_old() {
  [ -n "$FROM_OLD" ] || return 0
  [ "$FROM_OLD" != "$1" ] || return 0
  [ -d "$DEST_ROOT/$FROM_OLD" ] || return 0

  # A SYMLINK IS NOT THE SAME DIRECTORY WEARING ANOTHER NAME, even when it
  # points at one. `[ -d ]` above follows it, and the probe below is visible
  # through both paths, so the case-only branch would claim it — and then the
  # two-step `mv` moves the LINK into the destination DIRECTORY, leaving
  # `<name>.rename-tmp.<pid>` inside the installed skill while reporting
  # success (PR #241 review, P2). There is no rename to perform: the link goes
  # into the backup. Refusing to follow a link here also matches how the marker
  # walk treats one — a link is writable from outside the thing being governed.
  if [ -L "$DEST_ROOT/$FROM_OLD" ]; then
    _aside "$DEST_ROOT/$FROM_OLD" || return 1
    il_manifest_drop "$KIND/$FROM_OLD"
    log_ok "$FROM_OLD: removed (a symlink; renamed to $1), kept in $IL_BK"
    return 0
  fi

  # ASK THE FILESYSTEM, do not compare strings — and not `pwd -P` either, which
  # returns the spelling you typed rather than the one on disk, so both names
  # still compare unequal (measured; the first cut of this fix did exactly that
  # and changed nothing). Dropping a marker in one name and looking for it under
  # the other is the only check that cannot be fooled, and it needs no `stat`
  # flavour test — BSD and GNU disagree on the flags for inode/device.
  _same=0
  _probe=".harbor-same-dir-probe.$$"
  if : > "$DEST_ROOT/$FROM_OLD/$_probe" 2>/dev/null; then
    [ -e "$DEST_ROOT/$1/$_probe" ] && _same=1
    rm -f "$DEST_ROOT/$FROM_OLD/$_probe"
  fi

  if [ "$_same" -eq 1 ]; then
    # Same directory: the content is already correct (install_one wrote it), so
    # only the SPELLING is wrong. Two-step through a temporary name — a direct
    # `mv Alpha alpha` is a no-op or an error on a case-insensitive volume
    # depending on the filesystem, and neither is a rename.
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
    # THE RENAME CLEANUP MUST NOT SIT BEHIND THIS EARLY RETURN. It did, and
    # tests/install/skills-install-test.sh (then bin/) case 6 caught it on the suite's first run: when the
    # new kebab name is ALREADY current, the function returned before removing the
    # old PascalCase directory, so both stayed in the listing and the model saw two
    # skills where the repo has one. That is precisely the failure --from-old
    # exists to prevent, and it was silent — the run printed "already current".
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

  # ── I3 · ASK BEFORE WRITING, NOT AFTER (harbor#117) ───────────────────────
  # Everything below this line verifies the copy LANDED. Nothing above it asked
  # whether the copy was SAFE — and the answer lives in the bytes the cp is about
  # to destroy. skills-collide.sh refuses only when a live file's bytes are in no
  # commit and no install record (harbor#476, #641): work the repo has never seen.
  # An ordinary update leaves the live copy an older commit, so this stays silent
  # for it. The dry run asks too, so a refusal shows before anything is written.
  _refused=0; _replace=0; _collided=0
  if [ "$st" = DRIFTED ] && [ -x "$ROOT/bin/skills-collide.sh" ] && [ "$KIND" = skills ]; then
    if ! _co="$(CLAUDE_CONFIG_DIR="$IL_TARGET" sh "$ROOT/bin/skills-collide.sh" "$n" 2>&1)"; then
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

  # Carry the source's modes over — `cp -R` did not, for any file that already
  # existed at the destination — and then CHECK, because a repair that is not
  # verified is the same promise the byte check above refused to take on trust.
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

# The dest root may not exist at all — commands/ was absent on this box until this work created it,
# which is the whole reason slash commands were unused here. Creating it is part of installing, not
# a precondition, for skills/ too: a dry run must work when it is absent (the single most likely first
# use), and a dry run exits 1 only for what --apply would refuse, which an absent dir is not.
# The creation sits below il_target's live gate, so a refused run leaves no directory behind.
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
  # A RETIRED skill's rows go too: tracked here no longer, and gone from disk. 472 rows of skills retired on 2026-10-26
  # stayed, and reference-check printed "473 references do not resolve" at every session start. A skill still tracked
  # but missing on disk keeps its rows (REF-5's real finding), and so does a retired dir still on disk (box-only).
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
