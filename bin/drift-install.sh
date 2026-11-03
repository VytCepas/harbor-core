#!/usr/bin/env sh
# drift-install.sh (harbor#431) — does the RUNNING floor still equal its source?
#
#   sh drift-install.sh [--dir <config-dir>] [--ref <git-ref>] [--quiet]
#
# Exit 0 = every installed bin/ file, and every file the runtime ships elsewhere (lib/), matches the
# ref, resolved through runtime-install's SUITE mapping (harbor#763). Exit 1 = at least one does not.
#
# WHY THIS IS NOT ALREADY COVERED: admission-integrity.sh (B6) pins the box to ITSELF, deploy-install-stamp.sh (#115) gates the
# WRITE, pin-instructions.sh (B8) pins instruction surfaces and not bin/, drift-renew-check.sh (#44) counts commits over each
# installer's declared payload, and lint X2/X2b walk the REPO's bin/ and compare each file to its live twin. All ENUMERATE FROM
# THE REPOSITORY, so a file that exists only on the box (once a GitHub-PAT holder in the live floor, in no commit) is out of
# their reach. This enumerates $DIR/bin and asks what is unaccounted for.
# WHY CONTENT AND NOT A COMMIT COUNT: a lag counter read 14 commits behind while all 48 installed files were byte-identical to
# the ref, because floor-install and runtime-install write overlapping sets; a check that cries wolf gets switched off (No.2.11).
# THE FOUR VERDICTS: the live bytes are hashed with `git hash-object` and looked up in the path's history.
#   current    blob == the blob at <ref>.
#   stale      blob == the blob at some ANCESTOR commit: an undeployed change; the commits since are reported.
#   modified   blob matches no commit of the path: a hand-edit, or a file the repo has not seen.
#   unsourced  the path does not exist at <ref>: a live floor file with no source of truth. Loudest of the four.
# `stale` and `modified` stay separate: a missed deploy and an unreviewed edit to a guard are different events, and only one is
# fixed by re-running the installer.
# Removed notes: docs/explanation/code-cases/bin-drift-install.md
set -u

STAMP='[check:install-drift]'
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REF="origin/main"
QUIET=0

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)" || REPO=""
[ -n "$REPO" ] || { printf 'install-drift: cannot locate the repo this script sits in, so it cannot load library-log.sh\n' >&2; exit 2; }
. "$REPO/bin/library-log.sh"
. "$REPO/bin/deploy-install-lib.sh"
log_init install-drift

# Exit 2 never comes without a FAIL line and its fix (harbor#457); the libs load before the arguments are read for that reason.
_die2() { # <what failed> <fix command | "none: <where>">
  log_fail "$1 $STAMP"
  case "${2-}" in 'none: '*) log_nofix "${2#none: }" ;; *) log_fix "${2-}" ;; esac
  log_end || :
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] && [ -n "$2" ] || _die2 "install-drift: --dir needs a config dir" "none: sh $0 --help"; DIR="$2"; shift ;;
    --ref) [ $# -ge 2 ] || _die2 "install-drift: --ref needs a git ref" "none: sh $0 --help"; REF="$2"; shift ;;
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) _die2 "install-drift: unknown flag: $1" "none: sh $0 --help" ;;
  esac
  shift
done

# How the fixes below are spelled (also the stale verdicts' fix at the end): the live box is HOME/.claude.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
_qn() { case "$1" in *[!A-Za-z0-9_./:=@%+,-]*|'') _q "$1" ;; *) printf '%s' "$1" ;; esac; }
LIVE="$HOME/.claude"
_target_spelling() { if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then printf '%s' --live; else printf '%s %s' --dir "$(_q "$(_phys "$DIR")")"; fi; }
_redeploy() { # the command that puts this repo's bytes back: deploy for the live box, the installers elsewhere
  if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then printf 'sh %s/bin/deploy.sh --apply --live' "$(_qn "$REPO")"
  else printf 'sh %s/bin/deploy-runtime-install.sh --apply %s && sh %s/bin/admission-install.sh --apply %s' \
         "$(_qn "$REPO")" "$(_target_spelling)" "$(_qn "$REPO")" "$(_target_spelling)"; fi
}

# No install to compare is named by its cause (harbor#457): no config dir or settings.json means no first-run step; a config dir
# without bin/ means no deploy (unless .harbor-manifest says one ran).
if [ ! -d "$DIR/bin" ]; then
  if { [ ! -d "$DIR" ] || [ ! -f "$DIR/settings.json" ]; } && ! il_installed "$DIR"; then
    if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then _fx="$(il_first_run_cmd "$REPO")"; _why=': the first-run step has not been taken'
    else _fx="none: the path given to --dir, which is not a config dir"; _why=''; fi
    [ -d "$DIR" ] && _w="no settings.json in $DIR" || _w="no config dir at $DIR"
    _die2 "$_w, so there is no install to compare$_why" "$_fx"
  fi
  if [ -f "$DIR/.harbor-manifest" ]; then _why='.harbor-manifest records an install, so bin/ was removed after the deploy'
  else _why='no deploy has run here'; fi
  _die2 "no bin/ in $DIR, so there is no install to compare: $_why" "$(_redeploy)"
fi

# A ref that does not resolve must ABORT, never classify every file `unsourced`.
git -C "$REPO" rev-parse --verify --quiet "$REF^{commit}" >/dev/null 2>&1 || \
  _die2 "ref does not resolve: $REF" "none: git -C $(_qn "$REPO") rev-parse --verify $(_qn "$REF") (the ref this check compares against)"

n_current=0; n_stale=0; n_modified=0; n_unsourced=0
findings=""
NL='
'
TAB='	'

# WHERE AN INSTALLED FILE COMES FROM (harbor#763): bin/<name> is bin/<name> in the repo, except what runtime-install's SUITE and
# DATA ship from elsewhere. The mapping is read from the installer AT THE REF, so the question is what that commit's
# installer would have put here; without it the suite read `unsourced` on every run.
SUITE_MAP="$(git -C "$REPO" show "$REF:bin/deploy-runtime-install.sh" 2>/dev/null \
  | sed -n -e 's/^SUITE="\(.*\)"/\1/p' -e 's/^DATA="\(.*\)"/\1/p' | tr ' ' '\n' \
  | awk -F: 'NF == 2 && $1 != "" && $2 != "" { print $2 "\t" $1 }')"
_src_of() { # <relpath under the config dir> -> the repo path it is installed from
  _so="$(printf '%s\n' "$SUITE_MAP" | awk -F'\t' -v r="$1" '$1 == r { print $2; exit }')"
  # The core share's registers install as bin/standards/naming/<name> from standards/naming/<name> (harbor#1436).
  case "$1" in bin/standards/naming/*.tsv) _so="standards/naming/${1#bin/standards/naming/}" ;; esac
  # A hook engine ships from its folder (D-88): bin/<name> is gone at that ref and hooks/<stem>/<name> is there.
  case "${_so:-$1}" in bin/*)
    git -C "$REPO" cat-file -e "$REF:$1" 2>/dev/null || ! git -C "$REPO" cat-file -e "$REF:$(il_engine_path "${1#bin/}")" 2>/dev/null \
      || _so="$(il_engine_path "${1#bin/}")" ;;
  esac
  printf '%s' "${_so:-$1}"
}

# THE SET: every file in bin/ (a file only the box has is the finding this exists for), plus what the install manifest and
# SUITE record elsewhere (lib/core.sh). The verdict never comes from the manifest: it is git's, below.
_set="$(find "$DIR/bin" -type f ! -name ".*" 2>/dev/null | sed "s#^$DIR/##" | LC_ALL=C sort
        il_mf_rows "$DIR" | awk -F'\t' '($3 == "runtime-install" || $3 == "floor-install") && $1 !~ /^bin\/[^\/]*$/ { print $1 }'
        printf '%s\n' "$SUITE_MAP" | awk -F'\t' '$1 != "" && $1 !~ /^bin\/[^\/]*$/ { print $1 }')"
_set="$(printf '%s\n' "$_set" | awk 'NF && !seen[$0]++')"
# A file a pack installed (.harbor-packs, written by pack.sh) is that pack's, and pack.sh refuses to write over a core file:
# so it is never `unsourced` here.
_pown="$(mktemp "${TMPDIR:-/tmp}/install-drift-own.XXXXXX")" || _die2 "cannot create a temp file in ${TMPDIR:-/tmp}" "none: the TMPDIR this check was given"
cat "$DIR"/.harbor-packs/*.tsv 2>/dev/null | awk -F'\t' '$1 == "F" { print $2 }' > "$_pown"
if [ -s "$_pown" ]; then
  _set="$(printf '%s\n' "$_set" | awk -v f="$_pown" 'BEGIN { while ((getline l < f) > 0) o[l] = 1 } !($0 in o)')"
fi
rm -f "$_pown"

# THE REGISTER IS INSTALLED COMPOSED (harbor#1149): bin/docs/reference/checks.md is core's register plus the private layer's rows
# and the installed packs' ($DIR/checks.d), so it is held to the composition AT THAT COMMIT, not the bare core blob.
_ckt="$(mktemp "${TMPDIR:-/tmp}/install-drift-checks.XXXXXX")" || _die2 "cannot create a temp file in ${TMPDIR:-/tmp}" "none: the TMPDIR this check was given"
trap 'rm -rf "$_ckt" "$_ckt.out" "$_ckt.rc" "$_ckt.rc.out" "$_ckt.reg"' EXIT
# The required-checks list is composed the same way (harbor#1149), and held to the composition AT THAT COMMIT.
_blob_of() { # <commit> <repo path> -> the blob this path is held to at that commit
  if [ "$2" = contracts/required-checks.tsv ] && git -C "$REPO" show "$1:$2" > "$_ckt.rc" 2>/dev/null \
     && sh "$REPO/bin/gate-required-generate.sh" --core "$_ckt.rc" > "$_ckt.rc.out" 2>/dev/null; then
    git -C "$REPO" hash-object "$_ckt.rc.out" 2>/dev/null && return 0
  fi
  # A core-share register is installed cut to the core share (standard-kit.sh --core-file), so it is held to that cut AT THAT COMMIT.
  case "$2:${_CUT:-0}" in standards/naming/*.tsv:1)
    if [ -f "$REPO/bin/standard-kit.sh" ] && mkdir -p "$_ckt.reg" && git -C "$REPO" show "$1:standards/naming/kit.tsv" > "$_ckt.reg/kit.tsv" 2>/dev/null \
       && git -C "$REPO" show "$1:$2" > "$_ckt.reg/${2##*/}" 2>/dev/null \
       && sh "$REPO/bin/standard-kit.sh" --root "$REPO" --registry "$_ckt.reg" --core-file "${2##*/}" > "$_ckt.out" 2>/dev/null; then
      git -C "$REPO" hash-object "$_ckt.out" 2>/dev/null && return 0
    fi ;;
  esac
  if [ "$2" = docs/reference/checks.md ] && git -C "$REPO" show "$1:docs/reference/checks.md" > "$_ckt" 2>/dev/null \
     && sh "$REPO/bin/check-registry-generate.sh" --core "$_ckt" --packs "$DIR/checks.d" > "$_ckt.out" 2>/dev/null; then
    git -C "$REPO" hash-object "$_ckt.out" 2>/dev/null && return 0
  fi
  git -C "$REPO" rev-parse --quiet --verify "$1:$2" 2>/dev/null
}
# An install made before the list was composed, or when the private layer held other rows, is BEHIND, not edited in place; only
# bytes no commit of either explains read modified.
RC_SRC=contracts/required-checks.tsv
_lrevs=""
[ ! -f "$REPO/bin/gate-required-generate.sh" ] || _lrevs="$(sh "$REPO/bin/gate-required-generate.sh" --layer-revs 2>/dev/null || :)"
_rc_older() { # <core commit> <installed blob> -> 0 when those bytes are that core, bare or with an older revision of the layer's file
  _ob="$(git -C "$REPO" rev-parse --quiet --verify "$1:$RC_SRC" 2>/dev/null)" || return 1
  [ "$_ob" != "$2" ] || return 0
  git -C "$REPO" show "$1:$RC_SRC" > "$_ckt.rc" 2>/dev/null || return 1
  for _lr in $_lrevs; do
    sh "$REPO/bin/gate-required-generate.sh" --core "$_ckt.rc" --private-rev "$_lr" > "$_ckt.rc.out" 2>/dev/null || continue
    [ "$(git -C "$REPO" hash-object "$_ckt.rc.out" 2>/dev/null)" != "$2" ] || return 0
  done
  return 1
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  live="$DIR/$rel"
  [ -f "$live" ] || continue
  # bin/ files keep the name they have always been reported by, nested ones too (W1 installs docs/reference/checks.md there).
  case "$rel" in bin/*) b="${rel#bin/}" ;; *) b="$rel" ;; esac
  src="$(_src_of "$rel")"
  _CUT=0; case "$rel" in bin/standards/naming/*.tsv) _CUT=1 ;; esac   # bin/controls.tsv is the same repo file installed UNCUT
  live_blob="$(git -C "$REPO" hash-object -- "$live" 2>/dev/null)" || continue

  ref_blob="$(_blob_of "$REF" "$src" || true)"

  if [ -z "$ref_blob" ]; then
    # Absent at the ref may still be a file the repo DELETED, a different story from one it never had: history is asked first.
    if git -C "$REPO" rev-list "$REF" -- "$src" 2>/dev/null | head -1 | grep -q .; then
      findings="${findings}unsourced$TAB$b${TAB}deleted from the repo, still installed$TAB$rel$TAB$src$NL"
    else
      findings="${findings}unsourced$TAB$b${TAB}in no commit of this repository$TAB$rel$TAB$src$NL"
    fi
    n_unsourced=$((n_unsourced + 1))
    continue
  fi

  if [ "$live_blob" = "$ref_blob" ]; then
    n_current=$((n_current + 1))
    continue
  fi

  # Differs from the ref: walk the path's history for these exact bytes (an engine moved into hooks/ also walks its old bin/ path, D-88).
  behind=0; matched=0; older=0
  case "$src" in hooks/*) was="$rel" ;; *) was="$src" ;; esac
  for c in $(git -C "$REPO" rev-list "$REF" -- "$src" "$was" 2>/dev/null); do
    hb="$(_blob_of "$c" "$src" || _blob_of "$c" "$was" || true)"
    [ -n "$hb" ] || continue
    if [ "$hb" = "$live_blob" ]; then matched=1; break; fi
    if [ "$src" = "$RC_SRC" ] && _rc_older "$c" "$live_blob"; then matched=1; older=1; break; fi
    behind=$((behind + 1))
  done

  if [ "$matched" = 1 ]; then
    why="installed copy is $behind commit(s) behind $REF"
    [ "$older" = 0 ] || why="installed list was composed before core or the private layer last changed ($behind core commit(s) behind $REF); a redeploy composes both as they are now"
    findings="${findings}stale$TAB$b${TAB}$why$TAB$rel$TAB$src$NL"
    n_stale=$((n_stale + 1))
  else
    findings="${findings}modified$TAB$b${TAB}bytes match no commit -- edited in place, or never committed$TAB$rel$TAB$src$NL"
    n_modified=$((n_modified + 1))
  fi
done <<SET
$_set
SET

bad=$((n_stale + n_modified + n_unsourced))
[ "$QUIET" = 1 ] && [ "$bad" -eq 0 ] && exit 0

# Every line the check emits names it (docs/reference/checks.md): the header, and a suffix on each result line.
log_head "$STAMP $DIR/bin vs $REF"
log_note "current=$n_current stale=$n_stale modified=$n_modified unsourced=$n_unsourced $STAMP"
[ "$n_current" -eq 0 ] || log_ok "$n_current installed file(s) match $REF $STAMP"
while IFS='	' read -r _v _b _why _rel _src; do
  [ -n "$_v" ] || continue
  log_fail "$_v $_b ($_why) $STAMP"
  case "$_v" in
    stale) log_fix "$(_redeploy)" ;;
    modified)
      if [ "$_src" = "$RC_SRC" ]; then
        log_nofix "bin/drift-install.sh (the list is core's rows plus the private layer's required-checks.tsv: diff $DIR/$_rel against the output of 'sh $REPO/bin/gate-required-generate.sh' and capture what only the box holds; a redeploy overwrites it)"
      else
        log_nofix "bin/drift-install.sh (diff $REPO/$_src $DIR/$_rel and capture what exists only on the box; a redeploy overwrites it)"
      fi ;;
    *) log_nofix "bin/drift-install.sh (nothing in $REPO reproduces $DIR/$_rel: commit it, or move it out of ${_rel%/*}/)" ;;
  esac
done <<ROWS
$findings
ROWS
log_end; exit $?
